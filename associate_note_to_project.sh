associate_note_to_project() {
    local PROJECTS_DB="$PROJECTS_DB"
    local NOTES_DB="$NOTES_DB"
    local temp_file line_updated duplicate_detected project_found
    temp_file=$(mktemp)
    line_updated=0
    duplicate_detected=0
    project_found=0

    # Check if databases exist
    if [[ ! -f "$PROJECTS_DB" ]]; then
        whiptail --msgbox "Error: Projects database file not found: $PROJECTS_DB" 20 50
        return 1
    fi
    if [[ ! -f "$NOTES_DB" ]]; then
        whiptail --msgbox "Error: Notes database file not found: $NOTES_DB" 20 50
        return 1
    fi

    # Read projects into menu
    local project_menu_options=()
    while IFS='|' read -r title path rest; do
        project_menu_options+=("$path" "$title")
    done < "$PROJECTS_DB"
    if [[ "${#project_menu_options[@]}" -eq 0 ]]; then
        whiptail --msgbox "No projects available in the database." 20 50
        return 1
    fi

    # Project selection
    local selected_project_path
    selected_project_path=$(whiptail --title "Select Project" \
        --menu "Choose a project to associate a note:" \
        25 50 15 "${project_menu_options[@]}" 3>&1 1>&2 2>&3)
    [[ -z "$selected_project_path" ]] && return 1  # User canceled

    # Read notes into menu
    local note_menu_options=()
    while IFS='|' read -r note_title note_path rest; do
        note_menu_options+=("$note_path" "$note_title")
    done < "$NOTES_DB"
    if [[ "${#note_menu_options[@]}" -eq 0 ]]; then
        whiptail --msgbox "No notes available in the database." 20 50
        return 1
    fi

    # Note selection
    local selected_note_path
    selected_note_path=$(whiptail --title "Select Note" \
        --menu "Choose a note to associate:" \
        25 50 15 "${note_menu_options[@]}" 3>&1 1>&2 2>&3)
    [[ -z "$selected_note_path" ]] && return 1  # User canceled

    # Process PROJECTS_DB
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            echo >> "$temp_file"
            continue
        fi

        IFS='|' read -r title path notes rest <<< "$line"
        if [[ "$path" == "$selected_project_path" ]]; then
            project_found=1
            current_notes="$notes"
            local notes_array=()

            # Check for duplicates
            IFS=',' read -ra notes_array <<< "$current_notes"
            local duplicate=0
            for note in "${notes_array[@]}"; do
                [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
            done

            if (( duplicate )); then
                whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50
                duplicate_detected=1
                # Rebuild original line
                new_line="$title|$path|$current_notes"
                [[ -n "$rest" ]] && new_line+="|$rest"
                echo "$new_line" >> "$temp_file"
            else
                # Update notes
                if [[ -z "$current_notes" ]]; then
                    new_notes="$selected_note_path"
                else
                    new_notes="$current_notes,$selected_note_path"
                fi
                new_line="$title|$path|$new_notes"
                [[ -n "$rest" ]] && new_line+="|$rest"
                echo "$new_line" >> "$temp_file"
                line_updated=1
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$PROJECTS_DB"

    # Handle processing results
    if (( project_found )); then
        if (( line_updated )); then
            mv "$temp_file" "$PROJECTS_DB"
            whiptail --msgbox "Note successfully associated with the project." 10 50
        elif (( duplicate_detected )); then
            rm "$temp_file"
        else
            rm "$temp_file"
            whiptail --msgbox "No changes were made to the project entry." 10 50
        fi
    else
        rm "$temp_file"
        whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
        return 1
    fi
}
