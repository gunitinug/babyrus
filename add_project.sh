add_project() {
    local project_title=""
    local project_path=""
    local headings=()
    local indent_levels=()
    local metadata_dir="./projects/metadata"
    local projects_dir="./projects"
    PROJECTS_DB="${metadata_dir}/projects.db"

    mkdir -p "$metadata_dir" "$projects_dir"

    # Function to rebuild heading menu with visual indentation
    rebuild_heading_menu() {
        heading_menu=("Add new heading" "")
        for i in "${!headings[@]}"; do
            indent_spaces=$(( indent_levels[i] * 4 ))
            indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
            heading_menu+=("$i" "${indented_heading:0:130}")
        done
    }

    # Main project menu
    while true; do
		local project_action
        project_action=$(whiptail --menu "Project Configuration" 15 150 3 \
            "Project title" "Current: ${project_title:-<not set>}" \
            "Project path" "Status: ${project_path:-(will be generated)}" \
            "Proceed" "" 3>&1 1>&2 2>&3) || return 1

        case $project_action in
            "Project title")
                project_title=$(whiptail --inputbox "Enter project title" 8 78 "$project_title" 3>&1 1>&2 2>&3)
                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title can't be empty." 8 45
                    continue
                }
                project_path="${projects_dir}/${project_title}-$(date "+%d%m%Y-%H%M%S").txt"
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
    while true; do
        rebuild_heading_menu
        local heading_action
        heading_action=$(whiptail --menu "Project: ${project_title}" 20 150 10 \
            "${heading_menu[@]}" "Save and return" "" 3>&1 1>&2 2>&3) || return 1

        case $heading_action in
            "Add new heading")
				local new_heading
                new_heading=$(whiptail --inputbox "Enter new heading:" 8 78 3>&1 1>&2 2>&3)
                if [[ -n "$new_heading" ]]; then
                    headings+=("$new_heading")
                    indent_levels+=(0)
                fi
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

                    case $heading_operation in
                        "Change text")
							local new_text
                            new_text=$(whiptail --inputbox "Enter new heading text:" 8 78 \
                                "${headings[$selected_index]}" 3>&1 1>&2 2>&3)
                            headings[$selected_index]="$new_text"
                            ;;
                        "Move before"|"Move after")
                            # Get target position using indices
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
                            target_index=$((target_index))

                            # Store original positions
                            local original_source_pos=$selected_index
                            local original_target_pos=$target_index
                            local moving_heading="${headings[$original_source_pos]}"
                            local moving_indent="${indent_levels[$original_source_pos]}"

                            # Remove source from original position
                            headings=(
                                "${headings[@]:0:$original_source_pos}"
                                "${headings[@]:$((original_source_pos+1))}"
                            )
                            indent_levels=(
                                "${indent_levels[@]:0:$original_source_pos}"
                                "${indent_levels[@]:$((original_source_pos+1))}"
                            )

                            # Adjust target index for new array
                            if (( original_source_pos < original_target_pos )); then
                                adjusted_target_pos=$((original_target_pos - 1))
                            else
                                adjusted_target_pos=$original_target_pos
                            fi

                            # Apply "Move after" adjustment
                            if [[ "$heading_operation" == "Move after" ]]; then
                                ((adjusted_target_pos++))
                            fi

                            # Insert at new position
                            headings=(
                                "${headings[@]:0:$adjusted_target_pos}"
                                "$moving_heading"
                                "${headings[@]:$adjusted_target_pos}"
                            )
                            indent_levels=(
                                "${indent_levels[@]:0:$adjusted_target_pos}"
                                "$moving_indent"
                                "${indent_levels[@]:$adjusted_target_pos}"
                            )
                            ;;                            
                        "Indent right")
                            (( indent_levels[$selected_index]++ ))
                            ;;
                        "Indent left")
                            (( indent_levels[$selected_index] = indent_levels[$selected_index] > 0 ? indent_levels[$selected_index]-1 : 0 ))
                            ;;
                        "Remove heading")
                            headings=("${headings[@]:0:$selected_index}" "${headings[@]:$((selected_index+1))}")
                            indent_levels=("${indent_levels[@]:0:$selected_index}" "${indent_levels[@]:$((selected_index+1))}")
                            ;;
                        *) ;;
                    esac
                fi
                ;;
        esac
    done

    # Save project file
    {
        for i in "${!headings[@]}"; do
            printf "%$((indent_levels[i]*4))s%s\n" "" "${headings[$i]}"
        done
    } > "$project_path"

    # Update projects database
    echo "${project_title}|${project_path}|" >> "$PROJECTS_DB"
}

add_project
