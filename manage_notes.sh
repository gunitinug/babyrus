#!/bin/bash

BABYRUS_PATH="/my-projects/babyrus"
NOTES_PATH="${BABYRUS_PATH}/notes"
NOTES_METADATA_PATH="${NOTES_PATH}/metadata"
NOTES_DB="${NOTES_METADATA_PATH}/notes.db"
NOTES_TAGS_DB="${NOTES_METADATA_PATH}/notes-tags.db"
NOTES_EBOOKS_DB="${NOTES_METADATA_PATH}/notes-ebooks.db"
EBOOKS_DB="${BABYRUS_PATH}/ebooks.db"

# Create notes directories if not created
mkdir -p "${NOTES_METADATA_PATH}"

# Create if not existent
touch "$NOTES_DB" "$NOTES_TAGS_DB" "$NOTES_EBOOKS_DB"

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

# Global array to store filtered entries.
declare -a FILTERED_EBOOKS

CURRENT_PAGE=0   # persists page state across paginate() calls

paginate() {
    # Clear any previous selection
    SELECTED_ITEM=""

    local chunk_size=200

    # If new items are passed in, update TRUNC and reset CURRENT_PAGE.
    if [ "$#" -gt 0 ]; then
        FILTERED_EBOOKS=("$@")
        CURRENT_PAGE=0
    fi

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
                return 0
                ;;
        esac
    done

    return 1
}

# Filter by filename just before 
filter_by_filename() {
  # Prompt the user for a search term using whiptail.
  local search_term
  search_term=$(whiptail --inputbox "Enter search term for ebook file name:" 8 60 --title "Filter Ebooks" 3>&1 1>&2 2>&3 </dev/tty)
  if [ $? -ne 0 ]; then
    echo "User cancelled the filter."
    return 1
  fi

  # Clear the global array.
  FILTERED_EBOOKS=()

  # Check that the EBOOKS_DB file exists.
  if [ ! -f "$EBOOKS_DB" ]; then
    echo "EBOOKS_DB file not found: $EBOOKS_DB" >&2
    return 1
  fi

  # Read the EBOOKS_DB file line by line.
  while IFS= read -r line; do
    # Each line format: /path/to/ebook/some ebook.pdf|tag1,another tag
    # Extract the file path (everything before the first '|').
    local filepath="${line%|*}"
    # Extract the filename using basename.
    local filename
    filename=$(basename "$filepath")

    # If the filename contains the search term, add filepath to FILTERED_EBOOKS.
    if [[ "${filename,,}" == *"${search_term,,}"* ]]; then
      FILTERED_EBOOKS+=("$filepath" "")
    fi
  done < "$EBOOKS_DB"

  # DEBUG
  echo FILTERED_EBOOKS: >&2
  declare -p FILTERED_EBOOKS >&2

  # Optionally, notify the user how many entries were found.
  whiptail --msgbox "Found $(( ${#FILTERED_EBOOKS[@]} / 2 )) matching entries." 8 60 --title "Filter Results" >/dev/tty
}

# Global variables used by add_note and its helpers.
note_title=""
note_path=""
current_tags=()
ebook_entries=()

