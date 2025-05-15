PROJECTS_METADATA_DIR="./projects/metadata"
PROJECTS_DIR="./projects"
PROJECTS_DB="${PROJECTS_METADATA_DIR}/projects.db"

mkdir -p "$PROJECTS_METADATA_DIR" "$PROJECTS_DIR"

delete_project() {
    # Check if projects database exists and is readable
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --title "Error" --msgbox "Project database not found or empty." 8 50
        return 1
    fi

    # Read all project entries into an array
    local lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done < "$PROJECTS_DB"

    # Check for empty database
    if [[ ${#lines[@]} -eq 0 ]]; then
        whiptail --title "Error" --msgbox "No projects found in database." 8 50
        return 1
    fi

    # Extract project paths and build menu options
    local paths=()
    local options=()
    for i in "${!lines[@]}"; do
        IFS='|' read -ra parts <<< "${lines[i]}"
        if [[ ${#parts[@]} -ge 2 ]]; then
            paths+=("${parts[1]}")
            options+=("$((i+1))" "${parts[1]}")
        else
            paths+=("Invalid entry")
            options+=("$((i+1))" "Invalid project entry")
        fi
    done

    # Show selection menu
    local selected
    selected=$(whiptail --title "Delete Project" --menu "Choose a project to delete:" \
        20 60 10 "${options[@]}" 3>&1 1>&2 2>&3) || return 1
    
    [[ -z "$selected" ]] && return 1  # User canceled

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
