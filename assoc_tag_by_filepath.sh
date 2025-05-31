EBOOKS_DB='ebooks.db'
TAGS_DB='tags.db'

assoc_tag_by_filepath() {
    # Help message
    whiptail --title "Help" \
         --msgbox "This function will associate your chosen tag to every file in a directory that you choose. \
You may choose from a list of directories registered in the ebooks db." 12 80 >/dev/tty

    # Check if databases exist
    if [[ ! -s "$TAGS_DB" || ! -s "$EBOOKS_DB" ]]; then
        whiptail --msgbox "Error: Tags db or Ebooks db are empty. Register at least one ebook and tag." 10 60 >/dev/tty
        return 1
    fi

    # Read tags into array
    local tags=()
    if ! mapfile -t tags < "$TAGS_DB"; then
        whiptail --msgbox "Error: Failed to read tags database." 10 60 >/dev/tty
        return 1
    fi

    # Check if tags exist
    if [[ ${#tags[@]} -eq 0 ]]; then
        whiptail --msgbox "No tags found in database. Add tags first." 10 60 >/dev/tty
        return 1
    fi

    # Build tag selection menu
    local tag_menu_items=()
    for tag in "${tags[@]}"; do
        tag_menu_items+=("$tag" "")
    done

    # Select tag
    local selected_tag
    selected_tag=$(whiptail --title "Select Tag" --menu "Choose a tag to associate:" \
        20 150 10 "${tag_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    
    [[ -z "$selected_tag" ]] && return 1 # User canceled

    # Get unique directories
    local dirs
    dirs=$(cut -d'|' -f1 "$EBOOKS_DB" | sed -E 's:/[^/]+$::' | sort | uniq)
    
    # Check if directories exist
    if [[ -z "$dirs" ]]; then
        whiptail --msgbox "No directories found in ebooks database." 10 60 >/dev/tty
        return 1
    fi

    # Build directory menu
    local dir_menu_items=()
    while IFS= read -r dir; do
        dir_menu_items+=("$dir" "")
    done <<< "$dirs"

    # Select directory
    local selected_dir
    selected_dir=$(whiptail --title "Select Directory" --menu "Choose directory to tag:" \
        20 150 10 "${dir_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    
    [[ -z "$selected_dir" ]] && return  # User canceled

    # Escape special regex characters in directory path
    local escaped_dir="$selected_dir"
    #local escaped_dir="${selected_dir//\//\\/}"
    #escaped_dir="${escaped_dir//./\\.}"
    #escaped_dir="${escaped_dir//|/\\|}"
    #escaped_dir="${escaped_dir//^/\\^}"
    #escaped_dir="${escaped_dir//\$/\\\$}"
    #escaped_dir="${escaped_dir//+/\\+}"
    #escaped_dir="${escaped_dir//(/\(}"
    #escaped_dir="${escaped_dir//)/\)}"
    #escaped_dir="${escaped_dir//\[/\[}"
    #escaped_dir="${escaped_dir//]/\]}"
    #escaped_dir="${escaped_dir//\{/\{}"
    #escaped_dir="${escaped_dir//\}/\}}"

    # Get matching lines
    local matching_lines
    matching_lines=$(grep -E "^${escaped_dir}/[^/]+\|" "$EBOOKS_DB")
    
    # Check for matches
    if [[ -z "$matching_lines" ]]; then
        whiptail --msgbox "No ebooks found in directory: $selected_dir" 10 60 >/dev/tty
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
    whiptail --scrolltext --yesno --title "Confirm Association" \
        "Add tag to ALL files in directory?\n\n$message" \
        20 60 --yes-button "Associate" --no-button "Cancel" </dev/tty >/dev/tty || return 1

	# Create temporary file for new database
	local temp_db
	temp_db=$(mktemp) || return 1
	local updated=0

	# Process every line in EBOOKS_DB
	while IFS= read -r line; do
		local filepath="${line%%|*}"
		local tags_str="${line#*|}"
    
		# Extract directory portion from filepath
		local parent_dir="${filepath%/*}"

		# Check if this file is in the selected directory
		if [[ "$parent_dir" == "$selected_dir" ]]; then
			# This file is in our target directory - check tag
			if [[ ",${tags_str}," == *",${selected_tag},"* ]]; then
				# Tag already exists - keep original line
				echo "$line" >> "$temp_db"
			else
				# Add new tag
				if [[ -z "$tags_str" ]]; then
					echo "${filepath}|${selected_tag}" >> "$temp_db"
				else
					echo "${filepath}|${tags_str},${selected_tag}" >> "$temp_db"
				fi
				((updated++))
			fi
		else
			# Not in selected directory - keep original line
			echo "$line" >> "$temp_db"
		fi
	done < "$EBOOKS_DB"    

    # Replace original database
    if ! mv "$temp_db" "$EBOOKS_DB"; then
        whiptail --msgbox "Error: Failed to update database." 10 60 >/dev/tty
        return 1
    fi

    # Show results
    whiptail --msgbox "Successfully updated ${updated} files with '${selected_tag}' tag." 10 60
}

# Test
assoc_tag_by_filepath
