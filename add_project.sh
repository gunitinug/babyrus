#!/bin/bash

add_project() {	
    local project_title="New Project"
    local project_path=""
    local headings=()
    local indent_levels=()
    local move_source=""
    local metadata_dir="./projects/metadata"
    local projects_dir="./projects"
    PROJECTS_DB="${metadata_dir}/projects.db"

    mkdir -p "$metadata_dir" "$projects_dir"

    # Main project menu
    while true; do
		local project_action
        project_action=$(whiptail --menu "Project Configuration" 15 50 3 \
            "Project title" "$project_title" \
            "Project path" "$project_path" \
            "Proceed" "" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        case $project_action in
            "Project title")
                project_title=$(whiptail --inputbox "Enter project title" 8 78 "$project_title" 3>&1 1>&2 2>&3 </dev/tty)
                [[ -z "$project_title" ]] && {
					whiptail --title "Error" --msgbox "Project title can't be empty." 8 45 >/dev/tty
					continue
				}
                
                project_path="${projects_dir}/${project_title}-$(date "+%d%m%Y-%H%M%S").txt"
                ;;
            "Proceed")
                [[ -z "$project_title" ]] && {
					whiptail --title "Error" --msgbox "Project title is required." 8 45 >/dev/tty 
					continue
				}
                break
                ;;
            *) return 1 ;;
        esac
    done

    # Headings management
    local heading_menu=("Add new heading" "")
    while true; do
		local heading_action
        heading_action=$(whiptail --menu "Project Goals" 20 60 10 \
            "${heading_menu[@]}" "Save and return" "" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        case $heading_action in
            "Add new heading")
				local new_heading
                new_heading=$(whiptail --inputbox "Enter new heading" 8 78 3>&1 1>&2 2>&3 </dev/tty)
                if [[ -n "$new_heading" ]]; then
                    headings+=("$new_heading")
                    indent_levels+=(0)
                    heading_menu+=("${new_heading}" "0")
                fi
                ;;
            "Save and return")
                break
                ;;
            *)
                if [[ -n "$heading_action" ]]; then
					# Figure out selected_index for headings and indent_levels arrays for the selected heading item.
                    local selected_index=-1
                    for i in "${!heading_menu[@]}"; do
                        [[ "${heading_menu[$i]}" == "$heading_action" ]] && { selected_index=$((i/2)); break; }
                    done

                    # Heading operations menu
                    local heading_operation
                    heading_operation=$(whiptail --menu "Heading Operations" 20 60 7 \
                        "Change text" "" \
                        "Move before" "" \
                        "Move after" "" \
                        "Indent left" "" \
                        "Indent right" "" \
                        "Remove heading" "" \
                        "Save and return" "" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

                    case $heading_operation in
                        "Change text")
							local new_text
                            new_text=$(whiptail --inputbox "Enter new heading text" 8 78 "${headings[$selected_index]}" 3>&1 1>&2 2>&3)
                            headings[$selected_index]="$new_text"
                            heading_menu[$((selected_index*2+1))]="${indent_levels[$selected_index]}"
                            ;;
                        "Move before"|"Move after")
							# the move_source heading
                            move_source="$selected_index"
                            # targets array contains all heading_menu items except for the move_source (to be moved).
                            local targets=()
                            for i in "${!headings[@]}"; do
                                [[ $i -ne $move_source ]] && targets+=("${headings[$i]}" "")
                            done
                            local target
                            target=$(whiptail --menu "Select target heading" 20 60 10 "${targets[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
                            [[ -z "$target" ]] && continue
                            # Get the target_index from headings array. move_source is moved before or after the target.
                            local target_index=-1
                            for i in "${!headings[@]}"; do
                                [[ "${headings[$i]}" == "$target" ]] && { target_index=$i; break; }
                            done

							# Move before/after operations - fixed version
							if [[ "$heading_operation" == "Move before" || "$heading_operation" == "Move after" ]]; then
								# Store original positions and values
								local original_source_pos=$move_source
								local original_target_pos=$target_index
								local moving_heading="${headings[$original_source_pos]}"
								local moving_indent="${indent_levels[$original_source_pos]}"

								# Calculate adjusted target position after removal
								local adjusted_target_pos
								if (( original_source_pos < original_target_pos )); then
									adjusted_target_pos=$(( original_target_pos - 1 ))  # Account for source removal
								else
									adjusted_target_pos=$original_target_pos
								fi

								# Remove source element
								headings=("${headings[@]:0:$original_source_pos}" "${headings[@]:$((original_source_pos+1))}")
								indent_levels=("${indent_levels[@]:0:$original_source_pos}" "${indent_levels[@]:$((original_source_pos+1))}")

								# Adjust for "Move after"
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
							fi							

                            # Rebuild menu (from scratch)                            
                            heading_menu=("Add new heading" "")
                            for i in "${!headings[@]}"; do
                                heading_menu+=("${headings[$i]}" "${indent_levels[$i]}")
                            done
                            ;;
                        "Indent right")
                            (( indent_levels[$selected_index]++ ))
                            heading_menu[$((selected_index*2+1))]="${indent_levels[$selected_index]}"
                            ;;
                        "Indent left")
                            (( indent_levels[$selected_index] = indent_levels[$selected_index] > 0 ? indent_levels[$selected_index]-1 : 0 ))
                            heading_menu[$((selected_index*2+1))]="${indent_levels[$selected_index]}"
                            ;;
                        "Remove heading")
                            unset 'headings[$selected_index]'
                            unset 'indent_levels[$selected_index]'
                            headings=("${headings[@]}")
                            indent_levels=("${indent_levels[@]}")
                            # Rebuild menu
                            heading_menu=("Add new heading" "")
                            for i in "${!headings[@]}"; do
                                heading_menu+=("${headings[$i]}" "${indent_levels[$i]}")
                            done
                            ;;
                        *) ;;
                    esac
                fi
                ;;
        esac
    done

    # Save project file
    #local timestamp=$(date +%s)
    #local project_file="${projects_dir}/${project_title}-${timestamp}.txt" # we already have $project_path from above!
    local project_file="$project_path"
    {
        for i in "${!headings[@]}"; do
            printf "%${indent_levels[$i]}s%s\n" "" "${headings[$i]}"
        done
    } > "$project_file"

    # Update projects database    
    echo "${project_title}|${project_file}|" >> "$PROJECTS_DB"
}
