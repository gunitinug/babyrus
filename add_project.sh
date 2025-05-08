#!/bin/bash

add_project() {
    local project_title="New Project"
    local project_path=""
    local headings=()
    local indent_levels=()
    local move_source=""
    local metadata_dir="./projects/metadata"
    local projects_dir="./projects"

    mkdir -p "$metadata_dir" "$projects_dir"

    # Main project menu
    while true; do
        local project_action=$(whiptail --menu "Project Configuration" 15 50 3 \
            "Project title" "$project_title" \
            "Project path" "$project_path" \
            "Proceed" "" 3>&1 1>&2 2>&3)

        case $project_action in
            "Project title")
                project_title=$(whiptail --inputbox "Enter project title" 8 78 "$project_title" 3>&1 1>&2 2>&3)
                project_path="${projects_dir}/${project_title}-$(date +%s).txt"
                ;;
            "Proceed")
                [[ -z "$project_title" ]] && { echo "Project title is required"; continue; }
                break
                ;;
            *) return 1 ;;
        esac
    done

    # Headings management
    local heading_menu=("Add new heading" "")
    while true; do
        local heading_action=$(whiptail --menu "Headings Configuration" 20 60 10 \
            "${heading_menu[@]}" "Save and return" "" 3>&1 1>&2 2>&3)

        case $heading_action in
            "Add new heading")
                local new_heading=$(whiptail --inputbox "Enter new heading" 8 78 3>&1 1>&2 2>&3)
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
                    local selected_index=-1
                    for i in "${!heading_menu[@]}"; do
                        [[ "${heading_menu[$i]}" == "$heading_action" ]] && { selected_index=$((i/2)); break; }
                    done

                    # Heading operations menu
                    local heading_operation=$(whiptail --menu "Heading Operations" 20 60 7 \
                        "Change text" "" \
                        "Move before" "" \
                        "Move after" "" \
                        "Indent left" "" \
                        "Indent right" "" \
                        "Remove heading" "" \
                        "Save and return" "" 3>&1 1>&2 2>&3)

                    case $heading_operation in
                        "Change text")
                            local new_text=$(whiptail --inputbox "Enter new text" 8 78 "${headings[$selected_index]}" 3>&1 1>&2 2>&3)
                            headings[$selected_index]="$new_text"
                            heading_menu[$((selected_index*2+1))]="${indent_levels[$selected_index]}"
                            ;;
                        "Move before"|"Move after")
                            move_source="$selected_index"
                            local targets=()
                            for i in "${!headings[@]}"; do
                                [[ $i -ne $move_source ]] && targets+=("${headings[$i]}" "")
                            done
                            local target=$(whiptail --menu "Select target heading" 20 60 10 "${targets[@]}" 3>&1 1>&2 2>&3)
                            [[ -z "$target" ]] && continue
                            local target_index=-1
                            for i in "${!headings[@]}"; do
                                [[ "${headings[$i]}" == "$target" ]] && { target_index=$i; break; }
                            done

                            if [[ "$heading_operation" == "Move before" ]]; then
                                headings=("${headings[@]:0:$target_index}" "${headings[$move_source]}" "${headings[@]:$target_index}")
                                indent_levels=("${indent_levels[@]:0:$target_index}" "${indent_levels[$move_source]}" "${indent_levels[@]:$target_index}")
                            else
                                ((target_index++))
                                headings=("${headings[@]:0:$target_index}" "${headings[$move_source]}" "${headings[@]:$target_index}")
                                indent_levels=("${indent_levels[@]:0:$target_index}" "${indent_levels[$move_source]}" "${indent_levels[@]:$target_index}")
                            fi
                            # Rebuild menu
                            heading_menu=("Add new heading" "")
                            for i in "${!headings[@]}"; do
                                heading_menu+=("${headings[$i]}" "${indent_levels[$i]}")
                            done
                            ;;
                        "Indent left")
                            (( indent_levels[$selected_index]++ ))
                            heading_menu[$((selected_index*2+1))]="${indent_levels[$selected_index]}"
                            ;;
                        "Indent right")
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
    local timestamp=$(date +%s)
    local project_file="${projects_dir}/${project_title}-${timestamp}.txt"
    {
        for i in "${!headings[@]}"; do
            printf "%${indent_levels[$i]}s%s\n" "" "${headings[$i]}"
        done
    } > "$project_file"

    # Update projects database
    local projects_db="${metadata_dir}/PROJECTS_DB"
    echo "${project_title}|${project_file}|" >> "$projects_db"
}
