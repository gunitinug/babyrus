PROJECTS_DB="$(pwd)/projects/metadata/projects.db"

URLS_DB="$(pwd)/urls/urls.db"
mkdir -p "$(pwd)/urls"

URL_BROWSER='google-chrome'

open_url_assoc_to_note_from_project() {
	touch "$URLS_DB" "$PROJECTS_DB"
	
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls            

    # Check if Projects database exists
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "Projects database not found or empty!" 8 50 >/dev/tty
        return 1
    fi

    # Check if URLs database exists
    if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
        whiptail --msgbox "URL database not found or empty!" 8 50 >/dev/tty
        return 1
    fi

    while true; do
		# Build menu for choosing project path from PROJECTS_DB
		local projects_menu_items=()
		while IFS='|' read -r title proj_path notes; do
			# skip blank lines or malformed ones
			[[ -z "$proj_path" ]] && continue
			projects_menu_items+=("$proj_path" "")
		done < "$PROJECTS_DB"		
		
		# debug
		#echo projects_menu_items:
		#echo "${projects_menu_items[@]}"
		
		# Menu for choosing project path
		local chosen_project
		chosen_project=$(whiptail --title "Open URL from Note Associated to Project" --menu "Choose project" 20 150 10 \
		"${projects_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    
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

# Test
open_url_assoc_to_note_from_project
