edit_project() {
    local metadata_dir="./projects/metadata"
    local projects_dir="./projects"
    PROJECTS_DB="${metadata_dir}/projects.db"

    mkdir -p "$metadata_dir" "$projects_dir"

    # Check if projects database exists and has entries
    [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]] && {
        whiptail --msgbox "No projects found." 8 40
        return 1
    }

    # Read all projects into array
    local lines=()
    mapfile -t lines < "$PROJECTS_DB"

    # Create selection menu
    local menu_options=()
    for index in "${!lines[@]}"; do
        IFS='|' read -r title _ _ <<< "${lines[$index]}"
        menu_options+=("$index" "$title")
    done

    # Let user select project
    local selected_index
    selected_index=$(whiptail --menu "Select a project to edit:" 20 150 10 \
        "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1

    # Parse selected project
    local old_title old_path old_notes
    IFS='|' read -r old_title old_path old_notes <<< "${lines[$selected_index]}"

    # Verify project file exists
    [[ ! -f "$old_path" ]] && {
        whiptail --msgbox "Project file not found: $old_path" 10 60
        return 1
    }

    # Load existing headings and indentation
    local headings=()
    local indent_levels=()
    # Read the selected project file line by line
    # and populate headings and indent_levels
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local spaces="${line%%[^ ]*}"
        local length=${#spaces}
        local indent=$(( length / 4 ))
        local heading="${line#$spaces}"
        headings+=("$heading")
        indent_levels+=("$indent")
    done < "$old_path"

    # Main project menu
    local project_title="$old_title"
    local project_path="$old_path"
    local new_title project_action
    while true; do
        project_action=$(whiptail --menu "Project Configuration" 15 150 3 \
            "Project title" "Current: ${project_title:-<not set>}" \
            "Project path" "Status: ${project_path}" \
            "Proceed" "" 3>&1 1>&2 2>&3) || return 1

        case "$project_action" in
            "Project title")
                new_title=$(whiptail --inputbox "Enter project title:" 8 78 \
                    "$project_title" 3>&1 1>&2 2>&3)
                if [[ -z "$new_title" ]]; then
                    whiptail --msgbox "Project title can't be empty." 8 45
                    continue
                fi
                project_title="$new_title"
                ;;
            "Project path")
				continue
				;;
            "Proceed")
                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title is required." 8 45
                    continue
                }
                break
                ;;
            *) return 1 ;;            
        esac
    done

    # Headings management
    local heading_menu
    rebuild_heading_menu() {
        heading_menu=("Add new heading" "")
        for i in "${!headings[@]}"; do
            indent_spaces=$(( indent_levels[i] * 4 ))
            indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
            heading_menu+=("$i" "${indented_heading:0:130}")
        done
    }

    while true; do
        rebuild_heading_menu
        local heading_action
        heading_action=$(whiptail --menu "Project: ${project_title}" 20 150 10 \
            "${heading_menu[@]}" "Save and return" "" 3>&1 1>&2 2>&3) || return 1

        case "$heading_action" in
            "Add new heading")
				local new_heading
                new_heading=$(whiptail --inputbox "Enter new heading:" 8 78 3>&1 1>&2 2>&3)
                [[ -n "$new_heading" ]] && {
                    headings+=("$new_heading")
                    indent_levels+=(0)
                }
                ;;
            "Save and return")
                break
                ;;
            *)
                if [[ "$heading_action" =~ ^[0-9]+$ ]]; then
                    local selected_index=$heading_action
                    local heading_operation
                    heading_operation=$(whiptail --menu "Heading Operations" 20 60 7 \
                        "Change text" "" \
                        "Move before" "" \
                        "Move after" "" \
                        "Indent left" "" \
                        "Indent right" "" \
                        "Remove heading" "" 3>&1 1>&2 2>&3)

                    case "$heading_operation" in
                        "Change text")
							local new_text
                            new_text=$(whiptail --inputbox "Enter new heading text:" 8 78 \
                                "${headings[$selected_index]}" 3>&1 1>&2 2>&3)
                            headings[$selected_index]="$new_text"	# what happens when new text is ""?
                            ;;
                        "Move before"|"Move after")
                            local targets=()
                            for i in "${!headings[@]}"; do
                                [[ $i -ne $selected_index ]] && {
                                    indent_spaces=$(( indent_levels[i] * 4 ))
                                    indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
                                    targets+=("$i" "$indented_heading")
                                }
                            done

                            local target_index
                            target_index=$(whiptail --menu "Select target heading:" 20 150 10 \
                                "${targets[@]}" 3>&1 1>&2 2>&3)
                            [[ -z "$target_index" ]] && continue

                            local original_source_pos=$selected_index
                            local original_target_pos=$target_index
                            local moving_heading="${headings[$original_source_pos]}"
                            local moving_indent="${indent_levels[$original_source_pos]}"

                            # Remove source heading
                            headings=("${headings[@]:0:$original_source_pos}" 
                                "${headings[@]:$((original_source_pos+1))}")
                            indent_levels=("${indent_levels[@]:0:$original_source_pos}" 
                                "${indent_levels[@]:$((original_source_pos+1))}")

                            # Adjust target position
                            if (( original_source_pos < original_target_pos )); then
                                adjusted_target_pos=$((original_target_pos - 1))
                            else
                                adjusted_target_pos=$original_target_pos
                            fi

                            [[ "$heading_operation" == "Move after" ]] && ((adjusted_target_pos++))

                            # Insert at new position
                            headings=("${headings[@]:0:$adjusted_target_pos}" 
                                "$moving_heading" 
                                "${headings[@]:$adjusted_target_pos}")
                            indent_levels=("${indent_levels[@]:0:$adjusted_target_pos}" 
                                "$moving_indent" 
                                "${indent_levels[@]:$adjusted_target_pos}")
                            ;;
                        "Indent right")
                            (( indent_levels[$selected_index]++ ))
                            ;;
                        "Indent left")
                            (( indent_levels[$selected_index] = indent_levels[$selected_index] > 0 ? 
                                indent_levels[$selected_index]-1 : 0 ))
                            ;;
                        "Remove heading")
                            headings=("${headings[@]:0:$selected_index}" 
                                "${headings[@]:$((selected_index+1))}")
                            indent_levels=("${indent_levels[@]:0:$selected_index}" 
                                "${indent_levels[@]:$((selected_index+1))}")
                            ;;
                        *) ;;
                    esac
                fi
                ;;
        esac
    done

    # Save updated project file
    {
        for i in "${!headings[@]}"; do
            printf "%$((indent_levels[i]*4))s%s\n" "" "${headings[$i]}"
        done
    } > "$project_path"

    # Update projects database
    lines[$selected_index]="${project_title}|${project_path}|${old_notes}"
    printf "%s\n" "${lines[@]}" > "$PROJECTS_DB"
}

edit_project
