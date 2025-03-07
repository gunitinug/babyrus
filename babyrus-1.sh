#!/bin/bash

BABYRUS_VERSION='v.0.3'
BABYRUS_AUTHOR='Logan Lee'

# CHECK MINIMUM BASH VERSION A.B.C
check_bash_ver() {
    # Minimum bash version A.B.C
    local A B C bash_ver
    A=5
    B=2
    C=21

    IFS=. read -ra bash_ver <<< "$(bash --version | grep -Po '(?<=GNU bash, version )[0-9.]+')"

    i=0
    err_msg="Bash version at least $A.$B.$C required!"

    while [ $i -lt 3 ]; do
        part=${bash_ver[i]}

        if [[ $i -eq 0 && $part -ge $A ]] || [[ $i -eq 1 && $part -ge $B ]] || [[ $i -eq 2 && $part -ge $C ]]; then
            # Continue only if the condition is met for each part
            ((i++))
        else
            # Print error message and exit if bash is too old.
            echo "$err_msg" >&2
            exit 1
        fi
    done
}
check_bash_ver

# Check dependencies
if ! command -v whiptail &> /dev/null || ! command -v wmctrl &> /dev/null; then
    echo "Error: Both whiptail and wmctrl are required, but at least one is not installed." >&2
    exit 1
fi

# Try to maximize the current terminal window
if ! wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz &> /dev/null; then
    echo "If menu is broken please manually maximise terminal window before running this program." >&2
fi

# Allow a brief pause for the window manager to update the window size
sleep 0.5

# Database files
EBOOKS_DB="ebooks.db"  # Format: "path|tag1,tag2,..."
TAGS_DB="tags.db"      # Format: "tag"

# Ensure databases exist
touch "$EBOOKS_DB" "$TAGS_DB"

# Tweak this to set external apps.
declare -A EXTENSION_COMMANDS=(
    ["txt"]="gnome-text-editor"
    ["pdf"]="evince"
    ["epub"]="okular"
    ["mobi"]="xdg-open"
    ["azw3"]="xdg-open"
)

# Function to display the "In operation..." infobox
in_operation_msg() {
    TERM=ansi whiptail --infobox "In operation..." 8 40 >/dev/tty
}

list_files() {
    local path="$1"
    local mode="$2"

    local entries=(".." "up")
    for entry in "$path"/{*,.*}; do
        # Skip if the entry is "." or ".."
        [[ "$(basename "$entry")" == "." || "$(basename "$entry")" == ".." ]] && continue

        # normalise path
        entry="$(echo -n "$entry" | tr -s '/')"

        if [[ -d "$entry" && "$mode" == "D" ]]; then
            entries+=("$entry" " ")
        elif [[ -f "$entry" && "$mode" == "F" ]]; then
            entries+=("$entry" "$(basename "$entry")")
        fi
    done

   printf "%s\x1E" "${entries[@]}"
}

# debug
#echo list_files: >&2 
#list_files "$(pwd)" "D" | cat -v >&2

navigate() {
    local current_path="$1"

    while true; do
        in_operation_msg # show 'in operation...' when directory changes

	mapfile -t -d $'\x1E' choices < <(printf ":::SELECT:::\x1Eselect\x1E"; list_files "$current_path" "D" | sed 's/\x1E$//')

	# debug - switched off because too vebose.
	#echo choices: >&2
	#declare -p choices >&2

        selected=$(whiptail --title "File Browser" \
                            --menu "Current Directory: $current_path\nSelect a folder to search files." 20 170 10 \
                            "${choices[@]}" 3>&1 1>&2 2>&3)

        # Check if user cancelled
        if [ $? -ne 0 ]; then
            break
        fi

        # If .. then move up a level in the tree
	[[ "$selected" == ".." ]] && selected_path="$(dirname "$current_path")" || selected_path="$selected"

	# debug
	#echo selected_path: "$selected_path" >&2

	# Choose this item and quit
	[[ "$selected"  == ":::SELECT:::" ]] && echo "$current_path" && break 

        if [ -d "$selected_path" ]; then
            # If directory, navigate into it
            current_path="$selected_path"
        fi
    done
}

# debug
#navigate "$(pwd)"

split_second_print() {
	local array=("$@")
	local counter=0

	# Loop over each element in the array
	for element in "${array[@]}"; do
	    # Increment the counter
	    ((counter++))
	    
	    # Print the element followed by \x1e character
	    printf "%s\x1E" "$element"
	    
	    # After every second element, print \x1f character
	    if (( counter % 2 == 0 )); then
	        printf "\x1F"
	    fi
	done
}

# debug
#split_arr_test=("apple" "banana" "cherry" "date" "elderberry" "fig")
#split_second_print "${split_arr_test[@]}" | cat -v >&2

