#!/usr/bin/env bash

EBOOKS_DB="test.db"

add_ebooks_from_checklist() {
    local ITEMS_PER_PAGE=10
    local start_dir="$(pwd)"
    local current_dir="$start_dir"
    declare -A global_selected

    # Ensure the eBooks DB exists
    touch "$EBOOKS_DB"

    # Outer loop: directory traversal
    while true; do
        # Build lists of subdirs and files
        mapfile -t dirs < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type d | sort)
        mapfile -t files < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type f | sort)

        # Combine into one array for paging
        local -a items=("${dirs[@]}" "${files[@]}")
        local total=${#items[@]}
        local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
        local current_page=0

        # Paging & selection within this directory
        while true; do
            local start=$(( current_page * ITEMS_PER_PAGE ))
            local end=$(( start + ITEMS_PER_PAGE ))
            (( end > total )) && end=$total

            # Build checklist entries
            local -a choices=()
            for i in $(seq "$start" $((end - 1))); do
                local path="${items[$i]}"
                local name="$(basename "$path")"
                if [[ -d "$path" ]]; then
                    choices+=("dir_$i" "[DIR] $name" "OFF")
                else
                    local state="OFF"
                    [[ "${global_selected[$path]}" == "1" ]] && state="ON"
                    choices+=("file_$i" "$name" "$state")
                fi
            done

            # Navigation controls
            choices+=("__up__"   "[DIR] .. (parent)"            "OFF")
            (( current_page > 0 ))        && choices+=("__prev__" "Previous page"               "OFF")
            (( current_page < pages-1 ))  && choices+=("__next__" "Next page"                   "OFF")
            choices+=("__add__" "Proceed to add selected files" "OFF")

            # Show the checklist
            local result
            result=$(whiptail \
                --title "Add eBooks: ${current_dir}" \
                --checklist "Page $((current_page+1))/$pages\nSelect files/directories or navigation action:" \
                20 100 10 \
                "${choices[@]}" \
                3>&1 1>&2 2>&3) \
                || { whiptail --msgbox "Cancelled." 8 40; return 1; }

            # Normalize and split selections
            result=${result//\"/}
            IFS=' ' read -r -a sel_tags <<< "$result"

            ##
            # Snapshot the page’s file selections immediately,
            # so that global_selected is updated on any navigation.
            for i in $(seq "$start" $((end - 1))); do
                local p="${items[$i]}"
                if [[ -f "$p" ]]; then
                    if printf "%s\n" "${sel_tags[@]}" | grep -qx "file_$i"; then
                        global_selected["$p"]=1
                    else
                        unset global_selected["$p"]
                    fi
                fi
            done
            ##

            # Count selection types
            local movement_nav_count=0 dir_count=0 proceed_count=0 file_count=0
            for tag in "${sel_tags[@]}"; do
                case "$tag" in
                    "__up__"|"__prev__"|"__next__") ((movement_nav_count++)) ;;
                    "__add__")                       ((proceed_count++)) ;;
                    dir_*)                           ((dir_count++)) ;;
                    file_*)                          ((file_count++)) ;;
                esac
            done

            # Validation rules
            if (( movement_nav_count > 1 )); then
                whiptail --title "Invalid Selection" --msgbox "Please select only one of Previous, Next, or Up." 10 40
                continue
            fi
            if (( dir_count > 1 )); then
                whiptail --title "Invalid Selection" --msgbox "Please select only one directory at a time." 10 40
                continue
            fi
            if (( proceed_count > 1 )); then
                whiptail --title "Invalid Selection" --msgbox "Please select Proceed only once." 10 40
                continue
            fi
            if (( movement_nav_count == 1 )) && (( dir_count+proceed_count > 0 )); then
                whiptail --title "Invalid Selection" --msgbox "Navigation (Up/Prev/Next) cannot be combined with files, directories, or Proceed." 10 60
                continue
            fi
            if (( dir_count == 1 )) && (( proceed_count+movement_nav_count > 0 )); then
                whiptail --title "Invalid Selection" --msgbox "Directory selection cannot be combined with files, navigation, or Proceed." 10 60
                continue
            fi
            if (( proceed_count == 1 )) && (( movement_nav_count+dir_count > 0 )); then
                whiptail --title "Invalid Selection" --msgbox "Proceed cannot be combined with navigation or directory selection." 10 60
                continue
            fi

            # Handle movement navigation
            if (( movement_nav_count == 1 )); then
                if printf "%s\n" "${sel_tags[@]}" | grep -qx "__up__"; then
                    current_dir="$(dirname "$current_dir")"
                    break
                elif printf "%s\n" "${sel_tags[@]}" | grep -qx "__next__"; then
                    (( current_page++ ))
                else
                    (( current_page-- ))
                fi
                continue
            fi

            # Handle directory traversal
            if (( dir_count == 1 )); then
                for tag in "${sel_tags[@]}"; do
                    [[ "$tag" == dir_* ]] && idx="${tag#dir_}"
                done
                current_dir="${items[$idx]}"
                break
            fi

            # Handle Proceed
            if (( proceed_count == 1 )); then
                break 2
            fi

            # Otherwise refresh page with updated selections
        done
    done

    # Gather all files marked for addition
    local -a to_add=()
    for path in "${!global_selected[@]}"; do
        [[ "${global_selected[$path]}" == "1" ]] && to_add+=("$path")
    done

    if [ ${#to_add[@]} -eq 0 ]; then
        whiptail --msgbox "No eBooks selected." 8 40
        return 1
    fi

    # Confirm and write to DB
    local msg="These files will be added to $EBOOKS_DB (skipping duplicates):\n"
    for f in "${to_add[@]}"; do
        msg+="  $f\n"
    done

    if whiptail --yesno "$msg" 20 78 --title "Confirm Addition"; then
        for f in "${to_add[@]}"; do
            if ! grep -Fq "${f}|" "$EBOOKS_DB"; then
                echo "${f}|" >> "$EBOOKS_DB"
            fi
        done
        whiptail --msgbox "eBooks added successfully." 8 40
    else
        whiptail --msgbox "Addition cancelled." 8 40
    fi
}

# To invoke:
add_ebooks_from_checklist
