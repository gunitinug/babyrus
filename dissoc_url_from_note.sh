NOTES_DB="$(pwd)/notes/metadata/notes.db"
URLS_DB="$(pwd)/urls/urls.db"
mkdir -p "$(pwd)/urls"

dissoc_url_from_note() {
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls

    # Check URL database existence
    if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
        whiptail --msgbox "Error: URLs database not found or empty!" 8 50 >/dev/tty
        return 1
    fi

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
    for path in "${note_paths[@]}"; do
        menu_items+=("$path" "")
    done

    local selected_path
    selected_path=$(whiptail --menu "Select a note to dissociate URLs" 20 150 10 \
        "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    [[ -z "$selected_path" ]] && return 1

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
        choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 150 10 \
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
                remove_index=$(whiptail --menu "Select URL to remove" 20 150 10 \
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

# test
dissoc_url_from_note