# truncate logic for filenames (ie. basename)
# the logic is:
# "a very long truncated file.pdf" becomes "a very long truncated....pdf"
# preserves the file extension.
truncate_filename() {
    local filename="$1"
    local max_length="${2:-85}" # defaults to 85

    # Extract filename and extension
    local name="${filename%.*}"
    local ext="${filename##*.}"

    # If there's no extension, treat whole as name
    [[ "$filename" == "$ext" ]] && ext=""

    # Calculate max length for the name part (allow space for dots and extension)
    local trunc_length=$(( max_length - ${#ext} - 4 ))  # 4 accounts for "...."

    # If filename is within limit, return as-is
    if [[ ${#filename} -le $max_length ]]; then
        echo "$filename"
        return
    fi

    # Truncate the name and append "...." + extension
    local truncated_name="${name:0:trunc_length}"
    echo "${truncated_name}....${ext}"
}

# truncation logic for dirname
# like this:
# "/this/is/a/very/long/path" to "/this/is/a/.../long/path"
truncate_dirname() {
    local dir="$1"
    local max_length="${2:-50}" # defaults to 50

    if [[ ${#dir} -le $max_length ]]; then
        echo "$dir"
    else
        local keep_length=$(( max_length - 5 ))  # Space left after "/.../"
        local start_length=$(( keep_length / 2 ))  # Half for start
        local end_length=$(( keep_length - start_length ))  # Remaining for end

        local start="${dir:0:start_length}"
        local end="${dir: -end_length}"

        echo "${start}/.../${end}"
    fi
}

truncate_tags() {
    local input="$1"
    # Split input into tags, trimming whitespace for each tag
    local tags=()
    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do

        # Trim leading and trailing whitespace
        part="$(echo "$part" | awk '{sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print}')"

        [[ -n "$part" ]] && tags+=("$part")
    done

    # Handle empty input
    (( ${#tags[@]} == 0 )) && { echo ""; return; }

    # Check if already within limit
    local joined=$(IFS=','; echo "${tags[*]}")
    if (( ${#joined} <= 65 )); then
        echo "$joined"
        return
    fi

    local last_tag="${tags[-1]}"
    local n=${#tags[@]}
    local max_k=-1

    # Find maximum number of leading tags we can keep
    for ((k=0; k <= n-2; k++)); do
        local sum=0
        for ((i=0; i<k; i++)); do
            ((sum += ${#tags[i]}))
        done
        # Calculate total length: sum + 3 (...) + last_tag + commas (k+1)
        local total=$(( sum + ${#last_tag} + k + 1 + 3 ))
        (( total <= 65 )) && max_k=$k || break
    done

    # Build truncated result if possible
    if (( max_k >= 0 )); then
        local truncated=("${tags[@]:0:max_k}" "..." "$last_tag")
        local result=$(IFS=','; echo "${truncated[*]}")
        echo "$result"
        return
    fi

    # Fallback: truncate last tag if needed
    local max_last_len=$(( 65 - 4 ))  # Reserve space for "...","
    echo "...,${last_tag:0:$max_last_len}"
}

generate_trunc() {
	counter=1

	while IFS= read -r -d $'\x1f' group; do
	    # Skip empty groups (e.g., from trailing separator)
	    [[ -z "$group" ]] && continue
	    
	    # Split group into fields using \x1E as delimiter
	    IFS=$'\x1e' read -r fullpath filename _ <<< "$group"

	    # truncated fullpath will just be dirname without file name.
	    fullpath="$(dirname "$fullpath")"

	    # truncate long fullpath	    
	    truncated_path="[$(truncate_dirname "$fullpath")]"

	    # truncate long file name
	    truncated_filename="$(truncate_filename "$filename")"

            printf "%s:%s\x1E%s\x1E" "$counter" "$truncated_path" "$truncated_filename"
            ((counter++))
	done < <(split_second_print "$@")
}

generate_trunc_delete_ebook() {
	local counter=1
	local path tags dir file
	local truncated_dir truncated_file truncated_tags

        while IFS= read -r -d $'\x1f' group; do
            # Skip empty groups (e.g., from trailing separator)
            [[ -z "$group" ]] && continue

            # Split group into fields using \x1E as delimiter
            IFS=$'\x1e' read -r path tags _ <<< "$group"

	    dir="$(dirname "$path")"
	    file="$(basename "$path")"

	    # Truncate
	    truncated_dir="$(truncate_dirname "$dir" 35)"
	    truncated_file="$(truncate_filename "$file" 65)"

	    # Truncate tags too!
	    truncated_tags="$(truncate_tags "$tags")"

            printf "%s:%s\x1E%s\x1E" "$counter" "${truncated_dir}/${truncated_file}" "${truncated_tags}"
            ((counter++))
        done < <(split_second_print "$@")
}

generate_trunc_assoc_tag() {
        local counter=1
        local path space dir file
        local truncated_dir truncated_file

        while IFS= read -r -d $'\x1f' group; do
            # Skip empty groups (e.g., from trailing separator)
            [[ -z "$group" ]] && continue

            # Split group into fields using \x1E as delimiter
            IFS=$'\x1e' read -r path space _ <<< "$group"

            dir="$(dirname "$path")"
            file="$(basename "$path")"

            # Truncate
            truncated_dir="$(truncate_dirname "$dir" 35)"
            truncated_file="$(truncate_filename "$file" 65)"

            printf "%s:%s\x1E%s\x1E" "$counter" "${truncated_dir}/${truncated_file}" " "
            ((counter++))
        done < <(split_second_print "$@")
}

generate_trunc_dissoc_tag() {
        local counter=1
        local path tags dir file
        local truncated_dir truncated_file truncated_tags

        while IFS= read -r -d $'\x1f' group; do
            # Skip empty groups (e.g., from trailing separator)
            [[ -z "$group" ]] && continue

            # Split group into fields using \x1E as delimiter
            IFS=$'\x1e' read -r path tags _ <<< "$group"

            dir="$(dirname "$path")"
            file="$(basename "$path")"

            # Truncate
            truncated_dir="$(truncate_dirname "$dir" 35)"
            truncated_file="$(truncate_filename "$file" 65)"

	    # Truncate tags too!
	    truncated_tags="$(truncate_tags "$tags")"

            printf "%s:%s\x1E%s\x1E" "$counter" "${truncated_dir}/${truncated_file}" "$truncated_tags"
            ((counter++))
        done < <(split_second_print "$@")
}

generate_trunc_lookup() {
        local idx the_rest path tags dir file
        local truncated_dir truncated_file truncated_tags

        while IFS= read -r -d $'\x1f' group; do
            # Skip empty groups (e.g., from trailing separator)
            [[ -z "$group" ]] && continue

            # Split group into fields using \x1E as delimiter
            IFS=$'\x1e' read -r idx the_rest _ <<< "$group"

            # the_rest format: /path/to/file/some book.pdf|tag1,another tag
            path=${the_rest%|*}
            tags=${the_rest##*|}

            dir="$(dirname "$path")"
            file="$(basename "$path")"

            # Truncate
            truncated_dir="$(truncate_dirname "$dir" 35)"
            truncated_file="$(truncate_filename "$file" 65)"

            # Truncate tags too!
            truncated_tags="$(truncate_tags "$tags")"

            printf "%s\x1E%s\x1E" "$idx" "${truncated_dir}/${truncated_file} T:${truncated_tags}"
        done < <(split_second_print "$@")
}

# debug
#a="$(printf 'a%.0s' {1..55})"
#b="$(printf 'b%.0s' {1..55})"
#c='ccc'
#test_arr=("$a" 'a' "$b" 'b' "$c" 'c')
#echo generate_trunc: >&2
#generate_trunc "${test_arr[@]}" | cat -v >&2

# Global variables to hold the list and current page
TRUNC=()         # will hold the list items
CURRENT_PAGE=0   # persists page state across paginate() calls

paginate() {
    # Clear any previous selection
    SELECTED_ITEM=""

    local chunk_size=200

    # If new items are passed in, update TRUNC and reset CURRENT_PAGE.
    if [ "$#" -gt 0 ]; then
        TRUNC=("$@")
        CURRENT_PAGE=0
    fi

    local total_pages=$(( ( ${#TRUNC[@]} + chunk_size - 1 ) / chunk_size ))
    # Ensure CURRENT_PAGE is within valid bounds
    if (( CURRENT_PAGE >= total_pages )); then
        CURRENT_PAGE=$(( total_pages - 1 ))
    fi

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        # Extract the current chunk from the global TRUNC
        local current_chunk=("${TRUNC[@]:$start:$chunk_size}")
        local menu_options=()

        # Add navigation options if needed
        if (( CURRENT_PAGE > 0 )); then
            menu_options+=("previous page" " ")
        fi
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("next page" " ")
        fi

        # Append the current page items
        menu_options+=("${current_chunk[@]}")

        choice=$(whiptail --title "Paged Menu" --cancel-button "Back" \
            --menu "Choose an item (Page $((CURRENT_PAGE + 1))/$total_pages)" \
            20 170 10 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3)

        # Exit if user cancels
        if [ $? -ne 0 ]; then
            break
        fi

        case "$choice" in
            "previous page")
                (( CURRENT_PAGE-- ))
                ;;
            "next page")
                (( CURRENT_PAGE++ ))
                ;;
            *)
                # Return the selected item (page state remains for next call)
                SELECTED_ITEM="$choice"
                return 0
                ;;
        esac
    done

    return 1
}

# Example usage:
# result=$(paginate "Item 1" "Item 2" "Item 3" "Item 4" "Item 5")
# echo "Selected: $result"

# Store every logic for detecting illegal file names here.
check_illegal_filenames() {
    local input="$1"
    local illegal_files=()
    # Split the input into an array using the ASCII record separator (0x1E)
    IFS=$'\x1e' read -ra parts <<< "$input"
    # Iterate over basenames (every second element starting from index 1)
    for ((i=1; i < ${#parts[@]}; i += 2)); do
        local basename="${parts[i]}"

        # Illegal file name logic here.
        if [[ "$basename" == -* || "$basename" == *"|"* ]]; then
            illegal_files+=("$basename")
        fi
    done
    # Output results and return appropriate exit code
    if [[ ${#illegal_files[@]} -gt 0 ]]; then
        # Build the message
        msg="Error: Illegal filenames found:\n"
        for file in "${illegal_files[@]}"; do
            msg+="  ${file}\n"
        done
        msg+="\nConsider renaming the files and retry.\n"
        
        # Display the message using whiptail
        whiptail --title "Error" --msgbox "$(printf '%b' "$msg")" 15 60
        return 1
    else
        return 0
    fi
}

register_ebook() {
    # Get search string for files
    search=$(whiptail --inputbox "Enter search string to look for ebook files (empty for wildcard):" 8 40 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    # Get search path by navigating
    search_path="$(navigate "$(pwd)")"

    # if navigate is canceled so no search_path is set
    [ -z "$search_path" ] && return

    # List and filter files
    # If search_path is unset or empty, default to $(pwd). If search is unset or empty, search all files (ie. *).
    search_path=${search_path:-"$(pwd)"}
    search=${search:-"*"}
    # debug
    #echo "search: " "$search" >&2
    #echo "search_path: " "$search_path" >&2

    # in operation... message
    in_operation_msg

    run_find="$(find "$search_path" -type f -iname "*$search*" -exec sh -c 'printf "%s\036%s\036" "$1" "$(basename "$1")"' sh {} \;)"
    run_find="${run_find%$'\x1E'}"      # Remove any trailing delimiter.

    # Detect illegal file names.
    # If detected, return from this function.
    check_illegal_filenames "$run_find" || return

    # Check if run_find is empty so we can cancel.
    if [ -z "$run_find" ]; then
        whiptail --title "No Matches Found" --msgbox "Find found no matches" 8 45
        return 1  # Exit the function.
    fi

    IFS=$'\x1E' read -r -a filtered <<< "$run_find"

    # debug
    #echo "filtered: " "${filtered[*]}" >&2
    #echo "filtered length: " "${#filtered[*]}" >&2

    # shortened filtered output with line numbers:
    # shorten the dirname if its length is greater than 50.
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc "${filtered[@]}" | sed 's/\x1E$//')
    CURRENT_PAGE=0

    # debug
    #echo "trunc: " "${trunc[@]}" >&2
    #echo "trunc length: " "${#trunc[*]}" >&2

    paginate
    selected_trunc="$SELECTED_ITEM"
    #selected_trunc="$(paginate "${trunc[@]}")"
    # debug
    #echo selected_trunc: >&2
    #echo "$selected_trunc" >&2
    #exit

    # If cancelled by user
    if [ -z "$selected_trunc" ]; then
        whiptail --title "Register ebook canceled" --msgbox "Canceled by user." 8 45
        return 1  # Exit the function.
    fi

    # Select file (OLD just for ref)
    #selected_trunc=$(whiptail --title "Select Ebook" --menu "Choose file:" 20 170 10 "${trunc[@]}" 3>&1 1>&2 2>&3)

    # If selecting ebook is cancelled (OLD just for ref)
    #[ $? -ne 0 ] && return

    local n="$(echo "$selected_trunc" | cut -d':' -f1)"
    local m=$((2 * n - 1))

    # debug
    #echo "selected_trunc: " "$selected_trunc" >&2
    #echo "n: " "$n" >&2
    #echo "m: " "$m" >&2

    # Remember we want filtered[m-1].
    selected="${filtered[$((m - 1))]}"

    #debug
    #echo "selected: " "$selected" >&2

    # Check if ebook already exists
    if grep -q "^${selected}|" "$EBOOKS_DB"; then
        whiptail --msgbox "Ebook already registered!" 8 40
        return
    fi

    # Add to database (with empty tags)
    echo "$selected|" >> "$EBOOKS_DB"
    whiptail --msgbox "Registered: $selected" 20 80
}

# debug
#register_ebook
#exit

# Need to register a tag in order to associate to ebook.
register_tag() {
    while true; do
        tag=$(whiptail --inputbox "Enter new tag name (no commas):" 8 40 3>&1 1>&2 2>&3)
        if [[ $? -ne 0 ]]; then return; fi

        if [[ -z "$tag" ]]; then
            whiptail --msgbox "Tag name cannot be empty!" 8 40
            continue
        fi
        
        if [[ "$tag" == *","* ]]; then
            whiptail --msgbox "Tag name cannot contain commas!" 8 40
            continue
        fi
        
	# try to match each line exactly.
        if grep -Fxqi "$tag" "$TAGS_DB"; then
            whiptail --msgbox "Tag already exists!" 8 40
        else
            echo "$tag" >> "$TAGS_DB"
            whiptail --msgbox "Tag '$tag' registered!" 8 40
            return
        fi
    done
}

# pairs for whiptail's menu items.
make_into_pairs() {
    local arg
    local pairs=()
    # Build pairs like "arg\x1Eitem"
    for arg in "$@"; do
        pairs+=("${arg}"$'\x1E'" ")
    done
    # Join all pairs with \x1E between them
    (IFS=$'\x1E'; echo "${pairs[*]}")
}

# Filter to narrow down search.
filter_ebooks() {
    local filter_str="$1"
    shift
    local my_array=("$@")

    # Escape special glob characters and convert to lowercase
    local filter_str_escaped=$(sed 's/[][*?]/\\&/g' <<< "${filter_str,,}")

    # Case-insensitive literal substring match.
    for element in "${my_array[@]}"; do
        if [[ "$filter_str" == "*" || "${element,,}" == *"${filter_str_escaped}"* ]]; then
            printf "%s\0" "$element"
        fi
    done
}

# Filter to narrow down search when dissociating tag.
filter_menu_items() {
    local filter_str="$1"
    shift
    local my_array=("$@")

    # Escape special glob characters and convert to lowercase
    local filter_str_escaped=$(sed 's/[][*?]/\\&/g' <<< "${filter_str,,}")

    # Iterate over the array in steps of two to process path-tag pairs
    for ((i=0; i < ${#my_array[@]}; i+=2)); do
        # Ensure there is a corresponding tag to avoid errors on odd array lengths
        if (( i+1 >= ${#my_array[@]} )); then
            continue
        fi
        local path="${my_array[i]}"
        local tag="${my_array[i+1]}"

        # Check if the path matches the filter (case-insensitive substring match)
        if [[ "$filter_str" == "*" || "${path,,}" == *"${filter_str_escaped}"* ]]; then
            # Output both path and tag as null-delimited strings
            printf "%s\0" "$path"
            printf "%s\0" "$tag"
        fi
    done
}

associate_tag() {
    # Get list of ebooks
    mapfile -t ebooks < <(cut -d'|' -f1 "$EBOOKS_DB")
    if [[ ${#ebooks[@]} -eq 0 ]]; then
        whiptail --msgbox "No ebooks registered!" 8 40
        return
    fi

    # Get filter string from user using whiptail. No globbing, simple substring match.
    filter_str=$(whiptail --title "Filter eBooks" --inputbox "Enter filter string to narrow search (literal substring search; empty for wildcard):" 10 40 3>&1 1>&2 2>&3)
    
    # Handle cancel/escape
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Defaults to "*" if unset
    filter_str=${filter_str:-"*"}
    
    # Filter ebooks and store in array
    mapfile -d $'\0' filtered_ebooks < <(filter_ebooks "$filter_str" "${ebooks[@]}")

    # convert ebooks array into whiptail friendly format.
    mapfile -d $'\x1e' -t ebooks_whip < <(make_into_pairs "${filtered_ebooks[@]}")

    # Truncate ebooks_whip because of possible long file names.
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_assoc_tag "${ebooks_whip[@]}" | sed 's/\x1E$//')
    CURRENT_PAGE=0

    # Select ebook
    # paginate here because trunc may be large.
    paginate
    if [[ $? -ne 0 ]]; then return; fi
    ebook_trunc="$SELECTED_ITEM"
    #ebook_trunc="$(paginate "${trunc[@]}")"

    local n="$(echo "$ebook_trunc" | cut -d':' -f1)"
    local m=$((2 * n - 1))

    # debug
    #echo "ebook_trunc: " "$ebook_trunc" >&2
    #echo "n: " "$n" >&2
    #echo "m: " "$m" >&2

    # Remember we want ebooks_whip[m-1].
    ebook="${ebooks_whip[$((m - 1))]}"

    # Get existing tags for the ebook
    existing_tags="$(awk -F'|' -v ebook="$ebook" '$1 == ebook {print $2}' "$EBOOKS_DB")"
    
    # Get list of all tags
    mapfile -t tags < <(cat "$TAGS_DB")
    if [[ ${#tags[@]} -eq 0 ]]; then
        whiptail --msgbox "No tags registered!" 8 40
        return
    fi
    
    # convert tags array into whiptail friendly format.
    mapfile -d $'\x1e' -t tags_whip < <(make_into_pairs "${tags[@]}")

    # Select tag
    tag=$(whiptail --menu "Choose a tag:" 20 170 10 \
        "${tags_whip[@]}" 3>&1 1>&2 2>&3)					# again here menu items must come in pairs!
    if [[ $? -ne 0 ]]; then return; fi

    # Escape special regex characters in $tag
    escaped_tag=$(sed 's/[.[\*^$(){}+?|]/\\&/g' <<< "$tag")
    
    # Check if tag already exists as a standalone tag
    if [[ "$existing_tags" =~ (^|,)${escaped_tag}(,|$) ]]; then
        whiptail --msgbox "Ebook already has this tag!" 8 40
        return
    fi
    
    # Update ebook entry
    tmpfile=$(mktemp)
    awk -v ebook="$ebook" -v tag="$tag" '
        BEGIN {FS=OFS="|"} 
        $1 == ebook {
            if ($2 == "") $2 = tag
            else $2 = $2 "," tag
        }
        {print}
    ' "$EBOOKS_DB" > "$tmpfile" && mv "$tmpfile" "$EBOOKS_DB"
    
    whiptail --msgbox "Tag '$tag' added to '$ebook'!" 20 80
}

generate_ebooks_list() {
    local counter=1
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines if desired
        [[ -z "$line" ]] && continue
        echo "${counter}:${line}"
        ((counter++))
    done < "$EBOOKS_DB"
}

generate_ebooks_result_list() {
    local counter=1
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines if desired
        [[ -z "$line" ]] && continue
        echo "${counter}:${line}"
        ((counter++))
    done < "$1"
}

view_ebooks() {
    local tmpfile
    tmpfile=$(mktemp)
    generate_ebooks_list > "$tmpfile"
    whiptail --scrolltext --textbox "$tmpfile" 20 80
    rm -f "$tmpfile"
}

view_tags() {
    whiptail --scrolltext --textbox "$TAGS_DB" 20 60
}

search_tags() {
    # Get search term
    search=$(whiptail --inputbox "Enter tag search string:" 8 40 3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then return; fi
    
    # Find matching tags
    mapfile -t matching_tags < <(grep -i "$search" "$TAGS_DB")
    if [[ ${#matching_tags[@]} -eq 0 ]]; then
        whiptail --msgbox "No matching tags found!" 8 40
        return
    fi
    
    # convert matching_tags array into whiptail friendly format.
    mapfile -d $'\x1e' -t matching_tags_whip < <(make_into_pairs "${matching_tags[@]}")

    # Select tag
    tag=$(whiptail --menu "Choose a tag:" 20 170 10 \
        "${matching_tags_whip[@]}" 3>&1 1>&2 2>&3)		# menu items must come in pairs!!!!
    if [[ $? -ne 0 ]]; then return; fi
    
    # Find ebooks with this tag
    # First, escape regex metacharacters in $tag
    escaped_tag=$(sed 's/[.[\*^$(){}+?|]/\\&/g' <<< "$tag")
    # Use the escaped version in grep
    result="$(grep -E "\|.*${escaped_tag}(,|$)" "$EBOOKS_DB")"

    if [[ -z "$result" ]]; then
        whiptail --msgbox "No ebooks found with this tag!" 8 40
    else
        generate_ebooks_result_list <(echo "$result") >/tmp/search_result.txt
        whiptail --scrolltext --textbox /tmp/search_result.txt 20 80
        rm /tmp/search_result.txt
    fi
}

dissociate_tag_from_registered_ebook() {
    # Check if ebooks database exists
    [[ ! -f "$EBOOKS_DB" ]] && whiptail --msgbox "Ebooks database not found!" 8 40 && return 1

    # Read ebooks database into array
    local ebooks_list=()
    mapfile -t ebooks_list < "$EBOOKS_DB"

    # Check for empty database
    [[ ${#ebooks_list[@]} -eq 0 ]] && whiptail --msgbox "No registered ebooks!" 8 40 && return 0

    # Create menu items array
    local menu_items=()
    for entry in "${ebooks_list[@]}"; do
        IFS='|' read -r path tags <<< "$entry"
        menu_items+=("$path" "T:${tags}")
    done

    local filter_str
    # Get filter string from user using whiptail. No globbing, simple substring match.
    filter_str=$(whiptail --title "Filter eBooks" --inputbox "Enter filter string to narrow search (empty for wildcard):" 8 40 3>&1 1>&2 2>&3)    

    # Handle cancel/escape
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to "*" if unset
    filter_str=${filter_str:-"*"}

    # Filter menu_items and store in array
    mapfile -d $'\0' filtered_menu_items < <(filter_menu_items "$filter_str" "${menu_items[@]}")

    # Truncate menu_items because of possible long file names.
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_dissoc_tag "${filtered_menu_items[@]}" | sed 's/\x1E$//')
    CURRENT_PAGE=0

    # First selection: Choose ebook. paginate here because trunc may be large.
    paginate
    [[ $? -ne 0 ]] && return 0  # User canceled
    selected_ebook_trunc="$SELECTED_ITEM"

    local selected_ebook
    #selected_ebook_trunc="$(paginate "${trunc[@]}")"

    local n="$(echo "$selected_ebook_trunc" | cut -d':' -f1)"
    local m=$((2 * n - 1))

    # debug
    #echo "selected_ebook_trunc: " "$selected_ebook_trunc" >&2
    #echo "n: " "$n" >&2
    #echo "m: " "$m" >&2

    # Remember we want filtered_menu_items[m-1].
    selected_ebook="${filtered_menu_items[$((m - 1))]}"

    # Find the selected entry
    local original_entry tags_array
    for entry in "${ebooks_list[@]}"; do
        if [[ "$entry" == "${selected_ebook}|"* ]]; then
            IFS='|' read -r original_path original_tags <<< "$entry"
            break
        fi
    done

    # Split tags into array
    IFS=',' read -ra tags_array <<< "$original_tags"

    # Check if there are tags to remove
    [[ ${#tags_array[@]} -eq 0 ]] && whiptail --msgbox "No tags associated with this eBook!" 8 40 && return 0

    # Create tag selection menu
    local tag_menu_items=()
    for tag in "${tags_array[@]}"; do
        tag_menu_items+=("$tag" " ")
    done

    # Second selection: Choose tag to remove
    local selected_tag
    selected_tag=$(whiptail --title "Remove Tag from eBook" --menu "Choose tag to remove:" \
        15 60 0 "${tag_menu_items[@]}" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 0  # User canceled

    # Confirm removal
    whiptail --yesno "Remove tag '$selected_tag' from:\n$selected_ebook?" 20 80 || return 0

    # Process tag removal
    local new_tags=()
    for tag in "${tags_array[@]}"; do
        [[ "$tag" != "$selected_tag" ]] && new_tags+=("$tag")
    done

    # Update the entry
    local updated_entry="${original_path}|"
    if [[ ${#new_tags[@]} -gt 0 ]]; then
        updated_entry+="$(IFS=','; echo "${new_tags[*]}")"
    fi

    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    
    # Update the database
    for entry in "${ebooks_list[@]}"; do
        if [[ "$entry" == "${selected_ebook}|"* ]]; then
            echo "$updated_entry" >> "$temp_file"
        else
            echo "$entry" >> "$temp_file"
        fi
    done

    mv -f "$temp_file" "$EBOOKS_DB"
    whiptail --msgbox "Tag '$selected_tag' removed from '$selected_ebook'!" 20 80
}

delete_tag_from_global_list() {
    # Check dependencies
    [[ ! -f "$TAGS_DB" ]] && whiptail --msgbox "Tags database not found!" 8 40 && return 1
    [[ ! -f "$EBOOKS_DB" ]] && whiptail --msgbox "Ebooks database not found!" 8 40 && return 1

    # Read tags database
    local tags_list=()
    mapfile -t tags_list < "$TAGS_DB"
    [[ ${#tags_list[@]} -eq 0 ]] && whiptail --msgbox "No tags available!" 8 40 && return 0

    # Create menu items
    local menu_items=()
    for tag in "${tags_list[@]}"; do
        menu_items+=("$tag" " ")
    done

    # Tag selection
    local selected_tag
    selected_tag=$(whiptail --title "Delete Global Tag" --menu "Choose tag to delete:" \
        15 60 0 "${menu_items[@]}" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 0  # User canceled

    # Check for tag usage in ebooks
    local used_in=()
    while IFS='|' read -r path tags; do
        IFS=',' read -ra etags <<< "$tags"
        for tag in "${etags[@]}"; do
            [[ "$tag" == "$selected_tag" ]] && used_in+=("$path") && break
        done
    done < "$EBOOKS_DB"

    # If tag is still in use
    if [[ ${#used_in[@]} -gt 0 ]]; then
        local message="Tag is used in ${#used_in[@]} eBook(s):\n\n"
        message+=$(printf '%s\n' "${used_in[@]}")
        message+="\n\nDissociate tag first!"
        whiptail --scrolltext --msgbox "$message" 20 80
        return 1
    fi

    # Final confirmation
    whiptail --yesno "Permanently delete tag:\n'$selected_tag'?" 10 40 || return 0

    # Delete from tags database
    grep -Fx -v -- "$selected_tag" "$TAGS_DB" > "$TAGS_DB.tmp"; mv -f "$TAGS_DB.tmp" "$TAGS_DB"
    #grep -Fx -v -- "$selected_tag" "$TAGS_DB" > "$TAGS_DB.tmp" && mv -f "$TAGS_DB.tmp" "$TAGS_DB" # BIG FIX. you know why this doesn't work?
    # it's because LHS is false when grep output is empty so RHS is not run.
    whiptail --msgbox "Tag '$selected_tag' deleted successfully!" 8 40
}

remove_registered_ebook() {
    # Check if database file exists
    if [[ ! -f "$EBOOKS_DB" ]]; then
        whiptail --title "Error" --msgbox "Ebooks database not found!" 10 60
        return 1
    fi

    # Read database entries into array
    mapfile -t entries < "$EBOOKS_DB"

    # Check for empty database
    if [[ ${#entries[@]} -eq 0 ]]; then
        whiptail --title "Error" --msgbox "The ebooks database is empty!" 10 60
        return 1
    fi

    # Prepare menu items array for whiptail
    local menu_items=()
    for entry in "${entries[@]}"; do
        IFS='|' read -r path tags <<< "$entry"
        menu_items+=("$path" "T:${tags}")
    done

    # Get search string from user
    local search_str
    search_str=$(whiptail --title "Search Ebook" --inputbox "Enter text to filter registered ebooks (empty for wildcard):" 10 60 3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
        return 1  # User cancelled the search
    fi

    # Display 'In operation' message because creating TRUNC may take some time.
    in_operation_msg

    # Create filtered_menu_items based on search_str
    local filtered_menu_items=()
    for ((i=0; i<${#menu_items[@]}; i+=2)); do
        path="${menu_items[i]}"
        tags="${menu_items[i+1]}"
        if [[ "${path,,}" == *"${search_str,,}"* ]]; then
            filtered_menu_items+=("$path" "$tags")
        fi
    done

    # Check if filtered list is empty
    if [[ ${#filtered_menu_items[@]} -eq 0 ]]; then
        whiptail --title "Error" --msgbox "No ebooks found matching '$search_str'." 10 60
        return 1
    fi

    # Truncate menu_items because of possible long file names.
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_delete_ebook "${filtered_menu_items[@]}" | sed 's/\x1E$//')
    CURRENT_PAGE=0

    # Show selection dialog. paginate here because trunc may be large.
    local selected_path
    paginate
    # Exit if user canceled
    [ $? -ne 0 ] && return 1
    selected_trunc="$SELECTED_ITEM"

    #selected_trunc="$(paginate "${trunc[@]}")"

    local n="$(echo "$selected_trunc" | cut -d':' -f1)"
    local m=$((2 * n - 1))

    # debug
    #echo "selected_trunc: " "$selected_trunc" >&2
    #echo "n: " "$n" >&2
    #echo "m: " "$m" >&2

    # Remember we want filtered_menu_items[m-1].
    selected_path="${filtered_menu_items[$((m - 1))]}"

    # Show confirmation dialog
    whiptail --title "Confirm Removal" --yesno "Are you sure you want to remove:\n$selected_path" 20 80 \
        --yes-button "Remove" --no-button "Cancel" 3>&1 1>&2 2>&3

    # Proceed with removal if confirmed
    if [ $? -eq 0 ]; then
        # Create temporary file
        local temp_file
        temp_file=$(mktemp)

        # Remove entry and preserve other entries
        awk -v path="$selected_path" -F'|' '$1 != path' "$EBOOKS_DB" > "$temp_file"
        mv "$temp_file" "$EBOOKS_DB"

        whiptail --title "Success" --msgbox "'${selected_path}' removed successfully!" 20 80
    fi
}

# Open eBook codes start here:

# Get appropriate open command for file type
get_open_command() {
    local file="$1"
    local extension="${file##*.}"
    local cmd="${EXTENSION_COMMANDS[$extension]}"
    
    [ -z "$cmd" ] && cmd="xdg-open"
    
    command -v "$cmd" >/dev/null 2>&1 || {
        whiptail --msgbox "ERROR: Command '$cmd' not found for $extension files" 10 60
        return 1
    }
    echo "$cmd"
}

# File opening handler with existence check
open_file() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        whiptail --msgbox "ERROR: File does not exist:\n$file" 20 80
        return 1
    fi
    
    local open_cmd
    if ! open_cmd=$(get_open_command "$file"); then
        return 1
    fi

    # maybe a good idea to show 'Opening file for you...' for a second
    TERM=ansi whiptail --infobox "Opening file for you..." 8 40
    sleep 1
    
    $open_cmd "$file" &>/dev/null & disown
}

# Open file by search by filename workflow
open_file_search_by_filename() {
    local search_term
    search_term=$(whiptail --inputbox "Enter filename search term (empty for wildcard):" 10 60 3>&1 1>&2 2>&3)

    # Exit if user canceled
    [ $? -ne 0 ] && return 1

    # defaults to wildcard if empty
    search_term="${search_term:-*}"
    
    local matches=()
    while IFS= read -r line; do
        if [[ "$line" == *"|"* ]]; then
            IFS='|' read -r path tags <<< "$line"
            filename=$(basename "$path")
            if [[ "$search_term" == "*" || "${filename,,}" == *"${search_term,,}"* ]]; then
                matches+=("$path" " ")
            fi
        fi
    done < "$EBOOKS_DB"
    
    [ ${#matches[@]} -eq 0 ] && {
        whiptail --msgbox "No matches found for: $search_term" 10 60
        return
    }

    # Truncate matches because of possible long file names.
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_assoc_tag "${matches[@]}" | sed 's/\x1E$//')
    CURRENT_PAGE=0

    # paginate in case trunc gets too big.
    paginate
    # Exit if user canceled
    [ $? -ne 0 ] && return 1

    selected_trunc="$SELECTED_ITEM"
    #selected_trunc="$(paginate "${trunc[@]}")"

    local n="$(echo "$selected_trunc" | cut -d':' -f1)"
    local m=$((2 * n - 1))

    # debug
    #echo "selected_trunc: " "$selected_trunc" >&2
    #echo "n: " "$n" >&2
    #echo "m: " "$m" >&2

    # Remember we want matches[m-1].
    selected="${matches[$((m - 1))]}"

    [ -z "$selected" ] && whiptail --msgbox "No file selected." 10 60 && return 1
    open_file "$selected" || whiptail --msgbox "Error opening file: ${selected}." 20 80
}

# Open file by search by tag workflow
open_file_search_by_tag() {
    local tag_search
    tag_search=$(whiptail --inputbox "Enter tag search term (empty for wildcard):" 10 60 3>&1 1>&2 2>&3)

    # Exit if user canceled
    [ $? -ne 0 ] && return 1

    tag_search="${tag_search:-*}"
    
    # Get matching tags from TAGS_DB
    local tags=()
    while IFS= read -r tag; do
        [[ "$tag_search" == "*" || "${tag,,}" == *"${tag_search,,}"* ]] && tags+=("$tag" " ")
    done < "$TAGS_DB"
    
    [ ${#tags[@]} -eq 0 ] && {
        whiptail --msgbox "No tags found matching: $tag_search" 10 60
        return
    }
    
    local selected_tag
    selected_tag=$(whiptail --menu "Select tag" 20 170 10 "${tags[@]}" 3>&1 1>&2 2>&3)  # tweak dimensions

    # Exit if user canceled
    [ $? -ne 0 ] && return 1

    [ -z "$selected_tag" ] && return

    # Find files with selected tag
    local files=()
    while IFS= read -r line; do
        if [[ "$line" == *"|"* ]]; then
            IFS='|' read -r path tags <<< "$line"
            IFS=',' read -ra tag_array <<< "$tags"
            for t in "${tag_array[@]}"; do
                if [ "$t" = "$selected_tag" ]; then
                    files+=("$path" " ")
                    break
                fi
            done
        fi
    done < "$EBOOKS_DB"
    
    [ ${#files[@]} -eq 0 ] && {
        whiptail --msgbox "No files found for tag: $selected_tag" 10 60
        return
    }

    # Truncate ebooks_whip because of possible long file names.
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_assoc_tag "${files[@]}" | sed 's/\x1E$//')
    CURRENT_PAGE=0

    # paginate here because trunc might be large.
    paginate
    # Exit if user canceled
    [ $? -ne 0 ] && return 1
    
    selected_file_trunc="$SELECTED_ITEM"
    #selected_file_trunc="$(paginate "${trunc[@]}")"

    local n="$(echo "$selected_file_trunc" | cut -d':' -f1)"
    local m=$((2 * n - 1))

    # debug
    #echo "selected_file_trunc: " "$selected_file_trunc" >&2
    #echo "n: " "$n" >&2
    #echo "m: " "$m" >&2

    # Remember we want files[m-1].
    selected_file="${files[$((m - 1))]}"

    [ -z "$selected_file" ] && whiptail --msgbox "No file selected." 10 60 && return 1
    open_file "$selected_file" || whiptail --msgbox "Error opening file: ${selected_file}." 20 80
}

illegal_pattern() {
    local pattern="$1"
    if echo "$pattern" | grep -qE '^\||[^|]\|[^|]|\|{3,}|\|$'; then
        return 1  # Illegal pattern detected
    else
        return 0  # No illegal patterns
    fi
}

add_files_in_bulk() {
    # Show initial information
    whiptail --title "Bulk Add eBooks" --msgbox \
"This advanced feature allows you to add multiple eBook files to the database.\n\
It involves the following steps:\n\
1. Select a root directory to search\n\
2. Enter file patterns to match (case insensitive)\n\
3. Files will be added if not already registered" 12 70

    # Directory selection
    local selected_dir
    selected_dir=$(navigate "$(pwd)")
    if [[ -z "$selected_dir" ]]; then
        whiptail --msgbox "Directory selection canceled." 8 40
        return 1
    fi

    # Pattern input
    local pattern_input
    pattern_input=$(whiptail --inputbox "Enter glob file patterns (use || to separate multiple):\n\n\
Example: *.pdf||*.epub\n\
Matches any PDF or EPUB files" \
    --title "Search Patterns" 12 70 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1  # User canceled

    # Check for illegal pattern.
    illegal_pattern "$pattern_input" || { 
        whiptail --title "Alert" --msgbox "Illegal pattern. Try again." 8 78
        return 1
    }

    # Split patterns and validate
    local patterns=()
    IFS='||' read -ra temp_patterns <<< "$pattern_input"
    for p in "${temp_patterns[@]}"; do
        p="${p#"${p%%[![:space:]]*}"}"  # Trim leading whitespace
        p="${p%"${p##*[![:space:]]}"}"  # Trim trailing whitespace
        [[ -n "$p" ]] && patterns+=("$p")
    done

    if [[ ${#patterns[@]} -eq 0 ]]; then
        whiptail --msgbox "No valid patterns entered." 8 40
        return 1
    fi

    # Build find command
    local find_cmd=(-type f)
    if [[ ${#patterns[@]} -gt 0 ]]; then
        find_cmd+=(\()
        for ((i=0; i<${#patterns[@]}; i++)); do
            ((i > 0)) && find_cmd+=(-o)
            find_cmd+=(-iname "${patterns[i]}")
        done
        find_cmd+=(\))
    fi

    # Perform search
    TERM=ansi whiptail --infobox "Performing search..." 8 40 >/dev/tty
    local found_files=()
    while IFS= read -r -d $'\0'; do
        found_files+=("$REPLY")
    done < <(find "$selected_dir" "${find_cmd[@]}" -print0 2>/dev/null)

    if [[ ${#found_files[@]} -eq 0 ]]; then
        whiptail --msgbox "No files found matching patterns." 8 40
        return 1
    fi

    # Load existing entries
    local -A existing_map
    if [[ -f "$EBOOKS_DB" ]]; then
        while IFS='|' read -r path _; do
            existing_map["$path"]=1
        done < "$EBOOKS_DB"
    fi

    # Filter new files
    local new_entries=()
    for file in "${found_files[@]}"; do
        file="${file//\/\///}"  # Normalize path
        [[ ! -v existing_map["$file"] ]] && new_entries+=("$file")
    done

    # Handle no new entries
    if [[ ${#new_entries[@]} -eq 0 ]]; then
        whiptail --msgbox "All matching files already exist in database." 8 50
        return 0
    fi

    # Confirm yes/no to proceed.
    whiptail --title "Confirm" --yesno "${#new_entries[@]} entries found. Do you want to proceed and update database?" 8 78 || return 1

    # Add to database
    {
        for file in "${new_entries[@]}"; do
            echo "${file}|"
        done
    } >> "$EBOOKS_DB"

    # Show results
    local result_msg="Successfully added ${#new_entries[@]} files:\n\n"
    for file in "${new_entries[@]}"; do
        #result_msg+="${file##*/}\n"  # Show filename only
        result_msg+="${file}\n" 
    done
    
    # Too large to display from msgbox so use temporary file and textbox.
    echo "$result_msg" > /tmp/result_msg.txt
    whiptail --scrolltext --title "Results" --textbox /tmp/result_msg.txt 20 80
    rm /tmp/result_msg.txt
    #whiptail --title "Results" --scrolltext --msgbox "$result_msg" 20 80
}

# Parser for custom boolean patterns into a grep -P regex

convert_literal() {
    local lit="$1"
    local start_anchor=1
    local end_anchor=1

    # Check if the literal starts with *
    if [[ "$lit" == \** ]]; then
        start_anchor=0
        lit="${lit#\*}"
    fi

    # Check if the literal ends with *
    if [[ "$lit" == *\* ]]; then
        end_anchor=0
        lit="${lit%\*}"
    fi

    # Escape regex special characters except *
    # Corrected character class to include ], [ and others properly
    lit=$(echo "$lit" | sed -E 's/([].^$+?{}|()\\[])/\\\1/g')
    # Replace remaining * with .*
    lit=$(echo "$lit" | sed 's/\*/.*/g')

    # Handle case where lit is empty (e.g., input was *)
    if [ -z "$lit" ]; then
        lit=".*"
    fi

    # Apply start and end anchors
    if [ $start_anchor -eq 1 ]; then
        lit="^$lit"
    else
        lit=".*$lit"
    fi

    if [ $end_anchor -eq 1 ]; then
        lit="$lit$"
    else
        lit="$lit.*"
    fi

    echo "$lit"
}

# Check if a string is enclosed by a matching pair of outer parentheses
is_enclosed_by_parentheses() {
    local s="$1"
    # Must start with ( and end with )
    if [[ ${s:0:1} != "(" || ${s: -1} != ")" ]]; then
         echo 0
         return
    fi
    local level=0
    local i char
    for (( i=0; i<${#s}; i++ )); do
         char="${s:$i:1}"
         if [[ "$char" == "(" ]]; then
             level=$((level+1))
         elif [[ "$char" == ")" ]]; then
             level=$((level-1))
         fi
         # If level drops to 0 before the end, the outer parentheses aren’t encompassing all
         if [ $level -eq 0 ] && [ $i -lt $((${#s}-1)) ]; then
             echo 0
             return
         fi
    done
    echo 1
}

# Split string by a delimiter (e.g. "&&" or "||") at the top level,
# ignoring delimiters inside parentheses.
split_top_level() {
    local s="$1"
    local delim="$2"
    local delim_len=${#delim}
    local level=0
    local token=""
    local i char
    for (( i=0; i<${#s}; i++ )); do
         char="${s:$i:1}"
         if [[ "$char" == "(" ]]; then
             level=$((level+1))
         elif [[ "$char" == ")" ]]; then
             level=$((level-1))
         fi
         if [ $level -eq 0 ] && [[ "${s:$i:$delim_len}" == "$delim" ]]; then
             echo "$token"
             token=""
             i=$(( i + delim_len - 1 ))
         else
             token+="$char"
         fi
    done
    echo "$token"
}

# Parse a primary expression: either a grouped expression or a literal string.
parse_primary() {
    local expr="$1"
    # Trim leading/trailing whitespace.
    expr="$(echo -n "$expr" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ "$expr" == "("*")" ]]; then
         if [ "$(is_enclosed_by_parentheses "$expr")" -eq 1 ]; then
             # Remove outer parentheses and parse inside (non-top-level so no ^)
             expr="${expr:1:-1}"
             echo "$(parse_expr "$expr" 0)"
             return
         fi
    fi
    # Otherwise, treat as literal pattern.
    echo "$(convert_literal "$expr")"
}

# Parse an OR expression by splitting on top-level "||"
parse_or() {
    local expr="$1"
    local alternatives=()
    while IFS= read -r line; do
         alternatives+=("$line")
    done < <(split_top_level "$expr" "||")
    
    # If there’s only one alternative, return its parsed primary.
    if [ ${#alternatives[@]} -eq 1 ]; then
         echo "$(parse_primary "${alternatives[0]}")"
         return
    fi
    local regex_alts=""
    for alt in "${alternatives[@]}"; do
         local parsed
         parsed=$(parse_primary "$alt")
         if [ -z "$regex_alts" ]; then
              regex_alts="$parsed"
         else
              regex_alts="$regex_alts|$parsed"
         fi
    done
    echo "($regex_alts)"
}

# Parse a full boolean expression.
# This splits on top-level "&&" and wraps each part in a lookahead (?=.*...)
# If 'top' is 1 (default), a '^' anchor is prepended.
parse_expr() {
    local expr="$1"
    local top="${2:-1}"
    local parts=()
    while IFS= read -r line; do
         parts+=("$line")
    done < <(split_top_level "$expr" "&&")
    
    local regex=""
    for part in "${parts[@]}"; do
         local part_regex
         part_regex=$(parse_or "$part")
         regex="$regex(?=.*$part_regex)"
    done
    if [ "$top" -eq 1 ]; then
         echo "^$regex"
    else
         echo "$regex"
    fi
}

# Formats string for individual file info.
format_file_info() {
    local selected_line="$1"

    # Split the line at the first '|' into two parts.
    local file_with_path="${selected_line%|*}"
    local tags="${selected_line##*|}"

    # Extract the directory and filename
    local directory
    local filename
    directory=$(dirname "$file_with_path")
    filename=$(basename "$file_with_path")

    # Print the formatted output
    echo "File name:"
    echo "$filename"
    echo ""
    echo "Directory path:"
    echo "${directory}/"
    echo ""
    echo "Tags:"
    echo "$tags"
}

# Depends on parser code above for parsing custom boolean patterns to be used here.
lookup_registered_files() {
    # Show initial information
    whiptail --title "Lookup Registered Files" --msgbox \
    "This advanced feature allows you to look up full file information by narrowing it down by file name and tags." 8 78

    # Show boolean pattern help information
    whiptail --scrolltext --title "Boolean pattern for searching files" --msgbox \
    "Boolean Pattern HELP:\n\n\
Boolean patterns are used here only for FILE PATTERNS, not tag patterns.\n\
The pattern is similar to globbing in that pattern consists of (,),&&,||,*. It is NOT regex.\n\
We group patterns with ( and ). && is AND and || is OR. * is wildcard. ! is not supported yet.\n\
Don't include spaces between primary patterns ie. *programming*&&*.pdf not *programming* && *.pdf.\n\n\
Searches are case insensitive.\n\n\
Some examples:\n\
1. (*.pdf||*.epub)&&*schaum*\n\
Search pdf or epub containing 'schaum' in their file name.\n\
2. *.pdf&&*dover*\n\
Search pdf files with 'dover' in their file name.\n\
3. *.pdf||*.epub||*.txt\n\
Search for pdf or epub or txt files.\n\
4. (*linear algebra*&&*schaum*&&*.pdf)||(*dover*&&*linear algebra*&&*.epub)\n\
Search pdf files containing both 'linear algebra' and 'schaum' in their file names OR epub files containing \
'dover' and 'linear algebra' in their file names." 20 80

    local pattern regex filtered_paths filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter boolean pattern for file names (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"

    # DEBUG - if need be save to a temp file perhaps?
    #echo pattern: >&2
    #echo "$pattern" >&2

    # Convert pattern to regex using your existing parse_expr function
    regex=$(parse_expr "$pattern")

    # DEBUG
    #echo regex: >&2
    #echo "$regex" >&2

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file path part is considered (everything before the |)
    filtered_paths=$(cut -d'|' -f1 "$EBOOKS_DB" | grep -iP "$regex")
    if [ -z "$filtered_paths" ]; then
        whiptail --msgbox "No files match the given file name pattern." 8 60
        return 1
    fi

    # DEBUG
    #echo filtered_paths: >&2
    #echo "$filtered_paths" >&2 # check!

    # Get the full lines from $EBOOKS_DB corresponding to the filtered file paths.
    # The grep -F -x -f ensures we only get exact matches from the file path field.
    filtered_lines=$(grep -F -f <(echo "$filtered_paths" | sed 's/$/|/') "$EBOOKS_DB")

    # DEBUG
    #echo filtered_lines: >&2
    #echo "$filtered_lines" >&2

    # Tag pattern info. Inform user that tag patterns is not regex or globbing but simple substring match.
    whiptail --title "IMPORTANT NOTE about Tag Patterns" --msgbox \
    "You are about to provide value for a tag pattern. Remember that it is not regex or globbing but simple substring match.\n\
This means if you enter '*schaum*' \\* will be matched literally not as wildcard." 12 60

    # Step 2: Ask the user for a tag search pattern
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (if empty wildcard):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to .*
    tag_pattern="${tag_pattern:-.*}"

    # Further filter the lines by matching the tag pattern (which appears after the |)
    final_list=$(echo "$filtered_lines" | grep -iP "\|.*$tag_pattern")
    if [ -z "$final_list" ]; then
        whiptail --msgbox "No files match the given tag pattern." 8 60
        return 1
    fi

    in_operation_msg # show 'in operation...' while building menu items...

    local menu_items=()
    local idx=1
    declare -A line_map
    # Build the menu items array. Each menu entry is a pair:
    # the index number and a description (file path with tags)
    while IFS= read -r line; do
        # Replace the | separator with a more readable format for display.
        menu_items+=("$idx" "$(echo "$line")")
        line_map["$idx"]="$line"
        idx=$((idx + 1))
    done <<< "$final_list"

    # menu_items need truncating. the format is "idx#" "full path including tags"
    # Build the large list once:
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_lookup "${menu_items[@]}" | sed 's/\x1E$//')

    # Reset CURRENT_PAGE for this new TRUNC array.
    CURRENT_PAGE=0

    # Step 3: Loop to show the final list in a whiptail menu repeatedly
    while true; do
        # then paginate it.
        paginate

        if [ $? -ne 0 ]; then
            break
        fi

        # Display the whiptail menu.
        local selection
        selection="$SELECTED_ITEM"

        # Retrieve and display the selected file (full line with path and tags)
        local selected_line="${line_map[$selection]}"

        # Format file info and display it.
        local formatted_str="$(format_file_info "$selected_line")"
        whiptail --scrolltext --msgbox "$formatted_str" 20 80
    done
}

# Build list of filtered items from $EBOOKS_DB filtered by full path name and tag.
build_bulk() {    
    # Show boolean pattern help information
    whiptail --scrolltext --title "Boolean pattern for searching files" --msgbox \
    "Boolean Pattern HELP:\n\n\
Boolean patterns are used here only for FILE PATTERNS, not tag patterns.\n\
The pattern is similar to globbing in that pattern consists of (,),&&,||,*. It is NOT regex.\n\
We group patterns with ( and ). && is AND and || is OR. * is wildcard. ! is not supported yet.\n\
Don't include spaces between primary patterns ie. *programming*&&*.pdf not *programming* && *.pdf.\n\n\
Searches are case insensitive.\n\n\
Some examples:\n\
1. (*.pdf||*.epub)&&*schaum*\n\
Search pdf or epub containing 'schaum' in their file name.\n\
2. *.pdf&&*dover*\n\
Search pdf files with 'dover' in their file name.\n\
3. *.pdf||*.epub||*.txt\n\
Search for pdf or epub or txt files.\n\
4. (*linear algebra*&&*schaum*&&*.pdf)||(*dover*&&*linear algebra*&&*.epub)\n\
Search pdf files containing both 'linear algebra' and 'schaum' in their file names OR epub files containing \
'dover' and 'linear algebra' in their file names." 20 80 >/dev/tty

    local pattern regex filtered_paths filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter boolean pattern for file names (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3 </dev/tty)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"

    # DEBUG - if need be save to a temp file perhaps?
    #echo pattern: >&2
    #echo "$pattern" >&2

    # Convert pattern to regex using your existing parse_expr function
    regex=$(parse_expr "$pattern")

    # DEBUG
    #echo regex: >&2
    #echo "$regex" >&2

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file path part is considered (everything before the |)
    filtered_paths=$(cut -d'|' -f1 "$EBOOKS_DB" | grep -iP "$regex")
    if [ -z "$filtered_paths" ]; then
        whiptail --msgbox "No files match the given file name pattern." 8 60 >/dev/tty
        return 1
    fi

    # DEBUG
    #echo filtered_paths: >&2
    #echo "$filtered_paths" >&2 # check!

    # Get the full lines from $EBOOKS_DB corresponding to the filtered file paths.
    # The grep -F -x -f ensures we only get exact matches from the file path field.
    filtered_lines=$(grep -F -f <(echo "$filtered_paths" | sed 's/$/|/') "$EBOOKS_DB")

    # DEBUG
    #echo filtered_lines: >&2
    #echo "$filtered_lines" >&2

    # Tag pattern info. Inform user that tag patterns is not regex or globbing but simple substring match.
    whiptail --title "IMPORTANT NOTE about Tag Patterns" --msgbox \
    "You are about to provide value for a tag pattern. Remember that it is not regex or globbing but simple substring match.\n\
This means if you enter '*schaum*' \\* will be matched literally not as wildcard." 12 60 >/dev/tty

    # Step 2: Ask the user for a tag search pattern
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (if empty wildcard):" 8 60 3>&1 1>&2 2>&3 </dev/tty)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to .*
    tag_pattern="${tag_pattern:-.*}"

    # Further filter the lines by matching the tag pattern (which appears after the |)
    final_list=$(echo "$filtered_lines" | grep -iP "\|.*$tag_pattern")
    if [ -z "$final_list" ]; then
        whiptail --msgbox "No files match the given tag pattern." 8 60 >/dev/tty
        return 1
    fi
    
    # Echo with \0 delimiter for further processing.
    # Remember trailing \0 is actually needed to be transformed into an array.
    echo "$final_list" | while IFS= read -r line; do
        printf '%s\0' "$line"
    done    
}

assoc_tag_to_bulk() {
    # Initial message.
    whiptail --title "Bulk Associate Tag" --msgbox "This advanced feature lets you choose a registered tag and associate that same tag across a bulk of registered files." 10 60

    # Present tag selection menu using whiptail
    local tags=()
    while IFS= read -r tag; do
        tags+=("$tag" " ")
    done < "$TAGS_DB"
    
    [[ ${#tags[@]} -eq 0 ]] && { 
        whiptail --title "Error" --msgbox "No tags registered. Register at least one tag." 0 0
        return 1
    }
    
    local selected_tag
    selected_tag=$(whiptail --menu "Choose a tag to associate to bulk" 0 0 0 "${tags[@]}" 3>&1 1>&2 2>&3)
    [[ -z "$selected_tag" ]] && return 1  # User canceled
    
    # Read bulk entries
    local tempfile=$(mktemp) || return 1

    build_bulk > "$tempfile" || {
        whiptail --title "Error" --msgbox "User cancelled." 0 0
        return 1
    }

    local bulk
    mapfile -d '' bulk < "$tempfile"
    rm -f "$tempfile"
    
    # Process bulk entries
    local processed_bulk=()
    for entry in "${bulk[@]}"; do
        IFS='|' read -r path current_tags <<< "$entry"
        
        # Handle empty tags case
        if [[ -z "$current_tags" ]]; then
            new_tags="$selected_tag"
        else
            # Check if tag already exists
            if [[ ",$current_tags," == *",$selected_tag,"* ]]; then
                new_tags="$current_tags"
            else
                new_tags="$current_tags,$selected_tag"
            fi
        fi
        
        processed_bulk+=("$path|$new_tags")
    done

    # Create associative array for updates
    declare -A updated_entries
    for entry in "${processed_bulk[@]}"; do
        IFS='|' read -r path tags <<< "$entry"
        updated_entries["$path"]="$tags"
    done

    # Before updating database, show the candidates for update:
    local key
    local entries_str=""

    # Loop through the keys and format each line
    for key in "${!updated_entries[@]}"; do
        entries_str+="$key New:${updated_entries[$key]}\n"
    done

    # Inform user of candidates for update
    local tempfile=$(mktemp)
    printf "%b" "$entries_str" > "$tempfile"
    whiptail --scrolltext --title "ATTENTION Candidates For Tag Update" --textbox "$tempfile" 20 80
    rm -f "$tempfile"

    # Before updating database, ask user to confirm.
    whiptail --title "Confirm Update" --yesno \
"We have maximum of ${#updated_entries[@]} entries that could potentially be overwritten. \
If you proceed, all of the matching entries will be associated with the tag '${selected_tag}'. Do you want to update the database?" \
0 0

    [[ $? -ne 0 ]] && {
        whiptail --title "Error" --msgbox "User cancelled. Database has not been modified." 0 0
        return 1
    }

    # Update EBOOKS_DB
    local tmpfile=$(mktemp) || return 1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        IFS='|' read -r path tags <<< "$line"
        if [[ -v "updated_entries[$path]" ]]; then
            echo "$path|${updated_entries[$path]}" >> "$tmpfile"
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$EBOOKS_DB"

    # Replace original file with updated version
    mv -- "$tmpfile" "$EBOOKS_DB"

    # Display final message.
    whiptail --title "Bulk Update Finished" --msgbox \
"Bulk files have been associated with the tag '${selected_tag}'." 0 0
}

dissoc_tag_to_bulk() {
    # Initial message.
    whiptail --title "Bulk Dissociate Tag" --msgbox "This advanced feature lets you choose a registered tag and remove that same tag from a bulk of registered files." 10 60

    # Present tag selection menu using whiptail
    local tags=()
    while IFS= read -r tag; do
        tags+=("$tag" " ")
    done < "$TAGS_DB"
    
    [[ ${#tags[@]} -eq 0 ]] && { 
        whiptail --title "Error" --msgbox "No tags registered. Register at least one tag." 0 0
        return 1
    }
    
    local selected_tag
    selected_tag=$(whiptail --menu "Choose a tag to dissociate from bulk" 0 0 0 "${tags[@]}" 3>&1 1>&2 2>&3)
    [[ -z "$selected_tag" ]] && return 1  # User canceled
    
    # In operation msg because building bulk takes time.
    in_operation_msg

    # Read bulk entries
    local tempfile=$(mktemp) || return 1

    build_bulk > "$tempfile" || {
        whiptail --title "Error" --msgbox "User cancelled." 0 0
        return 1
    }

    local bulk
    mapfile -d '' bulk < "$tempfile"
    rm -f "$tempfile"
    
    # Process bulk entries
    local processed_bulk=()
    for entry in "${bulk[@]}"; do
        IFS='|' read -r path current_tags <<< "$entry"
        local new_tags

        # Remove selected_tag if present
        if [[ -n "$current_tags" ]]; then
            IFS=',' read -ra tags_array <<< "$current_tags"
            local new_tags_array=()
            for tag in "${tags_array[@]}"; do
                [[ "$tag" != "$selected_tag" ]] && new_tags_array+=("$tag")
            done
            # Join array back to comma-separated string
            new_tags=$(IFS=','; echo "${new_tags_array[*]}")
        else
            new_tags="$current_tags"
        fi

        processed_bulk+=("$path|$new_tags")
    done

    # Create associative array for updates
    declare -A updated_entries
    for entry in "${processed_bulk[@]}"; do
        IFS='|' read -r path tags <<< "$entry"
        # Only add to updates if tags changed
        if [[ "$tags" != "$(grep -F "$path|" "$EBOOKS_DB" | cut -d'|' -f2-)" ]]; then
            updated_entries["$path"]="$tags"
        fi
    done

    # Skip if no changes
    [[ ${#updated_entries[@]} -eq 0 ]] && {
        whiptail --title "No Changes" --msgbox "No files were found with the tag '${selected_tag}'. Database remains unchanged." 0 0
        return 0
    }

    # Before updating database, show the candidates for update:
    local key
    local entries_str=""

    # Loop through the keys and format each line
    for key in "${!updated_entries[@]}"; do
        entries_str+="$key New:${updated_entries[$key]}\n"
    done

    # Inform user of candidates for update
    local tempfile=$(mktemp)
    printf "%b" "$entries_str" > "$tempfile"
    whiptail --scrolltext --title "ATTENTION Candidates For Tag '${selected_tag}' Removal" --textbox "$tempfile" 20 80
    rm -f "$tempfile"

    # Confirmation dialog
    whiptail --title "Confirm Update" --yesno \
"We have ${#updated_entries[@]} entries that will be modified. \
If you proceed, all selected entries will have the tag '${selected_tag}' removed. Update database?" \
0 0

    [[ $? -ne 0 ]] && {
        whiptail --title "Error" --msgbox "User cancelled. Database has not been modified." 0 0
        return 1
    }

    # Update EBOOKS_DB
    local tmpfile=$(mktemp) || return 1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        IFS='|' read -r path tags <<< "$line"
        if [[ -v "updated_entries[$path]" ]]; then
            echo "$path|${updated_entries[$path]}" >> "$tmpfile"
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$EBOOKS_DB"

    # Replace original file with updated version
    mv -- "$tmpfile" "$EBOOKS_DB"

    # Final message
    whiptail --title "Bulk Update Finished" --msgbox \
"Bulk files have been dissociated from the tag '${selected_tag}'." 0 0
}

# Remove files in bulk.
remove_files_in_bulk() {
    # Initial message
    whiptail --title "DANGER: Bulk File Removal" --msgbox \
"This feature lets you remove multiple files from the database in bulk. Selected entries will be permanently removed from the database." 10 60

    # Read bulk entries
    local tempfile=$(mktemp) || return 1

    build_bulk > "$tempfile" || {
        whiptail --title "Error" --msgbox "User cancelled." 0 0
        return 1
    }

    local bulk
    mapfile -d '' bulk < "$tempfile"
    rm -f "$tempfile"

    # Extract paths from bulk entries
    declare -A paths_to_remove
    for entry in "${bulk[@]}"; do
        IFS='|' read -r path _ <<< "$entry"
        paths_to_remove["$path"]=1
    done

    # Check if any paths were selected
    [[ ${#paths_to_remove[@]} -eq 0 ]] && {
        whiptail --title "Error" --msgbox "No files selected for removal." 0 0
        return 1
    }

    # Confirmation dialog
    whiptail --title "Confirm Removal" --yesno \
"About to remove ${#paths_to_remove[@]} entries from the database. This operation cannot be undone!\n\nProceed with deletion?" \
0 0

    [[ $? -ne 0 ]] && {
        whiptail --title "Cancelled" --msgbox "Database remains unchanged. No files were removed." 0 0
        return 1
    }

    # Process database file
    local tmpfile=$(mktemp) || return 1
    local removed_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        IFS='|' read -r path _ <<< "$line"
        if [[ -v paths_to_remove["$path"] ]]; then
            ((removed_count++))
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$EBOOKS_DB"

    # Handle actual removals
    if (( removed_count > 0 )); then
        mv -- "$tmpfile" "$EBOOKS_DB"
        whiptail --title "Removal Complete" --msgbox \
"Successfully removed $removed_count entries from the database." 0 0
    else
        rm -f "$tmpfile"
        whiptail --title "No Changes" --msgbox \
"No matching entries found in the database. No files were removed." 0 0
    fi
}

# Search each line in $EBOOKS_DB for broken entries and remove them.
remove_broken_entries() { 
  # Initial information
  whiptail --title "Remove Broken Entries" --msgbox \
"This feature allows you to fix the database file by finding and removing broken entries (ie. paths to files that point to non-existent files)." 10 78

  # Check if the EBOOKS_DB variable is set and file exists.
  if [ -z "$EBOOKS_DB" ] || [ ! -f "$EBOOKS_DB" ]; then
    whiptail --msgbox "EBOOKS_DB is not set or the file does not exist." 8 78
    return 1
  fi

  # Declare an array to hold conflicting (broken) entries.
  local conflicting_entries=()

  # Process each line in the database.
  while IFS= read -r line; do
    # Retrieve the file path (everything before the first |)
    local filepath="${line%|*}"
    # Check if the file exists.
    if [ ! -f "$filepath" ]; then
      conflicting_entries+=("$line")
    fi
  done < "$EBOOKS_DB"

  # If no broken entries were found, inform the user.
  if [ ${#conflicting_entries[@]} -eq 0 ]; then
    whiptail --msgbox "There are no broken entries in the database." 8 78
    return 0
  fi

  # Prepare a message listing all broken entries.
  local message="${#conflicting_entries[@]} broken entries found:\n"
  for entry in "${conflicting_entries[@]}"; do
    message+="$entry\n"
  done

  # Inform the user about the conflicting lines.
  whiptail --msgbox "$message" 20 78

  # Confirm deletion with the user.
  if whiptail --yesno "Do you want to proceed with deletion of ${#conflicting_entries[@]} conflicting entries?" 8 78; then
    # Create a temporary file.
    local tmp_file
    tmp_file=$(mktemp) || { whiptail --msgbox "Failed to create temporary file." 8 78; return 1; }

    # Write back only the valid entries.
    while IFS= read -r line; do
      local found=0
      for broken in "${conflicting_entries[@]}"; do
        if [ "$line" = "$broken" ]; then
          found=1
          break
        fi
      done
      if [ $found -eq 0 ]; then
        echo "$line" >> "$tmp_file"
      fi
    done < "$EBOOKS_DB"

    # Replace the original database with the filtered version.
    mv "$tmp_file" "$EBOOKS_DB"
    
    # Inform the user that deletion is complete.
    whiptail --msgbox "Deletion of ${#conflicting_entries[@]} conflicting entries has completed." 8 78
  else
    whiptail --msgbox "No entries were deleted." 8 78
  fi
}

# Lookup by choosing a file path from registered files first.
lookup_by_filepath() {
    # Initial message.
    whiptail --title "Lookup By File Path" --msgbox \
"This feature allows you to query files by first choosing a file path among registered files:\n\
After choosing a path from the list, you can further narrow the search by both file name(boolean pattern) and tag(literal substring match)." 20 80

    # First, choose the path among registered files.

    # Extract unique directories (full path minus file name) from ebooks.db
    local dirs
    dirs=$(cut -d'|' -f1 "${EBOOKS_DB}" | sed -E 's:/[^/]+$::' | sort | uniq)

    # Build menu items for whiptail (each item appears as "tag description")
    local menu_items=()
    while IFS= read -r dir; do
        menu_items+=( "$dir" " " )
    done <<< "$dirs"

    # Prompt user to choose a directory with whiptail
    local choice
    choice=$(whiptail --title "Select Directory" --menu "Choose a directory for registered files:" 20 170 10 "${menu_items[@]}" 3>&1 1>&2 2>&3)

    # If user cancels, exit the function
    if [ $? -ne 0 ]; then
        whiptail --msgbox "User canceled." 8 60
        return 1
    fi

    # Display all lines in ebooks.db that match the chosen directory
    local matching_files_in_chosen_dir="$(grep -E "^${choice}/[^/]+\|" "${EBOOKS_DB}")"

    # Now, get from user pattern and tag_pattern to further narrow the search.
    # Show boolean pattern help information
    whiptail --scrolltext --title "Boolean pattern for searching files" --msgbox \
    "Boolean Pattern HELP:\n\n\
Boolean patterns are used here only for FILE PATTERNS, not tag patterns.\n\
The pattern is similar to globbing in that pattern consists of (,),&&,||,*. It is NOT regex.\n\
We group patterns with ( and ). && is AND and || is OR. * is wildcard. ! is not supported yet.\n\
Don't include spaces between primary patterns ie. *programming*&&*.pdf not *programming* && *.pdf.\n\n\
Searches are case insensitive.\n\n\
Some examples:\n\
1. (*.pdf||*.epub)&&*schaum*\n\
Search pdf or epub containing 'schaum' in their file name.\n\
2. *.pdf&&*dover*\n\
Search pdf files with 'dover' in their file name.\n\
3. *.pdf||*.epub||*.txt\n\
Search for pdf or epub or txt files.\n\
4. (*linear algebra*&&*schaum*&&*.pdf)||(*dover*&&*linear algebra*&&*.epub)\n\
Search pdf files containing both 'linear algebra' and 'schaum' in their file names OR epub files containing \
'dover' and 'linear algebra' in their file names." 20 80

    local pattern regex filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter boolean pattern for file names (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"

    # DEBUG - if need be save to a temp file perhaps?
    #echo pattern: >&2
    #echo "$pattern" >&2

    # Convert pattern to regex using your existing parse_expr function
    regex=$(parse_expr "$pattern")

    # DEBUG
    #echo regex: >&2
    #echo "$regex" >&2

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file path part is considered (everything before the |)
    filtered_paths="$(cut -d'|' -f1 <(echo "$matching_files_in_chosen_dir") | grep -iP "$regex")"

    if [ -z "$filtered_paths" ]; then
        whiptail --msgbox "No files match the given file name pattern." 8 60
        return 1
    fi

    filtered_lines=$(grep -F -f <(echo "$filtered_paths" | sed 's/$/|/') "$EBOOKS_DB")

    # DEBUG
    #echo filtered lines:
    #echo "$filtered_lines"
    #exit 1

    # Tag pattern info. Inform user that tag patterns is not regex or globbing but simple substring match.
    whiptail --title "IMPORTANT NOTE about Tag Patterns" --msgbox \
    "You are about to provide value for a tag pattern. Remember that it is not regex or globbing but simple substring match.\n\
This means if you enter '*schaum*' \\* will be matched literally not as wildcard." 12 60

    # Step 2: Ask the user for a tag search pattern
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (if empty wildcard):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to .*
    tag_pattern="${tag_pattern:-.*}"

    # Further filter the lines by matching the tag pattern (which appears after the |)
    final_list=$(echo "$filtered_lines" | grep -iP "\|.*$tag_pattern")

    # DEBUG
    #echo final list
    #echo "$final_list"
    #exit 1

    if [ -z "$final_list" ]; then
        whiptail --msgbox "No files match the given tag pattern." 8 60
        return 1
    fi

    in_operation_msg # show 'in operation...' while building menu items...

    local menu_items=()
    local idx=1
    declare -A line_map
    # Build the menu items array. Each menu entry is a pair:
    # the index number and a description (file path with tags)
    while IFS= read -r line; do
        # Replace the | separator with a more readable format for display.
        menu_items+=("$idx" "$(echo "$line")")
        line_map["$idx"]="$line"
        idx=$((idx + 1))
    done <<< "$final_list"

    # menu_items need truncating. the format is "idx#" "full path including tags"
    # Build the large list once:
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_lookup "${menu_items[@]}" | sed 's/\x1E$//')

    # Reset CURRENT_PAGE for this new TRUNC array.
    CURRENT_PAGE=0

    # Step 3: Loop to show the final list in a whiptail menu repeatedly
    while true; do
        # then paginate it.
        paginate

        if [ $? -ne 0 ]; then
            break
        fi

        # Display the whiptail menu.
        local selection
        selection="$SELECTED_ITEM"

        # Retrieve and display the selected file (full line with path and tags)
        local selected_line="${line_map[$selection]}"

        # Truncate whiptail title.
        local whip_title="Matching file in ${choice}/:"
        if [ ${#whip_title} -gt 50 ]; then
            whip_title="${whip_title:0:50}..."
        fi

        # Format file info and display it.
        local formatted_str="$(format_file_info "$selected_line")"
        whiptail --scrolltext --title "$whip_title" --msgbox "$formatted_str" 20 80
    done
}

# Open file by first selecting its file path and matching by file name pattern and tag pattern.
open_file_by_filepath() {
    # Initial message.
    whiptail --title "Open File By File Path" --msgbox \
"This feature allows you to open a registered file by first choosing a file path from registered files:\n\
After choosing a path from the list, you can further narrow the search by both file name(boolean pattern) and tag(literal substring match).\n\
Then, you can selected to open a file item." 20 80

    # First, choose the path among registered files.

    # Extract unique directories (full path minus file name) from ebooks.db
    local dirs
    dirs=$(cut -d'|' -f1 "${EBOOKS_DB}" | sed -E 's:/[^/]+$::' | sort | uniq)

    # Build menu items for whiptail (each item appears as "tag description")
    local menu_items=()
    while IFS= read -r dir; do
        menu_items+=( "$dir" " " )
    done <<< "$dirs"

    # Prompt user to choose a directory with whiptail
    local choice
    choice=$(whiptail --title "Select Directory" --menu "Choose a directory for registered files:" 20 170 10 "${menu_items[@]}" 3>&1 1>&2 2>&3)

    # If user cancels, exit the function
    if [ $? -ne 0 ]; then
        whiptail --msgbox "User canceled." 8 60
        return 1
    fi

    # Display all lines in ebooks.db that match the chosen directory
    local matching_files_in_chosen_dir="$(grep -E "^${choice}/[^/]+\|" ${EBOOKS_DB})"

    # Now, get from user pattern and tag_pattern to further narrow the search.
    # Show boolean pattern help information
    whiptail --scrolltext --title "Boolean pattern for searching files" --msgbox \
    "Boolean Pattern HELP:\n\n\
Boolean patterns are used here only for FILE PATTERNS, not tag patterns.\n\
The pattern is similar to globbing in that pattern consists of (,),&&,||,*. It is NOT regex.\n\
We group patterns with ( and ). && is AND and || is OR. * is wildcard. ! is not supported yet.\n\
Don't include spaces between primary patterns ie. *programming*&&*.pdf not *programming* && *.pdf.\n\n\
Searches are case insensitive.\n\n\
Some examples:\n\
1. (*.pdf||*.epub)&&*schaum*\n\
Search pdf or epub containing 'schaum' in their file name.\n\
2. *.pdf&&*dover*\n\
Search pdf files with 'dover' in their file name.\n\
3. *.pdf||*.epub||*.txt\n\
Search for pdf or epub or txt files.\n\
4. (*linear algebra*&&*schaum*&&*.pdf)||(*dover*&&*linear algebra*&&*.epub)\n\
Search pdf files containing both 'linear algebra' and 'schaum' in their file names OR epub files containing \
'dover' and 'linear algebra' in their file names." 20 80

    local pattern regex filtered_paths filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter boolean pattern for file names (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"

    # DEBUG - if need be save to a temp file perhaps?
    #echo pattern: >&2
    #echo "$pattern" >&2

    # Convert pattern to regex using your existing parse_expr function
    regex=$(parse_expr "$pattern")

    # DEBUG
    #echo regex: >&2
    #echo "$regex" >&2

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file path part is considered (everything before the |)
    filtered_paths="$(cut -d'|' -f1 <(echo "$matching_files_in_chosen_dir") | grep -iP "$regex")"

    if [ -z "$filtered_paths" ]; then
        whiptail --msgbox "No files match the given file name pattern." 8 60
        return 1
    fi

    filtered_lines=$(grep -F -f <(echo "$filtered_paths" | sed 's/$/|/') "$EBOOKS_DB")

    # DEBUG
    #echo filtered lines:
    #echo "$filtered_lines"
    #exit 1

    # Tag pattern info. Inform user that tag patterns is not regex or globbing but simple substring match.
    whiptail --title "IMPORTANT NOTE about Tag Patterns" --msgbox \
    "You are about to provide value for a tag pattern. Remember that it is not regex or globbing but simple substring match.\n\
This means if you enter '*schaum*' \\* will be matched literally not as wildcard." 12 60

    # Step 2: Ask the user for a tag search pattern
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (if empty wildcard):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to .*
    tag_pattern="${tag_pattern:-.*}"

    # Further filter the lines by matching the tag pattern (which appears after the |)
    final_list=$(echo "$filtered_lines" | grep -iP "\|.*$tag_pattern")

    # DEBUG
    #echo final list
    #echo "$final_list"
    #exit 1

    if [ -z "$final_list" ]; then
        whiptail --msgbox "No files match the given tag pattern." 8 60
        return 1
    fi

    in_operation_msg # show 'in operation...' while building menu items...

    local menu_items=()
    local idx=1
    declare -A line_map
    # Build the menu items array. Each menu entry is a pair:
    # the index number and a description (file path with tags)
    while IFS= read -r line; do
        # Replace the | separator with a more readable format for display.
        menu_items+=("$idx" "$(echo "$line")")
        line_map["$idx"]="$line"
        idx=$((idx + 1))
    done <<< "$final_list"

    # menu_items need truncating. the format is "idx#" "full path including tags"
    # Build the large list once:
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_lookup "${menu_items[@]}" | sed 's/\x1E$//')

    # Reset CURRENT_PAGE for this new TRUNC array.
    CURRENT_PAGE=0

    # Step 3: Loop to show the final list in a whiptail menu repeatedly
    while true; do
        # then paginate it.
        paginate

        if [ $? -ne 0 ]; then
            break
        fi

        # Display the whiptail menu.
        local selection
        selection="$SELECTED_ITEM"
        
        # First, check line_map[$selection] is set.
        [[ ! -v line_map[$selection] ]] && whiptail --msgbox "File entry not found." 20 80 && return 1
        
        # Retrieve and display the selected file (full line with path and tags delimited by |)
        local selected_line="${line_map[$selection]}"
        
        # Retrieve full file path portion first.
        local file="$(echo "$selected_line" | cut -d'|' -f1)"
        
        # Open selected file.
        open_file "$file" || whiptail --msgbox "Error opening file: ${file}." 20 80
    done
}

# Manage eBooks menu
show_ebooks_menu() {
    local SUBCHOICE FILE_OPTION TAG_OPTION SEARCH_OPTION OPEN_OPTION MAINTENANCE_OPTION

    while true; do
        SUBCHOICE=$(whiptail --title "BABYRUS ${BABYRUS_VERSION}" --cancel-button "Back" --menu "Categories: Manage eBooks" 15 50 6 \
            "1" "File Management" \
            "2" "Tag Management" \
            "3" "Search & Lookup" \
            "4" "Open & Read" \
            "5" "Maintenance & Backup" 3>&1 1>&2 2>&3)

        # Exit if user presses Cancel or Esc
        [ $? -ne 0 ] && break

        case "$SUBCHOICE" in
            "1")
                # File Management submenu: Items 1, 3, and 13
                FILE_OPTION=$(whiptail --title "File Management" --cancel-button "Back" --menu "Select an option" 15 50 6 \
                    "1" "Add Files In Bulk" \
                    "2" "Register eBook" \
                    "3" "Remove Registered eBook" \
                    "4" "Remove Files In Bulk" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$FILE_OPTION" in
                    "1") add_files_in_bulk ;;
                    "2") register_ebook ;;
                    "3") remove_registered_ebook ;;
                    "4") remove_files_in_bulk ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "2")
                # Tag Management submenu: Items 4, 7, 11, and 12
                TAG_OPTION=$(whiptail --title "Tag Management" --cancel-button "Back" --menu "Select an option" 15 50 6 \
                    "1" "Register Tag" \
                    "2" "Associate Tag with eBook" \
                    "3" "Associate Tag to Bulk" \
                    "4" "Dissociate Tag from Registered eBook" \
                    "5" "Dissociate Tag from Bulk" \
                    "6" "Delete Tag From Global List" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$TAG_OPTION" in
                    "1") register_tag ;;
                    "2") associate_tag ;;
                    "3") assoc_tag_to_bulk ;;
                    "4") dissociate_tag_from_registered_ebook ;;
                    "5") dissoc_tag_to_bulk ;;
                    "6") delete_tag_from_global_list ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "3")
                # Search & Lookup submenu: Items 2, 10, 8, and 9
                SEARCH_OPTION=$(whiptail --title "Search & Lookup" --cancel-button "Back" --menu "Select an option" 15 50 6 \
                    "1" "Lookup Registered Files" \
                    "2" "Search by eBook by Tag" \
                    "3" "Lookup By Filepath" \
                    "4" "View All Registered eBooks" \
                    "5" "View All Registered Tags" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$SEARCH_OPTION" in
                    "1") lookup_registered_files ;;
                    "2") search_tags ;;
                    "3") lookup_by_filepath ;;
                    "4") view_ebooks ;;
                    "5") view_tags ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "4")
                # Open & Read submenu: Items 5 and 6
                OPEN_OPTION=$(whiptail --title "Open & Read" --cancel-button "Back" --menu "Select an option" 15 50 4 \
                    "1" "Open eBook Search by Filename" \
                    "2" "Open eBook Search by Tag" \
                    "3" "Open File by File Path" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$OPEN_OPTION" in
                    "1") open_file_search_by_filename ;;
                    "2") open_file_search_by_tag ;;
                    "3") open_file_by_filepath ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "5")
                # Open & Read submenu: Items 5 and 6
                MAINTENANCE_OPTION=$(whiptail --title "Open & Read" --cancel-button "Back" --menu "Select an option" 15 50 3 \
                    "1" "Find Remove Broken Entries" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$MAINTENANCE_OPTION" in
                    "1") remove_broken_entries ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            *)
                whiptail --msgbox "Invalid Category" 8 40
                ;;
        esac
    done
}

MAIN_MENU_STR="'Taking a first step towards achievement.'

Copyleft February, March 2025 by ${BABYRUS_AUTHOR}. Feel free to share and modify."

# Main menu function
show_main_menu() {
    while true; do
        choice=$(whiptail --title "BABYRUS ${BABYRUS_VERSION} Main Menu" --cancel-button "Exit" --menu "$MAIN_MENU_STR" 20 50 5 \
            "eBooks" "Manage eBooks" \
            "Notes" "Manage Notes" \
            "Goals" "Manage Goals" \
            3>&1 1>&2 2>&3)

        if [ $? != 0 ]; then
            exit 0
        fi

        case $choice in
            "eBooks")
                show_ebooks_menu
                ;;
            "Notes")
                # Add your Notes menu handling here
                ;;
            "Goals")
                # Add your Goals menu handling here
                ;;
        esac
    done
}

show_main_menu
