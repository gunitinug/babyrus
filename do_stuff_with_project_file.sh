open_note_ebook_page_from_project() {
    local selected_line="$1"
    [[ -z "$selected_line" ]] && return 1

    local selected_ebook=$(get_ebooks "$selected_line")
    [[ -z "$selected_ebook" ]] && return 1

    # Extract the chapters part from the selected_ebook
    local chapters_part=$(cut -d'#' -f2 <<< "$selected_ebook")

    if [[ -n "$chapters_part" ]]; then
        # Chapters are present, prompt user to select one
        local selected_chapter=$(get_chapters "$selected_ebook")
        if [ -n "$selected_chapter" ]; then
            local page=$(extract_page "$selected_chapter")
            [[ -z "$page" ]] && return 1
            open_evince "$selected_ebook" "$page"
        #else
        #    # User canceled chapter selection; open without page
        #    open_evince "$selected_ebook"
        fi
    else
        # No chapters available; ask to open the ebook directly
        #open_evince "$selected_ebook"
        handle_no_chapters "$selected_ebook"
    fi
}

do_stuff_with_project_file() {
    #local PROJECTS_DB="$PROJECTS_DB"
    #local NOTES_DB="$NOTES_DB"
    
    # Read all projects into array
    local projects=()
    while IFS= read -r line; do
        projects+=("$line")
    done < "$PROJECTS_DB"
    
    if [ ${#projects[@]} -eq 0 ]; then
        whiptail --msgbox "No projects found in $PROJECTS_DB" 20 60 >/dev/tty
        return 1
    fi

    # Create project selection menu
    local project_menu_options=()
    for index in "${!projects[@]}"; do
        IFS='|' read -r title _ _ <<< "${projects[$index]}"
        project_menu_options+=("$((index + 1))" "$title")
    done

    # Show project selection
    local selected_project_tag
    selected_project_tag=$(whiptail --menu "Select Project" 20 78 12 "${project_menu_options[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1

    local selected_project_index=$((selected_project_tag - 1))
    local selected_project_line="${projects[$selected_project_index]}"
    IFS='|' read -r _ _ associated_notes <<< "$selected_project_line"

    # Process associated notes
    local note_paths=()
    IFS=',' read -ra note_paths <<< "$associated_notes"
    local note_lines=() 
    local note_menu_options=()

    for np in "${note_paths[@]}"; do
        while IFS= read -r line; do
            IFS='|' read -r title path _ _ <<< "$line"
            if [ "$path" = "$np" ]; then
                note_lines+=("$line")
                note_menu_options+=("${#note_lines[@]}" "$title")
                break
            fi
        done < "$NOTES_DB"
    done

    if [ ${#note_menu_options[@]} -eq 0 ]; then
        whiptail --msgbox "No notes found for selected project" 20 60
        return 1
    fi

    # Show note selection
    local selected_note_tag
    selected_note_tag=$(whiptail --menu "Select Note" 20 78 12 "${note_menu_options[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1

    local selected_note_index=$((selected_note_tag - 1))
    local selected_note_line="${note_lines[$selected_note_index]}"

    # Action selection
    local action
    action=$(whiptail --menu "Note Action" 15 50 5 \
        "1" "View Note" \
        "2" "Open ebooks" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1

    case "$action" in
        "1")
            IFS='|' read -r _ note_path _ _ <<< "$selected_note_line"
            whiptail --textbox "$note_path" 20 80
            ;;
        "2")
            open_note_ebook_page_from_project "$selected_note_line"
            ;;
    esac
}
