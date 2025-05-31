dissoc_tag_by_filepath() {
    # Check if databases exist
    if [[ ! -f "$TAGS_DB" || ! -f "$EBOOKS_DB" ]]; then
        whiptail --msgbox "Error: Databases missing. Verify TAGS_DB and EBOOKS_DB exist." 10 60
        return 1
    fi

    # Read tags into array
    local tags=()
    if ! mapfile -t tags < "$TAGS_DB"; then
        whiptail --msgbox "Error: Failed to read tags database." 10 60
        return 1
    fi

    # Check if tags exist
    if [[ ${#tags[@]} -eq 0 ]]; then
        whiptail --msgbox "No tags found in database. Add tags first." 10 60
        return 1
    fi

    # Build tag selection menu
    local tag_menu_items=()
    for tag in "${tags[@]}"; do
        tag_menu_items+=("$tag" "")
    done

    # Select tag
    local selected_tag
    selected_tag=$(whiptail --title "Remove Tag" --menu "Choose a tag to remove:" \
        15 $(( ${#tag_menu_items[@]} * 2 + 7 )) "${tag_menu_items[@]}" 3>&1 1>&2 2>&3)
    
    [[ -z "$selected_tag" ]] && return  # User canceled

    # Get unique directories
    local dirs
    dirs=$(cut -d'|' -f1 "$EBOOKS_DB" | sed -E 's:/[^/]+$::' | sort | uniq)
    
    # Check if directories exist
    if [[ -z "$dirs" ]]; then
        whiptail --msgbox "No directories found in ebooks database." 10 60
        return 1
    fi

    # Build directory menu
    local dir_menu_items=()
    while IFS= read -r dir; do
        dir_menu_items+=("$dir" "")
    done <<< "$dirs"

    # Select directory
    local selected_dir
    selected_dir=$(whiptail --title "Select Directory" --menu "Choose directory to remove tag from:" \
        15 $(( ${#dir_menu_items[@]} * 2 + 7 )) "${dir_menu_items[@]}" 3>&1 1>&2 2>&3)
    
    [[ -z "$selected_dir" ]] && return  # User canceled

    # Get matching lines
    local matching_lines
    matching_lines=$(grep -F "$selected_dir/" "$EBOOKS_DB")
    
    # Check for matches
    if [[ -z "$matching_lines" ]]; then
        whiptail --msgbox "No ebooks found in directory: $selected_dir" 10 60
        return 1
    fi

    # Prepare confirmation message
    local file_count
    file_count=$(wc -l <<< "$matching_lines")
    local sample_files
    sample_files=$(head -n 5 <<< "$matching_lines" | cut -d'|' -f1 | sed 's:.*/::')
    local message="Directory: $selected_dir\nTag: $selected_tag\nFiles: $file_count\n\nSample files:\n$sample_files"
    [[ $file_count -gt 5 ]] && message+="\n...and $((file_count - 5)) more"

    # Confirm action
    whiptail --yesno --title "Confirm Removal" \
        "Remove tag from ALL files in directory?\n\n$message" \
        20 60 --yes-button "Remove" --no-button "Cancel" || return

    # Process updates
    local temp_db
    temp_db=$(mktemp)
    local removed=0

    while IFS= read -r line; do
        local filepath="${line%%|*}"
        local tags_str="${line#*|}"
        local parent_dir="${filepath%/*}"

        # Only process files in selected directory
        if [[ "$parent_dir" == "$selected_dir" ]]; then
            # Check if tag exists
            if [[ ",${tags_str}," == *",${selected_tag},"* ]]; then
                # Remove tag using pattern substitution
                tags_str=${tags_str//,$selected_tag/}  # Remove tag with leading comma
                tags_str=${tags_str//$selected_tag,/}  # Remove tag with trailing comma
                tags_str=${tags_str//$selected_tag/}   # Remove standalone tag
                
                # Clean up potential double commas
                tags_str=${tags_str//,,/,}
                
                # Remove leading/trailing commas
                tags_str=${tags_str#,}
                tags_str=${tags_str%,}
                
                # Remove any empty tag strings
                [[ -z "$tags_str" ]] && tags_str=""
                
                echo "${filepath}|${tags_str}" >> "$temp_db"
                ((removed++))
            else
                # Tag not present - keep original line
                echo "$line" >> "$temp_db"
            fi
        else
            # Not in selected directory - keep original line
            echo "$line" >> "$temp_db"
        fi
    done < "$EBOOKS_DB"

    # Replace original database
    if ! mv "$temp_db" "$EBOOKS_DB"; then
        whiptail --msgbox "Error: Failed to update database." 10 60
        return 1
    fi

    # Show results
    if ((removed > 0)); then
        whiptail --msgbox "Successfully removed '$selected_tag' from $removed files." 10 60
    else
        whiptail --msgbox "No changes made. The tag was not found in any files." 10 60
    fi
}
