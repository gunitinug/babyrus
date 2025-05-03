associate_tag_from_checklist() {
    local ITEMS_PER_PAGE=100
    local current_page=0
    declare -A selected_entries  # Keys are entry indices, value is 1 if selected

    # --- Step 1: Pick a tag from $TAGS_DB ---
    local -a tags
    while IFS= read -r tag; do
        tags+=("$tag")
    done < "$TAGS_DB"

    if (( ${#tags[@]} == 0 )); then
        whiptail --msgbox "No tags available in $TAGS_DB." 8 40
        return 1
    fi

    # Build a numeric menu so we can handle spaces in tag names
    local -a tag_choices=()
    for i in "${!tags[@]}"; do
        tag_choices+=("$i" "${tags[$i]}")
    done

    local selected_index
    selected_index=$(whiptail --title "Select Tag to Associate" \
        --menu "Choose one tag:" 20 60 10 \
        "${tag_choices[@]}" \
        3>&1 1>&2 2>&3) || {
            whiptail --msgbox "Cancelled." 8 40
            return 1
        }
    local selected_tag="${tags[$selected_index]}"

    # --- Step 2: Ask for filename filter ---
    local search_term
    search_term=$(whiptail --inputbox \
        "Enter a substring to filter filenames (leave empty for all):" \
        8 50 --title "Search Filter" \
        3>&1 1>&2 2>&3) || {
            whiptail --msgbox "Cancelled." 8 40
            return 1
        }
    local search_lower=""
    [[ -n "$search_term" ]] && search_lower="$(tr '[:upper:]' '[:lower:]' <<< "$search_term")"

    # --- Step 3: Load & filter e-book entries ---
    local -a entries=()
    while IFS='|' read -r path tags_on_book; do
        if [[ -z "$search_term" ]] || \
           [[ "$(basename "$path" | tr '[:upper:]' '[:lower:]')" == *"$search_lower"* ]]; then
            entries+=("$path|$tags_on_book")
        fi
    done < "$EBOOKS_DB"

    if (( ${#entries[@]} == 0 )); then
        whiptail --msgbox "No eBooks found matching '$search_term'." 8 40
        return 1
    fi

    local total=${#entries[@]}
    local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))

    # --- Step 4: Paginated checklist of e-books ---
    while true; do        
        local start=$(( current_page * ITEMS_PER_PAGE ))
        local end=$(( start + ITEMS_PER_PAGE ))
        (( end > total )) && end=$total

        local -a choices=()
        for ((i = start; i < end; i++)); do
            local entry="${entries[$i]}"
            local path="${entry%%|*}"
            local display="$(basename "$path")"
            local state="OFF"
            [[ -n "${selected_entries[$i]}" ]] && state="ON"
            choices+=("entry_$i" "$display" "$state")
        done

        # navigation
        (( current_page > 0 )) && choices+=("__prev__" "< Previous page" OFF)
        (( current_page < pages-1 )) && choices+=("__next__" "> Next page" OFF)
        choices+=("__proceed__" "Proceed to tag association" OFF)

        local result
        result=$(whiptail --title "Associate Tag: Page $((current_page+1))/$pages" \
            --checklist "Select e-Books to tag or navigate:" \
            20 100 10 \
            "${choices[@]}" \
            3>&1 1>&2 2>&3) || {
                whiptail --msgbox "Cancelled." 8 40
                return 1
            }

        IFS=' ' read -r -a sel_tags <<< "${result//\"/}"

        # update selected_entries
        for ((i = start; i < end; i++)); do
            tag="entry_$i"
            if printf '%s\n' "${sel_tags[@]}" | grep -qx "$tag"; then
                selected_entries[$i]=1
            else
                unset selected_entries[$i]
            fi
        done

        # Count selection types
        local nav=0 proc=0
        for tag in "${sel_tags[@]}"; do
            [[ $tag == __prev__ || $tag == __next__ ]] && ((nav++))
            [[ $tag == __proceed__ ]] && ((proc++))
        done

		# Validate selections
        if (( nav > 1 || proc > 1 )); then
            whiptail --msgbox "Please select only one of navigation actions." 10 40
            continue
        fi
        if (( nav + proc > 1 )); then
            whiptail --msgbox "Please select only one action (Previous, Next, or Proceed)." 10 40
            continue
        fi        

        # handle navigation
        if (( nav == 1 )); then
            for tag in "${sel_tags[@]}"; do
                [[ $tag == __prev__ ]] && ((current_page--))
                [[ $tag == __next__ ]] && ((current_page++))
            done
            (( current_page < 0 )) && current_page=0
            (( current_page >= pages )) && current_page=$((pages-1))
            continue
        fi

        # proceed
        (( proc == 1 )) && break
    done

    # --- Step 5: Collect selected entries & update DB ---
    local -a to_update=()
    for idx in "${!selected_entries[@]}"; do
        to_update+=("${entries[$idx]}")
    done

    if (( ${#to_update[@]} == 0 )); then
        whiptail --msgbox "No eBooks selected." 8 40
        return 1
    fi

    local msg="Tag '${selected_tag}' will be added to:\n"
    for line in "${to_update[@]}"; do
        msg+="  ${line%%|*}\n"
    done

    if ! whiptail --scrolltext --yesno "$msg" 20 70 --title "Confirm Association"; then
        whiptail --msgbox "Operation cancelled." 8 40
        return 1
    fi

    # perform in-place update without duplicating tags
    local tmp_db
    tmp_db=$(mktemp) || { whiptail --msgbox "Error creating temp file." 8 40; return 1; }

    while IFS='|' read -r path tags_on_book; do
        local new_tags="$tags_on_book"
        local line="$path|$tags_on_book"

        # if this is one of the selected entries, append only if missing
        if printf '%s\n' "${to_update[@]}" | grep -qx "$line"; then
            if [[ ",$tags_on_book," != *",$selected_tag,"* ]]; then
                if [[ -z "$new_tags" ]]; then
                    new_tags="$selected_tag"
                else
                    new_tags="$new_tags,$selected_tag"
                fi
            fi
        fi

        printf '%s|%s\n' "$path" "$new_tags" >> "$tmp_db"
    done < "$EBOOKS_DB"

    mv "$tmp_db" "$EBOOKS_DB"
    whiptail --msgbox "Tag '$selected_tag' associated successfully." 8 40
}
