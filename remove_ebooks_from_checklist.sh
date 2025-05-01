EBOOKS_DB="test.db"

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

remove_ebooks_from_checklist() {
    local ITEMS_PER_PAGE=5
    local current_page=0
    declare -A selected_entries  # Keys are entry indices, value is 1 if selected

    # Read all entries from EBOOKS_DB
    local -a entries=()
    while IFS='|' read -r path tags; do
        entries+=("$path")
    done < "$EBOOKS_DB"
    local total=${#entries[@]}
    if (( total == 0 )); then
        whiptail --msgbox "No eBooks in database." 8 40
        return 1
    fi
    local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))

    # Pagination loop
    while true; do
        local start=$(( current_page * ITEMS_PER_PAGE ))
        local end=$(( start + ITEMS_PER_PAGE ))
        (( end > total )) && end=$total

        # Build choices for the current page
        local -a choices=()
        for ((i = start; i < end; i++)); do
            local path="${entries[$i]}"
            
            # Split path into directory and filename
			local dir_part=$(dirname "$path")
			local file_part=$(basename "$path")
			# Truncate components
			local trunc_dir=$(truncate_dirname "$dir_part")
			local trunc_file=$(truncate_filename "$file_part" 50)
			local truncated_path="${trunc_dir}/${trunc_file}"            

            local state="OFF"
            [[ -n "${selected_entries[$i]}" ]] && state="ON"
            choices+=("entry_$i" "$truncated_path" "$state")
        done

        # Add navigation controls
        if (( current_page > 0 )); then
            choices+=("__prev__" "Previous page" "OFF")
        fi
        if (( current_page < pages - 1 )); then
            choices+=("__next__" "Next page" "OFF")
        fi
        choices+=("__proceed__" "Proceed to remove selected entries" "OFF")

        # Show checklist
        local result
        result=$(whiptail \
            --title "Remove eBooks" \
            --checklist "Page $((current_page+1))/$pages\nSelect entries to remove or navigation action:" \
            20 150 10 \
            "${choices[@]}" \
            3>&1 1>&2 2>&3) \
            || { whiptail --msgbox "Cancelled." 8 40; return 1; }

        # Process selections
        IFS=' ' read -r -a sel_tags <<< "${result//\"/}"

        # Update selected_entries for current page
        for ((i = start; i < end; i++)); do
            local tag="entry_$i"
            if printf "%s\n" "${sel_tags[@]}" | grep -qx "$tag"; then
                selected_entries["$i"]=1
            else
                unset selected_entries["$i"]
            fi
        done

        # Count selection types
        local nav_count=0 proceed_count=0 entry_count=0
        for tag in "${sel_tags[@]}"; do
            case "$tag" in
                __prev__|__next__) ((nav_count++)) ;;
                __proceed__) ((proceed_count++)) ;;
                entry_*) ((entry_count++)) ;;
            esac
        done

        # Validate selections
        if (( nav_count > 1 || proceed_count > 1 )); then
            whiptail --msgbox "Please select only one of navigation actions." 10 40
            continue
        fi
        if (( nav_count + proceed_count > 1 )); then
            whiptail --msgbox "Please select only one action (Previous, Next, or Proceed)." 10 40
            continue
        fi

        # Handle navigation
        if (( nav_count == 1 )); then
            for tag in "${sel_tags[@]}"; do
                case "$tag" in
                    __prev__)
                        ((current_page--))
                        # Ensure current_page doesn't go below 0
                        ((current_page < 0)) && current_page=0                        
                        break
                        ;;
                    __next__)
                        ((current_page++))
                        # Ensure current_page doesn't exceed pages-1
                        ((current_page >= pages)) && current_page=$((pages - 1))                        
                        break
                        ;;
                esac
            done
            continue
        fi

        # Handle proceed
        if (( proceed_count == 1 )); then
            break
        fi

        # If no action, continue to next iteration (same page)
    done

    # Collect selected paths
    local -a selected_paths=()
    for index in "${!selected_entries[@]}"; do
        selected_paths+=("${entries[$index]}")
    done

    if (( ${#selected_paths[@]} == 0 )); then
        whiptail --msgbox "No entries selected." 8 40
        return 1
    fi

    # Confirm removal
    local msg="The following entries will be removed:\n"
    for path in "${selected_paths[@]}"; do
        msg+="  $path\n"
    done
    if whiptail --scrolltext --yesno "$msg" 20 78 --title "Confirm Removal"; then
        # Create a temporary file
        local tmp_db
        tmp_db=$(mktemp) || { whiptail --msgbox "Error creating temporary file." 8 40; return 1; }
        # Use grep to exclude selected paths
        grep -vf <(printf '^%s|\n' "${selected_paths[@]}") "$EBOOKS_DB" > "$tmp_db"
                
        # Replace the original database
        mv "$tmp_db" "$EBOOKS_DB"
        whiptail --msgbox "Entries removed successfully." 8 40
    else
        whiptail --msgbox "Removal cancelled." 8 40
    fi
}

remove_ebooks_from_checklist
