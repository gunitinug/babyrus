#!/bin/bash

EBOOKS_DB="ebooks.db"

rename_and_reregister_illegal_ebook_filenames() {
    # Info msgbox about what this function does
    whiptail --title "Info" --msgbox \
"Files registered in ebooks database can't have |,#:; characters in their file names \
because they are illegal in Manage Notes operations. \n\n\
This function will rename the file names accordingly both in ebooks database \
and physically on drive. You can also revert the changes later." 15 80

    local EBOOKS_DB_BACKUP="$EBOOKS_DB.backup"
    local LOG_FILE="$EBOOKS_DB.rename.log"
    local TEMP_DB
    TEMP_DB=$(mktemp) || return 1
    local -a changes=()
    local -a new_lines=()

    # Create backup of original database
    cp -- "$EBOOKS_DB" "$EBOOKS_DB_BACKUP" || return 1

    # Display whiptail message telling user to wait
    TERM=ansi whiptail --title "Processing" \
         --infobox "Collecting information about illegal filenames registered inside ebooks database.\n\nPlease wait..." 10 60

    # First pass: collect changes and prepare new database
    while IFS= read -r line; do
        IFS='|' read -r path tags <<< "$line"
        local dir old_basename new_basename new_path

        dir=$(dirname -- "$path")
        old_basename=$(basename -- "$path")
        new_basename=$(tr '|,#:;' '_' <<< "$old_basename")

        if [[ "$new_basename" != "$old_basename" ]]; then
            # Generate unique filename
            new_path="$dir/$new_basename"
            local counter=1
            
            while [[ -e "$new_path" ]]; do
                local name_part="${new_basename%.*}"
                local ext_part="${new_basename##*.}"
                if [[ "$name_part" == "$ext_part" ]]; then
                    new_basename="${new_basename}_$counter"
                else
                    new_basename="${name_part}_$counter.${ext_part}"
                fi
                new_path="$dir/$new_basename"
                ((counter++))
            done

            changes+=("$path|$new_path")
            new_lines+=("$new_path|$tags")
        else
            new_lines+=("$line")
        fi
    done < "$EBOOKS_DB_BACKUP"

    # Show confirmation dialog if changes needed
    if [[ ${#changes[@]} -gt 0 ]]; then
        local change_list
        change_list=$(mktemp) || return 1
        
        for change in "${changes[@]}"; do
            IFS='|' read -r old new <<< "$change"
            echo "  $old -> $new" >> "$change_list"
        done

        whiptail --title "Files to be renamed" --scrolltext --textbox "$change_list" 20 80
        rm -f "$change_list"

        if ! whiptail --title "Confirmation" --yesno "Proceed with these changes?" 10 80; then
            rm -f "$TEMP_DB"
            echo "Operation cancelled by user" >&2
            return 1
        fi
    else
        whiptail --title "No changes needed" --msgbox "No files with illegal characters found" 8 50
        rm -f "$TEMP_DB"
        return 0
    fi

    # Second pass: execute changes
    : > "$LOG_FILE"
    for change in "${changes[@]}"; do
        IFS='|' read -r old new <<< "$change"
        if ! mv -- "$old" "$new"; then
            echo "Error: Failed to rename '$old' to '$new'" >&2
            rm -f "$TEMP_DB"
            return 1
        fi
        echo "$old|$new" >> "$LOG_FILE"
    done

    # Write new database
    printf "%s\n" "${new_lines[@]}" > "$TEMP_DB"
    mv -- "$TEMP_DB" "$EBOOKS_DB" || return 1

    whiptail --title "Success" --msgbox "Files renamed and database updated!\n\nBackup: $EBOOKS_DB_BACKUP" 12 80
}

revert_rename_illegal_ebook_filenames() {    
    # Info msgbox about what this function does
    whiptail --title "Info" --msgbox \
"This function reverts changes made by Rename and Reregister Illegal Ebook Filenames function. \
It reverts both ebooks database and physical file names on drive." 10 80

    local EBOOKS_DB_BACKUP="$EBOOKS_DB.backup"
    local LOG_FILE="$EBOOKS_DB.rename.log"

    if [[ ! -f "$EBOOKS_DB_BACKUP" || ! -f "$LOG_FILE" ]]; then
        whiptail --title "Error" --msgbox "Backup or log file missing. Cannot revert." 8 50
        return 1
    fi

    # Show confirmation dialog
    if ! whiptail --title "Confirmation" --yesno "This will restore original filenames and database. Proceed?" 10 80; then
        echo "Revert cancelled by user" >&2
        return 1
    fi

    # Working... infobox
    TERM=ansi whiptail --title "Info" --infobox "Working..." 8 40

    cp -- "$EBOOKS_DB_BACKUP" "$EBOOKS_DB" || return 1

    while IFS= read -r line; do
        IFS='|' read -r original_path new_path <<< "$line"
        if [[ -e "$new_path" ]]; then
            if ! mv -f -- "$new_path" "$original_path"; then
                echo "Warning: Failed to revert '$new_path' to '$original_path'" >&2
            fi
        else
            echo "Warning: '$new_path' does not exist. Skipping." >&2
        fi
    done < "$LOG_FILE"

    whiptail --title "Success" --msgbox "Successfully reverted all changes!\n\nOriginal database restored from backup." 12 80
}

#rename_and_reregister_illegal_ebook_filenames
revert_rename_illegal_ebook_filenames
