#!/bin/bash

# Database files
EBOOKS_DB="ebooks.db"  # Format: "path|tag1,tag2,..."
TAGS_DB="tags.db"      # Format: "tag"

# Ensure databases exist
touch "$EBOOKS_DB" "$TAGS_DB"

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
            entries+=("$entry" "$(basename "$entry")")
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
	echo selected_path: "$selected_path" >&2

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
	    
	    # Print the element followed by null character (without a newline)
	    printf "%s\x1E" "$element"
	    
	    # After every second element, print a newline
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
    local max_length=85

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
    local max_length=50  # Ensures final string is ≤ 50 chars

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

# debug
#a="$(printf 'a%.0s' {1..55})"
#b="$(printf 'b%.0s' {1..55})"
#c='ccc'
#test_arr=("$a" 'a' "$b" 'b' "$c" 'c')
#echo generate_trunc: >&2
#generate_trunc "${test_arr[@]}" | cat -v >&2

#############################################################################
# NEED FIX!!!
# - the code breaks if there is no match in find [fixed]
# - handle cases where cancel is selected from whiptail menu [fixed]
# - modify truncation logic for dirname and basename. [fixed]
# - list hidden directories as well when navigating. [fixed]
# - display waiting infobox when operation takes time (such as find) [fixed]
# - WHAT IF file name contains | character?
# - paginate if file list too long.
#############################################################################