manage_tags() {
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
        menu_options+=("Back" "Return to previous menu")

        local selection
        selection=$(whiptail --title "Manage Tags" --menu "Current tags: ${current_tags[*]}" 20 60 10 \
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
            "Back")
                return
                ;;
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
        selection_trunc=$(whiptail --title "Manage Ebooks" --menu "Manage ebook associations" 20 170 10 \
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
                local new_ebook
                CURRENT_PAGE=0
                SELECTED_ITEM=""

                filter_by_filename
                paginate
                new_ebook="$SELECTED_ITEM"

                if [[ -z "$new_ebook" ]]; then
                    whiptail --msgbox "No ebook selected. Operation cancelled." 8 60 >/dev/tty
                    continue
                fi

                # Check if ebook already exists in ebook_entries
                local exists=0
                for entry in "${ebook_entries[@]}"; do
                    if [[ "$entry" == "${new_ebook}#"* ]]; then
                        exists=1
                        break
                    fi
                done
                if [ $exists -eq 1 ]; then
                    whiptail --msgbox "Ebook already exists in the current session." 8 60 >/dev/tty
                    continue
                fi

                local chapters
                chapters=$(whiptail --inputbox "Enter chapter:page pairs (e.g., chapter1:5, chapter3:10-15):" \
                    12 60 "" 3>&1 1>&2 2>&3 </dev/tty)
                [ $? -ne 0 ] && continue

                ebook_entries+=("${new_ebook}#${chapters}")
                ;;

            "Remove ebook")
                local remove_options=()
                for entry in "${ebook_entries[@]}"; do
                    remove_options+=("$(cut -d# -f1 <<< "$entry")" "")
                done
                local to_remove
                to_remove=$(whiptail --title "Remove Ebook" --menu "Select ebook to remove:" \
                    20 100 10 "${remove_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
                [ $? -eq 0 ] || continue

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

                local new_chapters
                new_chapters=$(whiptail --inputbox "Edit chapter:page pairs for ${selection}:" 12 60 \
                    "$current_chapters" 3>&1 1>&2 2>&3 </dev/tty)
                [ $? -eq 0 ] || continue

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
    echo note title: >&2
    echo "$note_title" >&2

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

    # Main loop
    while true; do
        local path_status="(will be generated)"
        [ -n "$note_title" ] && path_status="${NOTES_PATH}/${note_title}-*.txt"

        local tag_status="none"
        [ ${#current_tags[@]} -gt 0 ] && tag_status="${#current_tags[@]} tags"

        local ebook_status="none"
        [ ${#ebook_entries[@]} -gt 0 ] && ebook_status="${#ebook_entries[@]} ebooks"

        choice=$(whiptail --title "Create New Note" --menu "Configure note properties" 20 100 8 \
            "Note Title"    "Current: ${note_title:-<not set>}" \
            "Note Path"     "Status: ${path_status}" \
            "Tags"          "Status: ${tag_status}" \
            "Ebooks"        "Status: ${ebook_status}" \
            "Save and Edit" "Save note and open in editor" \
            "Save and Return" "Save note and exit" 3>&1 1>&2 2>&3)
        [ $? -eq 0 ] || break

        case "$choice" in
            "Note Title")
                note_title=$(whiptail --inputbox "Enter note title:" 8 40 "$note_title" 3>&1 1>&2 2>&3)
                ;;
            "Tags")
                manage_tags
                ;;
            "Ebooks")
                manage_ebooks
                ;;
            "Save and Edit")
                save_note || return 1
                nano "$note_path"
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

    local choice
    while true; do
        # Prepare status messages
        local path_status="$note_path"
        local tag_status="none"
        [ ${#current_tags[@]} -gt 0 ] && tag_status="${#current_tags[@]} tags"
        local ebook_status="none"
        [ ${#ebook_entries[@]} -gt 0 ] && ebook_status="${#ebook_entries[@]} ebooks"

        choice=$(whiptail --title "Edit Note" --menu "Edit note properties" 20 100 8 \
            "Note Title"    "Current: ${note_title}" \
            "Note Path"     "Path: ${path_status}" \
            "Tags"          "Status: ${tag_status}" \
            "Ebooks"        "Status: ${ebook_status}" \
            "Save and Edit" "Save changes and open in editor" \
            "Save and Return" "Save changes and exit" 3>&1 1>&2 2>&3)
        [ $? -eq 0 ] || break

        case "$choice" in
            "Note Title")
                note_title=$(whiptail --inputbox "Enter note title:" 8 40 "$note_title" 3>&1 1>&2 2>&3)
                ;;
            "Note Path")
                whiptail --msgbox "Note path cannot be edited: $note_path" 10 60
                ;;
            "Tags")
                manage_tags
                ;;
            "Ebooks")
                manage_ebooks
                ;;
            "Save and Edit")
                if update_note_in_db; then
                    nano "$note_path"
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

list_notes() {
    while true; do
        local db_file="$NOTES_DB"
        [ ! -f "$db_file" ] && {
            whiptail --msgbox "No notes database found" 8 40
            return 1
        }

        # Reset arrays and index for fresh load each iteration
        local -a menu_entries=()
        local -a MENU_PATH_ENTRIES=()
        local idx=1

        # Load current database state
        while IFS='|' read -r title path tags _; do
            local tag_display=""
            [ -n "$tags" ] && tag_display=" [${tags}]"
            menu_entries+=("${idx}:${title}" "${tag_display}")
            MENU_PATH_ENTRIES+=("$path" "")
            ((idx++))
        done < "$db_file"

        [ ${#menu_entries[@]} -eq 0 ] && {
            whiptail --msgbox "No notes found in database" 8 40
            return 1
        }

        # Show interactive menu
        local selected_idx
        selected_idx=$(whiptail \
            --title "Note Selection" \
            --cancel-button "Back" \
            --menu "Choose a note to edit" \
            20 170 10 \
            "${menu_entries[@]}" \
            3>&1 1>&2 2>&3)

        # Exit on cancel
        [ $? -ne 0 ] && break

        # Process selection
        selected_idx="$(echo "$selected_idx" | cut -d':' -f1)"
        local m=$((2 * selected_idx - 1))
        local array_index=$((m - 1))
        local selected_path="${MENU_PATH_ENTRIES[$array_index]}"
        
        # Edit note, exactly as it says ;-)
        edit_note "$selected_path"
    done
}

list_notes
