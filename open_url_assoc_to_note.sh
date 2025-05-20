NOTES_DB="$(pwd)/notes/metadata/notes.db"
URLS_DB="$(pwd)/urls/urls.db"
mkdir -p "$(pwd)/urls"

URL_BROWSER='google-chrome'

open_url_assoc_to_note() {
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
        for path in "${note_paths[@]}"; do
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
                20 150 10 "${url_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || break
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

# test
open_url_assoc_to_note