paginate() {
    local chunk_size=200
    # Populate array 'trunc' with all the passed arguments
    local trunc=("$@")
    
    # Calculate total pages (rounding up for any remainder)
    local total_pages=$(( (${#trunc[@]} + chunk_size - 1) / chunk_size ))
    local current_page=0
    local choice=""
    
    while true; do
        # Determine start index for current page
        local start=$(( current_page * chunk_size ))
        
        # Extract current chunk of items
        local current_chunk=("${trunc[@]:$start:$chunk_size}")
        
        # Build navigation options
        local menu_options=()
        
        # Add "previous page" if not on the first page
        if (( current_page > 0 )); then
            menu_options+=("previous page" " ")
        fi
        
        # Add "next page" if not on the last page
        if (( current_page < total_pages - 1 )); then
            menu_options+=("next page" " ")
        fi
        
        # Append the items for the current page
        menu_options+=("${current_chunk[@]}")
        
        # Display the whiptail menu
        choice=$(whiptail --title "Paged Menu" \
            --menu "Choose an item (Page $((current_page + 1))/$total_pages)" \
            20 170 10 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3)
        
        # If the user cancels or presses Esc, exit the loop
        if [ $? -ne 0 ]; then
            break
        fi
        
        # Process the user's selection
        case "$choice" in
            "previous page")
                (( current_page-- ))
                ;;
            "next page")
                (( current_page++ ))
                ;;
            *)
                # If an actual item was selected, exit the loop
                break
                ;;
        esac
    done
    
    # Output the final choice
    echo "$choice"
}

# Example usage:
# result=$(paginate "Item 1" "Item 2" "Item 3" "Item 4" "Item 5")
# echo "Selected: $result"

register_ebook() {
    # Get search string for files
    search=$(whiptail --inputbox "Enter search string to look for ebook files:" 8 40 3>&1 1>&2 2>&3)
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
    echo "search: " "$search" >&2
    echo "search_path: " "$search_path" >&2

    # in operation... message
    in_operation_msg

    run_find="$(find "$search_path" -type f -iname "*$search*" -exec sh -c 'printf "%s\036%s\036" "$1" "$(basename "$1")"' sh {} \;)"
    run_find="${run_find%$'\x1E'}"      # Remove any trailing delimiter.

    # clear screen, maybe?
    #clear

    # Check if run_find is empty so we can cancel.
    if [ -z "$run_find" ]; then
        whiptail --title "No Matches Found" --msgbox "Find found no matches" 8 45
        return 1  # Exit the function.
    fi

    IFS=$'\x1E' read -r -a filtered <<< "$run_find"

    # debug
    echo "filtered: " "${filtered[*]}" >&2
    echo "filtered length: " "${#filtered[*]}" >&2

    # shortened filtered output with line numbers:
    # shorten the dirname if its length is greater than 50.
    mapfile -d $'\x1e' -t trunc < <(generate_trunc "${filtered[@]}" | sed 's/\x1E$//')

    # debug
    echo "trunc: " "${trunc[@]}" >&2
    echo "trunc length: " "${#trunc[*]}" >&2

    selected_trunc="$(paginate "${trunc[@]}")"
    # debug
    echo selected_trunc:
    echo "$selected_trunc"
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
    echo "selected_trunc: " "$selected_trunc" >&2
    echo "n: " "$n" >&2
    echo "m: " "$m" >&2

    # Remember we want filtered[m-1].
    selected="${filtered[$((m - 1))]}"

    #debug
    echo "selected: " "$selected" >&2

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

# debug
#exit

associate_tag() {
    # Get list of ebooks
    mapfile -t ebooks < <(cut -d'|' -f1 "$EBOOKS_DB")
    if [[ ${#ebooks[@]} -eq 0 ]]; then
        whiptail --msgbox "No ebooks registered!" 8 40
        return
    fi

    # convert ebooks array into whiptail friendly format.
    mapfile -d $'\x1e' -t ebooks_whip < <(make_into_pairs "${ebooks[@]}")

    # Select ebook
    ebook=$(whiptail --menu "Choose an ebook:" 20 170 10 \
        "${ebooks_whip[@]}" 3>&1 1>&2 2>&3)				# remember whiptail menu items must come in pairs!!!!
    if [[ $? -ne 0 ]]; then return; fi
    
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
    
    whiptail --msgbox "Tag '$tag' added to '$ebook!'" 8 40
}

view_ebooks() {
    whiptail --textbox "$EBOOKS_DB" 20 60
}

view_tags() {
    whiptail --textbox "$TAGS_DB" 20 60
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
        echo "$result" > /tmp/search_result.txt
        whiptail --textbox /tmp/search_result.txt 20 60
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
        menu_items+=("$path" "[$tags]")
    done

    # First selection: Choose ebook
    local selected_ebook
    selected_ebook=$(whiptail --title "Select eBook" --menu "Choose eBook to edit tags:" \
        20 80 0 "${menu_items[@]}" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 0  # User canceled

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
    whiptail --yesno "Remove tag '$selected_tag' from:\n$selected_ebook?" 10 60 || return 0

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
    whiptail --msgbox "Tag '$selected_tag' removed from '$selected_ebook'!" 8 40
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
        whiptail --msgbox "$message" 20 60
        return 1
    fi

    # Final confirmation
    whiptail --yesno "Permanently delete tag:\n'$selected_tag'?" 10 40 || return 0

    # Delete from tags database
    grep -Fx -v -- "$selected_tag" "$TAGS_DB" > "$TAGS_DB.tmp" && mv -f "$TAGS_DB.tmp" "$TAGS_DB"
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

    # Show selection dialog
    local selected_path
    selected_path=$(whiptail --title "Remove Ebook" --menu "\nChoose an ebook to remove:" 20 170 10 \
        "${menu_items[@]}" 3>&1 1>&2 2>&3)

    # Exit if user canceled
    [ $? -ne 0 ] && return 1

    # Show confirmation dialog
    whiptail --title "Confirm Removal" --yesno "Are you sure you want to remove:\n$selected_path" 10 60 \
        --yes-button "Remove" --no-button "Cancel" 3>&1 1>&2 2>&3

    # Proceed with removal if confirmed
    if [ $? -eq 0 ]; then
        # Create temporary file
        local temp_file
        temp_file=$(mktemp)

        # Remove entry and preserve other entries
        awk -v path="$selected_path" -F'|' '$1 != path' "$EBOOKS_DB" > "$temp_file"
        mv "$temp_file" "$EBOOKS_DB"

        whiptail --title "Success" --msgbox "'${selected_path}' removed successfully!" 10 60
    fi
}

#############################################################################################################################
# TODO:
# - testing of new code not done. [fixed]
# - fix whip menu items not in pairs. [fixed]
# - view all registered tags. [fixed]
# - delete tag from global list. [fixed]
# - if a tag is deleted from global list what to do with ebook entry that has that tag? [fixed]
#	- i think if there is a registered book already associated with that tag we should prevent deletion
#	of that tag from global list until that book is deassociated.
# - deassociate tag from a registered ebook. [fixed]
# - list registered ebooks and when chosen open the file with external application.
# - delete registered ebook (ie. remove from $EBOOKS_DB).
# - aesthetics.
# - construct main menu. [fixed]
#############################################################################################################################

while true; do
    choice=$(whiptail --title "BABYRUS v.1" --menu "Main Menu" 25 50 10 \
	"1" "Register eBook" \
        "2" "Register Tag" \
        "3" "Associate Tag with eBook" \
        "4" "View All eBooks" \
	"5" "View All Tags" \
        "6" "Search by eBook by Tag" \
	"7" "Dissociate Tag from Registered eBook" \
	"8" "Delete Tag From Global List" \
	"9" "Remove Registered eBook" \
        "10" "Exit" 3>&1 1>&2 2>&3)
    
    case $choice in
	1) register_ebook ;;
        2) register_tag ;;
        3) associate_tag ;;
        4) view_ebooks ;;
	5) view_tags ;;
        6) search_tags ;;
	7) dissociate_tag_from_registered_ebook ;;
	8) delete_tag_from_global_list ;;
	9) remove_registered_ebook ;;
        10) exit 0 ;;
        *) exit 1 ;;
    esac
done
