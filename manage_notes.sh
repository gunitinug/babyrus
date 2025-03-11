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

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        # Extract the current chunk from the global TRUNC
        local current_chunk=("${FILTERED_EBOOKS[@]:$start:$chunk_size}")
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
                SELECTED_ITEM="$choice"
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
    shopt -s nocasematch  # Enable case-insensitive matching  
  
    if [[ "$filename" == *"$search_term"* ]]; then
      FILTERED_EBOOKS+=("$filepath" "")
    fi

    shopt -u nocasematch
  done < "$EBOOKS_DB"

  # DEBUG
  echo FILTERED_EBOOKS: >&2
  declare -p FILTERED_EBOOKS >&2

  # Optionally, notify the user how many entries were found.
  whiptail --msgbox "Found $(( ${#FILTERED_EBOOKS[@]} / 2 )) matching entries." 8 60 --title "Filter Results" >/dev/tty
}

#!/bin/bash

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
    while true; do
        # Read existing ebooks, skipping empty lines
        local -a ebooks=()
        if [ -f "$NOTES_EBOOKS_DB" ]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    ebooks+=("$line")
                fi
            done < "$NOTES_EBOOKS_DB"
        fi

        # Prepare menu options
        local menu_options=()
        for ebook in "${ebooks[@]}"; do
            local chapters=""
            for entry in "${ebook_entries[@]}"; do
                if [[ "$entry" == "${ebook}#"* ]]; then
                    chapters=$(cut -d# -f2- <<< "$entry")
                    break
                fi
            done
            menu_options+=("$ebook" "$chapters")
        done
        menu_options+=("Add new ebook" "")
        [ ${#ebook_entries[@]} -gt 0 ] && menu_options+=("Remove ebook" "")
        menu_options+=("Back" "Return to previous menu")

        local selection
        selection=$(whiptail --title "Manage Ebooks" --menu "Manage ebook associations" 20 100 10 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        [ $? -eq 0 ] || return

        case "$selection" in
            "Add new ebook")
                local new_ebook
                CURRENT_PAGE=0
                SELECTED_ITEM=""

                filter_by_filename
                paginate
                new_ebook="$SELECTED_ITEM"

                # Check if the user selected an ebook
                if [[ -z "$new_ebook" ]]; then
                    whiptail --msgbox "No ebook selected. Operation cancelled." 8 60 >/dev/tty
                    continue
                fi

                # Add to global ebooks list if not already present
                if ! grep -qxF "$new_ebook" "$NOTES_EBOOKS_DB"; then
                    echo "$new_ebook" >> "$NOTES_EBOOKS_DB"
                fi

                # Prompt for chapters/pages
                local chapters
                chapters=$(whiptail --inputbox "Enter chapter:page pairs (e.g., chapter1:5, chapter3:10-15):" \
                    12 60 3>&1 1>&2 2>&3 </dev/tty)
                # Check if user cancelled chapters input
                if [ $? -ne 0 ]; then
                    whiptail --msgbox "Chapters input cancelled. Ebook not added." 8 60 >/dev/tty
                    continue
                fi

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

                whiptail --yesno "Remove all associations for '${to_remove}'?" 8 60 </dev/tty >/dev/tty && {
                    local new_ebook_entries=()  # Temporary array for filtered entries
                    for entry in "${ebook_entries[@]}"; do
                        # If the entry does NOT start with "${to_remove}#", keep it
                        if [[ "$entry" != "${to_remove}"#* ]]; then
                            new_ebook_entries+=("$entry")
                        fi
                    done
                    ebook_entries=("${new_ebook_entries[@]}")  # Overwrite original array
                }
                ;;
            "Back")
                return
                ;;
            *)
                # Edit existing entry
                local current_chapters=""
                for entry in "${ebook_entries[@]}"; do
                    if [[ "$entry" == "${selection}#"* ]]; then
                        current_chapters=$(cut -d# -f2- <<< "$entry")
                        break
                    fi
                done

                local new_chapters
                new_chapters=$(whiptail --inputbox "Edit chapter:page pairs for ${selection}:" 12 60 \
                    "$current_chapters" 3>&1 1>&2 2>&3 </dev/tty)
                [ $? -eq 0 ] || continue

                # Update entry
                local new_update_entries=()  # Temporary array for filtered entries
            
                # Remove the existing entry matching "${selection}#*"
                for entry in "${ebook_entries[@]}"; do
                    if [[ "$entry" != "${selection}"#* ]]; then
                        new_update_entries+=("$entry")
                    fi
                done
            
                # Add the updated entry
                new_update_entries+=("${selection}#${new_chapters}")
            
                # Replace the original array with the updated one
                ebook_entries=("${new_update_entries[@]}")
                ;;
        esac
    done
}

save_note() {
    # Check that note_title and note_path are set; if not, do not save
    if [[ -z "$note_title" || -z "$note_path" ]]; then
        whiptail --title "Error" --msgbox "Note title and note path can't be empty!" 8 50 >/dev/tty
        return 1
    fi

    local timestamp
    timestamp=$(date +"%d-%m-%Y")
    local sanitized_title
    sanitized_title=$(tr -cd '[:alnum:]-_ ' <<< "$note_title" | tr ' ' '_')
    note_path="${NOTES_PATH}/${sanitized_title}-${timestamp}.txt"
    touch "$note_path" || return 1

    # Prepare metadata
    local tags_str
    tags_str=$(IFS=','; echo "${current_tags[*]}")
    local ebooks_str
    ebooks_str=$(IFS=';'; echo "${ebook_entries[*]}")

    # Update databases
    echo "${note_title}|${note_path}|${tags_str}|${ebooks_str}" >> "$NOTES_DB"
    sort -u "$HOME/notes/metadata/notes-tags.db" -o "$NOTES_TAGS_DB"
    sort -u "$HOME/notes/metadata/notes-ebooks.db" -o "$NOTES_EBOOKS_DB"

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

add_note
