EBOOKS_DB='ebooks.db'

remove_files_by_filepath_recursive() {
    # Inform user of the purpose
    whiptail --title "Attention" --msgbox "This function allows user to remove all files under file path including files in sub-directories. \
If a file has a tag associated with it, it will not be removed." 12 78 >/dev/tty

    # Get unique directories
    local directories
    directories=$(cut -d'|' -f1 "${EBOOKS_DB}" | sed -E 's:/[^/]+$::' | sort | uniq)
    
    # Check if there are any directories
    if [[ -z "$directories" ]]; then
        whiptail --title "Error" --msgbox "No directories found in the database." 8 50 >/dev/tty
        return 1
    fi

    # Create whiptail menu options
    local menu_options=()
    while IFS= read -r dir; do
        menu_options+=("$dir" "")
    done <<< "$directories"

    # Show directory selection menu
    local selected_dir
    selected_dir=$(whiptail --title "Select Directory" --menu "Choose a root directory to remove files from:" 20 150 12 "${menu_options[@]}" 3>&1 1>&2 2>&3) </dev/tty >/dev/tty
    
    # Exit if user cancelled
    if [[ -z "$selected_dir" ]]; then
        return 1
    fi

	# Find files to delete (those without tags)
	local files_to_delete=()
	local tagged_files=()
	while IFS= read -r line; do
		local filepath="${line%%|*}"
		local dirpath="${filepath%/*}"
		local tags="${line#*|}"
		
		if [[ "$dirpath" =~ ^"${selected_dir}"(/.*)?$ ]]; then
			if [[ -z "$tags" ]]; then
				files_to_delete+=("$filepath")
			else
				tagged_files+=("$filepath")
			fi
		fi
	done < "$EBOOKS_DB"

    # Check if there are files to delete
    if [[ ${#files_to_delete[@]} -eq 0 ]]; then
        whiptail --title "Information" --msgbox "No files found to delete in '$selected_dir' without tags." 10 70 >/dev/tty
        return 1
    fi

    # Show confirmation dialog
    local confirm_msg="About to delete ${#files_to_delete[@]} files from '$selected_dir' (recursive).\n\nFiles with tags will not be deleted."
    if ! whiptail --title "Confirm Deletion" --yesno "$confirm_msg" 15 78; then
        return 1
    fi

    # Backup the database file
    local backup_file="${EBOOKS_DB}.backup"
    cp "$EBOOKS_DB" "$backup_file"

    # Remove entries from the database    
    grep -v -E "^${selected_dir}(/.*)?\|$" "$EBOOKS_DB" > "${EBOOKS_DB}.tmp" && mv "${EBOOKS_DB}.tmp" "$EBOOKS_DB"

    # Show deleted files
    local deleted_msg="Removed files from ebooks db:\n\n$(printf '%s\n' "${files_to_delete[@]:0:10}")"
    if [[ ${#files_to_delete[@]} -gt 10 ]]; then
        deleted_msg+="\n..."
    fi
    whiptail --title "Files Removed" --msgbox "$deleted_msg" 20 78

    # Show tagged files that were excluded
    if [[ ${#tagged_files[@]} -gt 0 ]]; then
        local excluded_msg="The following files were not deleted because they have tag(s):\n\n$(printf '%s\n' "${tagged_files[@]:0:10}")"
        if [[ ${#tagged_files[@]} -gt 10 ]]; then
            excluded_msg+="\n..."
        fi
        excluded_msg+="\n\nPlease dissociate tag(s) from these files first."
        whiptail --title "Tagged Files Excluded" --msgbox "$excluded_msg" 20 78
    fi

    return 0
}

remove_files_by_filepath_recursive
