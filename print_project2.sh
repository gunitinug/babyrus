PROJECTS_METADATA_DIR="./projects/metadata"
PROJECTS_DIR="./projects"
PROJECTS_DB="${PROJECTS_METADATA_DIR}/projects.db"

mkdir -p "$PROJECTS_METADATA_DIR" "$PROJECTS_DIR"

print_project() {
    local line_num=0
    local options=()

    # Check if database file exists and is valid
    if [ ! -f "$PROJECTS_DB" ]; then
        whiptail --msgbox "Error: Project database '$PROJECTS_DB' not found." 10 50 >/dev/tty
        return 1
    elif [ ! -s "$PROJECTS_DB" ]; then
        whiptail --msgbox "Error: Project database '$PROJECTS_DB' is empty." 10 50 >/dev/tty
        return 1
    fi

    local line title path

    # Parse project entries (unchanged)
    while IFS= read -r line || [ -n "$line" ]; do
        ((line_num++))
        [ -z "$line" ] && continue

        IFS='|' read -r title path _ <<< "$line"
        if [ -z "$title" ] || [ -z "$path" ]; then
            whiptail --msgbox "Skipping invalid entry (line $line_num): Missing field(s)" 10 50 >/dev/tty
            continue
        fi
        options+=("$line_num" "$title")
    done < "$PROJECTS_DB"

    if [ ${#options[@]} -eq 0 ]; then
        whiptail --msgbox "Error: No valid projects found in database." 10 50 >/dev/tty
        return 1
    fi

    # Continuous selection loop added here
    while true; do
        # Show project selection menu
        local selected_line
        selected_line=$(whiptail --menu "Choose project to view content:" 20 150 10 "${options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        [ $? -ne 0 ] && break  # Exit loop on cancel
        
        # Rest of the original processing logic
        local line_=$(sed -n "${selected_line}p" "$PROJECTS_DB")
        if [ -z "$line_" ]; then
            whiptail --msgbox "Error: Selected project no longer exists." 10 50 >/dev/tty
            continue  # Continue loop instead of returning
        fi

        local title_ path_
        IFS='|' read -r title_ path_ _ <<< "$line_"

        if [ ! -e "$path_" ]; then
            whiptail --msgbox "Error: Project file '$path' not found." 10 50 >/dev/tty
            continue
        elif [ -d "$path_" ]; then
            whiptail --msgbox "Error: '$path' is a directory, not a file." 10 50 >/dev/tty
            continue
        elif [ ! -r "$path_" ]; then
            whiptail --msgbox "Error: Cannot read project file '$path'." 10 50 >/dev/tty
            continue
        fi

        local tmpfile
        tmpfile=$(mktemp) || {
            whiptail --msgbox "Error: Failed to create temporary file." 10 50 >/dev/tty
            continue
        }
        cat "$path_" > "$tmpfile"
        whiptail --scrolltext --textbox "$tmpfile" 20 80
        rm -f "$tmpfile"
    done
}

print_project
