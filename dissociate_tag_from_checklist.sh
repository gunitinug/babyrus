EBOOKS_DB="test.db"
TAGS_DB="test-tags.db"

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

dissociate_tag_from_checklist() {
    touch "$EBOOKS_DB" "$TAGS_DB"

    local ITEMS_PER_PAGE=100
    local current_page=0
    declare -A selected_entries  # Keys are entry indices, value is 1 if selected

    # Ask for tag to dissociate
    local tag_to_remove
    # build tag menu options (tag and empty description)
    local -a tag_choices=()
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tag_choices+=("$tag" "")
    done < "$TAGS_DB"
    if [[ ${#tag_choices[@]} -eq 0 ]]; then
        whiptail --msgbox "No tags found in database." 8 40
        return 1
    fi
    tag_to_remove=$(whiptail --title "Select Tag to Remove" --menu "Choose a tag to dissociate from eBooks:" \
        20 60 10 \
        "${tag_choices[@]}" \
        3>&1 1>&2 2>&3) || { whiptail --msgbox "Cancelled." 8 40; return 1; }

    # Gather entries containing that tag
    local -a entries=()
    while IFS='|' read -r path tags; do
        IFS=',' read -ra tag_array <<< "$tags"
        for t in "${tag_array[@]}"; do
            [[ "$t" == "$tag_to_remove" ]] && entries+=("$path|$tags") && break
        done
    done < "$EBOOKS_DB"

    local total=${#entries[@]}
    if (( total == 0 )); then
        whiptail --msgbox "No eBooks found with tag '$tag_to_remove'." 8 50
        return 1
    fi
    local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))

    # Pagination loop
    while true; do        
        local start=$(( current_page * ITEMS_PER_PAGE ))
        local end=$(( start + ITEMS_PER_PAGE ))
        (( end > total )) && end=$total

        local -a choices=()
        for ((i = start; i < end; i++)); do
            local entry="${entries[$i]}"
            local path="${entry%%|*}"
            # truncate display
            local dir_part=$(dirname "$path")
            local file_part=$(basename "$path")
            local trunc_dir=$(truncate_dirname "$dir_part")
            local trunc_file=$(truncate_filename "$file_part" 50)
            local disp="${trunc_dir}/${trunc_file}"

            local state="OFF"
            [[ -n "${selected_entries[$i]}" ]] && state="ON"
            choices+=("entry_$i" "$disp" "$state")
        done
        # nav
        (( current_page > 0 )) && choices+=("__prev__" "Previous page" OFF)
        (( current_page < pages-1 )) && choices+=("__next__" "Next page" OFF)
        choices+=("__proceed__" "Proceed to dissociate tag" OFF)

        local result
        result=$(whiptail --title "Dissociate Tag: $tag_to_remove" \
            --checklist "Page $((current_page+1))/$pages\nSelect eBooks to update or navigate:" \
            20 150 10 "${choices[@]}" 3>&1 1>&2 2>&3) \
            || { whiptail --msgbox "Cancelled." 8 40; return 1; }

        IFS=' ' read -r -a sel_tags <<< "${result//\"/}"
        # update selection
        for ((i = start; i < end; i++)); do
            local tagkey="entry_$i"
            if printf "%s\n" "${sel_tags[@]}" | grep -qx "$tagkey"; then
                selected_entries[$i]=1
            else
                unset selected_entries[$i]
            fi
        done

        # count actions
        local nav_count=0 proceed_count=0
        for tag in "${sel_tags[@]}"; do
            [[ "$tag" == __prev__ || "$tag" == __next__ ]] && ((nav_count++))
            [[ "$tag" == __proceed__ ]] && ((proceed_count++))
        done
        # validations
        if (( nav_count > 1 || proceed_count > 1 )); then
            whiptail --msgbox "Select only one navigation or proceed action." 10 40
            continue
        fi
        if (( nav_count + proceed_action > 1 )); then
            whiptail --msgbox "Do not select both navigation option and proceed at the same time." 10 40
			continue
        fi
        
        # navigation
        if (( nav_count == 1 )); then
            for tag in "${sel_tags[@]}"; do
                case "$tag" in
                    __prev__) ((current_page--)); ((current_page<0)) && current_page=0;;
                    __next__) ((current_page++)); ((current_page>=pages)) && current_page=$((pages-1));;
                esac
            done
            continue
        fi
        # proceed
        (( proceed_count == 1 )) && break
    done

    # Build selected paths
    local -a selected_paths=()
    for idx in "${!selected_entries[@]}"; do
        selected_paths+=("${entries[$idx]%%|*}")
    done
    if (( ${#selected_paths[@]} == 0 )); then
        whiptail --msgbox "No entries selected." 8 40
        return 1
    fi

    # Confirm
    local msg="The tag '$tag_to_remove' will be removed from:\n"
    for p in "${selected_paths[@]}"; do msg+="  $p\n"; done
    if ! whiptail --scrolltext --yesno "$msg" 20 78 --title "Confirm Dissociation"; then
        whiptail --msgbox "Cancelled." 8 40
        return 1
    fi

    # Process removal
    local tmp_db
    tmp_db=$(mktemp) || { whiptail --msgbox "Error creating temp file." 8 40; return 1; }
    declare -A tofix
    for p in "${selected_paths[@]}"; do tofix["$p"]=1; done
    while IFS='|' read -r path tags; do
        if [[ -n "${tofix[$path]}" ]]; then
            IFS=',' read -ra arr <<< "$tags"
            local new_arr=()
            for t in "${arr[@]}"; do
                [[ "$t" != "$tag_to_remove" && -n "$t" ]] && new_arr+=("$t")
            done
            local new_tags
            # only join if there are remaining tags
            if (( ${#new_arr[@]} > 0 )); then
                new_tags="$(IFS=','; echo "${new_arr[*]}")"
            else
                new_tags=""
            fi
            echo "$path|$new_tags" >> "$tmp_db"
        else
            echo "$path|$tags" >> "$tmp_db"
        fi
    done < "$EBOOKS_DB"
    mv "$tmp_db" "$EBOOKS_DB"
    whiptail --msgbox "Tag '$tag_to_remove' dissociated successfully." 8 50
}

dissociate_tag_from_checklist
