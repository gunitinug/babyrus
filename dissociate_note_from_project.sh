dissociate_note_from_project() {
    local PROJECTS_DB=${PROJECTS_DB:-"$HOME/projects_db"}  # Default path if not set
    
    # Check if database exists
    if [[ ! -f "$PROJECTS_DB" ]]; then
        whiptail --msgbox "Error: PROJECTS_DB file '$PROJECTS_DB' not found" 10 60
        return 1
    fi

    # Read all lines from database
    local -a lines
    mapfile -t lines < "$PROJECTS_DB"

    if [[ ${#lines[@]} -eq 0 ]]; then
        whiptail --msgbox "No projects found in database" 10 60
        return 1
    fi

    # Generate project selection menu options
    local -a project_options
    local index title path notes
    for index in "${!lines[@]}"; do
        IFS='|' read -r title path notes <<< "${lines[index]}"
        project_options+=("$index" "$path")
    done

    # Show project selection menu
    local selected_project
    selected_project=$(whiptail --title "Select Project" --menu "Choose a project:" \
        20 80 10 "${project_options[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then return 1; fi  # User canceled

    # Get selected project details
    local line="${lines[selected_project]}"
    IFS='|' read -r title path notes <<< "$line"

    # Check for existing notes
    if [[ -z "$notes" ]]; then
        whiptail --msgbox "Selected project has no associated notes" 10 60
        return 1
    fi

    # Split notes into array
    local -a notes_arr
    IFS=',' read -ra notes_arr <<< "$notes"
    if [[ ${#notes_arr[@]} -eq 0 ]]; then
        whiptail --msgbox "Selected project has no associated notes" 10 60
        return 1
    fi

    # Generate note selection menu options
    local -a note_options
    local note_index
    for note_index in "${!notes_arr[@]}"; do
        note_options+=("$note_index" "${notes_arr[note_index]}")
    done

    # Show note selection menu
    local selected_note
    selected_note=$(whiptail --title "Select Note" --menu "Choose note to remove:" \
        20 80 10 "${note_options[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then return 1; fi  # User canceled

    # Remove selected note from array
    local -a new_notes
    for note_index in "${!notes_arr[@]}"; do
        if [[ $note_index -ne $selected_note ]]; then
            new_notes+=("${notes_arr[note_index]}")
        fi
    done

    # Update the database entry
    local new_notes_str
    if [[ ${#new_notes[@]} -gt 0 ]]; then
        new_notes_str=$(IFS=','; printf '%s' "${new_notes[*]}")
    else
        new_notes_str=""
    fi

    lines[selected_project]="$title|$path|$new_notes_str"

    # Write updated database
    local tmp_db
    tmp_db=$(mktemp) || return 1
    printf "%s\n" "${lines[@]}" > "$tmp_db"
    mv -- "$tmp_db" "$PROJECTS_DB" || { rm -- "$tmp_db"; return 1; }

    whiptail --msgbox "Note successfully dissociated from project" 10 60
}
