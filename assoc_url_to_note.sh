NOTES_DB="$(pwd)/notes/metadata/notes.db"
URLS_DB="$(pwd)/urls/urls.db"
mkdir -p "$(pwd)/urls"

# Line format for URLS_DB is:
#/path/to/note/some note.txt${GS}https://some url/url.html${US}url title${RS}https://some other/url2.html${US}other url title

assoc_url_to_note() {
	touch "$URLS_DB"
	
    #local NOTES_DB="$NOTES_DB"
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls

    # Extract note paths from NOTES_DB
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "Error: Notes database not found or empty!" 8 50 >/dev/tty
        return 1
    fi

    # Read note paths
    local note_paths=()
    while IFS='|' read -r _ path _ _; do
        note_paths+=("$path")
    done < "$NOTES_DB"

    if [[ ${#note_paths[@]} -eq 0 ]]; then
        whiptail --msgbox "No notes found in database!" 8 50 >/dev/tty
        return 1
    fi

    # Select note path
    local menu_items=()
    for path in "${note_paths[@]}"; do
        menu_items+=("$path" "")
    done

    local selected_path
    selected_path=$(whiptail --menu "Select a note" 20 150 10 "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    [[ -z "$selected_path" ]] && return 1

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

    # URL management loop
    while true; do
        local menu_options=("Register URL" "" "Save and return" "")
        for i in "${!urls[@]}"; do
            menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
        done

        local choice
        choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 150 10 "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        [[ -z "$choice" ]] && return 1

        case "$choice" in
            "Register URL")
                local new_url new_title
                new_url=$(whiptail --inputbox "Enter URL:" 8 50 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
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

# test
assoc_url_to_note
