#!/bin/bash
# Assumes NOTES_DB is defined and points to the notes file.
# Each line in NOTES_DB is in the format:
# note_title|note_path|tag1,tag2|ebook_path1#chapter1:5,chapter3:10-15;ebook_path2#chapter1:2

BABYRUS_PATH="/my-projects/babyrus"
NOTES_PATH="${BABYRUS_PATH}/notes"
NOTES_METADATA_PATH="${NOTES_PATH}/metadata"
NOTES_DB="${NOTES_METADATA_PATH}/notes.db"

# truncate logic for filenames (ie. basename)
# the logic is:
# "a very long truncated file.pdf" becomes "a very long truncated....pdf"
# preserves the file extension.
truncate_filename() {
    local filename="$1"
    local max_length="${2:-85}" # defaults to 85

    # Extract filename and extension
    local name="${filename%.*}"
    local ext="${filename##*.}"

    # If there's no extension, treat whole as name
    [[ "$filename" == "$ext" ]] && ext=""

    # Calculate max length for the name part (allow space for dots and extension)
    local trunc_length=$(( max_length - ${#ext} - 4 ))  # 4 accounts for "...."

    # If filename is within limit, return as-is
    if [[ ${#filename} -le $max_length ]]; then
        echo "$filename"
        return
    fi

    # Truncate the name and append "...." + extension
    local truncated_name="${name:0:trunc_length}"
    echo "${truncated_name}....${ext}"
}

# truncation logic for dirname
# like this:
# "/this/is/a/very/long/path" to "/this/is/a/.../long/path"
truncate_dirname() {
    local dir="$1"
    local max_length="${2:-50}" # defaults to 50

    if [[ ${#dir} -le $max_length ]]; then
        echo "$dir"
    else
        local keep_length=$(( max_length - 5 ))  # Space left after "/.../"
        local start_length=$(( keep_length / 2 ))  # Half for start
        local end_length=$(( keep_length - start_length ))  # Remaining for end

        local start="${dir:0:start_length}"
        local end="${dir: -end_length}"

        echo "${start}/.../${end}"
    fi
}

delete_notes() {
    local ITEMS_PER_PAGE=100

    if [ ! -f "$NOTES_DB" ]; then
        whiptail --title "Error" --msgbox "$NOTES_DB does not exist." 10 40
        return 1
    fi

    # Read the file lines into an array.
    local -a lines
    mapfile -t lines < "$NOTES_DB"
    local total=${#lines[@]}
    # Calculate number of pages (ITEMS_PER_PAGE items per page).
    local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
    local current_page=0

    # Global associative array to track selections across pages.
    declare -A global_selected

    # Main loop for pagination and selection.
    while true; do
        local start=$(( current_page * ITEMS_PER_PAGE ))
        local end=$(( start + ITEMS_PER_PAGE ))
        if [ "$end" -gt "$total" ]; then
            end=$total
        fi

        # Build the list for the current page.
        local -a choices=()
        local i
        for i in $(seq $start $((end - 1))); do
            local state="OFF"
            # If note was already selected, set default state to ON.
            if [ "${global_selected[$i]}" == "1" ]; then
                state="ON"
            fi

            # Truncate note path
            local note_path
            note_path=$(cut -d'|' -f2 <<< "${lines[$i]}")

            local dir_tr filename_tr note_path_tr
            dir_tr="$(dirname "$note_path")"
            dir_tr="$(truncate_dirname "$dir_tr" 50)"
            filename_tr="$(basename "$note_path")"
            filename_tr="$(truncate_filename "$filename_tr" 50)"
            note_path_tr="${dir_tr}/${filename_tr}" 

           # Use the array index as the tag and the entire line as description.
            choices+=("$i" "$note_path_tr" "$state")
        done

        # Add navigation options.
        if [ "$current_page" -gt 0 ]; then
            choices+=("__prev__" "Previous page" "OFF")
        fi
        if [ "$current_page" -lt $((pages - 1)) ]; then
            choices+=("__next__" "Next page" "OFF")
        fi
        # Always allow proceeding to the next step.
        choices+=("__proceed__" "Proceed to deletion" "OFF")

        # Show the whiptail checklist.
        local result
        result=$(whiptail --title "Delete Notes" --checklist "Select notes to delete (page $((current_page + 1))/$pages)" 20 100 10 "${choices[@]}" 3>&1 1>&2 2>&3)
        local exit_status=$?
        if [ $exit_status -ne 0 ]; then
            whiptail --title "Cancelled" --msgbox "Deletion cancelled." 10 40
            return 1
        fi

        # Do I get back "" that interferes with matching case below?
        result=$(echo $result | tr -d '"')

        # Process returned selections.
        # (Note: whiptail returns a space-delimited string.)
        local -a selected_tags
        IFS=" " read -r -a selected_tags <<< "$result"

        # For each note on the current page, update our global selections.
        local found
        for i in $(seq $start $((end - 1))); do
            found=0
            local tag
            for tag in "${selected_tags[@]}"; do
                if [ "$tag" == "$i" ]; then
                    found=1
                    break
                fi
            done
            if [ $found -eq 1 ]; then
                global_selected["$i"]=1
            else
                # Remove any deselected note from this page.
                unset global_selected["$i"]
            fi
        done

        # Check for navigation actions.
        local nav_next=0 nav_prev=0 nav_proceed=0
        for tag in "${selected_tags[@]}"; do
            case "$tag" in
                "__next__") nav_next=1 ;;
                "__prev__") nav_prev=1 ;;
                "__proceed__") nav_proceed=1 ;;
            esac
        done

        # Count navigation commands selected.
        local nav_count=$(( nav_next + nav_prev + nav_proceed ))
        if [ "$nav_count" -gt 1 ]; then
            whiptail --title "Invalid Selection" --msgbox "Please select only one navigation option at a time." 10 40
            continue
        fi

        if [ $nav_next -eq 1 ] && [ $current_page -lt $((pages - 1)) ]; then
            current_page=$(( current_page + 1 ))
            continue
        fi
        if [ $nav_prev -eq 1 ] && [ $current_page -gt 0 ]; then
            current_page=$(( current_page - 1 ))
            continue
        fi
        if [ $nav_proceed -eq 1 ]; then
            break
        fi
        # If no navigation option was chosen, re-display the current page.
    done

    # Build a final selection list from global_selected.
    local -a final_selection=()
    local idx
    for idx in "${!global_selected[@]}"; do
        final_selection+=("$idx")
    done

    if [ ${#final_selection[@]} -eq 0 ]; then
        whiptail --title "No Selection" --msgbox "No notes selected for deletion." 10 40
        return 1
    fi

    # Construct a confirmation message.
    local msg="The following notes will be deleted:\n"
    for idx in "${final_selection[@]}"; do
        # Truncate note path
        note_path=$(cut -d'|' -f2 <<< "${lines[$idx]}")

        local dir_tr filename_tr note_path_tr
        dir_tr="$(dirname "$note_path")"
        dir_tr="$(truncate_dirname "$dir_tr" 50)"
        filename_tr="$(basename "$note_path")"
        filename_tr="$(truncate_filename "$filename_tr" 50)"
        note_path_tr="${dir_tr}/${filename_tr}" 

        msg+="${note_path_tr}\n"
    done

    # Confirm deletion.
    if whiptail --title "Confirm Deletion" --yesno "$msg" 20 78; then
        # Sort the indices in descending order to safely delete from the file.
        local -a sorted
        sorted=($(for i in "${final_selection[@]}"; do echo "$i"; done | sort -nr))
        for idx in "${sorted[@]}"; do
            local line_num=$(( idx + 1 ))
            sed -i "${line_num}d" "$NOTES_DB"
        done
        whiptail --title "Deletion Complete" --msgbox "Selected notes have been deleted." 10 40
    else
        whiptail --title "Cancelled" --msgbox "Deletion cancelled." 10 40
    fi
}

# Usage
delete_notes
