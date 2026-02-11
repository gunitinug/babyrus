#!/bin/bash
# babyrus - A terminal productivity tool.
# Copyright (C) 2025, 2026 Logan Lee
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

BABYRUS_VERSION='v.0.99ww'
BABYRUS_AUTHOR='Logan Lee'

BABYRUS_PATH="$(pwd)"
NOTES_PATH="${BABYRUS_PATH}/notes"
NOTES_METADATA_PATH="${NOTES_PATH}/metadata"
NOTES_DB="${NOTES_METADATA_PATH}/notes.db"
NOTES_TAGS_DB="${NOTES_METADATA_PATH}/notes-tags.db"
NOTES_EBOOKS_DB="${NOTES_METADATA_PATH}/notes-ebooks.db"
EBOOKS_DB="${BABYRUS_PATH}/ebooks.db"
EBOOKS_DB_BACKUP="${BABYRUS_PATH}/ebooks.db.backup"
EBOOKS_DB_RENAME_LOG="${BABYRUS_PATH}/ebooks.db.rename.log"
TAGS_DB="${BABYRUS_PATH}/tags.db"
PROJECTS_PATH="${BABYRUS_PATH}/projects"
PROJECTS_METADATA_PATH="${PROJECTS_PATH}/metadata"
PROJECTS_DB="${PROJECTS_METADATA_PATH}/projects.db"
PROJECTS_DB_SHORTLISTED="${PROJECTS_METADATA_PATH}/projects.db.shortlisted"
PROJECTS_DB_SHORTLISTED_HISTORY="${PROJECTS_METADATA_PATH}/projects.db.shortlisted.history"
URLS_PATH="${BABYRUS_PATH}/urls"
URLS_DB="${URLS_PATH}/urls.db"

enforce_touch_files() (
  # run in a subshell so set -euo pipefail won't persist outside the function
  set -euo pipefail

  local files=(
    "$EBOOKS_DB"
    #"$EBOOKS_DB_RENAME_LOG"
    "$TAGS_DB"
    "$NOTES_DB"
    "$NOTES_EBOOKS_DB"
    "$NOTES_TAGS_DB"
    "$PROJECTS_DB"
    "$PROJECTS_DB_SHORTLISTED"
    "$PROJECTS_DB_SHORTLISTED_HISTORY"
    "$URLS_DB"
  )

  for f in "${files[@]}"; do
    # create parent dir if needed, then touch the file
    mkdir -p "$(dirname -- "$f")"
    touch -- "$f"
  done

  return 0
)

# An artifact to keep to avoid error
SHORTLISTED_HISTORY="${BABYRUS_PATH}/projects/metadata/projects.db.shortlisted.history"

# Make sure all required directories and files are present.
enforce_touch_files

# DO NOT DELETE OR ALTER BETWEEN THESE MARKERS(INCLUDING MARKERS)!!!
#+++ CONFIGURATION +++#
# Tweak this to set external apps.
declare -A EXTENSION_COMMANDS=(
    ["txt"]="gnome-text-editor"
    ["pdf"]="zathura"
    ["epub"]="okular"
    ["mobi"]="okular"
    ["azw3"]="okular"
)

# Tweak these to set external apps for other sections.
DEFAULT_EDITOR="nano" # runs in the same terminal as babyrus.
URL_BROWSER="google-chrome"
#+++ CONFIGURATION END +++#

# ADD COMMANDS FOR VIEWERS.
declare -A VIEWER_COMMANDS=(
    # PDF viewers
    ["evince"]="evince -p"
    ["okular"]="okular -p"
    ["zathura"]="zathura -P"
    ["mupdf"]="mupdf"
    ["qpdfview"]="qpdfview"

    # EPUB/MOBI/AZW3 viewers
    ["calibre"]="ebook-viewer --open-at"    
)

# Function to edit configuration using whiptail
edit_configuration() {
    local config_file="${BABYRUS_PATH}/babyrus.sh"
    local backup_file="${config_file}.bak"
    local temp_file=$(mktemp)

    # Reload configuration from file before making changes
    source <(sed -n '/^#+++ CONFIGURATION +++#$/,/^#+++ CONFIGURATION END +++#$/{//!p}' "$config_file")

    # --- Make a local backup in memory ---
    local -A BACKUP_EC
    for key in "${!EXTENSION_COMMANDS[@]}"; do
        BACKUP_EC["$key"]="${EXTENSION_COMMANDS[$key]}"
    done
    # --- Also env variables ---
    local BACKUP_DE="$DEFAULT_EDITOR"
    local BACKUP_UB="$URL_BROWSER"

    # Create ordered list of extensions for consistent display
    local ordered_exts=("txt" "pdf" "epub" "mobi" "azw3")

    while true; do
        # Build menu options
        local options=()
        for ext in "${ordered_exts[@]}"; do
            options+=("${ext}" "${EXTENSION_COMMANDS[$ext]}")
        done
        options+=("DEFAULT_EDITOR" "${DEFAULT_EDITOR}")
        options+=("URL_BROWSER" "${URL_BROWSER}")
        options+=("Save" "Save changes")

        local choice
        choice=$(whiptail --title "Set Default Apps" --menu \
            "Choose a setting to modify:" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        # Cancel pressed
        [[ $? -ne 0 ]] && {
            # --- Revert EXTENSION_COMMANDS and env variables from local backup ---
            for key in "${!BACKUP_EC[@]}"; do
                EXTENSION_COMMANDS["$key"]="${BACKUP_EC[$key]}"
            done
            DEFAULT_EDITOR="$BACKUP_DE"            
            URL_BROWSER="$BACKUP_UB"
            return 1
        }

        local current_value
        local new_value
        case "$choice" in
            DEFAULT_EDITOR|URL_BROWSER)
                current_value="${!choice}"
                new_value=$(whiptail --inputbox "Enter new value for ${choice}:" \
                    10 60 "${current_value}" 3>&1 1>&2 2>&3)
                [[ $? -eq 0 ]] && [[ -n "$new_value" ]] && declare "${choice}=${new_value}"
                ;;
            "Save")
                break
                ;;
            *)
                current_value="${EXTENSION_COMMANDS[$choice]}"
                new_value=$(whiptail --inputbox "Enter new command for .${choice}:" \
                    10 60 "${current_value}" 3>&1 1>&2 2>&3)

                local s_=$?

                [[ $s_ -ne 0 ]] && continue   # user pressed Cancel

                new_value=$(echo "$new_value" | xargs)  # trim spaces

                if [[ ! -v VIEWER_COMMANDS[$new_value] ]]; then
                    whiptail --title "Alert" \
                            --msgbox "${new_value} command is currently unregistered." 8 50
                    continue
                fi

                [[ -n "$new_value" ]] && EXTENSION_COMMANDS["$choice"]="$new_value"
                ;;
        esac
    done

    # Ask yesno to user.
    whiptail --title "Confirm" --yesno "Are you sure to proceed?" 8 40 || {
        # --- Revert EXTENSION_COMMANDS and env variables from local backup ---
        for key in "${!BACKUP_EC[@]}"; do
            EXTENSION_COMMANDS["$key"]="${BACKUP_EC[$key]}"
        done
        DEFAULT_EDITOR="$BACKUP_DE"            
        URL_BROWSER="$BACKUP_UB"        
        return 1
    }

    # Create backup and update configuration file
    cp "$config_file" "$backup_file" 2>/dev/null || true

    # Generate new configuration block
    local new_config_block="#+++ CONFIGURATION +++#
# Tweak this to set external apps.
declare -A EXTENSION_COMMANDS=(
    [\"txt\"]=\"${EXTENSION_COMMANDS[txt]}\"
    [\"pdf\"]=\"${EXTENSION_COMMANDS[pdf]}\"
    [\"epub\"]=\"${EXTENSION_COMMANDS[epub]}\"
    [\"mobi\"]=\"${EXTENSION_COMMANDS[mobi]}\"
    [\"azw3\"]=\"${EXTENSION_COMMANDS[azw3]}\"
)

# Tweak these to set external apps for other sections.
DEFAULT_EDITOR=\"${DEFAULT_EDITOR}\" # runs in the same terminal as babyrus.
URL_BROWSER=\"${URL_BROWSER}\"
#+++ CONFIGURATION END +++#"

    # DEBUG
    #echo new_config_block: >&2
    #echo "$new_config_block" >&2  

    # Use awk to replace the configuration block
    awk -v new="$new_config_block" '
        !block_processed && /#\+\+\+ CONFIGURATION \+\+\+#/ {
            in_block = 1
            block_processed = 1
            printf "%s\n", new
            next
        }
        in_block && /#\+\+\+ CONFIGURATION END \+\+\+#/ {
            in_block = 0
            next
        }
        !in_block {
            print
        }
    ' "$config_file" > "$temp_file"

    # DEBUG
    #echo temp_file: >&2
    #cat $temp_file >&2
    #exit

    mv "$temp_file" "$config_file"
    chmod +x "$config_file"	# make babyrus.sh executable again.
    whiptail --title "Info" --msgbox "Settings saved. Restart BABYRUS to take effect." 8 40
}

# Create notes directories if not created
mkdir -p "${NOTES_METADATA_PATH}"

# Create if not existent
touch "$NOTES_DB" "$NOTES_TAGS_DB" "$NOTES_EBOOKS_DB"

# CHECK MINIMUM BASH VERSION 5.2.21
check_bash_ver() {
  # Required version components
  local req_major=5 req_minor=2 req_patch=21

  # Extract current Bash version components
  local cur_major=${BASH_VERSINFO[0]}
  local cur_minor=${BASH_VERSINFO[1]}
  local cur_patch=${BASH_VERSINFO[2]}

  local err_msg="Error: You need bash version at least ${req_major}.${req_minor}.${req_patch}."

  # Compare major version
  if (( cur_major < req_major )); then
    echo "$err_msg" >&2
    return 1
  elif (( cur_major > req_major )); then
    # Any major > 5 is automatically OK
    return 0
  fi

  # At this point cur_major == req_major
  # Compare minor version
  if (( cur_minor < req_minor )); then
    echo "$err_msg" >&2
    return 1
  elif (( cur_minor > req_minor )); then
    # 5.x where x > 2 is OK
    return 0
  fi

  # At this point cur_major == 5 && cur_minor == 2
  # Compare patch version
  if (( cur_patch < req_patch )); then
    echo "$err_msg" >&2
    return 1
  fi

  # If we reach here, version is >= 5.2.21
  return 0
}

check_bash_ver || exit 1

# Check dependencies
for cmd in whiptail wmctrl dialog; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done

# Try to maximize the current terminal window
if ! wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz &> /dev/null; then
    echo "If menu is broken please manually maximise terminal window before running this program." >&2
fi

# Allow a brief pause for the window manager to update the window size
sleep 0.5

# Database files
#EBOOKS_DB="ebooks.db"  # Format: "path|tag1,tag2,..."
TAGS_DB="${BABYRUS_PATH}/tags.db"      # Format: "tag"

# Ensure databases exist
touch "$EBOOKS_DB" "$TAGS_DB"

# Check all specified external apps are found for 'Manage eBooks' section.
for ext in "${!EXTENSION_COMMANDS[@]}"; do
    cmd="${EXTENSION_COMMANDS[$ext]}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Command for .$ext ($cmd) is not found. Modify EXTENSION_COMMANDS accordingly." >&2
        exit 1
    fi
done

# Check if all commands exist for other sections too.
if ! command -v "$DEFAULT_EDITOR" >/dev/null || \
   ! command -v "$URL_BROWSER" >/dev/null; then
    echo "This script requires '${DEFAULT_EDITOR}', '${URL_BROWSER}' in order to run correctly." >&2
    exit 1
fi

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
            entries+=("$entry" "")
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

	#mapfile -t -d $'\x1E' choices < <(printf ":::SELECT:::\x1Eselect\x1E"; list_files "$current_path" "D" | sed 's/\x1E$//')
	# fix here because otherwise $choices array gets last empty element missing
	# so they are no longer in pairs for whiptail menu.
	mapfile -t -d $'\x1E' choices < <(printf ":::SELECT:::\x1Eselect\x1E"; list_files "$current_path" "D")

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
            menu_options+=("previous page" "")
        fi
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("next page" "")
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
    search=$(whiptail --inputbox "Enter search string to look for ebook files (globbing; empty for wildcard):" 10 40 3>&1 1>&2 2>&3)
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

    #run_find="$(find "$search_path" -type f -iname "$search" -exec sh -c 'printf "%s\036%s\036" "$1" "$(basename "$1")"' sh {} \;)" # edited for globbing $search
    run_find="$(find "$search_path" -maxdepth 1 -type f -iname "$search" -exec sh -c 'printf "%s\036%s\036" "$1" "$(basename "$1")"' sh {} \;)" # non-recursive

    #run_find="${run_find%$'\x1E'}"      # Remove any trailing delimiter. (not needed?)

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
    #mapfile -d $'\x1e' -t TRUNC < <(generate_trunc "${filtered[@]}" | sed 's/\x1E$//') # removing trailing RS not needed?
    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc "${filtered[@]}")
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
        #whiptail --title "Register ebook canceled" --msgbox "Canceled by user." 8 45
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
        # debug
        #echo "$selected" >&2
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
        tag=$(whiptail --inputbox "Enter new tag name (no commas , or pipes |):" 8 40 3>&1 1>&2 2>&3)
        if [[ $? -ne 0 ]]; then return; fi

        if [[ -z "$tag" ]]; then
            whiptail --msgbox "Tag name cannot be empty!" 8 40
            continue
        fi

	# Make sure new tag name doesn't contain banned characters: , or |.
        if [[ "$tag" == *","* || "$tag" == *"|"* ]]; then
            whiptail --msgbox "Tag name cannot contain commas (,) or pipes (|)!" 8 50
            continue
        fi
        
#        if [[ "$tag" == *","* ]]; then
#            whiptail --msgbox "Tag name cannot contain commas!" 8 40
#            continue
#        fi
        
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
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    # No point continuing if there's no tag registered!
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
	    #whiptail --title "Alert" --msgbox "No tags db found or is empty! Register at least one tag!" 8 40 >/dev/tty
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
	    return 1
    }

    # NO LONGER NEEDED.
#    # Get list of ebooks
#    mapfile -t ebooks < <(cut -d'|' -f1 "$EBOOKS_DB")
#    if [[ ${#ebooks[@]} -eq 0 ]]; then
#        whiptail --msgbox "No ebooks registered!" 8 40
#        return
#    fi

   [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        #whiptail --title "Alert" --msgbox "No ebooks db found or is empty! Register at least one file!" 8 40 >/dev/tty
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    

    # Get filter string from user using whiptail. No globbing, simple substring match.
    filter_str=$(whiptail --title "Filter eBooks" --inputbox "Enter filter string to narrow search (globbing; empty for wildcard):" 10 40 3>&1 1>&2 2>&3)
    
    # Handle cancel/escape
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Defaults to "*" if unset
    filter_str=${filter_str:-"*"}
    
#    # Filter ebooks and store in array
#    mapfile -d $'\0' filtered_ebooks < <(filter_ebooks "$filter_str" "${ebooks[@]}")
#
#    # Show msgbox and return if filtered_ebooks is empty.
#    [[ "${#filtered_ebooks[@]}" -eq 0  ]] && whiptail --title "Attention" --msgbox "No matches." 10 40 && return
#
#    # convert ebooks array into whiptail friendly format.
#    mapfile -d $'\x1e' -t ebooks_whip < <(make_into_pairs "${filtered_ebooks[@]}")
#
#    # Truncate ebooks_whip because of possible long file names.
#    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_assoc_tag "${ebooks_whip[@]}" | sed 's/\x1E$//')

#    # FIX: SPEED IMPROVEMENT BY POPULATING TRUNC DIRECTLY. ALSO ADD WHIPTAIL GAUGE.
#    local total_lines
#    total_lines=$(wc -l < "$EBOOKS_DB")
#
#    # Make a temporary FIFO and ensure cleanup on exit
#    local fifo
#    fifo="$(mktemp -u --tmpdir gauge.XXXXXX)"
#    mkfifo "$fifo"
#    trap 'rm -f "$fifo"' EXIT
#
#    # Start whiptail reading from the FIFO in background
#    whiptail --gauge "Preparing file list..." 7 60 0 < "$fifo" &
#    local gauge_pid=$!
#    
#    # Open the FIFO for writing on fd 3 (keeps writer open until we close it)
#    exec 3> "$fifo"
#
    TRUNC=()
    local ebooks_whip=()
#    local idx=1 processed=1
#    local path tags dir file truncated_dir truncated_file truncated_tags
#
#    while IFS= read -r line; do
#        [[ -z $line ]] && continue
#    
#        path=${line%|*}
#        tags=${line##*|}
#        dir="$(dirname "$path")"
#        file="$(basename "$path")"
#    
#        if [[ "$filter_str" == "*" || "${file,,}" == *"${filter_str,,}"* ]]; then
#            truncated_dir="$(truncate_dirname "$dir" 35)"
#            truncated_file="$(truncate_filename "$file" 65)"
#            truncated_tags="$(truncate_tags "$tags")"
#            
#            ebooks_whip+=("$path" "")
#            TRUNC+=("${idx}:${truncated_dir}/${truncated_file}" "")
#            ((idx++))
#        fi
#
#        if (( processed % 100 == 0 || processed == total_lines )); then
#            local progress=$(( processed * 100 / total_lines ))
#            # Must send the XXX blocks exactly as below
#            printf 'XXX\n%d\nProcessing file %d of %d...\nXXX\n' \
#                "$progress" "$processed" "$total_lines" >&3
#        fi
#
#        ((processed++))
#    done < "$EBOOKS_DB"
#    
#    # Finalise the gauge (ensure 100% and a friendly message), then close FD3
#    printf 'XXX\n100\nFinished building list (%d files)\nXXX\n' "$total_lines" >&3
#    exec 3>&-
#    
#    # Wait for whiptail to exit and remove FIFO (trap will handle rm -f)
#    wait "$gauge_pid"
#    # --- end gauge-via-fifo pattern ---
#
#    [[ "${#ebooks_whip[@]}" -eq 0 ]] && whiptail --title "Attention" --msgbox "No matches." 10 40 && return 1
#    # END FIX.

    # NEW FIX: USE AWK FOR SPEED BOOST.
    # ensure gawk is used (we assume it exists)
    local AWK_BIN="gawk"
    
    # count total lines (avoid zero)
    local total=$(wc -l < "$EBOOKS_DB" 2>/dev/null || echo 0)
    (( total == 0 )) && total=1
    
    # temp files/fifos (unique)
    local pid fifo1 out1 fifo2 out2
    pid=$$
    fifo1="/tmp/ebook_gauge_filter_${pid}.fifo"
    out1="/tmp/ebook_filtered_${pid}.out"
    fifo2="/tmp/ebook_gauge_trunc_${pid}.fifo"
    out2="/tmp/ebook_trunc_${pid}.out"
    
    # cleanup on exit/interruption
    cleanup() {
      rm -f "$fifo1" "$fifo2" "$out1" "$out2"
    }
    trap cleanup EXIT
    
    ##########
    # Step 1: filtered_menu_items (filtering)
    ##########
    mkfifo "$fifo1"
    # start whiptail reading from fifo in background
    whiptail --title "Progress" --gauge "Filtering ebooks…" 8 60 0 < "$fifo1" &
    local gauge1_pid=$!
    
    # gawk: write NUL-separated matches to $out1 and progress to fifo1
    "$AWK_BIN" -v search="$filter_str" -v total="$total" '
    # Turn the glob into a regex (case insensitive)
    function glob2re(glob,    re) {
        # Escape regex meta characters first
        gsub(/([.^$+(){}|\\])/, "\\\\\\1", glob)

        # Convert glob wildcards to regex
        gsub(/\*/, ".*", glob)
        gsub(/\?/, ".", glob)

        return "^" glob "$"
    }    
    BEGIN { FS = OFS = "|"; idx = 1 }
    {
      tags = $NF
      path = $1
    
      slash = match(path, "/[^/]*$")
      if (slash) {
        file = substr(path, slash + 1)
        dir  = substr(path, 1, slash - 1)
        if (dir == "") dir = "/"
      } else {
        file = path
        dir  = "."
      }
    
      pattern = glob2re(tolower(search))
      #if (search == "*" || index(tolower(file), tolower(search)) > 0) {
      if (search == "*" || tolower(file) ~ pattern) {      
        printf("%s\0\0", path)
      }
    
      pct = int((NR / total) * 100)
      printf("%d\n", pct) > "'"$fifo1"'"
      fflush("'"$fifo1"'")
    }
    ' "$EBOOKS_DB" > "$out1"
    
    # close fifo so whiptail gets EOF and exits
    rm -f "$fifo1"
    wait "$gauge1_pid" 2>/dev/null || true
    
    # read results into array (NUL-separated)
    mapfile -d '' -t ebooks_whip < "$out1"
    rm -f "$out1"
    
    ##########
    # Step 2: TRUNC (truncate/display info)
    ##########
    mkfifo "$fifo2"
    whiptail --title "Progress" --gauge "Preparing display/truncation…" 8 70 0 < "$fifo2" &
    local gauge2_pid=$!
    
    "$AWK_BIN" -v search="$filter_str" -v total="$total" '
    # Turn the glob into a regex (case insensitive)
    function glob2re(glob,    re) {
        # Escape regex meta characters first
        gsub(/([.^$+(){}|\\])/, "\\\\\\1", glob)

        # Convert glob wildcards to regex
        gsub(/\*/, ".*", glob)
        gsub(/\?/, ".", glob)

        return "^" glob "$"
    }
    BEGIN {
      FS = OFS = "|"
      idx = 1
      maxd = 35   # dirname display width (including ellipsis if used)
      maxf = 65   # filename display width (including ellipsis)
      maxt = 40   # tags display width (including ellipsis)
    }
    {
      tags = $NF
      path = $1
    
      slash = match(path, "/[^/]*$")
      if (slash) {
        file = substr(path, slash + 1)
        dir  = substr(path, 1, slash - 1)
        if (dir == "") dir = "/"
      } else {
        file = path
        dir  = "."
      }
    
      pattern = glob2re(tolower(search))
      #if (search == "*" || index(tolower(file), tolower(search)) > 0) {
      if (search == "*" || tolower(file) ~ pattern) {
        # truncate dir
        trdir = dir
        if (length(trdir) > maxd) {
          start = length(trdir) - (maxd - 2)
          if (start < 1) start = 1
          trdir = "…" substr(trdir, start)
        }
    
        # truncate file (beginning + end)
        truncated_file = file
        if (length(file) > maxf) {
          prefix = int((maxf - 1) / 2)
          suffix = (maxf - 1) - prefix
          truncated_file = substr(file, 1, prefix) "…" substr(file, length(file) - suffix + 1)
        }
    
        # truncate tags
        truncated_tags = tags
        if (length(truncated_tags) > maxt) truncated_tags = substr(truncated_tags, 1, maxt - 1) "…"
    
        printf("%s\0%s\0", idx ":" trdir "/" truncated_file, "T:" truncated_tags)
        idx++
      }
    
      pct = int((NR / total) * 100)
      printf("%d\n", pct) > "'"$fifo2"'"
      fflush("'"$fifo2"'")
    }
    ' "$EBOOKS_DB" > "$out2"
    
    rm -f "$fifo2"
    wait "$gauge2_pid" 2>/dev/null || true
    
    mapfile -d '' -t TRUNC < "$out2"
    rm -f "$out2"
    # NEW FIX END.	

    CURRENT_PAGE=0

    while :; do
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

        # FIX: SORT TAGS AND REBUILD TAGS ARRAY.
        # Sort the array
        IFS=$'\n' sorted=($(sort <<<"${tags[*]}"))
        unset IFS

        # Rebuild the original array
        tags=("${sorted[@]}")
        # END FIX.

        # convert tags array into whiptail friendly format.
        mapfile -d $'\x1e' -t tags_whip < <(make_into_pairs "${tags[@]}")

        # FIX: PAGINATE TAG SELECTION
        local tag
        tag="$(paginate_tags_menu "Choose a Tag to Associate to File" "${tags_whip[@]}")" || continue

        # # Select tag
        # tag=$(whiptail --menu "Choose a tag:" 20 170 10 \
        #     "${tags_whip[@]}" 3>&1 1>&2 2>&3)					# again here menu items must come in pairs!
        # if [[ $? -ne 0 ]]; then return; fi

        # Escape special regex characters in $tag
        escaped_tag=$(sed 's/[.[\*^$(){}+?|]/\\&/g' <<< "$tag")

        # Check if tag already exists as a standalone tag
        if [[ "$existing_tags" =~ (^|,)${escaped_tag}(,|$) ]]; then
            whiptail --msgbox "Ebook already has this tag!" 8 40
            continue
        fi

        whiptail --title "Confirm" --yesno "Do you want me to go ahead and associate '${tag}' to '${ebook}'?" 20 80 || continue

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
    done
}

# Orphaned
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

# generate_ebooks_list is orphaned.
view_ebooks() {
    # EDGE CASE: EBOOKS_DB file
    if [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]]; then
        #whiptail --title "Alert" --msgbox "Ebooks db file does not exist or is empty!" 10 60
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

    local page_size=100
    local current_page=1
    local total_lines total_pages

    # Count non-empty lines using awk
    total_lines=$(awk 'NF > 0 {count++} END {print count+0}' "$EBOOKS_DB")
    if [[ $total_lines -eq 0 ]]; then
        whiptail --msgbox "No ebooks found in database." 8 50
        return
    fi

    total_pages=$(( (total_lines + page_size - 1) / page_size ))

    while true; do
        # Create menu options array directly using process substitution
        local -a menu_options_array
        
        # # Use awk to generate the main menu items
        # mapfile -d '' -t menu_options_array < <(
        #     awk -v page="$current_page" -v size="$page_size" '
        #         NF > 0 {
        #             if (++count > (page-1)*size && count <= page*size) 
        #                 printf "%s\0%s\0", count, $0
        #         }
        #     ' "$EBOOKS_DB"
        # )

        mapfile -d '' -t menu_options_array < <(
            awk -v page="$current_page" -v size="$page_size" -v path_max=30 -v file_max=80 '
                NF > 0 {
                    if (++count > (page-1)*size && count <= page*size) {
                        # Split line by "|" to get the path part
                        split($0, parts, "|")
                        full_path = parts[1]
                        
                        # Extract filename and path
                        last_slash = match(full_path, /\/[^\/]*$/)
                        if (last_slash > 0) {
                            path = substr(full_path, 1, last_slash - 1)
                            file = substr(full_path, last_slash + 1)
                        } else {
                            path = ""
                            file = full_path
                        }
                        
                        # Extract file extension
                        ext = ""
                        dot_pos = match(file, /\.[^.]*$/)
                        if (dot_pos > 0) {
                            ext = substr(file, dot_pos)
                            file_base = substr(file, 1, dot_pos - 1)
                        } else {
                            file_base = file
                        }
                        
                        # Truncate path
                        path_len = length(path)
                        if (path_len > path_max) {
                            # Keep first and last parts with ellipsis
                            first_part = substr(path, 1, 10)
                            last_slash_pos = match(path, /\/[^\/]*$/)
                            if (last_slash_pos > 10) {
                                last_part = substr(path, last_slash_pos)
                                path_tr = first_part ".../" last_part
                            } else {
                                path_tr = substr(path, 1, path_max - 3) "..."
                            }
                        } else {
                            path_tr = path
                        }
                        
                        # Truncate filename (keep extension visible)
                        file_base_len = length(file_base)
                        if (file_base_len > file_max - length(ext)) {
                            max_base = file_max - length(ext) - 3
                            if (max_base < 1) max_base = 1
                            file_tr = substr(file_base, 1, max_base) "..." ext
                        } else {
                            file_tr = file_base ext
                        }
                        
                        printf "%s\0%s/%s\0", count, path_tr, file_tr
                    }
                }
            ' "$EBOOKS_DB"
        )        

        # Add navigation buttons directly to the array
        if [[ $current_page -gt 1 ]]; then
            menu_options_array+=("__prev__" "Previous Page")
        fi
        if [[ $current_page -lt $total_pages ]]; then
            menu_options_array+=("__next__" "Next Page")
        fi

        # If no items on this page (shouldn't happen, but safe)
        if [[ ${#menu_options_array[@]} -eq 0 ]]; then
            menu_options_array=("" "No items on this page")
        fi

        # Show menu with fixed dimensions
        local choice
        choice=$(whiptail --title "E-Books (Page $current_page/$total_pages)" \
                 --menu "Choose an ebook:" 20 170 10 \
                 --ok-button "OK" --cancel-button "Back" \
                 "${menu_options_array[@]}" 3>&1 1>&2 2>&3)

        [[ $? -ne 0 ]] && return  # Exit on cancel

        case "$choice" in
            "__next__") 
                ((current_page++))
                continue
                ;;
            "__prev__")
                ((current_page--))
                continue
                ;;
            *)
            	# Edge case
            	[[ -z "$choice" ]] && continue
                # Get original line using awk
                local selected_line
                selected_line=$(awk -v line_num="$choice" '
                    NF > 0 && ++count == line_num {print; exit}
                ' "$EBOOKS_DB")
                
                if [[ -n "$selected_line" ]]; then
                    local formatted_str="$(format_file_info "$selected_line")"
                    whiptail --scrolltext --msgbox "$formatted_str" 25 80
                fi
                ;;
        esac
    done
}

# OLD VERSION
# view_ebooks() {
#     [[ $(wc -l < "$EBOOKS_DB") -eq 0 ]] && whiptail --title "Attention" --msgbox "No ebooks registered." 10 40 && return

#     local tmpfile
#     tmpfile=$(mktemp)
#     generate_ebooks_list > "$tmpfile"
#     whiptail --scrolltext --title "All Registered eBooks" --textbox "$tmpfile" 20 80
#     rm -f "$tmpfile"
# }

view_tags() {
    [[ $(wc -l < "$TAGS_DB") -eq 0 ]] && whiptail --title "Attention" --msgbox "No tags registered." 10 40 && return

    local tmp
    tmp=$(mktemp) || { echo "mktemp failed" >&2; return 1; }

    sort "$TAGS_DB" >"$tmp"
    whiptail --scrolltext --title "Tags" --textbox "$tmp" 20 60
    rm -f "$tmp"

    #whiptail --scrolltext --title "Tags" --textbox "$TAGS_DB" 20 60	# now tags are sorted alphabetically for viewing.
}

search_tags() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    paginate_result_menu() {
        local title="$1"
        local result="$2"
        local per_page=100
        local page=0
        local choice start end total max_page

        # Convert newline-separated string into an array safely
        mapfile -t lines <<< "$result"

        total=${#lines[@]}
        (( max_page = (total + per_page - 1) / per_page - 1 ))

        while :; do
            (( start = page * per_page ))
            (( end = start + per_page ))
            (( end > total )) && end=$total

            local menu_items=()
            local truncated_dir truncated_file truncated_tags
            for (( i=start; i<end; i++ )); do
                IFS='|' read -r path tags <<<"${lines[i]}"                

                # TRUNCATE!!!!
                local filename_tr dirname_tr tags_tr filename dirname
                filename="$(basename "$path")"
                dirname="$(dirname "$path")"
                filename_tr="$(truncate_filename "$filename" 80)"
                dirname_tr="$(truncate_dirname "$dirname" 45)"
                tags_tr="$(truncate_tags "$tags")"

                #menu_items+=("${i}:${path}" "T:${tags}")
                menu_items+=("${i}:${dirname_tr}/${filename_tr}" "T:${tags_tr}")
            done

            if (( page > 0 )); then
                menu_items+=("<< Prev Page" "")
            fi
            if (( page < max_page )); then
                menu_items+=(">> Next Page" "")
            fi

            choice=$(whiptail --title "$title (Page $((page+1))/$((max_page+1)))" \
                            --menu "Select a file:" 20 170 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3) || return 1

            case "$choice" in
                "<< Prev Page") ((page--)) ;;
                ">> Next Page") ((page++)) ;;
                *)
                    local index="${choice%%:*}"
                    echo "${lines[index]}"
                    return 0
                    ;;
            esac
        done
    }

    # Get search term
    search=$(whiptail --inputbox "Enter tag search string (literal substring match; empty means wildcard):" 10 40 3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then return; fi
    
    # Find matching tags
    mapfile -t matching_tags < <(grep -i "$search" "$TAGS_DB")
    if [[ ${#matching_tags[@]} -eq 0 ]]; then
        whiptail --msgbox "No matching tags found!" 8 40
        return
    fi
    
    # convert matching_tags array into whiptail friendly format.
    mapfile -d $'\x1e' -t matching_tags_whip < <(make_into_pairs "${matching_tags[@]}")

    # FIX: SORT TAGS ALPHABETICALLY.
    # Step 1: Flatten.
    local pairs=()
    for ((i=0; i<${#matching_tags_whip[@]}; i+=2)); do
        pairs+=("${matching_tags_whip[i]}")  # Only the tag matters since values are empty
    done
    
    # Step 2: Sort tags
    local sorted=()
    IFS=$'\n' sorted=($(sort <<<"${pairs[*]}"))
    unset IFS
    
    # Step 3: Rebuild tags array
    matching_tags_whip=()
    for tag in "${sorted[@]}"; do
        matching_tags_whip+=("$tag" "")
    done
    # END FIX.

    # # Select tag
    # tag=$(whiptail --menu "Choose a tag:" 20 170 10 \
    #     "${matching_tags_whip[@]}" 3>&1 1>&2 2>&3)		# menu items must come in pairs!!!!
    # if [[ $? -ne 0 ]]; then return; fi

    # FIX: PAGINATE TAG SELECTION.
    local tag
    tag="$(paginate_tags_menu "Choose a tag:" "${matching_tags_whip[@]}")" || return 1
    
    # Find ebooks with this tag
    # First, escape regex metacharacters in $tag
    escaped_tag=$(sed 's/[.[\*^$(){}+?|]/\\&/g' <<< "$tag")
    # Use the escaped version in grep
    result="$(grep -E "\|.*${escaped_tag}(,|$)" "$EBOOKS_DB")"

    if [[ -z "$result" ]]; then
        whiptail --msgbox "No ebooks found with this tag!" 8 40
    else
        # generate_ebooks_result_list <(echo "$result") >/tmp/search_result.txt
        # whiptail --scrolltext --textbox /tmp/search_result.txt 20 80
        # rm /tmp/search_result.txt

        # FIX: DISPLAY IN MENU.
        # Format file info and display it.
        local selected_line
        while :; do
            selected_line="$(paginate_result_menu "Search Results" "$result")" || return 1
            local formatted_str
            formatted_str="$(format_file_info "$selected_line")"
            whiptail --scrolltext --msgbox "$formatted_str" 25 80
        done
    fi
}

dissociate_tag_from_registered_ebook() {
    # Check if ebooks database exists. Also check tags db -- no point continuing if no tag registered!
    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }      

#    # Read ebooks database into array
#    local ebooks_list=()
#    mapfile -t ebooks_list < "$EBOOKS_DB"

#    # Check for empty database
#    [[ ${#ebooks_list[@]} -eq 0 ]] && whiptail --msgbox "No registered ebooks!" 8 40 && return 0

#    # Create menu items array
#    local menu_items=()
#    for entry in "${ebooks_list[@]}"; do
#        IFS='|' read -r path tags <<< "$entry"
#        menu_items+=("$path" "T:${tags}")
#    done

    local filter_str
    # Get filter string from user using whiptail. No globbing, simple substring match.
    filter_str=$(whiptail --title "Filter eBooks" --inputbox "Enter filter string to narrow search (globbing; empty for wildcard):" 8 40 3>&1 1>&2 2>&3)    

    # Handle cancel/escape
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to "*" if unset
    filter_str=${filter_str:-"*"}

#    # Filter menu_items and store in array
#    mapfile -d $'\0' filtered_menu_items < <(filter_menu_items "$filter_str" "${menu_items[@]}")
#
#    # Truncate menu_items because of possible long file names.
#    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_dissoc_tag "${filtered_menu_items[@]}" | sed 's/\x1E$//')

    # NEW FIX: USE AWK INSTEAD FOR BOTTLENECK SPEEDUP.
    # Initialize output files
    local out1 out2
    out1=$(mktemp)
    out2=$(mktemp)
    
    # Process the eBooks database
    awk -v filter_str="$filter_str" -v out1="$out1" -v out2="$out2" '
    function rindex(str, char,   i) {
        for (i = length(str); i > 0; i--) {
            if (substr(str, i, 1) == char) {
                return i
            }
        }
        return 0
    }
    function truncate_str(str, max_len,    slen, prefix_len, suffix_len) {
        slen = length(str)
        
        # If string is already short enough, return it as is
        if (slen <= max_len) return str
        
        # If max_len is too small to include ellipsis, just return the first max_len chars
        if (max_len <= 3) return substr(str, 1, max_len)
        
        # Compute how many chars to keep from start and end
        prefix_len = int((max_len - 3) / 2)
        suffix_len = max_len - 3 - prefix_len
        
        return substr(str, 1, prefix_len) "..." substr(str, slen - suffix_len + 1, suffix_len)
    }
    function truncate_file(file, max_len,   parts, dot_index, base, ext) {
        dot_index = match(file, /\.[^.]*$/)
        if (dot_index == 0) {
            if (length(file) > max_len)
                return "..." substr(file, length(file) - max_len + 4)
            return file
        }
        ext = substr(file, dot_index)
        base = substr(file, 1, dot_index - 1)
        if (length(base) + length(ext) > max_len) {
            base = truncate_str(base, max_len - length(ext))
        }
        return base ext
    }
    # Turn the glob into a regex (case insensitive)
    function glob2re(glob,    re) {
        # Escape regex meta characters first
        gsub(/([.^$+(){}|\\])/, "\\\\\\1", glob)

        # Convert glob wildcards to regex
        gsub(/\*/, ".*", glob)
        gsub(/\?/, ".", glob)

        return "^" glob "$"
    }
    BEGIN {
        FS = "|"
        filtered_count = 0
    }
    {
        path = $1
        tags = $2
        last_slash = rindex(path, "/")
        dir = substr(path, 1, last_slash - 1)
        file = substr(path, last_slash + 1)        
        # literal substring match
        #if (filter_str == "*" || index(tolower(file), tolower(filter_str)) > 0) {
        # globbing instead
        pattern = glob2re(tolower(filter_str))
        if (filter_str == "*" || tolower(file) ~ pattern) {
            filtered_count++
            # Output for filtered_menu_items
            printf "%s\0", path >> out1
            printf "T:%s\0", tags >> out1
            
            # Truncate components
            truncated_dir = (length(dir) > 35) ? truncate_str(dir, 35) : dir
            truncated_file = truncate_file(file, 75) # originally 65 make it bit longer
            truncated_tags = (length(tags) > 20) ? substr(tags, 1, 17) "..." : tags
            
            # Output for TRUNC
            printf "%d:%s/%s\0", filtered_count, truncated_dir, truncated_file >> out2
            printf "T:%s\0", truncated_tags >> out2
        }
    }' "$EBOOKS_DB"
    
    local filtered_menu_items=()
    TRUNC=()

    # Read the output files into arrays
    mapfile -d '' -t filtered_menu_items < "$out1"
    mapfile -d '' -t TRUNC < "$out2"
    
    # Clean up temporary files
    rm -f "$out1" "$out2"
    # END NEW FIX.

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
#    local original_entry tags_array
#    for entry in "${ebooks_list[@]}"; do
#        if [[ "$entry" == "${selected_ebook}|"* ]]; then
#            IFS='|' read -r original_path original_tags <<< "$entry"
#            break
#        fi
#    done

    # One-liner using awk.
    local original_path original_tags tags_array
    original_path=$(awk -F'|' -v ebook="$selected_ebook" '$1 == ebook {print $1; exit}' "$EBOOKS_DB")
    original_tags=$(awk -F'|' -v ebook="$selected_ebook" '$1 == ebook {print $2; exit}' "$EBOOKS_DB")

    # Split tags into array
    IFS=',' read -ra tags_array <<< "$original_tags"

    # Check if there are tags to remove
    [[ ${#tags_array[@]} -eq 0 ]] && whiptail --msgbox "No tags associated with this eBook!" 8 40 && return 0

    # Create tag selection menu
    local tag_menu_items=()
    for tag in "${tags_array[@]}"; do
        tag_menu_items+=("$tag" "")
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
#    for entry in "${ebooks_list[@]}"; do
#        if [[ "$entry" == "${selected_ebook}|"* ]]; then
#            echo "$updated_entry" >> "$temp_file"
#        else
#            echo "$entry" >> "$temp_file"
#        fi
#    done

    # awk one-liner.
    awk -v sel="$selected_ebook" -v upd="$updated_entry" -F'|' '
        index($0, sel"|") == 1 { print upd; next }
        { print }
    ' "$EBOOKS_DB" > "$temp_file"

    mv -f "$temp_file" "$EBOOKS_DB"
    whiptail --msgbox "Tag '$selected_tag' removed from '$selected_ebook'!" 20 80
}

delete_tag_from_global_list() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    # Check dependencies
    [[ ! -f "$TAGS_DB" ]] && whiptail --msgbox "Tags database not found!" 8 40 && return 1
    [[ ! -f "$EBOOKS_DB" ]] && whiptail --msgbox "Ebooks database not found!" 8 40 && return 1

    # Read tags database
    local tags_list=()
    mapfile -t tags_list < "$TAGS_DB"
    [[ ${#tags_list[@]} -eq 0 ]] && whiptail --msgbox "No tags available!" 8 40 && return 0

    # FIX: SORT TAGS IN TAGS_LIST AND REBUILD TAGS_LIST ARRAY.
    # Sort the array
    IFS=$'\n' sorted=($(sort <<<"${tags_list[*]}"))
    unset IFS
    
    # Rebuild the original array
    tags_list=("${sorted[@]}")
    # END FIX.

    # Create menu items
    local menu_items=()
    for tag in "${tags_list[@]}"; do
        menu_items+=("$tag" "")
    done

    # # Tag selection
    # local selected_tag
    # selected_tag=$(whiptail --title "Delete Global Tag" --menu "Choose tag to delete:" \
    #     20 60 10 "${menu_items[@]}" 3>&1 1>&2 2>&3)
    # [[ $? -ne 0 ]] && return 0  # User canceled

    # FIX: PAGINATE TAG SELECTION.
    local selected_tag
    selected_tag="$(paginate_tags_menu "Choose tag to delete from global list:" "${menu_items[@]}")" || return 1

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
    if [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]]; then
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40
        return 1
    fi

#    # Read database entries into array
#    mapfile -t entries < "$EBOOKS_DB"
#
#    # Check for empty database
#    if [[ ${#entries[@]} -eq 0 ]]; then
#        whiptail --title "Error" --msgbox "The ebooks database is empty!" 10 60
#        return 1
#    fi
#
#    # Prepare menu items array for whiptail
#    local menu_items=()
#    for entry in "${entries[@]}"; do
#        IFS='|' read -r path tags <<< "$entry"
#        menu_items+=("$path" "T:${tags}")
#    done

    # Get search string from user
    local search_str
    search_str=$(whiptail --title "Search Ebook" --inputbox "Enter text to filter registered ebooks (globbing; empty for wildcard):" 10 60 3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
        return 1  # User cancelled the search
    fi
    : ${search_str:=*}

#    # Display 'In operation' message because creating TRUNC may take some time.
#    in_operation_msg
#
#    # Create filtered_menu_items based on search_str
#    local filtered_menu_items=()
#    for ((i=0; i<${#menu_items[@]}; i+=2)); do
#        path="${menu_items[i]}"
#        tags="${menu_items[i+1]}"
#        if [[ "${path,,}" == *"${search_str,,}"* ]]; then
#            filtered_menu_items+=("$path" "$tags")
#        fi
#    done
#
#    # Check if filtered list is empty
#    if [[ ${#filtered_menu_items[@]} -eq 0 ]]; then
#        whiptail --title "Error" --msgbox "No ebooks found matching '$search_str'." 10 60
#        return 1
#    fi
#
#    # Truncate menu_items because of possible long file names.
#    mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_delete_ebook "${filtered_menu_items[@]}" | sed 's/\x1E$//')

#    # FIX: SPEED IMPROVEMENT BY POPULATING TRUNC DIRECTLY. ALSO ADD WHIPTAIL GAUGE.
#    local total_lines
#    total_lines=$(wc -l < "$EBOOKS_DB")
#
#    # Make a temporary FIFO and ensure cleanup on exit
#    local fifo
#    fifo="$(mktemp -u --tmpdir gauge.XXXXXX)"
#    mkfifo "$fifo"
#    trap 'rm -f "$fifo"' EXIT
#
#    # Start whiptail reading from the FIFO in background
#    whiptail --gauge "Preparing file list..." 7 60 0 < "$fifo" &
#    local gauge_pid=$!
#    
#    # Open the FIFO for writing on fd 3 (keeps writer open until we close it)
#    exec 3> "$fifo"
#
#    : ${search_str:=*}
#    
#    TRUNC=()
#    local filtered_menu_items=()
#    local idx=1 processed=1
#    local path tags dir file truncated_dir truncated_file truncated_tags
#
#    while IFS= read -r line; do
#        [[ -z $line ]] && continue
#    
#        path=${line%|*}
#        tags=${line##*|}
#        dir="$(dirname "$path")"
#        file="$(basename "$path")"
#    
#        if [[ "$search_str" == "*" || "${file,,}" == *"${search_str,,}"* ]]; then
#            truncated_dir="$(truncate_dirname "$dir" 35)"
#            truncated_file="$(truncate_filename "$file" 65)"
#            truncated_tags="$(truncate_tags "$tags")"
#            
#            filtered_menu_items+=("$path" "")
#            TRUNC+=("${idx}:${truncated_dir}/${truncated_file}" "T:${truncated_tags}")
#            ((idx++))
#        fi
#
#        if (( processed % 100 == 0 || processed == total_lines )); then
#            local progress=$(( processed * 100 / total_lines ))
#            # Must send the XXX blocks exactly as below
#            printf 'XXX\n%d\nProcessing file %d of %d...\nXXX\n' \
#                "$progress" "$processed" "$total_lines" >&3
#        fi
#
#        ((processed++))
#    done < "$EBOOKS_DB"
#
#    # Finalise the gauge (ensure 100% and a friendly message), then close FD3
#    printf 'XXX\n100\nFinished building list (%d files)\nXXX\n' "$total_lines" >&3
#    exec 3>&-
#    
#    # Wait for whiptail to exit and remove FIFO (trap will handle rm -f)
#    wait "$gauge_pid"
#    # --- end gauge-via-fifo pattern ---
#
#    [[ "${#filtered_menu_items[@]}" -eq 0 ]] && whiptail --title "Attention" --msgbox "No matches." 10 40 && return 1
#    # END FIX.

    # NEW FIX: USE AWK FOR SIGNIFICANT SPEED UP ON BOTTLENECK.
    local filtered_menu_items=()
    TRUNC=()

    # ensure gawk is used (we assume it exists)
    local AWK_BIN="gawk"
    
    # count total lines (avoid zero)
    local total=$(wc -l < "$EBOOKS_DB" 2>/dev/null || echo 0)
    (( total == 0 )) && total=1
    
    # temp files/fifos (unique)
    local pid fifo1 out1 fifo2 out2
    pid=$$
    fifo1="/tmp/ebook_gauge_filter_${pid}.fifo"
    out1="/tmp/ebook_filtered_${pid}.out"
    fifo2="/tmp/ebook_gauge_trunc_${pid}.fifo"
    out2="/tmp/ebook_trunc_${pid}.out"
    
    # cleanup on exit/interruption
    cleanup() {
      rm -f "$fifo1" "$fifo2" "$out1" "$out2"
    }
    trap cleanup EXIT
    
    ##########
    # Step 1: filtered_menu_items (filtering)
    ##########
    mkfifo "$fifo1"
    # start whiptail reading from fifo in background
    whiptail --title "Progress" --gauge "Filtering ebooks…" 8 60 0 < "$fifo1" &
    local gauge1_pid=$!
    
    # gawk: write NUL-separated matches to $out1 and progress to fifo1
    "$AWK_BIN" -v search="$search_str" -v total="$total" '
    # Turn the glob into a regex (case insensitive)
    function glob2re(glob,    re) {
        # Escape regex meta characters first
        gsub(/([.^$+(){}|\\])/, "\\\\\\1", glob)

        # Convert glob wildcards to regex
        gsub(/\*/, ".*", glob)
        gsub(/\?/, ".", glob)

        return "^" glob "$"
    }
    BEGIN { FS = OFS = "|"; idx = 1 }
    {
      tags = $NF
      path = $1
    
      slash = match(path, "/[^/]*$")
      if (slash) {
        file = substr(path, slash + 1)
        dir  = substr(path, 1, slash - 1)
        if (dir == "") dir = "/"
      } else {
        file = path
        dir  = "."
      }
    
      #if (search == "*" || index(tolower(file), tolower(search)) > 0) {
      #  printf("%s\0\0", path)
      #}
      pattern = glob2re(tolower(search))
      if (search == "*" || tolower(file) ~ pattern) {
          printf("%s\0\0", path)
      }
    
      pct = int((NR / total) * 100)
      printf("%d\n", pct) > "'"$fifo1"'"
      fflush("'"$fifo1"'")
    }
    ' "$EBOOKS_DB" > "$out1"
    
    # close fifo so whiptail gets EOF and exits
    rm -f "$fifo1"
    wait "$gauge1_pid" 2>/dev/null || true
    
    # read results into array (NUL-separated)
    mapfile -d '' -t filtered_menu_items < "$out1"
    rm -f "$out1"
    
    ##########
    # Step 2: TRUNC (truncate/display info)
    ##########
    mkfifo "$fifo2"
    whiptail --title "Progress" --gauge "Preparing display/truncation…" 8 70 0 < "$fifo2" &
    local gauge2_pid=$!
    
    "$AWK_BIN" -v search="$search_str" -v total="$total" '
    # Turn the glob into a regex (case insensitive)
    function glob2re(glob,    re) {
        # Escape regex meta characters first
        gsub(/([.^$+(){}|\\])/, "\\\\\\1", glob)

        # Convert glob wildcards to regex
        gsub(/\*/, ".*", glob)
        gsub(/\?/, ".", glob)

        return "^" glob "$"
    }
    BEGIN {
      FS = OFS = "|"
      idx = 1
      maxd = 35   # dirname display width (including ellipsis if used)
      maxf = 65   # filename display width (including ellipsis)
      maxt = 40   # tags display width (including ellipsis)
    }
    {
      tags = $NF
      path = $1
    
      slash = match(path, "/[^/]*$")
      if (slash) {
        file = substr(path, slash + 1)
        dir  = substr(path, 1, slash - 1)
        if (dir == "") dir = "/"
      } else {
        file = path
        dir  = "."
      }
    
      pattern = glob2re(tolower(search))
      #if (search == "*" || index(tolower(file), tolower(search)) > 0) {
      if (search == "*" || tolower(file) ~ pattern) {
        # truncate dir
        trdir = dir
        if (length(trdir) > maxd) {
          start = length(trdir) - (maxd - 2)
          if (start < 1) start = 1
          trdir = "…" substr(trdir, start)
        }
    
        # truncate file (beginning + end)
        truncated_file = file
        if (length(file) > maxf) {
          prefix = int((maxf - 1) / 2)
          suffix = (maxf - 1) - prefix
          truncated_file = substr(file, 1, prefix) "…" substr(file, length(file) - suffix + 1)
        }
    
        # truncate tags
        truncated_tags = tags
        if (length(truncated_tags) > maxt) truncated_tags = substr(truncated_tags, 1, maxt - 1) "…"
    
        printf("%s\0%s\0", idx ":" trdir "/" truncated_file, "T:" truncated_tags)
        idx++
      }
    
      pct = int((NR / total) * 100)
      printf("%d\n", pct) > "'"$fifo2"'"
      fflush("'"$fifo2"'")
    }
    ' "$EBOOKS_DB" > "$out2"
    
    rm -f "$fifo2"
    wait "$gauge2_pid" 2>/dev/null || true
    
    mapfile -d '' -t TRUNC < "$out2"
    rm -f "$out2"
    
    [ ${#TRUNC[@]} -eq 0 ] && {
        whiptail --msgbox "No matches found for: $search_term" 10 60
        return
    }
    # END NEW FIX.
    
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
    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local search_term
    search_term=$(whiptail --inputbox "Enter filename search term (globbing; empty for wildcard):" 10 60 3>&1 1>&2 2>&3)
    # Originally it was globbing but with new awk code it's literal substring match now.

    # Exit if user canceled
    [ $? -ne 0 ] && return 1

    # defaults to wildcard if empty
    search_term="${search_term:-*}"
    
    local matches=()
#    while IFS= read -r line; do
#        if [[ "$line" == *"|"* ]]; then
#            IFS='|' read -r path tags <<< "$line"
#            filename=$(basename "$path")
#
#            # Lower‑case filename and pattern
#            local filename_lc="${filename,,}"
#            local pattern_lc="${search_term,,}"
#
#            # Ensure a default wildcard
#            pattern_lc="${pattern_lc:-*}"
#
#            # Now do a glob on the lower‑cased filename
#            if [[ "$filename_lc" == $pattern_lc ]]; then
#                matches+=("$path" "")
#            fi
#
#            #if [[ "$search_term" == "*" || "${filename,,}" == *"${search_term,,}"* ]]; then
#            #    matches+=("$path" "")
#            #fi
#        fi
#    done < "$EBOOKS_DB"

#    # SHOW WHIPTAIL GAUGE.
#    # count lines (protect against empty file)
#    local total_lines
#    total_lines=$(wc -l < "$EBOOKS_DB" 2>/dev/null) || total_lines=0
#    (( total_lines == 0 )) && total_lines=1
#
#    # create fifo and ensure cleanup
#    local fifo gauge_pid processed=0 last_progress=-1 progress
#    fifo=$(mktemp -u --tmpdir gauge.XXXXXX)
#    mkfifo "$fifo"
#    trap 'rm -f "$fifo"' EXIT
#
#    # launch whiptail reading from fifo (background)
#    whiptail --gauge "Searching ebooks..." 7 60 0 < "$fifo" &
#    gauge_pid=$!
#    exec 3> "$fifo"

    TRUNC=()
#    local idx=1
#
#    # writer loop runs in the foreground so matches[] stays visible to caller
#    while IFS= read -r line; do
#        ((processed++))
#
#        if [[ "$line" == *"|"* ]]; then
#            IFS='|' read -r path tags <<< "$line"
#            local filename filename_lc pattern_lc
#            filename=$(basename "$path")
#            filename_lc="${filename,,}"
#            pattern_lc="${search_term,,}"
#            pattern_lc="${pattern_lc:-*}"
#
#            if [[ "$filename_lc" == $pattern_lc ]]; then
#                local dir="$(dirname "$path")"
#                local file="$(basename "$path")"
#    
#                # Truncate
#                local truncated_dir="$(truncate_dirname "$dir" 35)"
#                local truncated_file="$(truncate_filename "$file" 65)"
#
#                TRUNC+=("${idx}:${truncated_dir}/${truncated_file}" "")
#                matches+=("$path" "")
#                ((idx++))
#            fi
#        fi
#
#        # throttle gauge updates
#        if (( processed % 100 == 0 )); then
#            progress=$(( processed * 100 / total_lines ))
#            if (( progress != last_progress )); then
#                {
#                    echo "XXX"
#                    echo "$progress"
#                    echo "Processed ${processed}/${total_lines}..."
#                    echo "XXX"
#                } >&3
#                last_progress=$progress
#            fi
#        fi
#    done < "$EBOOKS_DB"
#
#    # final 100% update
#    {
#        echo "XXX"
#        echo "100"
#        echo "Done."
#        echo "XXX"
#    } >&3
#    exec 3>&-
#    wait "$gauge_pid"
#    # END.

    # NEW FIX: USE AWK FOR SPEED.
    # ensure gawk is used (we assume it exists)
    local AWK_BIN="gawk"
    
    # count total lines (avoid zero)
    local total=$(wc -l < "$EBOOKS_DB" 2>/dev/null || echo 0)
    (( total == 0 )) && total=1
    
    # temp files/fifos (unique)
    local pid fifo1 out1 fifo2 out2
    pid=$$
    fifo1="/tmp/ebook_gauge_filter_${pid}.fifo"
    out1="/tmp/ebook_filtered_${pid}.out"
    fifo2="/tmp/ebook_gauge_trunc_${pid}.fifo"
    out2="/tmp/ebook_trunc_${pid}.out"
    
    # cleanup on exit/interruption
    cleanup() {
      rm -f "$fifo1" "$fifo2" "$out1" "$out2"
    }
    trap cleanup EXIT
    
    ##########
    # Step 1: filtered_menu_items (filtering)
    ##########
    mkfifo "$fifo1"
    # start whiptail reading from fifo in background
    whiptail --title "Progress" --gauge "Filtering ebooks…" 8 60 0 < "$fifo1" &
    local gauge1_pid=$!
    
    # gawk: write NUL-separated matches to $out1 and progress to fifo1
    "$AWK_BIN" -v search="$search_term" -v total="$total" '
    # Turn the glob into a regex (case insensitive)
    function glob2re(g,    i, ch, out) {
        out = ""
        for (i = 1; i <= length(g); i++) {
            ch = substr(g, i, 1)
            if (ch == "*")      out = out ".*"
            else if (ch == "?") out = out "."
            else if (ch ~ /[.^$+(){}|\\]/) out = out "\\" ch
            else                 out = out ch
        }
        return "^" out "$"
    }
    BEGIN { FS = OFS = "|"; idx = 1 }
    {
      tags = $NF
      path = $1
    
      slash = match(path, "/[^/]*$")
      if (slash) {
        file = substr(path, slash + 1)
        dir  = substr(path, 1, slash - 1)
        if (dir == "") dir = "/"
      } else {
        file = path
        dir  = "."
      }
    
      pattern = glob2re(tolower(search))
      #print "Pattern is:" pattern > "/dev/stderr"
      if (search == "*" || tolower(file) ~ pattern) {
      #if (search == "*" || index(tolower(file), tolower(search)) > 0) {
        printf("%s\0\0", path)
      }
    
      pct = int((NR / total) * 100)
      printf("%d\n", pct) > "'"$fifo1"'"
      fflush("'"$fifo1"'")
    }
    ' "$EBOOKS_DB" > "$out1"
    
    # close fifo so whiptail gets EOF and exits
    rm -f "$fifo1"
    wait "$gauge1_pid" 2>/dev/null || true
    
    # read results into array (NUL-separated)
    mapfile -d '' -t matches < "$out1"
    rm -f "$out1"
    
    ##########
    # Step 2: TRUNC (truncate/display info)
    ##########
    mkfifo "$fifo2"
    whiptail --title "Progress" --gauge "Preparing display/truncation…" 8 70 0 < "$fifo2" &
    local gauge2_pid=$!
    
    "$AWK_BIN" -v search="$search_term" -v total="$total" '
    # Turn the glob into a regex (case insensitive)
    function glob2re(g,    i, ch, out) {
        out = ""
        for (i = 1; i <= length(g); i++) {
            ch = substr(g, i, 1)
            if (ch == "*")      out = out ".*"
            else if (ch == "?") out = out "."
            else if (ch ~ /[.^$+(){}|\\]/) out = out "\\" ch
            else                 out = out ch
        }
        return "^" out "$"
    }
    BEGIN {
      FS = OFS = "|"
      idx = 1
      maxd = 35   # dirname display width (including ellipsis if used)
      maxf = 65   # filename display width (including ellipsis)
      maxt = 40   # tags display width (including ellipsis)
    }
    {
      tags = $NF
      path = $1
    
      slash = match(path, "/[^/]*$")
      if (slash) {
        file = substr(path, slash + 1)
        dir  = substr(path, 1, slash - 1)
        if (dir == "") dir = "/"
      } else {
        file = path
        dir  = "."
      }
      pattern = glob2re(tolower(search))
      #print "Pattern is:" pattern
      if (search == "*" || tolower(file) ~ pattern) {
      #if (search == "*" || index(tolower(file), tolower(search)) > 0) {
        # truncate dir
        trdir = dir
        if (length(trdir) > maxd) {
          start = length(trdir) - (maxd - 2)
          if (start < 1) start = 1
          trdir = "…" substr(trdir, start)
        }
    
        # truncate file (beginning + end)
        truncated_file = file
        if (length(file) > maxf) {
          prefix = int((maxf - 1) / 2)
          suffix = (maxf - 1) - prefix
          truncated_file = substr(file, 1, prefix) "…" substr(file, length(file) - suffix + 1)
        }
    
        # truncate tags
        truncated_tags = tags
        if (length(truncated_tags) > maxt) truncated_tags = substr(truncated_tags, 1, maxt - 1) "…"
    
        printf("%s\0%s\0", idx ":" trdir "/" truncated_file, "T:" truncated_tags)
        idx++
      }
    
      pct = int((NR / total) * 100)
      printf("%d\n", pct) > "'"$fifo2"'"
      fflush("'"$fifo2"'")
    }
    ' "$EBOOKS_DB" > "$out2"
    
    rm -f "$fifo2"
    wait "$gauge2_pid" 2>/dev/null || true
    
    mapfile -d '' -t TRUNC < "$out2"
    rm -f "$out2"
    # END NEW FIX.
    
    [ ${#TRUNC[@]} -eq 0 ] && {
        whiptail --msgbox "No matches found for: $search_term" 10 60
        return
    }

    # Truncate matches because of possible long file names.
    #mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_assoc_tag "${matches[@]}" | sed 's/\x1E$//')
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
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }          

    local tag_search
    tag_search=$(whiptail --inputbox "Enter tag search term (literal substring match; empty for wildcard):" 10 60 3>&1 1>&2 2>&3)

    # Exit if user canceled
    [ $? -ne 0 ] && return 1

    tag_search="${tag_search:-*}"
    
    # Get matching tags from TAGS_DB
    local tags=()
    while IFS= read -r tag; do
        [[ "$tag_search" == "*" || "${tag,,}" == *"${tag_search,,}"* ]] && tags+=("$tag" "")
    done < "$TAGS_DB"
    
    [ ${#tags[@]} -eq 0 ] && {
        whiptail --msgbox "No tags found matching: $tag_search" 10 60
        return
    }

    # FIX: SORT TAGS ALPHABETICALLY.
    # Step 1: Flatten.
    local pairs=()
    for ((i=0; i<${#tags[@]}; i+=2)); do
        pairs+=("${tags[i]}")  # Only the tag matters since values are empty
    done
    
    # Step 2: Sort tags
    local sorted=()
    IFS=$'\n' sorted=($(sort <<<"${pairs[*]}"))
    unset IFS
    
    # Step 3: Rebuild tags array
    tags=()
    for tag in "${sorted[@]}"; do
        tags+=("$tag" "")
    done
    # END FIX.
    
    # local selected_tag
    # selected_tag=$(whiptail --menu "Select tag" 20 170 10 "${tags[@]}" 3>&1 1>&2 2>&3)  # tweak dimensions

    # FIX: PAGINATE TAG SELECTION.
    local selected_tag
    selected_tag="$(paginate_tags_menu "Select a tag" "${tags[@]}")" || return 1

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
                    files+=("$path" "")
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
        #whiptail --msgbox "Directory selection canceled." 8 40
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

    # Print the formatted output, now also print file size.
    echo "File name:"
    echo "$filename"
    echo ""
    echo "Directory path:"
    echo "${directory}/"
    echo ""
    echo "Tags:"
    echo "$tags"
    echo ""
    echo "$(file --mime-type -b "$file_with_path")"
    echo ""
    echo "File size:"
    echo "$(du -h "$file_with_path" | cut -f1)"
}

# Depends on parser code above for parsing custom boolean patterns to be used here.
lookup_registered_files() {
    # Show initial information
    whiptail --title "Lookup Registered Files" --msgbox \
    "This advanced feature allows you to look up full file information by narrowing it down by file name and tags." 8 78

    local pattern regex filtered_paths filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter glob pattern for file names (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"

    # Convert pattern to regex using your existing parse_expr function - DON'T USE BOOLEAN PATTERN ANY MORE!
    #regex=$(parse_expr "$pattern")

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file path part is considered (everything before the |)
    #filtered_paths=$(cut -d'|' -f1 "$EBOOKS_DB" | grep -iP "$regex")   # DON'T USE BOOLEAN PATTERN ANY MORE!
    filtered_paths=$(
    awk -F'|' -v glob="$pattern" 'BEGIN { IGNORECASE = 1
        re = "^"
        for (i = 1; i <= length(glob); ++i) {
        c = substr(glob, i, 1)
        if (c == "*")       re = re ".*"
        else if (c == "?")  re = re "."
        else {
            if (c ~ /[][\.\\^$+(){}|]/) re = re "\\" c
            else re = re c
        }
        }
        re = re "$"
    }
    $1 ~ re { print $1 }
    ' "$EBOOKS_DB"
    )    

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
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (literal substring match; if empty wildcard):" 8 60 3>&1 1>&2 2>&3)
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

    #in_operation_msg # show 'in operation...' while building menu items...

    #local menu_items=()
#    local idx=1
#    declare -A line_map=()
#    
#    # Build the menu items array. Each menu entry is a pair:
#    # the index number and a description (file path with tags)
#    # FIX: CONSTRUCT TRUNC HERE TO POTENTIALLY SPEED UP BOTTLENECK.
#    # Count total lines once
#    local total_lines
#    total_lines=$(wc -l <<< "$final_list")
#
#    TRUNC=()
#    # Make a temporary FIFO and ensure cleanup on exit
#    local fifo
#    fifo="$(mktemp -u --tmpdir gauge.XXXXXX)"
#    mkfifo "$fifo"
#    trap 'rm -f "$fifo"' EXIT
#    
#    # Start whiptail reading from the FIFO in background
#    whiptail --gauge "Preparing file list..." 7 60 0 < "$fifo" &
#    local gauge_pid=$!
#    
#    # Open the FIFO for writing on fd 3 (keeps writer open until we close it)
#    exec 3> "$fifo"
#    
#    # Build TRUNC in main shell; send gauge updates to fd 3
#    while IFS= read -r line; do
#        [[ -z $line ]] && continue
#    
#        local path=${line%|*}
#        local tags=${line##*|}
#    
#        local dir="$(dirname "$path")"
#        local file="$(basename "$path")"
#    
#        local truncated_dir="$(truncate_dirname "$dir" 35)"
#        local truncated_file="$(truncate_filename "$file" 65)"
#        local truncated_tags="$(truncate_tags "$tags")"
#    
#        TRUNC+=("$idx" "${truncated_dir}/${truncated_file} T:${truncated_tags}")
#        line_map["$idx"]="$line"
#    
#        if (( idx % 100 == 0 || idx == total_lines )); then
#            local progress=$(( idx * 100 / total_lines ))
#            # Must send the XXX blocks exactly as below
#            printf 'XXX\n%d\nProcessing file %d of %d...\nXXX\n' \
#                "$progress" "$idx" "$total_lines" >&3
#        fi
#    
#        ((idx++))
#    done < <(printf "%s\n" "$final_list")
#    
#    # Finalise the gauge (ensure 100% and a friendly message), then close FD3
#    printf 'XXX\n100\nFinished building list (%d files)\nXXX\n' "$total_lines" >&3
#    exec 3>&-
#    
#    # Wait for whiptail to exit and remove FIFO (trap will handle rm -f)
#    wait "$gauge_pid"
#    # --- end gauge-via-fifo pattern ---

    # NEW FIX: BOTTLENECK SPEEDUP BY REPLACING LOOPS WITH AWK.
    local total_lines
    total_lines=$(wc -l <<< "$final_list")
    
    # Create temporary files for awk output
    trunc_file=$(mktemp)
    line_map_file=$(mktemp)
    
    # FIFO for whiptail gauge
    local fifo
    fifo="$(mktemp -u --tmpdir gauge.XXXXXX)"
    mkfifo "$fifo"
    trap 'rm -f "$fifo" "$trunc_file" "$line_map_file"' EXIT
    
    # Start whiptail
    whiptail --gauge "Preparing file list..." 7 60 0 < "$fifo" &
    local gauge_pid=$!
    
    # Open FIFO for writing
    exec 3> "$fifo"
    
    # Process lines with awk
    awk -v total_lines="$total_lines" \
        -v trunc_file="$trunc_file" \
        -v line_map_file="$line_map_file" \
        -v fifo="$fifo" '
    function truncate_dirname(dir, max_len) {
        if (length(dir) <= max_len) return dir;
        return "..." substr(dir, length(dir) - max_len + 4);
    }
    function truncate_filename(file, max_len) {
        # If the filename is already short enough, return it as is
        if (length(file) <= max_len) {
            return file
        }
        
        # Find the last dot to separate extension
        dot_position = 0
        for (i = length(file); i > 0; i--) {
            if (substr(file, i, 1) == ".") {
                dot_position = i
                break
            }
        }
        
        # If no extension found, just truncate the filename
        if (dot_position == 0) {
            return substr(file, 1, max_len - 3) "..."
        }
        
        # Extract the base name and extension
        base = substr(file, 1, dot_position - 1)
        ext = substr(file, dot_position)
        
        # Calculate how much space we have for the base name
        base_max_len = max_len - length(ext) - 3  # 3 for the "..."
        
        # Truncate the base name and add dots and extension
        truncated_base = substr(base, 1, base_max_len)
        return truncated_base "..." ext
    }
    function truncate_tags(tags, max_len) {
        if (length(tags) <= max_len) return tags;
        return substr(tags, 1, max_len - 3) "...";
    }
    {
        if (!NF) next;
        
        split($0, parts, "|");
        path = parts[1];
        tags = parts[2];
        
        dir = path;
        sub("/[^/]*$", "", dir);
        file = path;
        sub(".*/", "", file);
        
        truncated_dir = truncate_dirname(dir, 35);
        truncated_file = truncate_filename(file, 65);
        truncated_tags = truncate_tags(tags, 20); # Adjust tag length as needed
        
        # Write to temporary files using null delimiter
        printf "%s\0%s\0", NR, truncated_dir "/" truncated_file " T:" truncated_tags >> trunc_file;
        printf "%s\0%s\0", NR, $0 >> line_map_file;
        
        # Progress update
        if (NR % 100 == 0 || NR == total_lines) {
            progress = NR * 100 / total_lines;
            printf "XXX\n%d\nProcessing file %d of %d...\nXXX\n", progress, NR, total_lines >> fifo;
            fflush(fifo);
        }
    }
    END {
        printf "XXX\n100\nFinished building list (%d files)\nXXX\n", total_lines >> fifo;
        close(fifo);
        close(trunc_file);
        close(line_map_file);
    }
    ' < <(printf "%s\n" "$final_list")
    
    # Close FIFO and wait for whiptail
    exec 3>&-
    wait "$gauge_pid"
    
    # Read temporary files into arrays using null delimiter
    declare -a TRUNC
    declare -A line_map
    
    # Read trunc_file
    while IFS= read -r -d '' idx && IFS= read -r -d '' value; do
        TRUNC+=("$idx" "$value")
    done < "$trunc_file"
    
    # Read line_map_file
    while IFS= read -r -d '' idx && IFS= read -r -d '' value; do
        line_map["$idx"]="$value"
    done < "$line_map_file"
    # NEW FIX ENDS.

    # menu_items need truncating. the format is "idx#" "full path including tags"
    # Build the large list once:
    #mapfile -d $'\x1e' -t TRUNC < <(generate_trunc_lookup "${menu_items[@]}" | sed 's/\x1E$//')

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
        whiptail --scrolltext --msgbox "$formatted_str" 25 80
    done
}

# Build list of filtered items from $EBOOKS_DB filtered by full path name and tag.
# NO LONGER USESBOOLEAN PATTERN BUT GLOBBING!!!!
build_bulk() {    
    local pattern regex filtered_paths filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter glob pattern for file names (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3 </dev/tty)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"

    # DEBUG - if need be save to a temp file perhaps?
    #echo pattern: >&2
    #echo "$pattern" >&2

    # Convert pattern to regex using your existing parse_expr function
    #regex=$(parse_expr "$pattern")

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file path part is considered (everything before the |)
    #filtered_paths=$(cut -d'|' -f1 "$EBOOKS_DB" | grep -iP "$regex")

    filtered_paths=$(
    awk -F'|' -v glob="$pattern" 'BEGIN { IGNORECASE = 1
        re = "^"
        for (i = 1; i <= length(glob); ++i) {
        c = substr(glob, i, 1)
        if (c == "*")       re = re ".*"
        else if (c == "?")  re = re "."
        else {
            if (c ~ /[][\.\\^$+(){}|]/) re = re "\\" c
            else re = re c
        }
        }
        re = re "$"
    }
    $1 ~ re { print $1 }
    ' "$EBOOKS_DB"
    )

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
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (literal substring match; if empty wildcard):" 8 60 3>&1 1>&2 2>&3 </dev/tty)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to .* --- not needed.
    #tag_pattern="${tag_pattern:-.*}"

    # Further filter the lines by matching the tag pattern (which appears after the |)
    #final_list=$(echo "$filtered_lines" | grep -iP "\|.*$tag_pattern")
    final_list=$(printf '%s\n' "$filtered_lines" | grep -iP "\|.*${tag_pattern:+\Q$tag_pattern\E}")   # literal substring match

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
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    # Initial message.
    whiptail --title "Bulk Associate Tag" --msgbox "This advanced feature lets you choose a registered tag and associate that same tag across a bulk of registered files." 10 60

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }      

    # Present tag selection menu using whiptail
    local tags=()
    while IFS= read -r tag; do
        tags+=("$tag" "")
    done < "$TAGS_DB"
    
    [[ ${#tags[@]} -eq 0 ]] && { 
        whiptail --title "Error" --msgbox "No tags registered. Register at least one tag." 10 70
        return 1
    }

    # FIX: SORT TAGS ALPHABETICALLY.
    # Step 1: Flatten.
    local pairs=()
    for ((i=0; i<${#tags[@]}; i+=2)); do
        pairs+=("${tags[i]}")  # Only the tag matters since values are empty
    done
    
    # Step 2: Sort tags
    local sorted=()
    IFS=$'\n' sorted=($(sort <<<"${pairs[*]}"))
    unset IFS
    
    # Step 3: Rebuild tags array
    tags=()
    for tag in "${sorted[@]}"; do
        tags+=("$tag" "")
    done
    # END FIX.
    
    # local selected_tag
    # selected_tag=$(whiptail --menu "Choose a tag to associate to bulk" 20 150 10 "${tags[@]}" 3>&1 1>&2 2>&3)
    # [[ -z "$selected_tag" ]] && return 1  # User canceled
    
    # FIX: PAGINATE TAG SELECTION.
    local selected_tag
    selected_tag="$(paginate_tags_menu "Choose a tag to associate to bulk" "${tags[@]}")" || return 1

    # Read bulk entries
    local tempfile=$(mktemp) || return 1

    build_bulk > "$tempfile" || {
        #whiptail --title "Error" --msgbox "User cancelled." 10 70
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
If you proceed, all of the matching entries will be associated with the tag '${selected_tag}'. Do you want to update the database?" 10 70

    [[ $? -ne 0 ]] && {
        whiptail --title "Error" --msgbox "User cancelled. Database has not been modified." 10 70
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
"Bulk files have been associated with the tag '${selected_tag}'." 10 70
}

dissoc_tag_to_bulk() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    # Initial message.
    whiptail --title "Bulk Dissociate Tag" --msgbox "This advanced feature lets you choose a registered tag and remove that same tag from a bulk of registered files." 10 60

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }      

    # Present tag selection menu using whiptail
    local tags=()
    while IFS= read -r tag; do
        tags+=("$tag" "")
    done < "$TAGS_DB"
    
    [[ ${#tags[@]} -eq 0 ]] && { 
        whiptail --title "Error" --msgbox "No tags registered. Register at least one tag." 10 70
        return 1
    }

    # FIX: FLATTEN TAGS ARRAY, SORT, THEN REBUILD.
    # Step 1: Flatten.
    local pairs=()
    for ((i=0; i<${#tags[@]}; i+=2)); do
        pairs+=("${tags[i]}")  # Only the tag matters since values are empty
    done
    
    # Step 2: Sort tags
    local sorted=()
    IFS=$'\n' sorted=($(sort <<<"${pairs[*]}"))
    unset IFS
    
    # Step 3: Rebuild tags array
    tags=()
    for tag in "${sorted[@]}"; do
        tags+=("$tag" "")
    done
    # END FIX.
    
    # local selected_tag
    # selected_tag=$(whiptail --menu "Choose a tag to dissociate from bulk" 20 150 10 "${tags[@]}" 3>&1 1>&2 2>&3)
    # [[ -z "$selected_tag" ]] && return 1  # User canceled
    
    # FIX: PAGINATE TAG SELECTION.
    local selected_tag
    selected_tag="$(paginate_tags_menu "Choose a tag to dissociate from bulk" "${tags[@]}")" || return 1

    # In operation msg because building bulk takes time.
    in_operation_msg

    # Read bulk entries
    local tempfile=$(mktemp) || return 1

    build_bulk > "$tempfile" || {
        #whiptail --title "Error" --msgbox "User cancelled." 10 70
        return 1
    }

#    local bulk
#    mapfile -d '' bulk < "$tempfile"
#    rm -f "$tempfile"
#    
#    # Process bulk entries
#    local processed_bulk=()
#    for entry in "${bulk[@]}"; do
#        IFS='|' read -r path current_tags <<< "$entry"
#        local new_tags
#
#        # Remove selected_tag if present
#        if [[ -n "$current_tags" ]]; then
#            IFS=',' read -ra tags_array <<< "$current_tags"
#            local new_tags_array=()
#            for tag in "${tags_array[@]}"; do
#                [[ "$tag" != "$selected_tag" ]] && new_tags_array+=("$tag")
#            done
#            # Join array back to comma-separated string
#            new_tags=$(IFS=','; echo "${new_tags_array[*]}")
#        else
#            new_tags="$current_tags"
#        fi
#
#        processed_bulk+=("$path|$new_tags")
#    done

    # NEW FIX: USE AWK INSTEAD TO POPULATE PROCESSED_BULK
    local processed_bulk=()
    mapfile -d '' processed_bulk < <(
      awk -v sel="$selected_tag" 'BEGIN { RS = "\0"; ORS = "\0" }
      {
        split($0, a, "|")
        path = a[1]
        tags = a[2]
        if (tags == "") {
          print path "|"
          next
        }
        n = split(tags, arr, ",")
        out = ""
        for (i = 1; i <= n; i++) {
          if (arr[i] != sel && arr[i] != "") {
            out = out "," arr[i]
          }
        }
        gsub(/^,|,$/, "", out)
        print path "|" out
      }' "$tempfile"
    )
    rm -f "$tempfile"
    # NEW FIX ENDS.

    # Create associative array for updates
    declare -A updated_entries
#    for entry in "${processed_bulk[@]}"; do
#        IFS='|' read -r path tags <<< "$entry"
#        # Only add to updates if tags changed
#        if [[ "$tags" != "$(grep -F "$path|" "$EBOOKS_DB" | cut -d'|' -f2-)" ]]; then
#            updated_entries["$path"]="$tags"
#        fi
#    done

    # NEW FIX: POPULATE UPDATED_ENTRIES USING AWK.
    # Create temporary files for the data
    local processed_bulk_file=$(mktemp)
    printf "%s\n" "${processed_bulk[@]}" > "$processed_bulk_file"

    local updated_list=$(awk -F'|' '
      NR==FNR {
        a[$1] = $2
        next
      }
      {
        if ($1 in a && a[$1] != $2) {
          print $1 "|" a[$1]
        }
      }' "$processed_bulk_file" "$EBOOKS_DB")
    
    # Populate the bash associative array from the awk output
    if [[ -n "$updated_list" ]]; then
      while IFS='|' read -r path tags; do
        updated_entries["$path"]="$tags"
      done <<< "$updated_list"
    fi

    rm "$processed_bulk_file"
    # NEW FIX END.

    # Skip if no changes
    [[ ${#updated_entries[@]} -eq 0 ]] && {
        whiptail --title "No Changes" --msgbox "No files were found with the tag '${selected_tag}'. Database remains unchanged." 10 70
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
        whiptail --title "Error" --msgbox "User cancelled. Database has not been modified." 10 70
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
"Bulk files have been dissociated from the tag '${selected_tag}'." 10 70
}

# Remove files in bulk.
remove_files_in_bulk() {
    # Initial message
    whiptail --title "DANGER: Bulk File Removal" --msgbox \
"This feature lets you remove multiple files from the database in bulk. Selected entries will be permanently removed from the database." 10 60

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    # Read bulk entries
    local tempfile=$(mktemp) || return 1

    build_bulk > "$tempfile" || {
        #whiptail --title "Error" --msgbox "User cancelled." 10 70
        return 1
    }

    local bulk
    mapfile -d '' bulk < "$tempfile"
    rm -f "$tempfile"

    # Debug
    #printf "%s\n" "${bulk[@]}" >&2
    #exit

    # Extract paths from bulk entries
    declare -A paths_to_remove
    for entry in "${bulk[@]}"; do
        IFS='|' read -r path _ <<< "$entry"
        paths_to_remove["$path"]=1
    done

    # Check if any paths were selected
    [[ ${#paths_to_remove[@]} -eq 0 ]] && {
        whiptail --title "Error" --msgbox "No files selected for removal." 10 70
        return 1
    }

    # Confirmation dialog
    whiptail --title "Confirm Removal" --yesno \
"About to remove ${#paths_to_remove[@]} entries from the database. This operation cannot be undone!\n\nProceed with deletion?" \
0 0

    [[ $? -ne 0 ]] && {
        whiptail --title "Cancelled" --msgbox "Database remains unchanged. No files were removed." 10 70
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
"Successfully removed $removed_count entries from the database." 10 70
    else
        rm -f "$tmpfile"
        whiptail --title "No Changes" --msgbox \
"No matching entries found in the database. No files were removed." 10 70
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
  #local message="${#conflicting_entries[@]} broken entries found:\n"
  #for entry in "${conflicting_entries[@]}"; do
  #  message+="$entry\n"
  #done

  # Inform the user about the conflicting lines.
  #whiptail --msgbox "$message" 20 78

  # Prepare a message listing the first 20 broken entries.
  local message="${#conflicting_entries[@]} broken entries found:\n"
  local count=0
  for entry in "${conflicting_entries[@]}"; do
    if (( count < 20 )); then
      message+="$entry\n"
      ((count++))
    else
      message+="...\n"
      break
    fi
  done
  
  # Inform the user about the conflicting lines.
  whiptail --scrolltext --msgbox "$message" 20 78

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
    select_dir_paginated_lookup() {
        local page_size=80   # number of items per page
        local page=0
        local choice=""
        local dirs
        local total_pages
        local menu_items=()
        
        # Extract unique directories
        dirs=$(cut -d'|' -f1 "${EBOOKS_DB}" | sed -E 's:/[^/]+$::' | sort | uniq)
        
        # Convert dirs to array
        IFS=$'\n' read -rd '' -a dirs_array <<< "$dirs"
        
        if (( ${#dirs_array[@]} == 0 )); then
            whiptail --title "Attention" \
                    --msgbox "No directories found! Perhaps ebooks db is empty." \
                    10 60
            return 1
        fi

        # Calculate total pages
        total_pages=$(( (${#dirs_array[@]} + page_size - 1) / page_size ))
        
        while true; do
            menu_items=()
            # Slice array for current page
            start=$(( page * page_size ))
            end=$(( start + page_size ))
            (( end > ${#dirs_array[@]} )) && end=${#dirs_array[@]}
            
            for (( i=start; i<end; i++ )); do
                menu_items+=( "${dirs_array[i]}" "" )
            done
            
            # Add navigation options if needed
            (( page > 0 )) && menu_items+=( "<< Prev" "" )
            (( page < total_pages - 1 )) && menu_items+=( "Next >>" "" )
            
            # Show menu
            local sel
            sel=$(whiptail --title "Select Directory" \
                        --menu "Choose a directory for registered files:" \
                        20 170 10 \
                        "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1            
            
            case "$sel" in
                "Next >>")
                    ((page++))
                    ;;
                "<< Prev")
                    ((page--))
                    ;;
                *)
                    choice="$sel"
                    break
                    ;;
            esac
        done
        
        echo "$choice"
    }

    # Initial message.
    whiptail --title "Lookup By File Path" --msgbox \
"This feature allows you to query files by first choosing a file path among registered files:\n\
After choosing a path from the list, you can further narrow the search by both file name(glob pattern) and tag(literal substring match)." 20 80

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    # FEATURE: PAGINATE PATH SEL.
    local choice
    choice="$(select_dir_paginated_lookup)" || return 1

    # Display all lines in ebooks.db that match the chosen directory
    local matching_files_in_chosen_dir="$(grep -E "^${choice}/[^/]+\|" "${EBOOKS_DB}")"

    # Now, get from user pattern and tag_pattern to further narrow the search.

    # REPLACE BOOLEAN SEARCH WITH GLOBBING

    local pattern regex filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter glob pattern for file names (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"

    # DEBUG - if need be save to a temp file perhaps?
    #echo pattern: >&2
    #echo "$pattern" >&2

    # Convert pattern to regex using your existing parse_expr function
    #regex=$(parse_expr "$pattern")

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file path part is considered (everything before the |)
    #filtered_paths="$(cut -d'|' -f1 <(echo "$matching_files_in_chosen_dir") | grep -iP "$regex")"

    filtered_paths=$(
    awk -F'|' -v glob="$pattern" '
    BEGIN {
        IGNORECASE = 1
        # build regex from glob
        re = "^"
        for (i = 1; i <= length(glob); ++i) {
        c = substr(glob, i, 1)
        if (c == "*")      re = re ".*"
        else if (c == "?") re = re "."
        else {
            if (c ~ /[][\.\\^$+(){}|]/) re = re "\\" c
            else re = re c
        }
        }
        re = re "$"
    }
    $1 ~ re { print $1 }
    ' <(echo "$matching_files_in_chosen_dir")
    )

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
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (literal substring match; if empty wildcard):" 8 60 3>&1 1>&2 2>&3)
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
        whiptail --scrolltext --title "$whip_title" --msgbox "$formatted_str" 25 80
    done
}

# Open file by first selecting its file path and matching by file name pattern and tag pattern.
open_file_by_filepath() {
    select_dir_paginated() {
        local page_size=80   # number of items per page
        local page=0
        local choice=""
        local dirs
        local total_pages
        local menu_items=()
        
        # Extract unique directories
        dirs=$(cut -d'|' -f1 "${EBOOKS_DB}" | sed -E 's:/[^/]+$::' | sort | uniq)
        
        # Convert dirs to array
        IFS=$'\n' read -rd '' -a dirs_array <<< "$dirs"
        
        if (( ${#dirs_array[@]} == 0 )); then
            whiptail --title "Attention" \
                    --msgbox "No directories found! Perhaps ebooks db is empty." \
                    10 60
            return 1
        fi

        # Calculate total pages
        total_pages=$(( (${#dirs_array[@]} + page_size - 1) / page_size ))
        
        while true; do
            menu_items=()
            # Slice array for current page
            start=$(( page * page_size ))
            end=$(( start + page_size ))
            (( end > ${#dirs_array[@]} )) && end=${#dirs_array[@]}
            
            for (( i=start; i<end; i++ )); do
                menu_items+=( "${dirs_array[i]}" "" )
            done
            
            # Add navigation options if needed
            (( page > 0 )) && menu_items+=( "<< Prev" "" )
            (( page < total_pages - 1 )) && menu_items+=( "Next >>" "" )
            
            # Show menu
            local sel
            sel=$(whiptail --title "Select Directory" \
                        --menu "Choose a directory for registered files:" \
                        20 170 10 \
                        "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1            
            
            case "$sel" in
                "Next >>")
                    ((page++))
                    ;;
                "<< Prev")
                    ((page--))
                    ;;
                *)
                    choice="$sel"
                    break
                    ;;
            esac
        done
        
        echo "$choice"
    }

    # Initial message.
    whiptail --title "Open File By File Path" --msgbox \
"This feature allows you to open a registered file by first choosing a file path from registered files:\n\
After choosing a path from the list, you can further narrow the search by both file name(glob) and tag(literal substring match).\n\
Then, you can select to open a file item." 20 80

    # If EBOOKS_DB are empty
    # TAGS_DB are not mandatory here.
    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }    

    # First, choose the path among registered files.

    # FIX: PAGINATE SELECTION OF DIR
    local choice
    choice="$(select_dir_paginated)" || return 1

    # Display all lines in ebooks.db that match the chosen directory
    # Displays matching lines from ebooks.db that has the chosen dir.
    local matching_files_in_chosen_dir="$(grep -E "^${choice}/[^/]+\|" ${EBOOKS_DB})"

    # Now, get from user pattern and tag_pattern to further narrow the search.
    # REPLACE BOOLEAN SEARCH WITH GLOBBING.

    local pattern regex filtered_paths filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter glob pattern for file names (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"
    pattern="${pattern,,}"

    # Convert pattern to regex using your existing parse_expr function
    #regex=$(parse_expr "$pattern")

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file name is considered
    #filtered_paths="$(cut -d'|' -f1 <(echo "$matching_files_in_chosen_dir") | grep -iP "$regex")"
    # filtered_paths="$(
    #     while IFS='|' read -r path rest; do
    #         fname=${path##*/}
    #         if grep -iqP "$regex" <<< "$fname"; then
    #             echo "$path|$rest"
    #         fi
    #     done <<< "$matching_files_in_chosen_dir"
    # )"

    filtered_paths="$(
    awk -F'|' -v glob="$pattern" '
    BEGIN {
        IGNORECASE = 1
        # build regex from glob
        re = "^"
        for (i = 1; i <= length(glob); ++i) {
        c = substr(glob, i, 1)
        if (c == "*")      re = re ".*"
        else if (c == "?") re = re "."
        else {
            if (c ~ /[][\.\\^$+(){}|]/) re = re "\\" c
            else re = re c
        }
        }
        re = re "$"
    }
    {
        if ($1 ~ re) print $0
    }
    ' <<< "$matching_files_in_chosen_dir"
    )"

    if [ -z "$filtered_paths" ]; then
        whiptail --msgbox "No files match the given file name pattern." 8 60
        return 1
    fi

    #filtered_lines=$(grep -F -f <(echo "$filtered_paths" | sed 's/$/|/') "$EBOOKS_DB")     # this seems wrong.
    filtered_lines="$filtered_paths"    # seems redundant but failsafe.

    # DEBUG
    #echo filtered lines:
    #echo "$filtered_lines"
    #exit 1

    # Tag pattern info. Inform user that tag patterns is not regex or globbing but simple substring match.
    whiptail --title "IMPORTANT NOTE about Tag Patterns" --msgbox \
    "You are about to provide value for a tag pattern. Remember that it is not regex or globbing but simple substring match.\n\
This means if you enter '*schaum*' \\* will be matched literally not as wildcard." 12 60

    # Step 2: Ask the user for a tag search pattern
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (literal substring match; if empty wildcard):" 8 60 3>&1 1>&2 2>&3)
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

add_ebooks_from_checklist() {
    local ITEMS_PER_PAGE=100
    local start_dir="$(pwd)"
    local current_dir="$start_dir"
    declare -A global_selected

    # Ensure the eBooks DB exists
    touch "$EBOOKS_DB"

    # Outer loop: directory traversal
    while true; do
        # Build lists of subdirs and files
        mapfile -t dirs < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type d | sort)
        mapfile -t files < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type f | sort)

        # Combine into one array for paging
        local -a items=("${dirs[@]}" "${files[@]}")
        local total=${#items[@]}
        local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
        local current_page=0

        # Paging & selection within this directory
        while true; do
            local start=$(( current_page * ITEMS_PER_PAGE ))
            local end=$(( start + ITEMS_PER_PAGE ))
            (( end > total )) && end=$total

            # Build checklist entries
            local -a choices=()
            for i in $(seq "$start" $((end - 1))); do
                local path="${items[$i]}"
                local name="$(basename "$path")"

                local name_tr
                name_tr="$(truncate_filename "$name" 80)"

                if [[ -d "$path" ]]; then
                    choices+=("dir_$i" "[DIR] $name_tr" "OFF")
                else
                    local state="OFF"
                    [[ "${global_selected[$path]}" == "1" ]] && state="ON"
                    choices+=("file_$i" "$name_tr" "$state")
                fi
            done

            # Navigation controls
            choices+=("__up__"   "[DIR] .. (parent)"            "OFF")
            (( current_page > 0 ))        && choices+=("__prev__" "Previous page"               "OFF")
            (( current_page < pages-1 ))  && choices+=("__next__" "Next page"                   "OFF")
            choices+=("__add__" "Proceed to add selected files" "OFF")

            # Show the checklist
            local result
            result=$(whiptail \
                --title "Add eBooks: ${current_dir}" \
                --checklist "Page $((current_page+1))/$pages\nSelect files/directories or navigation action:" \
                20 100 10 \
                "${choices[@]}" \
                3>&1 1>&2 2>&3) \
                || { return 1; }

            # Normalize and split selections
            result=${result//\"/}
            IFS=' ' read -r -a sel_tags <<< "$result"

            ##
            # Snapshot the page’s file selections immediately,
            # so that global_selected is updated on any navigation.
            for i in $(seq "$start" $((end - 1))); do
                local p="${items[$i]}"
                if [[ -f "$p" ]]; then
                    if printf "%s\n" "${sel_tags[@]}" | grep -qx "file_$i"; then
                        global_selected["$p"]=1
                    else
                        unset global_selected["$p"]
                    fi
                fi
            done
            ##

            # Count selection types
            local movement_nav_count=0 dir_count=0 proceed_count=0 file_count=0
            for tag in "${sel_tags[@]}"; do
                case "$tag" in
                    "__up__"|"__prev__"|"__next__") ((movement_nav_count++)) ;;
                    "__add__")                       ((proceed_count++)) ;;
                    dir_*)                           ((dir_count++)) ;;
                    file_*)                          ((file_count++)) ;;
                esac
            done

            # Validation rules
            if (( movement_nav_count > 1 )); then
                whiptail --title "Invalid Selection" --msgbox "Please select only one of Previous, Next, or Up." 10 40
                continue
            fi
            if (( dir_count > 1 )); then
                whiptail --title "Invalid Selection" --msgbox "Please select only one directory at a time." 10 40
                continue
            fi
            if (( proceed_count > 1 )); then
                whiptail --title "Invalid Selection" --msgbox "Please select Proceed only once." 10 40
                continue
            fi
            if (( movement_nav_count == 1 )) && (( dir_count+proceed_count > 0 )); then
                whiptail --title "Invalid Selection" --msgbox "Navigation (Up/Prev/Next) cannot be combined with files, directories, or Proceed." 10 60
                continue
            fi
            if (( dir_count == 1 )) && (( proceed_count+movement_nav_count > 0 )); then
                whiptail --title "Invalid Selection" --msgbox "Directory selection cannot be combined with files, navigation, or Proceed." 10 60
                continue
            fi
            if (( proceed_count == 1 )) && (( movement_nav_count+dir_count > 0 )); then
                whiptail --title "Invalid Selection" --msgbox "Proceed cannot be combined with navigation or directory selection." 10 60
                continue
            fi

            # Handle movement navigation
            if (( movement_nav_count == 1 )); then
                if printf "%s\n" "${sel_tags[@]}" | grep -qx "__up__"; then
                    current_dir="$(dirname "$current_dir")"
                    break
                elif printf "%s\n" "${sel_tags[@]}" | grep -qx "__next__"; then
                    (( current_page++ ))
                else
                    (( current_page-- ))
                fi
                continue
            fi

            # Handle directory traversal
            if (( dir_count == 1 )); then
                for tag in "${sel_tags[@]}"; do
                    [[ "$tag" == dir_* ]] && idx="${tag#dir_}"
                done
                current_dir="${items[$idx]}"
                break
            fi

            # Handle Proceed
            if (( proceed_count == 1 )); then
                break 2
            fi

            # Otherwise refresh page with updated selections
        done
    done

    # Gather all files marked for addition
    local -a to_add=()
    for path in "${!global_selected[@]}"; do
        [[ "${global_selected[$path]}" == "1" ]] && to_add+=("$path")
    done

    if [ ${#to_add[@]} -eq 0 ]; then
        whiptail --msgbox "No eBooks selected." 8 40
        return 1
    fi

    # Confirm and write to DB
    local msg="These files will be added to $EBOOKS_DB (skipping duplicates):\n"
    for f in "${to_add[@]}"; do
        msg+="  $f\n"
    done

    if whiptail --scrolltext --yesno "$msg" 20 78 --title "Confirm Addition"; then
        for f in "${to_add[@]}"; do
            if ! grep -Fq "${f}|" "$EBOOKS_DB"; then
                echo "${f}|" >> "$EBOOKS_DB"
            fi
        done
        whiptail --msgbox "eBooks added successfully." 8 40
    else
        whiptail --msgbox "Addition cancelled." 8 40
    fi
}

rename_and_reregister_illegal_ebook_filenames() {
    # Info msgbox about what this function does
    whiptail --title "Info" --msgbox \
"Files registered in ebooks database can't have |,#:; characters in their file names \
because they are illegal in Manage Notes operations. \n\n\
This function will rename the file names accordingly both in ebooks database \
and physically on drive. You can also revert the changes later." 15 80

    local EBOOKS_DB_BACKUP="$EBOOKS_DB.backup"
    local LOG_FILE="$EBOOKS_DB.rename.log"
    local TEMP_DB
    TEMP_DB=$(mktemp) || return 1
    local -A used_paths=()
    local -a changes=()
    local -a new_lines=()

    # is this necessary? it's giving no such file error if user selects not to go ahead with renaming.
    touch /tmp/changes.tmp /tmp/new_lines.tmp 2>/dev/null

    # If ebooks.db and ebooks.db.backup files are equal content
    # then we shouldn't proceed!    
    if [[ -f "$EBOOKS_DB_BACKUP" ]] && cmp -s "$EBOOKS_DB" "$EBOOKS_DB_BACKUP"; then
        whiptail --title "Error" --msgbox "Something is wrong. Start afresh by deleting ${EBOOKS_DB_BACKUP} file and try again." 10 50 </dev/tty >/dev/tty
        #echo "ebooks db and ebooks db backup files are the same!" >&2   # debug
        return 1
    fi

    # Create new backup of original database
    cp -- "$EBOOKS_DB" "${EBOOKS_DB_BACKUP}_" || return 1

    # Display whiptail message telling user to wait
    TERM=ansi whiptail --title "Processing" \
         --infobox "Collecting information about illegal filenames registered inside ebooks database.\n\nPlease wait..." 10 60

    # First pass: collect changes and prepare new database
    # Process in awk
    awk -F'|' -v OFS='|' '
    function sanitize(name) {
        gsub(/[,:#;]/, "_", name)
        return name
    }

    {
        path = $1
        tags = $2

        dir = path
        sub(/\/[^\/]*$/, "", dir)  # dirname
        old_basename = path
        sub(/^.*\//, "", old_basename)  # basename

        new_basename = sanitize(old_basename)
        new_path = dir "/" new_basename

        # Only rename if old file name and sanitized version differs
        if (new_basename != old_basename) {
            counter = 1
            while (new_path in used || system("[ -e \"" new_path "\" ]") == 0) {
                split(new_basename, parts, /\./)
                if (length(parts) == 1) {
                    new_basename = parts[1] "_" counter
                } else {
                    ext = parts[length(parts)]
                    name_part = substr(new_basename, 1, length(new_basename) - length(ext) - 1)
                    new_basename = name_part "_" counter "." ext
                }
                new_path = dir "/" new_basename
                counter++
            }
            used[new_path] = 1
            print path "|" new_path > "/tmp/changes.tmp"
            print new_path "|" tags > "/tmp/new_lines.tmp"
        } else {
            # Name unchanged; keep line as-is
            print $0 > "/tmp/new_lines.tmp"
        }
    }
    ' "${EBOOKS_DB_BACKUP}_"

    # Read back into bash arrays and associative array
    while IFS='|' read -r old new; do
        changes+=("$old|$new")
        used_paths["$new"]=1
    done < /tmp/changes.tmp

    while IFS= read -r line; do
        new_lines+=("$line")
    done < /tmp/new_lines.tmp

    # Cleanup temp files
    rm -f /tmp/changes.tmp /tmp/new_lines.tmp 2>/dev/null

    # Show confirmation dialog if changes needed
    if [[ ${#changes[@]} -gt 0 ]]; then
        local change_list
        change_list=$(mktemp) || return 1
        
        for change in "${changes[@]}"; do
            IFS='|' read -r old new <<< "$change"
            echo "  $old -> $new" >> "$change_list"
        done

        whiptail --title "Files to be renamed (${#changes[@]} files)" --scrolltext --textbox "$change_list" 20 80
        rm -f "$change_list"

        if ! whiptail --title "Confirmation" --yesno "Proceed with these changes?" 10 80; then
            rm -f "$TEMP_DB"
            #echo "Operation cancelled by user" >&2
            rm -f "${EBOOKS_DB_BACKUP}_"
            return 1
        fi

        # Only create ebooks db backup file if renaming has occurred.
        cp "${EBOOKS_DB_BACKUP}_" "${EBOOKS_DB_BACKUP}"
        rm -f "${EBOOKS_DB_BACKUP}_"
    else
        whiptail --title "No changes needed" --msgbox "No files with illegal characters found" 8 50
        rm -f "$TEMP_DB"
        rm -f "${EBOOKS_DB_BACKUP}_"
        return 0
    fi

    # Display whiptail message telling user to wait
    TERM=ansi whiptail --title "Processing" \
         --infobox "Changes being applied.\n\nPlease wait..." 10 60

    # Second pass: execute changes
    : > "$LOG_FILE"
    for change in "${changes[@]}"; do
        IFS='|' read -r old new <<< "$change"

        # Debug
        #echo "Before mv:" >&2
        #echo "old: $old" >&2
        #echo "new: $new" >&2
        #exit

        if ! mv -- "$old" "$new"; then
            echo "Error: Failed to rename '$old' to '$new'" >&2
            whiptail --title "Error" --msgbox "Failed to rename '$old' to '$new'. Aborting." 8 60
            rm -f "$TEMP_DB"
            return 1
        fi
        echo "$old|$new" >> "$LOG_FILE"
    done

    # Write new database
    printf "%s\n" "${new_lines[@]}" > "$TEMP_DB"
    mv -- "$TEMP_DB" "$EBOOKS_DB" || return 1

    whiptail --title "Success" --msgbox "Files renamed and database updated!\n\nBackup: $EBOOKS_DB_BACKUP" 12 80
}

revert_rename_illegal_ebook_filenames() {  
    check_backup_and_log() {
        # 1. Check line counts equal
        if [[ $(wc -l < "$EBOOKS_DB") -ne $(wc -l < "$EBOOKS_DB_BACKUP") ]]; then
            echo "Line count mismatch between DB and backup" >&2
            return 1
        fi

        # 2. Check every new_path exists, but don't exit early
        local missing=0

        awk -F'|' '
            {
                new_path = $2
                if (system("[ -f \"" new_path "\" ]") != 0) {
                    printf("Missing file in filesystem: %s\n", new_path) > "/dev/stderr"
                    missing = 1
                }
            }
            END {
                exit missing
            }
        ' "$LOG_FILE" || return 1

        return 0
    }
  
    # Info msgbox about what this function does
    whiptail --title "Info" --msgbox \
"This function reverts changes made by Rename and Reregister Illegal Ebook Filenames function. \
It reverts both ebooks database and physical file names on drive." 10 80

    local EBOOKS_DB_BACKUP="$EBOOKS_DB.backup"
    local LOG_FILE="$EBOOKS_DB.rename.log"

    if [[ ! -f "$EBOOKS_DB_BACKUP" || ! -f "$LOG_FILE" ]]; then
        whiptail --title "Attention" --msgbox "There is nothing to revert." 8 50
        return 1
    fi

    # Extra check to see if ebooks db backup file and log file's integrity holds - test this at the next opportunity!
    check_backup_and_log || return 1

    # Show confirmation dialog
    if ! whiptail --title "Confirmation" --yesno "This will restore original filenames and database. Proceed?" 10 80; then
        #echo "Revert cancelled by user" >&2
        return 1
    fi

    # Working... infobox
    TERM=ansi whiptail --title "Info" --infobox "Working..." 8 40

    cp -- "$EBOOKS_DB_BACKUP" "$EBOOKS_DB" || return 1

    while IFS= read -r line; do
        IFS='|' read -r original_path new_path <<< "$line"
        if [[ -e "$new_path" ]]; then
            if ! mv -f -- "$new_path" "$original_path"; then
                echo "Warning: Failed to revert '$new_path' to '$original_path'" >&2
            fi
        else
            echo "Warning: '$new_path' does not exist. Skipping." >&2
        fi
    done < "$LOG_FILE"

    whiptail --title "Success" --msgbox "Successfully reverted all changes!\n\nOriginal database restored from backup." 12 80
}

remove_ebooks_from_checklist() {
    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40
        return 1
    }

    local ITEMS_PER_PAGE=100
    local current_page=0
    declare -A selected_entries  # Keys are entry indices, value is 1 if selected

    # Ask for search term first
    local search_term
    search_term=$(whiptail --inputbox "Enter a string to filter by filename (globbing; leave empty for wildcard):" 8 50 --title "Search Filter" 3>&1 1>&2 2>&3) || { 
        #whiptail --msgbox "Cancelled." 8 40
        return 1
    }

    : ${search_term:=*}

    # Prepare case-insensitive search
    local search_term_lower=""
    [[ -n "$search_term" ]] && search_term_lower="$(tr '[:upper:]' '[:lower:]' <<< "$search_term")"

    # Waiting... info box
    TERM=ansi whiptail --title "Building..." --infobox "Preparing menu, please wait" 8 40

    # Read entries with filtering
    local -a entries=()
    while IFS='|' read -r path tags; do
        # Filter logic
        if [[ "$search_term" == "*" ]]; then  # No filter
            entries+=("$path")
        else
            local filename="$(basename "$path")"
            local filename_lower="$(tr '[:upper:]' '[:lower:]' <<< "$filename")"
            [[ "$filename_lower" == $search_term_lower ]] && entries+=("$path")
        fi
    done < "$EBOOKS_DB"

    # Empty state message
    local total=${#entries[@]}
    if (( total == 0 )); then
        if [[ -n "$search_term" ]]; then
            whiptail --msgbox "No eBooks found matching '$search_term'." 8 40
        else
            whiptail --msgbox "No eBooks in database." 8 40
        fi
        return 1
    fi
    local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))

    # Pagination loop
    while true; do
	# Waiting... info box
	TERM=ansi whiptail --title "Building..." --infobox "Preparing menu, please wait" 8 40

        local start=$(( current_page * ITEMS_PER_PAGE ))
        local end=$(( start + ITEMS_PER_PAGE ))
        (( end > total )) && end=$total

        # Build choices for the current page
        local -a choices=()
        for ((i = start; i < end; i++)); do
            local path="${entries[$i]}"
            
            # Split path into directory and filename
			local dir_part=$(dirname "$path")
			local file_part=$(basename "$path")
			# Truncate components
			local trunc_dir=$(truncate_dirname "$dir_part")
			local trunc_file=$(truncate_filename "$file_part" 50)
			local truncated_path="${trunc_dir}/${trunc_file}"            

            local state="OFF"
            [[ -n "${selected_entries[$i]}" ]] && state="ON"
            choices+=("entry_$i" "$truncated_path" "$state")
        done

        # Add navigation controls
        if (( current_page > 0 )); then
            choices+=("__prev__" "Previous page" "OFF")
        fi
        if (( current_page < pages - 1 )); then
            choices+=("__next__" "Next page" "OFF")
        fi
        choices+=("__proceed__" "Proceed to remove selected entries" "OFF")

        # Show checklist
        local result
        result=$(whiptail \
            --title "Remove Registered eBooks From DB" \
            --checklist "Page $((current_page+1))/$pages\nSelect entries to remove or navigation action:" \
            20 150 10 \
            "${choices[@]}" \
            3>&1 1>&2 2>&3) \
            || { whiptail --msgbox "Cancelled." 8 40; return 1; }

        # Process selections
        IFS=' ' read -r -a sel_tags <<< "${result//\"/}"

        # Update selected_entries for current page
        for ((i = start; i < end; i++)); do
            local tag="entry_$i"
            if printf "%s\n" "${sel_tags[@]}" | grep -qx "$tag"; then
                selected_entries["$i"]=1
            else
                unset selected_entries["$i"]
            fi
        done

        # Count selection types
        local nav_count=0 proceed_count=0 entry_count=0
        for tag in "${sel_tags[@]}"; do
            case "$tag" in
                __prev__|__next__) ((nav_count++)) ;;
                __proceed__) ((proceed_count++)) ;;
                entry_*) ((entry_count++)) ;;
            esac
        done

        # Validate selections
        if (( nav_count > 1 || proceed_count > 1 )); then
            whiptail --msgbox "Please select only one of navigation actions." 10 40
            continue
        fi
        if (( nav_count + proceed_count > 1 )); then
            whiptail --msgbox "Please select only one action (Previous, Next, or Proceed)." 10 40
            continue
        fi

        # Handle navigation
        if (( nav_count == 1 )); then
            for tag in "${sel_tags[@]}"; do
                case "$tag" in
                    __prev__)
                        ((current_page--))
                        # Ensure current_page doesn't go below 0
                        ((current_page < 0)) && current_page=0                        
                        break
                        ;;
                    __next__)
                        ((current_page++))
                        # Ensure current_page doesn't exceed pages-1
                        ((current_page >= pages)) && current_page=$((pages - 1))                        
                        break
                        ;;
                esac
            done
            continue
        fi

        # Handle proceed
        if (( proceed_count == 1 )); then
            break
        fi

        # If no action, continue to next iteration (same page)
    done

    # Collect selected paths
    local -a selected_paths=()
    for index in "${!selected_entries[@]}"; do
        selected_paths+=("${entries[$index]}")
    done

    if (( ${#selected_paths[@]} == 0 )); then
        whiptail --msgbox "No entries selected." 8 40
        return 1
    fi

    # Confirm removal
    local msg="The following entries will be removed:\n"
    for path in "${selected_paths[@]}"; do
        msg+="  $path\n"
    done
    if whiptail --scrolltext --yesno "$msg" 20 78 --title "Confirm Removal"; then
        # Create a temporary file
        local tmp_db
        tmp_db=$(mktemp) || { whiptail --msgbox "Error creating temporary file." 8 40; return 1; }
        # Use grep to exclude selected paths
        grep -vf <(printf '^%s|\n' "${selected_paths[@]}") "$EBOOKS_DB" > "$tmp_db"
                
        # Replace the original database
        mv "$tmp_db" "$EBOOKS_DB"
        whiptail --msgbox "Entries removed successfully." 8 40
    else
        whiptail --msgbox "Removal cancelled." 8 40
    fi
}

dissociate_tag_from_checklist() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    touch "$EBOOKS_DB" "$TAGS_DB"

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }      

    local ITEMS_PER_PAGE=100
    local current_page=0
    declare -A selected_entries  # Keys are entry indices, value is 1 if selected

    # Ask for tag to dissociate
    local tag_to_remove
    # build tag menu options (tag and empty description)
    local -a tag_choices=()
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tag_choices+=("$tag" "")
    done < "$TAGS_DB"
    if [[ ${#tag_choices[@]} -eq 0 ]]; then
        whiptail --msgbox "No tags found in database." 8 40
        return 1
    fi

    # FIX: FLATTEN TAG_CHOICES, SORT, THEN REBUILD
    # Step 1: Flatten.
    local pairs=()
    for ((i=0; i<${#tag_choices[@]}; i+=2)); do
        pairs+=("${tag_choices[i]}")  # Only the tag matters since values are empty
    done
    
    # Step 2: Sort tags
    local sorted=()
    IFS=$'\n' sorted=($(sort <<<"${pairs[*]}"))
    unset IFS
    
    # Step 3: Rebuild tag_choices array
    tag_choices=()
    for tag in "${sorted[@]}"; do
        tag_choices+=("$tag" "")
    done
    # END FIX.

    # tag_to_remove=$(whiptail --title "Select Tag to Remove" --menu "Choose a tag to dissociate from eBooks:" \
    #     20 60 10 \
    #     "${tag_choices[@]}" \
    #     3>&1 1>&2 2>&3) || { whiptail --msgbox "Cancelled." 8 40; return 1; }

    # FIX: PAGINATE TAG SELECTION.
    local tag_to_remove
    tag_to_remove="$(paginate_tags_menu "Select Tag to Remove" "${tag_choices[@]}")" || return 1

    # Gather entries containing that tag
    local -a entries=()
    while IFS='|' read -r path tags; do
        IFS=',' read -ra tag_array <<< "$tags"
        for t in "${tag_array[@]}"; do
            [[ "$t" == "$tag_to_remove" ]] && entries+=("$path|$tags") && break
        done
    done < "$EBOOKS_DB"

    local total=${#entries[@]}
    if (( total == 0 )); then
        whiptail --msgbox "No eBooks found with tag '$tag_to_remove'." 8 50
        return 1
    fi
    local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))

    # Pagination loop
    while true; do        
        local start=$(( current_page * ITEMS_PER_PAGE ))
        local end=$(( start + ITEMS_PER_PAGE ))
        (( end > total )) && end=$total

        local -a choices=()
        for ((i = start; i < end; i++)); do
            local entry="${entries[$i]}"
            local path="${entry%%|*}"
            # truncate display
            local dir_part=$(dirname "$path")
            local file_part=$(basename "$path")
            local trunc_dir=$(truncate_dirname "$dir_part")
            local trunc_file=$(truncate_filename "$file_part" 50)
            local disp="${trunc_dir}/${trunc_file}"

            local state="OFF"
            [[ -n "${selected_entries[$i]}" ]] && state="ON"
            choices+=("entry_$i" "$disp" "$state")
        done
        # nav
        (( current_page > 0 )) && choices+=("__prev__" "Previous page" OFF)
        (( current_page < pages-1 )) && choices+=("__next__" "Next page" OFF)
        choices+=("__proceed__" "Proceed to dissociate tag" OFF)

        local result
        result=$(whiptail --title "Dissociate Tag: $tag_to_remove" \
            --checklist "Page $((current_page+1))/$pages\nSelect eBooks to update or navigate:" \
            20 150 10 "${choices[@]}" 3>&1 1>&2 2>&3) \
            || { return 1; }

        IFS=' ' read -r -a sel_tags <<< "${result//\"/}"
        # update selection
        for ((i = start; i < end; i++)); do
            local tagkey="entry_$i"
            if printf "%s\n" "${sel_tags[@]}" | grep -qx "$tagkey"; then
                selected_entries[$i]=1
            else
                unset selected_entries[$i]
            fi
        done

        # count actions
        local nav_count=0 proceed_count=0
        for tag in "${sel_tags[@]}"; do
            [[ "$tag" == __prev__ || "$tag" == __next__ ]] && ((nav_count++))
            [[ "$tag" == __proceed__ ]] && ((proceed_count++))
        done
        # validations
        if (( nav_count > 1 || proceed_count > 1 )); then
            whiptail --msgbox "Select only one navigation or proceed action." 10 40
            continue
        fi
        if (( nav_count + proceed_action > 1 )); then
            whiptail --msgbox "Do not select both navigation option and proceed at the same time." 10 40
			continue
        fi
        
        # navigation
        if (( nav_count == 1 )); then
            for tag in "${sel_tags[@]}"; do
                case "$tag" in
                    __prev__) ((current_page--)); ((current_page<0)) && current_page=0;;
                    __next__) ((current_page++)); ((current_page>=pages)) && current_page=$((pages-1));;
                esac
            done
            continue
        fi
        # proceed
        (( proceed_count == 1 )) && break
    done

    # Build selected paths
    local -a selected_paths=()
    for idx in "${!selected_entries[@]}"; do
        selected_paths+=("${entries[$idx]%%|*}")
    done
    if (( ${#selected_paths[@]} == 0 )); then
        whiptail --msgbox "No entries selected." 8 40
        return 1
    fi

    # Confirm
    local msg="The tag '$tag_to_remove' will be removed from:\n"
    for p in "${selected_paths[@]}"; do msg+="  $p\n"; done
    if ! whiptail --scrolltext --yesno "$msg" 20 78 --title "Confirm Dissociation"; then
        whiptail --msgbox "Cancelled." 8 40
        return 1
    fi

    # Process removal
    local tmp_db
    tmp_db=$(mktemp) || { whiptail --msgbox "Error creating temp file." 8 40; return 1; }
    declare -A tofix
    for p in "${selected_paths[@]}"; do tofix["$p"]=1; done
    while IFS='|' read -r path tags; do
        if [[ -n "${tofix[$path]}" ]]; then
            IFS=',' read -ra arr <<< "$tags"
            local new_arr=()
            for t in "${arr[@]}"; do
                [[ "$t" != "$tag_to_remove" && -n "$t" ]] && new_arr+=("$t")
            done
            local new_tags
            # only join if there are remaining tags
            if (( ${#new_arr[@]} > 0 )); then
                new_tags="$(IFS=','; echo "${new_arr[*]}")"
            else
                new_tags=""
            fi
            echo "$path|$new_tags" >> "$tmp_db"
        else
            echo "$path|$tags" >> "$tmp_db"
        fi
    done < "$EBOOKS_DB"
    mv "$tmp_db" "$EBOOKS_DB"
    whiptail --msgbox "Tag '$tag_to_remove' dissociated successfully." 8 50
}

associate_tag_from_checklist() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    touch "$EBOOKS_DB" "$TAGS_DB"

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }        

    local ITEMS_PER_PAGE=100
    local current_page=0
    declare -A selected_entries  # Keys are entry indices, value is 1 if selected

    # --- Step 1: Pick a tag from $TAGS_DB ---
    local -a tags
    while IFS= read -r tag; do
        tags+=("$tag")
    done < "$TAGS_DB"

    if (( ${#tags[@]} == 0 )); then
        whiptail --msgbox "No tags available in $TAGS_DB." 8 40
        return 1
    fi

    # FIX: SORT TAGS AND REBUILD TAGS ARRAY.
    # Sort the array
    local sorted=()
    IFS=$'\n' sorted=($(sort <<<"${tags[*]}"))
    unset IFS
    
    # Rebuild the original array
    tags=("${sorted[@]}")
    # END FIX.


    # Build a numeric menu so we can handle spaces in tag names
    local -a tag_choices=()
    for i in "${!tags[@]}"; do
        tag_choices+=("$i" "${tags[$i]}")
    done

    # local selected_index
    # selected_index=$(whiptail --title "Select Tag to Associate" \
    #     --menu "Choose one tag:" 20 60 10 \
    #     "${tag_choices[@]}" \
    #     3>&1 1>&2 2>&3) || {
    #         whiptail --msgbox "Cancelled." 8 40
    #         return 1
    #     }

    # FIX: PAGINATE TAG SELECTION.
    local selected_index
    selected_index="$(paginate_tags_menu "Select Tag to Associate" "${tag_choices[@]}")" || return 1

    local selected_tag="${tags[$selected_index]}"

    # --- Step 2: Ask for filename filter ---
    local search_term
    search_term=$(whiptail --inputbox \
        "Enter a substring to filter filenames (globbing; empty is wildcard):" \
        8 50 --title "Search Filter" \
        3>&1 1>&2 2>&3) || {
            #whiptail --msgbox "Cancelled." 8 40
            return 1
        }

    : ${search_term:=*}
    local search_lower="${search_term,,}"
        
    # Bulding... infobox
    TERM=ansi whiptail --title "Building" --infobox "Building menu.\n\nPlease wait..." 10 40

    # --- Step 3: Load & filter e-book entries ---
    local -a entries=()
    while IFS='|' read -r path tags_on_book; do
        local file_="$(basename "$path")"

        if [[ "$search_term" == "*" ]] || \
           [[ "${file_,,}" == $search_lower ]]; then
            entries+=("$path|$tags_on_book")
        fi
    done < "$EBOOKS_DB"

    if (( ${#entries[@]} == 0 )); then
        whiptail --msgbox "No eBooks found matching '$search_term'." 8 40
        return 1
    fi

    local total=${#entries[@]}
    local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))

    # --- Step 4: Paginated checklist of e-books ---
    while true; do        
        # Bulding... infobox
        TERM=ansi whiptail --title "Processing" --infobox "Please wait..." 10 40

        local start=$(( current_page * ITEMS_PER_PAGE ))
        local end=$(( start + ITEMS_PER_PAGE ))
        (( end > total )) && end=$total

        local -a choices=()
        for ((i = start; i < end; i++)); do
            local entry="${entries[$i]}"
            local path="${entry%%|*}"
            local display="$(truncate_filename "$(basename "$path")" 50)"
            local state="OFF"
            [[ -n "${selected_entries[$i]}" ]] && state="ON"
            choices+=("entry_$i" "$display" "$state")
        done

        # navigation
        (( current_page > 0 )) && choices+=("__prev__" "< Previous page" OFF)
        (( current_page < pages-1 )) && choices+=("__next__" "> Next page" OFF)
        choices+=("__proceed__" "Proceed to tag association" OFF)

        local result
        result=$(whiptail --title "Associate Tag: Page $((current_page+1))/$pages" \
            --checklist "Select e-Books to tag or navigate:" \
            20 100 10 \
            "${choices[@]}" \
            3>&1 1>&2 2>&3) || {
                whiptail --msgbox "Cancelled." 8 40
                return 1
            }

        IFS=' ' read -r -a sel_tags <<< "${result//\"/}"

        # update selected_entries
        for ((i = start; i < end; i++)); do
            tag="entry_$i"
            if printf '%s\n' "${sel_tags[@]}" | grep -qx "$tag"; then
                selected_entries[$i]=1
            else
                unset selected_entries[$i]
            fi
        done

        # Count selection types
        local nav=0 proc=0
        for tag in "${sel_tags[@]}"; do
            [[ $tag == __prev__ || $tag == __next__ ]] && ((nav++))
            [[ $tag == __proceed__ ]] && ((proc++))
        done

		# Validate selections
        if (( nav > 1 || proc > 1 )); then
            whiptail --msgbox "Please select only one of navigation actions." 10 40
            continue
        fi
        if (( nav + proc > 1 )); then
            whiptail --msgbox "Please select only one action (Previous, Next, or Proceed)." 10 40
            continue
        fi        

        # handle navigation
        if (( nav == 1 )); then
            for tag in "${sel_tags[@]}"; do
                [[ $tag == __prev__ ]] && ((current_page--))
                [[ $tag == __next__ ]] && ((current_page++))
            done
            (( current_page < 0 )) && current_page=0
            (( current_page >= pages )) && current_page=$((pages-1))
            continue
        fi

        # proceed
        (( proc == 1 )) && break
    done

    # --- Step 5: Collect selected entries & update DB ---
    local -a to_update=()
    for idx in "${!selected_entries[@]}"; do
        to_update+=("${entries[$idx]}")
    done

    if (( ${#to_update[@]} == 0 )); then
        whiptail --msgbox "No eBooks selected." 8 40
        return 1
    fi

    local msg="Tag '${selected_tag}' will be added to (excluding duplicates):\n"
    for line in "${to_update[@]}"; do
        msg+="  ${line%%|*}\n"
    done

    if ! whiptail --scrolltext --yesno "$msg" 20 70 --title "Confirm Association"; then
        whiptail --msgbox "Operation cancelled." 8 40
        return 1
    fi

    # perform in-place update without duplicating tags
    local tmp_db
    tmp_db=$(mktemp) || { whiptail --msgbox "Error creating temp file." 8 40; return 1; }

    while IFS='|' read -r path tags_on_book; do
        local new_tags="$tags_on_book"
        local line="$path|$tags_on_book"

        # if this is one of the selected entries, append only if missing
        if printf '%s\n' "${to_update[@]}" | grep -Fxq -- "$line"; then
            if [[ ",$tags_on_book," != *",$selected_tag,"* ]]; then
                if [[ -z "$new_tags" ]]; then
                    new_tags="$selected_tag"
                else
                    new_tags="$new_tags,$selected_tag"
                fi
            fi
        fi

        printf '%s|%s\n' "$path" "$new_tags" >> "$tmp_db"
    done < "$EBOOKS_DB"

    mv "$tmp_db" "$EBOOKS_DB"
    whiptail --msgbox "Tag '$selected_tag' associated successfully." 8 40
}

assoc_tag_by_filepath() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    # Help message
    whiptail --title "Help" \
         --msgbox "This function will associate your chosen tag to every file in a directory that you choose. \
You may choose from a list of directories registered in the ebooks db." 12 80 >/dev/tty

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }      

    # Read tags into array
    local tags=()
    if ! mapfile -t tags < "$TAGS_DB"; then
        whiptail --msgbox "Error: Failed to read tags database." 10 60 >/dev/tty
        return 1
    fi

    # Check if tags exist
    if [[ ${#tags[@]} -eq 0 ]]; then
        whiptail --msgbox "No tags found in database. Add tags first." 10 60 >/dev/tty
        return 1
    fi

    # FIX: SORT TAG AND REBUILD TAGS ARRAY
    # Sort the array
    IFS=$'\n' sorted=($(sort <<<"${tags[*]}"))
    unset IFS
    
    # Rebuild the original array
    tags=("${sorted[@]}")
    # END FIX.

    # Build tag selection menu
    local tag_menu_items=()
    for tag in "${tags[@]}"; do
        tag_menu_items+=("$tag" "")
    done

    # Select tag
    # local selected_tag
    # selected_tag=$(whiptail --title "Select Tag" --menu "Choose a tag to associate:" \
    #     20 150 10 "${tag_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    
    # [[ -z "$selected_tag" ]] && return 1 # User canceled

    # FIX: PAGINATE TAG SELECTION.
    local selected_tag
    selected_tag="$(paginate_tags_menu "Choose a tag to associate:" "${tag_menu_items[@]}")" || return 1

    # Get unique directories
    local dirs
    dirs=$(cut -d'|' -f1 "$EBOOKS_DB" | sed -E 's:/[^/]+$::' | sort | uniq)
    
    # Check if directories exist
    if [[ -z "$dirs" ]]; then
        whiptail --msgbox "No directories found in ebooks database." 10 60 >/dev/tty
        return 1
    fi

    # Build directory menu
    local dir_menu_items=()
    while IFS= read -r dir; do
        dir_menu_items+=("$dir" "")
    done <<< "$dirs"

    # Select directory
    local selected_dir
    selected_dir=$(whiptail --title "Select Directory" --menu "Choose directory to tag:" \
        20 150 10 "${dir_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    
    [[ -z "$selected_dir" ]] && return  # User canceled

    # # Escape special regex characters in directory path
    # local escaped_dir="$selected_dir"
    # #local escaped_dir="${selected_dir//\//\\/}"
    # #escaped_dir="${escaped_dir//./\\.}"
    # #escaped_dir="${escaped_dir//|/\\|}"
    # #escaped_dir="${escaped_dir//^/\\^}"
    # #escaped_dir="${escaped_dir//\$/\\\$}"
    # #escaped_dir="${escaped_dir//+/\\+}"
    # #escaped_dir="${escaped_dir//(/\(}"
    # #escaped_dir="${escaped_dir//)/\)}"
    # #escaped_dir="${escaped_dir//\[/\[}"
    # #escaped_dir="${escaped_dir//]/\]}"
    # #escaped_dir="${escaped_dir//\{/\{}"
    # #escaped_dir="${escaped_dir//\}/\}}"

    # # Get matching lines
    # local matching_lines
    # matching_lines=$(grep -E "^${escaped_dir}/[^/]+\|" "$EBOOKS_DB")

    # FIX: AWK REPLACEMENT (DOESN'T DO REGEX SO ESCAPING META NOT REQUIRED)
    local matching_lines=$(
        awk -v dir="$selected_dir" -F'|' '
        BEGIN {
            prefix = dir "/"
            plen = length(prefix)
        }
        {
            if (index($1, prefix) == 1) {
                rest = substr($1, plen+1)
                if (length(rest) > 0 && index(rest, "/") == 0 && NF > 1) {
                    print
                }
            }
        }
        ' "$EBOOKS_DB"
    )

    # Debug
    #echo matching_lines: >&2
    #echo "$matching_lines" >&2
    #exit

    local escaped_dir="$selected_dir"   # just included here for failsafe.

    # Check for matches
    if [[ -z "$matching_lines" ]]; then
        whiptail --msgbox "No ebooks found in directory: $selected_dir" 10 60 >/dev/tty
        return 1
    fi

    # Prepare confirmation message
    local file_count
    file_count=$(wc -l <<< "$matching_lines")
    local sample_files
    sample_files=$(head -n 5 <<< "$matching_lines" | cut -d'|' -f1 | sed 's:.*/::')
    local message="Directory: $selected_dir\nTag: $selected_tag\nFiles: $file_count\n\nSample files:\n$sample_files"
    [[ $file_count -gt 5 ]] && message+="\n...and $((file_count - 5)) more"

    # Confirm action
    whiptail --scrolltext --yesno --title "Confirm Association" \
        "Add tag to ALL files in directory?\n\n$message" \
        20 60 --yes-button "Associate" --no-button "Cancel" </dev/tty >/dev/tty || return 1

	# Create temporary file for new database
	local temp_db
	temp_db=$(mktemp) || return 1
	local updated=0

	# Process every line in EBOOKS_DB
	while IFS= read -r line; do
		local filepath="${line%%|*}"
		local tags_str="${line#*|}"
    
		# Extract directory portion from filepath
		local parent_dir="${filepath%/*}"

		# Check if this file is in the selected directory
		if [[ "$parent_dir" == "$selected_dir" ]]; then
			# This file is in our target directory - check tag
			if [[ ",${tags_str}," == *",${selected_tag},"* ]]; then
				# Tag already exists - keep original line
				echo "$line" >> "$temp_db"
			else
				# Add new tag
				if [[ -z "$tags_str" ]]; then
					echo "${filepath}|${selected_tag}" >> "$temp_db"
				else
					echo "${filepath}|${tags_str},${selected_tag}" >> "$temp_db"
				fi
				((updated++))
			fi
		else
			# Not in selected directory - keep original line
			echo "$line" >> "$temp_db"
		fi
	done < "$EBOOKS_DB"    

    # Replace original database
    if ! mv "$temp_db" "$EBOOKS_DB"; then
        whiptail --msgbox "Error: Failed to update database." 10 60 >/dev/tty
        return 1
    fi

    # Show results
    whiptail --msgbox "Successfully updated ${updated} files with '${selected_tag}' tag." 10 60
}

dissoc_tag_by_filepath() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }
    
    # Help message
    whiptail --title "Help" \
         --msgbox "This function will dissociate your chosen tag to every file in a directory that you choose. \
You may choose from a list of directories registered in the ebooks db. It is inverse of associate tag by filepath function." 12 80 >/dev/tty	
	
    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }
    
    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }          

    # Read tags into array
    local tags=()
    if ! mapfile -t tags < "$TAGS_DB"; then
        whiptail --msgbox "Error: Failed to read tags database." 10 60 >/dev/tty
        return 1
    fi

    # Check if tags exist
    if [[ ${#tags[@]} -eq 0 ]]; then
        whiptail --msgbox "No tags found in database. Add tags first." 10 60 >/dev/tty
        return 1
    fi

    # FIX: FILTER TAGS IN TAGS ARRAY AND REBUILD TAGS ARRAY.
    # Sort the array
    local sorted=()
    IFS=$'\n' sorted=($(sort <<<"${tags[*]}"))
    unset IFS
    
    # Rebuild the original array
    tags=("${sorted[@]}")
    # FIX END.

    # Build tag selection menu
    local tag_menu_items=()
    for tag in "${tags[@]}"; do
        tag_menu_items+=("$tag" "")
    done

    # # Select tag
    # local selected_tag
    # selected_tag=$(whiptail --title "Remove Tag" --menu "Choose a tag to remove:" \
    #     20 150 10 "${tag_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    
    # [[ -z "$selected_tag" ]] && return 1 # User canceled

    # FIX: PAGINATE TAG SELECTION.
    local selected_tag
    selected_tag="$(paginate_tags_menu "Choose a tag to remove:" "${tag_menu_items[@]}")" || return 1

    # Get unique directories
    local dirs
    dirs=$(cut -d'|' -f1 "$EBOOKS_DB" | sed -E 's:/[^/]+$::' | sort | uniq)
    
    # Check if directories exist
    if [[ -z "$dirs" ]]; then
        whiptail --msgbox "No directories found in ebooks database." 10 60 >/dev/tty
        return 1
    fi

    # Build directory menu
    local dir_menu_items=()
    while IFS= read -r dir; do
        dir_menu_items+=("$dir" "")
    done <<< "$dirs"

    # Select directory
    local selected_dir
    selected_dir=$(whiptail --title "Select Directory" --menu "Choose directory to remove tag from:" \
        20 150 10 "${dir_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    
    [[ -z "$selected_dir" ]] && return 1 # User canceled

    # Get matching lines
    local matching_lines
    matching_lines=$(grep -E "^${selected_dir}/[^/]+\|" "$EBOOKS_DB")
    #matching_lines=$(grep -F "$selected_dir/" "$EBOOKS_DB")
    
    # Check for matches
    if [[ -z "$matching_lines" ]]; then
        whiptail --msgbox "No ebooks found in directory: $selected_dir" 10 60 >/dev/tty
        return 1
    fi

    # Prepare confirmation message
    local file_count
    file_count=$(wc -l <<< "$matching_lines")
    local sample_files
    sample_files=$(head -n 5 <<< "$matching_lines" | cut -d'|' -f1 | sed 's:.*/::')
    local message="Directory: $selected_dir\nTag: $selected_tag\nFiles: $file_count\n\nSample files:\n$sample_files"
    [[ $file_count -gt 5 ]] && message+="\n...and $((file_count - 5)) more"

    # Confirm action
    whiptail --scrolltext --yesno --title "Confirm Removal" \
        "Remove tag from ALL files in directory?\n\n$message" \
        20 60 --yes-button "Remove" --no-button "Cancel" </dev/tty >/dev/tty || return 1

    # Process updates
    local temp_db
    temp_db=$(mktemp) || return 1
    local removed=0

    while IFS= read -r line; do
        local filepath="${line%%|*}"
        local tags_str="${line#*|}"
        local parent_dir="${filepath%/*}"

        # Only process files in selected directory
        if [[ "$parent_dir" == "$selected_dir" ]]; then
            # Check if tag exists
            if [[ ",${tags_str}," == *",${selected_tag},"* ]]; then
                # Remove tag using pattern substitution
                tags_str=${tags_str//,$selected_tag/}  # Remove tag with leading comma
                tags_str=${tags_str//$selected_tag,/}  # Remove tag with trailing comma
                tags_str=${tags_str//$selected_tag/}   # Remove standalone tag
                
                # Clean up potential double commas
                tags_str=${tags_str//,,/,}
                
                # Remove leading/trailing commas
                tags_str=${tags_str#,}
                tags_str=${tags_str%,}
                
                # Remove any empty tag strings
                [[ -z "$tags_str" ]] && tags_str=""
                
                echo "${filepath}|${tags_str}" >> "$temp_db"
                ((removed++))
            else
                # Tag not present - keep original line
                echo "$line" >> "$temp_db"
            fi
        else
            # Not in selected directory - keep original line
            echo "$line" >> "$temp_db"
        fi
    done < "$EBOOKS_DB"

    # Replace original database
    if ! mv "$temp_db" "$EBOOKS_DB"; then
        whiptail --msgbox "Error: Failed to update database." 10 60 >/dev/tty
        return 1
    fi

    # Show results
    if ((removed > 0)); then
        whiptail --msgbox "Successfully removed '${selected_tag}' from $removed files." 10 60
    else
        whiptail --msgbox "No changes made. The tag was not found in any files." 10 60
    fi
}

remove_files_by_filepath() {
    # Inform user of the purpose
    whiptail --title "Attention" --msgbox "This function allows user to remove all files from ebooks db under file path. \
It does not search recursively but just files under selected path. If a file has a tag associated with it, it will not be removed. \
It does not delete the files physically on drive." 12 78 >/dev/tty

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    # Get unique directories
    local directories
    directories=$(cut -d'|' -f1 "${EBOOKS_DB}" | sed -E 's:/[^/]+$::' | sort | uniq)
    
    # Check if there are any directories
    if [[ -z "$directories" ]]; then
        whiptail --title "Error" --msgbox "No directories found in the database." 8 50 >/dev/tty
        return 1
    fi

    # Create whiptail menu options
    local menu_options=()
    while IFS= read -r dir; do
        menu_options+=("$dir" "")
    done <<< "$directories"

    # Show directory selection menu
    local selected_dir
    selected_dir=$(whiptail --title "Select Directory" --menu "Choose a directory to remove files from:" 20 150 12 "${menu_options[@]}" 3>&1 1>&2 2>&3) </dev/tty >/dev/tty
    
    # Exit if user cancelled
    if [[ -z "$selected_dir" ]]; then
        return 1
    fi

    # Find files to delete (those without tags)
    local files_to_delete=()
    local tagged_files=()
    while IFS= read -r line; do
        local filepath="${line%%|*}"
        local dirpath="${filepath%/*}"
        local tags="${line#*|}"
        
        if [[ "$dirpath" == "$selected_dir" ]]; then
            if [[ -z "$tags" ]]; then
                files_to_delete+=("$filepath")
            else
                tagged_files+=("$filepath")
            fi
        fi
    done < "$EBOOKS_DB"

    # Check if there are files to delete
    if [[ ${#files_to_delete[@]} -eq 0 ]]; then
        whiptail --title "Information" --msgbox "No files found to delete in '$selected_dir' without tags." 10 70 >/dev/tty
        return 1
    fi

    # Show confirmation dialog
    local confirm_msg="About to delete ${#files_to_delete[@]} files from '$selected_dir' (non-recursive).\n\nFiles with tags will not be deleted."
    if ! whiptail --title "Confirm Deletion" --yesno "$confirm_msg" 15 78; then
        return 1
    fi

    # Backup the database file
    local backup_file="${EBOOKS_DB}.backup"
    cp "$EBOOKS_DB" "$backup_file"

    # Remove entries from the database
    grep -v -E "^${selected_dir}/[^/]+\|$" "$EBOOKS_DB" > "${EBOOKS_DB}.tmp" && mv "${EBOOKS_DB}.tmp" "$EBOOKS_DB"

    # Show deleted files
    local deleted_msg="Removed files from ebooks db:\n\n$(printf '%s\n' "${files_to_delete[@]:0:10}")"
    if [[ ${#files_to_delete[@]} -gt 10 ]]; then
        deleted_msg+="\n..."
    fi
    whiptail --scrolltext --title "Files Removed" --msgbox "$deleted_msg" 20 78

    # Show tagged files that were excluded
    if [[ ${#tagged_files[@]} -gt 0 ]]; then
        local excluded_msg="The following files were not deleted because they have tag(s):\n\n$(printf '%s\n' "${tagged_files[@]:0:10}")"
        if [[ ${#tagged_files[@]} -gt 10 ]]; then
            excluded_msg+="\n..."
        fi
        excluded_msg+="\n\nPlease dissociate tag(s) from these files first."
        whiptail --scrolltext --title "Tagged Files Excluded" --msgbox "$excluded_msg" 20 78
    fi

    return 0
}

remove_files_by_filepath_recursive() {
    # Inform user of the purpose
    whiptail --title "Attention" --msgbox "This function allows user to remove all files from ebooks db under file path including files in sub-directories. \
If a file has a tag associated with it, it will not be removed. \
It does not delete the files physically on drive." 12 78 >/dev/tty

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    # Get unique directories
    local directories
    directories=$(cut -d'|' -f1 "${EBOOKS_DB}" | sed -E 's:/[^/]+$::' | sort | uniq)
    
    # Check if there are any directories
    if [[ -z "$directories" ]]; then
        whiptail --title "Error" --msgbox "No directories found in the database." 8 50 >/dev/tty
        return 1
    fi

    # Create whiptail menu options
    local menu_options=()
    while IFS= read -r dir; do
        menu_options+=("$dir" "")
    done <<< "$directories"

    # Show directory selection menu
    local selected_dir
    selected_dir=$(whiptail --title "Select Directory" --menu "Choose a root directory to remove files from:" 20 150 12 "${menu_options[@]}" 3>&1 1>&2 2>&3) </dev/tty >/dev/tty
    
    # Exit if user cancelled
    if [[ -z "$selected_dir" ]]; then
        return 1
    fi

	# Find files to delete (those without tags)
	local files_to_delete=()
	local tagged_files=()
	while IFS= read -r line; do
		local filepath="${line%%|*}"
		local dirpath="${filepath%/*}"
		local tags="${line#*|}"
		
		if [[ "$dirpath" =~ ^"${selected_dir}"(/.*)?$ ]]; then
			if [[ -z "$tags" ]]; then
				files_to_delete+=("$filepath")
			else
				tagged_files+=("$filepath")
			fi
		fi
	done < "$EBOOKS_DB"

    # Check if there are files to delete
    if [[ ${#files_to_delete[@]} -eq 0 ]]; then
        whiptail --title "Information" --msgbox "No files found to delete in '$selected_dir' without tags." 10 70 >/dev/tty
        return 1
    fi

    # Show confirmation dialog
    local confirm_msg="About to delete ${#files_to_delete[@]} files from '$selected_dir' (recursive).\n\nFiles with tags will not be deleted."
    if ! whiptail --title "Confirm Deletion" --yesno "$confirm_msg" 15 78; then
        return 1
    fi

    # Backup the database file
    local backup_file="${EBOOKS_DB}.backup"
    cp "$EBOOKS_DB" "$backup_file"

    # Remove entries from the database    
    grep -v -E "^${selected_dir}(/.*)?\|$" "$EBOOKS_DB" > "${EBOOKS_DB}.tmp" && mv "${EBOOKS_DB}.tmp" "$EBOOKS_DB"

    # Show deleted files
    local deleted_msg="Removed files from ebooks db:\n\n$(printf '%s\n' "${files_to_delete[@]:0:10}")"
    if [[ ${#files_to_delete[@]} -gt 10 ]]; then
        deleted_msg+="\n..."
    fi
    whiptail --scrolltext --title "Files Removed" --msgbox "$deleted_msg" 20 78

    # Show tagged files that were excluded
    if [[ ${#tagged_files[@]} -gt 0 ]]; then
        local excluded_msg="The following files were not deleted because they have tag(s):\n\n$(printf '%s\n' "${tagged_files[@]:0:10}")"
        if [[ ${#tagged_files[@]} -gt 10 ]]; then
            excluded_msg+="\n..."
        fi
        excluded_msg+="\n\nPlease dissociate tag(s) from these files first."
        whiptail --scrolltext --title "Tagged Files Excluded" --msgbox "$excluded_msg" 20 78
    fi

    return 0
}

# Manage eBooks menu
show_ebooks_menu() {
    local SUBCHOICE FILE_OPTION TAG_OPTION SEARCH_OPTION OPEN_OPTION MAINTENANCE_OPTION

    while true; do
        SUBCHOICE=$(whiptail --title "Manage eBooks" --cancel-button "Back" --menu "Choose an option:" 15 50 6 \
            "1" "File Management" \
            "2" "Tag Management" \
            "3" "Search & Lookup" \
            "4" "Open & Read" \
            "5" "Maintenance" 3>&1 1>&2 2>&3)

        # Exit if user presses Cancel or Esc
        [ $? -ne 0 ] && break

        case "$SUBCHOICE" in
            "1")
                # File Management submenu: Items 1, 3, and 13
                FILE_OPTION=$(whiptail --title "File Management" --cancel-button "Back" --menu "Select an option" 20 50 8 \
                    "1" "Add Files In Bulk" \
                    "2" "Register eBook" \
                    "3" "Register eBooks From Checklist" \
                    "4" "Remove Registered eBook" \
                    "5" "Remove eBooks From Checklist" \
                    "6" "Remove Files In Bulk" \
		    "7" "Remove Files by Filepath" \
		    "8" "Remove Files by Filepath Recursively" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$FILE_OPTION" in
                    "1") add_files_in_bulk ;;
                    "2") register_ebook ;;
                    "3") add_ebooks_from_checklist ;;
                    "4") remove_registered_ebook ;;
                    "5") remove_ebooks_from_checklist ;;
                    "6") remove_files_in_bulk ;;
		    "7") remove_files_by_filepath ;;
		    "8") remove_files_by_filepath_recursive ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "2")
                # Tag Management submenu: Items 4, 7, 11, and 12
                TAG_OPTION=$(whiptail --title "Tag Management" --cancel-button "Back" --menu "Select an option" 20 50 10 \
                    "1" "Register Tag" \
                    "2" "Associate Tag with eBook" \
                    "3" "Associate Tag from Checklist" \
                    "4" "Associate Tag to Bulk" \
		    "5" "Associate Tag by Filepath" \
                    "6" "Dissociate Tag from Registered eBook" \
                    "7" "Disociate Tag from Checklist" \
                    "8" "Dissociate Tag from Bulk" \
		    "9" "Dissociate Tag by Filepath" \
                    "10" "Delete Tag From Global List" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$TAG_OPTION" in
                    "1") register_tag ;;
                    "2") associate_tag ;;
                    "3") associate_tag_from_checklist ;;
                    "4") assoc_tag_to_bulk ;;                    
		    "5") assoc_tag_by_filepath ;;
                    "6") dissociate_tag_from_registered_ebook ;;
                    "7") dissociate_tag_from_checklist ;;
                    "8") dissoc_tag_to_bulk ;;
		    "9") dissoc_tag_by_filepath ;;
                    "10") delete_tag_from_global_list ;;
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
                MAINTENANCE_OPTION=$(whiptail --title "Maintenance" --cancel-button "Back" --menu "Select an option" 15 50 3 \
                    "1" "Find Remove Broken Entries" \
                    "2" "Rename and Reregister Illegal Filenames" \
                    "3" "Revert Renaming Illegal Filenames" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$MAINTENANCE_OPTION" in
                    "1") remove_broken_entries ;;
                    "2") rename_and_reregister_illegal_ebook_filenames ;;
                    "3") revert_rename_illegal_ebook_filenames ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            *)
                whiptail --msgbox "Invalid Category" 8 40
                ;;
        esac
    done
}

################################ 
# Manage Notes code starts here
################################

#MANAGE NOTES - files and formats
#================================
#
#~/notes/:
#note_title-timestamp.txt
#
#~/notes/metadata/:
#notes.db:
#note_title|note_path|tag1,tag2|ebook_path1#chapter1:5,chapter3:10-15;ebook_path2#chapter1:2
#
#notes-tags.db:
#tag1
#tag2
#...
#
#notes-ebooks.db:
#ebook_path1
#ebook_path2
#...

# Utility function for delete_note().
# Checks if selected note due to be deleted is safe to delete by comparing
# lines in PROJECTS_DB file.
# It is not safe for deletion if match is found in PROJECTS_DB.
note_safe_to_delete() {
    local note_path="$1"
    
    if [[ ! -f "$PROJECTS_DB" ]]; then
        echo "Projects database not found: $PROJECTS_DB" >&2
        return 1
    fi
    
    while IFS='|' read -r _ proj_path notes; do
        IFS=',' read -ra note_array <<< "$notes"
        for project_note in "${note_array[@]}"; do
            if [[ "$project_note" == "$note_path" ]]; then
		echo "$proj_path"
                return 1  # Note is referenced in a project - not safe to delete
            fi
        done
    done < "$PROJECTS_DB"
    
    return 0  # Note is not referenced in any project - safe to delete
}

# This script is not able to deal with file names containing: | , # : ;
# So, if that's the case then stop right there.
illegal_filename() {
  echo "$1" | grep -q '[|,#:;]' && return 1 || return 0
}

# Truncation logic for chapters.
# Output:
# ...,last_chapter:pages
truncate_chapters() {
    local chapters="$1"
    local max_len="$2"
    local prefix="...,"
    local prefix_len=${#prefix}

    # If chapters is empty, just output an empty string.
    if [ -z "$chapters" ]; then
        echo ""
        return
    fi

    # Get the last chapter by taking the substring after the final comma.
    # If no comma is present, consider the entire string as the last chapter.
    local last
    if [[ "$chapters" == *","* ]]; then
        last="${chapters##*,}"
    else
        # If only one chapter is encoded then empty prefix.
        prefix=""
        last="$chapters"
    fi

    # Compose the result with the fixed prefix.
    local result="${prefix}${last}"

    # If the full result is within the allowed length, output it.
    if [ ${#result} -le "$max_len" ]; then
        echo "$result"
        return
    fi

    # Otherwise, calculate the available space for the last chapter.
    local available=$(( max_len - prefix_len ))
    # If the limit is too small even for the prefix, just return a cut-off.
    if [ "$available" -le 0 ]; then
        echo "${result:0:max_len}"
        return
    fi

    # Truncate the last chapter from the left (keeping its end)
    # so that the overall length does not exceed max_len.
    if [ ${#last} -gt "$available" ]; then
        last="${last: -available}"
    fi

    echo "${prefix}${last}"
}

# Need this to truncate menu inside manage ebooks().
generate_trunc_manage_ebooks_menu() {
    # Initialize the result array
    TRUNC_MANAGE_EBOOKS_MENU=()
    
    # Get the input array from arguments
    local input_array=("$@")

    # If input_array is empty return
    [[ ${#input_array[@]} -eq 0 ]] && return 1
    
    local idx=1
    # Process pairs of elements
    for ((i = 0; i < ${#input_array[@]}; i += 2)); do
        local full_path="${input_array[i]}"
        local chapters="${input_array[i+1]}"

        # DEBUG
        #echo "chapters:" >&2
        #echo "$chapters" >&2
        
        # Split path into directory and filename
        local dir_part=$(dirname "$full_path")
        local file_part=$(basename "$full_path")
        
        # Truncate components
        local trunc_dir=$(truncate_dirname "$dir_part")
        local trunc_file=$(truncate_filename "$file_part" 50)
        local truncated_path="${trunc_dir}/${trunc_file}"
        
        # Truncate chapters
        local trunc_chapters=$(truncate_chapters "$chapters" 20)
        
        # DEBUG
        #echo "trunc_chapters:" >&2
        #echo "$trunc_chapters" >&2

        # Add to result array
        TRUNC_MANAGE_EBOOKS_MENU+=("${idx}:${truncated_path}" "$trunc_chapters")
        (( idx++ ))
    done
}

# Need this function to create TRUNC_FILTERED_EBOOKS array
generate_trunc_manage_ebooks() {
    # Initialize the TRUNC_FILTERED_EBOOKS array
    TRUNC_FILTERED_EBOOKS=()

    # If FILTERED_EBOOKS is empty return
    [[ ${#FILTERED_EBOOKS[@]} -eq 0 ]] && return 1

    local idx=1
    # Process each full path from FILTERED_EBOOKS (assuming pairs: fullpath "" ...)
    for ((i=0; i < ${#FILTERED_EBOOKS[@]}; i+=2)); do
        fullpath="${FILTERED_EBOOKS[i]}"

        # Extract the directory and filename parts
        dir=$(dirname "$fullpath")
        file=$(basename "$fullpath")

        # Apply truncation functions to the directory and filename respectively
        truncated_dir=$(truncate_dirname "$dir")
        truncated_file=$(truncate_filename "$file")

        # Reassemble the truncated path
        truncated_path="${truncated_dir}/${truncated_file}"

        # Append the truncated path and an empty string to maintain pair structure
        TRUNC_FILTERED_EBOOKS+=( "${idx}:${truncated_path}" "" )
        (( idx++ ))
    done
}

generate_trunc_manage_ebooks_remove_ebook() {
    # Initialize the TRUNC_FILTERED_EBOOKS_REMOVE array
    TRUNC_FILTERED_EBOOKS_REMOVE=()

    local remove_options=("$@")   # OMG, forgot to enclose in ()!!
    local fullpath dir file truncated_dir truncated_file truncated_path

    # If remove_options is empty return
    [[ ${#remove_options[@]} -eq 0 ]] && return 1

    local idx=1
    # Process each full path from remove_options (assuming pairs: fullpath "" ...)
    for ((i=0; i < ${#remove_options[@]}; i+=2)); do
        fullpath="${remove_options[i]}"

        # DEBUG
        #echo "fullpath:" >&2
        #echo "$fullpath" >&2

        # Extract the directory and filename parts
        dir=$(dirname "$fullpath")
        file=$(basename "$fullpath")

        # Apply truncation functions to the directory and filename respectively
        truncated_dir=$(truncate_dirname "$dir")
        truncated_file=$(truncate_filename "$file" 50)

        # DEBUG
        #echo "dir:" >&2
        #echo "$dir" >&2
        #echo "trunc dir:" >&2
        #echo "$truncated_dir" >&2

        # Reassemble the truncated path
        truncated_path="${truncated_dir}/${truncated_file}"

        # Append the truncated path and an empty string to maintain pair structure
        TRUNC_FILTERED_EBOOKS_REMOVE+=( "${idx}:${truncated_path}" "" )
        (( idx++ ))
    done
}

# Global array to store filtered entries.
declare -a FILTERED_EBOOKS

CURRENT_PAGE=0   # persists page state across paginate_n() calls

paginate_n() {
    # Clear any previous selection
    SELECTED_ITEM=""

    local chunk_size=200

    # If new items are passed in, update TRUNC and reset CURRENT_PAGE.
    if [ "$#" -gt 0 ]; then
        FILTERED_EBOOKS=("$@")
        CURRENT_PAGE=0
    fi

    [[ ${#FILTERED_EBOOKS[@]} -eq 0 ]] && return 1

    local total_pages=$(( ( ${#FILTERED_EBOOKS[@]} + chunk_size - 1 ) / chunk_size ))
    # Ensure CURRENT_PAGE is within valid bounds
    if (( CURRENT_PAGE >= total_pages )); then
        CURRENT_PAGE=$(( total_pages - 1 ))
    fi

    # populate TRUNC_FILTERED_EBOOKS from FILTERED_EBOOKS
    generate_trunc_manage_ebooks

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        # Extract the current chunk from the global TRUNC
        #local current_chunk=("${FILTERED_EBOOKS[@]:$start:$chunk_size}")
        local current_chunk=("${TRUNC_FILTERED_EBOOKS[@]:$start:$chunk_size}")
        local menu_options=()

        # Add navigation options if needed
        if (( CURRENT_PAGE > 0 )); then
            menu_options+=("previous page" "")
        fi
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("next page" "")
        fi

        # Append the current page items
        menu_options+=("${current_chunk[@]}")

        choice=$(whiptail --title "Paged Menu" --cancel-button "Back" \
            --menu "Choose an item (Page $((CURRENT_PAGE + 1))/$total_pages)" \
            20 170 10 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

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
                local n="$(echo "$choice" | cut -d':' -f1)"
                local m=$((2 * n - 1))

                SELECTED_ITEM="${FILTERED_EBOOKS[$((m - 1))]}"
                ! illegal_filename "$SELECTED_ITEM" && SELECTED_ITEM="" && return 2
                return 0
                ;;
        esac
    done

    return 1
}

# Modified: Filter by both tag and file name.
filter_by_filename() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

  [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
    whiptail --title "Ebook Database" --msgbox "Ebooks database not found or empty. Register at least one ebook." 10 60 >/dev/tty
    return 1
  }
 
# When filtering by file name, we don't strictly need a tag associated with. 
#  [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
#    whiptail --title "Ebook Database" --msgbox "Tags database not found or empty. Register at least one ebook tag ." 10 60 >/dev/tty
#    return 1
#  }

  # Read available tags from TAGS_DB
  local tags=()
#   if [ -f "$TAGS_DB" ]; then
#     while IFS= read -r tag; do
#       tags+=("$tag")
#     done < "$TAGS_DB"
#   fi
  if [[ -f "$TAGS_DB" ]]; then
    mapfile -t tags < <(sort "$TAGS_DB")
  fi

  # Prepare tag options for whiptail menu, starting with "ANY TAG"
  local tag_options=("ANY TAG" "Any tag (no filter)")
  for tag in "${tags[@]}"; do
    tag_options+=("$tag" "")
  done

#   # Present tag selection menu
#   local selected_tag
#   selected_tag=$(whiptail --title "Select Tag to Filter" --menu "Choose a tag to filter by (or select ANY TAG):" 20 150 10 "${tag_options[@]}" 3>&1 1>&2 2>&3 </dev/tty)
#   if [ $? -ne 0 ]; then
#     return 1
#   fi

  # FIX: PAGINATE TAG SELECTION.
  local selected_tag
  selected_tag="$(paginate_tags_menu "Select eBook Tag to Filter" "${tag_options[@]}")" || return 1

  # Prompt for search term
  local search_term
  search_term=$(whiptail --inputbox "Enter search term for ebook file name (globbing; empty is wildcard):" 8 60 --title "Filter Ebooks" 3>&1 1>&2 2>&3 </dev/tty)
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  : ${search_term:=*}

  # Clear the global array
  FILTERED_EBOOKS=()

  # Check EBOOKS_DB existence
  if [ ! -f "$EBOOKS_DB" ]; then
    echo "EBOOKS_DB file not found: $EBOOKS_DB" >&2
    return 1
  fi

  in_operation_msg

  # Process each line in EBOOKS_DB and populate $FILTERED_EBOOKS
  # where the items are in pairs: ($filepath, "")
mapfile -t FILTERED_EBOOKS < <(
  awk -F'\\|' \
      -v tag="$selected_tag" \
      -v glob="$search_term" '
    # Convert shell glob → regex (case-insensitive)
    function glob_to_regex(g, r, i, c) {
      r = "^"
      for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*")        r = r ".*"
        else if (c == "?")   r = r "."
        else if (c == ".")   r = r "\\."
        else if (c == "[")   r = r "["
        else if (c == "]")   r = r "]"
        else if (c == "\\")  r = r "\\\\"
        else                 r = r c
      }
      return r "$"
    }

    BEGIN {
      IGNORECASE = 1   # case-insensitive filename and glob match
      if (length(glob) > 0)
        regex = glob_to_regex(glob)
      else
        regex = ""     # no filename filter
    }

    {
      filepath = $1
      tags     = $2

      # --- Tag filter ---
      if (tag != "ANY TAG") {
        tags2 = "," tags ","
        pat   = "," tag ","
        if (index(tags2, pat) == 0) next
      }

      # --- Filename filter ---
      if (regex != "") {
        n = split(filepath, arr, "/")
        filename = arr[n]

        if (filename !~ regex)
          next
      }

      print filepath
      print ""
    }
  ' "$EBOOKS_DB"
)

  # Show result count
  whiptail --msgbox "Found $(( ${#FILTERED_EBOOKS[@]} / 2 )) matching entries." 8 60 --title "Filter Results" >/dev/tty
}

# Global variables used by add_note and its helpers.
note_title=""
note_path=""
current_tags=()
ebook_entries=()

# FIX: implemented pagination.
manage_tags() {
    local current_page=0
    local tags_per_page=20  # Showing 8 tags per page to leave space for navigation items

    while true; do
        # Read existing tags
        local -a tags=()
        if [ -f "$NOTES_TAGS_DB" ]; then
            mapfile -t tags < "$NOTES_TAGS_DB"
        fi

        # Calculate total pages
        local total_pages=$(( (${#tags[@]} + tags_per_page - 1) / tags_per_page ))
        
        # Get tags for current page
        local start_index=$((current_page * tags_per_page))
        local end_index=$((start_index + tags_per_page - 1))
        local -a page_tags=("${tags[@]:$start_index:$tags_per_page}")

        # Prepare menu options
        local menu_options=()
        
        # Add tags for current page
        for tag in "${page_tags[@]}"; do
	    # LOGIC ERROR: matches subword too.
            #if [[ " ${current_tags[@]} " =~ " ${tag} " ]]; then
            #    menu_options+=("$tag" "[X]")

	    local sep=$'\x1F'  # ASCII Unit Separator, unlikely to appear in real tags
	    local joined="$sep$(IFS="$sep"; echo "${current_tags[*]}")$sep"
	    if [[ "$joined" == *"${sep}${tag}${sep}"* ]]; then
		menu_options+=("$tag" "[X]")
            else
                menu_options+=("$tag" "[ ]")
            fi
        done

        # Add navigation items if needed
        if [ $total_pages -gt 1 ]; then
            if [ $current_page -gt 0 ]; then
                menu_options+=("<< Previous Page" "")
            fi
            
            #menu_options+=("Add new tag" "")
            
            if [ $current_page -lt $((total_pages - 1)) ]; then
                menu_options+=(">> Next Page" "")
            fi

	    # changed order.
	    menu_options+=("Add new tag" "")
        else
            menu_options+=("Add new tag" "")
        fi

        # truncate $current_tags first
        local current_tags_tr tr_menu_str
        current_tags_tr="$(IFS=','; echo "${current_tags[*]}")"
        (( ${#current_tags[@]} > 1 )) && tr_menu_str="${current_tags_tr:0:37}..." || tr_menu_str="${current_tags_tr[*]:0:40}"

        local selection
        selection=$(whiptail --title "Manage Tags (Page $((current_page + 1))/$total_pages)" \
            --cancel-button "Back" --menu "Current tags: $tr_menu_str" 20 60 10 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        [ $? -eq 0 ] || return

        case "$selection" in
            "Add new tag")
                local new_tag
                new_tag=$(whiptail --inputbox "Enter new tag:" 8 40 3>&1 1>&2 2>&3 </dev/tty)
                [ $? -eq 0 ] || continue
                # ANY TAG is banned word
                [[ "$new_tag" == "ANY TAG" ]] && whiptail --title "Invalid Tag" --msgbox "'ANY TAG' is not allowed as a tag name." 8 40 && continue

                # FIX: DELETE BANNED CHARS - MORE EFFICIENT.
                new_tag=${new_tag//[|,#:;]/}
                #new_tag=${new_tag//[|,#;]/}
                #new_tag=$(echo "$new_tag" | tr -d '|,')
                # END FIX.

                if [ -n "$new_tag" ]; then
#                    # Add to global tags list
#                    echo "$new_tag" >> "$NOTES_TAGS_DB"
#                    current_tags+=("$new_tag")
#                    # Reset to first page after adding a new tag
#                    current_page=0

    		    # FIX: CHECK FOR DUPLICATE BEFORE ADDING TAG.
                    # Check if tag already exists
                    if grep -qFx "$new_tag" "$NOTES_TAGS_DB"; then
                        whiptail --msgbox "Tag '${new_tag}' already exists!" 8 40
                    else
                        # Add to global tags list
                        echo "$new_tag" >> "$NOTES_TAGS_DB"
                        current_tags+=("$new_tag")
                        # Reset to first page after adding a new tag
                        current_page=0
                    fi
                fi
                ;;
            "<< Previous Page")
                ((current_page--))
                continue
                ;;
            ">> Next Page")
                ((current_page++))
                continue
                ;;
            *)
                # Toggle tag selection
		# LOGIC ERROR: matches subword too.
                #if [[ " ${current_tags[@]} " =~ " ${selection} " ]]; then
		
		local sep=$'\x1F'  # ASCII Unit Separator, unlikely to appear in real tags
		local joined="$sep$(IFS="$sep"; echo "${current_tags[*]}")$sep"
		if [[ "$joined" == *"${sep}${selection}${sep}"* ]]; then
                    if whiptail --yesno "Remove tag '${selection}'?" 8 40 </dev/tty >/dev/tty; then
                        local new_tags=()
                        for tag in "${current_tags[@]}"; do
                            [[ "$tag" != "$selection" ]] && new_tags+=("$tag")
                        done
                        current_tags=("${new_tags[@]}")
                    fi
                else
                    if whiptail --yesno "Add tag '${selection}'?" 8 40 </dev/tty >/dev/tty; then
                        current_tags+=("$selection")
                    fi
                fi
                ;;
        esac
    done
}

# DEPRECATED.
manage_tags_old() {
    while true; do
        # Read existing tags
        local -a tags=()
        if [ -f "$NOTES_TAGS_DB" ]; then
            mapfile -t tags < "$NOTES_TAGS_DB"
        fi

        # Prepare menu options
        local menu_options=()
        for tag in "${tags[@]}"; do
            if [[ " ${current_tags[@]} " =~ " ${tag} " ]]; then
                menu_options+=("$tag" "[X]")
            else
                menu_options+=("$tag" "[ ]")
            fi
        done
        menu_options+=("Add new tag" "")
        #menu_options+=("Back" "Return to previous menu")

        local selection
        selection=$(whiptail --title "Manage Tags" --cancel-button "Back" --menu "Current tags: ${current_tags[*]}" 20 60 10 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        [ $? -eq 0 ] || return

        case "$selection" in
            "Add new tag")
                local new_tag
                new_tag=$(whiptail --inputbox "Enter new tag:" 8 40 3>&1 1>&2 2>&3 </dev/tty)
                [ $? -eq 0 ] || continue
                new_tag=$(echo "$new_tag" | tr -d '|,')
                if [ -n "$new_tag" ]; then
                    # Add to global tags list
                    echo "$new_tag" >> "$NOTES_TAGS_DB"
                    current_tags+=("$new_tag")
                fi
                ;;
            #"Back")
            #    return
            #    ;;
            *)
                # Toggle tag selection
                if [[ " ${current_tags[@]} " =~ " ${selection} " ]]; then
                    if whiptail --yesno "Remove tag '${selection}'?" 8 40 </dev/tty >/dev/tty; then
                        local new_tags=()
                        for tag in "${current_tags[@]}"; do
                            [[ "$tag" != "$selection" ]] && new_tags+=("$tag")
                        done
                        current_tags=("${new_tags[@]}")
                    fi
                else
                    if whiptail --yesno "Add tag '${selection}'?" 8 40 </dev/tty >/dev/tty; then
                        current_tags+=("$selection")
                    fi
                fi
                ;;
        esac
    done
}

# Verify pages string (for an ebook).
verify_pages_str() {
    local pages="$1"
    
    # Check for single page (e.g. "5")
    if [[ "$pages" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    
    # Check for page range (e.g. "5-10")
    if [[ "$pages" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        
        # Verify that the ending page is greater than the starting page
        if (( end > start )); then
            return 0
        fi
    fi

    # Return non-zero for invalid string
    return 1
}

# UI to construct CHAPTER_PAGES string.
add_chapters() {
    # Reset global
    CHAPTER_PAGES=""
    declare -a chapters=()

    # If need to prefill chapters.
    local current_chapters="$1"

    # Prefill chapters array if current_chapters is given as $1.
    if [[ -n "$current_chapters" ]]; then
        # Split current_chapters by comma and populate the chapters array.
        IFS=',' read -ra chapters <<< "$current_chapters"
    fi   

    local chapter_name chapter_pages new_entry
    local choice index chapter_entry old_name old_pages new_pages
    local num_chapters

    while true; do
        num_chapters=${#chapters[@]}
        #add_choice=$((num_chapters + 1))
        #save_choice=$((num_chapters + 2))
        
        # Build menu with chapters first, then static options
        menu_options=()
        for ((index=0; index<num_chapters; index++)); do
            menu_options+=("$((index+1))" "${chapters[index]}")
        done
        menu_options+=("Add chapter" "")
        menu_options+=("Save and return" "")

	# If added lot of chapters menu gets broken so increase dimensions!
        choice=$(whiptail --title "Chapter Management" --cancel-button "Back" --menu "Choose an option:" \
            22 150 15 "${menu_options[@]}" 3>&1 1>&2 2>&3)
        
        [[ $? -ne 0 ]] && choice="Save and return"  # Handle ESC/Cancel as Save
        
        if [[ "$choice" == "Add chapter" ]]; then
            # Add new chapter
            while true; do
                chapter_name=$(whiptail --inputbox "Enter chapter name:" 8 40 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && break

		# FIX
		# Check for illegal chapter name
		if [[ "$chapter_name" =~ [\;\|#,:] ]]; then
			whiptail --title "Attention" --msgbox "Chapter name cannot contain illegal characters (|#,:;)." 8 60
    			continue
		fi
		# END FIX.
                
                chapter_pages=$(whiptail --inputbox "Enter pages for '$chapter_name' (eg. 1 or 1-10):" \
                    8 40 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue

                # Check for syntax page1 or page1-page2 here.
                # Check for:
                # If pages a-b, b must be > a.
                # ^[0-9]+-[0-9]+$ or ^[0-9]+$.
                if ! verify_pages_str "$chapter_pages"; then
                    whiptail --title "Error" --msgbox "Invalid pages syntax." 8 40
                    continue
                fi
                
                # Remember that we can have same chapter name but different pages.
                new_entry="$chapter_name:$chapter_pages"
                if [[ " ${chapters[*]} " =~ " $new_entry " ]]; then
                    whiptail --msgbox "Duplicate entry: $new_entry" 8 40
                else
                    chapters+=("$new_entry")
                    break
                fi
            done

        elif [[ "$choice" == "Save and return" ]]; then
            # Save and exit
            CHAPTER_PAGES=$(IFS=','; echo "${chapters[*]}")
            return 0

        elif [[ $choice -le $num_chapters ]]; then
            # Chapter selected - show edit/delete menu
            index=$((choice - 1))
            chapter_entry="${chapters[index]}"
            old_name="${chapter_entry%%:*}"
            old_pages="${chapter_entry#*:}"
            
            action=$(whiptail --menu "Chapter: $chapter_entry" 15 50 5 \
                "Edit pages" "" \
                "Delete chapter" "" \
                3>&1 1>&2 2>&3)
            
            if [[ $? -eq 0 ]]; then
                case $action in
                    "Edit pages")  # Edit pages
                        while true; do
                            new_pages=$(whiptail --inputbox "New pages for '$old_name' (eg. 1 or 1-10):" \
                                8 40 "$old_pages" 3>&1 1>&2 2>&3)
                            [[ $? -ne 0 ]] && break

                            # Check for pages syntax here.
                            if ! verify_pages_str "$new_pages"; then
                                whiptail --title "Error" --msgbox "Invalid pages syntax." 8 40
                                continue
                            fi
                            
                            new_entry="$old_name:$new_pages"
                            if [[ " ${chapters[*]} " =~ " $new_entry " ]]; then
                                whiptail --msgbox "No change." 8 40
                                break
                            else
                                chapters[index]="$new_entry"
                                break
                            fi
                        done
                        ;;
                    "Delete chapter")  # Delete chapter
                        unset 'chapters[index]'
                        chapters=("${chapters[@]}")  # Re-index array
                        ;;
                esac
            fi
        fi
    done
}

paginate_n_checklist() {
    # Initialize global array
    SELECTED_ITEMS=()
    # Temporary associative array to track indices (requires Bash 4+)
    declare -A SELECTED_INDICES 

    local chunk_size=50

    if [ "$#" -gt 0 ]; then
        FILTERED_EBOOKS=("$@")
        CURRENT_PAGE=0
    fi

    [[ ${#FILTERED_EBOOKS[@]} -eq 0 ]] && return 1

    local total_pages=$(( ( ${#FILTERED_EBOOKS[@]} + chunk_size - 1 ) / chunk_size ))
    
    # Ensure CURRENT_PAGE is within valid bounds
    if (( CURRENT_PAGE >= total_pages )); then
        CURRENT_PAGE=$(( total_pages - 1 ))
    elif (( CURRENT_PAGE < 0 )); then
        CURRENT_PAGE=0
    fi

    generate_trunc_manage_ebooks

    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        local current_chunk=("${TRUNC_FILTERED_EBOOKS[@]:$start:$chunk_size}")
        local menu_options=()

        # 1. Add Navigation and Action items
        # Format: Tag, Item, Status
        
        # --- Conditional Navigation Items ---
        if (( CURRENT_PAGE > 0 )); then
            menu_options+=("PREV" "" "OFF")
        fi        
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("NEXT" "" "OFF")
        fi

        # ADD item
        menu_options+=("ADD"  "" "OFF")

        # 2. Append the current page items with their current selection state
        for (( i=0; i<${#current_chunk[@]}; i+=2 )); do
            local tag="${current_chunk[$i]}"
            local desc="${current_chunk[$i+1]}"
            
            # Determine if this item is already selected
            local status="OFF"
            [[ -n "${SELECTED_INDICES[$tag]}" ]] && status="ON"
            
            menu_options+=("$tag" "$desc" "$status")
        done

        # 3. Display Checklist
        local choices
        choices=$(whiptail --title "Ebook asset files to add" \
            --separate-output \
            --checklist "Select items (Page $((CURRENT_PAGE + 1))/$total_pages)" \
            25 170 15 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3)

        # Exit if user cancels (Back/ESC)
        if [ $? -ne 0 ]; then
            return 1
        fi

        # 4. Process Selections
        # First, clear current page selections from the tracker so we can re-sync
        for (( i=0; i<${#current_chunk[@]}; i+=2 )); do
            unset SELECTED_INDICES["${current_chunk[$i]}"]
        done

        local nav_next=false
        local nav_prev=false
        local action_add=false

        # Read choices line by line
        while read -r line; do
            case "$line" in
                "PREV") nav_prev=true ;;
                "NEXT") nav_next=true ;;
                "ADD")  action_add=true ;;
                *)      
                    SELECTED_INDICES["$line"]=1 # update selections from every page.
                    ;;
            esac
        done <<< "$choices" # from every page

        # 5. Validation Logic
        if $action_add && ( $nav_next || $nav_prev ); then
            whiptail --msgbox "You cannot select navigation items and 'Add' at the same time." 8 60
            continue
        fi

        if $nav_next && $nav_prev; then
            whiptail --msgbox "You cannot select both Next and Previous page simultaneously." 8 60
            continue
        fi

        local line_count
        line_count=$(grep -c '^' <<< "$choices")

        if (( line_count < 2 )) && $action_add; then
            whiptail --msgbox "Select at least one asset file before adding." 8 60
            continue
        fi

        # 6. Navigation / Finalization Execution
        if $action_add; then
            # Convert indices back to original paths in FILTERED_EBOOKS
            for idx_tag in "${!SELECTED_INDICES[@]}"; do
                # Extract numeric index 'n' from 'n:path'
                local n="$(echo "$idx_tag" | cut -d':' -f1)"
                local m=$((2 * n - 1))
                local item="${FILTERED_EBOOKS[$((m - 1))]}"
                
                # Check for illegal ebook name
                if illegal_filename "$item"; then
                    SELECTED_ITEMS+=("$item")
                else
                    return 2
                fi
            done
            return 0
        elif $nav_prev; then
            if (( CURRENT_PAGE > 0 )); then
                (( CURRENT_PAGE-- ))
            else
                #whiptail --msgbox "You are already on the first page." 8 40
                :
            fi
        elif $nav_next; then
            if (( CURRENT_PAGE < total_pages - 1 )); then
                (( CURRENT_PAGE++ ))
            else
                #whiptail --msgbox "You are already on the last page." 8 40
                :
            fi
        fi
    done
}

# DEBUG
#add_chapters
#echo CHAPTER_PAGES: >&2
#echo "$CHAPTER_PAGES" >&2
#exit

manage_ebooks() {
    # Load existing ebooks into ebook_entries if desired (remove if starting fresh)
    # If you want to edit existing entries, uncomment the following lines:
    # if [ -f "$NOTES_EBOOKS_DB" ]; then
    #     while IFS= read -r line; do
    #         [[ -n "$line" ]] && ebook_entries+=("$line")
    #     done < "$NOTES_EBOOKS_DB"
    # fi

    while true; do
        # Prepare menu options from ebook_entries
        local menu_options=()
        for entry in "${ebook_entries[@]}"; do
            ebook=$(cut -d# -f1 <<< "$entry")
            chapters=$(cut -d# -f2- <<< "$entry")
            menu_options+=("$ebook" "$chapters")
        done

        # Generate TRUNC_MANAGE_EBOOKS_MENU
        generate_trunc_manage_ebooks_menu "${menu_options[@]}"

        TRUNC_MANAGE_EBOOKS_MENU+=("Add new ebook" "")
        [ ${#ebook_entries[@]} -gt 0 ] && TRUNC_MANAGE_EBOOKS_MENU+=("Remove ebook" "")
        TRUNC_MANAGE_EBOOKS_MENU+=("Back" "Return to previous menu")

        local selection_trunc
        selection_trunc=$(whiptail --title "Manage Ebooks" --cancel-button "Back" --menu "Manage ebook associations" 20 170 10 \
            "${TRUNC_MANAGE_EBOOKS_MENU[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        [ $? -eq 0 ] || break

        # Get selection from TRUNC_MANAGE_EBOOKS_MENU
        local n m selection

        # Account for when selection_trunc is "Add new ebook" or "Remove ebook" or "Back"
        if [[ "$selection_trunc" != "Add new ebook" && "$selection_trunc" != "Remove ebook" && "$selection_trunc" != "Back" ]]; then
            n="$(echo "$selection_trunc" | cut -d':' -f1)"
            m=$((2 * n - 1))
            selection="${menu_options[$((m - 1))]}"
        else
            selection="$selection_trunc"
        fi

        case "$selection" in
            "Add new ebook")
                local new_ebooks=()
                CURRENT_PAGE=0
                SELECTED_ITEMS=""

                ! filter_by_filename && continue

                paginate_n_checklist

                # Illegal file name
                [[ $? -eq 2 ]] && {
                    whiptail --title "Error" --msgbox "Some file names are illegal.  Contains | , # : ;. Rename file and try again." 10 60
                    return 1
                }

                new_ebooks=("${SELECTED_ITEMS[@]}")

                if (( ${#new_ebooks[@]} == 0 )); then
                    whiptail --msgbox "No ebook selected. Operation cancelled." 8 60 >/dev/tty
                    continue
                fi

                # Iterate through each newly selected ebook
                for new_ebook in "${new_ebooks[@]}"; do
                    local exists=0
                    
                    # Check if this specific ebook already exists in ebook_entries
                    for entry in "${ebook_entries[@]}"; do
                        # Matches the ebook name followed by the # delimiter
                        if [[ "$entry" == "${new_ebook}#"* ]]; then
                            exists=1
                            break
                        fi
                    done

                    if [[ $exists -eq 1 ]]; then
                        # Optional: Notify user, or simply skip to keep the UI clean
                        :
                    else
                        # If unique, add it to the ebook_entries array with the # suffix
                        local chapters=""
                        ebook_entries+=("${new_ebook}#${chapters}")
                    fi
                done
                (( $exists )) && whiptail --msgbox "Some ebook files were skipped because they are already registered." 8 60 >/dev/tty
                ;;

            "Remove ebook")
                # DEBUG
                #echo Remove ebook: >&2
                #echo ebook_entries: >&2
                #declare -p ebook_entries >&2

                local remove_options=()
                for entry in "${ebook_entries[@]}"; do
                    remove_options+=("$(cut -d# -f1 <<< "$entry")" "")
                done

                # DEBUG
                #echo Remove ebook: >&2
                #echo remove_options: >&2
                #declare -p remove_options >&2

                # Truncate remove_options
                generate_trunc_manage_ebooks_remove_ebook "${remove_options[@]}"

                local to_remove to_remove_tr
                to_remove_tr=$(whiptail --title "Remove Ebook" --menu "Select ebook to remove:" \
                    20 170 10 "${TRUNC_FILTERED_EBOOKS_REMOVE[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
                [ $? -eq 0 ] || continue

                local n m
                n="$(echo "$to_remove_tr" | cut -d':' -f1)"
                m=$((2 * n - 1))
                to_remove="${remove_options[$((m - 1))]}"

                local new_entries=()
                for entry in "${ebook_entries[@]}"; do
                    [[ "$entry" != "${to_remove}#"* ]] && new_entries+=("$entry")
                done
                ebook_entries=("${new_entries[@]}")
                ;;

            "Back")
                return
                ;;

            *)
                # Edit existing entry
                local current_chapters=""
                for idx in "${!ebook_entries[@]}"; do
                    if [[ "${ebook_entries[idx]}" == "${selection}#"* ]]; then
                        current_chapters=$(cut -d# -f2- <<< "${ebook_entries[idx]}")
                        break
                    fi
                done

                #local new_chapters
                #new_chapters=$(whiptail --inputbox "Edit chapter:page pairs for ${selection}:" 12 60 \
                #    "$current_chapters" 3>&1 1>&2 2>&3 </dev/tty)
                #[ $? -eq 0 ] || continue

                # Get CHAPTER_PAGES
                # Prefilled
                add_chapters "$current_chapters"
                #if [[ -z "$CHAPTER_PAGES" ]]; then
                #    whiptail --title "Error" --msgbox "No chapter pages specified." 8 40
                #    continue
                #fi
                local new_chapters="$CHAPTER_PAGES"

                # Update the entry in ebook_entries
                for idx in "${!ebook_entries[@]}"; do
                    if [[ "${ebook_entries[idx]}" == "${selection}#"* ]]; then
                        ebook_entries[idx]="${selection}#${new_chapters}"
                        break
                    fi
                done
                ;;
        esac
    done
}

save_note() {
    # DEBUG
    #echo note title: >&2
    #echo "$note_title" >&2

    # Check that note_title and note_path are set; if not, do not save
    if [[ -z "$note_title" ]]; then
        whiptail --title "Error" --msgbox "Note title can't be empty!" 8 50 >/dev/tty
        return 1
    fi

    local timestamp
    timestamp=$(date "+%d%m%Y-%H%M%S") # Change format to day-month-year-hour-second.
    local sanitized_title
    sanitized_title=$(tr -cd '[:alnum:]-_ ' <<< "$note_title" | tr ' ' '_')
    note_path="${NOTES_PATH}/${sanitized_title}-${timestamp}.txt"
    touch "$note_path" || return 1

    # Prepare metadata
    local tags_str
    tags_str=$(IFS=','; echo "${current_tags[*]}")
    local ebooks_str
    ebooks_str=$(IFS=';'; echo "${ebook_entries[*]}")

    # Copy over current_tags and ebooks_entries to files
    for tg in "${current_tags[@]}"; do
        echo "$tg" >> "$NOTES_TAGS_DB"
    done

    for eb in "${ebook_entries[@]}"; do
        echo "${eb%#*}" >> "$NOTES_EBOOKS_DB"
    done

    # Update databases
    echo "${note_title}|${note_path}|${tags_str}|${ebooks_str}" >> "$NOTES_DB"
    sort -u "$NOTES_TAGS_DB" -o "$NOTES_TAGS_DB"
    sort -u "$NOTES_EBOOKS_DB" -o "$NOTES_EBOOKS_DB"

    whiptail --msgbox "Note created successfully:\n${note_path}" 10 60 >/dev/tty
}

add_note() {
    # Reinitialize globals for a new note.
    note_title=""
    note_path=""
    current_tags=()
    ebook_entries=()
    local choice

    # Add note with same tag functionality requires this.
    if [[ -n "$1" ]]; then
        current_tags+=("$1")
    fi

    # Main loop
    while true; do
        # Truncate Note Title.
        local note_title_tr tr_max
        tr_max=25

        if [ -n "$note_title" ]; then
            if [ ${#note_title} -gt $(($tr_max + 3)) ]; then
                note_title_tr="${note_title:0:$tr_max}..."
            else
                note_title_tr="$note_title"
            fi
        fi

        local path_status="(will be generated)"
        [ -n "$note_title" ] && {
            local dirname_tr filename_tr

            dirname_tr="$(truncate_dirname "$NOTES_PATH")"
            filename_tr="$note_title_tr"

            #path_status="${NOTES_PATH}/${note_title}-*.txt"
            path_status="${dirname_tr}/${filename_tr}-*.txt"
        }

        local tag_status="none"
        [ ${#current_tags[@]} -gt 0 ] && tag_status="${#current_tags[@]} tags"

        local ebook_status="none"
        [ ${#ebook_entries[@]} -gt 0 ] && ebook_status="${#ebook_entries[@]} ebooks"

        choice=$(whiptail --title "Create New Note" --menu "Configure note properties" 20 100 8 \
            "Note Title"    "Current: ${note_title_tr:-<not set>}" \
            "Note Path"     "Status: ${path_status}" \
            "Tags"          "Status: ${tag_status}" \
            "Ebooks"        "Status: ${ebook_status}" \
            "Save and Edit" "Save note and open in editor" \
            "Save and Return" "Save note and exit" 3>&1 1>&2 2>&3)
        [ $? -eq 0 ] || break

        case "$choice" in
            "Note Title")
		local old_note_title		# FIX: CHECK FOR ILLEGAL CHARS.
		old_note_title="$note_title"

                note_title=$(whiptail --inputbox "Enter note title:" 8 40 "$note_title" 3>&1 1>&2 2>&3)
		# FIX: CHECK FOR ILLEGAL CHARS.
                if [[ "$note_title" =~ [\|#] ]]; then
			note_title="$old_note_title"	# Revert
                        whiptail --title "Attention" --msgbox "Note title cannot contain illegal characters (|#)." 8 60
                        continue
                fi
		# END FIX.

                [ -z "$note_title" ] && note_title_tr=""
                ;;
            "Tags")
                manage_tags
                ;;
            "Ebooks")
                manage_ebooks
                ;;
            "Save and Edit")
                save_note || return 1
                #nano "$note_path"
		"$DEFAULT_EDITOR" "$note_path"
                break
                ;;
            "Save and Return")
                save_note || return 1
                break
                ;;
        esac
    done
}

# Helper function to load existing note data
load_note_data() {
    # note_path is global.
    #note_path="$1"

    # Reset globals
    note_title=""
    current_tags=()
    ebook_entries=()

    # Find the line in NOTES_DB
    local line
    line=$(grep -F "|${note_path}|" "$NOTES_DB")
    if [ -z "$line" ]; then
        echo "Note not found in database: $note_path" >&2
        return 1
    fi

    # Split into fields
    IFS='|' read -r note_title _note_path tags_str ebooks_str <<< "$line"

    # Ensure note_path is correct
    [[ "$note_path" != "$_note_path" ]] && return 1

    # Split tags and ebooks
    IFS=',' read -ra current_tags <<< "$tags_str"
    IFS=';' read -ra ebook_entries <<< "$ebooks_str"

    return 0
}

# Helper function to update note in database
update_note_in_db() {
    # Compose new line
    local tags_str=$(IFS=','; echo "${current_tags[*]}")
    local ebooks_str=$(IFS=';'; echo "${ebook_entries[*]}")

    # Update tags and ebooks databases
    for tag in "${current_tags[@]}"; do
        echo "$tag" >> "$NOTES_TAGS_DB"
    done
    for entry in "${ebook_entries[@]}"; do
        local ebook_path="${entry%#*}"
        echo "$ebook_path" >> "$NOTES_EBOOKS_DB"
    done

    # Sort and deduplicate
    sort -u "$NOTES_TAGS_DB" -o "$NOTES_TAGS_DB"
    sort -u "$NOTES_EBOOKS_DB" -o "$NOTES_EBOOKS_DB"

    # Replace the line in NOTES_DB
    local old_line=$(grep -F "|${note_path}|" "$NOTES_DB")
    local new_line="${note_title}|${note_path}|${tags_str}|${ebooks_str}"

    # Use temp file to update NOTES_DB
    local temp_db
    temp_db=$(mktemp)
    while IFS= read -r line; do
        if [[ "$line" == "$old_line" ]]; then
            echo "$new_line"
        else
            echo "$line"
        fi
    done < "$NOTES_DB" > "$temp_db"

    if ! mv "$temp_db" "$NOTES_DB"; then
        whiptail --msgbox "Failed to update the note in the database." 8 50 >/dev/tty
        return 1
    fi

    whiptail --msgbox "Note attributes updated successfully." 8 50 >/dev/tty
    return 0
}

edit_note() {
    # Global
    note_path="$1"

    # Load existing note data into globals
    if ! load_note_data; then
        whiptail --msgbox "Error loading note data." 8 50 >/dev/tty
        return 1
    fi

    # DEBUG
    #echo ebook_entries: >&2
    #declare -p ebook_entries >&2

    local choice
    while true; do
        # Prepare status messages
        #local path_status="$note_path"
        local path_status
        local tag_status="none"
        [ ${#current_tags[@]} -gt 0 ] && tag_status="${#current_tags[@]} tags"
        local ebook_status="none"
        [ ${#ebook_entries[@]} -gt 0 ] && ebook_status="${#ebook_entries[@]} ebooks"

        # Truncate Note Path
        local dirname filename dirname_tr filename_tr tr_max
        tr_max=34 # max-*.txt

        dirname="$(dirname "$note_path")"
        dirname_tr="$(truncate_dirname "$dirname")"

        filename="$(basename "$note_path")"
        filename_tr="$(truncate_filename "$filename" $tr_max)"

        path_status="${dirname_tr}/${filename_tr}"

        choice=$(whiptail --title "Edit Note" --menu "Edit note properties" 20 100 8 \
            "Note Title"    "Current: ${note_title:0:50}" \
            "Note Path"     "Path: ${path_status}" \
            "Tags"          "Status: ${tag_status}" \
            "Ebooks"        "Status: ${ebook_status}" \
            "Save and Edit" "Save changes and open in editor" \
            "Save and Return" "Save changes and exit" 3>&1 1>&2 2>&3)
        [ $? -eq 0 ] || break

        case "$choice" in
            "Note Title")
		local old_note_title
		old_note_title="$note_title"	# FIX: CHECK ILLEGAL CHARS.

                note_title=$(whiptail --inputbox "Enter note title:" 8 40 "$note_title" 3>&1 1>&2 2>&3)

                # FIX: CHECK FOR ILLEGAL CHARS.
                if [[ "$note_title" =~ [\|#] ]]; then
                        note_title="$old_note_title"    # Revert
                        whiptail --title "Attention" --msgbox "Note title cannot contain illegal characters (|#)." 8 60
                        continue
                fi
                # END FIX.
                ;;
            "Note Path")
                whiptail --msgbox "Note path is: $note_path" 10 80
                ;;
            "Tags")
                manage_tags
                ;;
            "Ebooks")
                manage_ebooks
                ;;
            "Save and Edit")
                if update_note_in_db; then
                    #nano "$note_path"
		    "$DEFAULT_EDITOR" "$note_path"
                    break
                fi
                ;;
            "Save and Return")
                update_note_in_db
                break
                ;;
        esac
    done
}

paginate_get_notes() {
    # Clear any previous selection
    SELECTED_ITEM=""

    local chunk_size=200

    # If new items are passed in, update FILTERED_EBOOKS and reset CURRENT_PAGE.
    # First arg is custom menu title.
    local menu_title
    if [ "$#" -gt 0 ]; then
        menu_title="$1"  # First argument is the title
        shift  # Shift to remove the title from the arguments
        FILTERED_EBOOKS=("$@")  # Remaining arguments are the items
        CURRENT_PAGE=0
    fi

    # Set default title if menu_title is not provided.
    # But if menu_title is not privided as $1 then FILTERED_EBOOKS will be errorneous.
    : "${menu_title:=Paged Menu}"

    [[ ${#FILTERED_EBOOKS[@]} -eq 0 ]] && return 1

    local total_pages=$(( ( ${#FILTERED_EBOOKS[@]} + chunk_size - 1 ) / chunk_size ))
    # Ensure CURRENT_PAGE is within valid bounds
    if (( CURRENT_PAGE >= total_pages )); then
        CURRENT_PAGE=$(( total_pages - 1 ))
    fi

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        # Extract the current chunk
        local current_chunk=("${FILTERED_EBOOKS[@]:$start:$chunk_size}")
        local menu_options=()

        # Add navigation options if needed
        if (( CURRENT_PAGE > 0 )); then
            menu_options+=("previous page" "")
        fi
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("next page" "")
        fi

        # Append the current page items
        menu_options+=("${current_chunk[@]}")

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "Choose an item (Page $((CURRENT_PAGE + 1))/$total_pages)" \
            20 170 10 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        # Exit with code 1 if user cancels. Make sure to reset SELECTED_ITEM.
        if [ $? -ne 0 ]; then
            SELECTED_ITEM=""
            return 1
        fi

        case "$choice" in
            "previous page")
                (( CURRENT_PAGE-- ))
                ;;
            "next page")
                (( CURRENT_PAGE++ ))
                ;;
            *)
                # Return the index              
                SELECTED_ITEM="$choice"                
                return 0
                ;;
        esac
    done

    return 1
}

list_notes() {
    # SUB FUNCTION FOR PAGINATE SELECT TAG.
    show_tag_menu() {
        local TAG_OPTIONS__=("$@")  # Expect pairs: tag, ""
        local PAGE_SIZE=10
        local page=0
        local total_items=$(( ${#TAG_OPTIONS__[@]} / 2 ))
        local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
        local selected_tag__=""
        local choice start end menu_items

        while true; do
            start=$(( page * PAGE_SIZE * 2 ))
            end=$(( start + PAGE_SIZE * 2 ))
            menu_items=("${TAG_OPTIONS__[@]:$start:$((PAGE_SIZE * 2))}")

            # Add navigation items
            if (( page > 0 )); then
                menu_items+=("<< Previous Page" "")
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=("Next Page >>" "")
            fi

            choice=$(whiptail --title "Filter by Tag (Page $((page + 1))/$total_pages)" \
                            --menu "Choose a tag to find notes to edit:" 20 60 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3)

            # Handle user action
            exit_status=$?
            if [[ $exit_status -ne 0 ]]; then
                # User pressed Cancel or Esc
                return 1
            fi

            case "$choice" in
                "Next Page >>")
                    ((page++))
                    ;;
                "<< Previous Page")
                    ((page--))
                    ;;
                *)
                    selected_tag__="$choice"
                    break
                    ;;
            esac
        done

        echo "$selected_tag__"
    }

    local db_file="$NOTES_DB"
    [[ ! -f "$db_file" || ! -s "$db_file" ]] && {
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    # FIX: POPULATE LINES BY LETTING USER SELECT TAG FIRST.
    # Read all tags into a bash array for whiptail menu
    local -a tags lines

    mapfile -t tags < "$NOTES_TAGS_DB"

    if [[ "${#tags[@]}" -eq 0 ]]; then
        mapfile -t lines < "$NOTES_DB"
    else
        # Build tag options for whiptail (needs tag and description pairs)
        local TAG_OPTIONS=()
        TAG_OPTIONS+=("ANY TAG" "")
        for tag in "${tags[@]}"; do
            TAG_OPTIONS+=("$tag" "")
        done

        # ADDITIONAL FIX: PAGINATE SELECT TAG.
        local selected_tag=$(show_tag_menu "${TAG_OPTIONS[@]}")

        # # Show menu and let user choose a tag
        # local selected_tag
        # selected_tag=$(whiptail --title "Filter by Tag" \
        #                         --menu "Choose a tag to find linked notes:" 20 60 10 \
        #                         "${TAG_OPTIONS[@]}" \
        #                         3>&1 1>&2 2>&3) || return 1

        if [[ "$selected_tag" == "ANY TAG" ]]; then
            mapfile -t lines < "$NOTES_DB"
        else
            # Populate array with lines that have exact match for selected tag
            mapfile -t lines < <(awk -F'|' -v tag="$selected_tag" '      
                {
                    n = split($3, tags, ",")
                    for (i = 1; i <= n; i++) {
                        if (tags[i] == tag) {
                            print $0
                            next
                        }
                    }
                }' "$NOTES_DB")
        fi
    fi
    # END FIX.    

    # local lines=()
    # while IFS= read -r line; do
    #     lines+=("$line")
    # done < "$NOTES_DB"

    if [[ ${#lines[@]} -eq 0 ]]; then
        [[ -n "$selected_tag" ]] && whiptail --msgbox "No matching notes for tag '${selected_tag}'." 8 50 >/dev/tty
        # echo ""
        return 1
    fi        

    while true; do
        # Reset arrays and index for fresh load each iteration
        local -a menu_entries=()
        local -a MENU_PATH_ENTRIES=()
        local idx=1

        # Load current database state
        while IFS='|' read -r title path tags _; do
            # Truncate long title
            title_tr="${title:0:50}"

            local tag_display=""
            [ -n "$tags" ] && tag_display=" [${tags}]"
            menu_entries+=("${idx}:${title_tr}" "${tag_display}")
            MENU_PATH_ENTRIES+=("$path" "")
            ((idx++))
        done < <(printf '%s\n' "${lines[@]}")

        [ ${#menu_entries[@]} -eq 0 ] && {
            whiptail --msgbox "No notes found in database." 8 40
            return 1
        }

        # Show interactive menu
        #local selected_idx
        #selected_idx=$(whiptail \
        #    --title "Note Selection" \
        #    --cancel-button "Back" \
        #    --menu "Choose a note to edit" \
        #    20 170 10 \
        #    "${menu_entries[@]}" \
        #    3>&1 1>&2 2>&3)
        #
        # Exit on cancel
        #[ $? -ne 0 ] && break

        # Paginate menu entries instead.
        CURRENT_PAGE=0
        SELECTED_ITEM=""

        ! paginate_get_notes "Edit Note" "${menu_entries[@]}" && break

        local selected_idx="$SELECTED_ITEM"

        # If user cancels out of paginate menu then SELECTED_ITEM is empty.
        [ -z "selected_idx" ] && break

        # Process selection
        selected_idx="$(echo "$selected_idx" | cut -d':' -f1)"
        local m=$((2 * selected_idx - 1))
        local array_index=$((m - 1))
        local selected_path="${MENU_PATH_ENTRIES[$array_index]}"
        
        # Edit note, exactly as it says ;-)
        edit_note "$selected_path"
    done
}

# Following code section is about opening ebook file associated with a note
# with an external viewer like evince.
get_notes() {
    # SUB FUNCTION FOR PAGINATE SELECT TAG.
    show_tag_menu() {
        local TAG_OPTIONS__=("$@")  # Expect pairs: tag, ""
        local PAGE_SIZE=10
        local page=0
        local total_items=$(( ${#TAG_OPTIONS__[@]} / 2 ))
        local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
        local selected_tag__=""
        local choice start end menu_items

        while true; do
            start=$(( page * PAGE_SIZE * 2 ))
            end=$(( start + PAGE_SIZE * 2 ))
            menu_items=("${TAG_OPTIONS__[@]:$start:$((PAGE_SIZE * 2))}")

            # Add navigation items
            if (( page > 0 )); then
                menu_items+=("<< Previous Page" "")
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=("Next Page >>" "")
            fi

            choice=$(whiptail --title "Filter by Tag (Page $((page + 1))/$total_pages)" \
                            --menu "Choose a tag to find linked notes:" 20 60 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3)

            # Handle user action
            exit_status=$?
            if [[ $exit_status -ne 0 ]]; then
                # User pressed Cancel or Esc
                return 1
            fi

            case "$choice" in
                "Next Page >>")
                    ((page++))
                    ;;
                "<< Previous Page")
                    ((page--))
                    ;;
                *)
                    selected_tag__="$choice"
                    break
                    ;;
            esac
        done

        echo "$selected_tag__"
    }

    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 >/dev/tty
        return 1
    fi

    # FIX: POPULATE LINES BY LETTING USER SELECT TAG FIRST.
    # Read all tags into a bash array for whiptail menu
    local -a tags lines

    mapfile -t tags < "$NOTES_TAGS_DB"

    if [[ "${#tags[@]}" -eq 0 ]]; then
        mapfile -t lines < "$NOTES_DB"
    else
        # Build tag options for whiptail (needs tag and description pairs)
        local TAG_OPTIONS=()
        TAG_OPTIONS+=("ANY TAG" "")
        for tag in "${tags[@]}"; do
            TAG_OPTIONS+=("$tag" "")
        done

        # ADDITIONAL FIX: PAGINATE SELECT TAG.
        local selected_tag=$(show_tag_menu "${TAG_OPTIONS[@]}")

        # # Show menu and let user choose a tag
        # local selected_tag
        # selected_tag=$(whiptail --title "Filter by Tag" \
        #                         --menu "Choose a tag to find linked notes:" 20 60 10 \
        #                         "${TAG_OPTIONS[@]}" \
        #                         3>&1 1>&2 2>&3) || return 1

        if [[ "$selected_tag" == "ANY TAG" ]]; then
            mapfile -t lines < "$NOTES_DB"
        else
            # Populate array with lines that have exact match for selected tag
            mapfile -t lines < <(awk -F'|' -v tag="$selected_tag" '      
                {
                    n = split($3, tags, ",")
                    for (i = 1; i <= n; i++) {
                        if (tags[i] == tag) {
                            print $0
                            next
                        }
                    }
                }' "$NOTES_DB")
        fi
    fi
    # END FIX.    

    # local lines=()
    # while IFS= read -r line; do
    #     lines+=("$line")
    # done < "$NOTES_DB"

    if [[ ${#lines[@]} -eq 0 ]]; then
        [[ -n "$selected_tag" ]] && whiptail --msgbox "No matching notes for tag '${selected_tag}'." 8 50 >/dev/tty
        # echo ""
        return 1
    fi

    local options=()
    for i in "${!lines[@]}"; do
        local note_path=$(cut -d'|' -f2 <<< "${lines[$i]}")
        local tags=$(cut -d'|' -f3 <<< "${lines[$i]}")

        # Truncate note path
        local dir_tr filename_tr note_path_tr
        dir_tr="$(dirname "$note_path")"
        dir_tr="$(truncate_dirname "$dir_tr" 50)"
        filename_tr="$(basename "$note_path")"
        filename_tr="$(truncate_filename "$filename_tr" 50)"
        note_path_tr="${dir_tr}/${filename_tr}"

        # Truncate tags
        local tags_tr
        tags_tr="$(truncate_tags "$tags")"

        # Menu options (now, truncated)
        #options+=("$((i+1))" "$note_path | Tags: $tags")
        options+=("$((i+1))" "${note_path_tr} [${tags_tr}]")
    done

    #local selected_line_tag
    #selected_line_tag=$(whiptail --menu "Select a note" 20 100 10 "${options[@]}" 3>&1 1>&2 2>&3)
    #[[ $? -ne 0 ]] && { echo ""; return 1; }

    # Paginate instead
    CURRENT_PAGE=0
    SELECTED_ITEM=""

    ! paginate_get_notes "Open Associated eBook" "${options[@]}" && return 1
    local selected_line_tag="$SELECTED_ITEM"

    local selected_index=$((selected_line_tag - 1))
    [[ $selected_index -lt 0 || $selected_index -ge ${#lines[@]} ]] && return 1

    echo "${lines[$selected_index]}"
}

get_ebooks() {
    local selected_line="$1"
    [[ -z "$selected_line" ]] && { echo ""; return 1; }

    local ebooks_part=$(cut -d'|' -f4 <<< "$selected_line")
    [[ -z "$ebooks_part" ]] && { whiptail --msgbox "No ebooks associated with the note." 8 50 >/dev/tty;  return 1; }

    IFS=';' read -ra ebooks <<< "$ebooks_part"
    [[ ${#ebooks[@]} -eq 0 ]] && { whiptail --msgbox "No ebooks associated with the note." 8 50 >/dev/tty; return 1; }

    local ebook_options=()
    for i in "${!ebooks[@]}"; do
        local ebook_path=$(cut -d'#' -f1 <<< "${ebooks[$i]}")

        # Truncate ebook path
        local dir_tr filename_tr ebook_path_tr
        dir_tr="$(dirname "$ebook_path")"
        dir_tr="$(truncate_dirname "$dir_tr" 50)"
        filename_tr="$(basename "$ebook_path")"
        filename_tr="$(truncate_filename "$filename_tr" 50)"
        ebook_path_tr="${dir_tr}/${filename_tr}"

        # Menu options, now truncated
        #ebook_options+=("$((i+1))" "$ebook_path")
        ebook_options+=("$((i+1))" "${ebook_path_tr}")
    done

    local selected_ebook_tag
    selected_ebook_tag=$(whiptail --menu "Select an ebook" 20 170 10 "${ebook_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
    [[ $? -ne 0 ]] && { echo ""; return 1; }

    local ebook_index=$((selected_ebook_tag - 1))
    [[ $ebook_index -lt 0 || $ebook_index -ge ${#ebooks[@]} ]] && { echo ""; return 1; }

    echo "${ebooks[$ebook_index]}"
}

get_chapters() {
    local selected_ebook="$1"
    [[ -z "$selected_ebook" ]] && { echo ""; return 1; }

    local chapters_part=$(cut -d'#' -f2 <<< "$selected_ebook")
    #[[ -z "$chapters_part" ]] && { whiptail --msgbox "No chapters associated with the ebook." 20 80; echo ""; return 1; }

    IFS=',' read -ra chapters <<< "$chapters_part"
    #[[ ${#chapters[@]} -eq 0 ]] && { whiptail --msgbox "No chapters associated with the ebook." 20 80; echo ""; return 1; }

    local chapter_options=()

    # Open with no bookmark
    chapter_options+=(">> Just open" "")

    for i in "${!chapters[@]}"; do
        chapter_options+=("$((i+1))" "${chapters[$i]}")
    done

    local selected_chapter_tag
    selected_chapter_tag=$(whiptail --menu "Select a chapter" 20 80 10 "${chapter_options[@]}" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && { echo ""; return 1; }

    if [[ "$selected_chapter_tag" == ">> Just open" ]]; then
        echo ">> Just open"
        return
    fi

    local chapter_index=$((selected_chapter_tag - 1))
    [[ $chapter_index -lt 0 || $chapter_index -ge ${#chapters[@]} ]] && { echo ""; return 1; }

    echo "${chapters[$chapter_index]}"
}

extract_page() {
    local chapter_entry="$1"
    [[ -z "$chapter_entry" ]] && { echo ""; return 1; }

    local page_part="${chapter_entry#*:}"
    page_part="${page_part%%-*}"
    [[ -z "$page_part" ]] && { whiptail --msgbox "Invalid chapter format." 20 80; echo ""; return 1; }
    [[ "$page_part" =~ ^[0-9]+$ ]] || { whiptail --msgbox "Invalid page number: $page_part" 20 80; echo ""; return 1; }

    echo "$page_part"
}

open_evince() {
    local selected_ebook="$1"
    local page="$2"
    [[ -z "$selected_ebook" ]] && return 1   # Allow empty pages to just open the document.

    local ebook_path=$(cut -d'#' -f1 <<< "$selected_ebook")
    [[ -f "$ebook_path" ]] || { whiptail --msgbox "Ebook not found: $ebook_path" 20 80; return 1; }

    # extract extension then get viewer accordingly.
    local ext="${ebook_path##*.}"
    local viewer="${EXTENSION_COMMANDS[$ext]}"

    # check viewer is installed in system
    if ! command -v "$viewer" &>/dev/null; then
        whiptail --title "Alert" --msgbox "Command ${viewer} is not installed! Install it first." 20 80
        return 1
    fi

    #evince -p "$page" "$ebook_path" &> /dev/null & disown

    if [ -z "$page" ]; then
        #evince "$ebook_path" &> /dev/null & disown
	    #"$DEFAULT_VIEWER" "$ebook_path" &> /dev/null & disown
        "$viewer" "$ebook_path" &> /dev/null & disown
    else
        if [[ "$viewer" == "mupdf" ]]; then
            local cmd_and_option=(${VIEWER_COMMANDS[$viewer]})
            "${cmd_and_option[@]}" "$ebook_path" "$page" &> /dev/null & disown
            return
        elif [[ "$viewer" == "qpdfview" ]]; then
            local cmd_and_option=(${VIEWER_COMMANDS[$viewer]})
            "${cmd_and_option[@]}" "${ebook_path}#${page}" &> /dev/null & disown
            return                    
        fi
        #evince -p "$page" "$ebook_path" &> /dev/null & disown
	    #"$DEFAULT_VIEWER" -p "$page" "$ebook_path" &> /dev/null & disown        
        
        local cmd_and_option=(${VIEWER_COMMANDS[$viewer]})
        "${cmd_and_option[@]}" "$page" "$ebook_path" &> /dev/null & disown

    fi
}

handle_no_chapters() {
    local selected_ebook="$1"
    local choice exit_status    

    # Display whiptail menu and capture both output and exit status
    choice=$(whiptail --title "No Chapters Found" \
                     --menu "What would you like to do?" \
                     15 60 4 \
                     "Open" "Open ebook anyway" \
                     "Return" "Return without opening" \
                     3>&1 1>&2 2>&3)
    exit_status=$?

    # Handle user selection
    case $exit_status in
        0)
            case "$choice" in
                "Open")
                    open_evince "$selected_ebook"
                    ;;
                "Return")
                    return
                    ;;
            esac
            ;;
        *)
            # User pressed Cancel or closed dialog
            return
            ;;
    esac
}

open_note_ebook_page() {
    local selected_line=$(get_notes)
    [[ -z "$selected_line" ]] && return 1

    local selected_ebook=$(get_ebooks "$selected_line")
    [[ -z "$selected_ebook" ]] && return 1

    # Extract the chapters part from the selected_ebook
    local chapters_part=$(cut -d'#' -f2 <<< "$selected_ebook")

    if [[ -n "$chapters_part" ]]; then
        # Chapters are present, prompt user to select one
        local selected_chapter=$(get_chapters "$selected_ebook")

        # >> Just open
        if [[ "$selected_chapter" == ">> Just open" ]]; then
            handle_no_chapters "$selected_ebook"
            return
        fi

        if [ -n "$selected_chapter" ]; then
            local page=$(extract_page "$selected_chapter")
            [[ -z "$page" ]] && return 1
            open_evince "$selected_ebook" "$page"
        #else
        #    # User canceled chapter selection; open without page
        #    open_evince "$selected_ebook"
        fi
    else
        # No chapters available; ask to open the ebook directly
        #open_evince "$selected_ebook"
        handle_no_chapters "$selected_ebook"
    fi
}

# Following code section is about doing operations with note filtered by tag.
# DEPRECATED.
get_note_tag_from_global_list_old() {
    local tags_file="${NOTES_TAGS_DB}"
    if [[ ! -f "$tags_file" ]]; then
        echo "Error: Tags database file not found." >&2
        return 1
    fi

    # Read tags into array
    local tags=()
    while IFS= read -r tag; do
        tags+=("$tag" "")
    done < "$tags_file"

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo "No tags available in the database." >&2
        return 1
    fi

    # Use whiptail to display menu
    local selected_tag
    selected_tag=$(whiptail --title "Do stuff by Tag" --menu "Choose a tag" 20 40 10 "${tags[@]}" 3>&1 1>&2 2>&3 >/dev/tty)

    # Check if selection was cancelled
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    echo "$selected_tag"
}

# FIX: Paginated.
get_note_tag_from_global_list() {
    local tags_file="${NOTES_TAGS_DB}"
    if [[ ! -f "$tags_file" ]]; then
        #echo "Error: Tags database file not found." >&2
        whiptail --msgbox "No tags found. Add at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

    # Read all tags into array
    local all_tags=()
    while IFS= read -r tag; do
        all_tags+=("$tag")
    done < "$tags_file"

    if [[ ${#all_tags[@]} -eq 0 ]]; then
        #echo "No tags available in the database." >&2
        whiptail --msgbox "No tags found. Add at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

    # Pagination variables
    local current_page=0
    local tags_per_page=20
    local total_pages=$(( (${#all_tags[@]} + tags_per_page - 1) / tags_per_page ))

    while true; do
        # Calculate start and end indices for current page
        local start=$((current_page * tags_per_page))
        local end=$((start + tags_per_page))
        
        # Prepare menu items for current page
        local menu_items=()
        for ((i=start; i<end && i<${#all_tags[@]}; i++)); do
            menu_items+=("${all_tags[i]}" "")
        done

        # Add navigation buttons if needed
        if [[ $current_page -gt 0 ]]; then
            menu_items+=("<< Previous Page" "")
        fi
        if [[ $current_page -lt $((total_pages - 1)) ]]; then
            menu_items+=(">> Next Page" "")
        fi

        # Use whiptail to display menu
        local selected_tag
        selected_tag=$(whiptail --title "Do stuff by Tag (Page $((current_page + 1))/$total_pages)" \
                               --menu "Choose a tag" 20 40 10 "${menu_items[@]}" \
                               3>&1 1>&2 2>&3 >/dev/tty)

        # Check if selection was cancelled
        if [[ $? -ne 0 ]]; then
            return 1
        fi

        # Handle pagination navigation
        case "$selected_tag" in
            "<< Previous Page")
                current_page=$((current_page - 1))
                continue
                ;;
            ">> Next Page")
                current_page=$((current_page + 1))
                continue
                ;;
            *)
                echo "$selected_tag"
                return 0
                ;;
        esac
    done
}

filter_notes_by_tag() {
    local target_tag="$1"
    local notes_file="${NOTES_DB}"
    FILTERED_NOTES_BY_TAG=()

    if [[ ! -f "$notes_file" || ! -s "$notes_file" ]]; then
        #echo "Error: Notes database file not found." >&2
        #whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 </dev/tty >/dev/tty  # we don't need this since add note with same tag.
        return 1
    fi

    while IFS= read -r line; do
        IFS='|' read -ra fields <<< "$line"
        [[ ${#fields[@]} -lt 3 ]] && continue  # Skip invalid lines

        # Check if target tag exists in the comma-separated list
        if [[ ",${fields[2]}," =~ ",${target_tag}," ]]; then
            FILTERED_NOTES_BY_TAG+=("$line")
        fi
    done < "$notes_file"
}

list_notes_from_filtered() {
    while true; do
        # Reset arrays and index for fresh load each iteration
        local -a menu_entries=()
        local -a MENU_PATH_ENTRIES=()
        local idx=1

        # Populate arrays from arguments passed to the function
        for entry in "$@"; do
            IFS='|' read -r title path tags _ <<< "$entry"
            # Truncate long title
            title_tr="${title:0:50}"

            local tag_display=""
            [ -n "$tags" ] && tag_display=" [${tags}]"
            menu_entries+=("${idx}:${title_tr}" "${tag_display}")
            MENU_PATH_ENTRIES+=("$path" "")
            ((idx++))
        done

        [ ${#menu_entries[@]} -eq 0 ] && {
            whiptail --msgbox "No notes found in database" 8 40
            return 1
        }

        # Show interactive menu with pagination
        CURRENT_PAGE=0
        SELECTED_ITEM=""

        ! paginate_get_notes "Edit Note" "${menu_entries[@]}" && break

        local selected_idx="$SELECTED_ITEM"

        # Exit if user cancels
        [ -z "$selected_idx" ] && break

        # Process selection
        selected_idx="$(echo "$selected_idx" | cut -d':' -f1)"
        local m=$((2 * selected_idx - 1))
        local array_index=$((m - 1))
        local selected_path="${MENU_PATH_ENTRIES[$array_index]}"
        
        # Edit the selected note
        edit_note "$selected_path"
    done
}

get_notes_from_filtered() {
    # Directly populate lines from arguments
    local lines=("$@")

    if [[ ${#lines[@]} -eq 0 ]]; then
        whiptail --msgbox "No notes found in database" 20 80
        echo ""
        return 1
    fi

    local options=()
    for i in "${!lines[@]}"; do
        local note_path=$(cut -d'|' -f2 <<< "${lines[$i]}")
        local tags=$(cut -d'|' -f3 <<< "${lines[$i]}")

        # Truncate note path
        local dir_tr filename_tr note_path_tr
        dir_tr="$(dirname "$note_path")"
        dir_tr="$(truncate_dirname "$dir_tr" 50)"
        filename_tr="$(basename "$note_path")"
        filename_tr="$(truncate_filename "$filename_tr" 50)"
        note_path_tr="${dir_tr}/${filename_tr}"

        # Truncate tags
        local tags_tr
        tags_tr="$(truncate_tags "$tags")"

        # Menu options (now, truncated)
        options+=("$((i+1))" "${note_path_tr} [${tags_tr}]")
    done

    # Paginate selection
    CURRENT_PAGE=0
    SELECTED_ITEM=""

    ! paginate_get_notes "Open Associated eBook" "${options[@]}" && return 1
    local selected_line_tag="$SELECTED_ITEM"

    local selected_index=$((selected_line_tag - 1))
    [[ $selected_index -lt 0 || $selected_index -ge ${#lines[@]} ]] && return 1

    echo "${lines[$selected_index]}"
}

open_note_ebook_page_from_filtered() {
    local selected_line=$(get_notes_from_filtered "$@")
    [[ -z "$selected_line" ]] && return 1

    local selected_ebook=$(get_ebooks "$selected_line")
    [[ -z "$selected_ebook" ]] && return 1

    # Extract the chapters part from the selected_ebook
    local chapters_part=$(cut -d'#' -f2 <<< "$selected_ebook")

    if [[ -n "$chapters_part" ]]; then
        # Chapters are present, prompt user to select one
        local selected_chapter=$(get_chapters "$selected_ebook")

        # >> Just open
        if [[ "$selected_chapter" == ">> Just open" ]]; then
            handle_no_chapters "$selected_ebook"
            return
        fi

        if [ -n "$selected_chapter" ]; then
            local page=$(extract_page "$selected_chapter")
            [[ -z "$page" ]] && return 1
            open_evince "$selected_ebook" "$page"
        #else
        #    # User canceled chapter selection; open without page
        #    open_evince "$selected_ebook"
        fi
    else
        # No chapters available; ask to open the ebook directly
        #open_evince "$selected_ebook"
        handle_no_chapters "$selected_ebook"
    fi
}

associate_new_note_to_project() {
    (
        ask() {
            choice=$(whiptail --title "Next action" \
                            --menu "Choose an option:" \
                            15 60 2 \
                            "associate" "Associate this note with project file" \
                            "continue"  "Do nothing further" \
                            3>&1 1>&2 2>&3)

            exit_status=$?

            # Handle Cancel or ESC
            if [[ $exit_status -ne 0 ]]; then
                return 1
            fi

            case "$choice" in
                continue)
                    return 1
                    ;;
                associate)
                    return 0
                    ;;
            esac
        }
        
        ask
    ) || return 1

    # accept note path as arg
    local NEW_NOTE_PATH="$1"

    local temp_file line_updated duplicate_detected project_found
    temp_file=$(mktemp) || return 1
    line_updated=0
    duplicate_detected=0
    project_found=0

    # Check if databases exist
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "Please add at least one project and try again." 8 60
        return 1
    fi
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "Please add at least one note and try again." 8 60
        return 1
    fi

    # FIX: ALLOW FILTERING BY GLOB.
    # Get pattern from user using whiptail
    local pattern
    pattern=$(whiptail --inputbox "Enter filename glob pattern to filter projects (empty for wildcard):" 10 60 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    : "${pattern:=*}"	# default to * if unset.

    # Enable case-insensitive glob matching
    shopt -s nocasematch
    
    local project_menu_options=()
    local filename title path rest
    while IFS='|' read -r title path rest; do
        # Extract filename from path
        filename=$(basename "$path")
        
        # Check if filename matches the pattern (now case-insensitive)
        if [[ "$filename" == $pattern ]]; then
            project_menu_options+=("$path" "")
        fi
    done < "$PROJECTS_DB"
    
    # Restore default case sensitivity
    shopt -u nocasematch

    # If no matches found, show message and exit
    if [ ${#project_menu_options[@]} -eq 0 ]; then
        whiptail --msgbox "No projects matched the pattern '${pattern}'" 8 40 >/dev/tty
        return 1
    fi
    # END FIX.

    # Project selection
    paginate_get_projects "Select Project" "${project_menu_options[@]}"
    local selected_project_path
    selected_project_path="$SELECTED_ITEM_PROJECT"
    [[ -z "$selected_project_path" ]] && return 1

    # WE'VE SELECTED PROJECT FILE AT THIS POINT!!!!

    local selected_note_path="$NEW_NOTE_PATH"

    # Process PROJECTS_DB - update each line (only change line of selected project file)
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi

        IFS='|' read -r title path notes <<< "$line"
        # If there is matched line...
        if [[ "$path" == "$selected_project_path" ]]; then
            project_found=1
            current_notes="$notes"
            local notes_array=()

            # Check for duplicates
            IFS=',' read -ra notes_array <<< "$current_notes"
            local duplicate=0	# Reset for each iteration.
            # If duplicate found then set duplicate and break out of for loop here.
            for note in "${notes_array[@]}"; do
                [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
            done

            if (( duplicate )); then
                whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                # reset
                line_updated=0

                duplicate_detected=1
                # Rebuild original line
                new_line="$title|$path|$current_notes"
                # There is no fourth field!!!!
                # [[ -n "$rest" ]] && new_line+="|$rest"
                echo "$new_line" >> "$temp_file"	# No change.
            else
                # reset
                duplicate_detected=0

                # Update notes
                # If there is no previously associated note...
                if [[ -z "$current_notes" ]]; then
                    new_notes="$selected_note_path"
                else
                    new_notes="$current_notes,$selected_note_path"
                fi
                new_line="$title|$path|$new_notes"
                #[[ -n "$rest" ]] && new_line+="|$rest"
                echo "$new_line" >> "$temp_file"	# Changes made.
                line_updated=1
            fi
        else
            # Just leave the line unchanged.
            echo "$line" >> "$temp_file"
        fi
    done < "$PROJECTS_DB"

    # Handle processing results
    if (( project_found )); then
        if (( line_updated && !duplicate_detected )); then
            mv "$temp_file" "$PROJECTS_DB"
            whiptail --msgbox "Note successfully associated with the project." 10 50
        elif (( duplicate_detected )); then
            rm "$temp_file"
            #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
            return 1
        else
            rm "$temp_file"
            whiptail --msgbox "No changes were made to the project entry." 10 50
            return 1
        fi
    else
        rm "$temp_file"
        whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
        return 1
    fi
}

associate_notes_by_tag_to_project() {
    select_filtered_note_by_tag() {
        local menu_items=()
        local line

        # Build menu items from arguments
        local _title note_path _tags _rest
        for line in "$@"; do
            IFS='|' read -r _title note_path _tags _rest <<< "$line"
            menu_items+=("$note_path" "")
        done

        # Show menu
        local selected_note
        selected_note=$(whiptail --title "Select Note" \
            --menu "Select a note by tag:" 20 170 10 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3)

        # Handle user cancel
        [[ -z "$selected_note" ]] && return 1

        echo "$selected_note"
    }    

    select_filtered_notes_by_tag_checklist() {
        local PAGE_SIZE=5

        # ---- convert input paths → (tag, empty-desc) pairs ----
        local -a all_items=()
        local line
        for line in "$@"; do
            local path
            path=$(echo "$line" | cut -d'|' -f2)
            all_items+=( "$path" "" )
        done

        # # If no filtered notes to begin with then display the warning message.
        # if [[ ${#all_items[@]} -eq 0 ]]; then
        #     whiptail --title "Attention" \
        #             --msgbox "There are no notes by that tag. Add at least one note file and try again." \
        #             20 80
        #     return 1
        # fi        

        local total_items=$(( ${#all_items[@]} / 2 ))
        local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))

        local current_page=0
        declare -A selected_map

        while :; do
            local options=()
            local start=$(( current_page * PAGE_SIZE ))
            local end=$(( start + PAGE_SIZE ))

            # Page items
            for ((i=start; i<end && i<total_items; i++)); do
                local tag="${all_items[i*2]}"
                local state=OFF
                [[ ${selected_map["$tag"]} ]] && state=ON
                options+=( "$tag" "" "$state" )
            done

            # Navigation
            (( current_page > 0 )) && options+=( "<< Prev page" "Go to previous page" OFF )
            (( current_page < total_pages - 1 )) && options+=( ">> Next page" "Go to next page" OFF )
            options+=( "SUBMIT" "Finish selection" OFF )

            local choice
            choice=$(whiptail --title "Select Notes (Page $((current_page+1))/$total_pages)" \
                            --checklist "Select notes by tag" 20 170 10 \
                            "${options[@]}" \
                            3>&1 1>&2 2>&3
            )

            [[ $? -ne 0 ]] && return 1

            # Convert choice string to array
            readarray -t chosen < <(echo "$choice" | xargs -n1)

            local go_prev=0 go_next=0 do_submit=0

            for item in "${chosen[@]}"; do
                case "$item" in
                    "<< Prev page") go_prev=1 ;;
                    ">> Next page") go_next=1 ;;
                    "SUBMIT")       do_submit=1 ;;
                    *) selected_map["$item"]=1 ;;
                esac
            done

            # Remove unchecked items from current page
            for ((i=start; i<end && i<total_items; i++)); do
                local tag="${all_items[i*2]}"
                local found=0
                for item in "${chosen[@]}"; do
                    [[ "$item" == "$tag" ]] && found=1
                done
                [[ $found -eq 0 ]] && unset selected_map["$tag"]
            done

            # ---- safeguards ----
            if (( go_prev && go_next )); then
                whiptail --msgbox "You cannot select both Prev and Next at the same time." 8 60 >/dev/tty
                continue
            fi

            if (( do_submit )); then
                if (( go_prev || go_next )); then
                    whiptail --msgbox "Submit cannot be combined with page navigation." 8 60 >/dev/tty
                    continue
                fi

                if (( ${#selected_map[@]} == 0 )); then
                    whiptail --msgbox "Please select at least one note before submitting." 8 60 >/dev/tty
                    continue
                fi

                break
            fi

            (( go_next )) && ((current_page++))
            (( go_prev )) && ((current_page--))
        done

        # Output selected file paths (newline-delimited)
        local p
        for p in "${!selected_map[@]}"; do
            echo "$p"
        done
    }

    update_proj_db_file_by_notes_checklist() {
        local selected_project_path="$1"
        local temp_file="$2"
        shift 2

        # assign the rest to an array - what user has selected from whiptail checklist.
        local sel_note_paths_checklist=("$@")

        # Empty temp_file
        > "$temp_file"

        local title path current_notes new_notes note
        local current_array=()
        # Read PROJECTS_DB line by line
        while IFS='|' read -r title path current_notes; do
            if [[ "$path" == "$selected_project_path" ]]; then
                # Prepare new notes string
                if [[ -z "$current_notes" ]]; then
                    # No current notes, just join selected notes
                    new_notes="$(printf '%s,' "${sel_note_paths_checklist[@]}")"
                    new_notes=${new_notes%,}   # remove trailing comma
                else
                    # Merge current notes with selected notes, remove duplicates
                    IFS=',' read -ra current_array <<< "$current_notes"
                    declare -A seen
                    local new_array=()

                    # Add current notes first
                    for note in "${current_array[@]}"; do
                        seen["$note"]=1
                        new_array+=("$note")
                    done

                    # Add selected notes if not already present
                    for note in "${sel_note_paths_checklist[@]}"; do
                        if [[ -z "${seen[$note]}" ]]; then
                            new_array+=("$note")
                        fi
                    done
                    
                    new_notes="$(printf '%s,' "${new_array[@]}")"
                    new_notes=${new_notes%,}  # remove trailing comma
                fi

                # Construct new line
                echo "$title|$path|$new_notes" >> "$temp_file"
            else
                # Keep line unchanged
                echo "$title|$path|$current_notes" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Compare temp_file and PROJECTS_DB
        if cmp -s "$temp_file" "$PROJECTS_DB"; then
            return 1  # Files are the same
        else
            return 0  # Files differ
        fi
    }

    whiptail --title "Attention" \
         --msgbox "Step 1: Select the note files.\nStep 2: Select the project files to associate them with.\n\nYou can associate multiple note files to multiple project files in this function." \
         20 80

    # let user select notes from whiptai checklist.
    local selected_notes_chk
    mapfile -t selected_notes_chk < <(select_filtered_notes_by_tag_checklist "$@")
    [[ ${#selected_notes_chk[@]} -eq 0 ]] && return 1

    local temp_file line_updated duplicate_detected project_found
    temp_file=$(mktemp) || return 1
    line_updated=0
    duplicate_detected=0
    project_found=0

    # Check if databases exist
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "Please add at least one project and try again." 8 60
        return 1
    fi
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "Please add at least one note and try again." 8 60
        return 1
    fi

    # FIX: ALLOW FILTERING BY GLOB.
    # Get pattern from user using whiptail
    local pattern
    pattern=$(whiptail --inputbox "Enter filename glob pattern to filter projects (empty for wildcard):" 10 60 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    : "${pattern:=*}"	# default to * if unset.

    # Enable case-insensitive glob matching
    shopt -s nocasematch
    
    local project_menu_options=()
    local filename title path rest
    while IFS='|' read -r title path rest; do
        # Extract filename from path
        filename=$(basename "$path")
        
        # Check if filename matches the pattern (now case-insensitive)
        if [[ "$filename" == $pattern ]]; then
            project_menu_options+=("$path" "")
        fi
    done < "$PROJECTS_DB"
    
    # Restore default case sensitivity
    shopt -u nocasematch

    # If no matches found, show message and exit
    if [ ${#project_menu_options[@]} -eq 0 ]; then
        whiptail --msgbox "No projects matched the pattern '${pattern}'" 8 40 >/dev/tty
        return 1
    fi
    # END FIX.

    while :; do
        # Project selection
        paginate_get_projects "Select Project to Associate With" "${project_menu_options[@]}"
        local selected_project_path
        selected_project_path="$SELECTED_ITEM_PROJECT"
        [[ -z "$selected_project_path" ]] && return 1

        # Update PROJECTS_DB file and check if changes are made.
        if update_proj_db_file_by_notes_checklist "$selected_project_path" "$temp_file" "${selected_notes_chk[@]}"; then
            mv "$temp_file" "$PROJECTS_DB"
            whiptail --msgbox "Notes successfully associated with the project." 10 50            
        else
            rm "$temp_file"
            whiptail --msgbox "No changes were made to the project entry. This may mean that your chosen notes are already associated with chosen project." 10 50
        fi
    done
}

do_note_filter_by_tag() {
    # Initial message
    whiptail --title "Do Stuff by Tag" --msgbox "The following advanced feature lets you narrow down note entries \
by their associated tag and do stuff with them. You can add a new note with the chosen tag, edit note or open associated ebooks. You can also associate a note to multiple projects.\n\n\
After creating a new note, you can choose to associate it to a project file. Afterwards, you can do stuff with it from Manage Goals section such as View Note or Open ebooks." 20 70

    local chosen_tag
    chosen_tag=$(get_note_tag_from_global_list) || return 1
    #filter_notes_by_tag "$chosen_tag" || { whiptail --msgbox "No notes with tag ${chosen_tag} found." 8 40 >/dev/tty; return 1; }
    filter_notes_by_tag "$chosen_tag"
    
    # # Check if any notes were actually filtered
    # if [[ ${#FILTERED_NOTES_BY_TAG[@]} -eq 0 ]]; then
    #     whiptail --msgbox "No notes found with tag: $chosen_tag" 8 40 >/dev/tty
    #     return 1
    # fi

    # TASK: need to update $FILTERED_NOTES_BY_TAG when new note with same tag is added!
    while :; do
        # Update $FILTERED_NOTES_BY_TAG array.
        #filter_notes_by_tag "$chosen_tag" || { whiptail --msgbox "No notes with tag ${chosen_tag} found." 8 40 >/dev/tty; return 1; }
        filter_notes_by_tag "$chosen_tag"
        
        # # Check if any notes were actually filtered
        # if [[ ${#FILTERED_NOTES_BY_TAG[@]} -eq 0 ]]; then
        #     whiptail --msgbox "No notes found with tag: $chosen_tag" 8 40 >/dev/tty
        #     return 1
        # fi

        local choice
        choice=$(whiptail --title "Filtered by tag: $chosen_tag" --menu "Select action:" \
            15 50 4 "Add note with same tag" "" "Edit note" "" "Open associated ebook" "" "Associate note to project" "" \
            3>&1 1>&2 2>&3) || return  # Explicit cancellation handling

        case "$choice" in
            "Add note with same tag")
                add_note "$chosen_tag" || return 1
                [[ -n "$note_path" ]] && associate_new_note_to_project "$note_path"
                ;;
            "Edit note")
                [[ ${#FILTERED_NOTES_BY_TAG[@]} -eq 0 ]] && {
                    whiptail --title "Attention" --msgbox \
                        "No notes found. Create at least one note file and try again." 10 60
                    continue
                }                
                list_notes_from_filtered "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Open associated ebook")
                [[ ${#FILTERED_NOTES_BY_TAG[@]} -eq 0 ]] && {
                    whiptail --title "Attention" --msgbox \
                        "No notes found. Create at least one note file and try again." 10 60
                    continue
                }                
                open_note_ebook_page_from_filtered "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Associate note to project")
                [[ ${#FILTERED_NOTES_BY_TAG[@]} -eq 0 ]] && {
                    whiptail --title "Attention" --msgbox \
                        "No notes found. Create at least one note file and try again." 10 60
                    continue
                }                
                associate_notes_by_tag_to_project "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
        esac
    done
}

# The following code section is about opening an ebook file in global list NOTES_EBOOKS_DB.
open_ebook_note_from_global_list() {
    paginate_menu() {
        local title=$1
        shift
        local options=("$@")  # rest are options (tag, description pairs)
        local page_size=10    # items per page
        local total_items=${#options[@]}
        local total_pages=$(( (total_items / 2 + page_size - 1) / page_size ))
        local current_page=1
        local choice

        while true; do
            local start_index=$(( (current_page - 1) * page_size * 2 ))
            local end_index=$(( start_index + page_size * 2 ))
            local page_items=("${options[@]:start_index:end_index-start_index}")

            # Add navigation items if applicable
            local menu_items=("${page_items[@]}")
            if (( current_page > 1 )); then
                menu_items+=("<< Prev page" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next page" "")
            fi

            choice=$(whiptail --title "$title" \
                            --cancel-button "Back" \
                            --menu "Page ${current_page}/${total_pages}" 20 170 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # user pressed Cancel

            case "$choice" in
                ">> Next page")
                    ((current_page++))
                    ;;
                "<< Prev page")
                    ((current_page--))
                    ;;
                *)
                    echo "$choice"
                    return 0
                    ;;
            esac
        done
    }

    # Initial message
    whiptail --title "Open eBook File From Global List" \
         --msgbox "This feature allows you to open an ebook file from global list." 8 78

    # Check if the database file exists
    if [[ ! -f "$NOTES_EBOOKS_DB" || ! -s "$NOTES_EBOOKS_DB" ]]; then
	whiptail --title "Attention" --msgbox "No ebooks found. Add at least one note and associate at least one ebook and try again." 10 50 >/dev/tty
        return 1
    fi

    # Read all lines into an array
    local ebook_paths=()
    mapfile -t ebook_paths < "$NOTES_EBOOKS_DB"

    # Check if there are any ebooks
    if [[ ${#ebook_paths[@]} -eq 0 ]]; then
	whiptail --msgbox "No eBooks found in the database." 8 40 >/dev/tty
        return 1
    fi

    # Prepare the options array for whiptail
    local options=()
    local OPTIONS_LINE=()

    local idx=1
    for line in "${ebook_paths[@]}"; do
        # Truncate this.
        local dirname filename dirname_tr filename_tr
        dirname="$(dirname "$line")"
        dirname_tr="$(truncate_dirname "$dirname" 50)"
        filename="$(basename "$line")"
        filename_tr="$(truncate_filename "$filename" 50)"

        local line_tr
        line_tr="${dirname_tr}/${filename_tr}"

        options+=("$idx" "$line_tr")
        
        # Store full line here.
        OPTIONS_LINE+=("$line")

        ((idx++))
    done

    # # Show the menu and get the selected line
    # local selected_idx selected_line
    # selected_idx=$(whiptail --title "Open eBook File From Global List" \
    #     --cancel-button "Back" \
    #     --menu "Choose an eBook to open:" \
    #     20 170 10 \
    #     "${options[@]}" \
    #     3>&1 1>&2 2>&3) || return 1

    local selected_idx selected_line
    selected_idx="$(paginate_menu "Open eBook File From Global List" "${options[@]}")" || return 1

    # Get line
    selected_line="${OPTIONS_LINE["$((selected_idx-1))"]}"

    # Check if a line was selected
    if [[ -n "$selected_line" ]]; then
        open_evince "$selected_line"
    fi
}

delete_notes() {
    local ITEMS_PER_PAGE=100

    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --title "Attention" --msgbox "No notes found." 8 40 >/dev/tty
        return 1
    fi

    # Read the file lines into an array.
    local -a lines
    mapfile -t lines < "$NOTES_DB"

    # FEATURE: ASK FOR GLOB AND FILTER BY FILE NAME.
    local glob
    glob=$(whiptail --inputbox "Enter glob to filter by file name (empty for wildcard):" 10 60 3>&1 1>&2 2>&3) || return 1

    # default to *
    : ${glob:=*}

    # 3. Filter lines by FILENAME of second field
    local filtered_lines=()
    local -A map_idx   # associative array mapping filtered index → original index

    local i line path filename
    local fidx=0

    for i in "${!lines[@]}"; do
        line=${lines[$i]}

        # Extract second field: /path/to/note/note title.txt
        IFS='|' read -r _ path _ <<< "$line"

        # Extract FILENAME only (basename)
        filename=${path##*/}

        # Match filename against user-provided glob
        if [[ "${filename,,}" == ${glob,,} ]]; then
            filtered_lines+=("$line")
            map_idx[$fidx]=$i
            ((fidx++))
        fi
    done

    local total=${#filtered_lines[@]}
    # Calculate number of pages (ITEMS_PER_PAGE items per page).
    local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
    local current_page=0

    # Global associative array to track selections across pages.
    declare -A global_selected

    # Main loop for pagination and selection.
    while true; do
        local start=$(( current_page * ITEMS_PER_PAGE ))
        local end=$(( start + ITEMS_PER_PAGE ))
        if [ "$end" -gt "$total" ]; then
            end=$total
        fi

        # Build the list for the current page.
        local -a choices=()
        local i
        for i in $(seq $start $((end - 1))); do
            local state="OFF"
            # If note was already selected, set default state to ON.
            if [ "${global_selected[$i]}" == "1" ]; then
                state="ON"
            fi

            # Truncate note path
            local note_path
            note_path=$(cut -d'|' -f2 <<< "${filtered_lines[$i]}")

            local dir_tr filename_tr note_path_tr
            dir_tr="$(dirname "$note_path")"
            dir_tr="$(truncate_dirname "$dir_tr" 50)"
            filename_tr="$(basename "$note_path")"
            filename_tr="$(truncate_filename "$filename_tr" 50)"
            note_path_tr="${dir_tr}/${filename_tr}" 

           # Use the array index as the tag and the entire line as description.
            choices+=("$i" "$note_path_tr" "$state")
        done

        # Add navigation options.
        if [ "$current_page" -gt 0 ]; then
            choices+=("__prev__" "Previous page" "OFF")
        fi
        if [ "$current_page" -lt $((pages - 1)) ]; then
            choices+=("__next__" "Next page" "OFF")
        fi
        # Always allow proceeding to the next step.
        choices+=("__proceed__" "Proceed to deletion" "OFF")

        # Show the whiptail checklist.
        local result
        result=$(whiptail --title "Delete Notes" --checklist "Select notes to delete (page $((current_page + 1))/$pages)" 20 170 10 "${choices[@]}" 3>&1 1>&2 2>&3)
        local exit_status=$?
        if [ $exit_status -ne 0 ]; then
            whiptail --title "Cancelled" --msgbox "Deletion cancelled." 10 40
            return 1
        fi

        # Do I get back "" that interferes with matching case below?
        result=$(echo $result | tr -d '"')

        # Process returned selections.
        # (Note: whiptail returns a space-delimited string.)
        local -a selected_tags
        IFS=" " read -r -a selected_tags <<< "$result"

        # For each note on the current page, update our global selections.
        local found
        for i in $(seq $start $((end - 1))); do
            found=0
            local tag
            for tag in "${selected_tags[@]}"; do
                if [ "$tag" == "$i" ]; then
                    found=1
                    break
                fi
            done
            if [ $found -eq 1 ]; then
                global_selected["$i"]=1
            else
                # Remove any deselected note from this page.
                unset global_selected["$i"]
            fi
        done

        # Check for navigation actions.
        local nav_next=0 nav_prev=0 nav_proceed=0
        for tag in "${selected_tags[@]}"; do
            case "$tag" in
                "__next__") nav_next=1 ;;
                "__prev__") nav_prev=1 ;;
                "__proceed__") nav_proceed=1 ;;
            esac
        done

        # Count navigation commands selected.
        local nav_count=$(( nav_next + nav_prev + nav_proceed ))
        if [ "$nav_count" -gt 1 ]; then
            whiptail --title "Invalid Selection" --msgbox "Please select only one navigation option at a time." 10 40
            continue
        fi

        if [ $nav_next -eq 1 ] && [ $current_page -lt $((pages - 1)) ]; then
            current_page=$(( current_page + 1 ))
            continue
        fi
        if [ $nav_prev -eq 1 ] && [ $current_page -gt 0 ]; then
            current_page=$(( current_page - 1 ))
            continue
        fi
        if [ $nav_proceed -eq 1 ]; then
            break
        fi
        # If no navigation option was chosen, re-display the current page.
    done

    # Build a final selection list that contains corresponding $idx from $fidx.
    local -a final_selection=()
    local fidx idx
    for fidx in "${!global_selected[@]}"; do
        idx="${map_idx[$fidx]}"
        final_selection+=("$idx")
    done

    if [ ${#final_selection[@]} -eq 0 ]; then
        whiptail --title "No Selection" --msgbox "No notes selected for deletion." 10 40
        return 1
    fi

    # Construct a confirmation message.
    local msg="The following notes will be deleted:\n"
    local c_msg="There are following conflicts for project "
    local conflicted=0 proj_found=0
    for idx in "${final_selection[@]}"; do
        # Truncate note path
        note_path=$(cut -d'|' -f2 <<< "${lines[$idx]}")

        # FIX. IF CONFLICT THEN BUILD ERROR MSG.
        local proj_path 
        if ! proj_path="$(note_safe_to_delete "$note_path")"; then
            if [[ -n "$proj_path" ]]; then
                ((proj_found == 0)) && c_msg+="'${proj_path}':\n\n"

                conflicted=1
                proj_found=1
                c_msg+="Has associated note $note_path.\n"
                continue
            fi
        fi

        local dir_tr filename_tr note_path_tr
        dir_tr="$(dirname "$note_path")"
        dir_tr="$(truncate_dirname "$dir_tr" 50)"
        filename_tr="$(basename "$note_path")"
        filename_tr="$(truncate_filename "$filename_tr" 50)"
        note_path_tr="${dir_tr}/${filename_tr}" 

        msg+="${note_path_tr}\n"
    done

    # If conflicts, alert user then return from function.
    c_msg+="\nPlease dissociate these notes from project first!"
    ((conflicted == 1)) && {
	whiptail --scrolltext --title "Attention" --msgbox "$c_msg" 20 80
	return 1
    }

    # Confirm deletion.
    if whiptail --title "Confirm Deletion" --yesno "$msg" 20 78; then
        # Sort the indices in descending order to safely delete from the file.
        local -a sorted
        sorted=($(for i in "${final_selection[@]}"; do echo "$i"; done | sort -nr))
        for idx in "${sorted[@]}"; do
            local line_num=$(( idx + 1 ))

            # actual file deletion.
            local note_path="$(sed -n "${line_num}p" "$NOTES_DB" | cut -d'|' -f2)"

            if [[ -f "$note_path" ]]; then
                rm "$note_path"
                #echo "Deleted file: $note_path" >&2
            else
                :
                #echo "File not found: $note_path" >&2
            fi            

            # remove from database.
            sed -i "${line_num}d" "$NOTES_DB"            
        done
        whiptail --title "Deletion Complete" --msgbox "Selected notes have been deleted." 10 40
    else
        whiptail --title "Cancelled" --msgbox "Deletion cancelled." 10 40
    fi
}

delete_global_tag_of_notes() {
    # Check if tags database exists and isn't empty
    if [[ ! -f "$NOTES_TAGS_DB" || ! -s "$NOTES_TAGS_DB" ]]; then
        whiptail --msgbox "There are no registered tags." 10 50 >/dev/tty
        return 1
    fi

    # MAYBE DON'T NEED THIS.
    # Check if notes database exists and isn't empty
    # if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
	# whiptail --msgbox "There are no registered notes." 10 50 >/dev/tty
	# return 1
    # fi

    # FIX: PAGINATE SELECTED_TAG.
    # Read all tags into an array
    mapfile -t all_tags < "$NOTES_TAGS_DB"
    local current_page=0
    local tags_per_page=20

    while true; do
        # Calculate start and end indices for current page
        local start=$((current_page * tags_per_page))
        local end=$((start + tags_per_page - 1))
        
        # Get tags for current page
        local page_tags=("${all_tags[@]:$start:$tags_per_page}")

        # Prepare whiptail menu options
        local menu_options=()
        for tag in "${page_tags[@]}"; do
            menu_options+=("$tag" "")
        done

        # Add navigation options if needed
        if [[ $start -gt 0 ]]; then
            menu_options+=("< Previous Page" "")
        fi
        if [[ $end -lt $((${#all_tags[@]} - 1)) ]]; then
            menu_options+=("> Next Page" "")
        fi

        # Show tag selection menu
        local selected_tag
        selected_tag=$(whiptail --menu "Choose a tag to delete (Page $((current_page + 1))/$(( (${#all_tags[@]} + tags_per_page - 1) / tags_per_page )))" \
            25 100 15 "${menu_options[@]}" 3>&1 1>&2 2>&3 >/dev/tty)
        
        [[ $? -ne 0 ]] && return 1  # User canceled

        # Handle navigation
        if [[ "$selected_tag" == "< Previous Page" ]]; then
            ((current_page--))
            continue
        elif [[ "$selected_tag" == "> Next Page" ]]; then
            ((current_page++))
            continue
        else
            # User selected a tag to delete
            # Add your tag deletion logic here
            #whiptail --msgbox "Selected tag for deletion: $selected_tag" 10 50 >/dev/tty
            break
        fi
    done
    # END FIX.

#    # Read all tags into an array
#    mapfile -t tags < "$NOTES_TAGS_DB"
#
#    # Prepare whiptail menu options
#    local menu_options=()
#    for tag in "${tags[@]}"; do
#        menu_options+=("$tag" "")
#    done
#
#    # Show tag selection menu
#    local selected_tag
#    selected_tag=$(whiptail --menu "Choose a note tag to delete from global list." 20 50 10 "${menu_options[@]}" 3>&1 1>&2 2>&3 >/dev/tty)
#    [[ $? -ne 0 ]] && return  # User canceled

    # Check for conflicting notes
    local conflicts=()
    if [[ -f "$NOTES_DB" ]]; then
        while IFS='|' read -r note_title _ note_tags _; do
            IFS=',' read -ra tags_arr <<< "$note_tags"
            for t in "${tags_arr[@]}"; do
                if [[ "$t" == "$selected_tag" ]]; then
                    conflicts+=("$note_title")
                    break
                fi
            done
        done < "$NOTES_DB"
    fi

    # Handle conflicts or delete tag
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        local conflict_msg="Cannot delete tag '$selected_tag' due to conflicts in:\n"
        for title in "${conflicts[@]}"; do
            conflict_msg+="- $title\n"
        done
        conflict_msg+="\nPlease dissociate the tag from these notes first."
        whiptail --msgbox "$conflict_msg" 20 50
    else
	# Confirm before deletion
	whiptail --title "Confirm Deletion" \
        --yesno "Are you sure you want to delete tag '$selected_tag' from the global list?" 10 60 \
	|| return 1

        # Remove tag from tags database
        local temp_file=$(mktemp)
        grep -vFx "$selected_tag" "$NOTES_TAGS_DB" > "$temp_file"
        mv "$temp_file" "$NOTES_TAGS_DB"
        whiptail --msgbox "Note tag '$selected_tag' has been successfully deleted from global list." 10 50
    fi
}

URLS_DB="$(pwd)/urls/urls.db"
mkdir -p "$(pwd)/urls"

# Line format for URLS_DB is:
#/path/to/note/some note.txt${GS}https://some url/url.html${US}url title${RS}https://some other/url2.html${US}other url title

assoc_url_to_note() {
    show_tag_menu() {
        local TAG_OPTIONS__=("$@")  # Expect pairs: tag, ""
        local PAGE_SIZE=10
        local page=0
        local total_items=$(( ${#TAG_OPTIONS__[@]} / 2 ))
        local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
        local selected_tag__=""
        local choice start end menu_items

        while true; do
            start=$(( page * PAGE_SIZE * 2 ))
            end=$(( start + PAGE_SIZE * 2 ))
            menu_items=("${TAG_OPTIONS__[@]:$start:$((PAGE_SIZE * 2))}")

            # Add navigation items
            if (( page > 0 )); then
                menu_items+=("<< Previous Page" "")
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=("Next Page >>" "")
            fi

            choice=$(whiptail --title "Filter by Tag (Page $((page + 1))/$total_pages)" \
                            --menu "Choose a tag to find linked notes:" 20 60 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3)

            # Handle user action
            exit_status=$?
            if [[ $exit_status -ne 0 ]]; then
                # User pressed Cancel or Esc
                return 1
            fi

            case "$choice" in
                "Next Page >>")
                    ((page++))
                    ;;
                "<< Previous Page")
                    ((page--))
                    ;;
                *)
                    selected_tag__="$choice"
                    break
                    ;;
            esac
        done

        echo "$selected_tag__"
    }

    touch "$URLS_DB"
	
    #local NOTES_DB="$NOTES_DB"
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls

    # Extract note paths from NOTES_DB
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 >/dev/tty
        return 1
    fi

#    # Read note paths
#    local note_paths=()
#    while IFS='|' read -r _ path _ _; do
#        note_paths+=("$path")
#    done < "$NOTES_DB"
#
#    if [[ ${#note_paths[@]} -eq 0 ]]; then
#        whiptail --msgbox "No notes found in database!" 8 50 >/dev/tty
#        return 1
#    fi
#
#    # Select note path
#    local menu_items=()
#    for path in "${note_paths[@]}"; do
#        menu_items+=("$path" "")
#    done

    # FIX: POPULATE LINES BY LETTING USER SELECT TAG FIRST.
    # Read all tags into a bash array for whiptail menu
    local -a tags lines

    mapfile -t tags < "$NOTES_TAGS_DB"

    if [[ "${#tags[@]}" -eq 0 ]]; then
        mapfile -t lines < "$NOTES_DB"
    else
        # Build tag options for whiptail (needs tag and description pairs)
        local TAG_OPTIONS=()
        TAG_OPTIONS+=("ANY TAG" "")
        for tag in "${tags[@]}"; do
            TAG_OPTIONS+=("$tag" "")
        done

        # ADDITIONAL FIX: PAGINATE SELECT TAG.
        local selected_tag=$(show_tag_menu "${TAG_OPTIONS[@]}")

        # # Show menu and let user choose a tag
        # local selected_tag
        # selected_tag=$(whiptail --title "Filter by Tag" \
        #                         --menu "Choose a tag to find linked notes:" 20 60 10 \
        #                         "${TAG_OPTIONS[@]}" \
        #                         3>&1 1>&2 2>&3) || return 1

        if [[ "$selected_tag" == "ANY TAG" ]]; then
            mapfile -t lines < "$NOTES_DB"
        else
            # Populate array with lines that have exact match for selected tag
            mapfile -t lines < <(awk -F'|' -v tag="$selected_tag" '      
                {
                    n = split($3, tags, ",")
                    for (i = 1; i <= n; i++) {
                        if (tags[i] == tag) {
                            print $0
                            next
                        }
                    }
                }' "$NOTES_DB")
        fi
    fi
    # END FIX.    

    # local lines=()
    # while IFS= read -r line; do
    #     lines+=("$line")
    # done < "$NOTES_DB"

    if [[ ${#lines[@]} -eq 0 ]]; then
        [[ -n "$selected_tag" ]] && whiptail --msgbox "No matching notes for tag '${selected_tag}'." 8 50 >/dev/tty
        # echo ""
        return 1
    fi    

    # FIX TO ADD TAGS TO MENU_ITEMS
    # Read note paths
    local menu_items=()
    while IFS='|' read -r _ path tags _; do
        menu_items+=("$path" "[${tags}]")
    done < <(printf '%s\n' "${lines[@]}")

    if [[ ${#menu_items[@]} -eq 0 ]]; then
        whiptail --msgbox "No notes found in database!" 8 50 >/dev/tty
        return 1
    fi

    # Paginate instead
    ! paginate_get_notes "Select Note to Associate URL to" "${menu_items[@]}" && return 1
    local selected_path
    selected_path="$SELECTED_ITEM"
    [[ -z "$selected_path" ]] && return 1

    #local selected_path
    #selected_path=$(whiptail --menu "Select a note" 20 150 10 "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    #[[ -z "$selected_path" ]] && return 1

    # Load existing URLs
    local urls=()
    local titles=()
    if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"
    fi

    local url_regex='^(https?:\/\/)?(www\.)?([a-zA-Z0-9-]+\.)+[A-Za-z]{2,}(:[0-9]+)?(\/\S*)?$'

    # URL management loop
    while true; do
        local menu_options=("Register URL" "" "Save and return" "")
        for i in "${!urls[@]}"; do
            menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
        done

        local choice
        choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 170 10 "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        [[ -z "$choice" ]] && return 1

        case "$choice" in
            "Register URL")
                local new_url new_title
                new_url=$(whiptail --inputbox "Enter URL:" 8 50 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue

		# validate URL
		if [[ ! $new_url =~ $url_regex ]]; then
		    whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
		    continue
		fi

                new_title=$(whiptail --inputbox "Enter URL title:" 8 50 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue

                if [[ -z "$new_url" || -z "$new_title" ]]; then
                    whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                    continue
                fi

                urls+=("$new_url")
                titles+=("$new_title")
                ;;

            "Save and return")
                # Construct new entry
                local new_entry="${selected_path}${GS}"
                for i in "${!urls[@]}"; do
                    new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                done
                new_entry="${new_entry%$RS}"

                # Update URLS_DB
                local temp_file
                temp_file=$(mktemp) || return 1
                if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
					# Write every line except for selected path to temp file.
                    while IFS= read -r line; do
                        [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                    done < "$URLS_DB" > "$temp_file"
                fi
                # Add new entry at the end of the temp file.
                echo "$new_entry" >> "$temp_file"

                # Replace original file
                mv "$temp_file" "$URLS_DB"
                whiptail --msgbox "URL associations saved successfully!" 8 50 >/dev/tty
                return 0
                ;;

            *)
                # Handle existing URL selection
                local index="$choice"
                if [[ ! -v urls[index] ]]; then
                    whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                    continue
                fi

                # Submenu for edit/delete
                local sub_choice
                sub_choice=$(whiptail --menu "Manage URL" 20 60 10 \
                    "Change values" "" \
                    "Delete URL" "" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                [[ -z "$sub_choice" ]] && continue

                case "$sub_choice" in
                    "Change values")
                        local current_url="${urls[index]}"
                        local current_title="${titles[index]}"
                        new_url=$(whiptail --inputbox "Edit URL:" 8 50 "$current_url" 3>&1 1>&2 2>&3)
                        [[ $? -ne 0 ]] && continue

			# validate URL
                        if [[ ! $new_url =~ $url_regex ]]; then
                            whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
                            continue
                        fi

                        new_title=$(whiptail --inputbox "Edit URL title:" 8 50 "$current_title" 3>&1 1>&2 2>&3)
                        [[ $? -ne 0 ]] && continue

                        if [[ -z "$new_url" || -z "$new_title" ]]; then
                            whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                            continue
                        fi

                        urls[index]="$new_url"
                        titles[index]="$new_title"
                        ;;
                    "Delete URL")
                        unset 'urls[index]'
                        unset 'titles[index]'
                        # Reindex arrays
                        urls=("${urls[@]}")
                        titles=("${titles[@]}")
                        ;;
                esac
                ;;
        esac
    done
}

dissoc_url_from_note() {
    # SUB FUNCTION FOR PAGINATE SELECT TAG.
    show_tag_menu() {
        local TAG_OPTIONS__=("$@")  # Expect pairs: tag, ""
        local PAGE_SIZE=10
        local page=0
        local total_items=$(( ${#TAG_OPTIONS__[@]} / 2 ))
        local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
        local selected_tag__=""
        local choice start end menu_items

        while true; do
            start=$(( page * PAGE_SIZE * 2 ))
            end=$(( start + PAGE_SIZE * 2 ))
            menu_items=("${TAG_OPTIONS__[@]:$start:$((PAGE_SIZE * 2))}")

            # Add navigation items
            if (( page > 0 )); then
                menu_items+=("<< Previous Page" "")
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=("Next Page >>" "")
            fi

            choice=$(whiptail --title "Filter by Tag (Page $((page + 1))/$total_pages)" \
                            --menu "Choose a tag to find linked notes:" 20 60 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3)

            # Handle user action
            exit_status=$?
            if [[ $exit_status -ne 0 ]]; then
                # User pressed Cancel or Esc
                return 1
            fi

            case "$choice" in
                "Next Page >>")
                    ((page++))
                    ;;
                "<< Previous Page")
                    ((page--))
                    ;;
                *)
                    selected_tag__="$choice"
                    break
                    ;;
            esac
        done

        echo "$selected_tag__"
    }

    touch "$URLS_DB"
	
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls

    # Check URL database existence
    if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
        whiptail --msgbox "No associated URLs found. Associate at least one URL and try again." 8 40 >/dev/tty
        return 1
    fi

    # FIX: ASK FOR TAG FIRST.
    local -a tags
    mapfile -t tags < "$NOTES_TAGS_DB"    
    # Build tag options for whiptail (needs tag and description pairs)
    local TAG_OPTIONS=()
    TAG_OPTIONS+=("ANY TAG" "")
    for tag in "${tags[@]}"; do
        TAG_OPTIONS+=("$tag" "")
    done

    # ADDITIONAL FIX: PAGINATE SELECT TAG.
    local selected_tag=$(show_tag_menu "${TAG_OPTIONS[@]}")

    # Extract unique note paths from URLS_DB
    local note_paths=()
    while IFS= read -r line; do
        note_path="${line%%$GS*}"
        [[ -n "$note_path" ]] && note_paths+=("$note_path")
    done < <(awk -F"$GS" '!seen[$1]++' "$URLS_DB")

    if [[ ${#note_paths[@]} -eq 0 ]]; then
        whiptail --msgbox "No notes with URLs found in database!" 8 50 >/dev/tty
        return 1
    fi

    # Select note path
    local menu_items=()
    local tags__		# FIX: display tags too!
    for path in "${note_paths[@]}"; do
        #menu_items+=("$path" "")

        tags__=$(awk -F'|' -v target="$path" '$2 == target { print $3 }' "$NOTES_DB")

        # FIX: FILTER BY SELECTED TAG.
        local tag_array=()
        IFS=',' read -r -a tag_array <<< "$tags__"

        for tag in "${tag_array[@]}"; do
            if [[ "$tag" == "$selected_tag" || "$selected_tag" == "ANY TAG" ]]; then
                menu_items+=("$path" "[${tags__}]")
                break  # optional: stop after first match
            fi
        done
        # don't need it any more.
        #menu_items+=("$path" "[${tags__}]")
    done

    # fix for cancel or tag with no notes.
    [[ -n "$selected_tag" ]] && [[ "${#menu_items}" -eq 0 ]] && whiptail --msgbox "No matching notes for tag '${selected_tag}'." 8 60 >/dev/tty

    # Paginate instead!
    ! paginate_get_notes "Select Note to Dissociate URL" "${menu_items[@]}" && return 1
    local selected_path
    selected_path="$SELECTED_ITEM"
    [[ -z "$selected_path" ]] && return 1

    #local selected_path
    #selected_path=$(whiptail --menu "Select a note to dissociate URLs" 20 150 10 \
    #    "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    #[[ -z "$selected_path" ]] && return 1

    # Load existing URLs
    local urls=()
    local titles=()
    while IFS= read -r line; do
        if [[ "$line" == "${selected_path}${GS}"* ]]; then
            IFS="$RS" read -ra entries <<< "${line#*$GS}"
            for entry in "${entries[@]}"; do
                IFS="$US" read -r url title <<< "$entry"
                urls+=("$url")
                titles+=("$title")
            done
            break
        fi
    done < "$URLS_DB"

    # URL removal loop
    while true; do
        local menu_options=("Remove URL" "" "Save and return" "")
        for i in "${!urls[@]}"; do
            menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
        done

        local choice
        choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 170 10 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        [[ -z "$choice" ]] && continue

        case "$choice" in
            "Remove URL")
                if [[ ${#urls[@]} -eq 0 ]]; then
                    whiptail --msgbox "No URLs to remove!" 8 50 >/dev/tty
                    continue
                fi

                # Create removal submenu
                local remove_menu=()
                for i in "${!urls[@]}"; do
                    remove_menu+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                done

                local remove_index
                remove_index=$(whiptail --menu "Select URL to remove" 20 170 10 \
                    "${remove_menu[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                [[ -z "$remove_index" ]] && continue

                # Validate and remove selected URL
                if [[ -v "urls[$remove_index]" ]]; then
                    unset 'urls[$remove_index]'
                    unset 'titles[$remove_index]'
                    urls=("${urls[@]}")  # Reindex array
                    titles=("${titles[@]}")
                else
                    whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                fi
                ;;

            "Save and return")
                # Prepare new entry
                local new_entry="${selected_path}${GS}"
                for i in "${!urls[@]}"; do
                    new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                done
                new_entry="${new_entry%$RS}"

                # Update database
                local temp_file=$(mktemp) || return 1
                {
                    # Copy existing entries except current note
                    while IFS= read -r line; do
                        [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                    done < "$URLS_DB"
                    
                    # Add updated entry if URLs remain
                    [[ -n "$new_entry" ]] && echo "$new_entry"
                } > "$temp_file"

                mv "$temp_file" "$URLS_DB"
                whiptail --msgbox "URL associations updated!" 8 50 >/dev/tty
                return 0
                ;;

            *)
                # Ignore URL index selections
                continue
                ;;
        esac
    done
}

#URL_BROWSER='google-chrome'

open_url_assoc_to_note() {
    # SUB FUNCTION FOR PAGINATE SELECT TAG.
    show_tag_menu() {
        local TAG_OPTIONS__=("$@")  # Expect pairs: tag, ""
        local PAGE_SIZE=10
        local page=0
        local total_items=$(( ${#TAG_OPTIONS__[@]} / 2 ))
        local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
        local selected_tag__=""
        local choice start end menu_items

        while true; do
            start=$(( page * PAGE_SIZE * 2 ))
            end=$(( start + PAGE_SIZE * 2 ))
            menu_items=("${TAG_OPTIONS__[@]:$start:$((PAGE_SIZE * 2))}")

            # Add navigation items
            if (( page > 0 )); then
                menu_items+=("<< Previous Page" "")
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=("Next Page >>" "")
            fi

            choice=$(whiptail --title "Filter by Tag (Page $((page + 1))/$total_pages)" \
                            --menu "Choose a tag to find linked notes:" 20 60 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3)

            # Handle user action
            exit_status=$?
            if [[ $exit_status -ne 0 ]]; then
                # User pressed Cancel or Esc
                return 1
            fi

            case "$choice" in
                "Next Page >>")
                    ((page++))
                    ;;
                "<< Previous Page")
                    ((page--))
                    ;;
                *)
                    selected_tag__="$choice"
                    break
                    ;;
            esac
        done

        echo "$selected_tag__"
    }

    touch "$URLS_DB"
	
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls            

    # Check if URLs database exists
    if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
        whiptail --msgbox "No associated URLs found. Associate at least one URL and try again." 8 40 >/dev/tty
        return 1
    fi

    # FIX: ASK FOR TAG FIRST.
    local -a tags
    mapfile -t tags < "$NOTES_TAGS_DB"    
    # Build tag options for whiptail (needs tag and description pairs)
    local TAG_OPTIONS=()
    TAG_OPTIONS+=("ANY TAG" "")
    for tag in "${tags[@]}"; do
        TAG_OPTIONS+=("$tag" "")
    done

    # ADDITIONAL FIX: PAGINATE SELECT TAG.
    local selected_tag=$(show_tag_menu "${TAG_OPTIONS[@]}")

    while true; do
        # Extract unique note paths
        local note_paths=()
        while IFS= read -r line; do
            path="${line%%$GS*}"
            [[ -n "$path" ]] && note_paths+=("$path")
        done < <(awk -F"$GS" '!seen[$1]++' "$URLS_DB")

        if [[ ${#note_paths[@]} -eq 0 ]]; then
            whiptail --msgbox "No notes with URLs found!" 8 50 >/dev/tty
            return 1
        fi

        # Select note path
        local menu_items=("<< Return" "")
	    local tags__		# FIX: display tags too!
        for path in "${note_paths[@]}"; do
	        tags__=$(awk -F'|' -v target="$path" '$2 == target { print $3 }' "$NOTES_DB")

            # FIX: FILTER BY SELECTED TAG.
            local tag_array=()
            IFS=',' read -r -a tag_array <<< "$tags__"

            for tag in "${tag_array[@]}"; do
                if [[ "$tag" == "$selected_tag" || "$selected_tag" == "ANY TAG" ]]; then
                    menu_items+=("$path" "[${tags__}]")
                    break  # optional: stop after first match
                fi
            done

            #menu_items+=("$path" "[${tags__}]")
        done

        # Paginate instead!
        ! paginate_get_notes "Select Note to Open URL" "${menu_items[@]}" && return 1
        local selected_path
        selected_path="$SELECTED_ITEM"
        [[ -z "$selected_path" ]] && return 1

        #local selected_path
        #selected_path=$(whiptail --title "Select Note" --menu "Choose a note to open URLs:" \
        #    20 150 10 "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return 1
        #[[ -z "$selected_path" ]] && return 1
        
        # Handle return option
        if [[ "$selected_path" == "<< Return" ]]; then
            return 0
        fi

        # Extract URLs for selected note
        local urls=()
        local titles=()
        while IFS= read -r line; do
			# Only for the matched line...
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"

        if [[ ${#urls[@]} -eq 0 ]]; then
            whiptail --msgbox "No URLs found for selected note!" 8 50 >/dev/tty
            continue
        fi

        # URL selection loop
        while true; do
            local url_menu_items=("<< Back" "")
            for i in "${!urls[@]}"; do
                url_menu_items+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --title "URLs for $selected_path" --menu "Choose URL to open:" \
                20 170 10 "${url_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || break
            [[ -z "$choice" ]] && break

            if [[ "$choice" == "<< Back" ]]; then
                break
            elif [[ -n "${urls[$choice]}" ]]; then
                #eval "$URL_BROWSER" "'${urls[$choice]}'" >/dev/null 2>&1 &
                nohup "$URL_BROWSER" "${urls[$choice]}" >/dev/null 2>&1 &	# to make sure browser stays open
            fi
        done
    done
}

# allows print note files from main manage notes menu.
print_notes() {
    # SUB FUNCTION FOR PAGINATE SELECT TAG.
    show_tag_menu_for_print() {
        local TAG_OPTIONS__=("$@")  # Expect pairs: tag, ""
        local PAGE_SIZE=10
        local page=0
        local total_items=$(( ${#TAG_OPTIONS__[@]} / 2 ))
        local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
        local selected_tag__=""
        local choice start end menu_items

        while true; do
            start=$(( page * PAGE_SIZE * 2 ))
            end=$(( start + PAGE_SIZE * 2 ))
            menu_items=("${TAG_OPTIONS__[@]:$start:$((PAGE_SIZE * 2))}")

            # Add navigation items
            if (( page > 0 )); then
                menu_items+=("<< Previous Page" "")
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=("Next Page >>" "")
            fi

            choice=$(whiptail --title "Filter by Tag (Page $((page + 1))/$total_pages)" \
                            --menu "Choose a tag to find notes to print:" 20 60 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3)

            # Handle user action
            exit_status=$?
            if [[ $exit_status -ne 0 ]]; then
                # User pressed Cancel or Esc
                return 1
            fi

            case "$choice" in
                "Next Page >>")
                    ((page++))
                    ;;
                "<< Previous Page")
                    ((page--))
                    ;;
                *)
                    selected_tag__="$choice"
                    break
                    ;;
            esac
        done

        echo "$selected_tag__"
    }

    print_file_from_print_notes() {
        # Check if file argument is provided
        if [ -z "$1" ]; then
            return 1
        fi

        local file_to_print="$1"

        # Check if file exists
        if [ ! -f "$file_to_print" ]; then
            echo "Error: File '$file_to_print' does not exist." >&2
            return 1
        fi

        # Get list of printers
        local printers
        printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')

        # Edge case: no printers found.
        [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

        # Convert printer list into whiptail menu format
        local menu_items=()
        for p in $printers; do
            menu_items+=("$p" "")
        done

        # Show whiptail menu to select printer
        local selected_printer
        selected_printer=$(whiptail --title "Select Printer" \
            --menu "Choose a printer:" 20 60 10 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3)

        # Check if user cancelled
        if [ $? -ne 0 ]; then
            return 1
        fi

        # Print the file
        if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
            lpr -P "$selected_printer" "$file_to_print"
            if [ $? -eq 0 ]; then
                whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
            else
                whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                return 1
            fi            
        else
            :  # do nothing if No or Cancel
        fi
    }

    get_note_title_from_note_path_() {
        local note_path="$1"
        local note_title

        note_title=$(awk -F'|' -v path="$note_path" '
            $2 == path {
                print $1
                exit
            }
        ' "$NOTES_DB")

        echo "$note_title"
    }

    local db_file="$NOTES_DB"
    [[ ! -f "$db_file" || ! -s "$db_file" ]] && {
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    # FIX: POPULATE LINES BY LETTING USER SELECT TAG FIRST.
    # Read all tags into a bash array for whiptail menu
    local -a tags lines

    mapfile -t tags < "$NOTES_TAGS_DB"

    if [[ "${#tags[@]}" -eq 0 ]]; then
        mapfile -t lines < "$NOTES_DB"
    else
        # Build tag options for whiptail (needs tag and description pairs)
        local TAG_OPTIONS=()
        TAG_OPTIONS+=("ANY TAG" "")
        for tag in "${tags[@]}"; do
            TAG_OPTIONS+=("$tag" "")
        done

        # ADDITIONAL FIX: PAGINATE SELECT TAG.
        local selected_tag=$(show_tag_menu_for_print "${TAG_OPTIONS[@]}")

        if [[ "$selected_tag" == "ANY TAG" ]]; then
            mapfile -t lines < "$NOTES_DB"
        else
            # Populate array with lines that have exact match for selected tag
            mapfile -t lines < <(awk -F'|' -v tag="$selected_tag" '      
                {
                    n = split($3, tags, ",")
                    for (i = 1; i <= n; i++) {
                        if (tags[i] == tag) {
                            print $0
                            next
                        }
                    }
                }' "$NOTES_DB")
        fi
    fi
    # END FIX.    

    if [[ ${#lines[@]} -eq 0 ]]; then
        [[ -n "$selected_tag" ]] && whiptail --msgbox "No matching notes for tag '${selected_tag}'." 8 50 >/dev/tty
        # echo ""
        return 1
    fi        

    while true; do
        # Reset arrays and index for fresh load each iteration
        local -a menu_entries=()
        local -a MENU_PATH_ENTRIES=()
        local idx=1

        # Load current database state
        while IFS='|' read -r title path tags _; do
            # Truncate long title
            title_tr="${title:0:50}"

            local tag_display=""
            [ -n "$tags" ] && tag_display=" [${tags}]"
            menu_entries+=("${idx}:${title_tr}" "${tag_display}")
            MENU_PATH_ENTRIES+=("$path" "")
            ((idx++))
        done < <(printf '%s\n' "${lines[@]}")

        [ ${#menu_entries[@]} -eq 0 ] && {
            whiptail --msgbox "No notes found in database." 8 40
            return 1
        }

        # Paginate menu entries instead.
        CURRENT_PAGE=0
        SELECTED_ITEM=""

        ! paginate_get_notes "Print Note" "${menu_entries[@]}" && break

        local selected_idx="$SELECTED_ITEM"

        # If user cancels out of paginate menu then SELECTED_ITEM is empty.
        [ -z "selected_idx" ] && break

        # Process selection
        selected_idx="$(echo "$selected_idx" | cut -d':' -f1)"
        local m=$((2 * selected_idx - 1))
        local array_index=$((m - 1))
        local selected_path="${MENU_PATH_ENTRIES[$array_index]}"
        
        local action
        action=$(whiptail --title "Actions" --menu "Choose an action:" 10 40 2 \
                "View Note" "" \
                "Print Note" "" \
                3>&1 1>&2 2>&3) || :        

        case "$action" in
            "View Note")
                DIALOG_CONFIG="use_colors = ON
                screen_color = (BLACK,MAGENTA,OFF)
                dialog_color = (BLACK,WHITE,OFF)
                title_color = (RED,WHITE,OFF)
                border_color = (WHITE,WHITE,OFF)
                button_active_color = (WHITE,RED,OFF)"                                    

                local tmpfile
                tmpfile=$(mktemp)
                fold -s -w 145 "$selected_path" > "$tmpfile"
                # NOTE: NOTE_TITLE IS NOT EXTRACTED YET! -- FIXED?
                local note_title="$(get_note_title_from_note_path_ "$selected_path")"
                DIALOGRC=<(echo -e "$DIALOG_CONFIG") dialog --no-mouse --exit-label "Back" --title "$note_title" --textbox "$tmpfile" 35 150                
                rm -f "$tmpfile"
                clear
                ;;
            "Print Note")
                print_file_from_print_notes "$selected_path"
                ;;
            *)
                :
                ;;

        esac        
    done
}

add_note_tag_main() {
    local new_tag
    new_tag=$(whiptail --title "Add New Note Tag" --inputbox "Enter new tag:" 8 40 3>&1 1>&2 2>&3 </dev/tty) || return 1

    # ANY TAG is banned word - ban it case-insensitive?
    [[ "$new_tag" == "ANY TAG" ]] && whiptail --title "Invalid Tag" --msgbox "'ANY TAG' is not allowed as a tag name. Try again." 8 40 && return 1

    # FIX: DELETE BANNED CHARS - MORE EFFICIENT.
    new_tag=${new_tag//[|,#:;]/}
    # END FIX.

    if [ -n "$new_tag" ]; then
        # FIX: CHECK FOR DUPLICATE BEFORE ADDING TAG.
        # Check if tag already exists
        if grep -qiFx "$new_tag" "$NOTES_TAGS_DB"; then
            whiptail --msgbox "Tag '${new_tag}' already exists!" 8 40   # case-insensitive
            return 1
        else
            # Add to global tags list
            echo "$new_tag" >> "$NOTES_TAGS_DB"
            sort -u "$NOTES_TAGS_DB" -o "$NOTES_TAGS_DB"    # sort notes_tags_db file
            whiptail --msgbox "Tag '${new_tag}' has been added to notes tags db." 8 40
            return 0
        fi
    fi

    return 1
}

# Main menu function
manage_notes() {
    while true; do
        local option
        option=$(whiptail --title "Manage Notes" --cancel-button "Back" --menu "Choose an option:" 20 50 12 \
            "1" "Add Note" \
            "2" "Edit Note" \
            "3" "Print Note Using Printer" \
            "4" "Open Associated eBook" \
            "5" "Add New Note Tag" \
            "6" "Do Stuff by Tag" \
            "7" "Associate URL to Note" \
            "8" "Dissociate URL from Note" \
	        "9" "Open URL from Note" \
            "10" "Open an eBook From Global List" \
            "11" "Delete Notes" \
	        "12" "Delete Note Tag From Global List" 3>&1 1>&2 2>&3)

        # Exit the function if the user presses Esc or Cancel
        if [ $? -ne 0 ] || [ -z "$option" ]; then
            return
        fi

        case $option in
            1) add_note ;;
            2) list_notes ;;
            3) print_notes ;;
            4) open_note_ebook_page ;;
            5) add_note_tag_main ;;
            6) do_note_filter_by_tag ;;
            7) assoc_url_to_note ;;
            8) dissoc_url_from_note ;;
            9) open_url_assoc_to_note ;;
            10) open_ebook_note_from_global_list ;;
            11) delete_notes ;;
    	    12) delete_global_tag_of_notes ;;
            *) return ;;
        esac
    done
}

#########################################
# Manage Goals(Projects) code starts here
#########################################

PROJECTS_METADATA_DIR="$(pwd)/projects/metadata"
PROJECTS_DIR="$(pwd)/projects"
PROJECTS_DB="${PROJECTS_METADATA_DIR}/projects.db"

mkdir -p "$PROJECTS_METADATA_DIR" "$PROJECTS_DIR"
# FIX: start with empty projects db.
touch "$PROJECTS_DB"

# USAGE:
# mapfile -d '' -t filtered_lines < <(filter_projects_by_name)
filter_projects_by_name() {
    # Read the project database into an array
    local projects_lines
    readarray -t projects_lines < "$PROJECTS_DB"

    # Prompt user for a glob pattern
    local pattern
    pattern=$(whiptail --inputbox "Enter a glob pattern to filter projects (empty for wildcard):" 8 40 \
              --title "Project Filter" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1  # Exit if canceled

    # Set default pattern if empty
    : "${pattern:=*}"

    # Filter matching lines
    local filtered_lines=()
    local line title
    shopt -s nocasematch  # Enable case-insensitive matching
    for line in "${projects_lines[@]}"; do
        title="${line%%|*}"
        #[[ "$title" == $pattern ]] && filtered_lines+=("$line")    # doesn't seem to work if glob has spaces
        case "$title" in
            $pattern) filtered_lines+=("$line") ;;
        esac    
    done
    shopt -u nocasematch  # Disable case-insensitive matching (restore default)

    # DEBUG
    #echo "pattern:" >&2
    #echo "$pattern" >&2
    #echo "filtered_lines:" >&2
    #printf "%s\n" "${filtered_lines[@]}" >&2

    # Output null-delimited results
    (( ${#filtered_lines[@]} )) && printf "%s\0" "${filtered_lines[@]}" || {
        #whiptail --title "Alert" --msgbox "No matches found for pattern: '${pattern}'" 8 40 >/dev/tty  # we don't need this alert any more.
        return 1
    }
}

# DEBUG
#filter_projects_by_name
#exit 1

paginate_get_projects() {
    # Clear any previous selection
    SELECTED_ITEM_PROJECT=""

    local chunk_size=200

    # If new items are passed in, update FILTERED_EBOOKS and reset CURRENT_PAGE.
    # First arg is custom menu title.
    local menu_title
    if [ "$#" -gt 0 ]; then
        menu_title="$1"  # First argument is the title
        shift  # Shift to remove the title from the arguments
        FILTERED_PROJECTS=("$@")  # Remaining arguments are the items
        CURRENT_PAGE_PROJECTS=0
    fi

    # Set default title if menu_title is not provided.
    # But if menu_title is not privided as $1 then FILTERED_EBOOKS will be errorneous.
    : "${menu_title:=Paged Menu}"

    [[ ${#FILTERED_PROJECTS[@]} -eq 0 ]] && return 1

    local total_pages=$(( ( ${#FILTERED_PROJECTS[@]} + chunk_size - 1 ) / chunk_size ))
    # Ensure CURRENT_PAGE_PROJECTS is within valid bounds
    if (( CURRENT_PAGE_PROJECTS >= total_pages )); then
        CURRENT_PAGE_PROJECTS=$(( total_pages - 1 ))
    fi

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE_PROJECTS * chunk_size ))
        # Extract the current chunk
        local current_chunk=("${FILTERED_PROJECTS[@]:$start:$chunk_size}")
        local menu_options=()

        # Add navigation options if needed
        if (( CURRENT_PAGE_PROJECTS > 0 )); then
            menu_options+=("previous page" "")
        fi
        if (( CURRENT_PAGE_PROJECTS < total_pages - 1 )); then
            menu_options+=("next page" "")
        fi

        # Append the current page items
        menu_options+=("${current_chunk[@]}")

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "Choose an item (Page $((CURRENT_PAGE_PROJECTS + 1))/$total_pages)" \
            20 170 10 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        # Exit with code 1 if user cancels. Make sure to reset SELECTED_ITEM.
        if [ $? -ne 0 ]; then
            SELECTED_ITEM_PROJECT=""
            return 1
        fi

        case "$choice" in
            "previous page")
                (( CURRENT_PAGE_PROJECTS-- ))
                ;;
            "next page")
                (( CURRENT_PAGE_PROJECTS++ ))
                ;;
            *)
                # Return the index              
                SELECTED_ITEM_PROJECT="$choice"                
                return 0
                ;;
        esac
    done

    return 1
}

add_project() {
    local project_title=""
    local project_path=""
    local headings=()
    local indent_levels=()

    # Function to rebuild heading menu with visual indentation
    rebuild_heading_menu() {
        heading_menu=("Add new heading" "")
        for i in "${!headings[@]}"; do
            indent_spaces=$(( indent_levels[i] * 4 ))
            indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
            heading_menu+=("$i" "${indented_heading:0:130}")
        done
    }

    # Main project menu
    while true; do
		local project_action
        project_action=$(whiptail --menu "Project Configuration" 15 150 3 \
            "Project title" "Current: ${project_title:-<not set>}" \
            "Project path" "Status: ${project_path:-(will be generated)}" \
            "Proceed" "" 3>&1 1>&2 2>&3) || return 1

        case $project_action in
            "Project title")
		# FIX: FILTER BANNED CHAR |.
		local old_project_title
		old_project_title="$project_title" # save project title

                project_title=$(whiptail --inputbox "Enter project title" 8 78 "$project_title" 3>&1 1>&2 2>&3)

		# FIX: FILTER BANNED CHAR |.
		if [[ "$project_title" =~ \| ]]; then
			project_title="$old_project_title"	# Revert
			whiptail --title "Attention" --msgbox "Project title cannot contain | character." 8 40
			continue
		fi
		# END FIX.

                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title can't be empty." 8 45
                    continue
                }
                project_path="${PROJECTS_DIR}/${project_title}-$(date "+%d%m%Y-%H%M%S").txt"
                ;;
	    "Project path")
		continue
		;;
            "Proceed")
                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title is required." 8 45
                    continue
                }
                break
                ;;
            *) return 1 ;;
        esac
    done

    # Headings management
    while true; do
        rebuild_heading_menu
        local heading_action
        heading_action=$(whiptail --menu "Project: ${project_title}" 20 150 10 -- \
            "${heading_menu[@]}" "Save and return" "" 3>&1 1>&2 2>&3) || return 1

        case $heading_action in
            "Add new heading")
				local new_heading
                new_heading=$(whiptail --inputbox "Enter new heading:" 8 78 3>&1 1>&2 2>&3)
                if [[ -n "$new_heading" ]]; then
                    headings+=("$new_heading")
                    indent_levels+=(0)
                fi
                ;;
            "Save and return")
                break
                ;;
            *)
                if [[ "$heading_action" =~ ^[0-9]+$ ]]; then
                    local selected_index=$heading_action
                    local heading_operation
                    heading_operation=$(whiptail --menu "Heading Operations" 20 60 7 \
                        "Change text" "" \
                        "Move before" "" \
                        "Move after" "" \
                        "Indent left" "" \
                        "Indent right" "" \
                        "Remove heading" "" 3>&1 1>&2 2>&3)

                    case $heading_operation in
                        "Change text")
							local new_text
                            new_text=$(whiptail --inputbox "Enter new heading text:" 8 78 \
                                "${headings[$selected_index]}" 3>&1 1>&2 2>&3)
                            headings[$selected_index]="$new_text"
                            ;;
                        "Move before"|"Move after")
                            # LOGIC ERROR FIX: IF HEADINGS COUNT IS LESS THAN OR EQUAL TO ONE, CONTINUE.
                            [[ ${#headings[@]} -le 1 ]] && continue

                            # Get target position using indices
                            local targets=()
                            for i in "${!headings[@]}"; do
                                [[ $i -ne $selected_index ]] && {
                                    indent_spaces=$(( indent_levels[i] * 4 ))
                                    indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
                                    targets+=("$i" "$indented_heading")
                                }
                            done

							local target_index
                            target_index=$(whiptail --menu "Select target heading:" 20 150 10 \
                                "${targets[@]}" 3>&1 1>&2 2>&3)
                            [[ -z "$target_index" ]] && continue
                            target_index=$((target_index))

                            # Store original positions
                            local original_source_pos=$selected_index
                            local original_target_pos=$target_index
                            local moving_heading="${headings[$original_source_pos]}"
                            local moving_indent="${indent_levels[$original_source_pos]}"

                            # Remove source from original position
                            headings=(
                                "${headings[@]:0:$original_source_pos}"
                                "${headings[@]:$((original_source_pos+1))}"
                            )
                            indent_levels=(
                                "${indent_levels[@]:0:$original_source_pos}"
                                "${indent_levels[@]:$((original_source_pos+1))}"
                            )

                            # Adjust target index for new array
                            if (( original_source_pos < original_target_pos )); then
                                adjusted_target_pos=$((original_target_pos - 1))
                            else
                                adjusted_target_pos=$original_target_pos
                            fi

                            # Apply "Move after" adjustment
                            if [[ "$heading_operation" == "Move after" ]]; then
                                ((adjusted_target_pos++))
                            fi

                            # Insert at new position
                            headings=(
                                "${headings[@]:0:$adjusted_target_pos}"
                                "$moving_heading"
                                "${headings[@]:$adjusted_target_pos}"
                            )
                            indent_levels=(
                                "${indent_levels[@]:0:$adjusted_target_pos}"
                                "$moving_indent"
                                "${indent_levels[@]:$adjusted_target_pos}"
                            )
                            ;;                            
                        "Indent right")
                            (( indent_levels[$selected_index]++ ))
                            ;;
                        "Indent left")
                            (( indent_levels[$selected_index] = indent_levels[$selected_index] > 0 ? indent_levels[$selected_index]-1 : 0 ))
                            ;;
                        "Remove heading")
                            headings=("${headings[@]:0:$selected_index}" "${headings[@]:$((selected_index+1))}")
                            indent_levels=("${indent_levels[@]:0:$selected_index}" "${indent_levels[@]:$((selected_index+1))}")
                            ;;
                        *) ;;
                    esac
                fi
                ;;
        esac
    done

    # Save project file
    {
        for i in "${!headings[@]}"; do
            printf "%$((indent_levels[i]*4))s%s\n" "" "${headings[$i]}"
        done
    } > "$project_path"

    # Update projects database
    echo "${project_title}|${project_path}|" >> "$PROJECTS_DB"
}

edit_project() {
    # Check if projects database exists and has entries
    [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]] && {
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

#    # Read all projects into array
#    local lines=()
#    mapfile -t lines < "$PROJECTS_DB"
#
#    # Create selection menu
#    local menu_options=()
#    for index in "${!lines[@]}"; do
#        IFS='|' read -r title _ _ <<< "${lines[$index]}"
#        menu_options+=("$index" "$title")
#    done

    # FIX: ADD FILTERING
    # Read all projects into array
    local lines=()
    #mapfile -t lines < "$PROJECTS_DB"
    mapfile -d '' -t lines < <(filter_projects_by_name)		# get filtered lines from utility function. \0 delimited.

    # CRITICAL ERROR!!!
    # Instead of $index store matching index from $PROJECTS_DB file.
    # Create selection menu
    #local menu_options=()
    #for index in "${!lines[@]}"; do
    #    IFS='|' read -r title _ _ <<< "${lines[$index]}"
    #    menu_options+=("$index" "$title")
    #done

    local menu_options=()
    local title line lineno
    for line in "${lines[@]}"; do
        IFS='|' read -r title _ _ <<< "$line"
        lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1)

	# Store matching index from PROJECTS_DB file.
        [[ -n "$lineno" ]] && menu_options+=($((lineno-1)) "$title")
    done
    # END FIX.

    # Paginate menu options
    paginate_get_projects "Edit Project" "${menu_options[@]}"
    local selected_index
    selected_index="$SELECTED_ITEM_PROJECT"
    [[ -z "$selected_index" ]] && return 1

    # Let user select project
    #local selected_index
    #selected_index=$(whiptail --menu "Select a project to edit:" 20 150 10 \
    #    "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1

    # DIRTY FIX: OVERWRITE LINES TO CONTAIN ALL LINES FROM PROJECTS_DB.
    mapfile -t lines < "$PROJECTS_DB"

    # Parse selected project
    local old_title old_path old_notes
    IFS='|' read -r old_title old_path old_notes <<< "${lines[$selected_index]}"

    # Verify project file exists
    [[ ! -f "$old_path" ]] && {
        whiptail --msgbox "Project file not found: $old_path" 10 60
        return 1
    }

    # Dirty fix. $selected_index_file to point to the project file.
    local selected_index_file="$selected_index"

    # Load existing headings and indentation
    local headings=()
    local indent_levels=()
    # Read the selected project file line by line
    # and populate headings and indent_levels
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local spaces="${line%%[^ ]*}"
        local length=${#spaces}
        local indent=$(( length / 4 ))
        local heading="${line#$spaces}"
        headings+=("$heading")
        indent_levels+=("$indent")
    done < "$old_path"

    # Main project menu
    local project_title="$old_title"
    local project_path="$old_path"
    local new_title project_action
    while true; do
        project_action=$(whiptail --menu "Project Configuration" 15 150 3 \
            "Project title" "Current: ${project_title:-<not set>}" \
            "Project path" "Status: ${project_path}" \
            "Proceed" "" 3>&1 1>&2 2>&3) || return 1

        case "$project_action" in
            "Project title")
		# FIX: FILTER BANNED CHAR |.
		local old_project_title
		old_project_title="$project_title" # save project title

                new_title=$(whiptail --inputbox "Enter project title:" 8 78 \
                    "$project_title" 3>&1 1>&2 2>&3)

		# FIX: FILTER BANNED CHAR |.
		if [[ "$new_title" =~ \| ]]; then
			project_title="$old_project_title"	# Revert
			whiptail --title "Attention" --msgbox "Project title cannot contain | character." 8 40
			continue
		fi
		# END FIX.

                if [[ -z "$new_title" ]]; then
                    whiptail --msgbox "Project title can't be empty." 8 45
                    continue
                fi
                project_title="$new_title"
                ;;
            "Project path")
				continue
				;;
            "Proceed")
                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title is required." 8 45
                    continue
                }
                break
                ;;
            *) return 1 ;;            
        esac
    done

    # Headings management
    local heading_menu
    rebuild_heading_menu() {
        heading_menu=("Add new heading" "")
        for i in "${!headings[@]}"; do
            indent_spaces=$(( indent_levels[i] * 4 ))
            indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
            heading_menu+=("$i" "${indented_heading:0:130}")
        done
    }

    while true; do
        rebuild_heading_menu
        local heading_action
        heading_action=$(whiptail --menu "Project: ${project_title}" 20 150 10 -- \
            "${heading_menu[@]}" "Save and return" "" 3>&1 1>&2 2>&3) || return 1

        case "$heading_action" in
            "Add new heading")
				local new_heading
                new_heading=$(whiptail --inputbox "Enter new heading:" 8 78 3>&1 1>&2 2>&3)
                [[ -n "$new_heading" ]] && {
                    headings+=("$new_heading")
                    indent_levels+=(0)
                }
                ;;
            "Save and return")
                break
                ;;
            *)
                if [[ "$heading_action" =~ ^[0-9]+$ ]]; then
                    local selected_index=$heading_action
                    local heading_operation
                    heading_operation=$(whiptail --menu "Heading Operations" 20 60 7 \
                        "Change text" "" \
                        "Move before" "" \
                        "Move after" "" \
                        "Indent left" "" \
                        "Indent right" "" \
                        "Remove heading" "" 3>&1 1>&2 2>&3)

                    case "$heading_operation" in
                        "Change text")
							local new_text
                            new_text=$(whiptail --inputbox "Enter new heading text:" 8 78 \
                                "${headings[$selected_index]}" 3>&1 1>&2 2>&3)
                            headings[$selected_index]="$new_text"	# what happens when new text is ""?
                            ;;
                        "Move before"|"Move after")
                            # LOGIC ERROR FIX: IF HEADINGS COUNT IS LESS THAN OR EQUAL TO ONE, CONTINUE.
                            [[ ${#headings[@]} -le 1 ]] && continue

                            local targets=()
                            for i in "${!headings[@]}"; do
                                [[ $i -ne $selected_index ]] && {
                                    indent_spaces=$(( indent_levels[i] * 4 ))
                                    indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
                                    targets+=("$i" "$indented_heading")
                                }
                            done

                            local target_index
                            target_index=$(whiptail --menu "Select target heading:" 20 150 10 \
                                "${targets[@]}" 3>&1 1>&2 2>&3)
                            [[ -z "$target_index" ]] && continue

                            local original_source_pos=$selected_index
                            local original_target_pos=$target_index
                            local moving_heading="${headings[$original_source_pos]}"
                            local moving_indent="${indent_levels[$original_source_pos]}"

                            # Remove source heading
                            headings=("${headings[@]:0:$original_source_pos}" 
                                "${headings[@]:$((original_source_pos+1))}")
                            indent_levels=("${indent_levels[@]:0:$original_source_pos}" 
                                "${indent_levels[@]:$((original_source_pos+1))}")

                            # Adjust target position
                            if (( original_source_pos < original_target_pos )); then
                                adjusted_target_pos=$((original_target_pos - 1))
                            else
                                adjusted_target_pos=$original_target_pos
                            fi

                            [[ "$heading_operation" == "Move after" ]] && ((adjusted_target_pos++))

                            # Insert at new position
                            headings=("${headings[@]:0:$adjusted_target_pos}" 
                                "$moving_heading" 
                                "${headings[@]:$adjusted_target_pos}")
                            indent_levels=("${indent_levels[@]:0:$adjusted_target_pos}" 
                                "$moving_indent" 
                                "${indent_levels[@]:$adjusted_target_pos}")
                            ;;
                        "Indent right")
                            (( indent_levels[$selected_index]++ ))
                            ;;
                        "Indent left")
                            (( indent_levels[$selected_index] = indent_levels[$selected_index] > 0 ? 
                                indent_levels[$selected_index]-1 : 0 ))
                            ;;
                        "Remove heading")
                            headings=("${headings[@]:0:$selected_index}" 
                                "${headings[@]:$((selected_index+1))}")
                            indent_levels=("${indent_levels[@]:0:$selected_index}" 
                                "${indent_levels[@]:$((selected_index+1))}")
                            ;;
                        *) ;;
                    esac
                fi
                ;;
        esac
    done

    # Save updated project file
    {
        for i in "${!headings[@]}"; do
            printf "%$((indent_levels[i]*4))s%s\n" "" "${headings[$i]}"
        done
    } > "$project_path"

    # Update projects database: Dirty fix here too.
    lines[$selected_index_file]="${project_title}|${project_path}|${old_notes}"
    printf "%s\n" "${lines[@]}" > "$PROJECTS_DB"
}

print_project() {
    #local line_num=0		# can't use this any more.
    local options=("<< Back" "")

    # Check if database file exists and is valid
    if [ ! -f "$PROJECTS_DB" ]; then
        whiptail --msgbox "Project database '$PROJECTS_DB' not found." 8 40 >/dev/tty
        return 1
    elif [ ! -s "$PROJECTS_DB" ]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    fi

    # FIX: ADD FILTER BY GLOBBING
    local line title path

    # Parse project entries
    local lineno
    while IFS= read -r -d '' line; do
        #((line_num++))
	lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1) || echo "No exact match for '$match' found." >&2 # use this instead!

        [ -z "$line" ] && continue

        IFS='|' read -r title path _ <<< "$line"
        if [ -z "$title" ] || [ -z "$path" ]; then
            whiptail --msgbox "Skipping invalid entry (line $line_num): Missing field(s)" 10 50 >/dev/tty
            continue
        fi
        options+=("$lineno" "$title")
    done < <(filter_projects_by_name)
    # END FIX.

    # if [ ${#options[@]} -eq 0 ]; then
    #     whiptail --msgbox "Error: No valid projects found in database." 10 50 >/dev/tty
    #     return 1
    # fi

    # Continuous selection loop added here
    while true; do
    	# Paginate options
        paginate_get_projects "View Project Content" "${options[@]}"
        local selected_line
        selected_line="$SELECTED_ITEM_PROJECT"
        [[ -z "$selected_line" || "$selected_line" == "<< Back" ]] && return 1

        # Show project selection menu
        #local selected_line
        #selected_line=$(whiptail --cancel-button "Back" --menu "Choose project to view content:" 20 150 10 "${options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        #[ $? -ne 0 ] && return 1  # Exit loop on cancel
        
        # Rest of the original processing logic
        local line_=$(sed -n "${selected_line}p" "$PROJECTS_DB")
        if [ -z "$line_" ]; then
            whiptail --msgbox "Error: Selected project no longer exists." 10 50 >/dev/tty
            return 1
        fi

        local title_ path_
        IFS='|' read -r title_ path_ _ <<< "$line_"

        if [ ! -e "$path_" ]; then
            whiptail --msgbox "Error: Project file '$path_' not found." 10 50 >/dev/tty
            return 1
        elif [ -d "$path_" ]; then
            whiptail --msgbox "Error: '$path_' is a directory, not a file." 10 50 >/dev/tty
            return 1
        elif [ ! -r "$path_" ]; then
            whiptail --msgbox "Error: Cannot read project file '$path_'." 10 50 >/dev/tty
            return 1
        fi

        local tmpfile
        tmpfile=$(mktemp) || {
            whiptail --msgbox "Error: Failed to create temporary file." 10 50 >/dev/tty
            return 1
        }
        cat "$path_" > "$tmpfile"
        whiptail --scrolltext --title "$title_" --textbox "$tmpfile" 20 150
        rm -f "$tmpfile"
    done
}

delete_project() {
    # Check if projects database exists and is readable
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --title "Error" --msgbox "No projects found." 8 40
        return 1
    fi

    # FIX: FILTER BY PROJECT FILE NAME.
#    # Read all project entries into an array
#    local lines=()
#    while IFS= read -r line; do
#        lines+=("$line")
#    done < "$PROJECTS_DB"

    local lines=()
    mapfile -d '' -t lines < <(filter_projects_by_name)		# get filtered lines from utility function. \0 delimited.

    # # Check for empty database
    # if [[ ${#lines[@]} -eq 0 ]]; then
    #     whiptail --title "Error" --msgbox "No projects found in database." 8 50
    #     return 1
    # fi

#    # Extract project paths and build menu options
#    local paths=()
#    local options=()
#    for i in "${!lines[@]}"; do
#        IFS='|' read -ra parts <<< "${lines[i]}"
#        if [[ ${#parts[@]} -ge 2 ]]; then
#            paths+=("${parts[1]}")
#            options+=("$((i+1))" "${parts[1]}")
#        else
#            paths+=("Invalid entry")
#            options+=("$((i+1))" "Invalid project entry")
#        fi
#    done

    local paths=()
    local options=("<< Back" "")
    local line i
    for line in "${lines[@]}"; do
        IFS='|' read -ra parts <<< "$line"
	    i=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1)

        if [[ ${#parts[@]} -ge 2 ]]; then
            paths+=("${parts[1]}")
            options+=("$i" "${parts[1]}")
        else
            paths+=("Invalid entry")
            options+=("$i" "Invalid project entry")
        fi
    done

    mapfile -t lines < "$PROJECTS_DB"	# DIRTY FIX.
    # FIX END.

    # Paginate options then get item to delete
    paginate_get_projects "Delete Project" "${options[@]}"
    local selected
    selected="$SELECTED_ITEM_PROJECT"

    # Show selection menu
    #local selected
    #selected=$(whiptail --title "Delete Project" --menu "Choose a project to delete:" \
    #    20 150 10 "${options[@]}" 3>&1 1>&2 2>&3) || return 1
    
    [[ -z "$selected" || "$selected" == "<< Back" ]] && return 1  # User canceled

    # Validate selection
    local index=$((selected - 1))
    if [[ $index -lt 0 || $index -ge ${#lines[@]} ]]; then
        whiptail --title "Error" --msgbox "Invalid selection." 8 50
        return 1
    fi

    # Get project details
    local line_to_delete="${lines[index]}"
    IFS='|' read -ra parts_ <<< "$line_to_delete"
    local project_path="${parts_[1]}"

    # Confirmation dialog
    whiptail --title "Confirm Deletion" --yesno "Permanently delete project:\n$project_path" \
        --yes-button "Delete" --no-button "Cancel" 10 60 || return 1

    # Verify the project is within the allowed directory
    local project_real    
    project_real=$(realpath "$project_path") || {
        whiptail --title "Error" --msgbox "Invalid project path:\n$project_path" 8 60
        return 1
    }

    # Delete project files/directory
    if ! rm -rf "$project_real"; then
        whiptail --title "Error" --msgbox "Failed to delete project files:\n$project_real" 8 60
        return 1
    fi

    # Delete entry from database
    local tempfile
    tempfile=$(mktemp)
    grep -vFx "$line_to_delete" "$PROJECTS_DB" > "$tempfile"
    mv "$tempfile" "$PROJECTS_DB"

    whiptail --title "Success" --msgbox "Project deleted successfully." 8 50
}

associate_note_to_project() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    #local PROJECTS_DB="$PROJECTS_DB"
    #local NOTES_DB="$NOTES_DB"
    local temp_file line_updated duplicate_detected project_found
    temp_file=$(mktemp) || return 1
    line_updated=0
    duplicate_detected=0
    project_found=0

    # Check if databases exist
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

#    # Read projects into menu
#    local project_menu_options=()
#    while IFS='|' read -r title path rest; do
#        project_menu_options+=("$path" "")
#    done < "$PROJECTS_DB"
#    if [[ "${#project_menu_options[@]}" -eq 0 ]]; then
#        whiptail --msgbox "No projects available in the database." 20 50
#        return 1
#    fi

    # FIX: ALLOW FILTERING BY GLOB.
    # Get pattern from user using whiptail
    local pattern
    pattern=$(whiptail --inputbox "Enter filename glob pattern to filter projects (empty for wildcard):" 10 60 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    : "${pattern:=*}"	# default to * if unset.

    # Enable case-insensitive glob matching
    shopt -s nocasematch
    
    local project_menu_options=()
    local filename title path rest
    while IFS='|' read -r title path rest; do
        # Extract filename from path
        filename=$(basename "$path")
        
        # Check if filename matches the pattern (now case-insensitive)
        if [[ "$filename" == $pattern ]]; then
            project_menu_options+=("$path" "")
        fi
    done < "$PROJECTS_DB"
    
    # Restore default case sensitivity
    shopt -u nocasematch

    # If no matches found, show message and exit
    if [ ${#project_menu_options[@]} -eq 0 ]; then
        whiptail --msgbox "No projects matched the pattern '${pattern}'" 8 40 >/dev/tty
        return 1
    fi
    # END FIX.

    # Project selection
    paginate_get_projects "Select Project" "${project_menu_options[@]}"
    local selected_project_path
    selected_project_path="$SELECTED_ITEM_PROJECT"
    [[ -z "$selected_project_path" ]] && return 1

    #local selected_project_path
    #selected_project_path=$(whiptail --title "Select Project" \
    #    --menu "Choose project to associate note:" \
    #    25 150 15 "${project_menu_options[@]}" 3>&1 1>&2 2>&3)
    #[[ -z "$selected_project_path" ]] && return 1  # User canceled

    # FIX: FILTER BY TAG AND PAGINATE TAG SELECTION.
    local note_tag_options=("ANY TAG" "Any tag (no filter)")    

    while IFS= read -r tag; do
        [[ -n "$tag" ]] && note_tag_options+=("$tag" "")
    done < "$NOTES_TAGS_DB"

    local selected_note_tag
    selected_note_tag="$(paginate_tags_menu "Select Note Tag to Filter Notes" "${note_tag_options[@]}")" || return 1

    # Read notes into menu
    local note_menu_options=()
    local note_tags_arr
    while IFS='|' read -r note_title note_path note_tags rest; do
        # handle case when line has no associated tag yet. include its note path if ANY TAG was selected.
        if [[ "$selected_note_tag" == "ANY TAG" ]]; then
            note_menu_options+=("$note_path" "[${note_tags}]")
            continue
        fi

        # FIX: FILTER BY NOTE TAG
        IFS=',' read -r -a note_tags_arr <<< "$note_tags"

        # only enters here if line already has a tag
        for tag in "${note_tags_arr[@]}"; do
            if [[ "${tag,,}" == "${selected_note_tag,,}" || "$selected_note_tag" == "ANY TAG" ]]; then
                note_menu_options+=("$note_path" "[${note_tags}]")
                break
            fi
        done

        #note_menu_options+=("$note_path" "[${note_tags}]")
    done < "$NOTES_DB"
    if [[ "${#note_menu_options[@]}" -eq 0 ]]; then
        whiptail --msgbox "No notes available in the database." 20 50
        return 1
    fi

    while :; do
        # Note selection
        paginate_get_projects "Choose Note to Associate" "${note_menu_options[@]}"
        local selected_note_path
        selected_note_path="$SELECTED_ITEM_PROJECT"
        [[ -z "$selected_note_path" ]] && return 1

        #local selected_note_path
        #selected_note_path=$(whiptail --title "Select Note" \
        #    --menu "Choose a note to associate:" \
        #    25 150 15 "${note_menu_options[@]}" 3>&1 1>&2 2>&3)
        #[[ -z "$selected_note_path" ]] && return 1  # User canceled

        # Process PROJECTS_DB
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                #echo >> "$temp_file"
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                continue
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                continue
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            continue
        fi
    done
}

dissociate_note_from_project() {
    find_tags_for_linked_note() {
        local path_to_note_file="$1"
        local matching_tags_str=""

        # Ensure NOTES_DB is defined and exists
        if [[ -z "$NOTES_DB" || ! -f "$NOTES_DB" ]]; then
            echo "Error: NOTES_DB not defined or file not found." >&2
            return 1
        fi

        # Extract the tags (3rd field) for the matching note
        matching_tags_str=$(awk -F'|' -v path="$path_to_note_file" '$2 == path {print $3}' "$NOTES_DB")

        echo "$matching_tags_str"
    }

    #local PROJECTS_DB=${PROJECTS_DB:-"$HOME/projects_db"}

    # Check if database exists
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    fi

    # Read filtered projects (null-delimited)
    local lines=()
    mapfile -d '' -t lines < <(filter_projects_by_name)

    local project_options=("<< Back" "")
    local title path notes line lineno
    for line in "${lines[@]}"; do
        IFS='|' read -r title path notes <<< "$line"
        lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1)
        [[ -n "$lineno" ]] && project_options+=($((lineno-1)) "$path")
    done

    # Load full DB lines for editing later
    mapfile -t lines < "$PROJECTS_DB"

    # Show project selection menu
    paginate_get_projects "Select Project" "${project_options[@]}"
    local selected_project="$SELECTED_ITEM_PROJECT"
    [[ -z "$selected_project" || "$selected_project" == "<< Back" ]] && return 1

    local line="${lines[selected_project]}"
    IFS='|' read -r title path notes <<< "$line"

    # Begin dissociation loop
    while true; do
        if [[ -z "$notes" ]]; then
            whiptail --msgbox "Selected project has no associated notes." 10 60 >/dev/tty
            return 1
        fi

        # Split notes into array
        local -a notes_arr
        IFS=',' read -ra notes_arr <<< "$notes"

        if [[ ${#notes_arr[@]} -eq 0 ]]; then
            whiptail --msgbox "No notes left to dissociate." 10 60 >/dev/tty
            return 1
        fi

        # Build menu options (add << Back at top)
        local -a note_options=("<< Back" "")
        local note_index note_matching_tags
        for note_index in "${!notes_arr[@]}"; do
            note_matching_tags="$(find_tags_for_linked_note "${notes_arr[note_index]}")"
            note_options+=("$note_index" "${notes_arr[note_index]} [${note_matching_tags}]")
        done

        # Show note selection menu
        paginate_get_projects "Choose Note to Dissociate" "${note_options[@]}"
        local selected_note="$SELECTED_ITEM_PROJECT"

        # If user chooses << Back, stop loop
        [[ -z "$selected_note" || "$selected_note" == "<< Back" ]] && break

        # Remove selected note from list
        local -a new_notes=()
        for note_index in "${!notes_arr[@]}"; do
            if [[ $note_index -ne $selected_note ]]; then
                new_notes+=("${notes_arr[note_index]}")
            fi
        done

        # Join remaining notes into CSV
        local new_notes_str=""
        if [[ ${#new_notes[@]} -gt 0 ]]; then
            new_notes_str=$(IFS=','; printf '%s' "${new_notes[*]}")
        fi

        # Update database entry in memory
        lines[selected_project]="$title|$path|$new_notes_str"
        notes="$new_notes_str"  # Update current project notes for next loop

        # Write database back to file
        local tmp_db
        tmp_db=$(mktemp) || return 1
        printf "%s\n" "${lines[@]}" > "$tmp_db"
        mv -- "$tmp_db" "$PROJECTS_DB" || { rm -- "$tmp_db"; return 1; }

        whiptail --msgbox "Note successfully dissociated from project." 10 60 >/dev/tty

        # If no notes left, exit loop automatically
        [[ -z "$notes" ]] && {
            whiptail --msgbox "All notes have been dissociated from this project." 10 60 >/dev/tty
            break
        }
    done
}

# OLD VERSION - JUST FOR RECORD (NEW VERSION ALLOWS MULTIPLE DISSOCIATE NOTE SELECTION)
# dissociate_note_from_project() {
#     #local PROJECTS_DB=${PROJECTS_DB:-"$HOME/projects_db"}  # Default path if not set
    
#     # Check if database exists
#     if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
#         whiptail --msgbox "Error: PROJECTS_DB file '$PROJECTS_DB' not found or empty." 10 60 >/dev/tty
#         return 1
#     fi

#     # FIX: FILTER BY PROJECT NAME.
#     # Read all lines from database
# #    local -a lines
# #    mapfile -t lines < "$PROJECTS_DB"
#     local lines=()
#     mapfile -d '' -t lines < <(filter_projects_by_name)		# get filtered lines from utility function. \0 delimited.

#     # if [[ ${#lines[@]} -eq 0 ]]; then
#     #     whiptail --msgbox "No projects found in database." 10 60 >/dev/tty
#     #     return 1
#     # fi

#     # Generate project selection menu options
# #    local -a project_options
# #    local index title path notes
# #    for index in "${!lines[@]}"; do
# #        IFS='|' read -r title path notes <<< "${lines[index]}"
# #        project_options+=("$index" "$path")
# #    done
#     local project_options=("<< Back" "")
#     local title path notes line lineno
#     for line in "${lines[@]}"; do
#         IFS='|' read -r title path notes <<< "$line"
#         lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1)

# 	# Store matching index from PROJECTS_DB file.
#         [[ -n "$lineno" ]] && project_options+=($((lineno-1)) "$path")
#     done

#     mapfile -t lines < "$PROJECTS_DB"	# DIRTY FIX.
#     # END FIX.

#     # Show project selection menu
#     paginate_get_projects "Select Project" "${project_options[@]}"
#     local selected_project
#     selected_project="$SELECTED_ITEM_PROJECT"
#     [[ -z "$selected_project" || "$selected_project" == "<< Back" ]] && return 1

#     #local selected_project
#     #selected_project=$(whiptail --title "Select Project" --menu "Choose a project to dissociate note from:" \
#     #    20 80 10 "${project_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
#     #if [[ $? -ne 0 ]]; then return 1; fi  # User canceled

#     # Get selected project details
#     local line="${lines[selected_project]}"
#     IFS='|' read -r title path notes <<< "$line"

#     # Check for existing notes
#     if [[ -z "$notes" ]]; then
#         whiptail --msgbox "Selected project has no associated notes." 10 60 >/dev/tty
#         return 1
#     fi

#     # Split notes into array
#     local -a notes_arr
#     IFS=',' read -ra notes_arr <<< "$notes"
#     if [[ ${#notes_arr[@]} -eq 0 ]]; then
#         whiptail --msgbox "Selected project has no associated notes" 10 60 >/dev/tty
#         return 1
#     fi

#     # Generate note selection menu options
#     local -a note_options
#     local note_index
#     for note_index in "${!notes_arr[@]}"; do
#         note_options+=("$note_index" "${notes_arr[note_index]}")
#     done

#     # Show note selection menu
#     paginate_get_projects "Choose Note to Dissociate" "${note_options[@]}"
#     local selected_note
#     selected_note="$SELECTED_ITEM_PROJECT"
#     [[ -z "$selected_note" ]] && return 1

#     #local selected_note
#     #selected_note=$(whiptail --title "Select Note" --menu "Choose note to remove:" \
#     #    20 80 10 "${note_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
#     #if [[ $? -ne 0 ]]; then return 1; fi  # User canceled

#     # Remove selected note from array
#     local -a new_notes
#     for note_index in "${!notes_arr[@]}"; do
#         if [[ $note_index -ne $selected_note ]]; then
#             new_notes+=("${notes_arr[note_index]}")
#         fi
#     done

#     # Update the database entry
#     local new_notes_str
#     # If after removing selected note there is a note left over in entry...
#     if [[ ${#new_notes[@]} -gt 0 ]]; then
#         new_notes_str=$(IFS=','; printf '%s' "${new_notes[*]}")
#     else
#         new_notes_str=""
#     fi

#     lines[selected_project]="$title|$path|$new_notes_str"

#     # Write updated database
#     local tmp_db
#     tmp_db=$(mktemp) || return 1
#     printf "%s\n" "${lines[@]}" > "$tmp_db"
#     mv -- "$tmp_db" "$PROJECTS_DB" || { rm -- "$tmp_db"; return 1; }

#     whiptail --msgbox "Note successfully dissociated from project." 10 60
# }

open_note_ebook_page_from_project() {
    local selected_line="$1"

    #echo "selected_line: ${selected_line}"  # pass
    #exit

    [[ -z "$selected_line" ]] && return 1

    local selected_ebook=$(get_ebooks "$selected_line")

    #echo "selected_ebook: ${selected_ebook}"    # pass
    #exit

    [[ -z "$selected_ebook" ]] && return 1

    # Extract the chapters part from the selected_ebook
    local chapters_part=$(cut -d'#' -f2 <<< "$selected_ebook")

    #echo "chapters_part: ${chapters_part}"  #pass
    #exit

    if [[ -n "$chapters_part" ]]; then
        # Chapters are present, prompt user to select one
        local selected_chapter=$(get_chapters "$selected_ebook")

        if [[ "$selected_chapter" == ">> Just open" ]]; then
            handle_no_chapters "$selected_ebook"
            return
        fi

        if [ -n "$selected_chapter" ]; then
            local page=$(extract_page "$selected_chapter")
            [[ -z "$page" ]] && return 1
            open_evince "$selected_ebook" "$page"
        #else
        #    # User canceled chapter selection; open without page
        #    open_evince "$selected_ebook"
        fi
    else
        # No chapters available; ask to open the ebook directly
        #open_evince "$selected_ebook"
        handle_no_chapters "$selected_ebook"
    fi
}

do_stuff_with_project_file() {
    truncate_tag() {
        local tags="$1"
        local max_len=60    # tweak this!

        # If already within limit, print unchanged
        if (( ${#tags} <= max_len )); then
            echo "$tags"
            return
        fi

        # Split into an array (preserve tags with spaces)
        IFS=',' read -r -a arr <<< "$tags"

        local latest_tag="${arr[-1]}"
        local result=""
        local sep=""

        # Try adding tags until adding another exceeds limit
        for (( i=0; i<${#arr[@]}-1; i++ )); do
            local t="${arr[$i]}"
            local candidate="${result}${sep}${t}"

            # If not enough room even if we later add ", ..., latest_tag", stop
            local future="${candidate}, ..., ${latest_tag}"
            if (( ${#future} > max_len )); then
                break
            fi

            result="$candidate"
            sep=", "
        done

        # If we couldn't include any tags (very tight width), result may be empty
        if [[ -z "$result" ]]; then
            echo "... , ${latest_tag}"
        else
            echo "${result}, ..., ${latest_tag}"
        fi
    }

    show_note_menu() {
        local selected_project_title="$1"
        # might as well truncate it here.
        (( ${#selected_project_title} > 50 )) && selected_project_title="${selected_project_title:0:50}..."
        shift

        local note_menu_options=("$@")
        local page=0
        local per_page=50    # adjust this to my liking
        local total_items=$(( ${#note_menu_options[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local selected_note_tag=""

        while true; do
            local start=$(( page * per_page ))
            local end=$(( start + per_page ))
            if (( end > total_items )); then end=$total_items; fi

            # Build current page menu items
            local menu_items=()
            for ((i=start; i<end; i++)); do
                local idx=$(( i * 2 ))
                menu_items+=( "${note_menu_options[idx]}" "${note_menu_options[idx+1]}" )
            done

            # Add navigation options
            if (( page > 0 )); then
                menu_items+=( "<< Prev" "" )
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=( ">> Next" "" )
            fi

            # Display menu
            selected_note_tag=$(whiptail --title "Linked Notes for ${selected_project_title} (Page $((page+1))/$total_pages)" \
                --menu "Select a linked note:" 20 170 10 "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

            # Handle navigation
            case "$selected_note_tag" in
                "<< Prev") ((page--));;
                ">> Next") ((page++));;
                *) echo "$selected_note_tag"; return 0;;
            esac
        done
    }

    open_url_assoc_to_chosen_note() {
        touch "$URLS_DB"
        
        #local URLS_DB="$URLS_DB"
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls            

        # Check if URLs database exists
        if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
            whiptail --msgbox "URL database not found or empty!" 8 50 >/dev/tty
            return 1
        fi

        while true; do
            local selected_path
            [[ -n "$note_path" ]] && { selected_path="$note_path"; } || return 1

            # Extract URLs for selected note
            local urls=()
            local titles=()
            while IFS= read -r line; do
                # Only for the matched line...
                if [[ "$line" == "${selected_path}${GS}"* ]]; then
                    IFS="$RS" read -ra entries <<< "${line#*$GS}"
                    for entry in "${entries[@]}"; do
                        IFS="$US" read -r url title <<< "$entry"
                        urls+=("$url")
                        titles+=("$title")
                    done
                    break
                fi
            done < "$URLS_DB"

            if [[ ${#urls[@]} -eq 0 ]]; then
                whiptail --msgbox "No URLs found for selected note!" 8 50 >/dev/tty
                return 1                
            fi

            # URL selection loop
            [[ ${#urls[@]} -gt 0 ]] && {
                while true; do
                    local url_menu_items=("<< Back" "")
                    for i in "${!urls[@]}"; do
                        url_menu_items+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                    done

                    local choice
                    choice=$(whiptail --title "URLs for $selected_path" --menu "Choose URL to open:" \
                        20 170 10 "${url_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return 1
                    [[ -z "$choice" ]] && return 1

                    if [[ "$choice" == "<< Back" ]]; then
                        return 1
                    elif [[ -n "${urls[$choice]}" ]]; then                
                        nohup "$URL_BROWSER" "${urls[$choice]}" >/dev/null 2>&1 &	# to make sure browser stays open
                    fi
                done
            }
        done
    }

    assoc_url_to_chosen_note() {
        touch "$URLS_DB"
        
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls

        # Extract note paths from NOTES_DB
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Error: Notes database not found or empty!" 8 50 >/dev/tty
            return 1
        fi
        
        local selected_path
        [[ -n "$note_path" ]] && { selected_path="$note_path"; } || return 1

        # Load existing URLs
        local urls=()
        local titles=()
        if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
            while IFS= read -r line; do
                if [[ "$line" == "${selected_path}${GS}"* ]]; then
                    IFS="$RS" read -ra entries <<< "${line#*$GS}"
                    for entry in "${entries[@]}"; do
                        IFS="$US" read -r url title <<< "$entry"
                        urls+=("$url")
                        titles+=("$title")
                    done
                    break
                fi
            done < "$URLS_DB"
        fi

        local url_regex='^(https?:\/\/)?(www\.)?([a-zA-Z0-9-]+\.)+[A-Za-z]{2,}(:[0-9]+)?(\/\S*)?$'

        # URL management loop
        while true; do
            local menu_options=("Register URL" "" "Save and return" "")
            for i in "${!urls[@]}"; do
                menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 170 10 "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
            [[ -z "$choice" ]] && return 1

            case "$choice" in
                "Register URL")
                    local new_url new_title
                    new_url=$(whiptail --inputbox "Enter URL:" 8 50 3>&1 1>&2 2>&3)
                    [[ $? -ne 0 ]] && continue

                    # validate URL
                    if [[ ! $new_url =~ $url_regex ]]; then
                        whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
                        continue
                    fi

                    new_title=$(whiptail --inputbox "Enter URL title:" 8 50 3>&1 1>&2 2>&3)
                    [[ $? -ne 0 ]] && continue

                    if [[ -z "$new_url" || -z "$new_title" ]]; then
                        whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                        continue
                    fi

                    urls+=("$new_url")
                    titles+=("$new_title")
                    ;;

                "Save and return")
                    # Construct new entry
                    local new_entry="${selected_path}${GS}"
                    for i in "${!urls[@]}"; do
                        new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                    done
                    new_entry="${new_entry%$RS}"

                    # Update URLS_DB
                    local temp_file
                    temp_file=$(mktemp) || return 1
                    if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
                        # Write every line except for selected path to temp file.
                        while IFS= read -r line; do
                            [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                        done < "$URLS_DB" > "$temp_file"
                    fi
                    # Add new entry at the end of the temp file.
                    echo "$new_entry" >> "$temp_file"

                    # Replace original file
                    mv "$temp_file" "$URLS_DB"
                    whiptail --msgbox "URL associations saved successfully!" 8 50 >/dev/tty
                    return 0
                    ;;

                *)
                    # Handle existing URL selection
                    local index="$choice"
                    if [[ ! -v urls[index] ]]; then
                        whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                        continue
                    fi

                    # Submenu for edit/delete
                    local sub_choice
                    sub_choice=$(whiptail --menu "Manage URL" 20 60 10 \
                        "Change values" "" \
                        "Delete URL" "" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                    [[ -z "$sub_choice" ]] && continue

                    case "$sub_choice" in
                        "Change values")
                            local current_url="${urls[index]}"
                            local current_title="${titles[index]}"
                            new_url=$(whiptail --inputbox "Edit URL:" 8 50 "$current_url" 3>&1 1>&2 2>&3)
                            [[ $? -ne 0 ]] && continue

                            # validate URL
                            if [[ ! $new_url =~ $url_regex ]]; then
                                whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
                                continue
                            fi

                            new_title=$(whiptail --inputbox "Edit URL title:" 8 50 "$current_title" 3>&1 1>&2 2>&3)
                            [[ $? -ne 0 ]] && continue

                            if [[ -z "$new_url" || -z "$new_title" ]]; then
                                whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                                continue
                            fi

                            urls[index]="$new_url"
                            titles[index]="$new_title"
                            ;;
                        "Delete URL")
                            unset 'urls[index]'
                            unset 'titles[index]'
                            # Reindex arrays
                            urls=("${urls[@]}")
                            titles=("${titles[@]}")
                            ;;
                    esac
                    ;;
            esac
        done
    }    

    dissoc_url_from_chosen_note() {
        touch "$URLS_DB"
        
        #local URLS_DB="$URLS_DB"
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls

        # Check URL database existence
        if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
            whiptail --msgbox "Error: URLs database not found or empty!" 8 50 >/dev/tty
            return 1
        fi

        local selected_path
        [[ -n "$note_path" ]] && { selected_path="$note_path"; } || return 1

        # Load existing URLs
        local urls=()
        local titles=()
        while IFS= read -r line; do
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"

        # URL removal loop
        while true; do
            local menu_options=("Remove URL" "" "Save and return" "")
            for i in "${!urls[@]}"; do
                menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 170 10 \
                "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
            [[ -z "$choice" ]] && continue

            case "$choice" in
                "Remove URL")
                    if [[ ${#urls[@]} -eq 0 ]]; then
                        whiptail --msgbox "No URLs to remove!" 8 50 >/dev/tty
                        continue
                    fi

                    # Create removal submenu
                    local remove_menu=()
                    for i in "${!urls[@]}"; do
                        remove_menu+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                    done

                    local remove_index
                    remove_index=$(whiptail --menu "Select URL to remove" 20 170 10 \
                        "${remove_menu[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                    [[ -z "$remove_index" ]] && continue

                    # Validate and remove selected URL
                    if [[ -v "urls[$remove_index]" ]]; then
                        unset 'urls[$remove_index]'
                        unset 'titles[$remove_index]'
                        urls=("${urls[@]}")  # Reindex array
                        titles=("${titles[@]}")
                    else
                        whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                    fi
                    ;;

                "Save and return")
                    # Prepare new entry
                    local new_entry="${selected_path}${GS}"
                    for i in "${!urls[@]}"; do
                        new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                    done
                    new_entry="${new_entry%$RS}"

                    # Update database
                    local temp_file=$(mktemp) || return 1
                    {
                        # Copy existing entries except current note
                        while IFS= read -r line; do
                            [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                        done < "$URLS_DB"
                        
                        # Add updated entry if URLs remain
                        [[ -n "$new_entry" ]] && echo "$new_entry"
                    } > "$temp_file"

                    mv "$temp_file" "$URLS_DB"
                    whiptail --msgbox "URL associations updated!" 8 50 >/dev/tty
                    return 0
                    ;;

                *)
                    # Ignore URL index selections
                    continue
                    ;;
            esac
        done
    }

    associate_chosen_note_to_project() {
        # Get note path from arg
        local note_path="$1"
        [[ -z "$note_path" ]] && return 1

        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        # FIX: ALLOW FILTERING BY GLOB.
        # Get pattern from user using whiptail
        local pattern
        pattern=$(whiptail --inputbox "Enter filename glob pattern to filter projects (empty for wildcard):" 10 60 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        : "${pattern:=*}"	# default to * if unset.

        # Enable case-insensitive glob matching
        shopt -s nocasematch
        
        local project_menu_options=()
        local filename title path rest
        while IFS='|' read -r title path rest; do
            # Extract filename from path
            filename=$(basename "$path")
            
            # Check if filename matches the pattern (now case-insensitive)
            if [[ "$filename" == $pattern ]]; then
                project_menu_options+=("$path" "")
            fi
        done < "$PROJECTS_DB"
        
        # Restore default case sensitivity
        shopt -u nocasematch

        # If no matches found, show message and exit
        if [ ${#project_menu_options[@]} -eq 0 ]; then
            whiptail --msgbox "No projects matched the pattern '${pattern}'" 8 40 >/dev/tty
            return 1
        fi
        # END FIX.

        # Project selection
        paginate_get_projects "Select Project" "${project_menu_options[@]}"
        local selected_project_path
        selected_project_path="$SELECTED_ITEM_PROJECT"
        [[ -z "$selected_project_path" ]] && return 1

        # User already chosen $note_path as chosen note file.
        local selected_note_path
        selected_note_path="$note_path"

        [[ -z "$selected_note_path" ]] && return 1

        # Process PROJECTS_DB
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                #echo >> "$temp_file"
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                return 1
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                return 1
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            return 1
        fi
    }

    print_chosen_note() {
        print_file_from_do_stuff_project() {
            # Check if file argument is provided
            if [ -z "$1" ]; then
                return 1
            fi

            local file_to_print="$1"

            # Check if file exists
            if [ ! -f "$file_to_print" ]; then
                echo "Error: File '$file_to_print' does not exist." >&2
                return 1
            fi

            # Get list of printers
            local printers
            printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')            

            # Edge case: no printers found.
            [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

            # Convert printer list into whiptail menu format
            local menu_items=()
            for p in $printers; do
                menu_items+=("$p" "")
            done

            # Show whiptail menu to select printer
            local selected_printer
            selected_printer=$(whiptail --title "Select Printer" \
                --menu "Choose a printer:" 20 60 10 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            # Check if user cancelled
            if [ $? -ne 0 ]; then
                return 1
            fi

            # Print the file
            if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
                lpr -P "$selected_printer" "$file_to_print"
                if [ $? -eq 0 ]; then
                    whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
                else
                    whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                    return 1
                fi            
            else
                :  # do nothing if No or Cancel
            fi
        }

        local selected_path="$1"       
        print_file_from_do_stuff_project "$selected_path"
    }

    associate_new_note_to_project_from_do_stuff() {
        # note path is the new note you've just created from select notes menu.
        local NEW_NOTE_PATH="$note_path"
        [[ -z "$NEW_NOTE_PATH" ]] && return 1

        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        local selected_project_path
        selected_project_path="$1"
        [[ -z "$selected_project_path" ]] && return 1

        local selected_note_path="$NEW_NOTE_PATH"

        # WE'VE SELECTED PROJECT FILE AND NOTE FILE AT THIS POINT!!!!

        # Process PROJECTS_DB - update each line (only change line of selected project file)
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then set duplicate and break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                return 1
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                return 1
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            return 1
        fi
    }

    associate_note_to_project_from_do_stuff() {
        paginate_tags_menu() {
            local title="$1"
            shift
            local items=("$@")
            local per_page=20
            local total_items=$(( ${#items[@]} / 2 ))
            local total_pages=$(( (total_items + per_page - 1) / per_page ))
            local current_page=1
            local choice start_index end_index menu_items tag desc

            while true; do
                # Calculate start and end indices for current page
                start_index=$(( (current_page - 1) * per_page * 2 ))
                end_index=$(( start_index + per_page * 2 ))
                menu_items=()

                # Add items for current page
                for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                    tag="${items[i]}"
                    desc="${items[i+1]}"
                    menu_items+=("$tag" "$desc")
                done

                # Add navigation options
                if (( current_page > 1 )); then
                    menu_items+=("<< Prev" "")
                fi
                if (( current_page < total_pages )); then
                    menu_items+=(">> Next" "")
                fi

                # Show whiptail menu
                choice=$(whiptail --title "$title" \
                    --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                    "${menu_items[@]}" 3>&1 1>&2 2>&3)

                [[ $? -ne 0 ]] && return 1  # Cancel pressed

                case "$choice" in
                    ">> Next")
                        (( current_page++ ))
                        ;;
                    "<< Prev")
                        (( current_page-- ))
                        ;;
                    *)
                        # Return selected tag
                        printf '%s\n' "$choice"
                        return 0
                        ;;
                esac
            done
        }

        #local PROJECTS_DB="$PROJECTS_DB"
        #local NOTES_DB="$NOTES_DB"
        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        local selected_project_path
        selected_project_path="$1"
        [[ -z "$selected_project_path" ]] && return 1

        # FIX: FILTER BY TAG AND PAGINATE TAG SELECTION.
        local note_tag_options=("ANY TAG" "Any tag (no filter)")    

        while IFS= read -r tag; do
            [[ -n "$tag" ]] && note_tag_options+=("$tag" "")
        done < "$NOTES_TAGS_DB"

        local selected_note_tag
        selected_note_tag="$(paginate_tags_menu "Select Note Tag to Filter Notes" "${note_tag_options[@]}")" || return 1

        # Read notes into menu
        local note_menu_options=()
        local note_tags_arr
        while IFS='|' read -r note_title note_path note_tags rest; do
            # handle case when line has no associated tag yet. include its note path if ANY TAG was selected.
            if [[ "$selected_note_tag" == "ANY TAG" ]]; then
                note_menu_options+=("$note_path" "[${note_tags}]")
                continue
            fi

            # FIX: FILTER BY NOTE TAG
            IFS=',' read -r -a note_tags_arr <<< "$note_tags"

            # only enters here if line already has a tag
            for tag in "${note_tags_arr[@]}"; do
                if [[ "${tag,,}" == "${selected_note_tag,,}" || "$selected_note_tag" == "ANY TAG" ]]; then
                    note_menu_options+=("$note_path" "[${note_tags}]")
                    break
                fi
            done

            #note_menu_options+=("$note_path" "[${note_tags}]")
        done < "$NOTES_DB"
        if [[ "${#note_menu_options[@]}" -eq 0 ]]; then
            whiptail --msgbox "No notes available in the database." 20 50
            return 1
        fi

        while :; do
            # Note selection
            paginate_get_projects "Choose Note to Associate" "${note_menu_options[@]}"
            local selected_note_path
            selected_note_path="$SELECTED_ITEM_PROJECT"
            [[ -z "$selected_note_path" ]] && return 1

            #local selected_note_path
            #selected_note_path=$(whiptail --title "Select Note" \
            #    --menu "Choose a note to associate:" \
            #    25 150 15 "${note_menu_options[@]}" 3>&1 1>&2 2>&3)
            #[[ -z "$selected_note_path" ]] && return 1  # User canceled

            # Process PROJECTS_DB
            while IFS= read -r line; do
                if [[ -z "$line" ]]; then
                    #echo >> "$temp_file"
                    continue
                fi

                IFS='|' read -r title path notes <<< "$line"
                # If there is matched line...
                if [[ "$path" == "$selected_project_path" ]]; then
                    project_found=1
                    current_notes="$notes"
                    local notes_array=()

                    # Check for duplicates
                    IFS=',' read -ra notes_array <<< "$current_notes"
                    local duplicate=0	# Reset for each iteration.
                    # If duplicate found then break out of for loop here.
                    for note in "${notes_array[@]}"; do
                        [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                    done

                    if (( duplicate )); then
                        whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                        # reset
                        line_updated=0

                        duplicate_detected=1
                        # Rebuild original line
                        new_line="$title|$path|$current_notes"
                        # There is no fourth field!!!!
                        # [[ -n "$rest" ]] && new_line+="|$rest"
                        echo "$new_line" >> "$temp_file"	# No change.
                    else
                        # reset
                        duplicate_detected=0

                        # Update notes
                        # If there is no previously associated note...
                        if [[ -z "$current_notes" ]]; then
                            new_notes="$selected_note_path"
                        else
                            new_notes="$current_notes,$selected_note_path"
                        fi
                        new_line="$title|$path|$new_notes"
                        #[[ -n "$rest" ]] && new_line+="|$rest"
                        echo "$new_line" >> "$temp_file"	# Changes made.
                        line_updated=1
                    fi
                else
                    # Just leave the line unchanged.
                    echo "$line" >> "$temp_file"
                fi
            done < "$PROJECTS_DB"

            # Handle processing results
            if (( project_found )); then
                if (( line_updated && !duplicate_detected )); then
                    mv "$temp_file" "$PROJECTS_DB"
                    whiptail --msgbox "Note successfully associated with the project." 10 50
                elif (( duplicate_detected )); then
                    rm "$temp_file"
                    #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                    continue
                else
                    rm "$temp_file"
                    whiptail --msgbox "No changes were made to the project entry." 10 50
                    continue
                fi
            else
                rm "$temp_file"
                whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
                continue
            fi
        done
    }

    dissociate_note_from_project_from_do_stuff() {
        find_tags_for_linked_note() {
            local path_to_note_file="$1"
            local matching_tags_str=""

            # Ensure NOTES_DB is defined and exists
            if [[ -z "$NOTES_DB" || ! -f "$NOTES_DB" ]]; then
                echo "Error: NOTES_DB not defined or file not found." >&2
                return 1
            fi

            # Extract the tags (3rd field) for the matching note
            matching_tags_str=$(awk -F'|' -v path="$path_to_note_file" '$2 == path {print $3}' "$NOTES_DB")

            echo "$matching_tags_str"
        }

        # Check if database exists
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Error: PROJECTS_DB file '$PROJECTS_DB' not found or empty." 10 60 >/dev/tty
            return 1
        fi

        # Load full DB lines for editing later
        mapfile -t lines < "$PROJECTS_DB"

        local selected_project_path="$1"

        local selected_project=$(awk -F'|' -v path="$selected_project_path" '$2 == path { print NR; exit }' "$PROJECTS_DB")
        [[ -z "$selected_project" ]] && return 1
        ((selected_project--))

        local line="${lines[selected_project]}"
        IFS='|' read -r title path notes <<< "$line"

        # Begin dissociation loop
        while true; do
            if [[ -z "$notes" ]]; then
                whiptail --msgbox "Selected project has no associated notes." 10 60 >/dev/tty
                return 1
            fi

            # Split notes into array
            local -a notes_arr
            IFS=',' read -ra notes_arr <<< "$notes"

            if [[ ${#notes_arr[@]} -eq 0 ]]; then
                whiptail --msgbox "No notes left to dissociate." 10 60 >/dev/tty
                return 1
            fi

            # Build menu options (add << Back at top)
            local -a note_options=("<< Back" "")
            local note_index note_matching_tags
            for note_index in "${!notes_arr[@]}"; do
                note_matching_tags="$(find_tags_for_linked_note "${notes_arr[note_index]}")"
                note_options+=("$note_index" "${notes_arr[note_index]} [${note_matching_tags}]")
            done

            # Show note selection menu
            paginate_get_projects "Choose Note to Dissociate" "${note_options[@]}"
            local selected_note="$SELECTED_ITEM_PROJECT"

            # If user chooses << Back, stop loop
            [[ -z "$selected_note" || "$selected_note" == "<< Back" ]] && return 1

            # Remove selected note from list
            local -a new_notes=()
            for note_index in "${!notes_arr[@]}"; do
                if [[ $note_index -ne $selected_note ]]; then
                    new_notes+=("${notes_arr[note_index]}")
                fi
            done

            # Join remaining notes into CSV
            local new_notes_str=""
            if [[ ${#new_notes[@]} -gt 0 ]]; then
                new_notes_str=$(IFS=','; printf '%s' "${new_notes[*]}")
            fi

            # Update database entry in memory
            lines[selected_project]="$title|$path|$new_notes_str"
            notes="$new_notes_str"  # Update current project notes for next loop

            # Write database back to file
            local tmp_db
            tmp_db=$(mktemp) || return 1
            printf "%s\n" "${lines[@]}" > "$tmp_db"
            mv -- "$tmp_db" "$PROJECTS_DB" || { rm -- "$tmp_db"; return 1; }

            whiptail --msgbox "Note successfully dissociated from project." 10 60 >/dev/tty

            # If no notes left, exit loop automatically
            [[ -z "$notes" ]] && {
                whiptail --msgbox "All notes have been dissociated from this project." 10 60 >/dev/tty
                break
            }
        done
    }

    local projects=()
    mapfile -d '' -t projects < <(filter_projects_by_name)	

    local project_menu_options=("<< Back" "")
    local title line lineno
    for line in "${projects[@]}"; do
        IFS='|' read -r title _ _ <<< "$line"
        lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1)

	    # Store matching index from PROJECTS_DB file.
        [[ -n "$lineno" ]] && project_menu_options+=("$lineno" "$title")
    done

    mapfile -t projects < "$PROJECTS_DB"	# DIRTY FIX.
    # END FIX.

    # Show project selection
    paginate_get_projects "Select Project" "${project_menu_options[@]}"
    local selected_project_tag
    selected_project_tag="$SELECTED_ITEM_PROJECT"
    [[ -z "$selected_project_tag" || "$selected_project_tag" == "<< Back" ]] && return 1

    # FIX: WHILE LOOP TO ALLOW MULTIPLE LINKED NOTE SELECTIONS
    while :; do
        # Refresh linked notes list at the start of each iteration.
        mapfile -t projects < "$PROJECTS_DB"    # Reload from PROJECTS DB file.
        local selected_project_index=$((selected_project_tag - 1))
        local selected_project_line="${projects[$selected_project_index]}"

        local selected_project_title selected_project_path associated_notes
        IFS='|' read -r selected_project_title selected_project_path associated_notes <<< "$selected_project_line"

        # Process associated notes
        local note_paths=()
        IFS=',' read -ra note_paths <<< "$associated_notes"
        local note_lines=() 
        local note_menu_options=()

        # Add option 'Create new linked note' first
        note_menu_options+=("Create new linked note" "")
        note_menu_options+=("Link note" "")
        note_menu_options+=("Unlink note" "")

        local trunc_tag
        for np in "${note_paths[@]}"; do
            while IFS= read -r line; do
                IFS='|' read -r title path tags _ <<< "$line"
                if [ "$path" = "$np" ]; then
                    note_lines+=("$line")         

                    # truncate tag string
                    trunc_tag="$(truncate_tag "$tags")"    

                    note_menu_options+=("${#note_lines[@]}" "$title [${trunc_tag}]")
                    break
                fi
            done < "$NOTES_DB"
        done        
        # Refresh code end.                       

        # FIX: PAGINATE LINKED NOTE SELECTION
        local selected_note_tag
        selected_note_tag="$(show_note_menu "$selected_project_title" "${note_menu_options[@]}")" || return 1

        # Handle case when user selects "Create new lnked note".
        if [[ "$selected_note_tag" == "Create new linked note" ]]; then
            add_note || continue
            associate_new_note_to_project_from_do_stuff "$selected_project_path"
            continue    # Continue since we need to update the linked notes list now.
        elif [[ "$selected_note_tag" == "Link note" ]]; then
            associate_note_to_project_from_do_stuff "$selected_project_path" || continue
            continue    # Display list of linked notes again after associating a note.   
        elif [[ "$selected_note_tag" == "Unlink note" ]]; then
            dissociate_note_from_project_from_do_stuff "$selected_project_path" || continue
            continue    # Display list of lined notes again after dissociating notes.                     
        fi

        local selected_note_index=$((selected_note_tag - 1))
        local selected_note_line="${note_lines[$selected_note_index]}"

        # Action selection
        local action
        action=$(whiptail --menu "Note Action" 20 50 8 \
            "1" "View Note" \
            "2" "Open ebooks linked to note" \
            "3" "Edit Note" \
            "4" "Open linked URL" \
            "5" "Associate URL to note" \
            "6" "Dissociate URL from note" \
            "7" "Associate Note to Project" \
            "8" "Print Note using Printer" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue    # i want to return to list of linked note files so continue

        case "$action" in
            "1")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                #whiptail --scrolltext --title "$note_title" --textbox "$note_path" 35 150
                
                # FIX: USE DIALOG INSTEAD BECAUSE WHIPTAIL FAILS HERE.
                # Specifically, \n \t etc gets translated.
                # Match the colors with whiptail as best as possible.
                DIALOG_CONFIG="use_colors = ON
                screen_color = (BLACK,MAGENTA,OFF)
                dialog_color = (BLACK,WHITE,OFF)
                title_color = (RED,WHITE,OFF)
                border_color = (WHITE,WHITE,OFF)
                button_active_color = (WHITE,RED,OFF)"                                    
                #DIALOGRC=<(echo -e "$DIALOG_CONFIG") dialog --exit-label "Back" --title "$note_title" --textbox "$note_path" 35 150
                # Word wrap width 145
                local tmpfile=$(mktemp)
                fold -s -w 145 "$note_path" > "$tmpfile"
                DIALOGRC=<(echo -e "$DIALOG_CONFIG") dialog --no-mouse --exit-label "Back" --title "$note_title" --textbox "$tmpfile" 35 150
                rm -f "$tmpfile"
                clear
                ;;
            "2")
                open_note_ebook_page_from_project "$selected_note_line"
                ;;
            "3")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                edit_note "$note_path"
                ;;
            "4")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                open_url_assoc_to_chosen_note
                ;;
            "5")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                assoc_url_to_chosen_note
                ;;
            "6")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                dissoc_url_from_chosen_note
                ;;
            "7")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                associate_chosen_note_to_project "$note_path"
                ;;
            "8")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                print_chosen_note "$note_path"
                ;;
        esac
    done
}

open_url_assoc_to_note_from_project() {
    touch "$URLS_DB" "$PROJECTS_DB"
	
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls            

    # Check if Projects database exists
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    fi

    # Check if URLs database exists
    if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
        whiptail --msgbox "No URLs found. Associate at least one URL and try again." 8 40 >/dev/tty
        return 1
    fi

    # FIX: FILTER BY PROJECT NAME.
    # Get pattern from user using whiptail
    local pattern
    pattern=$(whiptail --inputbox "Enter filename glob pattern to filter projects (empty for wildcard):" 10 60 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    : "${pattern:=*}"	# default to * if unset.

    while true; do
		# FIX: FILTER CONTINUES HERE.
        # Enable case-insensitive glob matching
        shopt -s nocasematch

        local projects_menu_items=()
        local filename title proj_path notes
        while IFS='|' read -r title proj_path notes; do
            # Extract filename from path
            filename=$(basename "$proj_path")

            # Check if filename matches the pattern (now case-insensitive)
            if [[ "$filename" == $pattern ]]; then
                projects_menu_items+=("$proj_path" "")
            fi
        done < "$PROJECTS_DB"

        # Restore default case sensitivity
        shopt -u nocasematch

		# If $projects_menu_items is empty then inform user and return from function.
		[[ ${#projects_menu_items} -eq 0 ]] && {
			whiptail --title "Attention" --msgbox "There are no matches with pattern '${pattern}'." 10 70
			return 1
		}

#		# Build menu for choosing project path from PROJECTS_DB
#		local projects_menu_items=()
#		while IFS='|' read -r title proj_path notes; do
#			# skip blank lines or malformed ones
#			[[ -z "$proj_path" ]] && continue
#			projects_menu_items+=("$proj_path" "")
#		done < "$PROJECTS_DB"		
		# FIX END.
		
		# debug
		#echo projects_menu_items:
		#echo "${projects_menu_items[@]}"
		
		# Paginate instead!
		! paginate_get_projects "Choose Project to Open URL from Associated Note" "${projects_menu_items[@]}" && return 1
		local chosen_project
		chosen_project="$SELECTED_ITEM_PROJECT"
		[[ -z "$chosen_project" ]] && return 1

		# Menu for choosing project path
		#local chosen_project
		#chosen_project=$(whiptail --title "Open URL from Note Associated to Project" --menu "Choose project" 20 150 10 \
		#"${projects_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    
		# Matched line in PROJECTS_DB
		local project_line="$(grep -F "|${chosen_project}|" "$PROJECTS_DB")"
		[[ -z "$project_line" ]] && {
			whiptail --msgbox "Error. No match found in projects db!" 8 50 >/dev/tty
			return 1
		}
		
		# debug
		#echo project line:
		#echo "$project_line"
		
		# Extract notes field from line
		IFS='|' read -r _sel_title _sel_proj notes_field <<< "$project_line"
		# Create array containing note entries
		IFS=',' read -r -a note_paths_array <<< "$notes_field"

		# debug
		#echo notes_field:
		#echo "$notes_field"

        # Select note path
        local menu_items=("<< Return" "")
        for path in "${note_paths_array[@]}"; do
            menu_items+=("$path" "")
        done
		
        local selected_path
        selected_path=$(whiptail --title "Select Note" --menu "Choose a note to open URLs:" \
            20 150 10 "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return 1
        [[ -z "$selected_path" ]] && return 1
        
        # Handle return option
        if [[ "$selected_path" == "<< Return" ]]; then
            return 0
        fi

        # Extract URLs for selected note
        local urls=()
        local titles=()
        while IFS= read -r line; do
			# Only for the matched line...
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"

        if [[ ${#urls[@]} -eq 0 ]]; then
            whiptail --msgbox "No URLs found for selected note!" 8 50 >/dev/tty
            continue
        fi

        # URL selection loop
        while true; do
            local url_menu_items=("<< Back" "")
            for i in "${!urls[@]}"; do
                url_menu_items+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --title "URLs for $selected_path" --menu "Choose URL to open:" \
                20 170 10 "${url_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || break
            [[ -z "$choice" ]] && break

            if [[ "$choice" == "<< Back" ]]; then
                break
            elif [[ -n "${urls[$choice]}" ]]; then
                #eval "$URL_BROWSER" "'${urls[$choice]}'" >/dev/null 2>&1 &
                nohup "$URL_BROWSER" "${urls[$choice]}" >/dev/null 2>&1 &	# to make sure browser stays open
            fi
        done
    done
}

print_project_to_printer_from_main() {
    print_file_from_do_stuff_project_from_main() {
        # Check if file argument is provided
        if [ -z "$1" ]; then
            return 1
        fi

        local file_to_print="$1"

        # Check if file exists
        if [ ! -f "$file_to_print" ]; then
            echo "Error: File '$file_to_print' does not exist." >&2
            return 1
        fi

        # Get list of printers
        local printers
        printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')            

        # Edge case: no printers found.
        [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

        # Convert printer list into whiptail menu format
        local menu_items=()
        for p in $printers; do
            menu_items+=("$p" "")
        done

        # Show whiptail menu to select printer
        local selected_printer
        selected_printer=$(whiptail --title "Select Printer" \
            --menu "Choose a printer:" 20 60 10 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3)

        # Check if user cancelled
        if [ $? -ne 0 ]; then
            return 1
        fi

        # Print the file
        if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
            lpr -P "$selected_printer" "$file_to_print"
            if [ $? -eq 0 ]; then
                whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
            else
                whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                return 1
            fi            
        else
            :  # do nothing if No or Cancel
        fi
    }

    get_project_title_from_project_path() {
        local project_path="$1"
        local project_title

        project_title=$(awk -F'|' -v path="$project_path" '
            $2 == path {
                print $1
                exit
            }
        ' "$PROJECTS_DB")

        echo "$project_title"
    }
    
    #local line_num=0		# can't use this any more.
    local options=("<< Back" "")

    # Check if database file exists and is valid
    if [ ! -f "$PROJECTS_DB" ]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    elif [ ! -s "$PROJECTS_DB" ]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    fi

    # FIX: ADD FILTER BY GLOBBING
    local line title path

    # Parse project entries
    local lineno
    while IFS= read -r -d '' line; do
        #((line_num++))
	lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1) || echo "No exact match for '$match' found." >&2 # use this instead!

        [ -z "$line" ] && continue

        IFS='|' read -r title path _ <<< "$line"
        if [ -z "$title" ] || [ -z "$path" ]; then
            whiptail --msgbox "Skipping invalid entry (line $line_num): Missing field(s)" 10 50 >/dev/tty
            continue
        fi
        options+=("$lineno" "$title")
    done < <(filter_projects_by_name)
    # END FIX.

    # Continuous selection loop added here
    while true; do
    	# Paginate options
        paginate_get_projects "Print Project using Printer" "${options[@]}"
        local selected_line
        selected_line="$SELECTED_ITEM_PROJECT"
        [[ -z "$selected_line" || "$selected_line" == "<< Back" ]] && return 1
        
        # Rest of the original processing logic
        local line_=$(sed -n "${selected_line}p" "$PROJECTS_DB")
        if [ -z "$line_" ]; then
            whiptail --msgbox "Error: Selected project no longer exists." 10 50 >/dev/tty
            return 1
        fi

        local title_ path_
        IFS='|' read -r title_ path_ _ <<< "$line_"

        if [ ! -e "$path_" ]; then
            whiptail --msgbox "Error: Project file '$path_' not found." 10 50 >/dev/tty
            return 1
        elif [ -d "$path_" ]; then
            whiptail --msgbox "Error: '$path_' is a directory, not a file." 10 50 >/dev/tty
            return 1
        elif [ ! -r "$path_" ]; then
            whiptail --msgbox "Error: Cannot read project file '$path_'." 10 50 >/dev/tty
            return 1
        fi

        local action
        action=$(whiptail --title "Actions" --menu "Choose an action:" 10 40 2 \
                "View Project" "" \
                "Print Project" "" \
                3>&1 1>&2 2>&3) || :        

        case "$action" in
            "View Project")
                DIALOG_CONFIG="use_colors = ON
                screen_color = (BLACK,MAGENTA,OFF)
                dialog_color = (BLACK,WHITE,OFF)
                title_color = (RED,WHITE,OFF)
                border_color = (WHITE,WHITE,OFF)
                button_active_color = (WHITE,RED,OFF)"                                    

                local tmpfile
                tmpfile=$(mktemp)
                fold -s -w 145 "$path_" > "$tmpfile"
                # NOTE: PROJECT_TITLE IS NOT EXTRACTED YET! -- FIXED?
                local project_title="$(get_project_title_from_project_path "$path_")"
                DIALOGRC=<(echo -e "$DIALOG_CONFIG") dialog --no-mouse --exit-label "Back" --title "$project_title" --textbox "$tmpfile" 35 150                
                rm -f "$tmpfile"
                clear
                ;;
            "Print Project")
                print_file_from_do_stuff_project_from_main "$path_"
                ;;
            *)
                :
                ;;

        esac              
    done
}

# Utility function used to record add/remove project file to shortlist so history can be viewed.
save_action_shortlisted() {
    local proj_path="$1"
    local action="$2"

    # Ensure $SHORTLISTED_HISTORY file exists
    touch "$SHORTLISTED_HISTORY"

    # Get current timestamp
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Append timestamp, action, and project path to the history file
    echo "[$timestamp] $action $proj_path" >> "$SHORTLISTED_HISTORY"
}

add_to_shortlist() {
    add_item_to_shortlist() {
        # Check if projects database exists and has entries
        [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]] && {
            whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 </dev/tty >/dev/tty
            return 1
        }

        # FIX: ADD FILTERING
        # Read all projects into array
        local lines=()    
        mapfile -d '' -t lines < <(filter_projects_by_name)		# get filtered lines from utility function. \0 delimited.

        local menu_options=()
        local title line lineno
        for line in "${lines[@]}"; do
            IFS='|' read -r title _ _ <<< "$line"
            lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1)

            # Store matching index from PROJECTS_DB file.
            [[ -n "$lineno" ]] && menu_options+=($((lineno-1)) "$title")
        done
        # END FIX.

        # Paginate menu options
        paginate_get_projects "Select Project" "${menu_options[@]}"
        local selected_index
        selected_index="$SELECTED_ITEM_PROJECT"
        [[ -z "$selected_index" ]] && return 1

        # DIRTY FIX: OVERWRITE LINES TO CONTAIN ALL LINES FROM PROJECTS_DB.
        mapfile -t lines < "$PROJECTS_DB"

        # Parse selected project
        local old_title old_path old_notes
        IFS='|' read -r old_title old_path old_notes <<< "${lines[$selected_index]}"

        echo "$old_path"
    }

    # Ensure file exists
    touch "$PROJECTS_DB_SHORTLISTED"

    local choice new_item
    local page=0
    local page_size=50 # a common optimal page size.

    while true; do
        # Read shortlisted projects
        mapfile -t shortlisted < "$PROJECTS_DB_SHORTLISTED"

        local total=${#shortlisted[@]}
        local max_page=0
        (( total > 0 )) && max_page=$(( (total - 1) / page_size ))

        (( page < 0 )) && page=0
        (( page > max_page )) && page=$max_page

        local start=$(( page * page_size ))
        local end=$(( start + page_size ))

        # Build menu
        local menu_items=(
            "Add item" ""
        )

        # Navigation
        (( page > 0 )) && menu_items+=( "<< Prev" "" )
        (( page < max_page )) && menu_items+=( "Next >>" "" )

        # Paginated shortlisted items (4 per page)
        for ((i=start; i<end && i<total; i++)); do
            [[ -n "${shortlisted[i]}" ]] && menu_items+=( "${shortlisted[i]}" "" )
        done

        choice=$(whiptail \
            --title "Shortlisted Projects" \
            --cancel-button "Back" \
            --menu "Page $((page+1)) of $((max_page+1))" \
            20 170 10 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            "Add item")
                new_item=$(add_item_to_shortlist)
                [[ -z "$new_item" ]] && continue

                if ! whiptail --title "Confirm" --yesno "Do you want to add this project?" 8 40; then
                    continue
                fi

                if grep -Fxq -- "$new_item" "$PROJECTS_DB_SHORTLISTED"; then
                    whiptail --title "Duplicate" \
                             --msgbox "This project is already in the shortlist:\n\n$new_item" \
                             10 70
                else
                    echo "$new_item" >> "$PROJECTS_DB_SHORTLISTED"
                    save_action_shortlisted "$new_item" "ADDED"
                fi
                ;;
            "<< Prev")
                ((page--))
                ;;
            "Next >>")
                ((page++))
                ;;
            *)
                # shortlisted item selected — currently no-op (by design)
                :
                ;;
        esac
    done
}

remove_from_shortlist() {
    touch "$PROJECTS_DB_SHORTLISTED"

    local PAGE_SIZE=50
    local offset=0
    local choice

    mapfile -t all_items < "$PROJECTS_DB_SHORTLISTED"
    local total=${#all_items[@]}

    while true; do
        local menu_items=()
        menu_items+=( "Back" "" )

        # Navigation (does NOT count toward page size)
        (( offset > 0 )) && menu_items+=( "<< Prev" "" )
        (( offset + PAGE_SIZE < total )) && menu_items+=( "Next >>" "" )

        # Paginated shortlist items
        for (( i=offset; i<offset+PAGE_SIZE && i<total; i++ )); do
            menu_items+=( "${all_items[i]}" "" )
        done

        # Page indicator
        local current_page=$(( offset / PAGE_SIZE + 1 ))
        local total_pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))

        choice=$(whiptail \
            --title "Shortlisted Projects" \
            --cancel-button "Back" \
            --menu "Select a project to remove (Page ${current_page}/${total_pages}):" \
            20 170 10 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            "Back")
                return 1
                ;;
            "<< Prev")
                (( offset -= PAGE_SIZE ))
                (( offset < 0 )) && offset=0
                ;;
            "Next >>")
                (( offset += PAGE_SIZE ))
                ;;
            *)
                if whiptail --yesno "Are you sure you want to remove:\n$choice" 10 60; then
                    sed -i "\|^$(printf '%s' "$choice" | sed 's/[&/\]/\\&/g')\$|d" "$PROJECTS_DB_SHORTLISTED"
                    save_action_shortlisted "$choice" "REMOVED"
                    whiptail --msgbox "Removed: $choice" 10 60

                    # Refresh list and clamp offset
                    mapfile -t all_items < "$PROJECTS_DB_SHORTLISTED"
                    total=${#all_items[@]}
                    (( offset >= total )) && offset=$(( total - PAGE_SIZE ))
                    (( offset < 0 )) && offset=0
                fi
                ;;
        esac
    done
}

view_shortlist_history() {
    # Ensure the history file exists
    touch "$SHORTLISTED_HISTORY"

    if [[ ! -s "$SHORTLISTED_HISTORY" ]]; then
        # File is empty, show message
        whiptail --title "Shortlisted History" --msgbox "No history yet." 10 50
    else
        # File has content, show in textbox
        local tmp_file
        tmp_file=$(mktemp)
        cat "$SHORTLISTED_HISTORY" > "$tmp_file"
        whiptail --title "Shortlisted History" --textbox "$tmp_file" 20 80 --scrolltext
        rm -f "$tmp_file"
    fi
}

trim_shortlisted_history() {
    # Ensure the file exists
    [[ -f "$SHORTLISTED_HISTORY" ]] || return

    # Keep only the last 200 lines
    tail -n 200 "$SHORTLISTED_HISTORY" > "${SHORTLISTED_HISTORY}.tmp" && mv "${SHORTLISTED_HISTORY}.tmp" "$SHORTLISTED_HISTORY"
}

do_stuff_shortlisted() {
    truncate_tag() {
        local tags="$1"
        local max_len=60    # tweak this!

        # If already within limit, print unchanged
        if (( ${#tags} <= max_len )); then
            echo "$tags"
            return
        fi

        # Split into an array (preserve tags with spaces)
        IFS=',' read -r -a arr <<< "$tags"

        local latest_tag="${arr[-1]}"
        local result=""
        local sep=""

        # Try adding tags until adding another exceeds limit
        for (( i=0; i<${#arr[@]}-1; i++ )); do
            local t="${arr[$i]}"
            local candidate="${result}${sep}${t}"

            # If not enough room even if we later add ", ..., latest_tag", stop
            local future="${candidate}, ..., ${latest_tag}"
            if (( ${#future} > max_len )); then
                break
            fi

            result="$candidate"
            sep=", "
        done

        # If we couldn't include any tags (very tight width), result may be empty
        if [[ -z "$result" ]]; then
            echo "... , ${latest_tag}"
        else
            echo "${result}, ..., ${latest_tag}"
        fi
    }

    show_note_menu() {
        local selected_project_title="$1"
        # might as well truncate it here.
        (( ${#selected_project_title} > 50 )) && selected_project_title="${selected_project_title:0:50}..."
        shift

        local note_menu_options=("$@")
        local page=0
        local per_page=50    # adjust this to my liking
        local total_items=$(( ${#note_menu_options[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local selected_note_tag=""

        while true; do
            local start=$(( page * per_page ))
            local end=$(( start + per_page ))
            if (( end > total_items )); then end=$total_items; fi

            # Build current page menu items
            local menu_items=()
            for ((i=start; i<end; i++)); do
                local idx=$(( i * 2 ))
                menu_items+=( "${note_menu_options[idx]}" "${note_menu_options[idx+1]}" )
            done

            # Add navigation options
            if (( page > 0 )); then
                menu_items+=( "<< Prev" "" )
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=( ">> Next" "" )
            fi

            # Display menu
            selected_note_tag=$(whiptail --title "Linked Notes for ${selected_project_title} (Page $((page+1))/$total_pages)" \
                --menu "Select a linked note:" 20 170 10 "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

            # Handle navigation
            case "$selected_note_tag" in
                "<< Prev") ((page--));;
                ">> Next") ((page++));;
                *) echo "$selected_note_tag"; return 0;;
            esac
        done
    }

    open_url_assoc_to_chosen_note() {
        touch "$URLS_DB"
        
        #local URLS_DB="$URLS_DB"
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls            

        # Check if URLs database exists
        if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
            whiptail --msgbox "URL database not found or empty!" 8 50 >/dev/tty
            return 1
        fi

        while true; do
            local selected_path
            [[ -n "$note_path" ]] && { selected_path="$note_path"; } || return 1

            # Extract URLs for selected note
            local urls=()
            local titles=()
            while IFS= read -r line; do
                # Only for the matched line...
                if [[ "$line" == "${selected_path}${GS}"* ]]; then
                    IFS="$RS" read -ra entries <<< "${line#*$GS}"
                    for entry in "${entries[@]}"; do
                        IFS="$US" read -r url title <<< "$entry"
                        urls+=("$url")
                        titles+=("$title")
                    done
                    break
                fi
            done < "$URLS_DB"

            if [[ ${#urls[@]} -eq 0 ]]; then
                whiptail --msgbox "No URLs found for selected note!" 8 50 >/dev/tty
                return 1                
            fi

            # URL selection loop
            [[ ${#urls[@]} -gt 0 ]] && {
                while true; do
                    local url_menu_items=("<< Back" "")
                    for i in "${!urls[@]}"; do
                        url_menu_items+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                    done

                    local choice
                    choice=$(whiptail --title "URLs for $selected_path" --menu "Choose URL to open:" \
                        20 170 10 "${url_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || return 1
                    [[ -z "$choice" ]] && return 1

                    if [[ "$choice" == "<< Back" ]]; then
                        return 1
                    elif [[ -n "${urls[$choice]}" ]]; then                
                        nohup "$URL_BROWSER" "${urls[$choice]}" >/dev/null 2>&1 &	# to make sure browser stays open
                    fi
                done
            }
        done
    }

    assoc_url_to_chosen_note() {
        touch "$URLS_DB"
        
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls

        # Extract note paths from NOTES_DB
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Error: Notes database not found or empty!" 8 50 >/dev/tty
            return 1
        fi
        
        local selected_path
        [[ -n "$note_path" ]] && { selected_path="$note_path"; } || return 1

        # Load existing URLs
        local urls=()
        local titles=()
        if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
            while IFS= read -r line; do
                if [[ "$line" == "${selected_path}${GS}"* ]]; then
                    IFS="$RS" read -ra entries <<< "${line#*$GS}"
                    for entry in "${entries[@]}"; do
                        IFS="$US" read -r url title <<< "$entry"
                        urls+=("$url")
                        titles+=("$title")
                    done
                    break
                fi
            done < "$URLS_DB"
        fi

        local url_regex='^(https?:\/\/)?(www\.)?([a-zA-Z0-9-]+\.)+[A-Za-z]{2,}(:[0-9]+)?(\/\S*)?$'

        # URL management loop
        while true; do
            local menu_options=("Register URL" "" "Save and return" "")
            for i in "${!urls[@]}"; do
                menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 170 10 "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
            [[ -z "$choice" ]] && return 1

            case "$choice" in
                "Register URL")
                    local new_url new_title
                    new_url=$(whiptail --inputbox "Enter URL:" 8 50 3>&1 1>&2 2>&3)
                    [[ $? -ne 0 ]] && continue

                    # validate URL
                    if [[ ! $new_url =~ $url_regex ]]; then
                        whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
                        continue
                    fi

                    new_title=$(whiptail --inputbox "Enter URL title:" 8 50 3>&1 1>&2 2>&3)
                    [[ $? -ne 0 ]] && continue

                    if [[ -z "$new_url" || -z "$new_title" ]]; then
                        whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                        continue
                    fi

                    urls+=("$new_url")
                    titles+=("$new_title")
                    ;;

                "Save and return")
                    # Construct new entry
                    local new_entry="${selected_path}${GS}"
                    for i in "${!urls[@]}"; do
                        new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                    done
                    new_entry="${new_entry%$RS}"

                    # Update URLS_DB
                    local temp_file
                    temp_file=$(mktemp) || return 1
                    if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
                        # Write every line except for selected path to temp file.
                        while IFS= read -r line; do
                            [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                        done < "$URLS_DB" > "$temp_file"
                    fi
                    # Add new entry at the end of the temp file.
                    echo "$new_entry" >> "$temp_file"

                    # Replace original file
                    mv "$temp_file" "$URLS_DB"
                    whiptail --msgbox "URL associations saved successfully!" 8 50 >/dev/tty
                    return 0
                    ;;

                *)
                    # Handle existing URL selection
                    local index="$choice"
                    if [[ ! -v urls[index] ]]; then
                        whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                        continue
                    fi

                    # Submenu for edit/delete
                    local sub_choice
                    sub_choice=$(whiptail --menu "Manage URL" 20 60 10 \
                        "Change values" "" \
                        "Delete URL" "" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                    [[ -z "$sub_choice" ]] && continue

                    case "$sub_choice" in
                        "Change values")
                            local current_url="${urls[index]}"
                            local current_title="${titles[index]}"
                            new_url=$(whiptail --inputbox "Edit URL:" 8 50 "$current_url" 3>&1 1>&2 2>&3)
                            [[ $? -ne 0 ]] && continue

                            # validate URL
                            if [[ ! $new_url =~ $url_regex ]]; then
                                whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
                                continue
                            fi

                            new_title=$(whiptail --inputbox "Edit URL title:" 8 50 "$current_title" 3>&1 1>&2 2>&3)
                            [[ $? -ne 0 ]] && continue

                            if [[ -z "$new_url" || -z "$new_title" ]]; then
                                whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                                continue
                            fi

                            urls[index]="$new_url"
                            titles[index]="$new_title"
                            ;;
                        "Delete URL")
                            unset 'urls[index]'
                            unset 'titles[index]'
                            # Reindex arrays
                            urls=("${urls[@]}")
                            titles=("${titles[@]}")
                            ;;
                    esac
                    ;;
            esac
        done
    }    

    dissoc_url_from_chosen_note() {
        touch "$URLS_DB"
        
        #local URLS_DB="$URLS_DB"
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls

        # Check URL database existence
        if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
            whiptail --msgbox "Error: URLs database not found or empty!" 8 50 >/dev/tty
            return 1
        fi

        local selected_path
        [[ -n "$note_path" ]] && { selected_path="$note_path"; } || return 1

        # Load existing URLs
        local urls=()
        local titles=()
        while IFS= read -r line; do
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"

        # URL removal loop
        while true; do
            local menu_options=("Remove URL" "" "Save and return" "")
            for i in "${!urls[@]}"; do
                menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 170 10 \
                "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
            [[ -z "$choice" ]] && continue

            case "$choice" in
                "Remove URL")
                    if [[ ${#urls[@]} -eq 0 ]]; then
                        whiptail --msgbox "No URLs to remove!" 8 50 >/dev/tty
                        continue
                    fi

                    # Create removal submenu
                    local remove_menu=()
                    for i in "${!urls[@]}"; do
                        remove_menu+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                    done

                    local remove_index
                    remove_index=$(whiptail --menu "Select URL to remove" 20 170 10 \
                        "${remove_menu[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                    [[ -z "$remove_index" ]] && continue

                    # Validate and remove selected URL
                    if [[ -v "urls[$remove_index]" ]]; then
                        unset 'urls[$remove_index]'
                        unset 'titles[$remove_index]'
                        urls=("${urls[@]}")  # Reindex array
                        titles=("${titles[@]}")
                    else
                        whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                    fi
                    ;;

                "Save and return")
                    # Prepare new entry
                    local new_entry="${selected_path}${GS}"
                    for i in "${!urls[@]}"; do
                        new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                    done
                    new_entry="${new_entry%$RS}"

                    # Update database
                    local temp_file=$(mktemp) || return 1
                    {
                        # Copy existing entries except current note
                        while IFS= read -r line; do
                            [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                        done < "$URLS_DB"
                        
                        # Add updated entry if URLs remain
                        [[ -n "$new_entry" ]] && echo "$new_entry"
                    } > "$temp_file"

                    mv "$temp_file" "$URLS_DB"
                    whiptail --msgbox "URL associations updated!" 8 50 >/dev/tty
                    return 0
                    ;;

                *)
                    # Ignore URL index selections
                    continue
                    ;;
            esac
        done
    }

    associate_chosen_note_to_project() {
        # Get note path from arg
        local note_path="$1"
        [[ -z "$note_path" ]] && return 1

        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        # FIX: ALLOW FILTERING BY GLOB.
        # Get pattern from user using whiptail
        local pattern
        pattern=$(whiptail --inputbox "Enter filename glob pattern to filter projects (empty for wildcard):" 10 60 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        : "${pattern:=*}"	# default to * if unset.

        # Enable case-insensitive glob matching
        shopt -s nocasematch
        
        local project_menu_options=()
        local filename title path rest
        while IFS='|' read -r title path rest; do
            # Extract filename from path
            filename=$(basename "$path")
            
            # Check if filename matches the pattern (now case-insensitive)
            if [[ "$filename" == $pattern ]]; then
                project_menu_options+=("$path" "")
            fi
        done < "$PROJECTS_DB"
        
        # Restore default case sensitivity
        shopt -u nocasematch

        # If no matches found, show message and exit
        if [ ${#project_menu_options[@]} -eq 0 ]; then
            whiptail --msgbox "No projects matched the pattern '${pattern}'" 8 40 >/dev/tty
            return 1
        fi
        # END FIX.

        # Project selection
        paginate_get_projects "Select Project" "${project_menu_options[@]}"
        local selected_project_path
        selected_project_path="$SELECTED_ITEM_PROJECT"
        [[ -z "$selected_project_path" ]] && return 1

        # User already chosen $note_path as chosen note file.
        local selected_note_path
        selected_note_path="$note_path"

        [[ -z "$selected_note_path" ]] && return 1

        # Process PROJECTS_DB
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                #echo >> "$temp_file"
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                return 1
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                return 1
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            return 1
        fi
    }

    print_chosen_note() {
        print_file_from_do_stuff_project() {
            # Check if file argument is provided
            if [ -z "$1" ]; then
                return 1
            fi

            local file_to_print="$1"

            # Check if file exists
            if [ ! -f "$file_to_print" ]; then
                echo "Error: File '$file_to_print' does not exist." >&2
                return 1
            fi

            # Get list of printers
            local printers
            printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')            

            # Edge case: no printers found.
            [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

            # Convert printer list into whiptail menu format
            local menu_items=()
            for p in $printers; do
                menu_items+=("$p" "")
            done

            # Show whiptail menu to select printer
            local selected_printer
            selected_printer=$(whiptail --title "Select Printer" \
                --menu "Choose a printer:" 20 60 10 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            # Check if user cancelled
            if [ $? -ne 0 ]; then
                return 1
            fi

            # Print the file
            if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
                lpr -P "$selected_printer" "$file_to_print"
                if [ $? -eq 0 ]; then
                    whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
                else
                    whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                    return 1
                fi            
            else
                :  # do nothing if No or Cancel
            fi
        }

        local selected_path="$1"       
        print_file_from_do_stuff_project "$selected_path"
    }

    # Receives project path and echos matching whole line from PROJECTS_DB file.
    lookup_shortlist_item_from_proj_db() {
        local path="$1"
        local line

        # Use awk to match the second field (| as delimiter) with the given path
        line="$(awk -F'|' -v p="$path" '$2 == p {print; exit}' "$PROJECTS_DB")"

        echo "$line"
    }

    associate_new_note_to_project_from_shortlist() {
        # note path is the new note you've just created from select notes menu.
        local NEW_NOTE_PATH="$note_path"
        [[ -z "$NEW_NOTE_PATH" ]] && return 1

        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        local selected_project_path
        selected_project_path="$1"
        [[ -z "$selected_project_path" ]] && return 1

        local selected_note_path="$NEW_NOTE_PATH"

        # WE'VE SELECTED PROJECT FILE AND NOTE FILE AT THIS POINT!!!!

        # Process PROJECTS_DB - update each line (only change line of selected project file)
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then set duplicate and break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                return 1
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                return 1
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            return 1
        fi
    }

    associate_note_to_project_from_shortlist() {
        paginate_tags_menu() {
            local title="$1"
            shift
            local items=("$@")
            local per_page=20
            local total_items=$(( ${#items[@]} / 2 ))
            local total_pages=$(( (total_items + per_page - 1) / per_page ))
            local current_page=1
            local choice start_index end_index menu_items tag desc

            while true; do
                # Calculate start and end indices for current page
                start_index=$(( (current_page - 1) * per_page * 2 ))
                end_index=$(( start_index + per_page * 2 ))
                menu_items=()

                # Add items for current page
                for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                    tag="${items[i]}"
                    desc="${items[i+1]}"
                    menu_items+=("$tag" "$desc")
                done

                # Add navigation options
                if (( current_page > 1 )); then
                    menu_items+=("<< Prev" "")
                fi
                if (( current_page < total_pages )); then
                    menu_items+=(">> Next" "")
                fi

                # Show whiptail menu
                choice=$(whiptail --title "$title" \
                    --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                    "${menu_items[@]}" 3>&1 1>&2 2>&3)

                [[ $? -ne 0 ]] && return 1  # Cancel pressed

                case "$choice" in
                    ">> Next")
                        (( current_page++ ))
                        ;;
                    "<< Prev")
                        (( current_page-- ))
                        ;;
                    *)
                        # Return selected tag
                        printf '%s\n' "$choice"
                        return 0
                        ;;
                esac
            done
        }

        #local PROJECTS_DB="$PROJECTS_DB"
        #local NOTES_DB="$NOTES_DB"
        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        local selected_project_path
        selected_project_path="$1"
        [[ -z "$selected_project_path" ]] && return 1

        # FIX: FILTER BY TAG AND PAGINATE TAG SELECTION.
        local note_tag_options=("ANY TAG" "Any tag (no filter)")    

        while IFS= read -r tag; do
            [[ -n "$tag" ]] && note_tag_options+=("$tag" "")
        done < "$NOTES_TAGS_DB"

        local selected_note_tag
        selected_note_tag="$(paginate_tags_menu "Select Note Tag to Filter Notes" "${note_tag_options[@]}")" || return 1

        # Read notes into menu
        local note_menu_options=()
        local note_tags_arr
        while IFS='|' read -r note_title note_path note_tags rest; do
            # handle case when line has no associated tag yet. include its note path if ANY TAG was selected.
            if [[ "$selected_note_tag" == "ANY TAG" ]]; then
                note_menu_options+=("$note_path" "[${note_tags}]")
                continue
            fi

            # FIX: FILTER BY NOTE TAG
            IFS=',' read -r -a note_tags_arr <<< "$note_tags"

            # only enters here if line already has a tag
            for tag in "${note_tags_arr[@]}"; do
                if [[ "${tag,,}" == "${selected_note_tag,,}" || "$selected_note_tag" == "ANY TAG" ]]; then
                    note_menu_options+=("$note_path" "[${note_tags}]")
                    break
                fi
            done

            #note_menu_options+=("$note_path" "[${note_tags}]")
        done < "$NOTES_DB"
        if [[ "${#note_menu_options[@]}" -eq 0 ]]; then
            whiptail --msgbox "No notes available in the database." 20 50
            return 1
        fi

        while :; do
            # Note selection
            paginate_get_projects "Choose Note to Associate" "${note_menu_options[@]}"
            local selected_note_path
            selected_note_path="$SELECTED_ITEM_PROJECT"
            [[ -z "$selected_note_path" ]] && return 1

            #local selected_note_path
            #selected_note_path=$(whiptail --title "Select Note" \
            #    --menu "Choose a note to associate:" \
            #    25 150 15 "${note_menu_options[@]}" 3>&1 1>&2 2>&3)
            #[[ -z "$selected_note_path" ]] && return 1  # User canceled

            # Process PROJECTS_DB
            while IFS= read -r line; do
                if [[ -z "$line" ]]; then
                    #echo >> "$temp_file"
                    continue
                fi

                IFS='|' read -r title path notes <<< "$line"
                # If there is matched line...
                if [[ "$path" == "$selected_project_path" ]]; then
                    project_found=1
                    current_notes="$notes"
                    local notes_array=()

                    # Check for duplicates
                    IFS=',' read -ra notes_array <<< "$current_notes"
                    local duplicate=0	# Reset for each iteration.
                    # If duplicate found then break out of for loop here.
                    for note in "${notes_array[@]}"; do
                        [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                    done

                    if (( duplicate )); then
                        whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                        # reset
                        line_updated=0

                        duplicate_detected=1
                        # Rebuild original line
                        new_line="$title|$path|$current_notes"
                        # There is no fourth field!!!!
                        # [[ -n "$rest" ]] && new_line+="|$rest"
                        echo "$new_line" >> "$temp_file"	# No change.
                    else
                        # reset
                        duplicate_detected=0

                        # Update notes
                        # If there is no previously associated note...
                        if [[ -z "$current_notes" ]]; then
                            new_notes="$selected_note_path"
                        else
                            new_notes="$current_notes,$selected_note_path"
                        fi
                        new_line="$title|$path|$new_notes"
                        #[[ -n "$rest" ]] && new_line+="|$rest"
                        echo "$new_line" >> "$temp_file"	# Changes made.
                        line_updated=1
                    fi
                else
                    # Just leave the line unchanged.
                    echo "$line" >> "$temp_file"
                fi
            done < "$PROJECTS_DB"

            # Handle processing results
            if (( project_found )); then
                if (( line_updated && !duplicate_detected )); then
                    mv "$temp_file" "$PROJECTS_DB"
                    whiptail --msgbox "Note successfully associated with the project." 10 50
                elif (( duplicate_detected )); then
                    rm "$temp_file"
                    #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                    continue
                else
                    rm "$temp_file"
                    whiptail --msgbox "No changes were made to the project entry." 10 50
                    continue
                fi
            else
                rm "$temp_file"
                whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
                continue
            fi
        done
    }

    dissociate_note_from_project_from_shortlist() {
        find_tags_for_linked_note() {
            local path_to_note_file="$1"
            local matching_tags_str=""

            # Ensure NOTES_DB is defined and exists
            if [[ -z "$NOTES_DB" || ! -f "$NOTES_DB" ]]; then
                echo "Error: NOTES_DB not defined or file not found." >&2
                return 1
            fi

            # Extract the tags (3rd field) for the matching note
            matching_tags_str=$(awk -F'|' -v path="$path_to_note_file" '$2 == path {print $3}' "$NOTES_DB")

            echo "$matching_tags_str"
        }

        # Check if database exists
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Error: PROJECTS_DB file '$PROJECTS_DB' not found or empty." 10 60 >/dev/tty
            return 1
        fi

        # Load full DB lines for editing later
        mapfile -t lines < "$PROJECTS_DB"

        local selected_project_path="$1"

        local selected_project=$(awk -F'|' -v path="$selected_project_path" '$2 == path { print NR; exit }' "$PROJECTS_DB")
        [[ -z "$selected_project" ]] && return 1
        ((selected_project--))

        local line="${lines[selected_project]}"
        IFS='|' read -r title path notes <<< "$line"

        # Begin dissociation loop
        while true; do
            if [[ -z "$notes" ]]; then
                whiptail --msgbox "Selected project has no associated notes." 10 60 >/dev/tty
                return 1
            fi

            # Split notes into array
            local -a notes_arr
            IFS=',' read -ra notes_arr <<< "$notes"

            if [[ ${#notes_arr[@]} -eq 0 ]]; then
                whiptail --msgbox "No notes left to dissociate." 10 60 >/dev/tty
                return 1
            fi

            # Build menu options (add << Back at top)
            local -a note_options=("<< Back" "")
            local note_index note_matching_tags
            for note_index in "${!notes_arr[@]}"; do
                note_matching_tags="$(find_tags_for_linked_note "${notes_arr[note_index]}")"
                note_options+=("$note_index" "${notes_arr[note_index]} [${note_matching_tags}]")
            done

            # Show note selection menu
            paginate_get_projects "Choose Note to Dissociate" "${note_options[@]}"
            local selected_note="$SELECTED_ITEM_PROJECT"

            # If user chooses << Back, stop loop
            [[ -z "$selected_note" || "$selected_note" == "<< Back" ]] && return 1

            # Remove selected note from list
            local -a new_notes=()
            for note_index in "${!notes_arr[@]}"; do
                if [[ $note_index -ne $selected_note ]]; then
                    new_notes+=("${notes_arr[note_index]}")
                fi
            done

            # Join remaining notes into CSV
            local new_notes_str=""
            if [[ ${#new_notes[@]} -gt 0 ]]; then
                new_notes_str=$(IFS=','; printf '%s' "${new_notes[*]}")
            fi

            # Update database entry in memory
            lines[selected_project]="$title|$path|$new_notes_str"
            notes="$new_notes_str"  # Update current project notes for next loop

            # Write database back to file
            local tmp_db
            tmp_db=$(mktemp) || return 1
            printf "%s\n" "${lines[@]}" > "$tmp_db"
            mv -- "$tmp_db" "$PROJECTS_DB" || { rm -- "$tmp_db"; return 1; }

            whiptail --msgbox "Note successfully dissociated from project." 10 60 >/dev/tty

            # If no notes left, exit loop automatically
            [[ -z "$notes" ]] && {
                whiptail --msgbox "All notes have been dissociated from this project." 10 60 >/dev/tty
                break
            }
        done
    }

    # Populate menu with current shortlist
    local projects=()
    mapfile -t projects < "$PROJECTS_DB_SHORTLISTED"

    local project_menu_options=("<< Back" "")
    local p title line lineno
    for p in "${projects[@]}"; do
        # Get the matching line.
        line="$(lookup_shortlist_item_from_proj_db "$p")"

        IFS='|' read -r title _ _ <<< "$line"
        lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1)

	    # Store matching index from PROJECTS_DB file.
        [[ -n "$lineno" ]] && project_menu_options+=("$lineno" "$title")
    done

    mapfile -t projects < "$PROJECTS_DB"	# DIRTY FIX.
    # END FIX.

    # Show project selection
    paginate_get_projects "Select Project" "${project_menu_options[@]}"
    local selected_project_tag
    selected_project_tag="$SELECTED_ITEM_PROJECT"
    [[ -z "$selected_project_tag" || "$selected_project_tag" == "<< Back" ]] && return 1

    # FIX: WHILE LOOP TO ALLOW MULTIPLE LINKED NOTE SELECTIONS
    while :; do
        # Refresh linked notes list at the start of each iteration.
        mapfile -t projects < "$PROJECTS_DB"    # Reload from PROJECTS DB file.
        local selected_project_index=$((selected_project_tag - 1))
        local selected_project_line="${projects[$selected_project_index]}"

        local selected_project_title selected_project_path associated_notes
        IFS='|' read -r selected_project_title selected_project_path associated_notes <<< "$selected_project_line"

        # Process associated notes
        local note_paths=()
        IFS=',' read -ra note_paths <<< "$associated_notes"
        local note_lines=() 
        local note_menu_options=()

        # Add option 'Create new linked note' first
        note_menu_options+=("Create new linked note" "")
        note_menu_options+=("Link note" "")
        note_menu_options+=("Unlink note" "")

        local trunc_tag
        for np in "${note_paths[@]}"; do
            while IFS= read -r line; do
                IFS='|' read -r title path tags _ <<< "$line"
                if [ "$path" = "$np" ]; then
                    note_lines+=("$line")

                    # truncate tag string
                    trunc_tag="$(truncate_tag "$tags")"

                    note_menu_options+=("${#note_lines[@]}" "$title [${trunc_tag}]")
                    break
                fi
            done < "$NOTES_DB"
        done        
        # Refresh code end.

        # FIX: PAGINATE LINKED NOTE SELECTION
        local selected_note_tag
        selected_note_tag="$(show_note_menu "$selected_project_title" "${note_menu_options[@]}")" || return 1

        # Handle case when user selects "Create new lnked note".
        if [[ "$selected_note_tag" == "Create new linked note" ]]; then
            add_note || continue
            associate_new_note_to_project_from_shortlist "$selected_project_path"
            continue    # Continue since we need to update the linked notes list now.
        elif [[ "$selected_note_tag" == "Link note" ]]; then
            associate_note_to_project_from_shortlist "$selected_project_path" || continue
            continue    # Display list of linked notes again after associating a note.
        elif [[ "$selected_note_tag" == "Unlink note" ]]; then
            dissociate_note_from_project_from_shortlist "$selected_project_path" || continue
            continue    # Display list of lined notes again after dissociating notes.
        fi

        local selected_note_index=$((selected_note_tag - 1))
        local selected_note_line="${note_lines[$selected_note_index]}"

        # Action selection
        local action
        action=$(whiptail --menu "Note Action" 20 50 8 \
            "1" "View Note" \
            "2" "Open ebooks linked to note" \
            "3" "Edit Note" \
            "4" "Open linked URL" \
            "5" "Associate URL to note" \
            "6" "Dissociate URL from note" \
            "7" "Associate Note to Project" \
            "8" "Print Note using Printer" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue    # i want to return to list of linked note files so continue

        case "$action" in
            "1")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                #whiptail --scrolltext --title "$note_title" --textbox "$note_path" 35 150
                
                # FIX: USE DIALOG INSTEAD BECAUSE WHIPTAIL FAILS HERE.
                # Specifically, \n \t etc gets translated.
                # Match the colors with whiptail as best as possible.
                DIALOG_CONFIG="use_colors = ON
                screen_color = (BLACK,MAGENTA,OFF)
                dialog_color = (BLACK,WHITE,OFF)
                title_color = (RED,WHITE,OFF)
                border_color = (WHITE,WHITE,OFF)
                button_active_color = (WHITE,RED,OFF)"                                    
                #DIALOGRC=<(echo -e "$DIALOG_CONFIG") dialog --exit-label "Back" --title "$note_title" --textbox "$note_path" 35 150
                # Word wrap width 145
                local tmpfile=$(mktemp)
                fold -s -w 145 "$note_path" > "$tmpfile"
                DIALOGRC=<(echo -e "$DIALOG_CONFIG") dialog --no-mouse --exit-label "Back" --title "$note_title" --textbox "$tmpfile" 35 150
                rm -f "$tmpfile"
                clear
                ;;
            "2")
                open_note_ebook_page_from_project "$selected_note_line"
                ;;
            "3")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                edit_note "$note_path"
                ;;
            "4")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                open_url_assoc_to_chosen_note
                ;;
            "5")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                assoc_url_to_chosen_note
                ;;
            "6")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                dissoc_url_from_chosen_note
                ;;
            "7")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                associate_chosen_note_to_project "$note_path"
                ;;
            "8")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                print_chosen_note "$note_path"
                ;;
        esac
    done
}

do_stuff_with_shortlisted() {
    # Just keep the last 200 lines of history file.
    trim_shortlisted_history

    while true; do
        local choice
        choice=$(whiptail --title "Shortlisted Projects Menu" \
            --menu "Choose an action:" 15 50 6 \
            "1" "Do stuff" \
            "2" "Add to shortlist" \
            "3" "Remove from shortlist" \
            "4" "View history" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            1)
                do_stuff_shortlisted
                ;;
            2)
                add_to_shortlist
                ;;
            3)
                remove_from_shortlist
                ;;
            4)
                view_shortlist_history
                ;;
        esac
    done
}

show_projects_menu() {
    while true; do
	local choice
        choice=$(whiptail --title "Goals Management" --cancel-button "Back" --menu "Choose an option:" 20 60 10 \
            "1" "Add New Project" \
            "2" "Edit Existing Project" \
            "3" "Print Project Content on Screen" \
            "4" "Associate Note with Project" \
            "5" "Dissociate Note with Project" \
            "6" "Do Stuff with Linked Notes in Project File" \
            "7" "Open URL from Linked Notes in Project File" \
            "8" "Do Stuff with Shortlisted Projects" \
            "9" "Delete Project" \
            "10" "Print Project using Printer" 3>&1 1>&2 2>&3) || return 1

        case $choice in
            1)
                add_project
                ;;
            2)
                edit_project
                ;;
            3)
                print_project
                ;;
            4)
                associate_note_to_project
                ;;
            5)
                dissociate_note_from_project
                ;;
            6)
                do_stuff_with_project_file
                ;;
            7)
                open_url_assoc_to_note_from_project
                ;;
            8)
                do_stuff_with_shortlisted
                ;;
            9)
                delete_project
                ;;
            10)
                print_project_to_printer_from_main
                ;;
            *)
                return 1
                ;;
        esac
    done
}

##############################
# Back up code starts here
###############################

# Files and globs to include in the backup
readonly BACKUP_ENTRIES=(
  "ebooks.db"
  "ebooks.db.backup"
  "ebooks.db.rename.log"
  "tags.db"
  "notes/*.txt"
  "notes/metadata/notes.db"
  "notes/metadata/notes-ebooks.db"
  "notes/metadata/notes-tags.db"
  "projects/*.txt"
  "projects/metadata/projects.db"
  "projects/metadata/projects.db.shortlisted"
  "projects/metadata/projects.db.shortlisted.history"
  "urls/urls.db"
)

# backup_db [output_file]
# Creates a tar.gz of all matching entries in $PWD,
# quietly skipping any that don’t exist.
backup_db() {
  local out="${1:-backup_$(date +%Y%m%d_%H%M%S).tar.gz}"
  local -a files=()

  # Inform user about backup
  whiptail --title "Backup Database" --yesno \
    "This function will backup all database files plus all note files and project files. Do you want me to do backup now?" \
    10 60 || return 1

  # Enable nullglob so unmatched globs disappear instead of staying literal
  shopt -s nullglob
  for pattern in "${BACKUP_ENTRIES[@]}"; do
    for f in $pattern; do
      files+=("$f")
    done
  done
  shopt -u nullglob

  if (( ${#files[@]} == 0 )); then
    whiptail --title "Backup Database" --msgbox \
      "No files found to back up." \
      8 40
    return 1
  fi

  # Create backup
  if tar --ignore-failed-read -czvf "$out" "${files[@]}" &> /dev/null; then
    whiptail --title "Backup Database" --msgbox \
      "Backup complete. (${#files[@]} items archived)\nArchive: $out" \
      10 60
  else
    whiptail --title "Backup Database" --msgbox \
      "Error occurred during backup." \
      8 40
    return 2
  fi
}

# restore_db
# Lets user choose a backup archive to restore into $PWD
restore_db() {
    show_menu() {
        local menu_items=("$@")   # copy array elements
        local total_items=${#menu_items[@]}
        local items_per_page=10
        local total_pages=$(( (total_items + items_per_page*2 - 1) / (items_per_page*2) ))  # ceil division
        local page=0
        local choice

        while true; do
            local start=$((page * items_per_page * 2))
            local end=$((start + items_per_page * 2))
            local page_items=("${menu_items[@]:$start:$((items_per_page * 2))}")

            local menu_list=()
            menu_list+=("${page_items[@]}")            
            (( end < total_items )) && menu_list+=(">> Next" "")
            (( page > 0 )) && menu_list+=("<< Prev" "")

            choice=$(whiptail --title "Restore Database (Page $((page+1))/$total_pages)" \
                --menu "Choose an archive to restore:" 20 78 12 \
                "${menu_list[@]}" \
                3>&1 1>&2 2>&3) || return 1            

            case "$choice" in
                ">> Next") ((page++)) ;;
                "<< Prev") ((page--)) ;;
                *) echo "$choice"; return 0 ;;
            esac
        done
    }

  # Inform user about restore
  whiptail --title "Restore Database" --msgbox \
    "This function will let you choose a backup file to restore." \
    10 60

  # Collect backup files
  local archives=(backup_*.tar.gz)
  if (( ${#archives[@]} == 0 )) || [[ "${archives[0]}" == "backup_*.tar.gz" ]]; then
    whiptail --title "Restore Database" --msgbox \
      "No backup archives found in the current directory." \
      8 40
    return 1
  fi

  # Build menu items: tag each with index
  local menu_items=()
  for idx in "${!archives[@]}"; do
    menu_items+=("$idx" "${archives[$idx]}")
  done

#   # Show menu
#   local choice
#   choice=$(whiptail --title "Restore Database" --menu \
#     "Select an archive to restore:" 15 60 6 \
#     "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

  # FIX: PAGINATE SELECT ARCHIVE
  local choice
  choice="$(show_menu "${menu_items[@]}")" || return 1

  local selected_archive="${archives[$choice]}"

  # Ask user for the last time
  whiptail --title "Restore Database" --yesno \
    "Are you sure you want to restore the selected backup file?" \
    10 60 || return 1
    
  # DEBUG
  #echo tar -xzvf "$selected_archive" -C .
  #exit

  # Perform restore
  if tar -xzvf "$selected_archive" -C . &> /dev/null; then
    whiptail --title "Restore Database" --msgbox \
      "Restore complete. Files from $selected_archive have been extracted." \
      10 60
  else
    whiptail --title "Restore Database" --msgbox \
      "Error occurred during restore of $selected_archive." \
      8 40
    return 2
  fi
}

################################
# HELP
################################

# Help in sections.
show_help() {
    while true; do
        CHOICE=$(whiptail --title "Babyrus Help Menu" --cancel-button "Back" \
            --menu "Select a help topic:" 20 60 10 \
            "1" "Help: Manage eBooks" \
            "2" "Help: Manage Notes" \
            "3" "Help: Manage Goals" \
            "4" "Help: Configure" \
            "5" "Help: Help" \
            "6" "Help: Backup" \
            "7" "Help: Restore" 3>&1 1>&2 2>&3)

        exitstatus=$?
        if [ $exitstatus != 0 ]; then
            break
        fi

        case $CHOICE in
            1)
                whiptail --scrolltext --title "Manage eBooks" --cancel-button "Back" --msgbox "\
MANAGE EBOOKS / FILE MANAGEMENT / REGISTER FILE(S)
==================================================

ADD FILES IN BULK:
  - Register many files at once.
  - Steps:
    1. Select a root directory (recursive).
    2. Enter a search string to filter files by name.
    3. All matching files are added to the ebooks database.
  * Best for: Quickly registering a large set of files.

REGISTER EBOOK:
  - Register a single ebook file.
  - Steps:
    1. Enter a search string to filter by file name.
    2. Select a root directory (recursive).
    3. Choose a file from the matching list.
  * Best for: Finding and registering one specific file.

REGISTER EBOOKS FROM CHECKLIST:
  - Manually browse and select multiple files.
  - Steps:
    1. Open the checklist view.
    2. Traverse directories.
    3. Mark the files to register.
    4. Also mark '__add__' to confirm.
  * Best for: Picking files manually without search.

MANAGE EBOOKS / FILE MANAGEMENT / DEREGISTER FILE(S)
====================================================

REMOVE REGISTERED EBOOK:
  - Deregister a single ebook file.
  - Steps:
    1. Enter a search string to filter by file name.
    2. Choose a file from the matching list.
    3. Confirm to deregister.
  * Best for: Removing one specific ebook from the database.

REMOVE EBOOKS FROM CHECKLIST:
  - Deregister multiple files using a checklist.
  - Steps:
    1. Enter a search string to filter by file name.
    2. Wait for the checklist to appear.
    3. Select the files you want removed.
    4. Select '__proceed__' at the same time to confirm removal.
  * Best for: Removing multiple files manually.

REMOVE FILES IN BULK:
  - Deregister multiple files at once.
  - Steps:
    1. Enter a search string to filter by file name.
    2. Enter a search string to filter by tag name.
    3. Matching files are selected for bulk removal.
    4. Confirm removal.
  * Best for: Quickly deregistering many files matching criteria.

REMOVE FILES BY FILEPATH:
  - Deregister all files under a selected path (non-recursive).
  - Files with tags will NOT be removed.
  - Steps:
    1. Select a path from the menu.
    2. Confirm removal.
  * Best for: Removing all files in a specific directory without touching subdirectories.

REMOVE FILES BY FILEPATH RECURSIVELY:
  - Deregister all files under a selected path, including subdirectories.
  - Files with tags will NOT be removed.
  - Steps:
    1. Select a path from the menu.
    2. Confirm removal.
  * Best for: Removing all files in a directory tree except those with tags.

MANAGE EBOOKS / TAG MANAGEMENT / REGISTER TAG
=============================================

REGISTER TAG:
  - Create a new tag to associate with ebook(s).
  - Steps:
    1. Enter a name for the new tag when prompted.
  * Best for: Setting up a new tag to organize ebooks.

MANAGE EBOOKS / TAG MANAGEMENT / ASSOCIATE TAG
==============================================

ASSOCIATE TAG WITH EBOOK:
  - Associate a tag with a single registered ebook.
  - Steps:
    1. Enter a search string to filter by file name.
    2. Choose a file from the matching list.
    3. Choose a tag from the list of registered tags.
    4. The chosen tag is associated with the selected file.
  * Best for: Adding a tag to one specific ebook.

ASSOCIATE TAG FROM CHECKLIST:
  - Associate a tag with multiple files using a checklist.
  - Steps:
    1. Choose a tag from the list of registered tags.
    2. Enter a search string to filter by file name.
    3. Select files from the checklist.
    4. Also select '__proceed__' to confirm.
  * Best for: Tagging many files manually in one go.

ASSOCIATE TAG TO BULK:
  - Associate a tag with a large number of files automatically.
  - Steps:
    1. Choose a tag from the list of registered tags.
    2. Enter a search string to filter by file name.
    3. Enter a search string to filter by tag name.
    4. Review the candidate files in the message box.
    5. Confirm to apply the tag to all listed files.
  * Best for: Quickly tagging many files that meet specific criteria.

ASSOCIATE TAG BY FILEPATH:
  - Associate a tag with every file under a chosen directory.
  - Steps:
    1. Choose a tag from the list of registered tags.
    2. Select a directory where registered files are located.
    3. Confirm to associate the tag with every file in that directory.
  * Best for: Applying a tag across all files in a directory.

MANAGE EBOOKS / TAG MANAGEMENT / DISSOCIATE TAG
===============================================

DISSOCIATE TAG FROM REGISTERED EBOOK:
  - Remove a tag from a single registered ebook.
  - Steps:
    1. Enter a search string to filter by file name.
    2. Choose a file from the matching list.
    3. Choose a tag from the file's associated tags.
    4. Confirm to dissociate.
  * Best for: Removing one tag from one ebook.

DISSOCIATE TAG FROM CHECKLIST:
  - Remove a tag from multiple files using a checklist.
  - Steps:
    1. Choose a tag from the list of registered tags.
    2. Babyrus shows all matching files in a checklist.
    3. Select the files you want to dissociate the tag from.
    4. Also select '__proceed__' to confirm.
  * Best for: Manually dissociating a tag from many files.

DISSOCIATE TAG FROM BULK:
  - Remove a tag from many files automatically.
  - Steps:
    1. Choose a tag from the list of registered tags.
    2. Enter a search string to filter by file name.
    3. Enter a search string to filter by tag name.
    4. Review candidate files shown in the message box.
    5. Confirm to remove the tag from all candidate files.
  * Best for: Quickly clearing a tag from many files at once.

DISSOCIATE TAG BY FILEPATH:
  - Remove a tag from all files under a specific directory.
  - Steps:
    1. Choose a tag from the list of registered tags.
    2. Select a directory where registered files are located.
    3. Review the candidate files shown.
    4. Confirm to remove the tag from those files.
  * Best for: Removing a tag across all files in a directory.

MANAGE EBOOKS / TAG MANAGEMENT / DELETE TAG
===========================================

DELETE TAG FROM GLOBAL LIST:
  - Remove a tag completely from the tags database.
  - Steps:
    1. Babyrus shows all registered tags.
    2. Choose the tag you want to delete.
    3. If the tag is still associated with files, Babyrus will
       prompt you to dissociate it from those files first.
  * Best for: Cleaning up unused tags from the global list.

MANAGE EBOOKS / SEARCH & LOOKUP / LOOKUP FILES
==============================================

LOOKUP REGISTERED FILES:
  - Look up registered files by file name and tag.
  - Info available: full file name, directory, tags, size, mime type.
  - Steps:
    1. Enter a search string to filter by file name.
    2. Enter a search string to filter by tag name.
    3. Babyrus shows a list of matching files.
    4. Select a file to see full details.
    5. The menu stays open until you select 'Back'.
  * Best for: Inspecting detailed info for files matching certain criteria.

SEARCH EBOOK BY TAG:
  - Look up files by their associated tag.
  - Steps:
    1. Enter a search string to filter by tag names.
    2. Babyrus shows matching tags.
    3. Choose a tag to view its files.
    4. Matching files are shown in a message box.
  * Best for: Quickly finding all ebooks under one tag.

LOOKUP BY FILEPATH:
  - Look up registered files under a specific directory.
  - Steps:
    1. Select a directory from the list of registered paths.
    2. Enter a search string to filter by file name.
    3. Enter a search string to filter by tag name.
    4. Babyrus shows all matching files.
    5. Select a file to see full details (name, directory, tags, mime type, size).
  * Best for: Narrowing lookup to a specific folder and its files.

MANAGE EBOOKS / SEARCH & LOOKUP / VIEW ALL REGISTERED EBOOKS
============================================================

VIEW ALL REGISTERED EBOOKS:
  - Display detailed info for every registered ebook.
  - Steps:
    1. Babyrus shows a paginated list of all registered files.
    2. Select an item to view details (name, path, tags, mime type, size).
    3. Menu remains active so you can inspect multiple files.
  * Best for: Browsing all registered ebooks in one place.

MANAGE EBOOKS / SEARCH & LOOKUP / VIEW ALL REGISTERED TAGS
==========================================================

VIEW ALL REGISTERED TAGS:
  - Display all registered tags.
  - Steps:
    1. Babyrus shows tags in a scrollable message box.
  * Best for: Reviewing all available tags.

MANAGE EBOOKS / SEARCH & LOOKUP / OPEN & READ
=============================================

OPEN EBOOK SEARCH BY FILENAME:
  - Open a registered file by filtering with its file name.
  - Steps:
    1. Enter a search string to filter by file name.
    2. Babyrus shows a list of matching files.
    3. Choose a file to open with an external viewer.
  * Best for: Quickly opening a file when you know part of its name.

OPEN EBOOK SEARCH BY TAG:
  - Open a file by searching with its associated tag.
  - Steps:
    1. Enter a search string to filter by tag name.
    2. Babyrus shows matching tags from the tag database.
    3. Choose a tag to view associated files.
    4. Select a file to open with an external viewer.
  * Best for: Opening a file by category or topic.

OPEN FILE BY FILE PATH:
  - Open a file located in a specific directory.
  - Steps:
    1. Choose a directory from the list of registered file paths.
    2. Enter a search string to filter by file name (within the directory).
    3. Enter a search string to filter by tag name (within the directory).
    4. Babyrus shows matching files.
    5. Choose a file to open with an external viewer.
  * Best for: Narrowing down and opening files by folder location.

MANAGE EBOOKS / MAINTENANCE:
============================

FIND REMOVE BROKEN ENTRIES:
Used to remove from the eBooks database broken entries (i.e., paths that point to non-existent files). 
If there are no broken entries Babyrus will notify you. Otherwise, the broken entries are removed.

RENAME AND REREGISTER ILLEGAL FILENAMES:
Registered file names containing characters: | , # : ; are illegal in Babyrus 
because they potentially conflict with line formats of Babyrus’ database files. 
This function renames any illegal file names found in the eBooks database, 
avoids name conflicts, and reregisters them into the database. 
Babyrus allows the user to revert the changes if they wish. 
Babyrus takes some time to collect information about illegal file names. 
If illegal file names are found, Babyrus displays candidate files for renaming. 
After confirming, changes are made.

REVERT RENAMING ILLEGAL FILENAMES:
Babyrus provides a way to revert file renaming changes from the last renaming operation. 
If you confirm, Babyrus will restore original filenames in the eBooks database.
" 40 120
                ;;
            2)
                whiptail --scrolltext --title "Manage Notes" --cancel-button "Back" --msgbox "\
MANAGE NOTES:
=============

ADD NOTE:
Used to create a new note entry.

Step 1: Set Note Title
Select “Note Title” from the menu.
You must set a title before saving a note.
The note path is generated based on the title, and a timestamp is added to its name.
File name generation is automatic.

Step 2: Add Tags
Select “Tags” from the menu.
Babyrus will display a paginated list of all registered tags (including tags from other notes).
Use “>> Next Page” or “<< Previous Page” to navigate.

Options:
- Create a new tag: Select “Add new tag”, enter the name, and it will be created.
- Select existing tags: Choose from the list.
  Associated tags will be shown with [x] next to them.
You may associate any number of tags with a note.

Step 3: Associate Ebooks
Select “Ebooks” from the menu.
Babyrus will display a list of previously associated ebook files.

Adding a new ebook:
- Select “Add new ebook”.
- Filter candidate ebook files by tag:
  * Choose “ANY TAG” (no filtering), or
  * Select a tag (tags here belong to registered ebooks, not notes).
- Enter a search term to filter by ebook filename.
- Babyrus will display the number of matches found.
- A list of matching files will be shown.
- Select one file from the list.

Next actions:
- “Add chapter” – Create a bookmark with chapter name + page number.  
  Multiple chapters may be added.
- “Save and return” – Save the ebook selection and return.

Remove ebook:
- Remove associated ebook file: you can remove ebook files that you've added in the above steps.

Step 4: Edit the Note
Select “Save and Edit”: The note opens in an external terminal editor (e.g., vim or nano, depending on configuration).
When finished: Select “Save and Return” to store the changes.

EDIT NOTE:
The Edit Note function is used to edit an existing note. When you begin, Babyrus will display a paginated menu containing all existing notes. You can navigate forward or backward through pages if there are many items. Select the note you want to edit to access its menu.

The menu options for the selected note include:
- Note Title
- Note Path
- Tags
- Ebooks
- Save and Edit
- Save and Return

Editing the Note Title
You can change the note title by selecting Note Title.
Important: Changing the note title does not alter the note path or the note file name.

Managing Tags
To add or remove tags, select Tags. This will display a list of all registered tags, including both:
- Tags associated with this note (marked with [x])
- Other available tags
Selecting a tag will either associate or dissociate it with the note, depending on its current state.
You can also choose Add new tag to create a new tag and associate it with the note.

Managing Ebooks
To associate ebooks with the note, select Ebooks. Babyrus will display:
- A list of currently associated ebook files
- Options to Add new ebook or Remove ebook

Removing an Ebook
- Select Remove ebook.
- Choose the file you want to remove.

Adding an Ebook
- Select Add new ebook.
- Babyrus will display the global list of registered ebook tags, along with an ANY TAG option.
- Selecting ANY TAG means not filtering by tag.
- Enter a search term to filter ebook files by name (blank acts as a wildcard).
- Babyrus will show the number of matching entries. Select OK.
- From the displayed list of matching files, choose the ebook to associate with the note.

Adding Chapters (Optional)
After associating an ebook, Babyrus allows you to:
- Save and return
- Add chapter
If you select Add chapter, you can create bookmarks that let you reopen the ebook at a specific page later.

Saving Changes
From the main Edit Note menu, you can:
- Save and Edit – Opens the note file in an external terminal editor to modify its contents.
- Save and Return – Saves all changes and returns to the parent menu.

OPEN ASSOCIATED EBOOK:
This function allows you to open an ebook file that has been associated with a note using either Add Note or Edit Note. It also supports opening at specific bookmarks.

Displaying Notes
When you use this function, Babyrus will display a list of all registered note files.
- The file path (including the file name) is shown on the left.
- Any associated tag(s) appear on the right, surrounded by square brackets.
Select the note you want to work with.

Handling Notes Without eBooks
If the selected note has no associated ebooks, Babyrus will display:
\"No ebooks associated with the note\"

Displaying Associated eBooks
If the note does have associated ebooks, Babyrus will show a list of all linked ebook files.

If no chapters are registered:
A menu titled \"No Chapters Found\" appears with two options:
- Open – Opens the ebook file with the configured external viewer (e.g., Evince) at the last page opened by that viewer.
- Return – Goes back to the previous menu.

If chapters are registered:
Babyrus will display a list of all registered bookmarks.
Selecting one will open the ebook file with the external viewer directly at the specified page.

DO STUFF BY TAG:
This function allows you to narrow down note entries by their associated tag and perform actions on them. Available actions include editing notes or opening associated ebooks.

Step 1: Select a Tag
Babyrus begins by displaying a global list of all registered tags (tags linked to note files). Choose a tag from this list to continue.

Step 2: Choose an Action
After selecting a tag, you are given two options:
- Edit Note
- Open Associated eBook

Editing a Note
If you select Edit Note, Babyrus displays a list of all note files associated with the chosen tag. From there:
- Select the note you want.
- A familiar menu from the Edit Note function appears.

You can now:
- Edit note content
- Add or remove tags
- Add or remove ebooks

Opening an Associated eBook
If you select Open Associated eBook, Babyrus shows a list of note files that match the chosen tag. Once you select a note:
- A list of all associated ebook files is displayed.
- Choose the file you wish to open with an external viewer.

If no chapters are registered:
- Babyrus will still offer to open the file.

If chapters are registered:
- You can select a bookmark, and the ebook will open at that page in an external viewer.

ASSOCIATE URL TO NOTE:
This function is used to link a URL to your note file. URLs are managed separately from the Add Note or Edit Note functions.

Step 1: Display Registered Notes
When you begin, Babyrus displays a list of all registered note files. Left side shows file paths and right side associated tags inside square brackets.
Select the note file you want to work with.

Step 2: Access the URL Menu
After selecting a note, you are presented with a menu containing:
- Register URL
- Save and return
- A list of all URLs currently associated with the note

Step 3: Manage Existing URLs
If you click on an existing URL, two options are available:
- Change values – Edit the URL
- Delete URL – Remove the URL

Step 4: Register a New URL
To add a new URL, select Register URL.

Step 5: Save and Exit
Once finished, select Save and return to confirm your changes.

DISSOCIATE URL FROM NOTE:
This function is used to dissociate (unlink) a URL from a note previously associated using the Associate URL to Note function.

Step 1: Display Registered Notes
Babyrus first displays a list of all registered note files. Each item has file path on the left, associated tags (inside square brackets) on the right.
Select the note file you want to work with.

Step 2: View Associated URLs
After selecting a note, Babyrus shows a list of all URLs associated with the chosen note file. You will also see two options:
- Remove URL
- Save and return

Step 3: Remove a URL
If you want to remove a URL, select Remove URL. Babyrus will again display the list of URLs. Choose the one you want to remove, and it will be unlinked from the note.

Step 4: Save and return
Once you are done managing URLs, select Save and return to confirm the changes and return to parent menu.

OPEN URL FROM NOTE:
This function allows you to open a URL that has been previously associated with a note file.

Step 1: Display Registered Notes
Babyrus first displays a list of all registered note files. Each item has file path on the left, any associated tags (inside square brackets) on the right.
Select the note file you want to work with.

Step 2: View Associated URLs
After selecting a note, Babyrus will show you a list of all URLs associated with that note.

Step 3: Open URL
Choose the URL you want from the list. The selected URL will then be opened automatically in your web browser.

OPEN AN EBOOK FROM GLOBAL LIST:
Babyrus keeps track of all eBook file paths linked to note files in a single global list. This makes it easy to open any associated eBook directly with an external viewer.

Babyrus displays the complete global list of eBook files (those that are associated to a note file). Simply select the file you want, and it will open in your default external viewer.

DELETE NOTES:
This function is used to delete one or more note files.

How it Works:
- Babyrus displays a checklist of all registered note files.
- Multiple files can be selected at once for deletion.
- To confirm, check the option __proceed__.

Result:
- The selected note files are permanently removed from the notes database.

DELETE NOTE TAG FROM GLOBAL LIST:
Babyrus manages all registered note tags centrally. This function is used to delete a tag from the database.

How it Works:
- Babyrus presents a list of all registered note tags.
- Select one item to remove it.

Note:
- A tag can only be deleted if it is not associated with any note file.
- If the tag is still linked to one or more note files, Babyrus will notify you that the deletion cannot proceed until the conflicts are resolved.

Resolving Conflicts:
- Dissociate the tag from all associated note files first.
- Once the tag is no longer linked, it can be deleted successfully.
" 40 120
                ;;
            3)
                whiptail --scrolltext --title "Manage Goals" --cancel-button "Back" --msgbox "\
MANAGE GOALS:
=============

ADD NEW PROJECT:
Used to create a new project. Begin by entering a project title. Babyrus will automatically generate a project file name based on the title, with a timestamp appended to it.

When ready, select ‘Proceed’ to begin adding content to your project. The project file is structured with headings and subheadings that describe different parts of your project. Often they can be thought of as a summary.

Adding and Managing Headings
At the start, Babyrus displays two options:
- Add new heading
- Save and return

Select ‘Add new heading’ to insert a new heading. Once added, the heading will appear in the menu.

Selecting a heading opens a list of available actions:
- Change text – Edit the text of the selected heading.
- Move before – Move the heading before another one.
- Move after – Move the heading after another one.
- Indent right – Increase indentation by one tab, turning the heading into a subheading.
- Indent left – Decrease indentation by one tab, making the heading a parent heading.
- Remove heading – Delete the selected heading.

Note:
- To use the Move before or Move after options, your project must contain at least two headings.

Saving the Project
After you finish organizing and editing your headings, select ‘Save and return’ to save your changes and return to the previous menu.

EDIT EXISTING PROJECT:

This function is used to edit an existing project in Babyrus.

Finding the Project to Edit
Start by entering a glob pattern to narrow down your search. Babyrus will then display a list of candidate project files.
Select the project file you want to edit.

Changing the Project Title
Once selected, choose 'Project title' to modify the title of the project.

Note:
- The project path remains unchanged even when the title is updated.

Editing Project Content
Select 'Proceed' to view and edit the content of the chosen project. Babyrus will display the full content of the project file along with two options:
- Add new heading
- Save and return

Adding and Managing Headings
To add a new heading, select 'Add new heading.'
You can also select an existing heading to perform one of the following actions:
- Change text – Edit the text of the selected heading.
- Move before / Move after – Reposition the heading relative to another one.
- Indent left / Indent right – Adjust the indentation level.
- Remove heading – Delete the selected heading from the project.

Saving Changes
After making edits, select 'Save and return' to save all changes and go back to the parent menu.

PRINT PROJECT CONTENT ON SCREEN:

Used to display a project's content in read-only mode on the screen.

Filtering Projects
Start by entering a glob pattern to filter projects by title. Babyrus will display a list of candidate project files.

Viewing Content
Select the project you want to view. Babyrus will then display the project’s content on the screen in read-only mode.

ASSOCIATE NOTE WITH PROJECT:

Used to associate a note file with a project file.

Filtering Projects
Begin by entering a glob pattern to filter projects by title. Babyrus will show a list of matching project files. Select the one you want.

Selecting a Note File
Next, Babyrus will display all registered note files. Each entry shows the note’s full file path on the left and any associated tags on the right (inside square brackets).

Association Confirmation
Choose the note file you wish to associate with the selected project. If it isn’t already associated, Babyrus will confirm that the note has been successfully linked to the project.

DISSOCIATE NOTE FROM PROJECT:

Used to remove the association between a note file and a project file.

Filtering Projects
Start by entering a glob pattern to filter projects by title. Babyrus will list matching project files. Select the one you want.

Selecting an Associated Note
Babyrus will then display all note files currently associated with the chosen project. Select the note you wish to dissociate.

Dissociation Confirmation
If successful, Babyrus will notify you that the note has been successfully dissociated from the project.

DO STUFF WITH LINKED NOTES IN PROJECT FILE:

Used to perform actions with note files linked to a project file. The available actions are View Note and Open eBooks.

Filtering Projects

Start by entering a glob pattern to filter projects by title.
Babyrus will display a list of candidate project files.
Select the project you want to work with.

Selecting a Linked Note

After choosing a project, Babyrus will list all note files linked to that project.
Select the note file you want to interact with.

Viewing a Note

Choose 'View Note' to display the content of the selected note file in read-only mode.
This is useful when browsing through the contents of all note files linked to a project.

Opening eBooks

Choose 'Open eBooks' to access ebook files linked to the selected note file.
Babyrus will show all ebook files associated with that note.

If no chapters are registered:
Babyrus displays a simple menu with two options — Open and Return.
Select 'Open' to open the ebook using an external viewer.
Select 'Return' to go back to the previous menu.

If one or more chapters are registered:
Babyrus lists all registered chapters.
Choose one, and Babyrus will open the ebook file at that specific page using an external viewer.

OPEN URL FROM LINKED NOTES IN PROJECT FILE:

A note file can include linked URLs that you can open directly in a web browser. This function allows you to select a note file linked to a project file, then open one of its associated URLs.

Step 1: Filter Projects

Enter a glob pattern to filter projects by title.
Babyrus will display a list of all matching registered project files.

Step 2: Select a Project

Choose the project file you want to work with from the displayed list.

Step 3: Select a Linked Note

Babyrus will list all note files associated with the selected project.
Choose the note file you want to access.

Step 4: Open a Linked URL

Babyrus will display all registered URLs linked to the note.
Select the URL you want to open, and it will be launched in your default web browser.
Alternatively, select 'Back' to return to the parent menu.

DELETE PROJECT:

Used to delete a project file from the projects database.

Step 1: Filter Projects

Enter a glob pattern to filter projects by title.
Babyrus will display a list of all matching project files.

Step 2: Select a Project

Choose the project you want to delete from the list.

Step 3: Confirm Deletion

Babyrus will display a confirmation message.
Select 'Delete' to confirm.
The project file will then be permanently removed from the database.
" 40 120
                ;;
            4)
                whiptail --scrolltext --title "Configure" --cancel-button "Back" --msgbox "\
CONFIGURE:
==========

Use this function to set default applications for different file types based on their extensions.
Babyrus relies on these defaults to open files appropriately.

When you open the 'Set Default Apps' menu, you’ll see a list showing file extensions on the left and their current default applications on the right.

To change a default app:

1. Select the item corresponding to the extension you want to modify.
2. Babyrus will prompt you to enter a new command.
3. For example, to change the default app for '.pdf' files to Evince, enter: evince

From then on, Babyrus will use Evince whenever you open a '.pdf' file.
" 40 120
                ;;
            5)
                whiptail --scrolltext --title "Help" --cancel-button "Back" --msgbox "\
HELP:
=====

Use this function to view the help documentation for Babyrus.
It provides guidance on how to use all major features of the system.
" 40 120
                ;;
            6)
                whiptail --scrolltext --title "Backup" --cancel-button "Back" --msgbox "\
BACKUP:
=======

This function creates a backup of all Babyrus database files — including the ebooks, notes, and projects databases.

When prompted, confirm that you want to proceed.
Babyrus will generate a backup file named:

    backup_<timestamp>.tar.gz

This ensures your data is safely stored for recovery if needed.
" 40 120
                ;;
            7)
                whiptail --scrolltext --title "Restore" --cancel-button "Back" --msgbox "\
RESTORE:
========

Use this function to restore Babyrus data from a previously created backup file.

Simply select one of the available backup files to restore.
During the restoration process, existing database files will be overwritten with the contents of the backup.
" 40 120
                ;;
        esac
    done
}

################################
# Main Menu
################################
msg1="'Labor of love and hope"
msg2="in our Lord Jesus Christ.'"
msg3="1 Thessalonians 1:3"
padding1=$(( (53 - ${#msg1}) / 2 ))
padded_msg1="$(printf "%*s%s" $padding1 "" "$msg1")"
padding2=$(( (55 - ${#msg2}) / 2 ))
padded_msg2="$(printf "%*s%s" $padding2 "" "$msg2")"
padding3=$(( (53 - ${#msg3}) / 2 ))
padded_msg3="$(printf "%*s%s" $padding3 "" "$msg3")"
padded_msg="${padded_msg1}\n${padded_msg2}\n${padded_msg3}"
MAIN_MENU_STR="
${padded_msg}
"

# About message
about_babyrus() {
    whiptail --title "About BABYRUS" --msgbox \
"BABYRUS — a simple, fast, terminal-based productivity tool.
Version: ${BABYRUS_VERSION}

Copyleft © 2025, 2026 Logan Lee — GPLv3." \
    12 60
}

# Main menu function
show_main_menu() {
    while true; do
        choice=$(whiptail --title "BABYRUS ${BABYRUS_VERSION} Main Menu" --cancel-button "Exit" --menu "$MAIN_MENU_STR" 25 58 8 \
            "eBooks" "Manage eBooks" \
            "Notes" "Manage Notes" \
            "Goals" "Manage Goals" \
            "Configure" "Set Default Apps" \
            "Help" "Read Help" \
	        "Backup" "Backup Everything" \
	        "Restore" "Restore from File" \
            "About" "About BABYRUS" \
            3>&1 1>&2 2>&3)

        if [ $? != 0 ]; then
            exit 0
        fi

        case $choice in
            "eBooks")
                show_ebooks_menu
                ;;
            "Notes")
                manage_notes
                ;;
            "Goals")
                show_projects_menu
                ;;
            "Configure")
                edit_configuration
                ;;
            "Help")
                show_help
                ;;
	        "Backup")
		        backup_db
		        ;;
	        "Restore")
		        restore_db
		        ;;
            "About")
                about_babyrus
                ;;
        esac
    done
}

show_main_menu
