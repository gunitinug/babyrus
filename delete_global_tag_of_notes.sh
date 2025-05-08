BABYRUS_PATH="/my-projects/babyrus"
NOTES_PATH="${BABYRUS_PATH}/notes"
NOTES_METADATA_PATH="${NOTES_PATH}/metadata"
NOTES_DB="${NOTES_METADATA_PATH}/notes.db"
NOTES_TAGS_DB="${NOTES_METADATA_PATH}/notes-tags.db"
NOTES_EBOOKS_DB="${NOTES_METADATA_PATH}/notes-ebooks.db"
EBOOKS_DB="${BABYRUS_PATH}/ebooks.db"

delete_global_tag_of_notes() {
    # Check if tags database exists and isn't empty
    if [[ ! -f "$NOTES_TAGS_DB" || ! -s "$NOTES_TAGS_DB" ]]; then
        whiptail --msgbox "There are no registered tags." 10 50 >/dev/tty
        return 1
    fi

	# Check if notes database exists and isn't empty
	if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
		whiptail --msgbox "There are no registered notes." 10 50 >/dev/tty
		return 1
	fi

    # Read all tags into an array
    mapfile -t tags < "$NOTES_TAGS_DB"

    # Prepare whiptail menu options
    local menu_options=()
    for tag in "${tags[@]}"; do
        menu_options+=("$tag" "")
    done

    # Show tag selection menu
    local selected_tag
    selected_tag=$(whiptail --menu "Choose a note tag to delete from global list." 20 50 10 "${menu_options[@]}" 3>&1 1>&2 2>&3 >/dev/tty)
    [[ $? -ne 0 ]] && return  # User canceled

    # Check for conflicting notes
    local conflicts=()
    if [[ -f "$NOTES_DB" ]]; then
        while IFS='|' read -r note_title _ note_tags _; do
            IFS=',' read -ra tags_arr <<< "$note_tags"
            for t in "${tags_arr[@]}"; do
                if [[ "$t" == "$selected_tag" ]]; then
                    conflicts+=("$note_title")
                    break
                fi
            done
        done < "$NOTES_DB"
    fi

    # Handle conflicts or delete tag
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        local conflict_msg="Cannot delete tag '$selected_tag' due to conflicts in:\n"
        for title in "${conflicts[@]}"; do
            conflict_msg+="- $title\n"
        done
        conflict_msg+="\nPlease dissociate the tag from these notes first."
        whiptail --msgbox "$conflict_msg" 20 50
    else
		# Confirm before deletion
		whiptail --title "Confirm Deletion" \
        --yesno "Are you sure you want to delete tag '$selected_tag' from the global list?" 10 60 \
		|| return 1

        # Remove tag from tags database
        local temp_file=$(mktemp)
        grep -vFx "$selected_tag" "$NOTES_TAGS_DB" > "$temp_file"
        mv "$temp_file" "$NOTES_TAGS_DB"
        whiptail --msgbox "Note tag '$selected_tag' has been successfully deleted from global list." 10 50
    fi
}

delete_global_tag_of_notes
