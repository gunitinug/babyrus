#!/bin/bash
# babyrus - A terminal productivity tool.
# Copyright (C) 2025, 2026 Logan Lee
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

BABYRUS_VERSION='v.0.99x18'
BABYRUS_AUTHOR='Logan Lee'

# Shared Whiptail (libnewt) colour theme.
# Set BABYRUS_NEWT_COLORS before launching BABYRUS to supply a custom theme.
# Colour pairs use the format foreground,background.
# Default: light grey root, white dialogs, and navy-blue accents/selections.
BABYRUS_NEWT_COLORS="${BABYRUS_NEWT_COLORS:-${NEWT_COLORS:-}}"
if [[ -z "$BABYRUS_NEWT_COLORS" ]]; then
    BABYRUS_NEWT_COLORS='
root=black,lightgray
roottext=black,lightgray
window=black,white
border=blue,white
shadow=gray,lightgray
title=white,blue
button=blue,lightgray
actbutton=white,blue
compactbutton=blue,white
checkbox=black,white
actcheckbox=white,blue
entry=black,white
disentry=gray,lightgray
label=black,white
listbox=black,white
actlistbox=black,white
sellistbox=white,blue
actsellistbox=white,blue
textbox=black,white
acttextbox=black,white
emptyscale=blue,lightgray
fullscale=white,blue
helpline=blue,lightgray'
fi
export NEWT_COLORS="$BABYRUS_NEWT_COLORS"

# Shared colour theme for the ncurses-based `dialog` utility.  It mirrors the
# Whiptail palette: white/light surfaces, dark text, and navy-blue accents.
# Set BABYRUS_DIALOGRC before launching BABYRUS to supply a custom dialogrc.
BABYRUS_DIALOGRC="${BABYRUS_DIALOGRC:-
use_colors = ON
use_shadow = OFF
screen_color = (BLACK,WHITE,OFF)
shadow_color = (BLACK,BLACK,OFF)
dialog_color = (BLACK,WHITE,OFF)
title_color = (WHITE,BLUE,OFF)
border_color = (BLUE,WHITE,OFF)
border2_color = (BLUE,WHITE,OFF)
button_active_color = (WHITE,BLUE,OFF)
button_inactive_color = (BLUE,WHITE,OFF)
button_key_active_color = (WHITE,BLUE,OFF)
button_key_inactive_color = (BLUE,WHITE,OFF)
button_label_active_color = (WHITE,BLUE,OFF)
button_label_inactive_color = (BLUE,WHITE,OFF)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (BLUE,WHITE,OFF)
inputbox_border2_color = (BLUE,WHITE,OFF)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (WHITE,BLUE,OFF)
searchbox_border_color = (BLUE,WHITE,OFF)
searchbox_border2_color = (BLUE,WHITE,OFF)
position_indicator_color = (BLUE,WHITE,OFF)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (BLUE,WHITE,OFF)
menubox_border2_color = (BLUE,WHITE,OFF)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (WHITE,BLUE,OFF)
tag_color = (BLUE,WHITE,OFF)
tag_selected_color = (WHITE,BLUE,OFF)
tag_key_color = (BLUE,WHITE,OFF)
tag_key_selected_color = (WHITE,BLUE,OFF)
check_color = (BLACK,WHITE,OFF)
check_selected_color = (WHITE,BLUE,OFF)
uarrow_color = (BLUE,WHITE,OFF)
darrow_color = (BLUE,WHITE,OFF)
itemhelp_color = (BLACK,WHITE,OFF)
form_active_text_color = (WHITE,BLUE,OFF)
form_text_color = (BLACK,WHITE,OFF)
form_item_readonly_color = (BLACK,WHITE,OFF)
gauge_color = (WHITE,BLUE,OFF)
}"

# Shared sizing policy for every Whiptail menu and checklist.
# Navigation menus use a compact default width, but automatically widen when
# their title, prompt, or item labels need more room. Content pickers retain
# the full terminal width.
# Set BABYRUS_NAV_MENU_WIDTH before launching BABYRUS to customise the default.
BABYRUS_NAV_MENU_WIDTH="${BABYRUS_NAV_MENU_WIDTH:-76}"

# Return terminal rows and columns. Prefer the controlling terminal, then
# fall back to standard input, and finally use conservative defaults.
babyrus_terminal_size() {
    local rows=24 cols=80
    if ! read -r rows cols 2>/dev/null < <(stty size </dev/tty 2>/dev/null); then
        read -r rows cols 2>/dev/null < <(stty size 2>/dev/null) || :
    fi
    [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    (( rows > 0 )) || rows=24
    (( cols > 0 )) || cols=80
    printf '%d %d\n' "$rows" "$cols"
}

# Whiptail interprets literal \\n sequences as line breaks. Count both those
# and real newlines so the dialog height accounts for every prompt line.
babyrus_text_line_count() {
    local text="$1" count=1 rest
    text="${text//\\n/$'\n'}"
    while [[ "$text" == *$'\n'* ]]; do
        ((count++))
        text="${text#*$'\n'}"
    done
    printf '%d\n' "$count"
}

# Return the longest visible line in a Whiptail text string, interpreting its
# \\n sequences as line breaks first.
babyrus_text_max_line_length() {
    local text="$1" line max=0
    text="${text//\\n/$'\n'}"
    while IFS= read -r line; do
        ((${#line} > max)) && max=${#line}
    done <<< "$text"
    printf '%d\n' "$max"
}

# Wrap long prompt lines when a navigation menu is being displayed on a narrow
# terminal. The returned value uses Whiptail's \\n newline notation.
babyrus_wrap_whiptail_text() {
    local text="$1" width="$2"
    text="${text//\\n/$'\n'}"
    printf '%s\n' "$text" | fold -s -w "$width" | awk '
        NR > 1 { printf "\\n" }
        { printf "%s", $0 }
    '
}

# Prints "height width list-height". With no arguments this retains the
# 50-item content-picker sizing used by the eBook / note / file browsers.
# With PROMPT and ITEM_COUNT, it sizes a navigation menu to its actual number
# of visible items plus the prompt and normal dialog chrome.
babyrus_whiptail_dimensions() {
    local prompt="${1-}" item_count="${2:-50}"
    local rows cols height list_height prompt_lines
    read -r rows cols < <(babyrus_terminal_size)

    if (( $# >= 2 )); then
        [[ "$item_count" =~ ^[0-9]+$ ]] || item_count=1
        list_height=$item_count
        (( list_height < 1 )) && list_height=1
        (( list_height > 50 )) && list_height=50
        prompt_lines=$(babyrus_text_line_count "$prompt")
        height=$(( prompt_lines + list_height + 8 ))

        # Preserve all prompt lines and show as many menu rows as the terminal
        # can accommodate. On a very short terminal, keep at least one row.
        if (( height > rows )); then
            list_height=$(( rows - prompt_lines - 8 ))
            (( list_height < 1 )) && list_height=1
            height=$(( prompt_lines + list_height + 8 ))
            (( height > rows )) && height=$rows
        fi
    else
        height=60
        list_height=50
        if (( height > rows )); then
            height=$rows
            list_height=$(( rows - 10 ))
            (( list_height < 1 )) && list_height=1
        fi
    fi

    printf '%d %d %d\n' "$height" "$cols" "$list_height"
}

# Intercept every Whiptail menu/checklist so hard-coded dimensions cannot
# cause oversized dialogs. Navigation menus are compact and content-aware;
# content pickers retain their full terminal width and 50-row list capacity.
whiptail() {
    local -a args=("$@")
    local i widget_index=-1 title="" prompt="" is_navigation=0
    local item_start item_args_count item_arity item_count=0 j list_capacity
    local rows cols height width list_height nav_width ignored_width max_text=0 line_len
    local required_width wrap_width item_text
    local has_add_h=0 has_add_t=0

    read -r rows cols < <(babyrus_terminal_size)

    # Find the title and menu/checklist prompt.
    for (( i = 0; i < ${#args[@]}; i++ )); do
        case "${args[i]}" in
            --title)
                (( i + 1 < ${#args[@]} )) && title="${args[i+1]}"
                ;;
            --menu|--checklist)
                widget_index=$i
                (( i + 1 < ${#args[@]} )) && prompt="${args[i+1]}"
                break
                ;;
        esac
    done

    # Only menu/checklist widgets are resized here. Other Whiptail dialogs
    # keep their existing dimensions and theme.
    (( widget_index >= 0 )) || { command whiptail "${args[@]}"; return $?; }

    # Identify navigation/action menus rather than content pickers.
    case "$title" in
        "BABYRUS "*" Main Menu"|"Babyrus Help Menu") is_navigation=1 ;;
        "Manage eBooks"|"Manage Ebooks"|"File Management"|\
        "Tag Management"|"Search & Lookup"|"Open & Read"|"Maintenance"|\
        "Manage Notes"|"Goals Management"|"Chapter Management"|\
        "Heading Operations"|"Project Configuration"|"Manage Tags"|\
        "Note Action"|"Actions"|"Book Builder"|"Book Management"|\
        "URL Management"|"Configure"|"Help"|"Manage URL"|\
        "Manage URLs for "*|"Project: "*|"Chapter: "*|\
        "Current project: "*|"Selected section: "*)
            is_navigation=1
            ;;
    esac
    case "$prompt" in
        "Choose an option:"|"Select a help topic:"|"Project Configuration"|"Heading Operations"|\
        "Note Action"|"Choose an action:"|"What would you like to do?"|\
        "Manage ebook associations"|"Manage URL"|"Manage URLs for "*|\
        "Project: "*|"Chapter: "*|"Selected section: "*)
            is_navigation=1
            ;;
    esac

    # Each menu entry is a tag/description pair. Checklist entries add a
    # third status field. Skip an optional end-of-options marker if present.
    item_arity=2
    [[ "${args[widget_index]}" == "--checklist" ]] && item_arity=3
    item_start=$(( widget_index + 5 ))
    [[ "${args[item_start]:-}" == "--" ]] && ((item_start++))
    item_args_count=$(( ${#args[@]} - item_start ))
    (( item_args_count < 0 )) && item_args_count=0
    item_count=$(( item_args_count / item_arity ))

    # Goal-tree action menus contain these stable action tags. Treat every
    # such menu as a full-width content menu, even if its title is a heading
    # name rather than exactly "Manage Goals". This keeps all goal-tree
    # screens consistent across the different Goals Management workflows.
    for (( j=item_start; j + item_arity - 1 < ${#args[@]}; j+=item_arity )); do
        case "${args[j]}" in
            ADD_H) has_add_h=1 ;;
            ADD_T) has_add_t=1 ;;
        esac
    done
    if (( has_add_h == 1 && has_add_t == 1 )); then
        is_navigation=0
    fi

    # Work out the longest text line across the title, prompt, and menu labels.
    line_len=$(babyrus_text_max_line_length "$title")
    (( line_len > max_text )) && max_text=$line_len
    line_len=$(babyrus_text_max_line_length "$prompt")
    (( line_len > max_text )) && max_text=$line_len
    for (( j=item_start; j + item_arity - 1 < ${#args[@]}; j+=item_arity )); do
        item_text="${args[j]}  ${args[j+1]}"
        line_len=$(babyrus_text_max_line_length "$item_text")
        (( line_len > max_text )) && max_text=$line_len
    done

    if (( is_navigation )); then
        [[ "$BABYRUS_NAV_MENU_WIDTH" =~ ^[0-9]+$ ]] || BABYRUS_NAV_MENU_WIDTH=76
        nav_width=$BABYRUS_NAV_MENU_WIDTH
        (( nav_width < 40 )) && nav_width=40

        # Widen a navigation menu only when its text needs more room; never
        # exceed the terminal width. This keeps ordinary menus compact while
        # preventing titles, prompts, and menu labels from being clipped.
        required_width=$(( max_text + 8 ))
        (( required_width > nav_width )) && nav_width=$required_width
        (( nav_width > cols )) && nav_width=$cols
        (( nav_width < 1 )) && nav_width=cols

        width=$nav_width
        list_capacity=$item_count
    else
        width=$cols
        # Content pickers keep capacity for 50 displayed rows; only navigation
        # menus shrink their list area to the number of actual menu entries.
        list_capacity=50
    fi

    # Wrap long prompts when necessary so explanatory text (including the
    # main-menu verse) remains visible even on narrower terminals.
    wrap_width=$(( width - 8 ))
    (( wrap_width < 20 )) && wrap_width=20
    line_len=$(babyrus_text_max_line_length "$prompt")
    if (( line_len > wrap_width )); then
        args[widget_index+1]="$(babyrus_wrap_whiptail_text "$prompt" "$wrap_width")"
        prompt="${args[widget_index+1]}"
    fi

    # Size the dialog for the full prompt and the appropriate list capacity.
    # Navigation menus use their exact item count; content pickers retain 50.
    read -r height ignored_width list_height < <(babyrus_whiptail_dimensions "$prompt" "$list_capacity")

    # Replace only the three dimension arguments belonging to this widget.
    args[widget_index+2]="$height"
    args[widget_index+3]="$width"
    args[widget_index+4]="$list_height"

    command whiptail "${args[@]}"
}

# Intercept every `dialog` invocation so it uses the same palette and terminal
# sizing policy as Whiptail.  Textboxes use the full dialog height/width;
# menu/checklist widgets additionally receive the 50-row list height.
dialog() {
    local -a args=("$@")
    local height width list_height i

    read -r height width list_height < <(babyrus_whiptail_dimensions)

    for (( i = 0; i < ${#args[@]}; i++ )); do
        case "${args[i]}" in
            --menu|--checklist|--radiolist|--buildlist)
                # Syntax: widget text height width list-height
                if (( i + 4 < ${#args[@]} )); then
                    args[i + 2]="$height"
                    args[i + 3]="$width"
                    args[i + 4]="$list_height"
                fi
                break
                ;;
            --textbox|--tailbox|--tailboxbg|--programbox|--editbox|\
            --msgbox|--yesno|--infobox|--inputbox|--passwordbox)
                # Syntax: widget text/file height width
                if (( i + 3 < ${#args[@]} )); then
                    args[i + 2]="$height"
                    args[i + 3]="$width"
                fi
                break
                ;;
        esac
    done

    # A process-substitution file keeps the theme self-contained; no user
    # ~/.dialogrc or system /etc/dialogrc needs to be changed.
    DIALOGRC=<(printf '%s\n' "$BABYRUS_DIALOGRC") command dialog "${args[@]}"
}

BABYRUS_PATH="$(pwd)"
NOTES_PATH="${BABYRUS_PATH}/notes"
NOTES_METADATA_PATH="${NOTES_PATH}/metadata"
NOTES_DB="${NOTES_METADATA_PATH}/notes.db"
NOTES_TAGS_DB="${NOTES_METADATA_PATH}/notes-tags.db"
NOTES_EBOOKS_DB="${NOTES_METADATA_PATH}/notes-ebooks.db"
EBOOKS_DB="${BABYRUS_PATH}/ebooks.db"
EBOOKS_DB_BACKUP="${BABYRUS_PATH}/ebooks.db.backup"
EBOOKS_DB_RENAME_LOG="${BABYRUS_PATH}/ebooks.db.rename.log"
TAGS_DB="${BABYRUS_PATH}/tags.db"
PROJECTS_PATH="${BABYRUS_PATH}/projects"
PROJECTS_METADATA_PATH="${PROJECTS_PATH}/metadata"
PROJECTS_DB="${PROJECTS_METADATA_PATH}/projects.db"
PROJECTS_DB_SHORTLISTED="${PROJECTS_METADATA_PATH}/projects.db.shortlisted"
PROJECTS_DB_SHORTLISTED_HISTORY="${PROJECTS_METADATA_PATH}/projects.db.shortlisted.history"
URLS_PATH="${BABYRUS_PATH}/urls"
URLS_DB="${URLS_PATH}/urls.db"
BOOKS_LIST="${BABYRUS_PATH}/books-list.db"

# Try to maximize the current terminal window
if ! wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz &> /dev/null; then
    echo "If menu is broken please manually maximise terminal window before running this program." >&2
fi

# Allow a brief pause for the window manager to update the window size
sleep 0.5

#+++ FIRST RUN +++#
FIRST_RUN=1
#+++ FIRST RUN END +++#

enforce_touch_files() (
  # run in a subshell so set -euo pipefail won't persist outside the function
  set -euo pipefail

  local files=(
    "$EBOOKS_DB"
    #"$EBOOKS_DB_RENAME_LOG"
    "$TAGS_DB"
    "$NOTES_DB"
    "$NOTES_EBOOKS_DB"
    "$NOTES_TAGS_DB"
    "$PROJECTS_DB"
    "$PROJECTS_DB_SHORTLISTED"
    "$PROJECTS_DB_SHORTLISTED_HISTORY"
    "$URLS_DB"
    "$BOOKS_LIST"
  )

  for f in "${files[@]}"; do
    # create parent dir if needed, then touch the file
    mkdir -p "$(dirname -- "$f")"
    touch -- "$f"
  done

  return 0
)

# An artifact to keep to avoid error
SHORTLISTED_HISTORY="${BABYRUS_PATH}/projects/metadata/projects.db.shortlisted.history"

# Make sure all required directories and files are present.
enforce_touch_files

# DO NOT DELETE OR ALTER BETWEEN THESE MARKERS(INCLUDING MARKERS)!!!
#+++ CONFIGURATION +++#
# Tweak this to set external apps.
declare -A EXTENSION_COMMANDS=(
    ["txt"]="geany"
    ["pdf"]="zathura"
    ["epub"]="okular"
    ["mobi"]="okular"
    ["azw3"]="okular"
)

# Tweak these to set external apps for other sections.
DEFAULT_EDITOR="nano" # runs in the same terminal as babyrus.
URL_BROWSER="firefox"
#+++ CONFIGURATION END +++#

# ADD COMMANDS FOR VIEWERS.
declare -A VIEWER_COMMANDS=(
    # Txt editors
    ["gnome-text-editor"]="gnome-text-editor"
    ["gedit"]="gedit"
    ["kate"]="kate"
    ["mousepad"]="mousepad"
    ["featherpad"]="featherpad"
    ["xed"]="xed"
    ["geany"]="geany"
    ["code"]="code"    

    # PDF viewers
    ["evince"]="evince -p"
    ["okular"]="okular -p"
    ["zathura"]="zathura -P"
    ["mupdf"]="mupdf -p"
    ["qpdfview"]="qpdfview"

    # EPUB/MOBI/AZW3 viewers
    ["calibre"]="ebook-viewer --open-at"   
    ["foliate"]="foliate --chapter"
    ["bookworm"]="bookworm"
    ["thorium-reader"]="thorium"

    # Default editor (terminal-based)
    ["nano"]="nano"
    ["vim"]="vim"
    ["nvim"]="nvim"
    ["emacs"]="emacs -nw"
    ["micro"]="micro"
    ["helix"]="helix"    

    # URL browsers
    ["firefox"]="firefox"
    ["chromium"]="chromium"
    ["google-chrome"]="google-chrome"
    ["brave-browser"]="brave-browser"
    ["vivaldi"]="vivaldi"
    ["opera"]="opera"
    ["qutebrowser"]="qutebrowser"
    ["lynx"]="lynx"
    ["w3m"]="w3m"    
)

# List of common linux apps for extension.
declare -A AVAILABLE_CMDS=(
  ["txt"]="gnome-text-editor gedit kate mousepad featherpad xed geany code"
  ["pdf"]="evince okular zathura atril xpdf mupdf firefox"
  ["epub"]="calibre foliate okular bookworm thorium-reader"
  ["mobi"]="calibre okular"
  ["azw3"]="calibre okular"
  ["DEFAULT_EDITOR"]="nano vim nvim emacs micro helix"
  ["URL_BROWSER"]="firefox chromium google-chrome brave-browser vivaldi opera qutebrowser lynx w3m"
)

# Function to edit configuration using whiptail
edit_configuration() {
    avail_cmds_menu() {
        local chosen_ext="$1"
        local current_val="$2"
        local -a menu_items
        local app

        # Convert string to array
        read -ra apps <<< "${AVAILABLE_CMDS[$chosen_ext]}"

        # Build whiptail menu arguments
        for app in "${apps[@]}"; do
            menu_items+=("$app" "")
        done

        local chosen_cmd
        chosen_cmd=$(whiptail --title "Select Command" \
            --default-item "$current_val" \
            --menu "Choose application for $chosen_ext" \
            20 70 10 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3) || return 1

        ! command -v "$chosen_cmd" &>/dev/null && {
           whiptail --msgbox "Command not found: ${chosen_cmd}. Install it first!" 8 50 >/dev/tty
            return 1
        }

        printf '%s\n' "$chosen_cmd"
    }

    toggle_first_run() {
        local source_file="${BABYRUS_PATH}/babyrus.sh"        

        sed -i \
            '/^#+++ FIRST RUN +++#$/,/^#+++ FIRST RUN END +++#$/ s/^FIRST_RUN=0$/FIRST_RUN=1/' \
            "$source_file"
    }    

    [[ $FIRST_RUN -eq 0 ]] && {
        whiptail --title "First run" --msgbox \
"This is the first time you are running BABYRUS.

In the next screen, choose the default apps." 11 60 >/dev/tty
    }

    local config_file="${BABYRUS_PATH}/babyrus.sh"
    local backup_file="${config_file}.bak"
    local temp_file=$(mktemp)

    # Reload configuration from file before making changes
    source <(sed -n '/^#+++ CONFIGURATION +++#$/,/^#+++ CONFIGURATION END +++#$/{//!p}' "$config_file")

    # --- Make a local backup in memory ---
    local -A BACKUP_EC
    for key in "${!EXTENSION_COMMANDS[@]}"; do
        BACKUP_EC["$key"]="${EXTENSION_COMMANDS[$key]}"
    done
    # --- Also env variables ---
    local BACKUP_DE="$DEFAULT_EDITOR"
    local BACKUP_UB="$URL_BROWSER"

    # Create ordered list of extensions for consistent display
    local ordered_exts=("txt" "pdf" "epub" "mobi" "azw3")

    while true; do
        # Build menu options
        local options=()
        for ext in "${ordered_exts[@]}"; do
            options+=("${ext}" "${EXTENSION_COMMANDS[$ext]}")
        done
        options+=("DEFAULT_EDITOR" "${DEFAULT_EDITOR}")
        options+=("URL_BROWSER" "${URL_BROWSER}")
        options+=("Save" "Save changes")

        local choice
        choice=$(whiptail --title "Set Default Apps" --menu \
            "Choose a setting to modify:" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        # Cancel pressed
        [[ $? -ne 0 ]] && {
            # --- Revert EXTENSION_COMMANDS and env variables from local backup ---
            for key in "${!BACKUP_EC[@]}"; do
                EXTENSION_COMMANDS["$key"]="${BACKUP_EC[$key]}"
            done
            DEFAULT_EDITOR="$BACKUP_DE"            
            URL_BROWSER="$BACKUP_UB"

            [[ $FIRST_RUN -eq 0 ]] && exit
            return 1
        }

        local current_value
        local new_value
        case "$choice" in
            DEFAULT_EDITOR|URL_BROWSER)
                current_value="${!choice}"
                new_value="$(avail_cmds_menu "$choice" "$current_value")" && [[ -n "$new_value" ]] && declare "${choice}=${new_value}"
                ;;
            "Save")
                break
                ;;
            *)
                current_value="${EXTENSION_COMMANDS[$choice]}"
                new_value="$(avail_cmds_menu "$choice" "$current_value")"

                local s_=$?

                [[ $s_ -ne 0 ]] && continue   # user pressed Cancel

                new_value=$(echo "$new_value" | xargs)  # trim spaces

                if [[ ! -v VIEWER_COMMANDS[$new_value] ]]; then
                    whiptail --title "Alert" \
                            --msgbox "${new_value} command is currently unregistered." 8 50 >/dev/tty
                    continue
                fi

                [[ -n "$new_value" ]] && EXTENSION_COMMANDS["$choice"]="$new_value"
                ;;
        esac
    done

    # Ask yesno to user.
    whiptail --title "Confirm" --yesno "Are you sure to proceed?" 8 40 || {
        # --- Revert EXTENSION_COMMANDS and env variables from local backup ---
        for key in "${!BACKUP_EC[@]}"; do
            EXTENSION_COMMANDS["$key"]="${BACKUP_EC[$key]}"
        done
        DEFAULT_EDITOR="$BACKUP_DE"            
        URL_BROWSER="$BACKUP_UB"       

        [[ $FIRST_RUN -eq 0 ]] && exit 
        return 1
    }

    # Create backup and update configuration file
    cp "$config_file" "$backup_file" 2>/dev/null || true

    # Generate new configuration block
    local new_config_block="#+++ CONFIGURATION +++#
# Tweak this to set external apps.
declare -A EXTENSION_COMMANDS=(
    [\"txt\"]=\"${EXTENSION_COMMANDS[txt]}\"
    [\"pdf\"]=\"${EXTENSION_COMMANDS[pdf]}\"
    [\"epub\"]=\"${EXTENSION_COMMANDS[epub]}\"
    [\"mobi\"]=\"${EXTENSION_COMMANDS[mobi]}\"
    [\"azw3\"]=\"${EXTENSION_COMMANDS[azw3]}\"
)

# Tweak these to set external apps for other sections.
DEFAULT_EDITOR=\"${DEFAULT_EDITOR}\" # runs in the same terminal as babyrus.
URL_BROWSER=\"${URL_BROWSER}\"
#+++ CONFIGURATION END +++#"

    # DEBUG
    #echo new_config_block: >&2
    #echo "$new_config_block" >&2  

    # Use awk to replace the configuration block
    awk -v new="$new_config_block" '
        !block_processed && /#\+\+\+ CONFIGURATION \+\+\+#/ {
            in_block = 1
            block_processed = 1
            printf "%s\n", new
            next
        }
        in_block && /#\+\+\+ CONFIGURATION END \+\+\+#/ {
            in_block = 0
            next
        }
        !in_block {
            print
        }
    ' "$config_file" > "$temp_file"

    # DEBUG
    #echo temp_file: >&2
    #cat $temp_file >&2
    #exit

    mv "$temp_file" "$config_file"
    chmod +x "$config_file"	# make babyrus.sh executable again.
    whiptail --title "Info" --msgbox "Settings saved. Restart BABYRUS to take effect." 8 40

    local first_quit=$FIRST_RUN
    toggle_first_run
    (( first_quit == 0 )) && exit   # if first run and saved config, exit babyrus.
}

# Run edit conf if it's the first time BABYRUS is run.
[[ $FIRST_RUN -eq 0 ]] && edit_configuration

# Create notes directories if not created
mkdir -p "${NOTES_METADATA_PATH}"

# Create if not existent
touch "$NOTES_DB" "$NOTES_TAGS_DB" "$NOTES_EBOOKS_DB"

# CHECK MINIMUM BASH VERSION 5.2.21
check_bash_ver() {
  # Required version components
  local req_major=5 req_minor=2 req_patch=21

  # Extract current Bash version components
  local cur_major=${BASH_VERSINFO[0]}
  local cur_minor=${BASH_VERSINFO[1]}
  local cur_patch=${BASH_VERSINFO[2]}

  local err_msg="Error: You need bash version at least ${req_major}.${req_minor}.${req_patch}."

  # Compare major version
  if (( cur_major < req_major )); then
    echo "$err_msg" >&2
    return 1
  elif (( cur_major > req_major )); then
    # Any major > 5 is automatically OK
    return 0
  fi

  # At this point cur_major == req_major
  # Compare minor version
  if (( cur_minor < req_minor )); then
    echo "$err_msg" >&2
    return 1
  elif (( cur_minor > req_minor )); then
    # 5.x where x > 2 is OK
    return 0
  fi

  # At this point cur_major == 5 && cur_minor == 2
  # Compare patch version
  if (( cur_patch < req_patch )); then
    echo "$err_msg" >&2
    return 1
  fi

  # If we reach here, version is >= 5.2.21
  return 0
}

check_bash_ver || exit 1

# Check dependencies
for cmd in whiptail wmctrl dialog xclip; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done

# old location for wmctrl resize terminal window.

# Database files
#EBOOKS_DB="ebooks.db"  # Format: "path|tag1,tag2,..."
TAGS_DB="${BABYRUS_PATH}/tags.db"      # Format: "tag"

# Ensure databases exist
touch "$EBOOKS_DB" "$TAGS_DB"

# Check all specified external apps are found for 'Manage eBooks' section.
for ext in "${!EXTENSION_COMMANDS[@]}"; do
    cmd="${EXTENSION_COMMANDS[$ext]}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Command for .$ext ($cmd) is not found. Modify EXTENSION_COMMANDS accordingly." >&2
        exit 1
    fi
done

# Check if all commands exist for other sections too.
if ! command -v "$DEFAULT_EDITOR" >/dev/null || \
   ! command -v "$URL_BROWSER" >/dev/null; then
    echo "This script requires '${DEFAULT_EDITOR}', '${URL_BROWSER}' in order to run correctly." >&2
    exit 1
fi

# Function to display the "In operation..." infobox
in_operation_msg() {
    :
    #TERM=ansi whiptail --infobox "In operation..." 8 40 >/dev/tty
}

# Optimsed for speed when listing files under current directory.
list_files() {
    local path="$1"
    local mode="$2"
    local entry name

    local entries=(".." "up")

    if [[ "$mode" == "D" ]]; then
        for entry in "$path"/*/ "$path"/.[!.]*/ "$path"/..?*/; do
            [[ -d "$entry" ]] || continue

            # Remove duplicate leading slashes.
            [[ "$entry" == //* ]] && entry="/${entry#//}"

            entries+=("${entry%/}" "")
        done

    elif [[ "$mode" == "F" ]]; then
        for entry in "$path"/* "$path"/.[!.]* "$path"/..?*; do
            [[ -f "$entry" ]] || continue

            # Remove duplicate leading slashes.
            [[ "$entry" == //* ]] && entry="/${entry#//}"

            name="${entry##*/}"
            entries+=("$entry" "$name")
        done
    fi

    printf '%s\x1E' "${entries[@]}"
}

list_files_old() {
    local path="$1"
    local mode="$2"

    local entries=(".." "up")
    for entry in "$path"/{*,.*}; do
        # Skip if the entry is "." or ".."
        [[ "$(basename "$entry")" == "." || "$(basename "$entry")" == ".." ]] && continue

        # normalise path
        entry="$(echo -n "$entry" | tr -s '/')"

        if [[ -d "$entry" && "$mode" == "D" ]]; then
            entries+=("$entry" "")
        elif [[ -f "$entry" && "$mode" == "F" ]]; then
            entries+=("$entry" "$(basename "$entry")")
        fi
    done

   printf "%s\x1E" "${entries[@]}"
}

# debug
#echo list_files: >&2 
#list_files "$(pwd)" "D" | cat -v >&2

navigate() {
    local current_path="$1"
    local page=0 total pages start end i h w lh selected selected_path
    local -a all dirs menu

    while true; do
        # list_files prints: ".." "up" then every sub-directory (pairs)
        mapfile -t -d $'\x1E' all < <(list_files "$current_path" "D")
        dirs=("${all[@]:2}")
        total=$(( ${#dirs[@]} / 2 ))
        pages=$(( (total + EB_PAGE_SIZE - 1) / EB_PAGE_SIZE ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$(( pages - 1 ))
        (( page < 0 )) && page=0
        start=$(( page * EB_PAGE_SIZE ))
        end=$(( start + EB_PAGE_SIZE ))
        (( end > total )) && end=$total

        menu=("SELECT" "select" ".." "up")
        (( page > 0 )) && menu+=("__PREV_PAGE__" "Previous page")
        (( page < pages - 1 )) && menu+=("__NEXT_PAGE__" "Next page")
        for (( i=start; i<end; i++ )); do
            menu+=("${dirs[2*i]}" "${dirs[2*i+1]}")
        done

        read -r h w lh <<< "$(eb_menu_dims)"
        selected=$(whiptail --title "File Browser" \
                            --menu "Current Directory: $current_path\nSelect a folder to search files.\nPage $((page + 1))/${pages}  |  ${total} sub-director(ies)" \
                            "$h" "$w" "$lh" \
                            "${menu[@]}" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            break
        fi

        case "$selected" in
            __PREV_PAGE__) (( page-- )); continue ;;
            __NEXT_PAGE__) (( page++ )); continue ;;
            SELECT) echo "$current_path"; break ;;
        esac

        [[ "$selected" == ".." ]] && selected_path="$(dirname "$current_path")" || selected_path="$selected"

        if [ -d "$selected_path" ]; then
            current_path="$selected_path"
            page=0
        fi
    done
}

# debug
#navigate "$(pwd)"

split_second_print() {
	local array=("$@")
	local counter=0

	# Loop over each element in the array
	for element in "${array[@]}"; do
	    # Increment the counter
	    ((counter++))
	    
	    # Print the element followed by \x1e character
	    printf "%s\x1E" "$element"
	    
	    # After every second element, print \x1f character
	    if (( counter % 2 == 0 )); then
	        printf "\x1F"
	    fi
	done
}

# debug
#split_arr_test=("apple" "banana" "cherry" "date" "elderberry" "fig")
#split_second_print "${split_arr_test[@]}" | cat -v >&2

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

truncate_tags() {
    local input="$1"
    # Split input into tags, trimming whitespace for each tag
    local tags=()
    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do

        # Trim leading and trailing whitespace
        part="$(echo "$part" | awk '{sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print}')"

        [[ -n "$part" ]] && tags+=("$part")
    done

    # Handle empty input
    (( ${#tags[@]} == 0 )) && { echo ""; return; }

    # Check if already within limit
    local joined=$(IFS=','; echo "${tags[*]}")
    if (( ${#joined} <= 65 )); then
        echo "$joined"
        return
    fi

    local last_tag="${tags[-1]}"
    local n=${#tags[@]}
    local max_k=-1

    # Find maximum number of leading tags we can keep
    for ((k=0; k <= n-2; k++)); do
        local sum=0
        for ((i=0; i<k; i++)); do
            ((sum += ${#tags[i]}))
        done
        # Calculate total length: sum + 3 (...) + last_tag + commas (k+1)
        local total=$(( sum + ${#last_tag} + k + 1 + 3 ))
        (( total <= 65 )) && max_k=$k || break
    done

    # Build truncated result if possible
    if (( max_k >= 0 )); then
        local truncated=("${tags[@]:0:max_k}" "..." "$last_tag")
        local result=$(IFS=','; echo "${truncated[*]}")
        echo "$result"
        return
    fi

    # Fallback: truncate last tag if needed
    local max_last_len=$(( 65 - 4 ))  # Reserve space for "...","
    echo "...,${last_tag:0:$max_last_len}"
}


############################################################
# Manage eBooks helpers (tag formatting, directory scopes)
############################################################

# Short tag display used by every whiptail screen of the 'Manage eBooks'
# workflow:   [tag1,tag2,tag3 +N]   where N = number of tags - 3.
# Three tags or fewer are shown in full: [tag1,tag2]. No tags: []
format_tags_short() {
    local input="$1" part
    local -a raw=() tags=()
    IFS=',' read -ra raw <<< "$input"
    for part in "${raw[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ -n "$part" ]] && tags+=("$part")
    done

    local n=${#tags[@]}
    if (( n == 0 )); then
        printf '[]'
    elif (( n <= 3 )); then
        local IFS=','
        printf '[%s]' "${tags[*]}"
    else
        local IFS=','
        printf '[%s +%d]' "${tags[*]:0:3}" $(( n - 3 ))
    fi
}

# Same logic as format_tags_short() for use inside awk programs. Paste this
# text into the awk program: it defines fmt_tags(tags).
AWK_FMT_TAGS='
    function fmt_tags(t,    n, a, i, c, out) {
        n = split(t, a, ",")
        c = 0; out = ""
        for (i = 1; i <= n; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", a[i])
            if (a[i] == "") continue
            c++
            if (c <= 3) out = out (c > 1 ? "," : "") a[i]
        }
        if (c > 3) return "[" out " +" (c - 3) "]"
        return "[" out "]"
    }
'

# Prints every directory that holds registered files PLUS the immediate parent
# directory of each of them (sorted, unique). For example if the db has files
# under /path/to/some/files/sub1 and /path/to/some/files/sub2 then
# /path/to/some/files is listed too. "/" itself is never listed.
ebooks_dirs_with_parents() {
    awk -F'|' '
    NF > 0 && $1 != "" {
        p = $1
        if (!sub(/\/[^\/]+$/, "", p) || p == "") next
        dirs[p] = 1
        q = p
        if (sub(/\/[^\/]+$/, "", q) && q != "") dirs[q] = 1
    }
    END { for (d in dirs) print d }
    ' "$EBOOKS_DB" | sort
}

# Succeeds when at least one registered file lives directly inside directory $1.
ebooks_dir_has_direct_files() {
    awk -F'|' -v d="$1" '
    BEGIN { found = 1 }
    NF > 0 {
        p = $1
        sub(/\/[^\/]+$/, "", p)
        if (p == d) { found = 0; exit }
    }
    END { exit found }
    ' "$EBOOKS_DB"
}

# Fills DIR_MENU_ITEMS with "dir" "description" pairs ready for a whiptail menu.
# Parent directories remain selectable, but selecting one does not implicitly
# include sub-directories; that is controlled explicitly in the file-list UI.
ebooks_dir_menu_items() {
    DIR_MENU_ITEMS=()
    local d
    while IFS= read -r d; do
        [[ -n "$d" ]] && DIR_MENU_ITEMS+=("$d" "")
    done < <(ebooks_dirs_with_parents)

    (( ${#DIR_MENU_ITEMS[@]} > 0 ))
}

# Prints the db lines of files directly inside directory $1, or also below it
# when the optional second argument is 1.
ebooks_lines_in_scope() {
    local dir="$1" rec="${2:-0}"
    [[ "$rec" == "1" ]] || rec=0
    awk -F'|' -v d="$dir" -v rec="$rec" '
    NF > 0 {
        p = $1
        sub(/\/[^\/]+$/, "", p)
        if (p == d || (rec == 1 && index(p, d "/") == 1)) print
    }
    ' "$EBOOKS_DB"
}

############################################################
# Manage eBooks: paginated lists with glob / tag filtering
############################################################

EB_PAGE_SIZE=50          # items per whiptail page
EB_WIDTH=155             # width of every whiptail list
EB_GLOB=""               # active glob filter (file path or file name)
EB_TAGF=""               # active tag filter (literal substring of tags)
EB_PAGE=0                # current page (0-based), kept between calls
EB_NO_TAGS=0             # 1 = the listed files have no tags (hides tag filter)
EB_SRC_FILE=""           # file holding the 'path|tags' lines to browse
EB_SELECTED_LINE=""      # result of ebooks_pick_file()
EB_FILTERED=()           # lines left after the filters are applied
declare -A EB_SEL=()     # checklist selections (key: path, value: 1/0)
EB_PATH_MAX=0            # truncate displayed file paths to this many characters (0 = never)
EB_TAG_PICK=0            # 1 = __FILTER_BY_TAG__ asks a substring, then lets you pick ONE tag
EB_LIST_ONLY=0           # 1 = list is informational (selecting a file shows its full path)
EB_NO_FILTERS=0          # 1 = hide the glob / tag filter items
EB_PROCEED=""            # name of an extra "proceed" item of a menu (e.g. __ADD__); returns 2
EB_PROCEED_DESC=""       # its description (@N@ = number of listed files)
EB_NO_TAG_ITEM=0         # 1 = the tag picker also offers [NO TAG] (only files without tags)
EB_NO_TAG_VALUE="__NO_TAG__"   # value of EB_TAGF while the [NO TAG] filter is active
EB_SCOPE_DIR=""           # restrict a file list to this directory
EB_RECURSIVE=0             # include sub-directories when EB_SCOPE_DIR is set

# Prints "height width list-height" for a whiptail list that shows
# EB_PAGE_SIZE items (plus the action/navigation items). The height is capped
# to the terminal height; whiptail scrolls inside the list when it is smaller.
eb_menu_dims() {
    babyrus_whiptail_dimensions
}
eb_menu_dims_old() {
    local rows want h
    rows=$( { stty size </dev/tty; } 2>/dev/null | cut -d' ' -f1)
    [[ "$rows" =~ ^[0-9]+$ ]] || rows=0
    want=$(( EB_PAGE_SIZE + 16 ))
    h=$want
    (( rows > 0 && h > rows )) && h=$rows
    (( h < 14 )) && h=14
    echo "$h $EB_WIDTH $(( h - 10 ))"
}

ebooks_filter_reset() {
    EB_GLOB=""
    EB_TAGF=""
    EB_PAGE=0
    EB_SEL=()
    # per-list display modes: every list sets what it needs after the reset
    EB_PATH_MAX=0
    EB_TAG_PICK=0
    EB_LIST_ONLY=0
    EB_NO_FILTERS=0
    EB_PROCEED=""
    EB_PROCEED_DESC=""
    EB_NO_TAG_ITEM=0
    EB_SCOPE_DIR=""
    EB_RECURSIVE=0
}

# Truncates a file path for a whiptail menu / checklist item: when the path is
# longer than $2 characters, the beginning is replaced by "..." so the result
# is exactly $2 characters long and still ends with the file name.
# $2 = 0 (or missing) means: do not truncate.
eb_trunc_path() {
    local p="$1" max="${2:-0}"
    if (( max > 3 && ${#p} > max )); then
        printf '...%s' "${p: -$(( max - 3 ))}"
    else
        printf '%s' "$p"
    fi
}

# Print at most the first ten files from a named array. Entries may be plain
# paths or EBOOKS_DB lines (path|tags). Set the second argument to "tags" to
# include shortened tags beside each path; set it to "raw" for arbitrary text
# such as old -> new rename pairs.
ebooks_file_list_preview() {
    local array_name="$1" mode="${2:-path}" total i line path tags
    local -n entries="$array_name"
    total=${#entries[@]}

    for (( i=0; i<total && i<10; i++ )); do
        line="${entries[i]}"
        case "$mode" in
            tags)
                path="${line%%|*}"
                tags="${line#*|}"
                printf '  %s %s\n' "$(eb_trunc_path "$path" 110)" "$(format_tags_short "$tags")"
                ;;
            raw)
                printf '  %s\n' "$line"
                ;;
            *)
                printf '  %s\n' "${line%%|*}"
                ;;
        esac
    done

    if (( total > 10 )); then
        printf '  ... (%d more)\n' "$(( total - 10 ))"
    fi
}

# awk function used by every glob filter: glob2re(glob) -> anchored regex
EB_AWK_GLOB='
function glob2re(g,    i, ch, out) {
    out = ""
    for (i = 1; i <= length(g); i++) {
        ch = substr(g, i, 1)
        if (ch == "*")      out = out ".*"
        else if (ch == "?") out = out "."
        else if (index(".^$+(){}|[]\\", ch)) out = out "\\" ch
        else                out = out ch
    }
    return "^" out "$"
}
'

# Filters the paths read from stdin (one per line) with EB_GLOB (file path or
# file name, case insensitive). Without a glob everything passes.
ebooks_glob_filter() {
    if [[ -z "$EB_GLOB" ]]; then
        cat
        return
    fi
    EB_GLOB="$EB_GLOB" awk "$EB_AWK_GLOB"'
    BEGIN { re = glob2re(tolower(ENVIRON["EB_GLOB"])) }
    {
        lp = tolower($0)
        name = lp
        sub(/^.*\//, "", name)
        if (lp ~ re || name ~ re) print
    }'
}

# Applies EB_GLOB (matches the whole file path OR the file name, case
# insensitive, * and ? wildcards) and EB_TAGF (literal, case insensitive
# substring of the tags) to EB_SRC_FILE. Result: EB_FILTERED array.
ebooks_filter_apply() {
    EB_FILTERED=()
    [[ -f "$EB_SRC_FILE" ]] || return 0
    mapfile -t EB_FILTERED < <(
        EB_GLOB="$EB_GLOB" EB_TAGF="$EB_TAGF" EB_TAGEXACT="$EB_TAG_PICK" EB_NOFILT="$EB_NO_FILTERS" \
        EB_SCOPE_DIR="$EB_SCOPE_DIR" EB_RECURSIVE="$EB_RECURSIVE" \
        awk -F'|' "$EB_AWK_GLOB"'
        BEGIN {
            g = tolower(ENVIRON["EB_GLOB"])
            t = tolower(ENVIRON["EB_TAGF"])
            exact = (ENVIRON["EB_TAGEXACT"] == "1")
            d = ENVIRON["EB_SCOPE_DIR"]
            rec = (ENVIRON["EB_RECURSIVE"] == "1")
            prefix = (d == "/" ? "/" : d "/")
            if (ENVIRON["EB_NOFILT"] == "1") { g = ""; t = "" }
            if (g != "") re = glob2re(g)
        }
        NF > 0 {
            if (d != "") {
                p = $1
                sub(/\/[^\/]*$/, "", p)
                if (p == "") p = "/"
                if (p != d && !(rec && index(p, prefix) == 1)) next
            }
            if (g != "") {
                lp = tolower($1)
                name = lp
                sub(/^.*\//, "", name)
                if (!(lp ~ re || name ~ re)) next
            }
            if (t != "") {
                if (t == "__no_tag__") {
                    x = $2
                    gsub(/^[ \t,]+|[ \t,]+$/, "", x)
                    if (x != "") next
                } else if (exact) {
                    found = 0
                    n = split(tolower($2), a, ",")
                    for (i = 1; i <= n; i++) {
                        x = a[i]
                        gsub(/^[ \t]+|[ \t]+$/, "", x)
                        if (x == t) { found = 1; break }
                    }
                    if (!found) next
                } else if (index(tolower($2), t) == 0) next
            }
            print
        }' "$EB_SRC_FILE"
    )
}

# Asks the user for a glob / tag filter. Used by the list actions.
ebooks_ask_glob() {
    local g
    g=$(whiptail --title "__APPLY_GLOB__" --inputbox \
"Enter a glob to filter the files by FILE PATH and FILE NAME (case insensitive).\n\
* matches any characters (also across directories), ? matches one character.\n\
The whole path or the file name alone must match, e.g.  *schaum*  or  /books/*/math*.pdf\n\
Empty input removes the glob filter." 14 "$EB_WIDTH" "$EB_GLOB" 3>&1 1>&2 2>&3) || return 1
    EB_GLOB="$g"
    EB_PAGE=0
}

ebooks_ask_tagfilter() {
    # In substring mode, explicitly offer [NO TAG] alongside the existing
    # substring-filter workflow. Exact-tag mode uses the tag picker below,
    # which also offers [NO TAG].
    if (( EB_TAG_PICK == 1 )); then
        ebooks_pick_tag_filter
        return
    fi

    local choice t current_filter="${EB_TAGF}"
    [[ "$current_filter" == "$EB_NO_TAG_VALUE" ]] && current_filter=""

    choice=$(whiptail --title "__FILTER_BY_TAG__" --menu \
        "Choose how to filter the files by tag:" 12 "$EB_WIDTH" 2 \
        "[NO TAG]" "Only show files with no tag associated" \
        "__TAG_SUBSTRING__" "Filter by a tag-name substring" \
        3>&1 1>&2 2>&3) || return 1

    case "$choice" in
        "[NO TAG]")
            EB_TAGF="$EB_NO_TAG_VALUE"
            ;;
        "__TAG_SUBSTRING__")
            t=$(whiptail --title "__FILTER_BY_TAG__" --inputbox \
"Enter part of a tag name (literal substring match, case insensitive; not a glob or regex).\n\
Only files having a tag that contains this text are listed.\n\
Empty input removes the tag filter." 12 "$EB_WIDTH" "$current_filter" 3>&1 1>&2 2>&3) || return 1
            EB_TAGF="$t"
            ;;
    esac
    EB_PAGE=0
}

# __FILTER_BY_TAG__ for lists that filter by ONE tag: ask for a literal
# substring, list the tags (of the files currently listed, glob applied) that
# contain it and let the user pick one tag. The list is then filtered by that
# exact tag.
ebooks_pick_tag_filter() {
    local sub tag saved
    local -a matches=() pairs=()

    sub=$(whiptail --title "__FILTER_BY_TAG__" --inputbox \
"Enter part of a tag name (literal substring match, case insensitive; not a glob or regex).\n\
The matching tags are listed next and you can pick one of them.\n\
Empty input lists ALL tags." 12 "$EB_WIDTH" "" 3>&1 1>&2 2>&3) || return 1

    # tags carried by the files that pass the glob filter
    saved="$EB_TAGF"
    EB_TAGF=""
    ebooks_filter_apply
    EB_TAGF="$saved"
    mapfile -t matches < <(
        printf '%s\n' "${EB_FILTERED[@]}" | EB_SUB="$sub" awk -F'|' '
        BEGIN { s = tolower(ENVIRON["EB_SUB"]) }
        {
            n = split($2, a, ",")
            for (i = 1; i <= n; i++) {
                x = a[i]
                gsub(/^[ \t]+|[ \t]+$/, "", x)
                if (x != "" && (s == "" || index(tolower(x), s))) seen[x] = 1
            }
        }
        END { for (x in seen) print x }' | sort
    )

    # Always offer [NO TAG], even when no tagged files match the entered
    # substring. Selecting it filters the current source to untagged files only.
    pairs+=("[NO TAG]" "Only show files with no tags")
    for tag in "${matches[@]}"; do
        pairs+=("$tag" "")
    done
    tag="$(eb_paginate_tags_menu "Select a Tag to Filter By" "${pairs[@]}")" || return 1
    if [[ "$tag" == "[NO TAG]" ]]; then
        EB_TAGF="$EB_NO_TAG_VALUE"
    else
        EB_TAGF="$tag"
    fi
    EB_PAGE=0
}

# Items shared by the menu and the checklist: filter actions + page navigation.
# $1 = "menu" or "check". Fills the global EB_ACTION_ITEMS array.
ebooks_action_items() {
    local kind="$1" pages="$2" extra=()
    [[ "$kind" == "check" ]] && extra=("OFF")
    EB_ACTION_ITEMS=()
    if (( EB_NO_FILTERS == 0 )); then
        EB_ACTION_ITEMS+=("__APPLY_GLOB__" "Filter by glob (file path and file name)${EB_GLOB:+   [glob: $EB_GLOB]}" "${extra[@]}")
        EB_ACTION_ITEMS+=("__RESET_GLOB__" "Reset glob filter" "${extra[@]}")
        if (( EB_NO_TAGS == 0 )); then
            EB_ACTION_ITEMS+=("__FILTER_BY_TAG__" "Filter by tag${EB_TAGF:+   [tag filter: ${EB_TAGF/$EB_NO_TAG_VALUE/[NO TAG]}]}" "${extra[@]}")
            EB_ACTION_ITEMS+=("__RESET_FILTER__" "Reset tag filter" "${extra[@]}")
        fi
    fi
    if [[ -n "$EB_SCOPE_DIR" ]]; then
        EB_ACTION_ITEMS+=("__RECURSIVE__" "Include files from sub-directories" "${extra[@]}")
        EB_ACTION_ITEMS+=("__RESET_RECURSIVE__" "Reset recursive scope (current directory only)" "${extra[@]}")
    fi
    (( EB_PAGE > 0 )) && EB_ACTION_ITEMS+=("__PREV_PAGE__" "Previous page" "${extra[@]}")
    (( EB_PAGE < pages - 1 )) && EB_ACTION_ITEMS+=("__NEXT_PAGE__" "Next page" "${extra[@]}")
}

# Handles one of the filter / navigation actions. Returns 1 for unknown items.
ebooks_do_action() {
    case "$1" in
        __APPLY_GLOB__)    ebooks_ask_glob ;;
        __RESET_GLOB__)    EB_GLOB=""; EB_PAGE=0 ;;
        __FILTER_BY_TAG__) ebooks_ask_tagfilter ;;
        __RESET_FILTER__)  EB_TAGF=""; EB_PAGE=0 ;;
        __RECURSIVE__)     EB_RECURSIVE=1; EB_PAGE=0 ;;
        __RESET_RECURSIVE__) EB_RECURSIVE=0; EB_PAGE=0 ;;
        __PREV_PAGE__)     (( EB_PAGE-- )) ;;
        __NEXT_PAGE__)     (( EB_PAGE++ )) ;;
        *) return 1 ;;
    esac
    return 0
}

# One-line description of the filters + position, shown above the list.
ebooks_list_status() {
    local page="$1" pages="$2" total="$3"
    local s="Page ${page}/${pages}  |  ${total} file(s)"
    if (( EB_NO_FILTERS == 0 )); then
        s+="  |  glob: ${EB_GLOB:-(none)}"
        if (( EB_NO_TAGS == 0 )); then
            local tf="${EB_TAGF/$EB_NO_TAG_VALUE/[NO TAG]}"
            s+="  |  tag filter: ${tf:-(none)}"
        fi
    fi
    if [[ -n "$EB_SCOPE_DIR" ]]; then
        (( EB_RECURSIVE == 1 )) && s+="  |  scope: including sub-directories" || s+="  |  scope: this directory only"
    fi
    printf '%s' "$s"
}

# Shows a paginated menu (50 files per page) of the files in EB_SRC_FILE with
# __APPLY_GLOB__ / __RESET_GLOB__ / __FILTER_BY_TAG__ / __RESET_FILTER__ items.
# Both filters can be active at the same time. Filters and the page are kept
# between calls, call ebooks_filter_reset first for a fresh list.
# Returns 0 with EB_SELECTED_LINE set ("path|tags"), 1 on Back / Esc.
ebooks_pick_file() {
    local title="$1" prompt="${2:-Select a file}"
    local total pages start end i line choice h w lh shown
    local -a items

    while true; do
        ebooks_filter_apply
        total=${#EB_FILTERED[@]}
        pages=$(( (total + EB_PAGE_SIZE - 1) / EB_PAGE_SIZE ))
        (( pages < 1 )) && pages=1
        (( EB_PAGE >= pages )) && EB_PAGE=$(( pages - 1 ))
        (( EB_PAGE < 0 )) && EB_PAGE=0
        start=$(( EB_PAGE * EB_PAGE_SIZE ))
        end=$(( start + EB_PAGE_SIZE ))
        (( end > total )) && end=$total

        ebooks_action_items menu "$pages"
        items=("${EB_ACTION_ITEMS[@]}")
        if [[ -n "$EB_PROCEED" ]]; then
            items+=("$EB_PROCEED" "${EB_PROCEED_DESC//@N@/$total}")
        fi
        for (( i=start; i<end; i++ )); do
            line="${EB_FILTERED[i]}"
            shown="$(eb_trunc_path "${line%%|*}" "$EB_PATH_MAX")"
            if (( EB_NO_TAGS == 0 )); then
                items+=("$(( i + 1 ))" "${shown} $(format_tags_short "${line#*|}")")
            else
                items+=("$(( i + 1 ))" "${shown}")
            fi
        done

        read -r h w lh <<< "$(eb_menu_dims)"
        choice=$(whiptail --title "$title" --cancel-button "Back" \
            --menu "${prompt}\n$(ebooks_list_status "$((EB_PAGE + 1))" "$pages" "$total")" \
            "$h" "$w" "$lh" "${items[@]}" 3>&1 1>&2 2>&3) || return 1

        if ebooks_do_action "$choice"; then
            continue
        fi
        # proceed item (e.g. __ADD__ / __PROCEED__): return code 2
        if [[ -n "$EB_PROCEED" && "$choice" == "$EB_PROCEED" ]]; then
            return 2
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
            line="${EB_FILTERED[choice - 1]}"
            if (( EB_LIST_ONLY == 1 )); then
                # list shown for information: selecting an item shows its full path
                whiptail --title "Full file path" --msgbox "${line%%|*}" 10 "$EB_WIDTH"
                continue
            fi
            EB_SELECTED_LINE="$line"
            return 0
        fi
    done
}

# Same as ebooks_pick_file() but multi-select (checklist). Selected files are
# remembered in EB_SEL across pages and filter changes. Tick ONE action item
# (e.g. __PROCEED__) and press OK to run it.
# Returns 0 on __PROCEED__, 1 on Cancel / Esc.
ebooks_pick_files_checklist() {
    local title="$1" prompt="$2" proceed_label="$3"
    local total pages start end i line path choice h w lh t result shown
    local -a items sel actions

    while true; do
        ebooks_filter_apply
        total=${#EB_FILTERED[@]}
        pages=$(( (total + EB_PAGE_SIZE - 1) / EB_PAGE_SIZE ))
        (( pages < 1 )) && pages=1
        (( EB_PAGE >= pages )) && EB_PAGE=$(( pages - 1 ))
        (( EB_PAGE < 0 )) && EB_PAGE=0
        start=$(( EB_PAGE * EB_PAGE_SIZE ))
        end=$(( start + EB_PAGE_SIZE ))
        (( end > total )) && end=$total

        ebooks_action_items check "$pages"
        items=("${EB_ACTION_ITEMS[@]}" "__PROCEED__" "$proceed_label" "OFF")
        for (( i=start; i<end; i++ )); do
            line="${EB_FILTERED[i]}"
            path="${line%%|*}"
            shown="$(eb_trunc_path "$path" "$EB_PATH_MAX")"
            local state="OFF"
            [[ "${EB_SEL["$path"]:-0}" == "1" ]] && state="ON"
            if (( EB_NO_TAGS == 0 )); then
                items+=("f$(( i + 1 ))" "${shown} $(format_tags_short "${line#*|}")" "$state")
            else
                items+=("f$(( i + 1 ))" "${shown}" "$state")
            fi
        done

        local n_sel=0 p
        for p in "${!EB_SEL[@]}"; do [[ "${EB_SEL["$p"]}" == "1" ]] && (( n_sel++ )); done

        read -r h w lh <<< "$(eb_menu_dims)"
        result=$(whiptail --title "$title" --cancel-button "Cancel" \
            --checklist "${prompt}\n$(ebooks_list_status "$((EB_PAGE + 1))" "$pages" "$total")  |  selected: ${n_sel}\nTick files with SPACE; tick ONE action item and press OK to run it." \
            "$h" "$w" "$lh" "${items[@]}" 3>&1 1>&2 2>&3) || return 1

        result=${result//\"/}
        read -r -a sel <<< "$result"

        # remember the ticks of the files shown on this page
        for (( i=start; i<end; i++ )); do
            path="${EB_FILTERED[i]%%|*}"
            if printf '%s\n' "${sel[@]}" | grep -qx "f$(( i + 1 ))"; then
                EB_SEL["$path"]=1
            else
                EB_SEL["$path"]=0
            fi
        done

        actions=()
        for t in "${sel[@]}"; do
            [[ "$t" == __* ]] && actions+=("$t")
        done
        if (( ${#actions[@]} > 1 )); then
            whiptail --title "Invalid Selection" --msgbox "Please tick only ONE action item at a time (filter, reset, page navigation or proceed)." 10 100
            continue
        fi
        (( ${#actions[@]} == 0 )) && continue

        if [[ "${actions[0]}" == "__PROCEED__" ]]; then
            return 0
        fi
        ebooks_do_action "${actions[0]}"
    done
}

# Paginated (50 per page) directory picker: registered directories plus their
# parents (see ebooks_dir_menu_items). Prints the chosen directory.
ebooks_select_dir() {
    local prompt="${1:-Choose a directory:}"
    local page=0 total_dirs total_pages start end i sel h w lh
    local -a menu_items all_items

    if ! ebooks_dir_menu_items; then
        whiptail --title "Attention" --msgbox "No directories found! Perhaps ebooks db is empty." 10 60 >/dev/tty
        return 1
    fi
    all_items=("${DIR_MENU_ITEMS[@]}")
    total_dirs=$(( ${#all_items[@]} / 2 ))
    total_pages=$(( (total_dirs + EB_PAGE_SIZE - 1) / EB_PAGE_SIZE ))

    while true; do
        menu_items=()
        (( page > 0 )) && menu_items+=("__PREV_PAGE__" "Previous page")
        (( page < total_pages - 1 )) && menu_items+=("__NEXT_PAGE__" "Next page")
        start=$(( page * EB_PAGE_SIZE ))
        end=$(( start + EB_PAGE_SIZE ))
        (( end > total_dirs )) && end=$total_dirs
        for (( i=start; i<end; i++ )); do
            menu_items+=("${all_items[2*i]}" "${all_items[2*i+1]}")
        done

        read -r h w lh <<< "$(eb_menu_dims)"
        sel=$(whiptail --title "Select Directory" \
            --menu "${prompt}\nPage $((page + 1))/${total_pages}  |  ${total_dirs} director(ies)" \
            "$h" "$w" "$lh" "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$sel" in
            __NEXT_PAGE__) (( page++ )) ;;
            __PREV_PAGE__) (( page-- )) ;;
            *) printf '%s\n' "$sel"; return 0 ;;
        esac
    done
}

# Paginated tag picker. Args: title, then "tag" "desc" pairs.
# When the first item is [NO TAG], pin it at the top of EVERY page so the
# untagged-file filter remains available regardless of how many tags exist.
# Prints the chosen tag (first column).
eb_paginate_tags_menu() {
    local title="$1"
    shift
    local items=("$@")
    local total_items=$(( ${#items[@]} / 2 ))
    local pinned_no_tag=0 data_offset=0 page_size="$EB_PAGE_SIZE" data_items
    if (( total_items > 0 )) && [[ "${items[0]}" == "[NO TAG]" ]]; then
        pinned_no_tag=1
        data_offset=2
        (( page_size > 1 )) && (( page_size-- ))
    fi
    data_items=$(( total_items - pinned_no_tag ))
    local total_pages=$(( (data_items + page_size - 1) / page_size ))
    (( total_pages < 1 )) && total_pages=1
    local current_page=1 choice start_index end_index i h w lh
    local -a menu_items

    while true; do
        start_index=$(( data_offset + (current_page - 1) * page_size * 2 ))
        end_index=$(( start_index + page_size * 2 ))
        menu_items=()
        (( pinned_no_tag == 1 )) && menu_items+=("${items[0]}" "${items[1]}")
        (( current_page > 1 )) && menu_items+=("<< Prev" "")
        (( current_page < total_pages )) && menu_items+=(">> Next" "")
        for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
            menu_items+=("${items[i]}" "${items[i+1]}")
        done

        read -r h w lh <<< "$(eb_menu_dims)"
        choice=$(whiptail --title "$title" \
            --menu "Page ${current_page}/${total_pages}" "$h" "$w" "$lh" \
            "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            ">> Next") (( current_page++ )) ;;
            "<< Prev") (( current_page-- )) ;;
            *) printf '%s\n' "$choice"; return 0 ;;
        esac
    done
}

generate_trunc() {
	counter=1

	while IFS= read -r -d $'\x1f' group; do
	    # Skip empty groups (e.g., from trailing separator)
	    [[ -z "$group" ]] && continue
	    
	    # Split group into fields using \x1E as delimiter
	    IFS=$'\x1e' read -r fullpath filename _ <<< "$group"

	    # truncated fullpath will just be dirname without file name.
	    fullpath="$(dirname "$fullpath")"

	    # truncate long fullpath	    
	    truncated_path="[${fullpath}]"

	    # truncate long file name
	    truncated_filename="$filename"

            printf "%s:%s\x1E%s\x1E" "$counter" "$truncated_path" "$truncated_filename"
            ((counter++))
	done < <(split_second_print "$@")
}

generate_trunc_delete_ebook() {
	local counter=1
	local path tags dir file
	local truncated_dir truncated_file truncated_tags

        while IFS= read -r -d $'\x1f' group; do
            # Skip empty groups (e.g., from trailing separator)
            [[ -z "$group" ]] && continue

            # Split group into fields using \x1E as delimiter
            IFS=$'\x1e' read -r path tags _ <<< "$group"

	    dir="$(dirname "$path")"
	    file="$(basename "$path")"

	    # Truncate
	    truncated_dir="$dir"
	    truncated_file="$file"

	    # Truncate tags: [tag1,tag2,tag3 +N]
	    truncated_tags="$(format_tags_short "$tags")"

            printf "%s:%s\x1E%s\x1E" "$counter" "${truncated_dir}/${truncated_file}" "${truncated_tags}"
            ((counter++))
        done < <(split_second_print "$@")
}

generate_trunc_assoc_tag() {
        local counter=1
        local path tags space dir file
        local truncated_dir truncated_file

        while IFS= read -r -d $'\x1f' group; do
            # Skip empty groups (e.g., from trailing separator)
            [[ -z "$group" ]] && continue

            # Split group into fields using \x1E as delimiter
            IFS=$'\x1e' read -r path tags _ <<< "$group"

            dir="$(dirname "$path")"
            file="$(basename "$path")"

            # Truncate
            truncated_dir="$dir"
            truncated_file="$file"

            printf "%s:%s\x1E%s\x1E" "$counter" "${truncated_dir}/${truncated_file} $(format_tags_short "$tags")" " "
            ((counter++))
        done < <(split_second_print "$@")
}

generate_trunc_dissoc_tag() {
        local counter=1
        local path tags dir file
        local truncated_dir truncated_file truncated_tags

        while IFS= read -r -d $'\x1f' group; do
            # Skip empty groups (e.g., from trailing separator)
            [[ -z "$group" ]] && continue

            # Split group into fields using \x1E as delimiter
            IFS=$'\x1e' read -r path tags _ <<< "$group"

            dir="$(dirname "$path")"
            file="$(basename "$path")"

            # Truncate
            truncated_dir="$dir"
            truncated_file="$file"

	    # Truncate tags: [tag1,tag2,tag3 +N]
	    truncated_tags="$(format_tags_short "$tags")"

            printf "%s:%s\x1E%s\x1E" "$counter" "${truncated_dir}/${truncated_file}" "$truncated_tags"
            ((counter++))
        done < <(split_second_print "$@")
}

generate_trunc_lookup() {
        local idx the_rest path tags dir file
        local truncated_dir truncated_file truncated_tags

        while IFS= read -r -d $'\x1f' group; do
            # Skip empty groups (e.g., from trailing separator)
            [[ -z "$group" ]] && continue

            # Split group into fields using \x1E as delimiter
            IFS=$'\x1e' read -r idx the_rest _ <<< "$group"

            # the_rest format: /path/to/file/some book.pdf|tag1,another tag
            path=${the_rest%|*}
            tags=${the_rest##*|}

            dir="$(dirname "$path")"
            file="$(basename "$path")"

            # Truncate
            truncated_dir="$dir"
            truncated_file="$file"

            # Truncate tags: [tag1,tag2,tag3 +N]
            truncated_tags="$(format_tags_short "$tags")"

            printf "%s\x1E%s\x1E" "$idx" "${truncated_dir}/${truncated_file} ${truncated_tags}"
        done < <(split_second_print "$@")
}

# debug
#a="$(printf 'a%.0s' {1..55})"
#b="$(printf 'b%.0s' {1..55})"
#c='ccc'
#test_arr=("$a" 'a' "$b" 'b' "$c" 'c')
#echo generate_trunc: >&2
#generate_trunc "${test_arr[@]}" | cat -v >&2

# Global variables to hold the list and current page
TRUNC=()         # will hold the list items
CURRENT_PAGE=0   # persists page state across paginate() calls

paginate() {
    # Clear any previous selection
    SELECTED_ITEM=""

    local chunk_size=$EB_PAGE_SIZE

    # If new items are passed in, update TRUNC and reset CURRENT_PAGE.
    if [ "$#" -gt 0 ]; then
        TRUNC=("$@")
        CURRENT_PAGE=0
    fi

    local total_pages=$(( ( ${#TRUNC[@]} + chunk_size - 1 ) / chunk_size ))
    # Ensure CURRENT_PAGE is within valid bounds
    if (( CURRENT_PAGE >= total_pages )); then
        CURRENT_PAGE=$(( total_pages - 1 ))
    fi

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        # Extract the current chunk from the global TRUNC
        local current_chunk=("${TRUNC[@]:$start:$chunk_size}")
        local menu_options=()

        # Add navigation options if needed
        if (( CURRENT_PAGE > 0 )); then
            menu_options+=("previous page" "")
        fi
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("next page" "")
        fi

        # Append the current page items
        menu_options+=("${current_chunk[@]}")

        choice=$(whiptail --title "Paged Menu" --cancel-button "Back" \
            --menu "Choose an item (Page $((CURRENT_PAGE + 1))/$total_pages)" \
            $(eb_menu_dims) \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3)

        # Exit if user cancels
        if [ $? -ne 0 ]; then
            break
        fi

        case "$choice" in
            "previous page")
                (( CURRENT_PAGE-- ))
                ;;
            "next page")
                (( CURRENT_PAGE++ ))
                ;;
            *)
                # Return the selected item (page state remains for next call)
                SELECTED_ITEM="$choice"
                return 0
                ;;
        esac
    done

    return 1
}

# Example usage:
# result=$(paginate "Item 1" "Item 2" "Item 3" "Item 4" "Item 5")
# echo "Selected: $result"

# Store every logic for detecting illegal file names here.
check_illegal_filenames() {
    local input="$1"
    local illegal_files=()
    # Split the input into an array using the ASCII record separator (0x1E)
    IFS=$'\x1e' read -ra parts <<< "$input"
    # Iterate over basenames (every second element starting from index 1)
    for ((i=1; i < ${#parts[@]}; i += 2)); do
        local basename="${parts[i]}"

        # Illegal file name logic here.
        if [[ "$basename" == -* || "$basename" == *"|"* ]]; then
            illegal_files+=("$basename")
        fi
    done
    # Output results and return appropriate exit code.
    if (( ${#illegal_files[@]} > 0 )); then
        local msg="Error: ${#illegal_files[@]} illegal filename(s) found:\n\n"
        msg+="$(ebooks_file_list_preview illegal_files raw)"
        msg+="\nConsider renaming the files and retry.\n"
        whiptail --title "Error" --msgbox "$(printf '%b' "$msg")" 15 155
        return 1
    fi
    return 0
}

register_ebook() {
    local search_path
    search_path="$(navigate "$(pwd)")"

    [ -z "$search_path" ] && return

    in_operation_msg

    # List the files of the chosen directory (non-recursive). Files that cannot
    # be registered (name starting with '-' or containing '|') are skipped.
    local tmp f
    local -a illegal_files=()
    tmp=$(mktemp) || return 1
    while IFS= read -r -d '' f; do
        if [[ "${f##*/}" == -* || "$f" == *"|"* ]]; then
            illegal_files+=("${f##*/}")
            continue
        fi
        printf '%s|\n' "$f" >> "$tmp"
    done < <(find "$search_path" -maxdepth 1 -type f -print0 | sort -z)

    if (( ${#illegal_files[@]} > 0 )); then
        local illegal_msg="${#illegal_files[@]} illegal file name(s) skipped; they cannot be registered:\n\n"
        illegal_msg+="$(ebooks_file_list_preview illegal_files raw)"
        illegal_msg+="\nConsider renaming the files and retry."
        whiptail --title "Error" --msgbox "$illegal_msg" 20 155
    fi

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        whiptail --title "No Matches Found" --msgbox "No files found in: $search_path" 8 155
        return 1
    fi

    EB_SRC_FILE="$tmp"
    EB_NO_TAGS=1
    ebooks_filter_reset
    EB_PATH_MAX=140
    local rc=0
    ebooks_pick_file "Select Ebook" "Choose a file to register in: $search_path" || rc=1
    EB_NO_TAGS=0
    EB_SRC_FILE=""
    rm -f "$tmp"
    (( rc != 0 )) && return 1

    local selected="${EB_SELECTED_LINE%|}"

    if [[ -f "$EBOOKS_DB" ]] && EB_P="$selected" awk -F'|' '$1 == ENVIRON["EB_P"] { f = 1 } END { exit !f }' "$EBOOKS_DB"; then
        whiptail --msgbox "Ebook already registered!" 8 40
        return
    fi

    echo "$selected|" >> "$EBOOKS_DB"
    whiptail --msgbox "Registered: $selected" 20 155
}

# debug
#register_ebook
#exit

# Need to register a tag in order to associate to ebook.
register_tag() {
    while true; do
        tag=$(whiptail --inputbox "Enter new tag name (no commas , or pipes |):" 8 40 3>&1 1>&2 2>&3)
        if [[ $? -ne 0 ]]; then return; fi

        if [[ -z "$tag" ]]; then
            whiptail --msgbox "Tag name cannot be empty!" 8 40
            continue
        fi

	# Make sure new tag name doesn't contain banned characters: , or |.
        if [[ "$tag" == *","* || "$tag" == *"|"* ]]; then
            whiptail --msgbox "Tag name cannot contain commas (,) or pipes (|)!" 8 50
            continue
        fi
        
#        if [[ "$tag" == *","* ]]; then
#            whiptail --msgbox "Tag name cannot contain commas!" 8 40
#            continue
#        fi
        
	# try to match each line exactly.
        if grep -Fxqi "$tag" "$TAGS_DB"; then
            whiptail --msgbox "Tag already exists!" 8 40
        else
            echo "$tag" >> "$TAGS_DB"
            whiptail --msgbox "Tag '$tag' registered!" 8 40
            return
        fi
    done
}

# pairs for whiptail's menu items.
make_into_pairs() {
    local arg
    local pairs=()
    # Build pairs like "arg\x1Eitem"
    for arg in "$@"; do
        pairs+=("${arg}"$'\x1E'" ")
    done
    # Join all pairs with \x1E between them
    (IFS=$'\x1E'; echo "${pairs[*]}")
}

# Filter to narrow down search.
filter_ebooks() {
    local filter_str="$1"
    shift
    local my_array=("$@")

    # Escape special glob characters and convert to lowercase
    local filter_str_escaped=$(sed 's/[][*?]/\\&/g' <<< "${filter_str,,}")

    # Case-insensitive literal substring match.
    for element in "${my_array[@]}"; do
        if [[ "$filter_str" == "*" || "${element,,}" == *"${filter_str_escaped}"* ]]; then
            printf "%s\0" "$element"
        fi
    done
}

# Filter to narrow down search when dissociating tag.
filter_menu_items() {
    local filter_str="$1"
    shift
    local my_array=("$@")

    # Escape special glob characters and convert to lowercase
    local filter_str_escaped=$(sed 's/[][*?]/\\&/g' <<< "${filter_str,,}")

    # Iterate over the array in steps of two to process path-tag pairs
    for ((i=0; i < ${#my_array[@]}; i+=2)); do
        # Ensure there is a corresponding tag to avoid errors on odd array lengths
        if (( i+1 >= ${#my_array[@]} )); then
            continue
        fi
        local path="${my_array[i]}"
        local tag="${my_array[i+1]}"

        # Check if the path matches the filter (case-insensitive substring match)
        if [[ "$filter_str" == "*" || "${path,,}" == *"${filter_str_escaped}"* ]]; then
            # Output both path and tag as null-delimited strings
            printf "%s\0" "$path"
            printf "%s\0" "$tag"
        fi
    done
}

associate_tag() {
    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1

    local ebook existing_tags tag t tmpfile
    local -a tags sorted tags_whip

    while :; do
        ebooks_pick_file "Associate Tag" "Select an eBook to associate a tag with" || return

        ebook="${EB_SELECTED_LINE%%|*}"
        existing_tags="${EB_SELECTED_LINE#*|}"

        mapfile -t tags < "$TAGS_DB"
        if [[ ${#tags[@]} -eq 0 ]]; then
            whiptail --msgbox "No tags registered!" 8 40
            return
        fi

        mapfile -t sorted < <(printf '%s\n' "${tags[@]}" | sort)
        tags_whip=()
        for t in "${sorted[@]}"; do
            tags_whip+=("$t" "")
        done

        tag="$(eb_paginate_tags_menu "Choose a Tag to Associate to File" "${tags_whip[@]}")" || continue

        if [[ ",${existing_tags}," == *",${tag},"* ]]; then
            whiptail --msgbox "Ebook already has this tag!" 8 40
            continue
        fi

        whiptail --title "Confirm" --yesno "Do you want me to go ahead and associate '${tag}' to '${ebook}'?" 20 155 || continue

        tmpfile=$(mktemp)
        EB_P="$ebook" EB_T="$tag" awk '
            BEGIN { FS = OFS = "|" }
            $1 == ENVIRON["EB_P"] {
                if ($2 == "") $2 = ENVIRON["EB_T"]
                else $2 = $2 "," ENVIRON["EB_T"]
            }
            { print }
        ' "$EBOOKS_DB" > "$tmpfile" && mv "$tmpfile" "$EBOOKS_DB"

        whiptail --msgbox "Tag '$tag' added to '$ebook'!" 20 155
    done
}

# Orphaned
generate_ebooks_list() {
    local counter=1
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines if desired
        [[ -z "$line" ]] && continue
        echo "${counter}:${line}"
        ((counter++))
    done < "$EBOOKS_DB"
}

generate_ebooks_result_list() {
    local counter=1
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines if desired
        [[ -z "$line" ]] && continue
        echo "${counter}:${line}"
        ((counter++))
    done < "$1"
}

# generate_ebooks_list is orphaned.
view_tags() {
    if [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]]; then
        whiptail --title "Attention" --msgbox "No tags registered." 10 40
        return
    fi

    local -a all_tags=() tags=() items=()
    mapfile -t all_tags < <(sort "$TAGS_DB" | awk 'NF')

    if (( ${#all_tags[@]} == 0 )); then
        whiptail --title "Attention" --msgbox "No tags registered." 10 40
        return
    fi

    local filter="" page=0
    local total pages start end i h w lh choice t sub

    while true; do
        # __FILTER_BY_TAG__: literal, case insensitive substring match on the tag
        tags=()
        if [[ -z "$filter" ]]; then
            tags=("${all_tags[@]}")
        else
            for t in "${all_tags[@]}"; do
                [[ "${t,,}" == *"${filter,,}"* ]] && tags+=("$t")
            done
        fi

        total=${#tags[@]}
        pages=$(( (total + EB_PAGE_SIZE - 1) / EB_PAGE_SIZE ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$(( pages - 1 ))
        (( page < 0 )) && page=0
        start=$(( page * EB_PAGE_SIZE ))
        end=$(( start + EB_PAGE_SIZE ))
        (( end > total )) && end=$total

        items=()
        items+=("__FILTER_BY_TAG__" "Filter tags by literal substring${filter:+   [tag filter: $filter]}")
        items+=("__RESET_FILTER__" "Reset tag filter")
        (( page > 0 )) && items+=("__PREV_PAGE__" "Previous page")
        (( page < pages - 1 )) && items+=("__NEXT_PAGE__" "Next page")
        for (( i=start; i<end; i++ )); do
            items+=("${tags[i]}" "")
        done

        read -r h w lh <<< "$(eb_menu_dims)"
        choice=$(whiptail --title "Tags" --cancel-button "Back" \
            --menu "Registered tags: ${#all_tags[@]}  |  Matching: ${total}  |  Page $((page + 1))/${pages}  |  tag filter: ${filter:-(none)}" \
            "$h" "$w" "$lh" "${items[@]}" 3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            __FILTER_BY_TAG__)
                sub=$(whiptail --title "__FILTER_BY_TAG__" --inputbox \
"Enter part of a tag name (literal substring match, case insensitive; not a glob or regex).\n\
Only the tags that contain this text are listed.\n\
Empty input lists ALL tags." 12 "$EB_WIDTH" "$filter" 3>&1 1>&2 2>&3) && { filter="$sub"; page=0; }
                ;;
            __RESET_FILTER__) filter=""; page=0 ;;
            __NEXT_PAGE__)    (( page++ )) ;;
            __PREV_PAGE__)    (( page-- )) ;;
        esac
    done
}

dissociate_tag_from_registered_ebook() {
    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1

    ebooks_pick_file "Dissociate Tag" "Select an eBook to remove a tag from" || return 0

    local selected_ebook="${EB_SELECTED_LINE%%|*}"
    local original_tags="${EB_SELECTED_LINE#*|}"
    local tag
    local -a raw_tags tags_array=() tag_menu_items=() new_tags=()

    IFS=',' read -ra raw_tags <<< "$original_tags"
    for tag in "${raw_tags[@]}"; do
        [[ -n "$tag" ]] && tags_array+=("$tag")
    done

    [[ ${#tags_array[@]} -eq 0 ]] && whiptail --msgbox "No tags associated with this eBook!" 8 40 && return 0

    for tag in "${tags_array[@]}"; do
        tag_menu_items+=("$tag" "")
    done

    local selected_tag
    selected_tag=$(eb_paginate_tags_menu "Remove Tag from eBook" "${tag_menu_items[@]}") || return 0

    whiptail --yesno "Remove tag '$selected_tag' from:\n$selected_ebook?" 20 155 || return 0

    for tag in "${tags_array[@]}"; do
        [[ "$tag" != "$selected_tag" ]] && new_tags+=("$tag")
    done

    local new_tags_str=""
    if [[ ${#new_tags[@]} -gt 0 ]]; then
        new_tags_str="$(IFS=','; echo "${new_tags[*]}")"
    fi

    local temp_file
    temp_file=$(mktemp)

    EB_P="$selected_ebook" EB_NEW="$new_tags_str" awk '
        BEGIN { FS = OFS = "|" }
        $1 == ENVIRON["EB_P"] { print $1 "|" ENVIRON["EB_NEW"]; next }
        { print }
    ' "$EBOOKS_DB" > "$temp_file"

    mv -f "$temp_file" "$EBOOKS_DB"
    whiptail --msgbox "Tag '$selected_tag' removed from '$selected_ebook'!" 20 155
}

delete_tag_from_global_list() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=$EB_PAGE_SIZE
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" $(eb_menu_dims) \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

    # Check dependencies
    [[ ! -f "$TAGS_DB" ]] && whiptail --msgbox "Tags database not found!" 8 40 && return 1
    [[ ! -f "$EBOOKS_DB" ]] && whiptail --msgbox "Ebooks database not found!" 8 40 && return 1

    # Read tags database
    local tags_list=()
    mapfile -t tags_list < "$TAGS_DB"
    [[ ${#tags_list[@]} -eq 0 ]] && whiptail --msgbox "No tags available!" 8 40 && return 0

    # FIX: SORT TAGS IN TAGS_LIST AND REBUILD TAGS_LIST ARRAY.
    # Sort the array
    IFS=$'\n' sorted=($(sort <<<"${tags_list[*]}"))
    unset IFS
    
    # Rebuild the original array
    tags_list=("${sorted[@]}")
    # END FIX.

    # Create menu items
    local menu_items=()
    for tag in "${tags_list[@]}"; do
        menu_items+=("$tag" "")
    done

    # # Tag selection
    # local selected_tag
    # selected_tag=$(whiptail --title "Delete Global Tag" --menu "Choose tag to delete:" \
    #     20 60 10 "${menu_items[@]}" 3>&1 1>&2 2>&3)
    # [[ $? -ne 0 ]] && return 0  # User canceled

    # FIX: PAGINATE TAG SELECTION.
    local selected_tag
    selected_tag="$(paginate_tags_menu "Choose tag to delete from global list:" "${menu_items[@]}")" || return 1

    # Check for tag usage in ebooks
    local used_in=()
    while IFS='|' read -r path tags; do
        IFS=',' read -ra etags <<< "$tags"
        for tag in "${etags[@]}"; do
            [[ "$tag" == "$selected_tag" ]] && used_in+=("$path") && break
        done
    done < "$EBOOKS_DB"

    # If tag is still in use
    if [[ ${#used_in[@]} -gt 0 ]]; then
        local message="Tag is used in ${#used_in[@]} eBook(s):\n\n"
        message+="$(ebooks_file_list_preview used_in)"
        message+="\nDissociate tag first!"
        whiptail --scrolltext --msgbox "$message" 20 155
        return 1
    fi

    # Final confirmation
    whiptail --yesno "Permanently delete tag:\n'$selected_tag'?" 10 40 || return 0

    # Delete from tags database
    grep -Fx -v -- "$selected_tag" "$TAGS_DB" > "$TAGS_DB.tmp"; mv -f "$TAGS_DB.tmp" "$TAGS_DB"
    #grep -Fx -v -- "$selected_tag" "$TAGS_DB" > "$TAGS_DB.tmp" && mv -f "$TAGS_DB.tmp" "$TAGS_DB" # BIG FIX. you know why this doesn't work?
    # it's because LHS is false when grep output is empty so RHS is not run.
    whiptail --msgbox "Tag '$selected_tag' deleted successfully!" 8 40
}

remove_registered_ebook() {
    if [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]]; then
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40
        return 1
    fi

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1

    ebooks_pick_file "Select Ebook to Remove" "Select a registered eBook to remove from the database" || return 1

    local selected_path="${EB_SELECTED_LINE%%|*}"

    whiptail --title "Confirm Removal" --yesno "Are you sure you want to remove:\n$selected_path" 20 155 \
        --yes-button "Remove" --no-button "Cancel" 3>&1 1>&2 2>&3

    if [ $? -eq 0 ]; then
        local temp_file
        temp_file=$(mktemp)

        EB_P="$selected_path" awk -F'|' '$1 != ENVIRON["EB_P"]' "$EBOOKS_DB" > "$temp_file"
        mv "$temp_file" "$EBOOKS_DB"

        whiptail --title "Success" --msgbox "'${selected_path}' removed successfully!" 20 155
    fi
}

# Open eBook codes start here:

# Get appropriate open command for file type
get_open_command() {
    local file="$1"
    local extension="${file##*.}"
    local cmd="${EXTENSION_COMMANDS[$extension]}"
    
    [ -z "$cmd" ] && cmd="xdg-open"
    
    command -v "$cmd" >/dev/null 2>&1 || {
        whiptail --msgbox "ERROR: Command '$cmd' not found for $extension files" 10 60
        return 1
    }
    echo "$cmd"
}

# File opening handler with existence check
open_file() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        whiptail --msgbox "ERROR: File does not exist:\n$file" 20 155
        return 1
    fi
    
    local open_cmd
    if ! open_cmd=$(get_open_command "$file"); then
        return 1
    fi

    # maybe a good idea to show 'Opening file for you...' for a second
    #TERM=ansi whiptail --infobox "Opening file for you..." 8 40
    #sleep 1
    
    $open_cmd "$file" &>/dev/null & disown
}

# Open eBook by Search workflow: filter by glob (file path / file name) and by
# tag (__FILTER_BY_TAG__ asks for a literal substring, lists the matching tags
# paginated, or ALL tags when empty, plus a [NO TAG] item).
open_file_by_search() {
    if [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]]; then
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1

    ebooks_pick_file "Open eBook by Search" "Select a file to open (filter with __APPLY_GLOB__ / __FILTER_BY_TAG__)" || return 1

    local selected="${EB_SELECTED_LINE%%|*}"
    [ -z "$selected" ] && whiptail --msgbox "No file selected." 10 60 && return 1
    open_file "$selected" || whiptail --msgbox "Error opening file: ${selected}." 20 155
}

illegal_pattern() {
    local pattern="$1"
    if echo "$pattern" | grep -qE '^\||[^|]\|[^|]|\|{3,}|\|$'; then
        return 1  # Illegal pattern detected
    else
        return 0  # No illegal patterns
    fi
}

add_files_in_bulk() {
    whiptail --title "Bulk Add eBooks" --msgbox \
"This advanced feature allows you to add multiple eBook files to the database.\n\
It involves the following steps:\n\
1. Select a root directory to search\n\
2. The files found (txt, pdf, epub, mobi, azw3) that are not registered yet are listed. Narrow the list down with __APPLY_GLOB__ (file path or file name, case insensitive) / __RESET_GLOB__\n\
3. Select __ADD__ to add ALL the listed files to the database" 14 100

    local selected_dir
    selected_dir=$(navigate "$(pwd)")

    if [[ -z "$selected_dir" ]]; then
        return 1
    fi

    in_operation_msg

    # Candidates: not registered yet. Done in ONE pipeline (find | awk | sort)
    # instead of a bash loop doing a read + a printf >> per file, which is very
    # slow with thousands of files. awk loads the registered paths from the DB
    # (first input) and filters the find output (second input). File names
    # containing '|' (or a newline) cannot be stored and are left out.
    local tmp db_src="$EBOOKS_DB"
    [[ -f "$db_src" ]] || db_src=/dev/null
    tmp=$(mktemp) || return 1
    find "$selected_dir" \
        -type f \
        \( \
            -iname '*.txt' \
            -o -iname '*.pdf' \
            -o -iname '*.epub' \
            -o -iname '*.mobi' \
            -o -iname '*.azw3' \
        \) \
        ! -name '*|*' ! -path $'*\n*' \
        -print 2>/dev/null \
    | awk -F'|' '
        FILENAME == ARGV[1] { reg[$1] = 1; next }   # registered paths (DB, first field)
        {
            f = $0
            gsub(/\/\//, "/", f)            # normalize path (same as before)
            if (!(f in reg)) print f
        }' "$db_src" - \
    | sort \
    | sed 's/$/|/' > "$tmp"

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        whiptail --msgbox "No new files found in: $selected_dir\n(files already in the database are not listed)" 10 155
        return 0
    fi

    EB_SRC_FILE="$tmp"
    ebooks_filter_reset
    EB_NO_TAGS=1
    EB_PATH_MAX=120
    EB_LIST_ONLY=1
    EB_PROCEED="__ADD__"
    EB_PROCEED_DESC="Add all matched files (@N@) to the database"

    local rc=0
    ebooks_pick_file "Bulk Add eBooks" "New files under: ${selected_dir}. Select __ADD__ to add all listed files." || rc=$?

    local -a to_add=("${EB_FILTERED[@]}")
    EB_NO_TAGS=0
    EB_SRC_FILE=""
    rm -f "$tmp"
    ebooks_filter_reset

    (( rc != 2 )) && return 1

    if (( ${#to_add[@]} == 0 )); then
        whiptail --msgbox "No files matched. Nothing to add." 8 50
        return 1
    fi

    whiptail --title "Confirm" --yesno "${#to_add[@]} entries found. Do you want to proceed and update database?" 8 78 || return 1

    printf '%s\n' "${to_add[@]}" >> "$EBOOKS_DB"

    local result_file
    result_file=$(mktemp)
    {
        echo "Successfully added ${#to_add[@]} files:"
        echo
        ebooks_file_list_preview to_add
    } > "$result_file"
    whiptail --scrolltext --title "Results" --textbox "$result_file" 20 155
    rm -f "$result_file"
}

# Parser for custom boolean patterns into a grep -P regex

convert_literal() {
    local lit="$1"
    local start_anchor=1
    local end_anchor=1

    # Check if the literal starts with *
    if [[ "$lit" == \** ]]; then
        start_anchor=0
        lit="${lit#\*}"
    fi

    # Check if the literal ends with *
    if [[ "$lit" == *\* ]]; then
        end_anchor=0
        lit="${lit%\*}"
    fi

    # Escape regex special characters except *
    # Corrected character class to include ], [ and others properly
    lit=$(echo "$lit" | sed -E 's/([].^$+?{}|()\\[])/\\\1/g')
    # Replace remaining * with .*
    lit=$(echo "$lit" | sed 's/\*/.*/g')

    # Handle case where lit is empty (e.g., input was *)
    if [ -z "$lit" ]; then
        lit=".*"
    fi

    # Apply start and end anchors
    if [ $start_anchor -eq 1 ]; then
        lit="^$lit"
    else
        lit=".*$lit"
    fi

    if [ $end_anchor -eq 1 ]; then
        lit="$lit$"
    else
        lit="$lit.*"
    fi

    echo "$lit"
}

# Check if a string is enclosed by a matching pair of outer parentheses
is_enclosed_by_parentheses() {
    local s="$1"
    # Must start with ( and end with )
    if [[ ${s:0:1} != "(" || ${s: -1} != ")" ]]; then
         echo 0
         return
    fi
    local level=0
    local i char
    for (( i=0; i<${#s}; i++ )); do
         char="${s:$i:1}"
         if [[ "$char" == "(" ]]; then
             level=$((level+1))
         elif [[ "$char" == ")" ]]; then
             level=$((level-1))
         fi
         # If level drops to 0 before the end, the outer parentheses aren’t encompassing all
         if [ $level -eq 0 ] && [ $i -lt $((${#s}-1)) ]; then
             echo 0
             return
         fi
    done
    echo 1
}

# Split string by a delimiter (e.g. "&&" or "||") at the top level,
# ignoring delimiters inside parentheses.
split_top_level() {
    local s="$1"
    local delim="$2"
    local delim_len=${#delim}
    local level=0
    local token=""
    local i char
    for (( i=0; i<${#s}; i++ )); do
         char="${s:$i:1}"
         if [[ "$char" == "(" ]]; then
             level=$((level+1))
         elif [[ "$char" == ")" ]]; then
             level=$((level-1))
         fi
         if [ $level -eq 0 ] && [[ "${s:$i:$delim_len}" == "$delim" ]]; then
             echo "$token"
             token=""
             i=$(( i + delim_len - 1 ))
         else
             token+="$char"
         fi
    done
    echo "$token"
}

# Parse a primary expression: either a grouped expression or a literal string.
parse_primary() {
    local expr="$1"
    # Trim leading/trailing whitespace.
    expr="$(echo -n "$expr" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ "$expr" == "("*")" ]]; then
         if [ "$(is_enclosed_by_parentheses "$expr")" -eq 1 ]; then
             # Remove outer parentheses and parse inside (non-top-level so no ^)
             expr="${expr:1:-1}"
             echo "$(parse_expr "$expr" 0)"
             return
         fi
    fi
    # Otherwise, treat as literal pattern.
    echo "$(convert_literal "$expr")"
}

# Parse an OR expression by splitting on top-level "||"
parse_or() {
    local expr="$1"
    local alternatives=()
    while IFS= read -r line; do
         alternatives+=("$line")
    done < <(split_top_level "$expr" "||")
    
    # If there’s only one alternative, return its parsed primary.
    if [ ${#alternatives[@]} -eq 1 ]; then
         echo "$(parse_primary "${alternatives[0]}")"
         return
    fi
    local regex_alts=""
    for alt in "${alternatives[@]}"; do
         local parsed
         parsed=$(parse_primary "$alt")
         if [ -z "$regex_alts" ]; then
              regex_alts="$parsed"
         else
              regex_alts="$regex_alts|$parsed"
         fi
    done
    echo "($regex_alts)"
}

# Parse a full boolean expression.
# This splits on top-level "&&" and wraps each part in a lookahead (?=.*...)
# If 'top' is 1 (default), a '^' anchor is prepended.
parse_expr() {
    local expr="$1"
    local top="${2:-1}"
    local parts=()
    while IFS= read -r line; do
         parts+=("$line")
    done < <(split_top_level "$expr" "&&")
    
    local regex=""
    for part in "${parts[@]}"; do
         local part_regex
         part_regex=$(parse_or "$part")
         regex="$regex(?=.*$part_regex)"
    done
    if [ "$top" -eq 1 ]; then
         echo "^$regex"
    else
         echo "$regex"
    fi
}

# Formats string for individual file info.
format_file_info() {
    local selected_line="$1"

    # Split the line at the first '|' into two parts.
    local file_with_path="${selected_line%|*}"
    local tags="${selected_line##*|}"

    # Extract the directory and filename
    local directory
    local filename
    directory=$(dirname "$file_with_path")
    filename=$(basename "$file_with_path")

    # Print the formatted output, now also print file size.
    echo "File name:"
    echo "$filename"
    echo ""
    echo "Directory path:"
    echo "${directory}/"
    echo ""
    echo "Tags:"
    echo "$(format_tags_short "$tags")"
    echo ""
    echo "$(file --mime-type -b "$file_with_path")"
    echo ""
    echo "File size:"
    echo "$(du -h "$file_with_path" | cut -f1)"
}

# Depends on parser code above for parsing custom boolean patterns to be used here.
lookup_registered_files() {
    whiptail --title "Lookup Registered Files" --msgbox \
    "This advanced feature allows you to look up full file information. Narrow the list down with the items shown on top of it:\n\n__APPLY_GLOB__ / __RESET_GLOB__: filter by file path and file name (glob)\n__FILTER_BY_TAG__ / __RESET_FILTER__: filter by tag (literal substring match)\n\nBoth filters can be applied at the same time." 14 100

    if [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]]; then
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1

    while ebooks_pick_file "Lookup Registered Files" "Select a file to see its details"; do
        whiptail --scrolltext --msgbox "$(format_file_info "$EB_SELECTED_LINE")" 25 155
    done
}

# Build list of filtered items from $EBOOKS_DB filtered by full path name and tag.
# NO LONGER USESBOOLEAN PATTERN BUT GLOBBING!!!!
build_bulk() {    
    local pattern regex filtered_paths filtered_lines final_list tag_pattern

    # Step 1: Get the file name search pattern from the user
    pattern=$(whiptail --title "File Lookup" --inputbox "Enter glob pattern for file path and file name (if empty defaults to *):" 8 60 3>&1 1>&2 2>&3 </dev/tty)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to *
    pattern="${pattern:-*}"

    # DEBUG - if need be save to a temp file perhaps?
    #echo pattern: >&2
    #echo "$pattern" >&2

    # Convert pattern to regex using your existing parse_expr function
    #regex=$(parse_expr "$pattern")

    # Filter file paths from $EBOOKS_DB using the regex.
    # Only the file path part is considered (everything before the |)
    #filtered_paths=$(cut -d'|' -f1 "$EBOOKS_DB" | grep -iP "$regex")

    filtered_paths=$(
    awk -F'|' -v glob="$pattern" 'BEGIN { IGNORECASE = 1
        re = "^"
        for (i = 1; i <= length(glob); ++i) {
        c = substr(glob, i, 1)
        if (c == "*")       re = re ".*"
        else if (c == "?")  re = re "."
        else {
            if (c ~ /[][\.\\^$+(){}|]/) re = re "\\" c
            else re = re c
        }
        }
        re = re "$"
    }
    { n = $1; sub(/^.*\//, "", n); if ($1 ~ re || n ~ re) print $1 }
    ' "$EBOOKS_DB"
    )

    if [ -z "$filtered_paths" ]; then
        whiptail --msgbox "No files match the given file name pattern." 8 60 >/dev/tty
        return 1
    fi

    # DEBUG
    #echo filtered_paths: >&2
    #echo "$filtered_paths" >&2 # check!

    # Get the full lines from $EBOOKS_DB corresponding to the filtered file paths.
    # The grep -F -x -f ensures we only get exact matches from the file path field.
    filtered_lines=$(grep -F -f <(echo "$filtered_paths" | sed 's/$/|/') "$EBOOKS_DB")

    # DEBUG
    #echo filtered_lines: >&2
    #echo "$filtered_lines" >&2

    # Tag pattern info. Inform user that tag patterns is not regex or globbing but simple substring match.
    whiptail --title "IMPORTANT NOTE about Tag Patterns" --msgbox \
    "You are about to provide value for a tag pattern. Remember that it is not regex or globbing but simple substring match.\n\
This means if you enter '*schaum*' \\* will be matched literally not as wildcard." 12 60 >/dev/tty

    # Step 2: Ask the user for a tag search pattern
    tag_pattern=$(whiptail --title "Tag Lookup" --inputbox "Enter tag search pattern (literal substring match; if empty wildcard):" 8 60 3>&1 1>&2 2>&3 </dev/tty)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Defaults to .* --- not needed.
    #tag_pattern="${tag_pattern:-.*}"

    # Further filter the lines by matching the tag pattern (which appears after the |)
    #final_list=$(echo "$filtered_lines" | grep -iP "\|.*$tag_pattern")
    final_list=$(printf '%s\n' "$filtered_lines" | grep -iP "\|.*${tag_pattern:+\Q$tag_pattern\E}")   # literal substring match

    if [ -z "$final_list" ]; then
        whiptail --msgbox "No files match the given tag pattern." 8 60 >/dev/tty
        return 1
    fi
    
    # Echo with \0 delimiter for further processing.
    # Remember trailing \0 is actually needed to be transformed into an array.
    echo "$final_list" | while IFS= read -r line; do
        printf '%s\0' "$line"
    done    
}

# Adds tag $1 to every registered file whose path is listed (one per line) in
# file $2. Files that already have the tag are left unchanged.
ebooks_add_tag_to_paths() {
    local tag="$1" list="$2" tmp
    tmp=$(mktemp) || return 1
    EB_T="$tag" awk -F'|' '
        BEGIN { OFS = "|" }
        NR == FNR { m[$0] = 1; next }
        ($1 in m) {
            n = split($2, a, ",")
            has = 0
            for (i = 1; i <= n; i++) {
                x = a[i]
                gsub(/^[ \t]+|[ \t]+$/, "", x)
                if (x == ENVIRON["EB_T"]) has = 1
            }
            if (!has) {
                if ($2 == "") $2 = ENVIRON["EB_T"]
                else $2 = $2 "," ENVIRON["EB_T"]
            }
        }
        { print }
    ' "$list" "$EBOOKS_DB" > "$tmp" && mv -- "$tmp" "$EBOOKS_DB"
}

assoc_tag_to_bulk() {
    whiptail --title "Bulk Associate Tag" --msgbox "This advanced feature lets you choose a registered tag and associate that same tag across a bulk of registered files.\n\nAfter choosing the tag, the registered files are listed. Narrow the list down with __APPLY_GLOB__ / __RESET_GLOB__ (file path or file name) and __FILTER_BY_TAG__ / __RESET_FILTER__ (pick one tag), then select __PROCEED__ to associate the tag with ALL listed files." 14 100

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local -a tags=() sorted=() tag_items=()
    local tag
    while IFS= read -r tag; do
        [[ -n "$tag" ]] && tags+=("$tag")
    done < "$TAGS_DB"

    [[ ${#tags[@]} -eq 0 ]] && {
        whiptail --title "Error" --msgbox "No tags registered. Register at least one tag." 10 70
        return 1
    }

    mapfile -t sorted < <(printf '%s\n' "${tags[@]}" | sort)
    for tag in "${sorted[@]}"; do
        tag_items+=("$tag" "")
    done

    local selected_tag
    selected_tag="$(eb_paginate_tags_menu "Choose a tag to associate to bulk" "${tag_items[@]}")" || return 1

    EB_SRC_FILE="$EBOOKS_DB"
    ebooks_filter_reset
    EB_NO_TAGS=0
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1
    EB_LIST_ONLY=1
    EB_PROCEED="__PROCEED__"
    EB_PROCEED_DESC="Associate tag '${selected_tag}' with all matched files (@N@)"

    local rc=0
    ebooks_pick_file "Bulk Associate Tag: ${selected_tag}" "Select __PROCEED__ to associate '${selected_tag}' with ALL listed files." || rc=$?

    local -a matched=("${EB_FILTERED[@]}")
    ebooks_filter_reset

    (( rc != 2 )) && return 1

    if (( ${#matched[@]} == 0 )); then
        whiptail --title "Error" --msgbox "No files matched. Nothing to update." 10 70
        return 1
    fi

    local line to_update=0
    for line in "${matched[@]}"; do
        [[ ",${line#*|}," == *",${selected_tag},"* ]] || (( to_update++ ))
    done

    whiptail --title "Confirm Update" --yesno \
"${#matched[@]} files are listed; ${to_update} of them do not have the tag yet.\n\nIf you proceed, all of the listed files will be associated with the tag '${selected_tag}'. Do you want to update the database?" 12 100 || return 1

    local list
    list=$(mktemp) || return 1
    printf '%s\n' "${matched[@]%%|*}" > "$list"
    ebooks_add_tag_to_paths "$selected_tag" "$list"
    rm -f "$list"

    whiptail --title "Bulk Update Finished" --msgbox \
"${to_update} file(s) have been associated with the tag '${selected_tag}'." 10 100
}

dissoc_tag_to_bulk() {
    whiptail --title "Bulk Dissociate Tag" --msgbox "This advanced feature lets you choose a registered tag and remove that same tag from a bulk of registered files.\n\nAfter choosing the tag, the files carrying it are listed with their tags. Narrow the list down with __APPLY_GLOB__ / __RESET_GLOB__ (file path or file name) and __FILTER_BY_TAG__ / __RESET_FILTER__ (pick one tag), then select __PROCEED__ to remove the tag from ALL listed files." 14 100

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local selected_tag
    selected_tag="$(ebooks_choose_registered_tag "Choose a tag to dissociate from bulk")" || return 1

    local tmp
    tmp=$(mktemp) || return 1
    ebooks_lines_having_tag "$selected_tag" < "$EBOOKS_DB" > "$tmp"
    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        whiptail --title "No Changes" --msgbox "No files were found with the tag '${selected_tag}'. Database remains unchanged." 10 70
        return 0
    fi

    EB_SRC_FILE="$tmp"
    ebooks_filter_reset
    EB_NO_TAGS=0
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1
    EB_LIST_ONLY=1
    EB_PROCEED="__PROCEED__"
    EB_PROCEED_DESC="Remove tag '${selected_tag}' from all matched files (@N@)"

    local rc=0
    ebooks_pick_file "Bulk Dissociate Tag: ${selected_tag}" "Files carrying '${selected_tag}'. Select __PROCEED__ to remove it from ALL listed files." || rc=$?

    local -a matched=("${EB_FILTERED[@]}")
    EB_SRC_FILE=""
    rm -f "$tmp"
    ebooks_filter_reset

    (( rc != 2 )) && return 1

    if (( ${#matched[@]} == 0 )); then
        whiptail --title "No Changes" --msgbox "No files matched. Database remains unchanged." 10 70
        return 1
    fi

    whiptail --title "Confirm Update" --yesno \
"We have ${#matched[@]} entries that will be modified. If you proceed, all listed entries will have the tag '${selected_tag}' removed. Update database?" \
10 100 || return 1

    local list
    list=$(mktemp) || return 1
    printf '%s\n' "${matched[@]%%|*}" > "$list"
    ebooks_remove_tag_from_paths "$selected_tag" "$list"
    rm -f "$list"

    whiptail --title "Bulk Update Finished" --msgbox \
"${#matched[@]} file(s) have been dissociated from the tag '${selected_tag}'." 10 70
}

# Remove files in bulk.
remove_files_in_bulk() {
    whiptail --title "DANGER: Bulk File Removal" --msgbox \
"This feature lets you remove multiple files from the database in bulk. All files shown in the list are removed permanently from the database when you select __PROCEED__.\n\n\
Narrow the list down with __APPLY_GLOB__ / __RESET_GLOB__ (file path or file name) and __FILTER_BY_TAG__ / __RESET_FILTER__ (pick one tag). Both filters can be combined." 14 100

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    EB_SRC_FILE="$EBOOKS_DB"
    ebooks_filter_reset
    EB_NO_TAGS=0
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_LIST_ONLY=1
    EB_PROCEED="__PROCEED__"
    EB_PROCEED_DESC="Remove all matched files (@N@) from the database"

    local rc=0
    ebooks_pick_file "DANGER: Bulk File Removal" "Select __PROCEED__ to remove ALL listed files from the database." || rc=$?

    local -a to_remove=("${EB_FILTERED[@]}")
    local no_filter=0
    [[ -z "$EB_GLOB" && -z "$EB_TAGF" ]] && no_filter=1
    ebooks_filter_reset

    (( rc != 2 )) && return 1

    if (( ${#to_remove[@]} == 0 )); then
        whiptail --title "Error" --msgbox "No files selected for removal." 10 70
        return 1
    fi

    local warn=""
    (( no_filter == 1 )) && warn="NO FILTER IS ACTIVE: this removes EVERY registered file!\n\n"

    whiptail --title "Confirm Removal" --yesno \
"${warn}About to remove ${#to_remove[@]} entries from the database. This operation cannot be undone!\n\nProceed with deletion?" \
12 78 || return 1

    local list tmpdb
    list=$(mktemp) || return 1
    tmpdb=$(mktemp) || { rm -f "$list"; return 1; }
    printf '%s\n' "${to_remove[@]%%|*}" > "$list"

    awk -F'|' 'NR == FNR { rm[$0] = 1; next } !($1 in rm)' "$list" "$EBOOKS_DB" > "$tmpdb"
    mv -- "$tmpdb" "$EBOOKS_DB"
    rm -f "$list"

    whiptail --title "Removal Complete" --msgbox \
"Successfully removed ${#to_remove[@]} entries from the database." 10 70
}

# Search each line in $EBOOKS_DB for broken entries and remove them.
remove_broken_entries() { 
  # Initial information
  whiptail --title "Remove Broken Entries" --msgbox \
"This feature allows you to fix the database file by finding and removing broken entries (ie. paths to files that point to non-existent files)." 10 78

  # Check if the EBOOKS_DB variable is set and file exists.
  if [ -z "$EBOOKS_DB" ] || [ ! -f "$EBOOKS_DB" ]; then
    whiptail --msgbox "EBOOKS_DB is not set or the file does not exist." 8 78
    return 1
  fi

  # Declare an array to hold conflicting (broken) entries.
  local conflicting_entries=()

  # Process each line in the database.
  while IFS= read -r line; do
    # Retrieve the file path (everything before the first |)
    local filepath="${line%|*}"
    # Check if the file exists.
    if [ ! -f "$filepath" ]; then
      conflicting_entries+=("$line")
    fi
  done < "$EBOOKS_DB"

  # If no broken entries were found, inform the user.
  if [ ${#conflicting_entries[@]} -eq 0 ]; then
    whiptail --msgbox "There are no broken entries in the database." 8 78
    return 0
  fi

  # Prepare a message listing all broken entries.
  #local message="${#conflicting_entries[@]} broken entries found:\n"
  #for entry in "${conflicting_entries[@]}"; do
  #  message+="$entry\n"
  #done

  # Inform the user about the conflicting lines.
  #whiptail --msgbox "$message" 20 78

  # Show a concise preview; the helper includes the exact number omitted.
  local message="${#conflicting_entries[@]} broken entries found:\n\n"
  message+="$(ebooks_file_list_preview conflicting_entries tags)"
  
  # Inform the user about the conflicting lines.
  whiptail --scrolltext --msgbox "$message" 20 155

  # Confirm deletion with the user.
  if whiptail --yesno "Do you want to proceed with deletion of ${#conflicting_entries[@]} conflicting entries?" 8 155; then
    # Create a temporary file.
    local tmp_file
    tmp_file=$(mktemp) || { whiptail --msgbox "Failed to create temporary file." 8 78; return 1; }

    # Write back only the valid entries.
    while IFS= read -r line; do
      local found=0
      for broken in "${conflicting_entries[@]}"; do
        if [ "$line" = "$broken" ]; then
          found=1
          break
        fi
      done
      if [ $found -eq 0 ]; then
        echo "$line" >> "$tmp_file"
      fi
    done < "$EBOOKS_DB"

    # Replace the original database with the filtered version.
    mv "$tmp_file" "$EBOOKS_DB"
    
    # Inform the user that deletion is complete.
    whiptail --msgbox "Deletion of ${#conflicting_entries[@]} conflicting entries has completed." 8 78
  else
    whiptail --msgbox "No entries were deleted." 8 78
  fi
}

# Lookup by choosing a file path from registered files first.
lookup_by_filepath() {
    # Initial message.
    whiptail --title "Lookup By File Path" --msgbox \
"This feature allows you to query files by first choosing a file path among registered files.\n\
After choosing a path from the list, you can further narrow the search with __APPLY_GLOB__ (file path and file name) and __FILTER_BY_TAG__ (literal substring match) shown on top of the file list.\n\
Use __RECURSIVE__ in the file list to include sub-directories." 20 155

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local choice
    choice="$(ebooks_select_dir "Choose a directory for registered files:")" || return 1

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1
    EB_SCOPE_DIR="$choice"
    EB_RECURSIVE=0

    while ebooks_pick_file "Matching files in ${choice}/" "Select a file to see its details"; do
        whiptail --scrolltext --title "Matching file in ${choice}/:" --msgbox "$(format_file_info "$EB_SELECTED_LINE")" 25 155
    done

    ebooks_filter_reset
    EB_SRC_FILE=""
}

# Open file by first selecting its file path and matching by file name pattern and tag pattern.
open_file_by_filepath() {
    # Initial message.
    whiptail --title "Open File By File Path" --msgbox \
"This feature allows you to open a registered file by first choosing a file path from registered files.\n\
After choosing a path from the list, you can further narrow the search with __APPLY_GLOB__ (file path and file name) and __FILTER_BY_TAG__ (literal substring match) shown on top of the file list.\n\
Use __RECURSIVE__ in the file list to include sub-directories.\n\
Then, you can select to open a file item." 20 155

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local choice
    choice="$(ebooks_select_dir "Choose a directory for registered files:")" || return 1

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1
    EB_SCOPE_DIR="$choice"
    EB_RECURSIVE=0

    local file
    while ebooks_pick_file "Open file in ${choice}/" "Select a file to open"; do
        file="${EB_SELECTED_LINE%%|*}"
        open_file "$file" || whiptail --msgbox "Error opening file: ${file}." 20 155
    done

    ebooks_filter_reset
    EB_SRC_FILE=""
}

add_ebooks_from_checklist() {
    local ITEMS_PER_PAGE=$EB_PAGE_SIZE
    ebooks_filter_reset
    EB_PATH_MAX=140
    local start_dir="$(pwd)"
    local current_dir="$start_dir"
    local -a dirs=() files=() items=()
    declare -A global_selected

    # Ensure the eBooks DB exists
    touch "$EBOOKS_DB"

    # Outer loop: directory traversal
    while true; do
        # Build fresh lists of subdirectories and direct files. mapfile does not
        # clear an existing array, so clear both before reading a new directory.
        dirs=()
        files=()
        mapfile -t dirs < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type d | sort)
        # Files are filtered by the glob (file path or file name); directories stay visible.
        mapfile -t files < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type f | sort | ebooks_glob_filter)

        # Show directories first, followed by files, as requested. Both kinds
        # of entries remain paginated and directly selectable.
        items=("${dirs[@]}" "${files[@]}")
        local total=${#items[@]}
        local pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
        (( pages < 1 )) && pages=1
        local current_page=0

        # Paging & selection within this directory
        while true; do
            local start=$(( current_page * ITEMS_PER_PAGE ))
            local end=$(( start + ITEMS_PER_PAGE ))
            (( end > total )) && end=$total
            (( current_page >= pages )) && current_page=$(( pages - 1 ))
            (( current_page < 0 )) && current_page=0
            start=$(( current_page * ITEMS_PER_PAGE ))
            end=$(( start + ITEMS_PER_PAGE ))
            (( end > total )) && end=$total

            # Put special actions first so they remain visible at the top of
            # every page instead of appearing after the file/directory entries.
            local -a choices=(
                "__APPLY_GLOB__" "Filter files by glob (file path and file name)${EB_GLOB:+   [glob: $EB_GLOB]}" "OFF"
                "__RESET_GLOB__" "Reset glob filter" "OFF"
                "__up__" "[DIR] .. (parent)" "OFF"
            )
            (( current_page > 0 ))       && choices+=("__prev__" "Previous page" "OFF")
            (( current_page < pages-1 )) && choices+=("__next__" "Next page" "OFF")
            choices+=("__add__" "Proceed to add selected files" "OFF")

            for (( i=start; i<end; i++ )); do
                local path="${items[$i]}"
                local name_tr
                name_tr="$(eb_trunc_path "$path" "$EB_PATH_MAX")"

                if [[ -d "$path" ]]; then
                    choices+=("dir_$i" "[DIR] $name_tr" "OFF")
                else
                    local state="OFF"
                    [[ "${global_selected[$path]:-0}" == "1" ]] && state="ON"
                    choices+=("file_$i" "$name_tr" "$state")
                fi
            done

            # Show the checklist
            local result
            result=$(whiptail \
                --title "Add eBooks: ${current_dir}" \
                --checklist "Page $((current_page+1))/$pages\nSelect files/directories or navigation action:" \
                $(eb_menu_dims) \
                "${choices[@]}" \
                3>&1 1>&2 2>&3) \
                || { return 1; }

            # Normalize and split selections
            result=${result//\"/}
            IFS=' ' read -r -a sel_tags <<< "$result"

            ##
            # Snapshot the page’s file selections immediately,
            # so that global_selected is updated on any navigation.
            for (( i=start; i<end; i++ )); do
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
                    "__up__"|"__prev__"|"__next__"|"__APPLY_GLOB__"|"__RESET_GLOB__") ((movement_nav_count++)) ;;
                    "__add__")                       ((proceed_count++)) ;;
                    dir_*)                           ((dir_count++)) ;;
                    file_*)                          ((file_count++)) ;;
                esac
            done

            # Validation rules
            if (( movement_nav_count > 1 )); then
                whiptail --title "Invalid Selection" --msgbox "Please select only one of Previous, Next, Up, Apply glob or Reset glob." 10 40
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
                if printf "%s\n" "${sel_tags[@]}" | grep -qx "__APPLY_GLOB__"; then
                    ebooks_ask_glob
                    break
                elif printf "%s\n" "${sel_tags[@]}" | grep -qx "__RESET_GLOB__"; then
                    EB_GLOB=""
                    break
                elif printf "%s\n" "${sel_tags[@]}" | grep -qx "__up__"; then
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
    local msg="These ${#to_add[@]} files will be added to $EBOOKS_DB (skipping duplicates):\n\n"
    msg+="$(ebooks_file_list_preview to_add)"

    if whiptail --scrolltext --yesno "$msg" 20 155 --title "Confirm Addition"; then
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
    local -A used_paths=()
    local -a changes=()
    local -a new_lines=()

    # is this necessary? it's giving no such file error if user selects not to go ahead with renaming.
    touch /tmp/changes.tmp /tmp/new_lines.tmp 2>/dev/null

    # If ebooks.db and ebooks.db.backup files are equal content
    # then we shouldn't proceed!    
    if [[ -f "$EBOOKS_DB_BACKUP" ]] && cmp -s "$EBOOKS_DB" "$EBOOKS_DB_BACKUP"; then
        whiptail --title "Error" --msgbox "Something is wrong. Start afresh by deleting ${EBOOKS_DB_BACKUP} file and try again." 10 50 </dev/tty >/dev/tty
        #echo "ebooks db and ebooks db backup files are the same!" >&2   # debug
        return 1
    fi

    # Create new backup of original database
    cp -- "$EBOOKS_DB" "${EBOOKS_DB_BACKUP}_" || return 1

    # Display whiptail message telling user to wait
    TERM=ansi whiptail --title "Processing" \
         --infobox "Collecting information about illegal filenames registered inside ebooks database.\n\nPlease wait..." 10 60

    # First pass: collect changes and prepare new database
    # Process in awk
    awk -F'|' -v OFS='|' '
    function sanitize(name) {
        gsub(/[,:#;]/, "_", name)
        return name
    }

    {
        path = $1
        tags = $2

        dir = path
        sub(/\/[^\/]*$/, "", dir)  # dirname
        old_basename = path
        sub(/^.*\//, "", old_basename)  # basename

        new_basename = sanitize(old_basename)
        new_path = dir "/" new_basename

        # Only rename if old file name and sanitized version differs
        if (new_basename != old_basename) {
            counter = 1
            while (new_path in used || system("[ -e \"" new_path "\" ]") == 0) {
                split(new_basename, parts, /\./)
                if (length(parts) == 1) {
                    new_basename = parts[1] "_" counter
                } else {
                    ext = parts[length(parts)]
                    name_part = substr(new_basename, 1, length(new_basename) - length(ext) - 1)
                    new_basename = name_part "_" counter "." ext
                }
                new_path = dir "/" new_basename
                counter++
            }
            used[new_path] = 1
            print path "|" new_path > "/tmp/changes.tmp"
            print new_path "|" tags > "/tmp/new_lines.tmp"
        } else {
            # Name unchanged; keep line as-is
            print $0 > "/tmp/new_lines.tmp"
        }
    }
    ' "${EBOOKS_DB_BACKUP}_"

    # Read back into bash arrays and associative array
    while IFS='|' read -r old new; do
        changes+=("$old|$new")
        used_paths["$new"]=1
    done < /tmp/changes.tmp

    while IFS= read -r line; do
        new_lines+=("$line")
    done < /tmp/new_lines.tmp

    # Cleanup temp files
    rm -f /tmp/changes.tmp /tmp/new_lines.tmp 2>/dev/null

    # Show confirmation dialog if changes needed
    if [[ ${#changes[@]} -gt 0 ]]; then
        local change_list
        change_list=$(mktemp) || return 1
        
        local shown_changes=()
        for change in "${changes[@]}"; do
            IFS='|' read -r old new <<< "$change"
            shown_changes+=("$old -> $new")
        done
        ebooks_file_list_preview shown_changes raw > "$change_list"

        whiptail --title "Files to be renamed (${#changes[@]} files)" --scrolltext --textbox "$change_list" 20 155
        rm -f "$change_list"

        if ! whiptail --title "Confirmation" --yesno "Proceed with these changes?" 10 80; then
            rm -f "$TEMP_DB"
            #echo "Operation cancelled by user" >&2
            rm -f "${EBOOKS_DB_BACKUP}_"
            return 1
        fi

        # Only create ebooks db backup file if renaming has occurred.
        cp "${EBOOKS_DB_BACKUP}_" "${EBOOKS_DB_BACKUP}"
        rm -f "${EBOOKS_DB_BACKUP}_"
    else
        whiptail --title "No changes needed" --msgbox "No files with illegal characters found" 8 50
        rm -f "$TEMP_DB"
        rm -f "${EBOOKS_DB_BACKUP}_"
        return 0
    fi

    # Display whiptail message telling user to wait
    TERM=ansi whiptail --title "Processing" \
         --infobox "Changes being applied.\n\nPlease wait..." 10 60

    # Second pass: execute changes
    : > "$LOG_FILE"
    for change in "${changes[@]}"; do
        IFS='|' read -r old new <<< "$change"

        # Debug
        #echo "Before mv:" >&2
        #echo "old: $old" >&2
        #echo "new: $new" >&2
        #exit

        if ! mv -- "$old" "$new"; then
            echo "Error: Failed to rename '$old' to '$new'" >&2
            whiptail --title "Error" --msgbox "Failed to rename '$old' to '$new'. Aborting." 10 155
            rm -f "$TEMP_DB"
            return 1
        fi
        echo "$old|$new" >> "$LOG_FILE"
    done

    # Write new database
    printf "%s\n" "${new_lines[@]}" > "$TEMP_DB"
    mv -- "$TEMP_DB" "$EBOOKS_DB" || return 1

    whiptail --title "Success" --msgbox "Files renamed and database updated!\n\nBackup: $EBOOKS_DB_BACKUP" 12 155
}

revert_rename_illegal_ebook_filenames() {  
    check_backup_and_log() {
        # 1. Check line counts equal
        if [[ $(wc -l < "$EBOOKS_DB") -ne $(wc -l < "$EBOOKS_DB_BACKUP") ]]; then
            echo "Line count mismatch between DB and backup" >&2
            return 1
        fi

        # 2. Check every new_path exists, but don't exit early
        local missing=0

        awk -F'|' '
            {
                new_path = $2
                if (system("[ -f \"" new_path "\" ]") != 0) {
                    printf("Missing file in filesystem: %s\n", new_path) > "/dev/stderr"
                    missing = 1
                }
            }
            END {
                exit missing
            }
        ' "$LOG_FILE" || return 1

        return 0
    }
  
    # Info msgbox about what this function does
    whiptail --title "Info" --msgbox \
"This function reverts changes made by Rename and Reregister Illegal Ebook Filenames function. \
It reverts both ebooks database and physical file names on drive." 10 80

    local EBOOKS_DB_BACKUP="$EBOOKS_DB.backup"
    local LOG_FILE="$EBOOKS_DB.rename.log"

    if [[ ! -f "$EBOOKS_DB_BACKUP" || ! -f "$LOG_FILE" ]]; then
        whiptail --title "Attention" --msgbox "There is nothing to revert." 8 50
        return 1
    fi

    # Extra check to see if ebooks db backup file and log file's integrity holds - test this at the next opportunity!
    check_backup_and_log || return 1

    # Show confirmation dialog
    if ! whiptail --title "Confirmation" --yesno "This will restore original filenames and database. Proceed?" 10 80; then
        #echo "Revert cancelled by user" >&2
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

remove_ebooks_from_checklist() {
    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40
        return 1
    }

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1

    ebooks_pick_files_checklist "Remove Registered eBooks From DB" \
        "Select entries to remove." "Proceed to remove selected entries" || return 1

    local -a selected_paths=()
    local p
    for p in "${!EB_SEL[@]}"; do
        [[ "${EB_SEL["$p"]}" == "1" ]] && selected_paths+=("$p")
    done

    if (( ${#selected_paths[@]} == 0 )); then
        whiptail --msgbox "No entries selected." 8 40
        return 1
    fi

    mapfile -t selected_paths < <(printf '%s\n' "${selected_paths[@]}" | sort)

    local msg="The following ${#selected_paths[@]} entries will be removed:\n\n"
    msg+="$(ebooks_file_list_preview selected_paths)"

    if whiptail --scrolltext --yesno "$msg" 20 155 --title "Confirm Removal"; then
        local tmp_db list
        tmp_db=$(mktemp) || { whiptail --msgbox "Error creating temporary file." 8 40; return 1; }
        list=$(mktemp) || { rm -f "$tmp_db"; return 1; }
        printf '%s\n' "${selected_paths[@]}" > "$list"
        awk -F'|' 'NR == FNR { rm[$0] = 1; next } !($1 in rm)' "$list" "$EBOOKS_DB" > "$tmp_db"
        mv "$tmp_db" "$EBOOKS_DB"
        rm -f "$list"
        whiptail --msgbox "Entries removed successfully." 8 40
    else
        whiptail --msgbox "Removal cancelled." 8 40
    fi
}

# stdin: db lines. Prints those that carry tag $1 (exact tag match).
ebooks_lines_having_tag() {
    EB_T="$1" awk -F'|' '
    {
        n = split($2, a, ",")
        for (i = 1; i <= n; i++) {
            x = a[i]
            gsub(/^[ \t]+|[ \t]+$/, "", x)
            if (x == ENVIRON["EB_T"]) { print; break }
        }
    }'
}

# Removes tag $1 from every registered file whose path is listed (one per line)
# in file $2.
ebooks_remove_tag_from_paths() {
    local tag="$1" list="$2" tmp
    tmp=$(mktemp) || return 1
    EB_T="$tag" awk -F'|' '
        BEGIN { OFS = "|" }
        NR == FNR { m[$0] = 1; next }
        ($1 in m) {
            n = split($2, a, ",")
            out = ""
            for (i = 1; i <= n; i++) {
                x = a[i]
                gsub(/^[ \t]+|[ \t]+$/, "", x)
                if (x != "" && x != ENVIRON["EB_T"]) out = out (out == "" ? "" : ",") x
            }
            $2 = out
        }
        { print }
    ' "$list" "$EBOOKS_DB" > "$tmp" && mv -- "$tmp" "$EBOOKS_DB"
}

# Asks for a registered tag (paginated). $1 = menu title. Prints the tag.
ebooks_choose_registered_tag() {
    local title="$1" tag
    local -a tags=() sorted=() items=()
    while IFS= read -r tag; do
        [[ -n "$tag" ]] && tags+=("$tag")
    done < "$TAGS_DB"
    if (( ${#tags[@]} == 0 )); then
        whiptail --title "Error" --msgbox "No tags registered. Register at least one tag." 10 70
        return 1
    fi
    mapfile -t sorted < <(printf '%s\n' "${tags[@]}" | sort)
    for tag in "${sorted[@]}"; do
        items+=("$tag" "")
    done
    eb_paginate_tags_menu "$title" "${items[@]}"
}

dissociate_tag_from_checklist() {
    touch "$EBOOKS_DB" "$TAGS_DB"

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local tag_to_remove
    tag_to_remove="$(ebooks_choose_registered_tag "Select Tag to Dissociate")" || return 1

    # the files that carry the chosen tag
    local tmp
    tmp=$(mktemp) || return 1
    ebooks_lines_having_tag "$tag_to_remove" < "$EBOOKS_DB" > "$tmp"
    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        whiptail --msgbox "No eBooks found with tag '$tag_to_remove'." 8 60
        return 1
    fi

    EB_SRC_FILE="$tmp"
    ebooks_filter_reset
    EB_NO_TAGS=0
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1

    local rc=0
    ebooks_pick_files_checklist "Dissociate Tag: ${tag_to_remove}" \
        "Select e-Books to remove the tag '${tag_to_remove}' from." "Proceed to tag dissociation" || rc=1

    EB_SRC_FILE=""
    rm -f "$tmp"
    (( rc != 0 )) && return 1

    local -a selected_paths=()
    local p
    for p in "${!EB_SEL[@]}"; do
        [[ "${EB_SEL["$p"]}" == "1" ]] && selected_paths+=("$p")
    done

    if (( ${#selected_paths[@]} == 0 )); then
        whiptail --msgbox "No entries selected." 8 40
        return 1
    fi

    mapfile -t selected_paths < <(printf '%s\n' "${selected_paths[@]}" | sort)

    local msg="The tag '$tag_to_remove' will be removed from ${#selected_paths[@]} file(s):\n\n"
    msg+="$(ebooks_file_list_preview selected_paths)"

    if ! whiptail --scrolltext --yesno "$msg" 20 155 --title "Confirm Dissociation"; then
        whiptail --msgbox "Cancelled." 8 40
        return 1
    fi

    local list
    list=$(mktemp) || { whiptail --msgbox "Error creating temp file." 8 40; return 1; }
    printf '%s\n' "${selected_paths[@]}" > "$list"
    ebooks_remove_tag_from_paths "$tag_to_remove" "$list"
    rm -f "$list"

    whiptail --msgbox "Tag '$tag_to_remove' dissociated successfully." 8 50
}

associate_tag_from_checklist() {
    touch "$EBOOKS_DB" "$TAGS_DB"

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local -a tags=() sorted=() tag_choices=()
    local tag t
    while IFS= read -r tag; do
        [[ -n "$tag" ]] && tags+=("$tag")
    done < "$TAGS_DB"

    if (( ${#tags[@]} == 0 )); then
        whiptail --msgbox "No tags available in $TAGS_DB." 8 40
        return 1
    fi

    mapfile -t sorted < <(printf '%s\n' "${tags[@]}" | sort)
    for t in "${sorted[@]}"; do
        tag_choices+=("$t" "")
    done

    local selected_tag
    selected_tag="$(eb_paginate_tags_menu "Select Tag to Associate" "${tag_choices[@]}")" || return 1

    EB_SRC_FILE="$EBOOKS_DB"
    EB_NO_TAGS=0
    ebooks_filter_reset
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1

    ebooks_pick_files_checklist "Associate Tag: ${selected_tag}" \
        "Select e-Books to tag." "Proceed to tag association" || return 1

    local -a to_update=()
    local p
    for p in "${!EB_SEL[@]}"; do
        [[ "${EB_SEL["$p"]}" == "1" ]] && to_update+=("$p")
    done

    if (( ${#to_update[@]} == 0 )); then
        whiptail --msgbox "No eBooks selected." 8 40
        return 1
    fi

    mapfile -t to_update < <(printf '%s\n' "${to_update[@]}" | sort)

    local msg="Tag '${selected_tag}' will be added to ${#to_update[@]} file(s) (excluding duplicates):\n\n"
    msg+="$(ebooks_file_list_preview to_update)"

    if ! whiptail --scrolltext --yesno "$msg" 20 155 --title "Confirm Association"; then
        whiptail --msgbox "Operation cancelled." 8 40
        return 1
    fi

    local tmp_db
    tmp_db=$(mktemp) || { whiptail --msgbox "Error creating temp file." 8 40; return 1; }

    local path tags_on_book new_tags
    while IFS='|' read -r path tags_on_book; do
        new_tags="$tags_on_book"
        if [[ "${EB_SEL["$path"]:-0}" == "1" ]]; then
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

assoc_tag_by_filepath() {
    whiptail --title "Help" \
         --msgbox "This function will associate your chosen tag to every file in a directory that you choose. \
You may choose from a list of directories registered in the ebooks db. Use __RECURSIVE__ in the file list to include sub-directories. \
The matching files are listed with their tags before anything is changed." 12 80 >/dev/tty

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local -a tags=() sorted=() tag_menu_items=()
    local tag
    if ! mapfile -t tags < "$TAGS_DB"; then
        whiptail --msgbox "Error: Failed to read tags database." 10 60 >/dev/tty
        return 1
    fi
    if [[ ${#tags[@]} -eq 0 ]]; then
        whiptail --msgbox "No tags found in database. Add tags first." 10 60 >/dev/tty
        return 1
    fi

    mapfile -t sorted < <(printf '%s\n' "${tags[@]}" | sort)
    for tag in "${sorted[@]}"; do
        [[ -n "$tag" ]] && tag_menu_items+=("$tag" "")
    done

    local selected_tag
    selected_tag="$(eb_paginate_tags_menu "Choose a tag to associate:" "${tag_menu_items[@]}")" || return 1

    local selected_dir
    selected_dir="$(ebooks_select_dir "Choose directory to tag:")" || return 1
    [[ -z "$selected_dir" ]] && return

    EB_SRC_FILE="$EBOOKS_DB"
    ebooks_filter_reset
    EB_NO_TAGS=0
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1
    EB_LIST_ONLY=1
    EB_SCOPE_DIR="$selected_dir"
    EB_RECURSIVE=0
    EB_PROCEED="__PROCEED__"
    EB_PROCEED_DESC="Associate tag '${selected_tag}' with all matched files (@N@)"

    local rc=0
    ebooks_pick_file "Associate Tag By File Path" "Files in '${selected_dir}'. Use __RECURSIVE__ to include sub-directories, then select __PROCEED__ to associate '${selected_tag}' with ALL listed files." || rc=$?

    local -a matched=("${EB_FILTERED[@]}")
    local scope_recursive="$EB_RECURSIVE"
    ebooks_filter_reset
    EB_SRC_FILE=""

    (( rc != 2 )) && return 1

    local line to_update=0
    for line in "${matched[@]}"; do
        [[ ",${line#*|}," == *",${selected_tag},"* ]] || (( to_update++ ))
    done

    local scope_txt="this directory only"
    (( scope_recursive == 1 )) && scope_txt="this directory and its sub-directories"
    whiptail --scrolltext --yesno --title "Confirm Association" \
        "Add tag to ALL files in directory?\n\nDirectory: $selected_dir ($scope_txt)\nTag: $selected_tag\nFiles: ${#matched[@]} (${to_update} without the tag yet)" \
        14 155 --yes-button "Associate" --no-button "Cancel" </dev/tty >/dev/tty || return 1

    local list
    list=$(mktemp) || return 1
    printf '%s\n' "${matched[@]%%|*}" > "$list"
    if ! ebooks_add_tag_to_paths "$selected_tag" "$list"; then
        rm -f "$list"
        whiptail --msgbox "Error: Failed to update database." 10 60 >/dev/tty
        return 1
    fi
    rm -f "$list"

    whiptail --msgbox "Successfully updated ${to_update} files with '${selected_tag}' tag." 10 60
}

dissoc_tag_by_filepath() {
    whiptail --title "Help" \
         --msgbox "This function will dissociate your chosen tag from the files in a directory that you choose. \
You may choose from a list of directories registered in the ebooks db. Use __RECURSIVE__ in the file list to include sub-directories. \
The files carrying the tag are listed with their tags before anything is changed. It is inverse of associate tag by filepath function." 12 80 >/dev/tty

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No tags found. Register at least one tag and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local selected_tag
    selected_tag="$(ebooks_choose_registered_tag "Choose a tag to remove:")" || return 1

    local selected_dir
    selected_dir="$(ebooks_select_dir "Choose directory to remove tag from:")" || return 1
    [[ -z "$selected_dir" ]] && return 1  # User canceled

    local tmp
    tmp=$(mktemp) || return 1
    ebooks_lines_having_tag "$selected_tag" < "$EBOOKS_DB" > "$tmp"
    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        whiptail --msgbox "No ebooks with the tag '$selected_tag' found in the database." 10 155 >/dev/tty
        return 1
    fi

    EB_SRC_FILE="$tmp"
    ebooks_filter_reset
    EB_NO_TAGS=0
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_NO_TAG_ITEM=1
    EB_LIST_ONLY=1
    EB_SCOPE_DIR="$selected_dir"
    EB_RECURSIVE=0
    EB_PROCEED="__PROCEED__"
    EB_PROCEED_DESC="Remove tag '${selected_tag}' from all matched files (@N@)"

    local rc=0
    ebooks_pick_file "Dissociate Tag By File Path" "Files in '${selected_dir}' carrying '${selected_tag}'. Use __RECURSIVE__ to include sub-directories, then select __PROCEED__ to remove it from ALL listed files." || rc=$?

    local -a matched=("${EB_FILTERED[@]}")
    local scope_recursive="$EB_RECURSIVE"
    EB_SRC_FILE=""
    rm -f "$tmp"
    ebooks_filter_reset

    (( rc != 2 )) && return 1

    if (( ${#matched[@]} == 0 )); then
        whiptail --msgbox "No files matched. No changes made." 10 60
        return 1
    fi

    local scope_txt="this directory only"
    (( scope_recursive == 1 )) && scope_txt="this directory and its sub-directories"
    whiptail --scrolltext --yesno --title "Confirm Removal" \
        "Remove tag from ALL listed files?\n\nDirectory: $selected_dir ($scope_txt)\nTag: $selected_tag\nFiles: ${#matched[@]}" \
        14 155 --yes-button "Remove" --no-button "Cancel" </dev/tty >/dev/tty || return 1

    local list
    list=$(mktemp) || return 1
    printf '%s\n' "${matched[@]%%|*}" > "$list"
    if ! ebooks_remove_tag_from_paths "$selected_tag" "$list"; then
        rm -f "$list"
        whiptail --msgbox "Error: Failed to update database." 10 60 >/dev/tty
        return 1
    fi
    rm -f "$list"

    whiptail --msgbox "Successfully removed '${selected_tag}' from ${#matched[@]} files." 10 60
}

# Remove registered files from the selected directory. Sub-directories are
# included only after the user selects __RECURSIVE__ in the file-list UI.
ebooks_remove_files_in_path() {
    local selected_dir="$1"

    EB_SRC_FILE="$EBOOKS_DB"
    ebooks_filter_reset
    EB_NO_TAGS=0
    EB_PATH_MAX=110
    EB_TAG_PICK=1
    EB_LIST_ONLY=1
    EB_SCOPE_DIR="$selected_dir"
    EB_RECURSIVE=0
    EB_PROCEED="__PROCEED__"
    EB_PROCEED_DESC="Remove the files without tags among the @N@ matched files"

    local rc=0
    ebooks_pick_file "Files Under ${selected_dir}" \
        "Registered files under '${selected_dir}' with their tags. Use __RECURSIVE__ to include sub-directories; files with tags are never removed." || rc=$?

    local -a matched=("${EB_FILTERED[@]}")
    local scope_recursive="$EB_RECURSIVE"
    ebooks_filter_reset
    EB_SRC_FILE=""

    (( rc != 2 )) && return 1

    local -a files_to_delete=() tagged_files=()
    local line
    for line in "${matched[@]}"; do
        if [[ -z "${line#*|}" ]]; then
            files_to_delete+=("${line%%|*}")
        else
            tagged_files+=("${line%%|*}")
        fi
    done

    if (( ${#files_to_delete[@]} == 0 )); then
        whiptail --title "Information" --msgbox "None of the matched files is without tags. Nothing to remove." 10 100
        return 1
    fi

    local scope_txt="(this directory only)"
    (( scope_recursive == 1 )) && scope_txt="(including sub-directories)"

    local confirm_msg="About to delete ${#files_to_delete[@]} files from '$selected_dir' ${scope_txt}.\n\nFiles with tags will not be deleted."
    if ! whiptail --title "Confirm Deletion" --yesno "$confirm_msg" 15 155; then
        return 1
    fi

    local backup_file="${EBOOKS_DB}.backup"
    cp "$EBOOKS_DB" "$backup_file"

    local list
    list=$(mktemp) || return 1
    printf '%s\n' "${files_to_delete[@]}" > "$list"
    awk -F'|' 'NR == FNR { m[$0] = 1; next } !(($1 in m) && $0 ~ /\|$/)' "$list" "$EBOOKS_DB" > "${EBOOKS_DB}.tmp" && mv "${EBOOKS_DB}.tmp" "$EBOOKS_DB"
    rm -f "$list"

    local deleted_msg="Removed files from ebooks db:\n\n$(ebooks_file_list_preview files_to_delete)"
    whiptail --scrolltext --title "Files Removed" --msgbox "$deleted_msg" 20 155

    if (( ${#tagged_files[@]} > 0 )); then
        local excluded_msg="The following matched files were not deleted because they have tag(s):\n\n$(ebooks_file_list_preview tagged_files)\nPlease dissociate tag(s) from these files first."
        whiptail --scrolltext --title "Tagged Files Excluded" --msgbox "$excluded_msg" 20 155
    fi

    return 0
}

remove_files_by_filepath() {
    whiptail --title "Attention" --msgbox "This function allows you to remove registered files under a selected file path. Use __RECURSIVE__ in the file list to include sub-directories. The files are listed with their tags. If a file has a tag associated with it, it will not be removed. It does not delete files physically from the drive." 12 100 >/dev/tty

    [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
        whiptail --title "Attention" --msgbox "No ebook assets found. Add at least one asset and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    local selected_dir
    selected_dir="$(ebooks_select_dir "Choose a directory to remove files from:")" || return 1
    [[ -n "$selected_dir" ]] || return 1

    ebooks_remove_files_in_path "$selected_dir"
}

# Manage eBooks menu
show_ebooks_menu() {
    local SUBCHOICE FILE_OPTION TAG_OPTION SEARCH_OPTION OPEN_OPTION MAINTENANCE_OPTION

    while true; do
        SUBCHOICE=$(whiptail --title "Manage eBooks" --cancel-button "Back" --menu "Choose an option:" 15 50 6 \
            "1" "File Management" \
            "2" "Tag Management" \
            "3" "Search & Lookup" \
            "4" "Open & Read" \
            "5" "Maintenance" 3>&1 1>&2 2>&3)

        # Exit if user presses Cancel or Esc
        [ $? -ne 0 ] && break

        case "$SUBCHOICE" in
            "1")
                # File Management submenu: Items 1, 3, and 13
                FILE_OPTION=$(whiptail --title "File Management" --cancel-button "Back" --menu "Select an option" 20 50 8 \
                    "1" "Add Files In Bulk" \
                    "2" "Register eBook" \
                    "3" "Register eBooks From Checklist" \
                    "4" "Remove Registered eBook" \
                    "5" "Remove eBooks From Checklist" \
                    "6" "Remove Files In Bulk" \
		    "7" "Remove Files by Filepath" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$FILE_OPTION" in
                    "1") add_files_in_bulk ;;
                    "2") register_ebook ;;
                    "3") add_ebooks_from_checklist ;;
                    "4") remove_registered_ebook ;;
                    "5") remove_ebooks_from_checklist ;;
                    "6") remove_files_in_bulk ;;
		    "7") remove_files_by_filepath ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "2")
                # Tag Management submenu: Items 4, 7, 11, and 12
                TAG_OPTION=$(whiptail --title "Tag Management" --cancel-button "Back" --menu "Select an option" 20 50 10 \
                    "1" "Register Tag" \
                    "2" "Associate Tag with eBook" \
                    "3" "Associate Tag from Checklist" \
                    "4" "Associate Tag to Bulk" \
		    "5" "Associate Tag by Filepath" \
                    "6" "Dissociate Tag from Registered eBook" \
                    "7" "Disociate Tag from Checklist" \
                    "8" "Dissociate Tag from Bulk" \
		    "9" "Dissociate Tag by Filepath" \
                    "10" "Delete Tag From Global List" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$TAG_OPTION" in
                    "1") register_tag ;;
                    "2") associate_tag ;;
                    "3") associate_tag_from_checklist ;;
                    "4") assoc_tag_to_bulk ;;                    
		    "5") assoc_tag_by_filepath ;;
                    "6") dissociate_tag_from_registered_ebook ;;
                    "7") dissociate_tag_from_checklist ;;
                    "8") dissoc_tag_to_bulk ;;
		    "9") dissoc_tag_by_filepath ;;
                    "10") delete_tag_from_global_list ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "3")
                # Search & Lookup submenu: Items 2, 10, 8, and 9
                SEARCH_OPTION=$(whiptail --title "Search & Lookup" --cancel-button "Back" --menu "Select an option" 15 50 3 \
                    "1" "Lookup Registered Files" \
                    "2" "Lookup By Filepath" \
                    "3" "View All Registered Tags" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$SEARCH_OPTION" in
                    "1") lookup_registered_files ;;
                    "2") lookup_by_filepath ;;
                    "3") view_tags ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "4")
                # Open & Read submenu: Open eBook by Search, Open File by File Path
                OPEN_OPTION=$(whiptail --title "Open & Read" --cancel-button "Back" --menu "Select an option" 15 50 2 \
                    "1" "Open eBook by Search" \
                    "2" "Open File by File Path" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$OPEN_OPTION" in
                    "1") open_file_by_search ;;
                    "2") open_file_by_filepath ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            "5")
                # Open & Read submenu: Items 5 and 6
                MAINTENANCE_OPTION=$(whiptail --title "Maintenance" --cancel-button "Back" --menu "Select an option" 15 50 3 \
                    "1" "Find Remove Broken Entries" \
                    "2" "Rename and Reregister Illegal Filenames" \
                    "3" "Revert Renaming Illegal Filenames" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue
                case "$MAINTENANCE_OPTION" in
                    "1") remove_broken_entries ;;
                    "2") rename_and_reregister_illegal_ebook_filenames ;;
                    "3") revert_rename_illegal_ebook_filenames ;;
                    *) whiptail --msgbox "Invalid Option" 8 40 ;;
                esac
                ;;
            *)
                whiptail --msgbox "Invalid Category" 8 40
                ;;
        esac
    done
}

################################ 
# Manage Notes code starts here
################################

#MANAGE NOTES - files and formats
#================================
#
#~/notes/:
#note_title-timestamp.txt
#
#~/notes/metadata/:
#notes.db:
#note_title|note_path|tag1,tag2|ebook_path1#chapter1:5,chapter3:10-15;ebook_path2#chapter1:2
#
#notes-tags.db:
#tag1
#tag2
#...
#
#notes-ebooks.db:
#ebook_path1
#ebook_path2
#...

# Utility function for delete_note().
# Checks if selected note due to be deleted is safe to delete by comparing
# lines in PROJECTS_DB file.
# It is not safe for deletion if match is found in PROJECTS_DB.
note_safe_to_delete() {
    local note_path="$1"
    
    if [[ ! -f "$PROJECTS_DB" ]]; then
        echo "Projects database not found: $PROJECTS_DB" >&2
        return 1
    fi
    
    while IFS='|' read -r _ proj_path notes; do
        IFS=',' read -ra note_array <<< "$notes"
        for project_note in "${note_array[@]}"; do
            if [[ "$project_note" == "$note_path" ]]; then
		echo "$proj_path"
                return 1  # Note is referenced in a project - not safe to delete
            fi
        done
    done < "$PROJECTS_DB"
    
    return 0  # Note is not referenced in any project - safe to delete
}

# This script is not able to deal with file names containing: | , # : ;
# So, if that's the case then stop right there.
illegal_filename() {
  echo "$1" | grep -q '[|,#:;]' && return 1 || return 0
}

# Truncation logic for chapters.
# Output:
# ...,last_chapter:pages
truncate_chapters() {
    local chapters="$1"
    local max_len="$2"
    local prefix="...,"
    local prefix_len=${#prefix}

    # If chapters is empty, just output an empty string.
    if [ -z "$chapters" ]; then
        echo ""
        return
    fi

    # Get the last chapter by taking the substring after the final comma.
    # If no comma is present, consider the entire string as the last chapter.
    local last
    if [[ "$chapters" == *","* ]]; then
        last="${chapters##*,}"
    else
        # If only one chapter is encoded then empty prefix.
        prefix=""
        last="$chapters"
    fi

    # Compose the result with the fixed prefix.
    local result="${prefix}${last}"

    # If the full result is within the allowed length, output it.
    if [ ${#result} -le "$max_len" ]; then
        echo "$result"
        return
    fi

    # Otherwise, calculate the available space for the last chapter.
    local available=$(( max_len - prefix_len ))
    # If the limit is too small even for the prefix, just return a cut-off.
    if [ "$available" -le 0 ]; then
        echo "${result:0:max_len}"
        return
    fi

    # Truncate the last chapter from the left (keeping its end)
    # so that the overall length does not exceed max_len.
    if [ ${#last} -gt "$available" ]; then
        last="${last: -available}"
    fi

    echo "${prefix}${last}"
}

# Need this to truncate menu inside manage ebooks().
generate_trunc_manage_ebooks_menu() {
    # Initialize the result array
    TRUNC_MANAGE_EBOOKS_MENU=()
    
    # Get the input array from arguments
    local input_array=("$@")

    # If input_array is empty return
    [[ ${#input_array[@]} -eq 0 ]] && return 1
    
    local idx=1
    # Process pairs of elements
    for ((i = 0; i < ${#input_array[@]}; i += 2)); do
        local full_path="${input_array[i]}"
        local chapters="${input_array[i+1]}"

        # DEBUG
        #echo "chapters:" >&2
        #echo "$chapters" >&2
        
        # Split path into directory and filename
        local dir_part=$(dirname "$full_path")
        local file_part=$(basename "$full_path")
        
        # Truncate components
        local trunc_dir=$(truncate_dirname "$dir_part")
        local trunc_file=$(truncate_filename "$file_part" 50)
        local truncated_path="${trunc_dir}/${trunc_file}"
        
        # Truncate chapters
        local trunc_chapters=$(truncate_chapters "$chapters" 20)
        
        # DEBUG
        #echo "trunc_chapters:" >&2
        #echo "$trunc_chapters" >&2

        # Add to result array
        TRUNC_MANAGE_EBOOKS_MENU+=("${idx}:${truncated_path}" "$trunc_chapters")
        (( idx++ ))
    done
}

# Need this function to create TRUNC_FILTERED_EBOOKS array
generate_trunc_manage_ebooks() {
    # Initialize the TRUNC_FILTERED_EBOOKS array
    TRUNC_FILTERED_EBOOKS=()

    # If FILTERED_EBOOKS is empty return
    [[ ${#FILTERED_EBOOKS[@]} -eq 0 ]] && return 1

    local idx=1
    # Process each full path from FILTERED_EBOOKS (assuming pairs: fullpath "" ...)
    for ((i=0; i < ${#FILTERED_EBOOKS[@]}; i+=2)); do
        fullpath="${FILTERED_EBOOKS[i]}"

        # Extract the directory and filename parts
        dir=$(dirname "$fullpath")
        file=$(basename "$fullpath")

        # Apply truncation functions to the directory and filename respectively
        truncated_dir=$(truncate_dirname "$dir")
        truncated_file=$(truncate_filename "$file")

        # Reassemble the truncated path
        truncated_path="${truncated_dir}/${truncated_file}"

        # Append the truncated path and an empty string to maintain pair structure
        TRUNC_FILTERED_EBOOKS+=( "${idx}:${truncated_path}" "" )
        (( idx++ ))
    done
}

generate_trunc_manage_ebooks_remove_ebook() {
    # Initialize the TRUNC_FILTERED_EBOOKS_REMOVE array
    TRUNC_FILTERED_EBOOKS_REMOVE=()

    local remove_options=("$@")   # OMG, forgot to enclose in ()!!
    local fullpath dir file truncated_dir truncated_file truncated_path

    # If remove_options is empty return
    [[ ${#remove_options[@]} -eq 0 ]] && return 1

    local idx=1
    # Process each full path from remove_options (assuming pairs: fullpath "" ...)
    for ((i=0; i < ${#remove_options[@]}; i+=2)); do
        fullpath="${remove_options[i]}"

        # DEBUG
        #echo "fullpath:" >&2
        #echo "$fullpath" >&2

        # Extract the directory and filename parts
        dir=$(dirname "$fullpath")
        file=$(basename "$fullpath")

        # Apply truncation functions to the directory and filename respectively
        truncated_dir=$(truncate_dirname "$dir")
        truncated_file=$(truncate_filename "$file" 50)

        # DEBUG
        #echo "dir:" >&2
        #echo "$dir" >&2
        #echo "trunc dir:" >&2
        #echo "$truncated_dir" >&2

        # Reassemble the truncated path
        truncated_path="${truncated_dir}/${truncated_file}"

        # Append the truncated path and an empty string to maintain pair structure
        TRUNC_FILTERED_EBOOKS_REMOVE+=( "${idx}:${truncated_path}" "" )
        (( idx++ ))
    done
}

# Global array to store filtered entries.
declare -a FILTERED_EBOOKS

CURRENT_PAGE=0   # persists page state across paginate_n() calls

paginate_n() {
    # Clear any previous selection
    SELECTED_ITEM=""

    local chunk_size=200

    # If new items are passed in, update TRUNC and reset CURRENT_PAGE.
    if [ "$#" -gt 0 ]; then
        FILTERED_EBOOKS=("$@")
        CURRENT_PAGE=0
    fi

    [[ ${#FILTERED_EBOOKS[@]} -eq 0 ]] && return 1

    local total_pages=$(( ( ${#FILTERED_EBOOKS[@]} + chunk_size - 1 ) / chunk_size ))
    # Ensure CURRENT_PAGE is within valid bounds
    if (( CURRENT_PAGE >= total_pages )); then
        CURRENT_PAGE=$(( total_pages - 1 ))
    fi

    # populate TRUNC_FILTERED_EBOOKS from FILTERED_EBOOKS
    generate_trunc_manage_ebooks

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        # Extract the current chunk from the global TRUNC
        #local current_chunk=("${FILTERED_EBOOKS[@]:$start:$chunk_size}")
        local current_chunk=("${TRUNC_FILTERED_EBOOKS[@]:$start:$chunk_size}")
        local menu_options=()

        # Add navigation options if needed
        if (( CURRENT_PAGE > 0 )); then
            menu_options+=("previous page" "")
        fi
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("next page" "")
        fi

        # Append the current page items
        menu_options+=("${current_chunk[@]}")

        choice=$(whiptail --title "Paged Menu" --cancel-button "Back" \
            --menu "Choose an item (Page $((CURRENT_PAGE + 1))/$total_pages)" \
            20 155 10 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        # Exit if user cancels
        if [ $? -ne 0 ]; then
            break
        fi

        case "$choice" in
            "previous page")
                (( CURRENT_PAGE-- ))
                ;;
            "next page")
                (( CURRENT_PAGE++ ))
                ;;
            *)
                # Return the selected item (page state remains for next call)
                local n="$(echo "$choice" | cut -d':' -f1)"
                local m=$((2 * n - 1))

                SELECTED_ITEM="${FILTERED_EBOOKS[$((m - 1))]}"
                ! illegal_filename "$SELECTED_ITEM" && SELECTED_ITEM="" && return 2
                return 0
                ;;
        esac
    done

    return 1
}

# Modified: Filter by both tag and file name.
filter_by_filename() {
    paginate_tags_menu() {
        local title="$1"
        shift
        local items=("$@")
        local per_page=20
        local total_items=$(( ${#items[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local current_page=1
        local choice start_index end_index menu_items tag desc

        while true; do
            # Calculate start and end indices for current page
            start_index=$(( (current_page - 1) * per_page * 2 ))
            end_index=$(( start_index + per_page * 2 ))
            menu_items=()

            # Add items for current page
            for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                tag="${items[i]}"
                desc="${items[i+1]}"
                menu_items+=("$tag" "$desc")
            done

            # Add navigation options
            if (( current_page > 1 )); then
                menu_items+=("<< Prev" "")
            fi
            if (( current_page < total_pages )); then
                menu_items+=(">> Next" "")
            fi

            # Show whiptail menu
            choice=$(whiptail --title "$title" \
                --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            [[ $? -ne 0 ]] && return 1  # Cancel pressed

            case "$choice" in
                ">> Next")
                    (( current_page++ ))
                    ;;
                "<< Prev")
                    (( current_page-- ))
                    ;;
                *)
                    # Return selected tag
                    printf '%s\n' "$choice"
                    return 0
                    ;;
            esac
        done
    }

  [[ ! -f "$EBOOKS_DB" || ! -s "$EBOOKS_DB" ]] && {
    whiptail --title "Ebook Database" --msgbox "Ebooks database not found or empty. Register at least one ebook." 10 60 >/dev/tty
    return 1
  }
 
# When filtering by file name, we don't strictly need a tag associated with. 
#  [[ ! -f "$TAGS_DB" || ! -s "$TAGS_DB" ]] && {
#    whiptail --title "Ebook Database" --msgbox "Tags database not found or empty. Register at least one ebook tag ." 10 60 >/dev/tty
#    return 1
#  }

  # Read available tags from TAGS_DB
  local tags=()
#   if [ -f "$TAGS_DB" ]; then
#     while IFS= read -r tag; do
#       tags+=("$tag")
#     done < "$TAGS_DB"
#   fi
  if [[ -f "$TAGS_DB" ]]; then
    mapfile -t tags < <(sort "$TAGS_DB")
  fi

  # Prepare tag options for whiptail menu, starting with "ANY TAG"
  local tag_options=("ANY TAG" "Any tag (no filter)")
  for tag in "${tags[@]}"; do
    tag_options+=("$tag" "")
  done

#   # Present tag selection menu
#   local selected_tag
#   selected_tag=$(whiptail --title "Select Tag to Filter" --menu "Choose a tag to filter by (or select ANY TAG):" 20 150 10 "${tag_options[@]}" 3>&1 1>&2 2>&3 </dev/tty)
#   if [ $? -ne 0 ]; then
#     return 1
#   fi

  # FIX: PAGINATE TAG SELECTION.
  local selected_tag
  selected_tag="$(paginate_tags_menu "Select eBook Tag to Filter" "${tag_options[@]}")" || return 1

  # Prompt for search term
  local search_term
  search_term=$(whiptail --inputbox "Enter search term for ebook file name (globbing; empty is wildcard):" 8 60 --title "Filter Ebooks" 3>&1 1>&2 2>&3 </dev/tty)
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  : ${search_term:=*}

  # Clear the global array
  FILTERED_EBOOKS=()

  # Check EBOOKS_DB existence
  if [ ! -f "$EBOOKS_DB" ]; then
    echo "EBOOKS_DB file not found: $EBOOKS_DB" >&2
    return 1
  fi

  in_operation_msg

  # Process each line in EBOOKS_DB and populate $FILTERED_EBOOKS
  # where the items are in pairs: ($filepath, "")
mapfile -t FILTERED_EBOOKS < <(
  awk -F'\\|' \
      -v tag="$selected_tag" \
      -v glob="$search_term" '
    # Convert shell glob → regex (case-insensitive)
    function glob_to_regex(g, r, i, c) {
      r = "^"
      for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*")        r = r ".*"
        else if (c == "?")   r = r "."
        else if (c == ".")   r = r "\\."
        else if (c == "[")   r = r "["
        else if (c == "]")   r = r "]"
        else if (c == "\\")  r = r "\\\\"
        else                 r = r c
      }
      return r "$"
    }

    BEGIN {
      IGNORECASE = 1   # case-insensitive filename and glob match
      if (length(glob) > 0)
        regex = glob_to_regex(glob)
      else
        regex = ""     # no filename filter
    }

    {
      filepath = $1
      tags     = $2

      # --- Tag filter ---
      if (tag != "ANY TAG") {
        tags2 = "," tags ","
        pat   = "," tag ","
        if (index(tags2, pat) == 0) next
      }

      # --- Filename filter ---
      if (regex != "") {
        n = split(filepath, arr, "/")
        filename = arr[n]

        if (filename !~ regex)
          next
      }

      print filepath
      print ""
    }
  ' "$EBOOKS_DB"
)

  # Show result count
  whiptail --msgbox "Found $(( ${#FILTERED_EBOOKS[@]} / 2 )) matching entries." 8 60 --title "Filter Results" >/dev/tty
}

# Global variables used by add_note and its helpers.
note_title=""
note_path=""
current_tags=()
ebook_entries=()

# FIX: implemented pagination.
manage_tags() {
    local current_page=0
    local tags_per_page=20  # Showing 8 tags per page to leave space for navigation items

    while true; do
        # Read existing tags
        local -a tags=()
        if [ -f "$NOTES_TAGS_DB" ]; then
            mapfile -t tags < "$NOTES_TAGS_DB"
        fi

        # Calculate total pages
        local total_pages=$(( (${#tags[@]} + tags_per_page - 1) / tags_per_page ))
        
        # Get tags for current page
        local start_index=$((current_page * tags_per_page))
        local end_index=$((start_index + tags_per_page - 1))
        local -a page_tags=("${tags[@]:$start_index:$tags_per_page}")

        # Prepare menu options
        local menu_options=()
        
        # Add tags for current page
        for tag in "${page_tags[@]}"; do
	    # LOGIC ERROR: matches subword too.
            #if [[ " ${current_tags[@]} " =~ " ${tag} " ]]; then
            #    menu_options+=("$tag" "[X]")

	    local sep=$'\x1F'  # ASCII Unit Separator, unlikely to appear in real tags
	    local joined="$sep$(IFS="$sep"; echo "${current_tags[*]}")$sep"
	    if [[ "$joined" == *"${sep}${tag}${sep}"* ]]; then
		menu_options+=("$tag" "[X]")
            else
                menu_options+=("$tag" "[ ]")
            fi
        done

        # Add navigation items if needed
        if [ $total_pages -gt 1 ]; then
            if [ $current_page -gt 0 ]; then
                menu_options+=("<< Previous Page" "")
            fi
            
            #menu_options+=("Add new tag" "")
            
            if [ $current_page -lt $((total_pages - 1)) ]; then
                menu_options+=(">> Next Page" "")
            fi

	    # changed order.
	    menu_options+=("Add new tag" "")
        else
            menu_options+=("Add new tag" "")
        fi

        # truncate $current_tags first
        local current_tags_tr tr_menu_str
        current_tags_tr="$(IFS=','; echo "${current_tags[*]}")"
        (( ${#current_tags[@]} > 1 )) && tr_menu_str="${current_tags_tr:0:37}..." || tr_menu_str="${current_tags_tr[*]:0:40}"

        local selection
        selection=$(whiptail --title "Manage Tags (Page $((current_page + 1))/$total_pages)" \
            --cancel-button "Back" --menu "Current tags: $tr_menu_str" 20 60 10 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        [ $? -eq 0 ] || return

        case "$selection" in
            "Add new tag")
                local new_tag
                new_tag=$(whiptail --inputbox "Enter new tag:" 8 40 3>&1 1>&2 2>&3 </dev/tty)
                [ $? -eq 0 ] || continue

                # get rid of spaces before and after
                # xargs method replaces all multiple spaces into just a single space whereever found
                new_tag="$(echo "$new_tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

                # ANY TAG and NO TAG are banned words
                [[ "$new_tag" == "ANY TAG" || "$new_tag" == "NO TAG" ]] && whiptail --title "Invalid Tag" --msgbox "'${new_tag}' is not allowed as a tag name." 8 40 && continue

                # FIX: DELETE BANNED CHARS - MORE EFFICIENT.
                new_tag=${new_tag//[|,#:;]/}
                #new_tag=${new_tag//[|,#;]/}
                #new_tag=$(echo "$new_tag" | tr -d '|,')
                # END FIX.

                if [ -n "$new_tag" ]; then
#                    # Add to global tags list
#                    echo "$new_tag" >> "$NOTES_TAGS_DB"
#                    current_tags+=("$new_tag")
#                    # Reset to first page after adding a new tag
#                    current_page=0

    		    # FIX: CHECK FOR DUPLICATE BEFORE ADDING TAG.
                    # Check if tag already exists
                    if grep -qFx "$new_tag" "$NOTES_TAGS_DB"; then
                        whiptail --msgbox "Tag '${new_tag}' already exists!" 8 40
                    else
                        # Add to global tags list
                        echo "$new_tag" >> "$NOTES_TAGS_DB"
                        current_tags+=("$new_tag")
                        # Reset to first page after adding a new tag
                        current_page=0
                    fi
                fi
                ;;
            "<< Previous Page")
                ((current_page--))
                continue
                ;;
            ">> Next Page")
                ((current_page++))
                continue
                ;;
            *)
                # Toggle tag selection
		# LOGIC ERROR: matches subword too.
                #if [[ " ${current_tags[@]} " =~ " ${selection} " ]]; then
		
		local sep=$'\x1F'  # ASCII Unit Separator, unlikely to appear in real tags
		local joined="$sep$(IFS="$sep"; echo "${current_tags[*]}")$sep"
		if [[ "$joined" == *"${sep}${selection}${sep}"* ]]; then
                    if whiptail --yesno "Remove tag '${selection}'?" 8 40 </dev/tty >/dev/tty; then
                        local new_tags=()
                        for tag in "${current_tags[@]}"; do
                            [[ "$tag" != "$selection" ]] && new_tags+=("$tag")
                        done
                        current_tags=("${new_tags[@]}")
                    fi
                else
                    if whiptail --yesno "Add tag '${selection}'?" 8 40 </dev/tty >/dev/tty; then
                        current_tags+=("$selection")
                    fi
                fi
                ;;
        esac
    done
}

# DEPRECATED.
manage_tags_old() {
    while true; do
        # Read existing tags
        local -a tags=()
        if [ -f "$NOTES_TAGS_DB" ]; then
            mapfile -t tags < "$NOTES_TAGS_DB"
        fi

        # Prepare menu options
        local menu_options=()
        for tag in "${tags[@]}"; do
            if [[ " ${current_tags[@]} " =~ " ${tag} " ]]; then
                menu_options+=("$tag" "[X]")
            else
                menu_options+=("$tag" "[ ]")
            fi
        done
        menu_options+=("Add new tag" "")
        #menu_options+=("Back" "Return to previous menu")

        local selection
        selection=$(whiptail --title "Manage Tags" --cancel-button "Back" --menu "Current tags: ${current_tags[*]}" 20 60 10 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        [ $? -eq 0 ] || return

        case "$selection" in
            "Add new tag")
                local new_tag
                new_tag=$(whiptail --inputbox "Enter new tag:" 8 40 3>&1 1>&2 2>&3 </dev/tty)
                [ $? -eq 0 ] || continue
                new_tag=$(echo "$new_tag" | tr -d '|,')
                if [ -n "$new_tag" ]; then
                    # Add to global tags list
                    echo "$new_tag" >> "$NOTES_TAGS_DB"
                    current_tags+=("$new_tag")
                fi
                ;;
            #"Back")
            #    return
            #    ;;
            *)
                # Toggle tag selection
                if [[ " ${current_tags[@]} " =~ " ${selection} " ]]; then
                    if whiptail --yesno "Remove tag '${selection}'?" 8 40 </dev/tty >/dev/tty; then
                        local new_tags=()
                        for tag in "${current_tags[@]}"; do
                            [[ "$tag" != "$selection" ]] && new_tags+=("$tag")
                        done
                        current_tags=("${new_tags[@]}")
                    fi
                else
                    if whiptail --yesno "Add tag '${selection}'?" 8 40 </dev/tty >/dev/tty; then
                        current_tags+=("$selection")
                    fi
                fi
                ;;
        esac
    done
}

# Verify pages string (for an ebook).
verify_pages_str() {
    local pages="$1"
    
    # Check for single page (e.g. "5")
    if [[ "$pages" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    
    # Check for page range (e.g. "5-10")
    if [[ "$pages" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        
        # Verify that the ending page is greater than the starting page
        if (( end > start )); then
            return 0
        fi
    fi

    # Return non-zero for invalid string
    return 1
}

# UI to construct CHAPTER_PAGES string.
add_chapters() {
    # Reset global
    CHAPTER_PAGES=""
    declare -a chapters=()

    # If need to prefill chapters.
    local current_chapters="$1"

    # Prefill chapters array if current_chapters is given as $1.
    if [[ -n "$current_chapters" ]]; then
        # Split current_chapters by comma and populate the chapters array.
        IFS=',' read -ra chapters <<< "$current_chapters"
    fi   

    local chapter_name chapter_pages new_entry
    local choice index chapter_entry old_name old_pages new_pages
    local num_chapters

    while true; do
        num_chapters=${#chapters[@]}
        #add_choice=$((num_chapters + 1))
        #save_choice=$((num_chapters + 2))
        
        # Build menu with chapters first, then static options
        menu_options=()
        for ((index=0; index<num_chapters; index++)); do
            menu_options+=("$((index+1))" "${chapters[index]}")
        done
        menu_options+=("Add chapter" "")
        menu_options+=("Save and return" "")

	# If added lot of chapters menu gets broken so increase dimensions!
        choice=$(whiptail --title "Chapter Management" --cancel-button "Back" --menu "Choose an option:" \
            22 150 15 "${menu_options[@]}" 3>&1 1>&2 2>&3)
        
        [[ $? -ne 0 ]] && choice="Save and return"  # Handle ESC/Cancel as Save
        
        if [[ "$choice" == "Add chapter" ]]; then
            # Add new chapter
            while true; do
                chapter_name=$(whiptail --inputbox "Enter chapter name:" 8 40 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && break

		# FIX
		# Check for illegal chapter name
		if [[ "$chapter_name" =~ [\;\|#,:] ]]; then
			whiptail --title "Attention" --msgbox "Chapter name cannot contain illegal characters (|#,:;)." 8 60
    			continue
		fi
		# END FIX.
                
                chapter_pages=$(whiptail --inputbox "Enter pages for '$chapter_name' (eg. 1 or 1-10):" \
                    8 40 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue

                # Check for syntax page1 or page1-page2 here.
                # Check for:
                # If pages a-b, b must be > a.
                # ^[0-9]+-[0-9]+$ or ^[0-9]+$.
                if ! verify_pages_str "$chapter_pages"; then
                    whiptail --title "Error" --msgbox "Invalid pages syntax." 8 40
                    continue
                fi
                
                # Remember that we can have same chapter name but different pages.
                new_entry="$chapter_name:$chapter_pages"
                if [[ " ${chapters[*]} " =~ " $new_entry " ]]; then
                    whiptail --msgbox "Duplicate entry: $new_entry" 8 40
                else
                    chapters+=("$new_entry")
                    break
                fi
            done

        elif [[ "$choice" == "Save and return" ]]; then
            # Save and exit
            CHAPTER_PAGES=$(IFS=','; echo "${chapters[*]}")
            return 0

        elif [[ $choice -le $num_chapters ]]; then
            # Chapter selected - show edit/delete menu
            index=$((choice - 1))
            chapter_entry="${chapters[index]}"
            old_name="${chapter_entry%%:*}"
            old_pages="${chapter_entry#*:}"
            
            action=$(whiptail --menu "Chapter: $chapter_entry" 15 50 5 \
                "Edit pages" "" \
                "Delete chapter" "" \
                3>&1 1>&2 2>&3)
            
            if [[ $? -eq 0 ]]; then
                case $action in
                    "Edit pages")  # Edit pages
                        while true; do
                            new_pages=$(whiptail --inputbox "New pages for '$old_name' (eg. 1 or 1-10):" \
                                8 40 "$old_pages" 3>&1 1>&2 2>&3)
                            [[ $? -ne 0 ]] && break

                            # Check for pages syntax here.
                            if ! verify_pages_str "$new_pages"; then
                                whiptail --title "Error" --msgbox "Invalid pages syntax." 8 40
                                continue
                            fi
                            
                            new_entry="$old_name:$new_pages"
                            if [[ " ${chapters[*]} " =~ " $new_entry " ]]; then
                                whiptail --msgbox "No change." 8 40
                                break
                            else
                                chapters[index]="$new_entry"
                                break
                            fi
                        done
                        ;;
                    "Delete chapter")  # Delete chapter
                        unset 'chapters[index]'
                        chapters=("${chapters[@]}")  # Re-index array
                        ;;
                esac
            fi
        fi
    done
}

paginate_n_checklist() {
    # Initialize global array
    SELECTED_ITEMS=()
    # Temporary associative array to track indices (requires Bash 4+)
    declare -A SELECTED_INDICES 

    local chunk_size=50

    if [ "$#" -gt 0 ]; then
        FILTERED_EBOOKS=("$@")
        CURRENT_PAGE=0
    fi

    [[ ${#FILTERED_EBOOKS[@]} -eq 0 ]] && return 1

    local total_pages=$(( ( ${#FILTERED_EBOOKS[@]} + chunk_size - 1 ) / chunk_size ))
    
    # Ensure CURRENT_PAGE is within valid bounds
    if (( CURRENT_PAGE >= total_pages )); then
        CURRENT_PAGE=$(( total_pages - 1 ))
    elif (( CURRENT_PAGE < 0 )); then
        CURRENT_PAGE=0
    fi

    generate_trunc_manage_ebooks

    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        local current_chunk=("${TRUNC_FILTERED_EBOOKS[@]:$start:$chunk_size}")
        local menu_options=()

        # 1. Add Navigation and Action items
        # Format: Tag, Item, Status
        
        # --- Conditional Navigation Items ---
        if (( CURRENT_PAGE > 0 )); then
            menu_options+=("PREV" "" "OFF")
        fi        
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("NEXT" "" "OFF")
        fi

        # ADD item
        menu_options+=("ADD"  "" "OFF")

        # 2. Append the current page items with their current selection state
        for (( i=0; i<${#current_chunk[@]}; i+=2 )); do
            local tag="${current_chunk[$i]}"
            local desc="${current_chunk[$i+1]}"
            
            # Determine if this item is already selected
            local status="OFF"
            [[ -n "${SELECTED_INDICES[$tag]}" ]] && status="ON"
            
            menu_options+=("$tag" "$desc" "$status")
        done

        # 3. Display Checklist
        local choices
        choices=$(whiptail --title "Ebook asset files to add" \
            --separate-output \
            --checklist "Select items (Page $((CURRENT_PAGE + 1))/$total_pages)" \
            25 155 15 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3)

        # Exit if user cancels (Back/ESC)
        if [ $? -ne 0 ]; then
            return 1
        fi

        # 4. Process Selections
        # First, clear current page selections from the tracker so we can re-sync
        for (( i=0; i<${#current_chunk[@]}; i+=2 )); do
            unset SELECTED_INDICES["${current_chunk[$i]}"]
        done

        local nav_next=false
        local nav_prev=false
        local action_add=false

        # Read choices line by line
        while read -r line; do
            case "$line" in
                "PREV") nav_prev=true ;;
                "NEXT") nav_next=true ;;
                "ADD")  action_add=true ;;
                *)      
                    SELECTED_INDICES["$line"]=1 # update selections from every page.
                    ;;
            esac
        done <<< "$choices" # from every page

        # 5. Validation Logic
        if $action_add && ( $nav_next || $nav_prev ); then
            whiptail --msgbox "You cannot select navigation items and 'Add' at the same time." 8 60
            continue
        fi

        if $nav_next && $nav_prev; then
            whiptail --msgbox "You cannot select both Next and Previous page simultaneously." 8 60
            continue
        fi

        local line_count
        line_count=$(grep -c '^' <<< "$choices")

        if (( line_count < 2 )) && $action_add; then
            whiptail --msgbox "Select at least one asset file before adding." 8 60
            continue
        fi

        # 6. Navigation / Finalization Execution
        if $action_add; then
            # Convert indices back to original paths in FILTERED_EBOOKS
            for idx_tag in "${!SELECTED_INDICES[@]}"; do
                # Extract numeric index 'n' from 'n:path'
                local n="$(echo "$idx_tag" | cut -d':' -f1)"
                local m=$((2 * n - 1))
                local item="${FILTERED_EBOOKS[$((m - 1))]}"
                
                # Check for illegal ebook name
                if illegal_filename "$item"; then
                    SELECTED_ITEMS+=("$item")
                else
                    return 2
                fi
            done
            return 0
        elif $nav_prev; then
            if (( CURRENT_PAGE > 0 )); then
                (( CURRENT_PAGE-- ))
            else
                #whiptail --msgbox "You are already on the first page." 8 40
                :
            fi
        elif $nav_next; then
            if (( CURRENT_PAGE < total_pages - 1 )); then
                (( CURRENT_PAGE++ ))
            else
                #whiptail --msgbox "You are already on the last page." 8 40
                :
            fi
        fi
    done
}

# DEBUG
#add_chapters
#echo CHAPTER_PAGES: >&2
#echo "$CHAPTER_PAGES" >&2
#exit

manage_ebooks() {
    # Load existing ebooks into ebook_entries if desired (remove if starting fresh)
    # If you want to edit existing entries, uncomment the following lines:
    # if [ -f "$NOTES_EBOOKS_DB" ]; then
    #     while IFS= read -r line; do
    #         [[ -n "$line" ]] && ebook_entries+=("$line")
    #     done < "$NOTES_EBOOKS_DB"
    # fi

    while true; do
        # Prepare menu options from ebook_entries
        local menu_options=()
        for entry in "${ebook_entries[@]}"; do
            ebook=$(cut -d# -f1 <<< "$entry")
            chapters=$(cut -d# -f2- <<< "$entry")
            menu_options+=("$ebook" "$chapters")
        done

        # Generate TRUNC_MANAGE_EBOOKS_MENU
        generate_trunc_manage_ebooks_menu "${menu_options[@]}"

        TRUNC_MANAGE_EBOOKS_MENU+=("Add new ebook" "")
        [ ${#ebook_entries[@]} -gt 0 ] && TRUNC_MANAGE_EBOOKS_MENU+=("Remove ebook" "")
        TRUNC_MANAGE_EBOOKS_MENU+=("Back" "Return to previous menu")

        local selection_trunc
        selection_trunc=$(whiptail --title "Manage Ebooks" --cancel-button "Back" --menu "Manage ebook associations" 20 155 10 \
            "${TRUNC_MANAGE_EBOOKS_MENU[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
        [ $? -eq 0 ] || break

        # Get selection from TRUNC_MANAGE_EBOOKS_MENU
        local n m selection

        # Account for when selection_trunc is "Add new ebook" or "Remove ebook" or "Back"
        if [[ "$selection_trunc" != "Add new ebook" && "$selection_trunc" != "Remove ebook" && "$selection_trunc" != "Back" ]]; then
            n="$(echo "$selection_trunc" | cut -d':' -f1)"
            m=$((2 * n - 1))
            selection="${menu_options[$((m - 1))]}"
        else
            selection="$selection_trunc"
        fi

        case "$selection" in
            "Add new ebook")
                local new_ebooks=()
                CURRENT_PAGE=0
                SELECTED_ITEMS=""

                ! filter_by_filename && continue

                paginate_n_checklist

                # Illegal file name
                [[ $? -eq 2 ]] && {
                    whiptail --title "Error" --msgbox "Some file names are illegal.  Contains | , # : ;. Rename file and try again." 10 60
                    return 1
                }

                new_ebooks=("${SELECTED_ITEMS[@]}")

                if (( ${#new_ebooks[@]} == 0 )); then
                    whiptail --msgbox "No ebook selected. Operation cancelled." 8 60 >/dev/tty
                    continue
                fi

                # Iterate through each newly selected ebook
                for new_ebook in "${new_ebooks[@]}"; do
                    local exists=0
                    
                    # Check if this specific ebook already exists in ebook_entries
                    for entry in "${ebook_entries[@]}"; do
                        # Matches the ebook name followed by the # delimiter
                        if [[ "$entry" == "${new_ebook}#"* ]]; then
                            exists=1
                            break
                        fi
                    done

                    if [[ $exists -eq 1 ]]; then
                        # Optional: Notify user, or simply skip to keep the UI clean
                        :
                    else
                        # If unique, add it to the ebook_entries array with the # suffix
                        local chapters=""
                        ebook_entries+=("${new_ebook}#${chapters}")
                    fi
                done
                (( $exists )) && whiptail --msgbox "Some ebook files were skipped because they are already registered." 8 60 >/dev/tty
                ;;

            "Remove ebook")
                # DEBUG
                #echo Remove ebook: >&2
                #echo ebook_entries: >&2
                #declare -p ebook_entries >&2

                local remove_options=()
                for entry in "${ebook_entries[@]}"; do
                    remove_options+=("$(cut -d# -f1 <<< "$entry")" "")
                done

                # DEBUG
                #echo Remove ebook: >&2
                #echo remove_options: >&2
                #declare -p remove_options >&2

                # Truncate remove_options
                generate_trunc_manage_ebooks_remove_ebook "${remove_options[@]}"

                local to_remove to_remove_tr
                to_remove_tr=$(whiptail --title "Remove Ebook" --menu "Select ebook to remove:" \
                    20 155 10 "${TRUNC_FILTERED_EBOOKS_REMOVE[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
                [ $? -eq 0 ] || continue

                local n m
                n="$(echo "$to_remove_tr" | cut -d':' -f1)"
                m=$((2 * n - 1))
                to_remove="${remove_options[$((m - 1))]}"

                local new_entries=()
                for entry in "${ebook_entries[@]}"; do
                    [[ "$entry" != "${to_remove}#"* ]] && new_entries+=("$entry")
                done
                ebook_entries=("${new_entries[@]}")
                ;;

            "Back")
                return
                ;;

            *)
                # Edit existing entry
                local current_chapters=""
                for idx in "${!ebook_entries[@]}"; do
                    if [[ "${ebook_entries[idx]}" == "${selection}#"* ]]; then
                        current_chapters=$(cut -d# -f2- <<< "${ebook_entries[idx]}")
                        break
                    fi
                done

                #local new_chapters
                #new_chapters=$(whiptail --inputbox "Edit chapter:page pairs for ${selection}:" 12 60 \
                #    "$current_chapters" 3>&1 1>&2 2>&3 </dev/tty)
                #[ $? -eq 0 ] || continue

                # Get CHAPTER_PAGES
                # Prefilled
                add_chapters "$current_chapters"
                #if [[ -z "$CHAPTER_PAGES" ]]; then
                #    whiptail --title "Error" --msgbox "No chapter pages specified." 8 40
                #    continue
                #fi
                local new_chapters="$CHAPTER_PAGES"

                # Update the entry in ebook_entries
                for idx in "${!ebook_entries[@]}"; do
                    if [[ "${ebook_entries[idx]}" == "${selection}#"* ]]; then
                        ebook_entries[idx]="${selection}#${new_chapters}"
                        break
                    fi
                done
                ;;
        esac
    done
}

save_note() {
    # DEBUG
    #echo note title: >&2
    #echo "$note_title" >&2

    # Check that note_title and note_path are set; if not, do not save
    if [[ -z "$note_title" ]]; then
        whiptail --title "Error" --msgbox "Note title can't be empty!" 8 50 >/dev/tty
        return 1
    fi

    local timestamp
    timestamp=$(date "+%d%m%Y-%H%M%S") # Change format to day-month-year-hour-second.
    local sanitized_title
    sanitized_title=$(tr -cd '[:alnum:]-_ ' <<< "$note_title" | tr ' ' '_')
    note_path="${NOTES_PATH}/${sanitized_title}-${timestamp}.txt"
    touch "$note_path" || return 1

    # Prepare metadata
    local tags_str
    tags_str=$(IFS=','; echo "${current_tags[*]}")
    local ebooks_str
    ebooks_str=$(IFS=';'; echo "${ebook_entries[*]}")

    # Copy over current_tags and ebooks_entries to files
    for tg in "${current_tags[@]}"; do
        echo "$tg" >> "$NOTES_TAGS_DB"
    done

    for eb in "${ebook_entries[@]}"; do
        echo "${eb%#*}" >> "$NOTES_EBOOKS_DB"
    done

    # Update databases
    echo "${note_title}|${note_path}|${tags_str}|${ebooks_str}" >> "$NOTES_DB"
    sort -u "$NOTES_TAGS_DB" -o "$NOTES_TAGS_DB"
    sort -u "$NOTES_EBOOKS_DB" -o "$NOTES_EBOOKS_DB"

    whiptail --msgbox "Note created successfully:\n${note_path}" 10 60 >/dev/tty
}

add_note() {
    # Reinitialize globals for a new note.
    note_title=""
    note_path=""
    current_tags=()
    ebook_entries=()
    local choice

    # Add note with same tag functionality requires this.
    if [[ -n "$1" ]]; then
        current_tags+=("$1")
    fi

    # Main loop
    while true; do
        # Truncate Note Title.
        local note_title_tr tr_max
        tr_max=25

        if [ -n "$note_title" ]; then
            if [ ${#note_title} -gt $(($tr_max + 3)) ]; then
                note_title_tr="${note_title:0:$tr_max}..."
            else
                note_title_tr="$note_title"
            fi
        fi

        local path_status="(will be generated)"
        [ -n "$note_title" ] && {
            local dirname_tr filename_tr

            dirname_tr="$(truncate_dirname "$NOTES_PATH")"
            filename_tr="$note_title_tr"

            #path_status="${NOTES_PATH}/${note_title}-*.txt"
            path_status="${dirname_tr}/${filename_tr}-*.txt"
        }

        local tag_status="none"
        [ ${#current_tags[@]} -gt 0 ] && tag_status="${#current_tags[@]} tags"

        local ebook_status="none"
        [ ${#ebook_entries[@]} -gt 0 ] && ebook_status="${#ebook_entries[@]} ebooks"

        choice=$(whiptail --title "Create New Note" --menu "Configure note properties" 20 100 8 \
            "Note Title"    "Current: ${note_title_tr:-<not set>}" \
            "Note Path"     "Status: ${path_status}" \
            "Tags"          "Status: ${tag_status}" \
            "Ebooks"        "Status: ${ebook_status}" \
            "Save and Edit" "Save note and open in editor" \
            "Save and Return" "Save note and exit" 3>&1 1>&2 2>&3)
        [ $? -eq 0 ] || break

        case "$choice" in
            "Note Title")
		local old_note_title		# FIX: CHECK FOR ILLEGAL CHARS.
		old_note_title="$note_title"

                note_title=$(whiptail --inputbox "Enter note title:" 8 40 "$note_title" 3>&1 1>&2 2>&3)
		# FIX: CHECK FOR ILLEGAL CHARS.
                if [[ "$note_title" =~ [\|#] ]]; then
			note_title="$old_note_title"	# Revert
                        whiptail --title "Attention" --msgbox "Note title cannot contain illegal characters (|#)." 8 60
                        continue
                fi
		# END FIX.

                [ -z "$note_title" ] && note_title_tr=""
                ;;
            "Tags")
                manage_tags
                ;;
            "Ebooks")
                manage_ebooks
                ;;
            "Save and Edit")
                save_note || return 1
                #nano "$note_path"
		        #"$DEFAULT_EDITOR" "$note_path"
                eval "${VIEWER_COMMANDS[$DEFAULT_EDITOR]}" "$note_path"
                break
                ;;
            "Save and Return")
                save_note || return 1
                break
                ;;
        esac
    done
}

# Helper function to load existing note data
load_note_data() {
    # note_path is global.
    #note_path="$1"

    # Reset globals
    note_title=""
    current_tags=()
    ebook_entries=()

    # Find the line in NOTES_DB
    local line
    line=$(grep -F "|${note_path}|" "$NOTES_DB")
    if [ -z "$line" ]; then
        echo "Note not found in database: $note_path" >&2
        return 1
    fi

    # Split into fields
    IFS='|' read -r note_title _note_path tags_str ebooks_str <<< "$line"

    # Ensure note_path is correct
    [[ "$note_path" != "$_note_path" ]] && return 1

    # Split tags and ebooks
    IFS=',' read -ra current_tags <<< "$tags_str"
    IFS=';' read -ra ebook_entries <<< "$ebooks_str"

    return 0
}

# Helper function to update note in database
update_note_in_db() {
    # Compose new line
    local tags_str=$(IFS=','; echo "${current_tags[*]}")
    local ebooks_str=$(IFS=';'; echo "${ebook_entries[*]}")

    # Update tags and ebooks databases
    for tag in "${current_tags[@]}"; do
        echo "$tag" >> "$NOTES_TAGS_DB"
    done
    for entry in "${ebook_entries[@]}"; do
        local ebook_path="${entry%#*}"
        echo "$ebook_path" >> "$NOTES_EBOOKS_DB"
    done

    # Sort and deduplicate
    sort -u "$NOTES_TAGS_DB" -o "$NOTES_TAGS_DB"
    sort -u "$NOTES_EBOOKS_DB" -o "$NOTES_EBOOKS_DB"

    # Replace the line in NOTES_DB
    local old_line=$(grep -F "|${note_path}|" "$NOTES_DB")
    local new_line="${note_title}|${note_path}|${tags_str}|${ebooks_str}"

    # Use temp file to update NOTES_DB
    local temp_db
    temp_db=$(mktemp)
    while IFS= read -r line; do
        if [[ "$line" == "$old_line" ]]; then
            echo "$new_line"
        else
            echo "$line"
        fi
    done < "$NOTES_DB" > "$temp_db"

    if ! mv "$temp_db" "$NOTES_DB"; then
        whiptail --msgbox "Failed to update the note in the database." 8 50 >/dev/tty
        return 1
    fi

    whiptail --msgbox "Note attributes updated successfully." 8 50 >/dev/tty
    return 0
}

edit_note() {
    # Global
    note_path="$1"

    # Load existing note data into globals
    if ! load_note_data; then
        whiptail --msgbox "Error loading note data." 8 50 >/dev/tty
        return 1
    fi

    # DEBUG
    #echo ebook_entries: >&2
    #declare -p ebook_entries >&2

    local choice
    while true; do
        # Prepare status messages
        #local path_status="$note_path"
        local path_status
        local tag_status="none"
        [ ${#current_tags[@]} -gt 0 ] && tag_status="${#current_tags[@]} tags"
        local ebook_status="none"
        [ ${#ebook_entries[@]} -gt 0 ] && ebook_status="${#ebook_entries[@]} ebooks"

        # Truncate Note Path
        local dirname filename dirname_tr filename_tr tr_max
        tr_max=34 # max-*.txt

        dirname="$(dirname "$note_path")"
        dirname_tr="$(truncate_dirname "$dirname")"

        filename="$(basename "$note_path")"
        filename_tr="$(truncate_filename "$filename" $tr_max)"

        path_status="${dirname_tr}/${filename_tr}"

        choice=$(whiptail --title "Edit Note" --menu "Edit note properties" 20 100 8 \
            "Note Title"    "Current: ${note_title:0:50}" \
            "Note Path"     "Path: ${path_status}" \
            "Tags"          "Status: ${tag_status}" \
            "Ebooks"        "Status: ${ebook_status}" \
            "Save and Edit" "Save changes and open in editor" \
            "Save and Return" "Save changes and exit" 3>&1 1>&2 2>&3)
        [ $? -eq 0 ] || break

        case "$choice" in
            "Note Title")
		local old_note_title
		old_note_title="$note_title"	# FIX: CHECK ILLEGAL CHARS.

                note_title=$(whiptail --inputbox "Enter note title:" 8 40 "$note_title" 3>&1 1>&2 2>&3)

                # FIX: CHECK FOR ILLEGAL CHARS.
                if [[ "$note_title" =~ [\|#] ]]; then
                        note_title="$old_note_title"    # Revert
                        whiptail --title "Attention" --msgbox "Note title cannot contain illegal characters (|#)." 8 60
                        continue
                fi
                # END FIX.
                ;;
            "Note Path")
                whiptail --msgbox "Note path is: $note_path" 10 80
                ;;
            "Tags")
                manage_tags
                ;;
            "Ebooks")
                manage_ebooks
                ;;
            "Save and Edit")
                if update_note_in_db; then
                    #nano "$note_path"
		            #"$DEFAULT_EDITOR" "$note_path"
                    eval "${VIEWER_COMMANDS[$DEFAULT_EDITOR]}" "$note_path"
                    break
                fi
                ;;
            "Save and Return")
                update_note_in_db
                break
                ;;
        esac
    done
}

paginate_get_notes() {
    # Clear any previous selection
    SELECTED_ITEM=""

    local chunk_size=200

    # If new items are passed in, update FILTERED_EBOOKS and reset CURRENT_PAGE.
    # First arg is custom menu title.
    local menu_title
    if [ "$#" -gt 0 ]; then
        menu_title="$1"  # First argument is the title
        shift  # Shift to remove the title from the arguments
        FILTERED_EBOOKS=("$@")  # Remaining arguments are the items
        CURRENT_PAGE=0
    fi

    # Set default title if menu_title is not provided.
    # But if menu_title is not privided as $1 then FILTERED_EBOOKS will be errorneous.
    : "${menu_title:=Paged Menu}"

    [[ ${#FILTERED_EBOOKS[@]} -eq 0 ]] && return 1

    local total_pages=$(( ( ${#FILTERED_EBOOKS[@]} + chunk_size - 1 ) / chunk_size ))
    # Ensure CURRENT_PAGE is within valid bounds
    if (( CURRENT_PAGE >= total_pages )); then
        CURRENT_PAGE=$(( total_pages - 1 ))
    fi

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE * chunk_size ))
        # Extract the current chunk
        local current_chunk=("${FILTERED_EBOOKS[@]:$start:$chunk_size}")
        local menu_options=()

        # Add navigation options if needed
        if (( CURRENT_PAGE > 0 )); then
            menu_options+=("previous page" "")
        fi
        if (( CURRENT_PAGE < total_pages - 1 )); then
            menu_options+=("next page" "")
        fi

        # Append the current page items
        menu_options+=("${current_chunk[@]}")

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "Choose an item (Page $((CURRENT_PAGE + 1))/$total_pages)" \
            35 155 25 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        # Exit with code 1 if user cancels. Make sure to reset SELECTED_ITEM.
        if [ $? -ne 0 ]; then
            SELECTED_ITEM=""
            return 1
        fi

        case "$choice" in
            "previous page")
                (( CURRENT_PAGE-- ))
                ;;
            "next page")
                (( CURRENT_PAGE++ ))
                ;;
            *)
                # Return the index              
                SELECTED_ITEM="$choice"                
                return 0
                ;;
        esac
    done

    return 1
}

list_notes() {
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

    # The list has __FILTER_BY_TAG__ / __RESET_FILTER__ / __APPLY_GLOB__ /
    # __RESET_GLOB__ items (no tag is asked at the start).
    np_reset
    NP_SRC_FILE="$NOTES_DB"

    local selected_path
    while np_pick_note "Edit Note" "Choose a note to edit"; do
        IFS='|' read -r _ selected_path _ <<< "$NP_SELECTED_LINE"
        [[ -z "$selected_path" ]] && continue

        # Edit note, exactly as it says ;-)
        edit_note "$selected_path"

        # Notes may have changed meanwhile.
        [[ -s "$NOTES_DB" ]] || break
    done
}

# Following code section is about opening ebook file associated with a note
# with an external viewer like evince.
get_notes() {
    # SUB FUNCTION FOR PAGINATE SELECT TAG.
    show_tag_menu() {
        local TAG_OPTIONS__=("$@")  # Expect pairs: tag, ""
        local PAGE_SIZE=26  # ANY TAG plus 25 note files
        local page=0
        local total_items=$(( ${#TAG_OPTIONS__[@]} / 2 ))
        local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
        local selected_tag__=""
        local choice start end menu_items

        while true; do
            start=$(( page * PAGE_SIZE * 2 ))
            end=$(( start + PAGE_SIZE * 2 ))
            menu_items=("${TAG_OPTIONS__[@]:$start:$((PAGE_SIZE * 2))}")

            # Add navigation items
            if (( page > 0 )); then
                menu_items+=("<< Previous Page" "")
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=("Next Page >>" "")
            fi

            choice=$(whiptail --title "Filter by Tag (Page $((page + 1))/$total_pages)" \
                            --menu "Choose a tag to find linked notes:" 20 60 12 \
                            "${menu_items[@]}" \
                            3>&1 1>&2 2>&3)

            # Handle user action
            exit_status=$?
            if [[ $exit_status -ne 0 ]]; then
                # User pressed Cancel or Esc
                return 1
            fi

            case "$choice" in
                "Next Page >>")
                    ((page++))
                    ;;
                "<< Previous Page")
                    ((page--))
                    ;;
                *)
                    selected_tag__="$choice"
                    break
                    ;;
            esac
        done

        echo "$selected_tag__"
    }

    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 >/dev/tty
        return 1
    fi

    # FIX: POPULATE LINES BY LETTING USER SELECT TAG FIRST.
    # Read all tags into a bash array for whiptail menu
    local -a tags lines

    mapfile -t tags < "$NOTES_TAGS_DB"

    if [[ "${#tags[@]}" -eq 0 ]]; then
        mapfile -t lines < "$NOTES_DB"
    else
        # Build tag options for whiptail (needs tag and description pairs)
        local TAG_OPTIONS=()
        TAG_OPTIONS+=("ANY TAG" "")
        for tag in "${tags[@]}"; do
            TAG_OPTIONS+=("$tag" "")
        done

        # ADDITIONAL FIX: PAGINATE SELECT TAG.
        local selected_tag=$(show_tag_menu "${TAG_OPTIONS[@]}")

        # # Show menu and let user choose a tag
        # local selected_tag
        # selected_tag=$(whiptail --title "Filter by Tag" \
        #                         --menu "Choose a tag to find linked notes:" 20 60 10 \
        #                         "${TAG_OPTIONS[@]}" \
        #                         3>&1 1>&2 2>&3) || return 1

        if [[ "$selected_tag" == "ANY TAG" ]]; then
            mapfile -t lines < "$NOTES_DB"
        else
            # Populate array with lines that have exact match for selected tag
            mapfile -t lines < <(awk -F'|' -v tag="$selected_tag" '      
                {
                    n = split($3, tags, ",")
                    for (i = 1; i <= n; i++) {
                        if (tags[i] == tag) {
                            print $0
                            next
                        }
                    }
                }' "$NOTES_DB")
        fi
    fi
    # END FIX.    

    # local lines=()
    # while IFS= read -r line; do
    #     lines+=("$line")
    # done < "$NOTES_DB"

    if [[ ${#lines[@]} -eq 0 ]]; then
        [[ -n "$selected_tag" ]] && whiptail --msgbox "No matching notes for tag '${selected_tag}'." 8 50 >/dev/tty
        # echo ""
        return 1
    fi

    local options=()
    for i in "${!lines[@]}"; do
        local note_path=$(cut -d'|' -f2 <<< "${lines[$i]}")
        local tags=$(cut -d'|' -f3 <<< "${lines[$i]}")

        # Truncate note path
        local dir_tr filename_tr note_path_tr
        dir_tr="$(dirname "$note_path")"
        dir_tr="$(truncate_dirname "$dir_tr" 50)"
        filename_tr="$(basename "$note_path")"
        filename_tr="$(truncate_filename "$filename_tr" 50)"
        note_path_tr="${dir_tr}/${filename_tr}"

        # Truncate tags
        local tags_tr
        tags_tr="$(truncate_tags "$tags")"

        # Menu options (now, truncated)
        #options+=("$((i+1))" "$note_path | Tags: $tags")
        options+=("$((i+1))" "${note_path_tr} [${tags_tr}]")
    done

    #local selected_line_tag
    #selected_line_tag=$(whiptail --menu "Select a note" 20 100 10 "${options[@]}" 3>&1 1>&2 2>&3)
    #[[ $? -ne 0 ]] && { echo ""; return 1; }

    # Paginate instead
    CURRENT_PAGE=0
    SELECTED_ITEM=""

    ! paginate_get_notes "Open Associated eBook" "${options[@]}" && return 1
    local selected_line_tag="$SELECTED_ITEM"

    local selected_index=$((selected_line_tag - 1))
    [[ $selected_index -lt 0 || $selected_index -ge ${#lines[@]} ]] && return 1

    echo "${lines[$selected_index]}"
}

get_ebooks() {
    local selected_line="$1"
    [[ -z "$selected_line" ]] && { echo ""; return 1; }

    local ebooks_part=$(cut -d'|' -f4 <<< "$selected_line")
    [[ -z "$ebooks_part" ]] && { whiptail --msgbox "No ebooks associated with the note." 8 50 >/dev/tty;  return 1; }

    IFS=';' read -ra ebooks <<< "$ebooks_part"
    [[ ${#ebooks[@]} -eq 0 ]] && { whiptail --msgbox "No ebooks associated with the note." 8 50 >/dev/tty; return 1; }

    local ebook_options=()
    for i in "${!ebooks[@]}"; do
        local ebook_path=$(cut -d'#' -f1 <<< "${ebooks[$i]}")

        # Truncate ebook path
        local dir_tr filename_tr ebook_path_tr
        dir_tr="$(dirname "$ebook_path")"
        dir_tr="$(truncate_dirname "$dir_tr" 50)"
        filename_tr="$(basename "$ebook_path")"
        filename_tr="$(truncate_filename "$filename_tr" 50)"
        ebook_path_tr="${dir_tr}/${filename_tr}"

        # Menu options, now truncated
        #ebook_options+=("$((i+1))" "$ebook_path")
        ebook_options+=("$((i+1))" "${ebook_path_tr}")
    done

    local selected_ebook_tag
    selected_ebook_tag=$(whiptail --menu "Select an ebook" 20 155 10 "${ebook_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty)
    [[ $? -ne 0 ]] && { echo ""; return 1; }

    local ebook_index=$((selected_ebook_tag - 1))
    [[ $ebook_index -lt 0 || $ebook_index -ge ${#ebooks[@]} ]] && { echo ""; return 1; }

    echo "${ebooks[$ebook_index]}"
}

get_chapters() {
    local selected_ebook="$1"
    [[ -z "$selected_ebook" ]] && { echo ""; return 1; }

    local chapters_part=$(cut -d'#' -f2 <<< "$selected_ebook")
    #[[ -z "$chapters_part" ]] && { whiptail --msgbox "No chapters associated with the ebook." 20 80; echo ""; return 1; }

    IFS=',' read -ra chapters <<< "$chapters_part"
    #[[ ${#chapters[@]} -eq 0 ]] && { whiptail --msgbox "No chapters associated with the ebook." 20 80; echo ""; return 1; }

    local chapter_options=()

    # Open with no bookmark
    chapter_options+=(">> Just open" "")

    for i in "${!chapters[@]}"; do
        chapter_options+=("$((i+1))" "${chapters[$i]}")
    done

    local selected_chapter_tag
    selected_chapter_tag=$(whiptail --menu "Select a chapter" 20 80 10 "${chapter_options[@]}" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && { echo ""; return 1; }

    if [[ "$selected_chapter_tag" == ">> Just open" ]]; then
        echo ">> Just open"
        return
    fi

    local chapter_index=$((selected_chapter_tag - 1))
    [[ $chapter_index -lt 0 || $chapter_index -ge ${#chapters[@]} ]] && { echo ""; return 1; }

    echo "${chapters[$chapter_index]}"
}

extract_page() {
    local chapter_entry="$1"
    [[ -z "$chapter_entry" ]] && { echo ""; return 1; }

    local page_part="${chapter_entry#*:}"
    page_part="${page_part%%-*}"
    [[ -z "$page_part" ]] && { whiptail --msgbox "Invalid chapter format." 20 80; echo ""; return 1; }
    [[ "$page_part" =~ ^[0-9]+$ ]] || { whiptail --msgbox "Invalid page number: $page_part" 20 80; echo ""; return 1; }

    echo "$page_part"
}

open_evince() {
    local selected_ebook="$1"
    local page="$2"
    [[ -z "$selected_ebook" ]] && return 1   # Allow empty pages to just open the document.

    local ebook_path=$(cut -d'#' -f1 <<< "$selected_ebook")
    [[ -f "$ebook_path" ]] || { whiptail --msgbox "Ebook not found: $ebook_path" 20 80; return 1; }

    # extract extension then get viewer accordingly.
    local ext="${ebook_path##*.}"
    local viewer="${EXTENSION_COMMANDS[$ext]}"

    # check viewer is installed in system
    if ! command -v "$viewer" &>/dev/null; then
        whiptail --title "Alert" --msgbox "Command ${viewer} is not installed! Install it first." 20 80
        return 1
    fi

    #evince -p "$page" "$ebook_path" &> /dev/null & disown

    if [ -z "$page" ]; then
        #evince "$ebook_path" &> /dev/null & disown
	    #"$DEFAULT_VIEWER" "$ebook_path" &> /dev/null & disown
        "$viewer" "$ebook_path" &> /dev/null & disown
    else
        if [[ "$viewer" == "mupdf" ]]; then
            local cmd_and_option=(${VIEWER_COMMANDS[$viewer]})
            "${cmd_and_option[@]}" "$ebook_path" "$page" &> /dev/null & disown
            return
        elif [[ "$viewer" == "qpdfview" ]]; then
            local cmd_and_option=(${VIEWER_COMMANDS[$viewer]})
            "${cmd_and_option[@]}" "${ebook_path}#${page}" &> /dev/null & disown
            return                    
        fi
        #evince -p "$page" "$ebook_path" &> /dev/null & disown
	    #"$DEFAULT_VIEWER" -p "$page" "$ebook_path" &> /dev/null & disown        
        
        local cmd_and_option=(${VIEWER_COMMANDS[$viewer]})
        "${cmd_and_option[@]}" "$page" "$ebook_path" &> /dev/null & disown

    fi
}

handle_no_chapters() {
    local selected_ebook="$1"
    local choice exit_status    

    # Display whiptail menu and capture both output and exit status
    choice=$(whiptail --title "No Chapters Found" \
                     --menu "What would you like to do?" \
                     15 60 4 \
                     "Open" "Open ebook anyway" \
                     "Return" "Return without opening" \
                     3>&1 1>&2 2>&3)
    exit_status=$?

    # Handle user selection
    case $exit_status in
        0)
            case "$choice" in
                "Open")
                    open_evince "$selected_ebook"
                    ;;
                "Return")
                    return
                    ;;
            esac
            ;;
        *)
            # User pressed Cancel or closed dialog
            return
            ;;
    esac
}

open_note_ebook_page() {
    # Only notes with at least one ebook associated to them are listed
    # (looked up in $NOTES_DB, 4th field). No tag is asked at the start: the
    # list has __FILTER_BY_TAG__ / __RESET_FILTER__ / __APPLY_GLOB__ /
    # __RESET_GLOB__ items.
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 60 >/dev/tty
        return 1
    fi

    local ebook_src
    ebook_src=$(mktemp) || return 1
    awk -F'|' 'NF >= 2 && $4 ~ /[^ \t;]/' "$NOTES_DB" > "$ebook_src"
    if [[ ! -s "$ebook_src" ]]; then
        rm -f "$ebook_src"
        whiptail --title "Attention" --msgbox "No notes with associated ebooks found." 8 60 >/dev/tty
        return 1
    fi

    np_reset
    NP_SRC_FILE="$ebook_src"
    np_pick_note "Open Associated eBook" "Choose a note to open its associated ebook"
    local pick_rc=$?
    rm -f "$ebook_src"
    (( pick_rc == 0 )) || return 1

    local selected_line="$NP_SELECTED_LINE"
    [[ -z "$selected_line" ]] && return 1

    local selected_ebook=$(get_ebooks "$selected_line")
    [[ -z "$selected_ebook" ]] && return 1

    # Extract the chapters part from the selected_ebook
    local chapters_part=$(cut -d'#' -f2 <<< "$selected_ebook")

    if [[ -n "$chapters_part" ]]; then
        # Chapters are present, prompt user to select one
        local selected_chapter=$(get_chapters "$selected_ebook")

        # >> Just open
        if [[ "$selected_chapter" == ">> Just open" ]]; then
            handle_no_chapters "$selected_ebook"
            return
        fi

        if [ -n "$selected_chapter" ]; then
            local page=$(extract_page "$selected_chapter")
            [[ -z "$page" ]] && return 1
            open_evince "$selected_ebook" "$page"
        #else
        #    # User canceled chapter selection; open without page
        #    open_evince "$selected_ebook"
        fi
    else
        # No chapters available; ask to open the ebook directly
        #open_evince "$selected_ebook"
        handle_no_chapters "$selected_ebook"
    fi
}

# Following code section is about doing operations with note filtered by tag.
# DEPRECATED.
get_note_tag_from_global_list_old() {
    local tags_file="${NOTES_TAGS_DB}"
    if [[ ! -f "$tags_file" ]]; then
        echo "Error: Tags database file not found." >&2
        return 1
    fi

    # Read tags into array
    local tags=()
    while IFS= read -r tag; do
        tags+=("$tag" "")
    done < "$tags_file"

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo "No tags available in the database." >&2
        return 1
    fi

    # Use whiptail to display menu
    local selected_tag
    selected_tag=$(whiptail --title "Do stuff by Tag" --menu "Choose a tag" 20 40 10 "${tags[@]}" 3>&1 1>&2 2>&3 >/dev/tty)

    # Check if selection was cancelled
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    echo "$selected_tag"
}

# ---------------------------------------------------------------------------
# Do Stuff by Tag: shared helpers (used only by the Do Stuff by Tag workflow)
# ---------------------------------------------------------------------------
NT_NO_TAG_LABEL="[NO TAG]"      # pseudo tag: notes that have no tag at all
NT_CURRENT_TAG=""               # tag currently being filtered by (shown in statuses)
NT_NOTE_GLOB=""                 # glob applied to lists of notes
NT_PROJECT_GLOB=""              # glob applied to lists of projects
NT_TAG_FILTER=""                # literal substring filter applied to lists of tags
NT_PICKED_TAG=""                # result of nt_pick_tag
NT_PICKED_LINE=""               # result of nt_pick_note_line (NOTES_DB style line)
NT_PICKED_INDEX=-1              # result of nt_pick_note_line (index in the given lines)
NT_CHECKED_PATHS=()             # result of nt_pick_notes_checklist (note paths)
NT_PRESELECT_PATHS=()           # optional: note paths to pre-check in the next checklist
NT_EBOOK_NOTE_LINES=()          # result of nt_filter_notes_with_ebooks
NT_URL_NOTE_LINES=()            # result of nt_filter_notes_with_urls

# nt_glob_match GLOB SUBJECT...
# Returns 0 when GLOB is empty or when it matches (whole string, case
# insensitive) at least one of the SUBJECTs (callers pass the title only).
nt_glob_match() {
    local g="$1"
    shift
    [[ -z "$g" ]] && return 0

    local had_nocase=0 s rc=1
    shopt -q nocasematch && had_nocase=1
    shopt -s nocasematch
    for s in "$@"; do
        if [[ "$s" == $g ]]; then
            rc=0
            break
        fi
    done
    (( had_nocase )) || shopt -u nocasematch
    return $rc
}

# nt_ask_glob notes|projects  -> asks for a glob and stores it in the right variable.
nt_ask_glob() {
    local kind="$1" current what new
    case "$kind" in
        projects) current="$NT_PROJECT_GLOB"; what="TITLE of the project" ;;
        *)        current="$NT_NOTE_GLOB";    what="TITLE of the note" ;;
    esac

    new=$(whiptail --title "__APPLY_GLOB__" --inputbox \
"Enter a glob to filter by the ${what} (case insensitive).\n\
* matches any characters, ? matches one character.\n\
The whole ${what#* of the } must match, e.g.  *python*  or  Chapter ?*\n\
Empty input removes the glob filter." 16 90 "$current" 3>&1 1>&2 2>&3) || return 1

    case "$kind" in
        projects) NT_PROJECT_GLOB="$new" ;;
        *)        NT_NOTE_GLOB="$new" ;;
    esac
}

# nt_ask_tag_filter -> asks for a text and stores it in NT_TAG_FILTER.
# Tags are narrowed down by a literal (not glob) substring match, case-insensitive.
nt_ask_tag_filter() {
    local new
    new=$(whiptail --title "__FILTER__" --inputbox \
"Enter text to narrow down the tag list.\n\
Tags that contain this text are shown (literal substring match, case insensitive; no wildcards).\n\
Empty input removes the filter." 12 90 "$NT_TAG_FILTER" 3>&1 1>&2 2>&3) || return 1
    NT_TAG_FILTER="$new"
}

# nt_pick_tag TITLE PROMPT INCLUDE_NO_TAG
# Paginated menu of tags (from $NOTES_TAGS_DB) with __FILTER__ /
# __RESET_FILTER__ (literal substring match) on top. INCLUDE_NO_TAG=1 always
# shows [NO TAG] (never hidden by the filter). 50 tags per page, in a large box (clamped to the terminal height).
# On success sets NT_PICKED_TAG and returns 0; returns 1 on Back/Esc.
nt_pick_tag() {
    local title="$1" prompt="$2" include_no_tag="${3:-0}"
    local -a all_tags=() shown=() menu=()
    local tag k per_page=50 page=0
    NT_PICKED_TAG=""
    NT_TAG_FILTER=""

    if [[ -f "$NOTES_TAGS_DB" ]]; then
        while IFS= read -r tag || [[ -n "$tag" ]]; do
            [[ -n "$tag" ]] && all_tags+=("$tag")
        done < "$NOTES_TAGS_DB"
    fi

    while :; do
        shown=()
        for tag in "${all_tags[@]}"; do
            if [[ -z "$NT_TAG_FILTER" || "${tag,,}" == *"${NT_TAG_FILTER,,}"* ]]; then
                shown+=("$tag")
            fi
        done

        local matched=${#shown[@]}
        local pages=$(( (matched + per_page - 1) / per_page ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$(( pages - 1 ))
        (( page < 0 )) && page=0

        menu=()
        (( include_no_tag )) && menu+=("$NT_NO_TAG_LABEL" "Notes with no tag associated")
        menu+=(
            "__FILTER__" "Filter tags by text (literal substring)${NT_TAG_FILTER:+   [filter: $NT_TAG_FILTER]}"
            "__RESET_FILTER__" "Reset tag filter"
        )
        (( page > 0 )) && menu+=("<< Previous Page" "")
        (( page < pages - 1 )) && menu+=(">> Next Page" "")

        local s=$(( page * per_page )) e=$(( page * per_page + per_page ))
        (( e > matched )) && e=$matched
        for ((k = s; k < e; k++)); do
            menu+=("${shown[k]}" "")
        done

        local status="${prompt}\n\nFilter: ${NT_TAG_FILTER:-(none)}  |  ${matched}/${#all_tags[@]} tag(s)"
        (( matched == 0 )) && status+="  |  No tags match the filter."

        # Large box: 50 tags + [NO TAG] + filter items + 2 navigation items
        # without scrolling (clamped when the terminal is smaller).
        local box_h=64 menu_h=55 term_h
        term_h=$(tput lines 2>/dev/null || echo "$box_h")
        if (( term_h < box_h )); then
            box_h=$term_h
            menu_h=$(( box_h - 9 ))
            (( menu_h < 5 )) && menu_h=5
        fi

        local choice
        choice=$(whiptail --title "$title (Page $((page + 1))/${pages})" --cancel-button "Back" \
            --menu "$status" "$box_h" 150 "$menu_h" "${menu[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            "__FILTER__")       nt_ask_tag_filter; page=0 ;;
            "__RESET_FILTER__") NT_TAG_FILTER=""; page=0 ;;
            "<< Previous Page") (( page-- )) ;;
            ">> Next Page")     (( page++ )) ;;
            *)
                NT_PICKED_TAG="$choice"
                return 0
                ;;
        esac
    done
}

# nt_pick_note_line TITLE LINE...
# Paginated menu of notes (LINEs are NOTES_DB style lines) with
# __APPLY_GLOB__ / __RESET_GLOB__ on top. On success sets NT_PICKED_LINE and
# NT_PICKED_INDEX and returns 0. Returns 1 on Back/Esc.
nt_pick_note_line() {
    local title="$1"
    shift
    local -a lines=("$@")
    local total=${#lines[@]}
    local page_size=100 page=0
    local -a idx=()
    local i k ntitle npath ntags

    NT_PICKED_LINE=""
    NT_PICKED_INDEX=-1

    while :; do
        idx=()
        for ((i = 0; i < total; i++)); do
            IFS='|' read -r ntitle npath _ <<< "${lines[i]}"
            nt_glob_match "$NT_NOTE_GLOB" "$ntitle" && idx+=("$i")
        done

        local matched=${#idx[@]}
        local pages=$(( (matched + page_size - 1) / page_size ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$(( pages - 1 ))
        (( page < 0 )) && page=0

        local -a menu=(
            "__APPLY_GLOB__" "Filter notes by glob (title)${NT_NOTE_GLOB:+   [glob: $NT_NOTE_GLOB]}"
            "__RESET_GLOB__" "Reset glob filter"
        )
        (( page > 0 )) && menu+=("previous page" "")
        (( page < pages - 1 )) && menu+=("next page" "")

        local s=$(( page * page_size )) e=$(( page * page_size + page_size ))
        (( e > matched )) && e=$matched
        for ((k = s; k < e; k++)); do
            i=${idx[k]}
            IFS='|' read -r ntitle npath ntags _ <<< "${lines[i]}"
            menu+=("$i" "${ntitle:0:80} $(truncate_note_tags_by_tag "$ntags")")
        done

        local status="Tag: ${NT_CURRENT_TAG:-?}  |  Glob: ${NT_NOTE_GLOB:-(none)}  |  ${matched}/${total} note(s)  |  Page $((page + 1))/${pages}"
        (( matched == 0 )) && status+="\n\nNo notes match the glob. Use __APPLY_GLOB__ or __RESET_GLOB__."

        local choice
        choice=$(whiptail --title "$title" --cancel-button "Back" \
            --menu "$status" 35 155 25 "${menu[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            "__APPLY_GLOB__") nt_ask_glob notes; page=0 ;;
            "__RESET_GLOB__") NT_NOTE_GLOB=""; page=0 ;;
            "previous page")  (( page-- )) ;;
            "next page")      (( page++ )) ;;
            *)
                NT_PICKED_INDEX=$choice
                NT_PICKED_LINE="${lines[choice]}"
                return 0
                ;;
        esac
    done
}

# nt_pick_notes_checklist TITLE SUBMIT_ID SUBMIT_LABEL LINE...
# Paginated checklist of notes with __APPLY_GLOB__ / __RESET_GLOB__ items.
# Selections are kept while the glob changes or pages are switched.
# On success fills NT_CHECKED_PATHS and returns 0; returns 1 on cancel.
nt_pick_notes_checklist() {
    local title="$1" submit_id="$2" submit_label="$3"
    shift 3
    local -a lines=("$@")
    local total=${#lines[@]}
    local page_size=30 page=0
    local -A selected=()
    local -a idx=() chosen=() page_ids=() page_paths=()
    local i k c p pp ntitle npath ntags

    for p in "${NT_PRESELECT_PATHS[@]}"; do
        [[ -n "$p" ]] && selected["$p"]=1
    done
    NT_PRESELECT_PATHS=()
    NT_CHECKED_PATHS=()

    while :; do
        idx=()
        for ((i = 0; i < total; i++)); do
            IFS='|' read -r ntitle npath _ <<< "${lines[i]}"
            nt_glob_match "$NT_NOTE_GLOB" "$ntitle" && idx+=("$i")
        done

        local matched=${#idx[@]}
        local pages=$(( (matched + page_size - 1) / page_size ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$(( pages - 1 ))
        (( page < 0 )) && page=0

        local -a opts=(
            "__APPLY_GLOB__" "Filter notes by glob (title)${NT_NOTE_GLOB:+   [glob: $NT_NOTE_GLOB]}" "OFF"
            "__RESET_GLOB__" "Reset glob filter" "OFF"
        )
        (( page > 0 )) && opts+=("__PREV_PAGE__" "Previous page" "OFF")
        (( page < pages - 1 )) && opts+=("__NEXT_PAGE__" "Next page" "OFF")
        opts+=("$submit_id" "$submit_label" "OFF")

        page_ids=()
        page_paths=()
        local s=$(( page * page_size )) e=$(( page * page_size + page_size ))
        (( e > matched )) && e=$matched
        local state label
        for ((k = s; k < e; k++)); do
            i=${idx[k]}
            IFS='|' read -r ntitle npath ntags _ <<< "${lines[i]}"
            state="OFF"
            [[ -n "${selected[$npath]+x}" ]] && state="ON"
            label="${ntitle:0:80} $(truncate_note_tags_by_tag "$ntags")"
            opts+=("n_$i" "$label" "$state")
            page_ids+=("n_$i")
            page_paths+=("$npath")
        done

        local result
        result=$(whiptail --title "$title (Page $((page + 1))/${pages})" \
            --checklist "Tag: ${NT_CURRENT_TAG:-?}  |  Glob: ${NT_NOTE_GLOB:-(none)}  |  ${matched}/${total} note(s) shown  |  Selected: ${#selected[@]}" \
            35 155 25 "${opts[@]}" 3>&1 1>&2 2>&3) || return 1

        result=${result//\"/}
        chosen=()
        read -r -a chosen <<< "$result"

        # Remember what is checked on this page (selections of other pages and
        # of notes currently hidden by the glob are kept).
        for ((k = 0; k < ${#page_ids[@]}; k++)); do
            pp="${page_paths[k]}"
            if [[ " ${chosen[*]} " == *" ${page_ids[k]} "* ]]; then
                selected["$pp"]=1
            else
                unset 'selected[$pp]'
            fi
        done

        local act_glob=0 act_reset=0 act_prev=0 act_next=0 act_submit=0 n_actions=0
        for c in "${chosen[@]}"; do
            case "$c" in
                __APPLY_GLOB__) act_glob=1;   n_actions=$((n_actions + 1)) ;;
                __RESET_GLOB__) act_reset=1;  n_actions=$((n_actions + 1)) ;;
                __PREV_PAGE__)  act_prev=1;   n_actions=$((n_actions + 1)) ;;
                __NEXT_PAGE__)  act_next=1;   n_actions=$((n_actions + 1)) ;;
                "$submit_id")   act_submit=1; n_actions=$((n_actions + 1)) ;;
            esac
        done

        if (( n_actions > 1 )); then
            whiptail --title "Invalid Selection" --msgbox "Please select only one of: apply glob, reset glob, previous/next page or the final action." 10 70
            continue
        fi

        if (( act_glob )); then
            nt_ask_glob notes
            page=0
            continue
        fi
        if (( act_reset )); then
            NT_NOTE_GLOB=""
            page=0
            continue
        fi
        if (( act_prev )); then
            (( page > 0 )) && (( page-- ))
            continue
        fi
        if (( act_next )); then
            (( page < pages - 1 )) && (( page++ ))
            continue
        fi

        if (( act_submit )); then
            if (( ${#selected[@]} == 0 )); then
                whiptail --title "Attention" --msgbox "Please select at least one note first." 8 50
                continue
            fi
            # Return the selection in the order of the given lines.
            NT_CHECKED_PATHS=()
            for ((i = 0; i < total; i++)); do
                IFS='|' read -r _ npath _ <<< "${lines[i]}"
                [[ -n "${selected[$npath]+x}" ]] && NT_CHECKED_PATHS+=("$npath")
            done
            return 0
        fi
    done
}

# nt_pick_project TITLE [paths_only]
# Paginated menu of projects with __APPLY_GLOB__ / __RESET_GLOB__ on top.
# paths_only=1: show just the project paths (no titles). The glob always filters by title.
# On success sets SELECTED_ITEM_PROJECT (project file path) and returns 0.
nt_pick_project() {
    local title="$1" paths_only="${2:-0}"
    SELECTED_ITEM_PROJECT=""
    local page=0 page_size=100
    local -a mt=() mp=()
    local ptitle ppath total k

    while :; do
        mt=()
        mp=()
        total=0
        if [[ -f "$PROJECTS_DB" ]]; then
            while IFS='|' read -r ptitle ppath _ || [[ -n "$ppath" ]]; do
                [[ -z "$ppath" ]] && continue
                total=$((total + 1))
                if nt_glob_match "$NT_PROJECT_GLOB" "$ptitle"; then
                    mt+=("$ptitle")
                    mp+=("$ppath")
                fi
            done < "$PROJECTS_DB"
        fi

        local matched=${#mp[@]}
        local pages=$(( (matched + page_size - 1) / page_size ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$(( pages - 1 ))
        (( page < 0 )) && page=0

        local -a menu=(
            "__APPLY_GLOB__" "Filter projects by glob (title)${NT_PROJECT_GLOB:+   [glob: $NT_PROJECT_GLOB]}"
            "__RESET_GLOB__" "Reset glob filter"
        )
        (( page > 0 )) && menu+=("previous page" "")
        (( page < pages - 1 )) && menu+=("next page" "")

        local s=$(( page * page_size )) e=$(( page * page_size + page_size ))
        (( e > matched )) && e=$matched
        for ((k = s; k < e; k++)); do
            if [[ "$paths_only" == "1" ]]; then
                menu+=("${mp[k]}" "")
            else
                menu+=("${mp[k]}" "${mt[k]:0:80}")
            fi
        done

        local status="Glob: ${NT_PROJECT_GLOB:-(none)}  |  ${matched}/${total} project(s)  |  Page $((page + 1))/${pages}"
        (( matched == 0 )) && status+="\n\nNo projects match the glob. Use __APPLY_GLOB__ or __RESET_GLOB__."

        local choice
        choice=$(whiptail --title "$title" --cancel-button "Back" \
            --menu "$status" 35 175 25 "${menu[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            "__APPLY_GLOB__") nt_ask_glob projects; page=0 ;;
            "__RESET_GLOB__") NT_PROJECT_GLOB=""; page=0 ;;
            "previous page")  (( page-- )) ;;
            "next page")      (( page++ )) ;;
            *)
                SELECTED_ITEM_PROJECT="$choice"
                return 0
                ;;
        esac
    done
}

# nt_filter_notes_with_ebooks LINE...
# Looks the notes up in $NOTES_DB and keeps only those that have at least one
# ebook associated (4th field). Result (fresh DB lines) in NT_EBOOK_NOTE_LINES.
nt_filter_notes_with_ebooks() {
    NT_EBOOK_NOTE_LINES=()
    local -A db_line=()
    local l p e
    if [[ -f "$NOTES_DB" ]]; then
        while IFS= read -r l || [[ -n "$l" ]]; do
            IFS='|' read -r _ p _ e <<< "$l"
            [[ -n "$p" && -n "$e" ]] && db_line["$p"]="$l"
        done < "$NOTES_DB"
    fi
    for l in "$@"; do
        IFS='|' read -r _ p _ <<< "$l"
        [[ -n "${db_line[$p]+x}" ]] && NT_EBOOK_NOTE_LINES+=("${db_line[$p]}")
    done
    return 0
}

# nt_filter_notes_with_urls LINE...
# Keeps only the notes that have at least one URL in $URLS_DB.
# Result in NT_URL_NOTE_LINES.
nt_filter_notes_with_urls() {
    NT_URL_NOTE_LINES=()
    local GS=$'\x1D'
    local -A has=()
    local l p
    if [[ -f "$URLS_DB" ]]; then
        while IFS= read -r l || [[ -n "$l" ]]; do
            if [[ "$l" == *"$GS"?* ]]; then
                p="${l%%"$GS"*}"
                [[ -n "$p" ]] && has["$p"]=1
            fi
        done < "$URLS_DB"
    fi
    for l in "$@"; do
        IFS='|' read -r _ p _ <<< "$l"
        [[ -n "${has[$p]+x}" ]] && NT_URL_NOTE_LINES+=("$l")
    done
    return 0
}

# FIX: Paginated.
get_note_tag_from_global_list() {
    # $1 (optional): prompt text. Thin wrapper kept for compatibility; the
    # tag list (with [NO TAG], __FILTER__ / __RESET_FILTER__) is nt_pick_tag.
    nt_pick_tag "Do stuff by Tag" "${1:-Choose a tag}" 1 || return 1
    echo "$NT_PICKED_TAG"
}

filter_notes_by_tag() {
    local target_tag="$1"
    local notes_file="${NOTES_DB}"
    FILTERED_NOTES_BY_TAG=()

    if [[ ! -f "$notes_file" || ! -s "$notes_file" ]]; then
        #echo "Error: Notes database file not found." >&2
        #whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 </dev/tty >/dev/tty  # we don't need this since add note with same tag.
        return 1
    fi

    # [NO TAG]: notes that have no tag associated to them.
    if [[ "$target_tag" == "$NT_NO_TAG_LABEL" ]]; then
        mapfile -t FILTERED_NOTES_BY_TAG < <(
            awk -F'|' 'NF >= 2 && $2 != "" && ($3 == "" || $3 == "[]")' "$notes_file"
        )
        return 0
    fi

    while IFS= read -r line; do
        IFS='|' read -ra fields <<< "$line"
        [[ ${#fields[@]} -lt 3 ]] && continue  # Skip invalid lines

        # Check if target tag exists in the comma-separated list (literal match)
        if [[ ",${fields[2]}," == *",${target_tag},"* ]]; then
            FILTERED_NOTES_BY_TAG+=("$line")
        fi
    done < "$notes_file"
}

list_notes_from_filtered() {
    if [[ $# -eq 0 ]]; then
        whiptail --msgbox "No notes found in database" 8 40
        return 1
    fi

    local selected_path
    while true; do
        # Notes list with __APPLY_GLOB__ / __RESET_GLOB__
        nt_pick_note_line "Edit Note" "$@" || break
        IFS='|' read -r _ selected_path _ <<< "$NT_PICKED_LINE"
        [[ -z "$selected_path" ]] && break

        # Edit the selected note
        edit_note "$selected_path"
    done
}

get_notes_from_filtered() {
    # Only notes with at least one associated ebook (looked up in $NOTES_DB)
    # are listed. The chosen NOTES_DB line is returned in NT_PICKED_LINE.
    NT_PICKED_LINE=""
    nt_filter_notes_with_ebooks "$@"

    if [[ ${#NT_EBOOK_NOTE_LINES[@]} -eq 0 ]]; then
        whiptail --title "Attention" --msgbox "None of the notes has an ebook associated with it." 8 60
        return 1
    fi

    nt_pick_note_line "Open Associated eBook" "${NT_EBOOK_NOTE_LINES[@]}"
}

open_note_ebook_page_from_filtered() {
    get_notes_from_filtered "$@" || return 1
    local selected_line="$NT_PICKED_LINE"
    [[ -z "$selected_line" ]] && return 1

    local selected_ebook=$(get_ebooks "$selected_line")
    [[ -z "$selected_ebook" ]] && return 1

    # Extract the chapters part from the selected_ebook
    local chapters_part=$(cut -d'#' -f2 <<< "$selected_ebook")

    if [[ -n "$chapters_part" ]]; then
        # Chapters are present, prompt user to select one
        local selected_chapter=$(get_chapters "$selected_ebook")

        # >> Just open
        if [[ "$selected_chapter" == ">> Just open" ]]; then
            handle_no_chapters "$selected_ebook"
            return
        fi

        if [ -n "$selected_chapter" ]; then
            local page=$(extract_page "$selected_chapter")
            [[ -z "$page" ]] && return 1
            open_evince "$selected_ebook" "$page"
        #else
        #    # User canceled chapter selection; open without page
        #    open_evince "$selected_ebook"
        fi
    else
        # No chapters available; ask to open the ebook directly
        #open_evince "$selected_ebook"
        handle_no_chapters "$selected_ebook"
    fi
}

associate_new_note_to_project() {
    ask() {
        local choice exit_status
        choice=$(whiptail --title "Next action" \
                        --menu "Choose an option:" \
                        15 60 2 \
                        "associate" "Associate this note with project file" \
                        "continue"  "Do nothing further" \
                        3>&1 1>&2 2>&3)

        exit_status=$?

        # Cancel or ESC
        if [[ $exit_status -ne 0 ]]; then
            return 1
        fi

        case "$choice" in
            continue)
                return 1
                ;;
            associate)
                return 0
                ;;
        esac
    }

    ask || return 1

    # accept note path as arg
    local NEW_NOTE_PATH="$1"

    local temp_file line_updated duplicate_detected project_found
    temp_file=$(mktemp) || return 1
    line_updated=0
    duplicate_detected=0
    project_found=0

    # Check if databases exist
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "Please add at least one project and try again." 8 60
        return 1
    fi
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "Please add at least one note and try again." 8 60
        return 1
    fi

    # Project selection: list has __APPLY_GLOB__ / __RESET_GLOB__ items.
    nt_pick_project "Select Project" || { rm -f "$temp_file"; return 1; }
    local selected_project_path
    selected_project_path="$SELECTED_ITEM_PROJECT"
    [[ -z "$selected_project_path" ]] && { rm -f "$temp_file"; return 1; }

    # WE'VE SELECTED PROJECT FILE AT THIS POINT!!!!

    local selected_note_path="$NEW_NOTE_PATH"

    # Process PROJECTS_DB - update each line (only change line of selected project file)
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi

        IFS='|' read -r title path notes <<< "$line"
        # If there is matched line...
        if [[ "$path" == "$selected_project_path" ]]; then
            project_found=1
            current_notes="$notes"
            local notes_array=()

            # Check for duplicates
            IFS=',' read -ra notes_array <<< "$current_notes"
            local duplicate=0	# Reset for each iteration.
            # If duplicate found then set duplicate and break out of for loop here.
            for note in "${notes_array[@]}"; do
                [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
            done

            if (( duplicate )); then
                whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                # reset
                line_updated=0

                duplicate_detected=1
                # Rebuild original line
                new_line="$title|$path|$current_notes"
                # There is no fourth field!!!!
                # [[ -n "$rest" ]] && new_line+="|$rest"
                echo "$new_line" >> "$temp_file"	# No change.
            else
                # reset
                duplicate_detected=0

                # Update notes
                # If there is no previously associated note...
                if [[ -z "$current_notes" ]]; then
                    new_notes="$selected_note_path"
                else
                    new_notes="$current_notes,$selected_note_path"
                fi
                new_line="$title|$path|$new_notes"
                #[[ -n "$rest" ]] && new_line+="|$rest"
                echo "$new_line" >> "$temp_file"	# Changes made.
                line_updated=1
            fi
        else
            # Just leave the line unchanged.
            echo "$line" >> "$temp_file"
        fi
    done < "$PROJECTS_DB"

    # Handle processing results
    if (( project_found )); then
        if (( line_updated && !duplicate_detected )); then
            mv "$temp_file" "$PROJECTS_DB"
            whiptail --msgbox "Note successfully associated with the project." 10 50
        elif (( duplicate_detected )); then
            rm "$temp_file"
            #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
            return 1
        else
            rm "$temp_file"
            whiptail --msgbox "No changes were made to the project entry." 10 50
            return 1
        fi
    else
        rm "$temp_file"
        whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
        return 1
    fi
}

associate_notes_by_tag_to_project() {
    update_proj_db_file_by_notes_checklist() {
        local selected_project_path="$1"
        local temp_file="$2"
        shift 2

        # assign the rest to an array - what user has selected from whiptail checklist.
        local sel_note_paths_checklist=("$@")

        # Empty temp_file
        > "$temp_file"

        local title path current_notes new_notes note
        local current_array=()
        # Read PROJECTS_DB line by line
        while IFS='|' read -r title path current_notes; do
            if [[ "$path" == "$selected_project_path" ]]; then
                # Prepare new notes string
                if [[ -z "$current_notes" ]]; then
                    # No current notes, just join selected notes
                    new_notes="$(printf '%s,' "${sel_note_paths_checklist[@]}")"
                    new_notes=${new_notes%,}   # remove trailing comma
                else
                    # Merge current notes with selected notes, remove duplicates
                    IFS=',' read -ra current_array <<< "$current_notes"
                    declare -A seen
                    local new_array=()

                    # Add current notes first
                    for note in "${current_array[@]}"; do
                        seen["$note"]=1
                        new_array+=("$note")
                    done

                    # Add selected notes if not already present
                    for note in "${sel_note_paths_checklist[@]}"; do
                        if [[ -z "${seen[$note]}" ]]; then
                            new_array+=("$note")
                        fi
                    done
                    
                    new_notes="$(printf '%s,' "${new_array[@]}")"
                    new_notes=${new_notes%,}  # remove trailing comma
                fi

                # Construct new line
                echo "$title|$path|$new_notes" >> "$temp_file"
            else
                # Keep line unchanged
                echo "$title|$path|$current_notes" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Compare temp_file and PROJECTS_DB
        if cmp -s "$temp_file" "$PROJECTS_DB"; then
            return 1  # Files are the same
        else
            return 0  # Files differ
        fi
    }

    whiptail --title "Attention" \
         --msgbox "Step 1: Select the note files.\nStep 2: Select the project files to associate them with.\n\nYou can associate multiple note files to multiple project files in this function." \
         20 80

    # let user select notes from whiptai checklist.
    # Checklist of notes with __APPLY_GLOB__ / __RESET_GLOB__ items.
    nt_pick_notes_checklist "Select Notes" "SUBMIT" "Finish selection" "$@" || return 1
    local selected_notes_chk=("${NT_CHECKED_PATHS[@]}")
    [[ ${#selected_notes_chk[@]} -eq 0 ]] && return 1

    local temp_file line_updated duplicate_detected project_found
    temp_file=$(mktemp) || return 1
    line_updated=0
    duplicate_detected=0
    project_found=0

    # Check if databases exist
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "Please add at least one project and try again." 8 60
        return 1
    fi
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "Please add at least one note and try again." 8 60
        return 1
    fi

    while :; do
        # Project selection
        # Projects list with __APPLY_GLOB__ / __RESET_GLOB__ items.
        nt_pick_project "Select Project to Associate With" 1 || { rm -f "$temp_file"; return 1; }
        local selected_project_path
        selected_project_path="$SELECTED_ITEM_PROJECT"
        [[ -z "$selected_project_path" ]] && { rm -f "$temp_file"; return 1; }

        # Update PROJECTS_DB file and check if changes are made.
        if update_proj_db_file_by_notes_checklist "$selected_project_path" "$temp_file" "${selected_notes_chk[@]}"; then
            mv "$temp_file" "$PROJECTS_DB"
            whiptail --msgbox "Notes successfully associated with the project." 10 50            
        else
            rm "$temp_file"
            whiptail --msgbox "No changes were made to the project entry. This may mean that your chosen notes are already associated with chosen project." 10 50
        fi
    done
}

do_note_filter_by_tag() {
    truncate_note_tags_by_tag() {
        local tags="$1"
        local inner
        local -a tag_array
        local count
        local extra

        # Remove surrounding [ ]
        inner="${tags#[}"
        inner="${inner%]}"

        # Empty list
        if [[ -z "$inner" ]]; then
            printf '[]\n'
            return
        fi

        # Split on commas
        IFS=',' read -r -a tag_array <<< "$inner"

        count=${#tag_array[@]}

        if (( count <= 3 )); then
            printf '[%s]\n' "$inner"
            return
        fi

        extra=$((count - 3))

        printf '[%s,%s,%s +%d]\n' \
            "${tag_array[0]}" \
            "${tag_array[1]}" \
            "${tag_array[2]}" \
            "$extra"
    }

    assoc_url_to_note_by_tag() {
        touch "$URLS_DB"
        
        #local NOTES_DB="$NOTES_DB"
        #local URLS_DB="$URLS_DB"
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls

        # Extract note paths from NOTES_DB
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 >/dev/tty
            return 1
        fi

        local -a tags lines
        # Passed from FILTERED_NOTES_BY_TAG.
        lines=("$@")

        if [[ ${#lines[@]} -eq 0 ]]; then
            whiptail --msgbox "No notes with the tag found. Add at least one note and try again." 8 60
            return 1
        fi    

        # Notes list with __APPLY_GLOB__ / __RESET_GLOB__
        local title
        nt_pick_note_line "Select Note to Associate URL to" "${lines[@]}" || return 1
        local selected_path
        IFS='|' read -r _ selected_path _ <<< "$NT_PICKED_LINE"

        [[ -z "$selected_path" ]] && return 1

        # Load existing URLs
        local urls=()
        local titles=()
        if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
            while IFS= read -r line; do
                if [[ "$line" == "${selected_path}${GS}"* ]]; then
                    IFS="$RS" read -ra entries <<< "${line#*$GS}"
                    for entry in "${entries[@]}"; do
                        IFS="$US" read -r url title <<< "$entry"
                        urls+=("$url")
                        titles+=("$title")
                    done
                    break
                fi
            done < "$URLS_DB"
        fi

        local url_regex='^(https?:\/\/)?(www\.)?([a-zA-Z0-9-]+\.)+[A-Za-z]{2,}(:[0-9]+)?(\/\S*)?$'

        # URL management loop
        while true; do
            local menu_options=("Register URL" "" "Save and return" "")
            for i in "${!urls[@]}"; do
                menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 155 10 "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
            [[ -z "$choice" ]] && return 1

            case "$choice" in
                "Register URL")
                    local new_url new_title
                    new_url=$(whiptail --inputbox "Enter URL:" 8 50 3>&1 1>&2 2>&3)
                    [[ $? -ne 0 ]] && continue

                    # validate URL
                    if [[ ! $new_url =~ $url_regex ]]; then
                        whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
                        continue
                    fi

                    new_title=$(whiptail --inputbox "Enter URL title:" 8 50 3>&1 1>&2 2>&3)
                    [[ $? -ne 0 ]] && continue

                    if [[ -z "$new_url" || -z "$new_title" ]]; then
                        whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                        continue
                    fi

                    urls+=("$new_url")
                    titles+=("$new_title")
                    ;;

                "Save and return")
                    # Construct new entry
                    local new_entry="${selected_path}${GS}"
                    for i in "${!urls[@]}"; do
                        new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                    done
                    new_entry="${new_entry%$RS}"

                    # Update URLS_DB
                    local temp_file
                    temp_file=$(mktemp) || return 1
                    if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
                        # Write every line except for selected path to temp file.
                        while IFS= read -r line; do
                            [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                        done < "$URLS_DB" > "$temp_file"
                    fi
                    # Add new entry at the end of the temp file.
                    echo "$new_entry" >> "$temp_file"

                    # Replace original file
                    mv "$temp_file" "$URLS_DB"
                    whiptail --msgbox "URL associations saved successfully!" 8 50 >/dev/tty
                    return 0
                    ;;

                *)
                    # Handle existing URL selection
                    local index="$choice"
                    if [[ ! -v urls[index] ]]; then
                        whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                        continue
                    fi

                    # Submenu for edit/delete
                    local sub_choice
                    sub_choice=$(whiptail --menu "Manage URL" 20 60 10 \
                        "Change values" "" \
                        "Delete URL" "" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                    [[ -z "$sub_choice" ]] && continue

                    case "$sub_choice" in
                        "Change values")
                            local current_url="${urls[index]}"
                            local current_title="${titles[index]}"
                            new_url=$(whiptail --inputbox "Edit URL:" 8 50 "$current_url" 3>&1 1>&2 2>&3)
                            [[ $? -ne 0 ]] && continue

                            # validate URL
                            if [[ ! $new_url =~ $url_regex ]]; then
                                whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
                                continue
                            fi

                            new_title=$(whiptail --inputbox "Edit URL title:" 8 50 "$current_title" 3>&1 1>&2 2>&3)
                            [[ $? -ne 0 ]] && continue

                            if [[ -z "$new_url" || -z "$new_title" ]]; then
                                whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                                continue
                            fi

                            urls[index]="$new_url"
                            titles[index]="$new_title"
                            ;;
                        "Delete URL")
                            unset 'urls[index]'
                            unset 'titles[index]'
                            # Reindex arrays
                            urls=("${urls[@]}")
                            titles=("${titles[@]}")
                            ;;
                    esac
                    ;;
            esac
        done
    }

    dissoc_url_from_note_by_tag() {
        touch "$URLS_DB"
        
        #local URLS_DB="$URLS_DB"
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls

        # Check URL database existence
        if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
            whiptail --msgbox "No associated URLs found. Associate at least one URL and try again." 8 40 >/dev/tty
            return 1
        fi

        # Only the listed (filtered) notes that have URLs.
        nt_filter_notes_with_urls "$@"
        if [[ ${#NT_URL_NOTE_LINES[@]} -eq 0 ]]; then
            whiptail --msgbox "No notes with URLs found among the listed notes." 8 60 >/dev/tty
            return 1
        fi

        # Notes list with __APPLY_GLOB__ / __RESET_GLOB__
        nt_pick_note_line "Select Note to Dissociate URL" "${NT_URL_NOTE_LINES[@]}" || return 1
        local selected_path
        IFS='|' read -r _ selected_path _ <<< "$NT_PICKED_LINE"
        [[ -z "$selected_path" ]] && return 1

        # Load existing URLs
        local urls=()
        local titles=()
        while IFS= read -r line; do
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"

        # URL removal loop
        while true; do
            local menu_options=("Remove URL" "" "Save and return" "")
            for i in "${!urls[@]}"; do
                menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 155 10 \
                "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
            [[ -z "$choice" ]] && continue

            case "$choice" in
                "Remove URL")
                    if [[ ${#urls[@]} -eq 0 ]]; then
                        whiptail --msgbox "No URLs to remove!" 8 50 >/dev/tty
                        continue
                    fi

                    # Create removal submenu
                    local remove_menu=()
                    for i in "${!urls[@]}"; do
                        remove_menu+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                    done

                    local remove_index
                    remove_index=$(whiptail --menu "Select URL to remove" 20 155 10 \
                        "${remove_menu[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                    [[ -z "$remove_index" ]] && continue

                    # Validate and remove selected URL
                    if [[ -v "urls[$remove_index]" ]]; then
                        unset 'urls[$remove_index]'
                        unset 'titles[$remove_index]'
                        urls=("${urls[@]}")  # Reindex array
                        titles=("${titles[@]}")
                    else
                        whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                    fi
                    ;;

                "Save and return")
                    # Prepare new entry
                    local new_entry="${selected_path}${GS}"
                    for i in "${!urls[@]}"; do
                        new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                    done
                    new_entry="${new_entry%$RS}"

                    # Update database
                    local temp_file=$(mktemp) || return 1
                    {
                        # Copy existing entries except current note
                        while IFS= read -r line; do
                            [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                        done < "$URLS_DB"
                        
                        # Add updated entry if URLs remain
                        [[ -n "$new_entry" ]] && echo "$new_entry"
                    } > "$temp_file"

                    mv "$temp_file" "$URLS_DB"
                    whiptail --msgbox "URL associations updated!" 8 50 >/dev/tty
                    return 0
                    ;;

                *)
                    # Ignore URL index selections
                    continue
                    ;;
            esac
        done
    }

    open_url_assoc_to_note_by_tag() {
        touch "$URLS_DB"
        
        #local URLS_DB="$URLS_DB"
        local GS=$'\x1D'  # separates note path and rest
        local US=$'\x1F'  # separates url and url title
        local RS=$'\x1E'  # separates urls            

        # Check if URLs database exists
        if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
            whiptail --msgbox "No associated URLs found. Associate at least one URL and try again." 8 40 >/dev/tty
            return 1
        fi

        local -a scope_lines=("$@")

        while true; do
            # Only the listed (filtered) notes that have URLs.
            nt_filter_notes_with_urls "${scope_lines[@]}"
            if [[ ${#NT_URL_NOTE_LINES[@]} -eq 0 ]]; then
                whiptail --msgbox "No notes with URLs found among the listed notes." 8 60 >/dev/tty
                return 1
            fi

            # Notes list with __APPLY_GLOB__ / __RESET_GLOB__ (Back returns)
            nt_pick_note_line "Select Note to Open URL" "${NT_URL_NOTE_LINES[@]}" || return 0
            local selected_path
            IFS='|' read -r _ selected_path _ <<< "$NT_PICKED_LINE"
            [[ -z "$selected_path" ]] && return 1

            # debug
            #echo "$selected_path"   # broken here already! index is the same!!

            # Extract URLs for selected note
            local urls=()
            local titles=()
            while IFS= read -r line; do
                # Only for the matched line...
                if [[ "$line" == "${selected_path}${GS}"* ]]; then
                    # debug
                    #echo "$line"

                    IFS="$RS" read -ra entries <<< "${line#*$GS}"
                    for entry in "${entries[@]}"; do
                        IFS="$US" read -r url title <<< "$entry"
                        urls+=("$url")
                        titles+=("$title")
                    done
                    break
                fi
            done < "$URLS_DB"

            if [[ ${#urls[@]} -eq 0 ]]; then
                whiptail --msgbox "No URLs found for selected note!" 8 50 >/dev/tty
                continue
            fi

            # URL selection loop
            while true; do
                local url_menu_items=("<< Back" "")
                for i in "${!urls[@]}"; do
                    url_menu_items+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                done

                local choice
                choice=$(whiptail --title "URLs for $selected_path" --menu "Choose URL to open:" \
                    20 155 10 "${url_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || break
                [[ -z "$choice" ]] && break

                if [[ "$choice" == "<< Back" ]]; then
                    break
                elif [[ -n "${urls[$choice]}" ]]; then
                    #eval "$URL_BROWSER" "'${urls[$choice]}'" >/dev/null 2>&1 &
                    nohup "$URL_BROWSER" "${urls[$choice]}" >/dev/null 2>&1 &	# to make sure browser stays open
                fi
            done
        done
    }    

    get_notes_from_filtered2() {
        # Result (chosen NOTES_DB line) is returned in NT_PICKED_LINE.
        NT_PICKED_LINE=""
        if [[ $# -eq 0 ]]; then
            whiptail --msgbox "No notes found in database" 8 50
            return 1
        fi

        nt_pick_note_line "Select note file to copy to clipboard" "$@"
    }

    print_note_from_filtered() {
        print_note_by_tag() {
            print_file_from_do_stuff() {
                # Check if file argument is provided
                if [ -z "$1" ]; then
                    return 1
                fi

                local file_to_print="$1"

                # Check if file exists
                if [ ! -f "$file_to_print" ]; then
                    echo "Error: File '$file_to_print' does not exist." >&2
                    return 1
                fi

                # Get list of printers
                local printers
                printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')            

                # Edge case: no printers found.
                [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

                # Convert printer list into whiptail menu format
                local menu_items=()
                for p in $printers; do
                    menu_items+=("$p" "")
                done

                # Show whiptail menu to select printer
                local selected_printer
                selected_printer=$(whiptail --title "Select Printer" \
                    --menu "Choose a printer:" 20 60 10 \
                    "${menu_items[@]}" 3>&1 1>&2 2>&3)

                # Check if user cancelled
                if [ $? -ne 0 ]; then
                    return 1
                fi

                # Print the file
                if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
                    lpr -P "$selected_printer" "$file_to_print"
                    if [ $? -eq 0 ]; then
                        whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
                    else
                        whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                        return 1
                    fi            
                else
                    :  # do nothing if No or Cancel
                fi
            }

            local selected_path="$1"       
            print_file_from_do_stuff "$selected_path"
        }
        
        if [[ $# -eq 0 ]]; then
            whiptail --msgbox "No notes found in database" 8 50
            return 1
        fi

        # Notes list with __APPLY_GLOB__ / __RESET_GLOB__
        nt_pick_note_line "Select note file to print using printer" "$@" || return 1

        local line___
        line___="$NT_PICKED_LINE"

        local note_path___
        IFS='|' read -r _ note_path___ _ <<< "$line___"     

        print_note_by_tag "$note_path___"         
    }

    add_tag_to_notes_from_filtered() {
        whiptail --title "Attention" --msgbox \
"Step 1: Select tag to add.
Step 2: Select multiple notes to add the tag to.

Tag you have chosen will be added to the selected notes." 10 60
        local notes_db="${NOTES_DB:-}"
        local tags_db="${NOTES_TAGS_DB:-}"
        local page_size="${PAGE_SIZE:-30}"

        if [[ -z $notes_db || ! -r $notes_db || ! -w $notes_db ]]; then
            printf 'ERROR: NOTES_DB must be set and writable: %s\n' "${notes_db:-<unset>}" >&2
            return 1
        fi

        if [[ -z $tags_db || ! -r $tags_db ]]; then
            printf 'ERROR: NOTES_TAGS_DB must be set and readable: %s\n' "${tags_db:-<unset>}" >&2
            return 1
        fi

        if ! command -v whiptail >/dev/null 2>&1; then
            printf 'ERROR: whiptail is not installed.\n' >&2
            return 1
        fi

        if [[ $# -eq 0 ]]; then
            printf 'ERROR: pass filtered note lines as arguments.\n' >&2
            return 1
        fi

        local -a all_notes=("$@")
        local total="${#all_notes[@]}"

        (( total == 0 )) && {
            whiptail --msgbox "No filtered notes found. Add a note and try again." 8 50
            return 1
        }

        local page_count=$(( (total + page_size - 1) / page_size ))

        local tmp_sel=""
        local tmp_db=""
        trap 'rm -f -- "$tmp_sel" "$tmp_db"' RETURN

        local -a tag_menu=()
        local tag
        while IFS= read -r tag || [[ -n $tag ]]; do
            [[ -n $tag ]] || continue
            tag_menu+=("$tag" "")
        done < "$tags_db"

        if (( ${#tag_menu[@]} == 0 )); then
            whiptail --msgbox "No note tags found. Add a tag and try again." 8 50
            return 1
        fi

        # Tag list with __FILTER__ / __RESET_FILTER__ (same large box as __CHANGE_TAG__).
        # [NO TAG] is not offered: it is not a real tag that could be added to notes.
        local selected_tag
        nt_pick_tag "Choose Tag" "Choose the tag to add to the selected notes" 0 || return 1
        selected_tag="$NT_PICKED_TAG"

        local -A selected_paths=()
        local p

        while :; do
            # Notes checklist with __APPLY_GLOB__ / __RESET_GLOB__ items.
            nt_pick_notes_checklist "Select notes" "add_tag" "Add tag to selected notes" "${all_notes[@]}" || return 1

            selected_paths=()
            for p in "${NT_CHECKED_PATHS[@]}"; do
                selected_paths["$p"]=1
            done

            local selected_count="${#selected_paths[@]}"
            (( selected_count == 0 )) && continue

            if ! whiptail --title "Confirm" \
                --yesno "Add tag \"$selected_tag\" to $selected_count selected note(s)?" \
                10 70; then
                NT_PRESELECT_PATHS=("${NT_CHECKED_PATHS[@]}")
                continue
            fi

                tmp_sel=$(mktemp "${TMPDIR:-/tmp}/notes_sel.XXXXXX") || return 1
                tmp_db=$(mktemp "${notes_db}.XXXXXX") || { rm -f -- "$tmp_sel"; return 1; }

                {
                    local p
                    for p in "${!selected_paths[@]}"; do
                        printf '%s\n' "$p"
                    done
                } > "$tmp_sel"

                awk -F'|' -v OFS='|' -v tag="$selected_tag" -v selfile="$tmp_sel" '
                    BEGIN {
                        while ((getline p < selfile) > 0) sel[p] = 1
                        close(selfile)
                    }

                    function has_tag(tags, tag,   n, a, i) {
                        if (tags == "") return 0
                        n = split(tags, a, /,/)
                        for (i = 1; i <= n; i++) {
                            if (a[i] == tag) return 1
                        }
                        return 0
                    }

                    function append_tag(tags, tag,   n, a, i, out) {
                        if (tags == "") return tag
                        n = split(tags, a, /,/)
                        out = ""
                        for (i = 1; i <= n; i++) {
                            if (a[i] == "" || a[i] == tag) continue
                            out = (out == "" ? a[i] : out "," a[i])
                        }
                        return (out == "" ? tag : out "," tag)
                    }

                    {
                        if (sel[$2] && !has_tag($3, tag)) {
                            $3 = append_tag($3, tag)
                        }
                        print
                    }
                ' "$notes_db" > "$tmp_db" || { rm -f -- "$tmp_sel" "$tmp_db"; return 1; }

                mv -- "$tmp_db" "$notes_db" || { rm -f -- "$tmp_sel" "$tmp_db"; return 1; }
                rm -f -- "$tmp_sel"
                tmp_sel=""

                whiptail --msgbox "Tag \"$selected_tag\" added to selected notes." 8 60
                return 0
        done
    }

    lookup_info_by_tag() {
        if [[ $# -eq 0 ]]; then
            whiptail --title "Alert" \
                --msgbox "No matching notes found. Add at least one note and try again." 8 40
            return 1
        fi

        # Each argument has the format:
        # note title|/path/to/note/note.txt|tag1,tag2,another tag|rest
        local picked_title picked_path picked_tags selected_tags
        while true; do
            # Notes list with __APPLY_GLOB__ / __RESET_GLOB__
            nt_pick_note_line "Lookup notes" "$@" || return 1
            IFS='|' read -r picked_title picked_path picked_tags _ <<< "$NT_PICKED_LINE"

            # Remove the display brackets.
            selected_tags="${picked_tags#[}"
            selected_tags="${selected_tags%]}"

            whiptail \
                --title "Note Information" \
                --msgbox "$(printf \
                    'Note path:\n%s\n\nNote title:\n%s\n\nTags:\n%s' \
                    "$picked_path" \
                    "$picked_title" \
                    "$selected_tags"
                )" \
                20 90
        done
    }

    # Initial message
    whiptail --title "Do Stuff by Tag" --msgbox "The following advanced feature lets you narrow down note entries \
by their associated tag (or [NO TAG] to work with the notes that have no tag) and do stuff with them. You can add a new note, edit note or open associated ebooks. You can also associate a note to multiple projects.\n\n\
In the filtered view, __CHANGE_TAG__ filters the notes by a different tag and __REVERT_TAG__ goes back to the tag you chose at the start. Lists of notes and projects can be narrowed down with __APPLY_GLOB__ / __RESET_GLOB__.\n\n\
After creating a new note, you can choose to associate it to a project file. Afterwards, you can do stuff with it from Manage Goals section such as View Note or Open ebooks." 22 76

    local chosen_tag original_tag
    nt_pick_tag "Do stuff by Tag" "Choose a tag" 1 || return 1
    chosen_tag="$NT_PICKED_TAG"
    original_tag="$chosen_tag"

    while :; do
        # Globs are per action: start every action with no glob filters.
        NT_CURRENT_TAG="$chosen_tag"
        NT_NOTE_GLOB=""
        NT_PROJECT_GLOB=""

        # Update $FILTERED_NOTES_BY_TAG array (also picks up newly added notes/tags).
        filter_notes_by_tag "$chosen_tag"

        local no_tag_mode=0
        [[ "$chosen_tag" == "$NT_NO_TAG_LABEL" ]] && no_tag_mode=1

        local add_note_label="Add note with same tag"
        local add_tag_label="Add another tag to notes"
        if (( no_tag_mode )); then
            add_note_label="Add note with no tag"
            add_tag_label="Add tag to notes"
        fi

        local status_text="Current tag: ${chosen_tag}"
        [[ "$chosen_tag" != "$original_tag" ]] && status_text+="   (original tag: ${original_tag})"
        status_text+="   |   ${#FILTERED_NOTES_BY_TAG[@]} note(s)"

        local choice
        choice=$(whiptail --title "Filtered by tag: $chosen_tag" --menu "${status_text}\n\nSelect action:" \
            24 100 13 \
            "__CHANGE_TAG__" "Filter the notes by a different tag" \
            "__REVERT_TAG__" "Filter by the original tag again (${original_tag})" \
            "Lookup" "" "$add_note_label" "" "Copy note content to clipboard" "" "Edit note" "" "Open associated ebook" "" "Associate URL to note" "" \
            "Dissociate URL from note" "" "Open URL" "" "Print note using printer" "" "Associate note to project" "" "$add_tag_label" "" \
            3>&1 1>&2 2>&3) || return  # Explicit cancellation handling

        # Everything except changing the tag and adding a new note needs at least one filtered note.
        case "$choice" in
            "__CHANGE_TAG__"|"__REVERT_TAG__"|"$add_note_label") ;;
            *)
                if [[ ${#FILTERED_NOTES_BY_TAG[@]} -eq 0 ]]; then
                    whiptail --title "Attention" --msgbox \
                        "No notes found. Create at least one note file and try again." 10 60
                    continue
                fi
                ;;
        esac

        case "$choice" in
            "__CHANGE_TAG__")
                local new_tag
                nt_pick_tag "Do stuff by Tag" "Choose a different tag to filter the notes by (current: ${chosen_tag})" 1 || continue
                new_tag="$NT_PICKED_TAG"
                chosen_tag="$new_tag"
                ;;
            "__REVERT_TAG__")
                if [[ "$chosen_tag" == "$original_tag" ]]; then
                    whiptail --title "Attention" --msgbox "Already filtering by the original tag: ${original_tag}" 8 60
                else
                    chosen_tag="$original_tag"
                fi
                ;;
            "Lookup")
                lookup_info_by_tag "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Add note with same tag"|"Add note with no tag")
                if (( no_tag_mode )); then
                    add_note || return 1
                else
                    add_note "$chosen_tag" || return 1
                fi
                [[ -n "$note_path" ]] && associate_new_note_to_project "$note_path"
                ;;
            "Copy note content to clipboard")
                get_notes_from_filtered2 "${FILTERED_NOTES_BY_TAG[@]}" || continue
                local line___
                line___="$NT_PICKED_LINE"
                local note_path___
                IFS='|' read -r _ note_path___ _ <<< "$line___"
                # Save $note_path to xclip
                cat "$note_path___" | xclip -sel clip
                whiptail --msgbox "Copied to clipboard!" 8 50 >/dev/tty
                ;;
            "Edit note")
                list_notes_from_filtered "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Open associated ebook")
                open_note_ebook_page_from_filtered "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Associate URL to note")
                assoc_url_to_note_by_tag "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Dissociate URL from note")
                dissoc_url_from_note_by_tag "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Open URL")
                open_url_assoc_to_note_by_tag "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Associate note to project")
                associate_notes_by_tag_to_project "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Print note using printer")
                print_note_from_filtered "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
            "Add another tag to notes"|"Add tag to notes")
                add_tag_to_notes_from_filtered "${FILTERED_NOTES_BY_TAG[@]}"
                ;;
        esac
    done
}

# The following code section is about opening an ebook file in global list NOTES_EBOOKS_DB.
open_ebook_note_from_global_list() {
    # Initial message
    whiptail --title "Open eBook File From Global List" \
         --msgbox "This feature allows you to open an ebook file from global list.\n\nNarrow the list down with __APPLY_GLOB__ / __RESET_GLOB__ (glob on the full ebook file path or on the file name alone)." 12 78

    # Check if the database file exists
    if [[ ! -f "$NOTES_EBOOKS_DB" || ! -s "$NOTES_EBOOKS_DB" ]]; then
        whiptail --title "Attention" --msgbox "No ebooks found. Add at least one note and associate at least one ebook and try again." 10 50 >/dev/tty
        return 1
    fi

    # Same list as the Manage eBooks lists: 155 wide, 50 items per page,
    # __APPLY_GLOB__ / __RESET_GLOB__ on top. The lines have no tags.
    EB_SRC_FILE="$NOTES_EBOOKS_DB"
    EB_NO_TAGS=1
    ebooks_filter_reset
    EB_PATH_MAX=120

    local rc=0
    ebooks_pick_file "Open eBook File From Global List" "Choose an eBook to open" || rc=1
    EB_NO_TAGS=0
    (( rc == 0 )) || return 1

    local selected_line="$EB_SELECTED_LINE"
    if [[ -n "$selected_line" ]]; then
        open_evince "$selected_line"
    fi
}

delete_notes() {
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --title "Attention" --msgbox "No notes found." 8 40 >/dev/tty
        return 1
    fi

    # No glob is asked at the start: the list has __APPLY_GLOB__ (note title
    # only), __RESET_GLOB__, __FILTER_BY_TAG__ (with [NO TAG] and [ANY TAG])
    # and __RESET_FILTER__ items. Note paths (110 chars max) and shortened
    # tags are shown; __proceed__ is at the top.
    np_reset
    NP_SRC_FILE="$NOTES_DB"
    NP_SHOW_PATH=1
    NP_PATH_MAX=110
    NP_PROCEED="__proceed__"

    np_pick_notes_checklist "Delete Notes" "Select notes to delete" "Proceed to deletion (@N@ note(s) listed)" || return 1

    # Selected notes, in database order.
    local -a del_paths=()
    local p
    while IFS='|' read -r _ p _; do
        [[ -n "$p" && "${NP_SEL["$p"]:-0}" == "1" ]] && del_paths+=("$p")
    done < "$NOTES_DB"

    if (( ${#del_paths[@]} == 0 )); then
        return 1
    fi

    # Notes that are still associated with a project cannot be deleted.
    local -a ok_paths=() conflicts=() preview=()
    local proj_path
    for p in "${del_paths[@]}"; do
        proj_path=""
        if ! proj_path="$(note_safe_to_delete "$p")"; then
            if [[ -n "$proj_path" ]]; then
                conflicts+=("$(eb_trunc_path "$p" 110)  ->  project '${proj_path}'")
                continue
            fi
        fi
        ok_paths+=("$p")
    done

    if (( ${#conflicts[@]} > 0 )); then
        local c_msg="These notes are still associated with a project and cannot be deleted:\n\n"
        c_msg+="$(np_preview_list conflicts | sed 's/$/\\n/' | tr -d '\n')"
        c_msg+="\nPlease dissociate these notes from project first!"
        whiptail --scrolltext --title "Attention" --msgbox "$c_msg" 22 140
        return 1
    fi

    # Confirm deletion (first 10 notes, then "(... N more)").
    for p in "${ok_paths[@]}"; do
        preview+=("$(eb_trunc_path "$p" 110)")
    done
    local msg="The following ${#ok_paths[@]} note(s) will be deleted:\n\n"
    msg+="$(np_preview_list preview | sed 's/$/\\n/' | tr -d '\n')"

    if whiptail --title "Confirm Deletion" --yesno "$msg" 24 125; then
        local -A del=()
        for p in "${ok_paths[@]}"; do
            del["$p"]=1
            # actual file deletion.
            [[ -f "$p" ]] && rm -f -- "$p"
        done

        # remove from database.
        local tmp line np
        tmp=$(mktemp) || return 1
        while IFS= read -r line || [[ -n "$line" ]]; do
            IFS='|' read -r _ np _ <<< "$line"
            [[ -n "$np" && -n "${del["$np"]+x}" ]] && continue
            printf '%s\n' "$line"
        done < "$NOTES_DB" > "$tmp"
        mv "$tmp" "$NOTES_DB"

        whiptail --title "Deletion Complete" --msgbox "Selected notes have been deleted." 10 40
    fi
}

delete_global_tag_of_notes() {
    # Check if tags database exists and isn't empty
    if [[ ! -f "$NOTES_TAGS_DB" || ! -s "$NOTES_TAGS_DB" ]]; then
        whiptail --msgbox "There are no registered tags." 10 50 >/dev/tty
        return 1
    fi

    # MAYBE DON'T NEED THIS.
    # Check if notes database exists and isn't empty
    # if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
	# whiptail --msgbox "There are no registered notes." 10 50 >/dev/tty
	# return 1
    # fi

    # FIX: PAGINATE SELECTED_TAG.
    # Read all tags into an array
    mapfile -t all_tags < "$NOTES_TAGS_DB"
    local current_page=0
    local tags_per_page=50
    local tag_filter=""     # literal substring filter set with __FILTER__

    while true; do
        # after deletion in the menu, reload from list from database file.
        mapfile -t all_tags < "$NOTES_TAGS_DB"

        if [[ ${#all_tags[@]} -eq 0 ]]; then
            whiptail --msgbox "There are no registered tags." 10 50 >/dev/tty
            return 1
        fi

        # Keep only the tags that contain the filter text (literal substring,
        # case insensitive).
        local shown_tags=() tg
        for tg in "${all_tags[@]}"; do
            [[ -z "$tg" ]] && continue
            if [[ -z "$tag_filter" || "${tg,,}" == *"${tag_filter,,}"* ]]; then
                shown_tags+=("$tg")
            fi
        done

        local total_pages=$(( (${#shown_tags[@]} + tags_per_page - 1) / tags_per_page ))
        (( total_pages < 1 )) && total_pages=1
        (( current_page >= total_pages )) && current_page=$(( total_pages - 1 ))
        (( current_page < 0 )) && current_page=0

        # Calculate start and end indices for current page
        local start=$((current_page * tags_per_page))
        local end=$((start + tags_per_page - 1))

        # Get tags for current page
        local page_tags=("${shown_tags[@]:$start:$tags_per_page}")

        # Prepare whiptail menu options
        local menu_options=(
            "__FILTER__" "Filter tags by text (literal substring)${tag_filter:+   [filter: $tag_filter]}"
            "__RESET_FILTER__" "Reset tag filter"
        )
        for tag in "${page_tags[@]}"; do
            menu_options+=("$tag" "")
        done

        # Add navigation options if needed
        if [[ $start -gt 0 ]]; then
            menu_options+=("< Previous Page" "")
        fi
        if [[ $end -lt $((${#shown_tags[@]} - 1)) ]]; then
            menu_options+=("> Next Page" "")
        fi

        # Box big enough for 50 tags + filter / navigation items (capped to the terminal height).
        local dlg_h dlg_l rows cols
        read -r rows cols < <(stty size </dev/tty 2>/dev/null)
        [[ "$rows" =~ ^[0-9]+$ ]] || rows=0
        dlg_l=$(( tags_per_page + 4 ))
        dlg_h=$(( dlg_l + 11 ))
        (( rows > 0 && dlg_h > rows )) && dlg_h=$rows
        (( dlg_h < 14 )) && dlg_h=14
        dlg_l=$(( dlg_h - 11 ))

        # Show tag selection menu
        local selected_tag
        selected_tag=$(whiptail --menu "Choose a tag to delete (Page $((current_page + 1))/${total_pages})\n\nFilter: ${tag_filter:-(none)}  |  ${#shown_tags[@]}/${#all_tags[@]} tag(s)" \
            "$dlg_h" 100 "$dlg_l" "${menu_options[@]}" 3>&1 1>&2 2>&3 >/dev/tty)

        [[ $? -ne 0 ]] && return 1  # User canceled

        # Handle filter and navigation
        if [[ "$selected_tag" == "__FILTER__" ]]; then
            local new_filter
            new_filter=$(whiptail --title "__FILTER__" --inputbox \
"Enter text to narrow down the tag list.\nTags that contain this text are shown (literal substring match, case insensitive; no wildcards).\nEmpty input removes the filter." \
                12 80 "$tag_filter" 3>&1 1>&2 2>&3 >/dev/tty) && tag_filter="$new_filter"
            current_page=0
            continue
        elif [[ "$selected_tag" == "__RESET_FILTER__" ]]; then
            tag_filter=""
            current_page=0
            continue
        elif [[ "$selected_tag" == "< Previous Page" ]]; then
            ((current_page--))
            continue
        elif [[ "$selected_tag" == "> Next Page" ]]; then
            ((current_page++))
            continue
        else
            # User selected a tag to delete
            # Add your tag deletion logic here

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
                for title in "${conflicts[@]:0:10}"; do
                    conflict_msg+="- $title\n"
                done

                (( ${#conflicts[@]} > 10 )) && conflict_msg+="and more..."

                conflict_msg+="\n\nPlease dissociate the tag from these notes first."
                whiptail --msgbox "$conflict_msg" 20 80
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
        fi
    done
    # END FIX.
}

URLS_DB="$(pwd)/urls/urls.db"
mkdir -p "$(pwd)/urls"

# Line format for URLS_DB is:
#/path/to/note/some note.txt${GS}https://some url/url.html${US}url title${RS}https://some other/url2.html${US}other url title

assoc_url_to_note() {
    touch "$URLS_DB"
	
    #local NOTES_DB="$NOTES_DB"
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls

    # Extract note paths from NOTES_DB
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 >/dev/tty
        return 1
    fi

#    # Read note paths
#    local note_paths=()
#    while IFS='|' read -r _ path _ _; do
#        note_paths+=("$path")
#    done < "$NOTES_DB"
#
#    if [[ ${#note_paths[@]} -eq 0 ]]; then
#        whiptail --msgbox "No notes found in database!" 8 50 >/dev/tty
#        return 1
#    fi
#
#    # Select note path
#    local menu_items=()
#    for path in "${note_paths[@]}"; do
#        menu_items+=("$path" "")
#    done

    # Tag selection at start: same way as in 'Do Stuff by Tag'.
    np_choose_start_tag || return 1

    # Notes list: shortened tags, 155 wide, 50 notes per page.
    np_reset
    np_pick_note_for_tag "Select Note to Associate URL to" "Choose the note to associate URLs to" 0 "$NP_START_TAG" || return 1
    local selected_path
    IFS='|' read -r _ selected_path _ <<< "$NP_SELECTED_LINE"
    [[ -z "$selected_path" ]] && return 1

    #local selected_path
    #selected_path=$(whiptail --menu "Select a note" 20 150 10 "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    #[[ -z "$selected_path" ]] && return 1

    # Load existing URLs
    local urls=()
    local titles=()
    if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"
    fi

    local url_regex='^(https?:\/\/)?(www\.)?([a-zA-Z0-9-]+\.)+[A-Za-z]{2,}(:[0-9]+)?(\/\S*)?$'

    # URL management loop
    while true; do
        local menu_options=("Register URL" "" "Save and return" "")
        for i in "${!urls[@]}"; do
            menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
        done

        local choice
        choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 155 10 "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        [[ -z "$choice" ]] && return 1

        case "$choice" in
            "Register URL")
                local new_url new_title
                new_url=$(whiptail --inputbox "Enter URL:" 8 50 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue

		# validate URL
		if [[ ! $new_url =~ $url_regex ]]; then
		    whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
		    continue
		fi

                new_title=$(whiptail --inputbox "Enter URL title:" 8 50 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue

                if [[ -z "$new_url" || -z "$new_title" ]]; then
                    whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                    continue
                fi

                urls+=("$new_url")
                titles+=("$new_title")
                ;;

            "Save and return")
                # Construct new entry
                local new_entry="${selected_path}${GS}"
                for i in "${!urls[@]}"; do
                    new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                done
                new_entry="${new_entry%$RS}"

                # Update URLS_DB
                local temp_file
                temp_file=$(mktemp) || return 1
                if [[ -f "$URLS_DB" && -s "$URLS_DB" ]]; then
					# Write every line except for selected path to temp file.
                    while IFS= read -r line; do
                        [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                    done < "$URLS_DB" > "$temp_file"
                fi
                # Add new entry at the end of the temp file.
                echo "$new_entry" >> "$temp_file"

                # Replace original file
                mv "$temp_file" "$URLS_DB"
                whiptail --msgbox "URL associations saved successfully!" 8 50 >/dev/tty
                return 0
                ;;

            *)
                # Handle existing URL selection
                local index="$choice"
                if [[ ! -v urls[index] ]]; then
                    whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                    continue
                fi

                # Submenu for edit/delete
                local sub_choice
                sub_choice=$(whiptail --menu "Manage URL" 20 60 10 \
                    "Change values" "" \
                    "Delete URL" "" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                [[ -z "$sub_choice" ]] && continue

                case "$sub_choice" in
                    "Change values")
                        local current_url="${urls[index]}"
                        local current_title="${titles[index]}"
                        new_url=$(whiptail --inputbox "Edit URL:" 8 50 "$current_url" 3>&1 1>&2 2>&3)
                        [[ $? -ne 0 ]] && continue

			# validate URL
                        if [[ ! $new_url =~ $url_regex ]]; then
                            whiptail --msgbox "Invalid URL format! Please enter a valid URL." 8 50 >/dev/tty
                            continue
                        fi

                        new_title=$(whiptail --inputbox "Edit URL title:" 8 50 "$current_title" 3>&1 1>&2 2>&3)
                        [[ $? -ne 0 ]] && continue

                        if [[ -z "$new_url" || -z "$new_title" ]]; then
                            whiptail --msgbox "URL and title cannot be empty!" 8 50 >/dev/tty
                            continue
                        fi

                        urls[index]="$new_url"
                        titles[index]="$new_title"
                        ;;
                    "Delete URL")
                        unset 'urls[index]'
                        unset 'titles[index]'
                        # Reindex arrays
                        urls=("${urls[@]}")
                        titles=("${titles[@]}")
                        ;;
                esac
                ;;
        esac
    done
}

dissoc_url_from_note() {
    touch "$URLS_DB"
	
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls

    # Check URL database existence
    if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
        whiptail --msgbox "No associated URLs found. Associate at least one URL and try again." 8 40 >/dev/tty
        return 1
    fi

    # Tag selection at start: same way as in 'Do Stuff by Tag'.
    np_choose_start_tag || return 1

    # Notes list (only notes with at least one URL): shortened tags, 155 wide,
    # 50 notes per page.
    np_reset
    np_pick_note_for_tag "Select Note to Dissociate URL" "Choose the note to remove URLs from" 1 "$NP_START_TAG" || return 1
    local selected_path
    IFS='|' read -r _ selected_path _ <<< "$NP_SELECTED_LINE"
    [[ -z "$selected_path" ]] && return 1

    #local selected_path
    #selected_path=$(whiptail --menu "Select a note to dissociate URLs" 20 150 10 \
    #    "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
    #[[ -z "$selected_path" ]] && return 1

    # Load existing URLs
    local urls=()
    local titles=()
    while IFS= read -r line; do
        if [[ "$line" == "${selected_path}${GS}"* ]]; then
            IFS="$RS" read -ra entries <<< "${line#*$GS}"
            for entry in "${entries[@]}"; do
                IFS="$US" read -r url title <<< "$entry"
                urls+=("$url")
                titles+=("$title")
            done
            break
        fi
    done < "$URLS_DB"

    # URL removal loop
    while true; do
        local menu_options=("Remove URL" "" "Save and return" "")
        for i in "${!urls[@]}"; do
            menu_options+=("$i" "${urls[i]} - ${titles[i]:0:50}")
        done

        local choice
        choice=$(whiptail --menu "Manage URLs for ${selected_path}" 20 155 10 \
            "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        [[ -z "$choice" ]] && continue

        case "$choice" in
            "Remove URL")
                if [[ ${#urls[@]} -eq 0 ]]; then
                    whiptail --msgbox "No URLs to remove!" 8 50 >/dev/tty
                    continue
                fi

                # Create removal submenu
                local remove_menu=()
                for i in "${!urls[@]}"; do
                    remove_menu+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                done

                local remove_index
                remove_index=$(whiptail --menu "Select URL to remove" 20 155 10 \
                    "${remove_menu[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || continue
                [[ -z "$remove_index" ]] && continue

                # Validate and remove selected URL
                if [[ -v "urls[$remove_index]" ]]; then
                    unset 'urls[$remove_index]'
                    unset 'titles[$remove_index]'
                    urls=("${urls[@]}")  # Reindex array
                    titles=("${titles[@]}")
                else
                    whiptail --msgbox "Invalid selection!" 8 50 >/dev/tty
                fi
                ;;

            "Save and return")
                # Prepare new entry
                local new_entry="${selected_path}${GS}"
                for i in "${!urls[@]}"; do
                    new_entry+="${urls[i]}${US}${titles[i]}${RS}"
                done
                new_entry="${new_entry%$RS}"

                # Update database
                local temp_file=$(mktemp) || return 1
                {
                    # Copy existing entries except current note
                    while IFS= read -r line; do
                        [[ "$line" != "${selected_path}${GS}"* ]] && echo "$line"
                    done < "$URLS_DB"
                    
                    # Add updated entry if URLs remain
                    [[ -n "$new_entry" ]] && echo "$new_entry"
                } > "$temp_file"

                mv "$temp_file" "$URLS_DB"
                whiptail --msgbox "URL associations updated!" 8 50 >/dev/tty
                return 0
                ;;

            *)
                # Ignore URL index selections
                continue
                ;;
        esac
    done
}

#URL_BROWSER='google-chrome'

open_url_assoc_to_note() {
    touch "$URLS_DB"
	
    #local URLS_DB="$URLS_DB"
    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls            

    # Check if URLs database exists
    if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
        whiptail --msgbox "No associated URLs found. Associate at least one URL and try again." 8 40 >/dev/tty
        return 1
    fi

    # Tag selection at start: same way as in 'Do Stuff by Tag'.
    np_choose_start_tag || return 1
    np_reset

    while true; do
        # Notes list (only notes with at least one URL): shortened tags,
        # 155 wide, 50 notes per page. Back leaves.
        np_pick_note_for_tag "Select Note to Open URL" "Choose a note to open its URLs" 1 "$NP_START_TAG" || return 1
        local selected_path
        IFS='|' read -r _ selected_path _ <<< "$NP_SELECTED_LINE"
        [[ -z "$selected_path" ]] && return 1

        # Extract URLs for selected note
        local urls=()
        local titles=()
        while IFS= read -r line; do
			# Only for the matched line...
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"

        if [[ ${#urls[@]} -eq 0 ]]; then
            whiptail --msgbox "No URLs found for selected note!" 8 50 >/dev/tty
            continue
        fi

        # URL selection loop
        while true; do
            local url_menu_items=("<< Back" "")
            for i in "${!urls[@]}"; do
                url_menu_items+=("$i" "${urls[i]} - ${titles[i]:0:50}")
            done

            local choice
            choice=$(whiptail --title "URLs for $selected_path" --menu "Choose URL to open:" \
                20 155 10 "${url_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || break
            [[ -z "$choice" ]] && break

            if [[ "$choice" == "<< Back" ]]; then
                break
            elif [[ -n "${urls[$choice]}" ]]; then
                #eval "$URL_BROWSER" "'${urls[$choice]}'" >/dev/null 2>&1 &
                nohup "$URL_BROWSER" "${urls[$choice]}" >/dev/null 2>&1 &	# to make sure browser stays open
            fi
        done
    done
}

# allows print note files from main manage notes menu.
print_notes() {
    print_file_from_print_notes() {
        # Check if file argument is provided
        if [ -z "$1" ]; then
            return 1
        fi

        local file_to_print="$1"

        # Check if file exists
        if [ ! -f "$file_to_print" ]; then
            echo "Error: File '$file_to_print' does not exist." >&2
            return 1
        fi

        # Get list of printers
        local printers
        printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')

        # Edge case: no printers found.
        [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

        # Convert printer list into whiptail menu format
        local menu_items=()
        for p in $printers; do
            menu_items+=("$p" "")
        done

        # Show whiptail menu to select printer
        local selected_printer
        selected_printer=$(whiptail --title "Select Printer" \
            --menu "Choose a printer:" 20 60 10 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3)

        # Check if user cancelled
        if [ $? -ne 0 ]; then
            return 1
        fi

        # Print the file
        if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
            lpr -P "$selected_printer" "$file_to_print"
            if [ $? -eq 0 ]; then
                whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
            else
                whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                return 1
            fi            
        else
            :  # do nothing if No or Cancel
        fi
    }

    get_note_title_from_note_path_() {
        local note_path="$1"
        local note_title

        note_title=$(awk -F'|' -v path="$note_path" '
            $2 == path {
                print $1
                exit
            }
        ' "$NOTES_DB")

        echo "$note_title"
    }

    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

    # The list has __FILTER_BY_TAG__ / __RESET_FILTER__ / __APPLY_GLOB__ /
    # __RESET_GLOB__ items (no tag is asked at the start).
    np_reset
    NP_SRC_FILE="$NOTES_DB"

    while true; do
        np_pick_note "Print Note" "Choose a note to view or print" || break

        local selected_path
        IFS='|' read -r _ selected_path _ <<< "$NP_SELECTED_LINE"
        [[ -z "$selected_path" ]] && continue
        
        local action
        action=$(whiptail --title "Actions" --menu "Choose an action:" 10 40 2 \
                "View Note" "" \
                "Print Note" "" \
                3>&1 1>&2 2>&3) || :        

        case "$action" in
            "View Note")

                local tmpfile
                tmpfile=$(mktemp)
                fold -s -w 145 "$selected_path" > "$tmpfile"
                # NOTE: NOTE_TITLE IS NOT EXTRACTED YET! -- FIXED?
                local note_title="$(get_note_title_from_note_path_ "$selected_path")"
                dialog --no-mouse --exit-label "Back" --title "$note_title" --textbox "$tmpfile" 35 150                
                rm -f "$tmpfile"
                clear
                ;;
            "Print Note")
                print_file_from_print_notes "$selected_path"
                ;;
            *)
                :
                ;;

        esac        
    done
}

add_note_tag_main() {
    local new_tag
    new_tag=$(whiptail --title "Add New Note Tag" --inputbox "Enter new tag:" 8 40 3>&1 1>&2 2>&3 </dev/tty) || return 1

    # ANY TAG is banned word - ban it case-insensitive?
    [[ "$new_tag" == "ANY TAG" ]] && whiptail --title "Invalid Tag" --msgbox "'ANY TAG' is not allowed as a tag name. Try again." 8 40 && return 1

    # FIX: DELETE BANNED CHARS - MORE EFFICIENT.
    new_tag=${new_tag//[|,#:;]/}
    # END FIX.

    if [ -n "$new_tag" ]; then
        # FIX: CHECK FOR DUPLICATE BEFORE ADDING TAG.
        # Check if tag already exists
        if grep -qiFx "$new_tag" "$NOTES_TAGS_DB"; then
            whiptail --msgbox "Tag '${new_tag}' already exists!" 8 40   # case-insensitive
            return 1
        else
            # Add to global tags list
            echo "$new_tag" >> "$NOTES_TAGS_DB"
            sort -u "$NOTES_TAGS_DB" -o "$NOTES_TAGS_DB"    # sort notes_tags_db file
            whiptail --msgbox "Tag '${new_tag}' has been added to notes tags db." 8 40
            return 0
        fi
    fi

    return 1
}

add_note_tag_menu() {
    local subject=""
    local topic=""
    local tag_name=""
    local choice

    while true; do
        # Construct tag name
        if [[ -n "$subject" && -n "$topic" ]]; then
            tag_name="${subject}->${topic}"
        else
            tag_name="$subject"
        fi

        # Silently remove banned characters
        tag_name="${tag_name//[|,#:;]/}"

        choice=$(
            whiptail \
                --title "Add Note Tag" \
                --menu "Create a new tag (formatted 'subject->topic'):" \
                18 70 8 \
                "Subject" "${subject:-<not set>}" \
                "Topic" "${topic:-<not set>}" \
                "Tag Name" "'${tag_name}'" \
                "Save" "" \
                3>&1 1>&2 2>&3
        ) || return 1

        case "$choice" in
            Subject)
                subject=$(
                    whiptail \
                        --title "Subject" \
                        --inputbox "Enter subject:" \
                        10 60 "$subject" \
                        3>&1 1>&2 2>&3
                ) || continue
                ;;

            Topic)
                topic=$(
                    whiptail \
                        --title "Topic" \
                        --inputbox "Enter topic (optional):" \
                        10 60 "$topic" \
                        3>&1 1>&2 2>&3
                ) || continue
                ;;

            Save)
                # Reconstruct again to ensure latest values
                if [[ -n "$subject" && -n "$topic" ]]; then
                    tag_name="${subject}->${topic}"
                else
                    tag_name="$subject"
                fi

                # Remove banned characters
                tag_name="${tag_name//[|,#:;]/}"

                # Trim whitespace
                tag_name="$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$tag_name")"

                if [[ -z "$tag_name" ]]; then
                    whiptail \
                        --title "Error" \
                        --msgbox "Tag Name cannot be empty." \
                        8 40
                    continue
                fi

                if [[ "$tag_name" == "ANY TAG" ]]; then
                    whiptail \
                        --title "Error" \
                        --msgbox "'ANY TAG' is a reserved tag name." \
                        8 45
                    continue
                fi

                if grep -Fxq -- "$tag_name" "$NOTES_TAGS_DB"; then
                    whiptail \
                        --title "Duplicate" \
                        --msgbox "Tag already exists." \
                        8 40
                    continue
                fi

                {
                    cat "$NOTES_TAGS_DB"
                    printf '%s\n' "$tag_name"
                } | sort -u > "${NOTES_TAGS_DB}.tmp" &&
                    mv "${NOTES_TAGS_DB}.tmp" "$NOTES_TAGS_DB"

                whiptail \
                    --title "Success" \
                    --msgbox "Tag added:\n\n$tag_name" \
                    10 50

                return 0
                ;;
        esac
    done
}

lookup_note_tags() {
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --title "Attention" --msgbox "No notes found. Add at least one note and try again." 8 60
        return 1
    fi

    # Tag selection at start: 150 wide, 50 tags per page, __FILTER__ /
    # __RESET_FILTER__ (literal substring). [NO TAG] and [ANY TAG] are always there.
    local -a all_tags=() pinned=("[NO TAG]" "Look up notes with no tag associated" "[ANY TAG]" "Look up all notes")
    local t
    if [[ -f "$NOTES_TAGS_DB" ]]; then
        while IFS= read -r t || [[ -n "$t" ]]; do
            [[ -n "$t" ]] && all_tags+=("$t")
        done < "$NOTES_TAGS_DB"
    fi

    local chosen_tag="" first=1 rc tag_ok=0
    local info_title info_path info_tags
    local tag_menu_filter=""   # __FILTER__ text, kept while the tag menu is reopened

    np_reset
    NP_SRC_FILE="$NOTES_DB"
    NP_NO_TAG_FILTER=1      # the tag is chosen with __CHANGE_TAG__ instead
    NP_CHANGE_TAG=1

    while true; do
        if np_tag_menu "Lookup Note Tag" "Choose a tag to look up notes" 150 pinned all_tags 1 tag_menu_filter; then
            chosen_tag="$NP_PICKED_TAG"
        else
            # Back leaves when there is no usable tag (start, or the last tag
            # picked had no notes); otherwise it keeps the current tag.
            (( first || ! tag_ok )) && return 1
        fi
        first=0

        NP_TAG_LABEL="$chosen_tag"
        NP_PAGE=0
        case "$chosen_tag" in
            "[NO TAG]")  NP_TAGF="$NP_NO_TAG_VALUE" ;;
            "[ANY TAG]") NP_TAGF="" ;;
            *)           NP_TAGF="$chosen_tag" ;;
        esac

        while true; do
            np_filter_apply
            if (( ${#NP_FILTERED[@]} == 0 )) && [[ -z "$NP_GLOB" ]]; then
                case "$chosen_tag" in
                    "[NO TAG]")  whiptail --title "Attention" --msgbox "There are no notes without an associated tag." 8 60 ;;
                    "[ANY TAG]") whiptail --title "Attention" --msgbox "No notes found." 8 60 ;;
                    *)           whiptail --title "Attention" --msgbox "No matching notes for tag '${chosen_tag}'." 8 60 ;;
                esac
                tag_ok=0
                break
            fi
            tag_ok=1

            np_pick_note "Lookup notes" "Select a note to see its details"
            rc=$?
            case $rc in
                0)
                    IFS='|' read -r info_title info_path info_tags _ <<< "$NP_SELECTED_LINE"
                    whiptail --title "Note Information" --msgbox "$(printf \
                        'Note path:\n%s\n\nNote title:\n%s\n\nTags:\n%s' \
                        "$info_path" "$info_title" "$info_tags")" 20 90
                    ;;
                3) break ;;      # __CHANGE_TAG__
                *) return 1 ;;   # Back
            esac
        done
    done
}

# Let's user to dissociate a tag from a multiple note files filtered by a tag.
dissociate_note_tag_from_checklist() {
    local removal_tag
    local menu_items=()
    local line title path tags rest
    local choice
    local -A selected_notes=()
    local -A available_tags=()

    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 60
        return 1
    fi

    #
    # Checklist of notes. Only notes with at least one tag are listed since a
    # tag is going to be removed from them. No tag is asked at the start: the
    # list has __FILTER_BY_TAG__ / __RESET_FILTER__ / __APPLY_GLOB__ /
    # __RESET_GLOB__ items.
    #
    local src
    src=$(mktemp) || return 1
    awk -F'|' 'NF >= 2 && $3 ~ /[^ \t,]/' "$NOTES_DB" > "$src"
    if [[ ! -s "$src" ]]; then
        rm -f "$src"
        whiptail --msgbox "No notes with associated tags found." 8 50
        return 1
    fi

    np_reset
    NP_SRC_FILE="$src"
    NP_NO_TAG_ITEM=0            # only notes with tags: no [NO TAG] (just [ANY TAG])
    NP_SHOW_PATH=1              # show note file paths and tags
    NP_PATH_MAX=110
    NP_PROCEED="__submit__"

    if ! np_pick_notes_checklist "Dissociate Note Tag" "Select notes to remove a tag from" "Finish Selection (@N@ note(s) listed)"; then
        rm -f "$src"
        return 1
    fi
    rm -f "$src"

    for path in "${!NP_SEL[@]}"; do
        [[ "${NP_SEL["$path"]}" == "1" ]] && selected_notes["$path"]=1
    done

    (( ${#selected_notes[@]} == 0 )) && return

    #
    # Collect all tags from selected notes
    #
    while IFS='|' read -r title path tags rest; do
        [[ ${selected_notes[$path]} ]] || continue

        IFS=',' read -ra taglist <<< "$tags"

        for t in "${taglist[@]}"; do
            [[ -n $t ]] && available_tags["$t"]=1
        done
    done < "$NOTES_DB"

    #
    # Build sorted tag list
    #
    menu_items=()

    while IFS= read -r t; do
        menu_items+=("$t")
    done < <(
        printf '%s\n' "${!available_tags[@]}" | sort -f
    )

    (( ${#menu_items[@]} == 0 )) && {
        whiptail --msgbox "No associated tags found." 8 40
        return 1
    }

    # Tag to remove: same way as choosing a tag at the start of 'Do Stuff by
    # Tag' (__FILTER__ / __RESET_FILTER__, 50 tags per page), without
    # [NO TAG] / [ANY TAG].
    local -a no_pinned=()
    np_tag_menu "Remove Tag" "Select tag to remove" 155 no_pinned menu_items 1 || return 1
    removal_tag="$NP_PICKED_TAG"

    #
    # Confirmation
    #
    whiptail \
        --title "Confirm" \
        --yesno "Remove '$removal_tag' from the selected notes?" \
        10 60 || return 1

    #
    # Rewrite database
    #
    local tmp
    tmp=$(mktemp)

    while IFS='|' read -r title path tags rest; do

        if [[ ${selected_notes[$path]} ]]; then

            IFS=',' read -ra taglist <<< "$tags"

            local newtags=()

            for t in "${taglist[@]}"; do
                [[ $t == "$removal_tag" ]] && continue
                [[ -n $t ]] && newtags+=("$t")
            done

            tags=$(IFS=,; echo "${newtags[*]}")
        fi

        printf '%s|%s|%s|%s\n' \
            "$title" "$path" "$tags" "$rest"

    done < "$NOTES_DB" > "$tmp"

    mv "$tmp" "$NOTES_DB"

    whiptail --msgbox "Tag removed successfully." 8 40
}

############################################################
# Manage Notes: paginated lists with title glob / tag filtering
# (modelled on the Manage eBooks lists, e.g. 'Lookup Registered Files').
# Used by: Edit Note, Print Note Using Printer, Open Associated eBook,
# Lookup Note Tag, Dissociate Note Tag from Checklist, Associate/Dissociate
# URL, Open URL from Note and Delete Notes.
############################################################

NP_PAGE_SIZE=50            # notes per whiptail page
NP_WIDTH=155               # width of every note list / checklist
NP_SRC_FILE=""             # file with NOTES_DB style lines (title|path|tags|ebooks) to browse
NP_GLOB=""                 # active glob filter (matches the note TITLE only)
NP_TAGF=""                 # tag filter: "" = [ANY TAG], $NP_NO_TAG_VALUE = [NO TAG], else an exact tag
NP_NO_TAG_VALUE="__NO_TAG__"
NP_PAGE=0                  # current page (0-based), kept between calls
NP_FILTERED=()             # lines left after the filters are applied
NP_SELECTED_LINE=""        # result of np_pick_note()
NP_PICKED_TAG=""           # result of np_tag_menu()
NP_SHOW_PATH=0             # 1 = show the note file path instead of the title
NP_PATH_MAX=0              # truncate displayed paths to this many characters (0 = never)
NP_NO_FILTERS=0            # 1 = hide the glob / tag filter items
NP_NO_TAG_FILTER=0         # 1 = hide only the tag filter items (keep the glob items)
NP_NO_TAG_ITEM=1           # 1 = the tag picker of __FILTER_BY_TAG__ offers [NO TAG]
NP_CHANGE_TAG=0            # 1 = show a __CHANGE_TAG__ item (np_pick_note returns 3 for it)
NP_TAG_LABEL=""            # tag shown in the status line (fixed-tag lists)
NP_REVERT_TAG=0            # 1 = show a __REVERT_TAG__ item (np_pick_note returns 4 for it)
NP_ORIG_TAG=""             # tag chosen at the start (target of __REVERT_TAG__)
NP_GLOB_BY_FILE=0          # 1 = the glob matches the note FILE NAME instead of the title
NP_PROCEED=""              # name of the extra action item of a checklist (e.g. __submit__)
NP_PROCEED_DESC=""         # its description (@N@ = number of listed notes)
NP_START_TAG=""            # result of np_choose_start_tag()
declare -A NP_SEL=()       # checklist selections (key: note path, value: 1/0)
NP_ACTION_ITEMS=()

np_reset() {
    NP_GLOB=""
    NP_TAGF=""
    NP_PAGE=0
    NP_SEL=()
    NP_SELECTED_LINE=""
    NP_SHOW_PATH=0
    NP_PATH_MAX=0
    NP_NO_FILTERS=0
    NP_NO_TAG_FILTER=0
    NP_NO_TAG_ITEM=1
    NP_CHANGE_TAG=0
    NP_TAG_LABEL=""
    NP_REVERT_TAG=0
    NP_ORIG_TAG=""
    NP_GLOB_BY_FILE=0
    NP_PROCEED=""
    NP_PROCEED_DESC=""
}

# Prints "height width list-height" for a whiptail list that shows
# NP_PAGE_SIZE items plus the action / navigation items. $1 = width (default
# $EB_WIDTH). Height and width are capped to the terminal size; whiptail
# scrolls inside the list when the terminal is smaller.
np_dims() {
    local want_w="${1:-$EB_WIDTH}" rows cols h w lh
    read -r rows cols < <(stty size </dev/tty 2>/dev/null)
    [[ "$rows" =~ ^[0-9]+$ ]] || rows=0
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=0

    lh=$(( NP_PAGE_SIZE + 8 ))
    h=$(( lh + 11 ))
    w=$want_w
    (( rows > 0 && h > rows )) && h=$rows
    (( h < 14 )) && h=14
    lh=$(( h - 11 ))
    (( lh < 3 )) && lh=3
    (( cols > 0 && w > cols )) && w=$cols
    (( w < 40 )) && w=40
    echo "$h $w $lh"
}

# Applies NP_GLOB (note TITLE only, whole title, case insensitive, * and ?)
# and NP_TAGF to NP_SRC_FILE. Result: NP_FILTERED array.
np_filter_apply() {
    NP_FILTERED=()
    [[ -f "$NP_SRC_FILE" ]] || return 0
    mapfile -t NP_FILTERED < <(
        NP_GLOB="$NP_GLOB" NP_TAGF="$NP_TAGF" NP_NOVAL="$NP_NO_TAG_VALUE" NP_BYFILE="$NP_GLOB_BY_FILE" \
        awk -F'|' "$EB_AWK_GLOB"'
        BEGIN {
            g = tolower(ENVIRON["NP_GLOB"])
            t = ENVIRON["NP_TAGF"]
            nov = ENVIRON["NP_NOVAL"]
            byfile = ENVIRON["NP_BYFILE"]
            if (g != "") re = glob2re(g)
        }
        NF >= 2 {
            subject = $1
            if (byfile == "1") {
                n = split($2, pp, "/")
                subject = pp[n]
            }
            if (g != "" && tolower(subject) !~ re) next
            if (t != "") {
                if (t == nov) {
                    x = $3
                    gsub(/^[ \t,]+|[ \t,]+$/, "", x)
                    if (x != "") next
                } else {
                    found = 0
                    n = split($3, a, ",")
                    for (i = 1; i <= n; i++) {
                        x = a[i]
                        gsub(/^[ \t]+|[ \t]+$/, "", x)
                        if (x == t) { found = 1; break }
                    }
                    if (!found) next
                }
            }
            print
        }' "$NP_SRC_FILE"
    )
}

# What the glob is matched against (for labels and prompts).
np_glob_what() {
    if (( NP_GLOB_BY_FILE == 1 )); then
        printf 'note file name'
    else
        printf 'note title'
    fi
}

np_ask_glob() {
    local g example whole
    if (( NP_GLOB_BY_FILE == 1 )); then
        whole="file name"
        example='*python*  or  chapter?.txt'
    else
        whole="title"
        example='*python*  or  Chapter ?*'
    fi
    g=$(whiptail --title "__APPLY_GLOB__" --inputbox \
"Enter a glob to filter the notes by $(np_glob_what | tr a-z A-Z) (case insensitive).\n\
* matches any characters, ? matches one character.\n\
The whole ${whole} must match, e.g.  ${example}\n\
Empty input removes the glob filter." 14 "$NP_WIDTH" "$NP_GLOB" 3>&1 1>&2 2>&3) || return 1
    NP_GLOB="$g"
    NP_PAGE=0
}

# np_tag_menu TITLE PROMPT WIDTH PINNED_ARRAY TAGS_ARRAY WITH_FILTER
# Paginated tag picker (50 tags per page). The tags of PINNED_ARRAY (pairs of
# "tag" "description", e.g. [NO TAG] / [ANY TAG]) are shown on EVERY page.
# WITH_FILTER=1 adds __FILTER__ / __RESET_FILTER__ items that narrow the tags
# down by a literal (not glob), case insensitive substring.
# Optional 7th argument: NAME of a variable that keeps the __FILTER__ text. It is
# read when the menu opens and updated whenever the filter changes, so the
# caller can reopen the menu later with the same filter still applied.
# Sets NP_PICKED_TAG; returns 1 on Back / Esc.
np_tag_menu() {
    local title="$1" prompt="$2" width="${3:-155}" with_filter="${6:-0}"
    local -n _npt_pinned="$4"
    local -n _npt_tags="$5"
    local _npt_nofilter=""
    local -n _npt_keep="${7:-_npt_nofilter}"
    local -a shown=() menu=()
    local filter="$_npt_keep" page=0 per_page=50 k t matched pages choice f
    local rows cols h w lh n_extra

    NP_PICKED_TAG=""
    while :; do
        shown=()
        for t in "${_npt_tags[@]}"; do
            if [[ -z "$filter" || "${t,,}" == *"${filter,,}"* ]]; then
                shown+=("$t")
            fi
        done
        matched=${#shown[@]}
        pages=$(( (matched + per_page - 1) / per_page ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$(( pages - 1 ))
        (( page < 0 )) && page=0

        menu=("${_npt_pinned[@]}")
        if (( with_filter )); then
            menu+=(
                "__FILTER__" "Filter tags by text (literal substring)${filter:+   [filter: $filter]}"
                "__RESET_FILTER__" "Reset tag filter"
            )
        fi
        (( page > 0 )) && menu+=("<< Previous Page" "")
        (( page < pages - 1 )) && menu+=(">> Next Page" "")
        for (( k = page * per_page; k < (page + 1) * per_page && k < matched; k++ )); do
            menu+=("${shown[k]}" "")
        done

        # Box big enough for 50 tags + pinned + filter + navigation items
        # (capped to the terminal size).
        n_extra=$(( ${#_npt_pinned[@]} / 2 + 2 ))
        (( with_filter )) && n_extra=$(( n_extra + 2 ))
        lh=$(( per_page + n_extra ))
        h=$(( lh + 11 ))
        w=$width
        read -r rows cols < <(stty size </dev/tty 2>/dev/null)
        [[ "$rows" =~ ^[0-9]+$ ]] || rows=0
        [[ "$cols" =~ ^[0-9]+$ ]] || cols=0
        (( rows > 0 && h > rows )) && h=$rows
        (( h < 14 )) && h=14
        lh=$(( h - 11 ))
        (( lh < 3 )) && lh=3
        (( cols > 0 && w > cols )) && w=$cols
        (( w < 40 )) && w=40

        local status="${prompt}"
        if (( with_filter )); then
            status+="\n\nFilter: ${filter:-(none)}  |  ${matched}/${#_npt_tags[@]} tag(s)  |  Page $((page + 1))/${pages}"
        else
            status+="\n\n${matched} tag(s)  |  Page $((page + 1))/${pages}"
        fi
        (( matched == 0 )) && status+="  |  No tags match."

        choice=$(whiptail --title "$title" --cancel-button "Back" \
            --menu "$status" "$h" "$w" "$lh" "${menu[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            "__FILTER__")
                f=$(whiptail --title "__FILTER__" --inputbox \
"Enter text to narrow down the tag list.\n\
Tags that contain this text are shown (literal substring match, case insensitive; no wildcards).\n\
Empty input removes the filter." 12 "$w" "$filter" 3>&1 1>&2 2>&3) && filter="$f"
                _npt_keep="$filter"
                page=0
                ;;
            "__RESET_FILTER__") filter=""; _npt_keep=""; page=0 ;;
            "<< Previous Page") (( page-- )) ;;
            ">> Next Page")     (( page++ )) ;;
            *)
                NP_PICKED_TAG="$choice"
                return 0
                ;;
        esac
    done
}

# __FILTER_BY_TAG__ of the note lists: shows the tags (of the notes currently
# listed, glob applied) with __FILTER__ / __RESET_FILTER__ items that narrow
# them down by a literal substring, and lets the user pick ONE of them.
# [ANY TAG] (and [NO TAG] unless NP_NO_TAG_ITEM=0) are always offered. The
# list is then filtered by that exact tag.
np_pick_tag_filter() {
    local saved
    local -a matches=() pinned=()

    # tags carried by the notes that pass the glob filter
    saved="$NP_TAGF"
    NP_TAGF=""
    np_filter_apply
    NP_TAGF="$saved"
    if (( ${#NP_FILTERED[@]} > 0 )); then
        mapfile -t matches < <(
            printf '%s\n' "${NP_FILTERED[@]}" | awk -F'|' '
            {
                n = split($3, a, ",")
                for (i = 1; i <= n; i++) {
                    x = a[i]
                    gsub(/^[ \t]+|[ \t]+$/, "", x)
                    if (x != "") seen[x] = 1
                }
            }
            END { for (x in seen) print x }' | sort -f
        )
    fi

    (( NP_NO_TAG_ITEM == 1 )) && pinned+=("[NO TAG]" "Only show notes with no tag associated")
    pinned+=("[ANY TAG]" "Show notes with any tag (remove the tag filter)")

    # __FILTER__ / __RESET_FILTER__ narrow the tag list by a literal substring.
    np_tag_menu "Select a Tag to Filter By" "Choose a tag to filter the notes by" "$NP_WIDTH" pinned matches 1 || return 1
    case "$NP_PICKED_TAG" in
        "[NO TAG]")  NP_TAGF="$NP_NO_TAG_VALUE" ;;
        "[ANY TAG]") NP_TAGF="" ;;
        *)           NP_TAGF="$NP_PICKED_TAG" ;;
    esac
    NP_PAGE=0
}

# $1 = "menu" or "check", $2 = number of pages, $3 = number of listed notes.
# Fills the global NP_ACTION_ITEMS array (proceed item first, at the top).
np_action_items() {
    local kind="$1" pages="$2" total="$3" extra=()
    [[ "$kind" == "check" ]] && extra=("OFF")
    NP_ACTION_ITEMS=()
    if [[ -n "$NP_PROCEED" && "$kind" == "check" ]]; then
        NP_ACTION_ITEMS+=("$NP_PROCEED" "${NP_PROCEED_DESC//@N@/$total}" "${extra[@]}")
    fi
    if (( NP_CHANGE_TAG == 1 )); then
        NP_ACTION_ITEMS+=("__CHANGE_TAG__" "Choose a different tag (current: ${NP_TAG_LABEL})" "${extra[@]}")
    fi
    if (( NP_REVERT_TAG == 1 )); then
        NP_ACTION_ITEMS+=("__REVERT_TAG__" "Back to the original tag (${NP_ORIG_TAG})" "${extra[@]}")
    fi
    if (( NP_NO_FILTERS == 0 )); then
        NP_ACTION_ITEMS+=("__APPLY_GLOB__" "Filter by glob ($(np_glob_what))${NP_GLOB:+   [glob: $NP_GLOB]}" "${extra[@]}")
        NP_ACTION_ITEMS+=("__RESET_GLOB__" "Reset glob filter" "${extra[@]}")
        if (( NP_NO_TAG_FILTER == 0 )); then
            local tf="${NP_TAGF/$NP_NO_TAG_VALUE/[NO TAG]}"
            NP_ACTION_ITEMS+=("__FILTER_BY_TAG__" "Filter by tag${NP_TAGF:+   [tag filter: ${tf}]}" "${extra[@]}")
            NP_ACTION_ITEMS+=("__RESET_FILTER__" "Reset tag filter" "${extra[@]}")
        fi
    fi
    (( NP_PAGE > 0 )) && NP_ACTION_ITEMS+=("__PREV_PAGE__" "Previous page" "${extra[@]}")
    (( NP_PAGE < pages - 1 )) && NP_ACTION_ITEMS+=("__NEXT_PAGE__" "Next page" "${extra[@]}")
    return 0
}

# Handles one of the filter / navigation actions. Returns 1 for other items.
np_do_action() {
    case "$1" in
        __APPLY_GLOB__)    np_ask_glob ;;
        __RESET_GLOB__)    NP_GLOB=""; NP_PAGE=0 ;;
        __FILTER_BY_TAG__) np_pick_tag_filter ;;
        __RESET_FILTER__)  NP_TAGF=""; NP_PAGE=0 ;;
        __PREV_PAGE__)     (( NP_PAGE-- )) ;;
        __NEXT_PAGE__)     (( NP_PAGE++ )) ;;
        *) return 1 ;;
    esac
    return 0
}

# One-line status shown above the list: position, count and active filters.
np_status() {
    local page="$1" pages="$2" total="$3"
    local s="Page ${page}/${pages}  |  ${total} note(s)"
    [[ -n "$NP_TAG_LABEL" ]] && s+="  |  tag: ${NP_TAG_LABEL}"
    if (( NP_NO_FILTERS == 0 )); then
        s+="  |  glob ($(np_glob_what)): ${NP_GLOB:-(none)}"
        if (( NP_NO_TAG_FILTER == 0 )); then
            local tf
            if [[ -z "$NP_TAGF" ]]; then
                tf="[ANY TAG]"
            else
                tf="${NP_TAGF/$NP_NO_TAG_VALUE/[NO TAG]}"
            fi
            s+="  |  tag filter: ${tf}"
        fi
    fi
    printf '%s' "$s"
}

# Item text of a note: title (or the note path) followed by [tag1,tag2,tag3 +N]
np_item_label() {
    local title path tags shown
    IFS='|' read -r title path tags _ <<< "$1"
    if (( NP_SHOW_PATH == 1 )); then
        shown="$(eb_trunc_path "$path" "$NP_PATH_MAX")"
    else
        shown="${title:0:70}"
    fi
    printf '%s %s' "$shown" "$(format_tags_short "$tags")"
}

# Paginated menu (50 notes per page) of the notes in NP_SRC_FILE with the
# filter items on top. Filters and the page are kept between calls; call
# np_reset first for a fresh list.
# Returns 0 with NP_SELECTED_LINE set (NOTES_DB line), 1 on Back / Esc and
# 3 when __CHANGE_TAG__ was chosen and 4 when __REVERT_TAG__ was chosen.
np_pick_note() {
    local title="$1" prompt="${2:-Select a note}"
    local total pages start end i choice h w lh
    local -a items

    while true; do
        np_filter_apply
        total=${#NP_FILTERED[@]}
        pages=$(( (total + NP_PAGE_SIZE - 1) / NP_PAGE_SIZE ))
        (( pages < 1 )) && pages=1
        (( NP_PAGE >= pages )) && NP_PAGE=$(( pages - 1 ))
        (( NP_PAGE < 0 )) && NP_PAGE=0
        start=$(( NP_PAGE * NP_PAGE_SIZE ))
        end=$(( start + NP_PAGE_SIZE ))
        (( end > total )) && end=$total

        np_action_items menu "$pages" "$total"
        items=("${NP_ACTION_ITEMS[@]}")
        for (( i=start; i<end; i++ )); do
            items+=("$(( i + 1 ))" "$(np_item_label "${NP_FILTERED[i]}")")
        done

        if (( ${#items[@]} == 0 )); then
            whiptail --title "Attention" --msgbox "No matching notes found." 8 50
            return 1
        fi

        local hint=""
        (( total == 0 )) && hint="\nNo notes match the current filters."
        read -r h w lh <<< "$(np_dims "$NP_WIDTH")"
        choice=$(whiptail --title "$title" --cancel-button "Back" \
            --menu "${prompt}\n$(np_status "$((NP_PAGE + 1))" "$pages" "$total")${hint}" \
            "$h" "$w" "$lh" "${items[@]}" 3>&1 1>&2 2>&3) || return 1

        [[ "$choice" == "__CHANGE_TAG__" ]] && return 3
        [[ "$choice" == "__REVERT_TAG__" ]] && return 4
        if np_do_action "$choice"; then
            continue
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
            NP_SELECTED_LINE="${NP_FILTERED[choice - 1]}"
            return 0
        fi
    done
}

# Same as np_pick_note() but multi-select (checklist). Selected notes are
# remembered in NP_SEL (key: note path) across pages and filter changes. Tick
# ONE action item (the NP_PROCEED item is at the top) and press OK to run it.
# $3 = label of the proceed item (@N@ = number of listed notes).
# Returns 0 on proceed (at least one note selected), 1 on Cancel / Esc.
np_pick_notes_checklist() {
    local title="$1" prompt="$2" proceed_label="$3"
    local total pages start end i line path choice h w lh t result state n_sel p key
    local -a items sel actions
    local -A chosen

    while true; do
        np_filter_apply
        total=${#NP_FILTERED[@]}
        pages=$(( (total + NP_PAGE_SIZE - 1) / NP_PAGE_SIZE ))
        (( pages < 1 )) && pages=1
        (( NP_PAGE >= pages )) && NP_PAGE=$(( pages - 1 ))
        (( NP_PAGE < 0 )) && NP_PAGE=0
        start=$(( NP_PAGE * NP_PAGE_SIZE ))
        end=$(( start + NP_PAGE_SIZE ))
        (( end > total )) && end=$total

        NP_PROCEED_DESC="$proceed_label"
        np_action_items check "$pages" "$total"
        items=("${NP_ACTION_ITEMS[@]}")
        for (( i=start; i<end; i++ )); do
            line="${NP_FILTERED[i]}"
            IFS='|' read -r _ path _ <<< "$line"
            state="OFF"
            [[ "${NP_SEL["$path"]:-0}" == "1" ]] && state="ON"
            items+=("n$(( i + 1 ))" "$(np_item_label "$line")" "$state")
        done

        n_sel=0
        for p in "${!NP_SEL[@]}"; do
            [[ "${NP_SEL["$p"]}" == "1" ]] && n_sel=$(( n_sel + 1 ))
        done

        if (( ${#items[@]} == 0 )); then
            whiptail --title "Attention" --msgbox "No matching notes found." 8 50
            return 1
        fi

        read -r h w lh <<< "$(np_dims "$NP_WIDTH")"
        result=$(whiptail --title "$title" --cancel-button "Cancel" \
            --checklist "${prompt}\n$(np_status "$((NP_PAGE + 1))" "$pages" "$total")  |  selected: ${n_sel} (incl. notes hidden by filters)\nTick notes with SPACE; tick ONE action item and press OK to run it." \
            "$h" "$w" "$lh" "${items[@]}" 3>&1 1>&2 2>&3) || return 1

        result=${result//\"/}
        read -r -a sel <<< "$result"
        chosen=()
        for t in "${sel[@]}"; do chosen["$t"]=1; done

        # remember the ticks of the notes shown on this page
        for (( i=start; i<end; i++ )); do
            IFS='|' read -r _ path _ <<< "${NP_FILTERED[i]}"
            key="n$(( i + 1 ))"
            if [[ -n "${chosen[$key]+x}" ]]; then
                NP_SEL["$path"]=1
            else
                NP_SEL["$path"]=0
            fi
        done

        actions=()
        for t in "${sel[@]}"; do
            [[ "$t" == __* ]] && actions+=("$t")
        done
        if (( ${#actions[@]} > 1 )); then
            whiptail --title "Invalid Selection" --msgbox "Please tick only ONE action item at a time (filter, reset, page navigation or proceed)." 10 100
            continue
        fi
        (( ${#actions[@]} == 0 )) && continue

        if [[ -n "$NP_PROCEED" && "${actions[0]}" == "$NP_PROCEED" ]]; then
            n_sel=0
            for p in "${!NP_SEL[@]}"; do
                [[ "${NP_SEL["$p"]}" == "1" ]] && n_sel=$(( n_sel + 1 ))
            done
            if (( n_sel == 0 )); then
                whiptail --title "Attention" --msgbox "Please select at least one note first." 8 60
                continue
            fi
            return 0
        fi
        np_do_action "${actions[0]}"
    done
}

# Prints at most the first 10 lines of the named array followed by
# "(... N more)" when there are more of them.
np_preview_list() {
    local -n _npp_items="$1"
    local total=${#_npp_items[@]} i
    for (( i=0; i<total && i<10; i++ )); do
        printf '%s\n' "${_npp_items[i]}"
    done
    if (( total > 10 )); then
        printf '(... %d more)\n' "$(( total - 10 ))"
    fi
}

# Tag selection of the URL workflows. Same way as the tag selection of
# 'Do Stuff by Tag': 50 tags per page, 150 wide, __FILTER__ / __RESET_FILTER__
# (literal substring). [NO TAG] and [ANY TAG] are always offered.
# Sets NP_START_TAG; returns 1 on Back / Esc.
np_choose_start_tag() {
    local -a all_tags=() pinned=("[NO TAG]" "Notes with no tag associated" "[ANY TAG]" "All notes (any tag or none)")
    local t
    if [[ -f "$NOTES_TAGS_DB" ]]; then
        while IFS= read -r t || [[ -n "$t" ]]; do
            [[ -n "$t" ]] && all_tags+=("$t")
        done < "$NOTES_TAGS_DB"
    fi
    # NP_START_TAG keeps its value when the user goes Back.
    np_tag_menu "Select Tag" "Choose a tag to find notes" 150 pinned all_tags 1 || return 1
    NP_START_TAG="$NP_PICKED_TAG"
}

# np_pick_note_for_tag TITLE PROMPT NEED_URLS TAG
# Lists the notes of $NOTES_DB that carry TAG ([NO TAG] / [ANY TAG] allowed)
# and, when NEED_URLS=1, have at least one URL in $URLS_DB. Paths + shortened
# tags, 155 wide, 50 per page. The list has __CHANGE_TAG__, __REVERT_TAG__
# (back to the tag chosen at the start), __APPLY_GLOB__ (matches the note FILE
# NAME) and __RESET_GLOB__ items. Call np_reset once before; the glob, the tag
# and the page are kept between calls. NP_START_TAG holds the current tag.
# Same return codes as np_pick_note (NP_SELECTED_LINE).
np_pick_note_for_tag() {
    local title="$1" prompt="$2" need_urls="$3" tag="$4"
    local src rc GS=$'\x1D'

    NP_START_TAG="$tag"
    [[ -z "$NP_ORIG_TAG" ]] && NP_ORIG_TAG="$tag"

    src=$(mktemp) || return 1
    if [[ "$need_urls" == "1" ]]; then
        awk -F'|' -v gs="$GS" -v urls="$URLS_DB" '
            BEGIN {
                while ((getline l < urls) > 0) {
                    k = index(l, gs)
                    if (k > 1 && length(l) > k) has[substr(l, 1, k - 1)] = 1
                }
            }
            NF >= 2 && ($2 in has)' "$NOTES_DB" > "$src"
    else
        awk -F'|' 'NF >= 2' "$NOTES_DB" > "$src"
    fi

    NP_SRC_FILE="$src"
    NP_NO_FILTERS=0
    NP_NO_TAG_FILTER=1          # the tag is changed with __CHANGE_TAG__ / __REVERT_TAG__
    NP_CHANGE_TAG=1
    NP_REVERT_TAG=1
    NP_GLOB_BY_FILE=1           # the glob matches the note file name
    NP_SHOW_PATH=1
    NP_PATH_MAX=110

    while true; do
        NP_TAG_LABEL="$NP_START_TAG"
        case "$NP_START_TAG" in
            "[NO TAG]")  NP_TAGF="$NP_NO_TAG_VALUE" ;;
            "[ANY TAG]") NP_TAGF="" ;;
            *)           NP_TAGF="$NP_START_TAG" ;;
        esac

        np_pick_note "$title" "$prompt"
        rc=$?
        case $rc in
            3)  # __CHANGE_TAG__ (Back keeps the current tag)
                np_choose_start_tag && NP_PAGE=0
                ;;
            4)  # __REVERT_TAG__
                if [[ "$NP_START_TAG" == "$NP_ORIG_TAG" ]]; then
                    whiptail --title "Attention" --msgbox "Already filtering by the original tag: ${NP_ORIG_TAG}" 8 60
                else
                    NP_START_TAG="$NP_ORIG_TAG"
                    NP_PAGE=0
                fi
                ;;
            *)  break ;;
        esac
    done

    rm -f "$src"
    return $rc
}

# Main menu function
manage_notes() {
    while true; do
        local option
        option=$(whiptail --title "Manage Notes" --cancel-button "Back" --menu "Choose an option:" 23 70 14 \
            "1" "Add Note" \
            "2" "Edit Note" \
            "3" "Print Note Using Printer" \
            "4" "Open Associated eBook" \
            "5" "Add New Note Tag" \
            "6" "Lookup Note Tag" \
            "7" "Do Stuff by Tag" \
            "8" "Dissociate Note Tag from Checklist" \
            "9" "Associate URL to Note" \
            "10" "Dissociate URL from Note" \
	        "11" "Open URL from Note" \
            "12" "Open an eBook From Global List" \
            "13" "Delete Notes" \
	        "14" "Delete Note Tag From Global List" 3>&1 1>&2 2>&3)

        # Exit the function if the user presses Esc or Cancel
        if [ $? -ne 0 ] || [ -z "$option" ]; then
            return
        fi

        case $option in
            1) add_note ;;
            2) list_notes ;;
            3) print_notes ;;
            4) open_note_ebook_page ;;
            5) add_note_tag_menu ;;
            6) lookup_note_tags ;;
            7) do_note_filter_by_tag ;;
            8) dissociate_note_tag_from_checklist ;;
            9) assoc_url_to_note ;;
            10) dissoc_url_from_note ;;
            11) open_url_assoc_to_note ;;
            12) open_ebook_note_from_global_list ;;
            13) delete_notes ;;
    	    14) delete_global_tag_of_notes ;;
            *) return ;;
        esac
    done
}

#########################################
# Manage Goals(Projects) code starts here
#########################################

PROJECTS_METADATA_DIR="$(pwd)/projects/metadata"
PROJECTS_DIR="$(pwd)/projects"
PROJECTS_DB="${PROJECTS_METADATA_DIR}/projects.db"

mkdir -p "$PROJECTS_METADATA_DIR" "$PROJECTS_DIR"
# FIX: start with empty projects db.
touch "$PROJECTS_DB"

# USAGE:
# mapfile -d '' -t filtered_lines < <(filter_projects_by_name)
filter_projects_by_name() {
    # Read the project database into an array
    local projects_lines
    readarray -t projects_lines < "$PROJECTS_DB"

    # Prompt user for a glob pattern
    local pattern
    pattern=$(whiptail --inputbox "Enter a glob pattern to filter projects (empty for wildcard):" 8 40 \
              --title "Project Filter" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1  # Exit if canceled

    # Set default pattern if empty
    : "${pattern:=*}"

    # Filter matching lines
    local filtered_lines=()
    local line title
    shopt -s nocasematch  # Enable case-insensitive matching
    for line in "${projects_lines[@]}"; do
        title="${line%%|*}"
        #[[ "$title" == $pattern ]] && filtered_lines+=("$line")    # doesn't seem to work if glob has spaces
        case "$title" in
            $pattern) filtered_lines+=("$line") ;;
        esac    
    done
    shopt -u nocasematch  # Disable case-insensitive matching (restore default)

    # Sort by title--case insensitive.
    mapfile -t filtered_lines < <(
        printf '%s\n' "${filtered_lines[@]}" |
            sort -t'|' -k1,1f
    )    

    # DEBUG
    #echo "pattern:" >&2
    #echo "$pattern" >&2
    #echo "filtered_lines:" >&2
    #printf "%s\n" "${filtered_lines[@]}" >&2

    # Output null-delimited results
    (( ${#filtered_lines[@]} )) && printf "%s\0" "${filtered_lines[@]}" || {
        #whiptail --title "Alert" --msgbox "No matches found for pattern: '${pattern}'" 8 40 >/dev/tty  # we don't need this alert any more.
        return 1
    }
}

# DEBUG
#filter_projects_by_name
#exit 1

paginate_get_projects() {
    # Clear any previous selection
    SELECTED_ITEM_PROJECT=""

    local chunk_size=200

    # If new items are passed in, update FILTERED_EBOOKS and reset CURRENT_PAGE.
    # First arg is custom menu title.
    local menu_title
    if [ "$#" -gt 0 ]; then
        menu_title="$1"  # First argument is the title
        shift  # Shift to remove the title from the arguments
        FILTERED_PROJECTS=("$@")  # Remaining arguments are the items
        CURRENT_PAGE_PROJECTS=0
    fi

    # Set default title if menu_title is not provided.
    # But if menu_title is not privided as $1 then FILTERED_EBOOKS will be errorneous.
    : "${menu_title:=Paged Menu}"

    [[ ${#FILTERED_PROJECTS[@]} -eq 0 ]] && return 1

    local total_pages=$(( ( ${#FILTERED_PROJECTS[@]} + chunk_size - 1 ) / chunk_size ))
    # Ensure CURRENT_PAGE_PROJECTS is within valid bounds
    if (( CURRENT_PAGE_PROJECTS >= total_pages )); then
        CURRENT_PAGE_PROJECTS=$(( total_pages - 1 ))
    fi

    local choice=""
    while true; do
        local start=$(( CURRENT_PAGE_PROJECTS * chunk_size ))
        # Extract the current chunk
        local current_chunk=("${FILTERED_PROJECTS[@]:$start:$chunk_size}")
        local menu_options=()

        # Add navigation options if needed
        if (( CURRENT_PAGE_PROJECTS > 0 )); then
            menu_options+=("previous page" "")
        fi
        if (( CURRENT_PAGE_PROJECTS < total_pages - 1 )); then
            menu_options+=("next page" "")
        fi

        # Append the current page items
        menu_options+=("${current_chunk[@]}")

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "Choose an item (Page $((CURRENT_PAGE_PROJECTS + 1))/$total_pages)" \
            35 175 25 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3 </dev/tty >/dev/tty)

        # Exit with code 1 if user cancels. Make sure to reset SELECTED_ITEM.
        if [ $? -ne 0 ]; then
            SELECTED_ITEM_PROJECT=""
            return 1
        fi

        case "$choice" in
            "previous page")
                (( CURRENT_PAGE_PROJECTS-- ))
                ;;
            "next page")
                (( CURRENT_PAGE_PROJECTS++ ))
                ;;
            *)
                # Return the index              
                SELECTED_ITEM_PROJECT="$choice"                
                return 0
                ;;
        esac
    done

    return 1
}

##############################################################
# Goals Management: shared pickers and helpers
##############################################################

# State shared between the Goals Management pickers. The calling workflow
# resets the glob/filter variables when it starts, so the user's glob and
# filter survive while they keep working inside the same workflow.
GOALS_PROJECT_GLOB=""
GOALS_NOTE_GLOB=""
GOALS_NOTE_TAGFILTER=""
GOALS_SELECTED_PROJECT_LINENO=""
GOALS_SELECTED_PROJECT_TITLE=""
GOALS_SELECTED_PROJECT_PATH=""
GOALS_SELECTED_PROJECT_NOTES=""
GOALS_SELECTED_PROJECT_LINE=""
GOALS_SELECTED_NOTE_TAG=""
GOALS_PICKED_NOTE_INDEX=""
GOALS_PICKED_NOTE_PATH=""
GOALS_PICKED_PATHS=()
GOALS_NOTE_TITLE_MODE=""
GOALS_PROJECT_TITLE_MODE=""
GOALS_MENU_CHOICE=""

# Pick a project from PROJECTS_DB.
#
# Every row shows the full project path. __APPLY_GLOB__ matches the project
# FILE NAME (the last component of the path), case-insensitively, and
# __RESET_GLOB__ clears the glob. The current glob is kept in
# GOALS_PROJECT_GLOB.
#
# On success (return 0) these are set:
#   GOALS_SELECTED_PROJECT_LINENO  1-based line number in PROJECTS_DB
#   GOALS_SELECTED_PROJECT_TITLE / _PATH / _NOTES / _LINE
# Returns 1 when the user goes Back.
goals_select_project() {
    local menu_title="${1:-Select Project}"
    local -a rows_lineno=() rows_title=() rows_path=() rows_notes=() rows_line=()
    local -a order=() menu_items=()
    local row lineno=0 t p n base choice new_glob
    local page=1 page_size=50 total total_pages start end k i prompt
    local what="file name"
    # With GOALS_PROJECT_RESTRICT_FILE set (a file holding one project path per
    # line, e.g. the shortlist) only those projects are offered.
    local -A allowed_paths=()
    local restrict_note="" ap
    if [[ -n "${GOALS_PROJECT_RESTRICT_FILE:-}" ]]; then
        restrict_note=" (shortlisted projects only)"
        if [[ -r "$GOALS_PROJECT_RESTRICT_FILE" ]]; then
            while IFS= read -r ap || [[ -n "$ap" ]]; do
                [[ -n "$ap" ]] && allowed_paths["$ap"]=1
            done < "$GOALS_PROJECT_RESTRICT_FILE"
        fi
        if (( ${#allowed_paths[@]} == 0 )); then
            whiptail --title "$menu_title" --msgbox \
                "No shortlisted projects found. Shortlist at least one project and try again." 8 70
            return 1
        fi
    fi
    [[ -n "${GOALS_PROJECT_TITLE_MODE:-}" ]] && what="title"

    GOALS_SELECTED_PROJECT_LINENO=""
    GOALS_SELECTED_PROJECT_TITLE=""
    GOALS_SELECTED_PROJECT_PATH=""
    GOALS_SELECTED_PROJECT_NOTES=""
    GOALS_SELECTED_PROJECT_LINE=""

    if [[ ! -s "$PROJECTS_DB" ]]; then
        whiptail --title "$menu_title" --msgbox \
            "No projects found. Add at least one project and try again." 8 60
        return 1
    fi

    while :; do
        rows_lineno=(); rows_title=(); rows_path=(); rows_notes=(); rows_line=()
        lineno=0
        while IFS= read -r row || [[ -n "$row" ]]; do
            lineno=$((lineno + 1))
            [[ -n "$row" ]] || continue
            IFS='|' read -r t p n <<< "$row"
            [[ -n "$p" ]] || continue
            if [[ -n "${GOALS_PROJECT_RESTRICT_FILE:-}" && -z "${allowed_paths[$p]:-}" ]]; then
                continue
            fi
            if [[ -n "$GOALS_PROJECT_GLOB" ]]; then
                if [[ -n "${GOALS_PROJECT_TITLE_MODE:-}" ]]; then base="$t"; else base="${p##*/}"; fi
                [[ "${base,,}" == ${GOALS_PROJECT_GLOB,,} ]] || continue
            fi
            rows_lineno+=("$lineno"); rows_title+=("$t"); rows_path+=("$p")
            rows_notes+=("$n"); rows_line+=("$row")
        done < "$PROJECTS_DB"

        # Sort by full project path, case-insensitively.
        order=()
        if (( ${#rows_path[@]} > 0 )); then
            mapfile -t order < <(
                for i in "${!rows_path[@]}"; do
                    if [[ -n "${GOALS_PROJECT_TITLE_MODE:-}" ]]; then
                        printf '%s\t%s\n' "${rows_title[i],,}" "$i"
                    else
                        printf '%s\t%s\n' "${rows_path[i],,}" "$i"
                    fi
                done | LC_ALL=C sort -t $'\t' -k1,1 | cut -f2
            )
        fi

        total=${#order[@]}
        total_pages=$(( (total + page_size - 1) / page_size ))
        (( total_pages < 1 )) && total_pages=1
        (( page > total_pages )) && page=$total_pages
        start=$(( (page - 1) * page_size ))
        end=$(( start + page_size ))
        (( end > total )) && end=$total

        menu_items=(
            "__APPLY_GLOB__" "Apply glob (matches project ${what})"
            "__RESET_GLOB__" "Reset glob"
        )
        (( page > 1 )) && menu_items+=("__PREV_PAGE__" "<< Previous page")
        for (( k = start; k < end; k++ )); do
            i=${order[k]}
            if [[ -n "${GOALS_PROJECT_TITLE_MODE:-}" ]]; then
                menu_items+=("$((k + 1))" "${rows_title[i]}")
            else
                menu_items+=("$((k + 1))" "${rows_path[i]}")
            fi
        done
        (( page < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page >>")

        prompt="Choose a project${restrict_note} (page $page/$total_pages, $total shown)\n${what^} glob: ${GOALS_PROJECT_GLOB:-none (showing all projects)}"
        (( total == 0 )) && prompt+="\nNo project ${what}s match the current glob."

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "$prompt" 35 175 25 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            __PREV_PAGE__) (( page > 1 )) && page=$((page - 1)) ;;
            __NEXT_PAGE__) (( page < total_pages )) && page=$((page + 1)) ;;
            __APPLY_GLOB__)
                if new_glob=$(whiptail --title "Apply Project ${what^} Glob" --inputbox \
                    "Enter a case-insensitive glob to match project ${what}s (for example: *javascript*). Leave empty to show all projects." \
                    11 90 "$GOALS_PROJECT_GLOB" 3>&1 1>&2 2>&3); then
                    GOALS_PROJECT_GLOB="$new_glob"
                    page=1
                fi
                ;;
            __RESET_GLOB__)
                GOALS_PROJECT_GLOB=""
                page=1
                ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || continue
                k=$((choice - 1))
                (( k >= start && k < end )) || continue
                i=${order[k]}
                GOALS_SELECTED_PROJECT_LINENO="${rows_lineno[i]}"
                GOALS_SELECTED_PROJECT_TITLE="${rows_title[i]}"
                GOALS_SELECTED_PROJECT_PATH="${rows_path[i]}"
                GOALS_SELECTED_PROJECT_NOTES="${rows_notes[i]}"
                GOALS_SELECTED_PROJECT_LINE="${rows_line[i]}"
                return 0
                ;;
        esac
    done
}

# "[a,b,c +2]" style summary of a comma-separated tag list.
goals_truncate_note_tags() {
    local tags="$1"
    local -a arr=()
    if [[ -z "$tags" ]]; then
        printf '[]'
        return
    fi
    IFS=',' read -r -a arr <<< "$tags"
    if (( ${#arr[@]} <= 3 )); then
        printf '[%s]' "$tags"
    else
        printf '[%s,%s,%s +%d]' "${arr[0]}" "${arr[1]}" "${arr[2]}" $(( ${#arr[@]} - 3 ))
    fi
}

# goals_note_has_tag "tag1,tag2" "wanted"  (case-insensitive exact tag match)
goals_note_has_tag() {
    local -a arr=()
    local t
    IFS=',' read -r -a arr <<< "$1"
    for t in "${arr[@]}"; do
        [[ "${t,,}" == "${2,,}" ]] && return 0
    done
    return 1
}

# Simple paginated menu of tag/description pairs.
# Usage: goals_paged_menu "Title" "Prompt" tag1 desc1 tag2 desc2 ...
# Sets GOALS_MENU_CHOICE; returns 1 on Back.
goals_paged_menu() {
    local menu_title="$1" prompt="$2"
    shift 2
    local -a items=("$@") menu_items=()
    local page=1 page_size=30 total total_pages start end k choice

    GOALS_MENU_CHOICE=""
    total=$(( ${#items[@]} / 2 ))
    total_pages=$(( (total + page_size - 1) / page_size ))
    (( total_pages < 1 )) && total_pages=1

    while :; do
        start=$(( (page - 1) * page_size ))
        end=$(( start + page_size ))
        (( end > total )) && end=$total
        menu_items=()
        (( page > 1 )) && menu_items+=("__PREV_PAGE__" "<< Previous page")
        for (( k = start; k < end; k++ )); do
            menu_items+=("${items[2*k]}" "${items[2*k+1]}")
        done
        (( page < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page >>")

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "$prompt (page $page/$total_pages)" 30 100 20 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            __PREV_PAGE__) (( page > 1 )) && page=$((page - 1)) ;;
            __NEXT_PAGE__) (( page < total_pages )) && page=$((page + 1)) ;;
            *) GOALS_MENU_CHOICE="$choice"; return 0 ;;
        esac
    done
}

# Select a note tag (with __FILTER__ / __RESET_FILTER__).
#
# Usage: goals_select_note_tag_filter [options] [--tags t1 t2 ...]
#   --title TEXT         menu title
#   --prompt TEXT        first line of the prompt
#   --pins LIST          comma list of pinned entries: NO, ANY (default "NO,ANY";
#                        use "" for none, "NO" for just [NO TAG])
#   --no-tag-desc TEXT   description of [NO TAG]
#   --any-tag-desc TEXT  description of [ANY TAG]
#   --tags t1 t2 ...     list exactly these tags (must be the last option);
#                        without it every tag in NOTES_TAGS_DB is listed
# __FILTER__ narrows the tag list by a literal (case-insensitive) substring;
# __RESET_FILTER__ clears it. Result in GOALS_SELECTED_NOTE_TAG.
goals_select_note_tag_filter() {
    local menu_title="Select Note Tag to Filter Notes"
    local base_prompt="Choose a tag to filter notes by"
    local pins="NO,ANY"
    local no_tag_desc="Notes that have no tag"
    local any_tag_desc="All notes, with or without tags"
    local use_db=1
    local tag_pattern="" pat_lc tag choice new_pat prompt status
    local page=1 page_size=30 total total_pages start end k
    local -a all_tags=() shown=() menu_items=()

    GOALS_SELECTED_NOTE_TAG=""

    while (( $# > 0 )); do
        case "$1" in
            --title)        menu_title="$2"; shift 2 ;;
            --prompt)       base_prompt="$2"; shift 2 ;;
            --pins)         pins="$2"; shift 2 ;;
            --no-tag-desc)  no_tag_desc="$2"; shift 2 ;;
            --any-tag-desc) any_tag_desc="$2"; shift 2 ;;
            --tags)         shift; use_db=0; all_tags=("$@"); break ;;
            *)              shift ;;
        esac
    done

    if (( use_db )) && [[ -r "$NOTES_TAGS_DB" ]]; then
        while IFS= read -r tag; do
            [[ -n "$tag" ]] && all_tags+=("$tag")
        done < <(sort -f -- "$NOTES_TAGS_DB")
    fi

    while :; do
        shown=()
        pat_lc="${tag_pattern,,}"
        for tag in "${all_tags[@]}"; do
            if [[ -z "$tag_pattern" || "${tag,,}" == *"$pat_lc"* ]]; then
                shown+=("$tag")
            fi
        done

        total=${#shown[@]}
        total_pages=$(( (total + page_size - 1) / page_size ))
        (( total_pages < 1 )) && total_pages=1
        (( page > total_pages )) && page=$total_pages
        start=$(( (page - 1) * page_size ))
        end=$(( start + page_size ))
        (( end > total )) && end=$total

        menu_items=()
        [[ ",$pins," == *,NO,* ]]  && menu_items+=("[NO TAG]" "$no_tag_desc")
        [[ ",$pins," == *,ANY,* ]] && menu_items+=("[ANY TAG]" "$any_tag_desc")
        menu_items+=(
            "__FILTER__" "Filter the tag list (literal substring)"
            "__RESET_FILTER__" "Reset the tag list filter"
        )
        (( page > 1 )) && menu_items+=("__PREV_PAGE__" "<< Previous page")
        for (( k = start; k < end; k++ )); do
            menu_items+=("${shown[k]}" "")
        done
        (( page < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page >>")

        if [[ -n "$tag_pattern" ]]; then
            status="Tag list filter: '$tag_pattern' (literal substring, case-insensitive) - ${total} of ${#all_tags[@]} tags shown"
            (( total == 0 )) && status+=$'\nNo tags contain that text.'
        else
            status="Tag list filter: none - ${#all_tags[@]} tags"
        fi
        (( ${#all_tags[@]} == 0 )) && status+=$'\nThere are no tags to list.'
        prompt="$base_prompt (page $page/$total_pages)\n$status"

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "$prompt" 30 100 20 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            __PREV_PAGE__) (( page > 1 )) && page=$((page - 1)) ;;
            __NEXT_PAGE__) (( page < total_pages )) && page=$((page + 1)) ;;
            __FILTER__)
                if new_pat=$(whiptail --title "Filter Tags" --inputbox \
                    "Enter text to look for in tag names. It is matched literally (no wildcards) and ignoring case. Leave empty to show all tags." \
                    11 80 "$tag_pattern" 3>&1 1>&2 2>&3); then
                    tag_pattern="$new_pat"
                    page=1
                fi
                ;;
            __RESET_FILTER__)
                tag_pattern=""
                page=1
                ;;
            *)
                GOALS_SELECTED_NOTE_TAG="$choice"
                return 0
                ;;
        esac
    done
}

# Multi-select version of goals_pick_note (a checklist).
#
# Usage: goals_pick_notes_multi TITLE PURPOSE ACTION_TAG ACTION_DESC top|bottom path1 path2 ...
#
# Rows show the full note path followed by the note's tags. Control items:
#   __APPLY_GLOB__ (matches note file name), __RESET_GLOB__,
#   __FILTER_BY_TAG__ (then [ANY TAG], [NO TAG], __FILTER__, __RESET_FILTER__),
#   __RESET_FILTER__, plus page navigation and the action item ACTION_TAG.
# Ticked notes are remembered across pages, globs and tag filters.
# The glob/filter live in GOALS_NOTE_GLOB / GOALS_NOTE_TAGFILTER.
#
# Sets GOALS_PICKED_PATHS (array) and returns 0 when the action item is ticked
# with at least one note selected; returns 1 on Back.
goals_pick_notes_multi() {
    local menu_title="$1" purpose="$2" action_tag="$3" action_desc="$4" action_pos="$5"
    shift 5
    local -a cand_paths=("$@") cand_tags=() cand_names=() vis=() items=() sel_items=() page_idx=() split=() menu_tags=()
    local -A db_tags=() selected=() seen_tags=()
    local row_title row_path row_tags p i k t base choice new_glob it
    local page=1 page_size=50 total total_pages start end prompt
    local sel_count hidden has_untagged n_ctl
    local do_apply do_reset_glob do_filter do_reset_filter do_prev do_next do_action

    GOALS_PICKED_PATHS=()

    if (( ${#cand_paths[@]} == 0 )); then
        whiptail --title "$menu_title" --msgbox "There are no notes to choose from." 8 50
        return 1
    fi

    if [[ -r "$NOTES_DB" ]]; then
        while IFS='|' read -r row_title row_path row_tags _; do
            [[ -n "$row_path" ]] && db_tags["$row_path"]="$row_tags"
        done < "$NOTES_DB"
    fi
    for p in "${cand_paths[@]}"; do
        cand_tags+=("${db_tags[$p]:-}")
        cand_names+=("${p##*/}")
    done

    while :; do
        vis=()
        for i in "${!cand_paths[@]}"; do
            if [[ -n "$GOALS_NOTE_GLOB" ]]; then
                [[ "${cand_names[i],,}" == ${GOALS_NOTE_GLOB,,} ]] || continue
            fi
            if [[ -n "$GOALS_NOTE_TAGFILTER" && "$GOALS_NOTE_TAGFILTER" != "[ANY TAG]" ]]; then
                if [[ "$GOALS_NOTE_TAGFILTER" == "[NO TAG]" ]]; then
                    [[ -z "${cand_tags[i]}" ]] || continue
                else
                    goals_note_has_tag "${cand_tags[i]}" "$GOALS_NOTE_TAGFILTER" || continue
                fi
            fi
            vis+=("$i")
        done

        total=${#vis[@]}
        total_pages=$(( (total + page_size - 1) / page_size ))
        (( total_pages < 1 )) && total_pages=1
        (( page > total_pages )) && page=$total_pages
        start=$(( (page - 1) * page_size ))
        end=$(( start + page_size ))
        (( end > total )) && end=$total

        items=()
        [[ "$action_pos" == "top" ]] && items+=("$action_tag" "$action_desc" OFF)
        items+=(
            "__APPLY_GLOB__" "Apply glob (matches note file name)" OFF
            "__RESET_GLOB__" "Reset glob" OFF
            "__FILTER_BY_TAG__" "Filter by tag" OFF
            "__RESET_FILTER__" "Reset tag filter" OFF
        )
        (( page > 1 )) && items+=("__PREV_PAGE__" "<< Previous page" OFF)
        page_idx=()
        for (( k = start; k < end; k++ )); do
            i=${vis[k]}
            page_idx+=("$i")
            if [[ -n "${selected[$i]:-}" ]]; then
                items+=("n$i" "${cand_paths[i]}  $(goals_truncate_note_tags "${cand_tags[i]}")" ON)
            else
                items+=("n$i" "${cand_paths[i]}  $(goals_truncate_note_tags "${cand_tags[i]}")" OFF)
            fi
        done
        (( page < total_pages )) && items+=("__NEXT_PAGE__" "Next page >>" OFF)
        [[ "$action_pos" == "bottom" ]] && items+=("$action_tag" "$action_desc" OFF)

        sel_count=${#selected[@]}
        hidden=0
        for i in "${!selected[@]}"; do
            local found=0
            for k in "${vis[@]}"; do [[ "$k" == "$i" ]] && { found=1; break; }; done
            (( found )) || hidden=$((hidden + 1))
        done

        prompt="$purpose (page $page/$total_pages, $total of ${#cand_paths[@]} notes shown)\nFile name glob: ${GOALS_NOTE_GLOB:-none}\nTag filter: ${GOALS_NOTE_TAGFILTER:-none}\nSelected: $sel_count note(s)"
        (( hidden > 0 )) && prompt+=" ($hidden hidden by the current filters)"
        prompt+="\nTick notes, then tick $action_tag and press OK. Tick only one control item at a time."
        (( total == 0 )) && prompt+="\nNo notes match the current glob and tag filter."

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --checklist "$prompt" 35 155 25 \
            "${items[@]}" 3>&1 1>&2 2>&3) || return 1

        choice=${choice//\"/}
        read -r -a sel_items <<< "$choice"

        # Commit the ticks of the notes on this page.
        for i in "${page_idx[@]}"; do
            unset 'selected[$i]'
        done
        do_apply=0; do_reset_glob=0; do_filter=0; do_reset_filter=0; do_prev=0; do_next=0; do_action=0
        for it in "${sel_items[@]}"; do
            case "$it" in
                __APPLY_GLOB__)    do_apply=1 ;;
                __RESET_GLOB__)    do_reset_glob=1 ;;
                __FILTER_BY_TAG__) do_filter=1 ;;
                __RESET_FILTER__)  do_reset_filter=1 ;;
                __PREV_PAGE__)     do_prev=1 ;;
                __NEXT_PAGE__)     do_next=1 ;;
                "$action_tag")     do_action=1 ;;
                n[0-9]*)           selected["${it#n}"]=1 ;;
            esac
        done

        n_ctl=$(( do_apply + do_reset_glob + do_filter + do_reset_filter + do_prev + do_next + do_action ))
        if (( n_ctl > 1 )); then
            whiptail --title "Invalid selection" --msgbox \
                "Tick only one control item at a time (your ticked notes were kept)." 8 70
            continue
        fi

        if (( do_prev )); then
            (( page > 1 )) && page=$((page - 1))
        elif (( do_next )); then
            (( page < total_pages )) && page=$((page + 1))
        elif (( do_reset_glob )); then
            GOALS_NOTE_GLOB=""; page=1
        elif (( do_reset_filter )); then
            GOALS_NOTE_TAGFILTER=""; page=1
        elif (( do_apply )); then
            if new_glob=$(whiptail --title "Apply Note File Name Glob" --inputbox \
                "Enter a case-insensitive glob to match note file names (for example: *python*). Leave empty to show all notes." \
                11 90 "$GOALS_NOTE_GLOB" 3>&1 1>&2 2>&3); then
                GOALS_NOTE_GLOB="$new_glob"; page=1
            fi
        elif (( do_filter )); then
            # Tags found on the notes that match the current glob.
            seen_tags=(); has_untagged=0
            for i in "${!cand_paths[@]}"; do
                if [[ -n "$GOALS_NOTE_GLOB" ]]; then
                    [[ "${cand_names[i],,}" == ${GOALS_NOTE_GLOB,,} ]] || continue
                fi
                [[ -z "${cand_tags[i]}" ]] && { has_untagged=1; continue; }
                IFS=',' read -r -a split <<< "${cand_tags[i]}"
                for t in "${split[@]}"; do
                    [[ -n "$t" ]] && seen_tags["${t,,}"]="$t"
                done
            done
            menu_tags=()
            if (( ${#seen_tags[@]} > 0 )); then
                while IFS= read -r t; do
                    [[ -n "$t" ]] && menu_tags+=("$t")
                done < <(printf '%s\n' "${seen_tags[@]}" | sort -f)
            fi
            if goals_select_note_tag_filter --title "Filter Notes by Tag" --tags "${menu_tags[@]}"; then
                GOALS_NOTE_TAGFILTER="$GOALS_SELECTED_NOTE_TAG"; page=1
            fi
        elif (( do_action )); then
            if (( ${#selected[@]} == 0 )); then
                whiptail --title "Nothing selected" --msgbox \
                    "Select at least one note before choosing $action_tag." 8 70
                continue
            fi
            GOALS_PICKED_PATHS=()
            for i in "${!cand_paths[@]}"; do
                [[ -n "${selected[$i]:-}" ]] && GOALS_PICKED_PATHS+=("${cand_paths[i]}")
            done
            return 0
        fi
    done
}

# Pick one note from a list of note paths.
#
# Usage: goals_pick_note "Menu title" "Prompt text" path1 path2 ...
#
# Each row shows the full note path followed by the note's tags.
#   __APPLY_GLOB__      case-insensitive glob matched against the note FILE NAME
#   __RESET_GLOB__      clears the glob
#   __FILTER_BY_TAG__   choose a tag (or [NO TAG]) to filter by
#   __RESET_FILTER__    clears the tag filter
# The glob and tag filter live in GOALS_NOTE_GLOB / GOALS_NOTE_TAGFILTER;
# the caller resets them when its workflow starts.
#
# Sets GOALS_PICKED_NOTE_INDEX (0-based position among the paths passed in)
# and GOALS_PICKED_NOTE_PATH. Returns 1 when the user goes Back.
goals_pick_note() {
    local menu_title="$1" purpose="$2"
    shift 2
    local -a cand_paths=("$@") cand_tags=() vis=() menu_items=() tag_items=()
    local -A db_tags=() db_titles=() seen_tags=()
    local -a cand_names=() cand_labels=()
    local glob_label="File name glob" glob_what="note file names" apply_desc="matches note file name" glob_title="File Name"
    if [[ -n "${GOALS_NOTE_TITLE_MODE:-}" ]]; then
        glob_label="Title glob"; glob_what="note titles"; apply_desc="matches note title"; glob_title="Title"
    fi
    local row_title row_path row_tags p i k t base choice new_glob
    local page=1 page_size=50 total total_pages start end prompt tag_label
    local has_untagged=0
    local -a split=()

    GOALS_PICKED_NOTE_INDEX=""
    GOALS_PICKED_NOTE_PATH=""

    if (( ${#cand_paths[@]} == 0 )); then
        whiptail --title "$menu_title" --msgbox "There are no notes to choose from." 8 50
        return 1
    fi

    if [[ -r "$NOTES_DB" ]]; then
        while IFS='|' read -r row_title row_path row_tags _; do
            if [[ -n "$row_path" ]]; then
                db_tags["$row_path"]="$row_tags"
                db_titles["$row_path"]="$row_title"
            fi
        done < "$NOTES_DB"
    fi
    for p in "${cand_paths[@]}"; do
        cand_tags+=("${db_tags[$p]:-}")
        if [[ -n "${GOALS_NOTE_TITLE_MODE:-}" ]]; then
            cand_names+=("${db_titles[$p]:-${p##*/}}")
            cand_labels+=("${db_titles[$p]:-${p##*/}}")
        else
            cand_names+=("${p##*/}")
            cand_labels+=("$p")
        fi
    done

    while :; do
        vis=()
        for i in "${!cand_paths[@]}"; do
            if [[ -n "$GOALS_NOTE_GLOB" ]]; then
                base="${cand_names[i]}"
                [[ "${base,,}" == ${GOALS_NOTE_GLOB,,} ]] || continue
            fi
            if [[ -n "$GOALS_NOTE_TAGFILTER" && "$GOALS_NOTE_TAGFILTER" != "[ANY TAG]" ]]; then
                if [[ "$GOALS_NOTE_TAGFILTER" == "[NO TAG]" ]]; then
                    [[ -z "${cand_tags[i]}" ]] || continue
                else
                    goals_note_has_tag "${cand_tags[i]}" "$GOALS_NOTE_TAGFILTER" || continue
                fi
            fi
            vis+=("$i")
        done

        total=${#vis[@]}
        total_pages=$(( (total + page_size - 1) / page_size ))
        (( total_pages < 1 )) && total_pages=1
        (( page > total_pages )) && page=$total_pages
        start=$(( (page - 1) * page_size ))
        end=$(( start + page_size ))
        (( end > total )) && end=$total

        menu_items=(
            "__APPLY_GLOB__" "Apply glob (${apply_desc})"
            "__RESET_GLOB__" "Reset glob"
            "__FILTER_BY_TAG__" "Filter by tag"
            "__RESET_FILTER__" "Reset tag filter"
        )
        (( page > 1 )) && menu_items+=("__PREV_PAGE__" "<< Previous page")
        for (( k = start; k < end; k++ )); do
            i=${vis[k]}
            menu_items+=("$i" "${cand_labels[i]}  $(goals_truncate_note_tags "${cand_tags[i]}")")
        done
        (( page < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page >>")

        tag_label="${GOALS_NOTE_TAGFILTER:-none}"
        prompt="$purpose (page $page/$total_pages, $total of ${#cand_paths[@]} notes shown)\n${glob_label}: ${GOALS_NOTE_GLOB:-none}\nTag filter: $tag_label"
        (( total == 0 )) && prompt+="\nNo notes match the current glob and tag filter."

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "$prompt" 35 175 25 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            __PREV_PAGE__) (( page > 1 )) && page=$((page - 1)) ;;
            __NEXT_PAGE__) (( page < total_pages )) && page=$((page + 1)) ;;
            __APPLY_GLOB__)
                if new_glob=$(whiptail --title "Apply Note ${glob_title} Glob" --inputbox \
                    "Enter a case-insensitive glob to match ${glob_what} (for example: *python*). Leave empty to show all notes." \
                    11 90 "$GOALS_NOTE_GLOB" 3>&1 1>&2 2>&3); then
                    GOALS_NOTE_GLOB="$new_glob"
                    page=1
                fi
                ;;
            __RESET_GLOB__)
                GOALS_NOTE_GLOB=""
                page=1
                ;;
            __RESET_FILTER__)
                GOALS_NOTE_TAGFILTER=""
                page=1
                ;;
            __FILTER_BY_TAG__)
                # Offer the tags found on notes that match the current glob,
                # so changing the tag filter never requires resetting it first.
                seen_tags=()
                has_untagged=0
                for i in "${!cand_paths[@]}"; do
                    if [[ -n "$GOALS_NOTE_GLOB" ]]; then
                        base="${cand_names[i]}"
                        [[ "${base,,}" == ${GOALS_NOTE_GLOB,,} ]] || continue
                    fi
                    if [[ -z "${cand_tags[i]}" ]]; then
                        has_untagged=1
                        continue
                    fi
                    IFS=',' read -r -a split <<< "${cand_tags[i]}"
                    for t in "${split[@]}"; do
                        [[ -n "$t" ]] && seen_tags["${t,,}"]="$t"
                    done
                done
                if [[ -n "${GOALS_NOTE_TAGMENU_FULL:-}" ]]; then
                    # Full tag menu: [NO TAG], [ANY TAG], __FILTER__ (literal
                    # substring) and __RESET_FILTER__, then the tags.
                    local -a menu_tags=()
                    if (( ${#seen_tags[@]} > 0 )); then
                        while IFS= read -r t; do
                            [[ -n "$t" ]] && menu_tags+=("$t")
                        done < <(printf '%s\n' "${seen_tags[@]}" | sort -f)
                    fi
                    if goals_select_note_tag_filter --title "Filter Notes by Tag" --tags "${menu_tags[@]}"; then
                        GOALS_NOTE_TAGFILTER="$GOALS_SELECTED_NOTE_TAG"
                        page=1
                    fi
                    continue
                fi
                tag_items=()
                (( has_untagged )) && tag_items+=("[NO TAG]" "Notes without tags")
                if (( ${#seen_tags[@]} > 0 )); then
                    while IFS= read -r t; do
                        [[ -n "$t" ]] && tag_items+=("$t" "")
                    done < <(printf '%s\n' "${seen_tags[@]}" | sort -f)
                fi
                if (( ${#tag_items[@]} == 0 )); then
                    whiptail --title "Filter by Tag" --msgbox \
                        "No tags are available among the notes matching the current glob." 8 70
                elif goals_paged_menu "Filter Notes by Tag" "Choose a tag" "${tag_items[@]}"; then
                    GOALS_NOTE_TAGFILTER="$GOALS_MENU_CHOICE"
                    page=1
                fi
                ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || continue
                (( choice < ${#cand_paths[@]} )) || continue
                GOALS_PICKED_NOTE_INDEX="$choice"
                GOALS_PICKED_NOTE_PATH="${cand_paths[choice]}"
                return 0
                ;;
        esac
    done
}

# Unsaved-changes support for the "Manage Goals" project tree menus.
# These read the tree arrays of the calling project editor (Bash dynamic
# scoping), so they work for every copy of that editor.
project_state_sig() {
    local i
    for i in "${!item_id[@]}"; do
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${item_type[i]}" "${item_id[i]}" "${parent_id[i]}" \
            "${item_position[i]}" "${effective_status[i]:-}" \
            "${item_importance[i]}" "${item_content[i]}" "${item_comment[i]}"
    done
}

# Returns 0 when it is fine to leave the editor (nothing unsaved, or the
# user saved / chose to discard) and 1 when the user wants to stay.
project_confirm_leave() {
    [[ "$(project_state_sig)" == "$PROJECT_SAVED_SIG" ]] && return 0

    local answer
    answer=$(whiptail --title "Project: Unsaved Changes" --cancel-button "Stay" \
        --menu "You have unsaved changes in this project. Save them before going back?" \
        14 70 3 \
        "SAVE" "Save changes and go back" \
        "DISCARD" "Discard changes and go back" \
        "STAY" "Stay and keep editing" 3>&1 1>&2 2>&3) || return 1

    case "$answer" in
        SAVE)
            if save_project; then
                PROJECT_SAVED_SIG="$(project_state_sig)"
                return 0
            fi
            return 1
            ;;
        DISCARD) return 0 ;;
        *) return 1 ;;
    esac
}

add_project() {
    local project_title=""
    local project_path=""

    # Main project menu
    while true; do
        local project_title_tr="${project_title:0:80}"
        (( ${#project_title} > 80 )) && project_title_tr+="..."    

        local project_path_tr="$project_path"
        (( ${#project_path} > 80 )) && project_path_tr="${project_path:0:40}...${project_path: -40}"

		local project_action
        project_action=$(whiptail --menu "Project Configuration" 15 150 3 \
            "Project title" "Current: ${project_title_tr:-<not set>}" \
            "Project path" "Status: ${project_path_tr:-(will be generated)}" \
            "Proceed" "" 3>&1 1>&2 2>&3) || return 1

        case $project_action in
            "Project title")
                # FIX: FILTER BANNED CHAR |.
                local old_project_title
                old_project_title="$project_title" # save project title

                project_title=$(whiptail --inputbox "Enter project title" 8 78 "$project_title" 3>&1 1>&2 2>&3)

                # FIX: FILTER BANNED CHAR |.
                if [[ "$project_title" =~ \| ]]; then
                    project_title="$old_project_title"	# Revert
                    whiptail --title "Attention" --msgbox "Project title cannot contain | character." 8 40
                    continue
                fi
                # END FIX.

                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title can't be empty." 8 45
                    continue
                }
                project_path="${PROJECTS_DIR}/${project_title}-$(date "+%d%m%Y-%H%M%S").txt"
                ;;
            "Project path")
                continue
        		;;
            "Proceed")
                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title is required." 8 45
                    continue
                }
                break
                ;;
            *) return 1 ;;
        esac
    done

    save_to_projects_db() {
        local entry="${project_title}|${project_path}|"

        [[ -z "$project_title" || -z "$project_path" ]] && return

        if grep -Fxq -- "$entry" "$PROJECTS_DB" 2>/dev/null; then
            return 0  # already present
        fi

        printf '%s\n' "$entry" >> "$PROJECTS_DB"
    }

    # ============================================================
    # Babyrus - Goal / Project Manager
    #
    # Project file format:
    #
    # TYPE|ID|PARENT_ID|POSITION|STATUS|IMPORTANCE|CONTENT|COMMENT
    #
    # H|1|0|0|NS|N|Programming
    # H|2|1|0|IP|I|Bash
    # H|3|2|0|IP|VI|Whiptail
    # T|4|3|0|C|VI|create checklist menu->implement checklist
    # T|5|3|1|NS|I|support pagination->add prev/next
    #
    # TYPE:
    #   H = heading
    #   T = task
    #
    # STATUS:
    #   NS = not started
    #   IP = in progress
    #   PA = paused
    #   C  = completed
    #
    # IMPORTANCE:
    #   VI = very important
    #   I  = important
    #   N  = normal
    #   NI = not important
    #
    # ============================================================


    # ------------------------------------------------------------
    # Configuration
    # ------------------------------------------------------------

    PROJECT_FILE="$project_path"

    # Verify project file exists--don't need it here because save project later in the next screen.
    # [[ ! -f "$PROJECT_FILE" ]] && {
    #     whiptail --msgbox "Project file not found: ${PROJECT_FILE}" 10 60
    #     return 1
    # }    

    declare -a item_type
    declare -a item_id
    declare -a parent_id
    declare -a item_position
    declare -a item_status
    declare -a item_importance
    declare -a item_content
    declare -a item_comment

    # Calculated/effective status.
    #
    # For tasks:
    #     effective_status == stored status
    #
    # For leaf headings:
    #     effective_status == stored status
    #
    # For container headings:
    #     effective_status is calculated from children.
    #
    declare -a effective_status

    NEXT_ID=1

    # Return status/importance to their friendly names when displaying.
    status_name() {
        case "$1" in
            NS) printf '%s' "Not started" ;;
            IP) printf '%s' "In progress" ;;
            PA) printf '%s' "Paused" ;;
            C)  printf '%s' "Completed" ;;
            *)  printf '%s' "$1" ;;
        esac
    }

    importance_name() {
        case "$1" in
            VI) printf '%s' "Very important" ;;
            I)  printf '%s' "Important" ;;
            N)  printf '%s' "Normal" ;;
            NI) printf '%s' "Not important" ;;
            *)  printf '%s' "$1" ;;
        esac
    }


    # ------------------------------------------------------------
    # Validation helpers
    # ------------------------------------------------------------

    valid_status() {
        case "$1" in
            NS|IP|PA|C) return 0 ;;
            *) return 1 ;;
        esac
    }

    valid_importance() {
        case "$1" in
            VI|I|N|NI) return 0 ;;
            *) return 1 ;;
        esac
    }

    valid_type() {
        [[ "$1" == "H" || "$1" == "T" ]]
    }

    # Find array index for persistent item ID.
    #
    # Returns:
    #   global variable RESULT_INDEX
    #
    find_index_by_id() {
        local wanted_id="$1"
        local i

        RESULT_INDEX=-1

        for i in "${!item_id[@]}"; do
            if [[ "${item_id[i]}" == "$wanted_id" ]]; then
                RESULT_INDEX=$i
                return 0
            fi
        done

        return 1
    }


    # ------------------------------------------------------------
    # Project loading
    # ------------------------------------------------------------

    load_project() {
        local file="${1:-$PROJECT_FILE}"
        local line
        local type id parent position status importance content comment

        item_type=()
        item_id=()
        parent_id=()
        item_position=()
        item_status=()
        item_importance=()
        item_content=()
        item_comment=()
        effective_status=()

        NEXT_ID=1

        [[ -f "$file" ]] || return 0

        while IFS= read -r line || [[ -n "$line" ]]; do

            # Ignore empty lines.
            [[ -z "$line" ]] && continue

            # Comments may be useful during development.
            [[ "$line" == \#* ]] && continue

            IFS='|' read -r type id parent position status importance content comment <<< "$line"

            if [[ -z "$content" ]]; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "Invalid line:\n\n$line" \
                    10 70
                return 1
            fi

            if ! valid_type "$type"; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "Invalid item type '$type'.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            if ! valid_status "$status"; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "Invalid status '$status'.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            if ! valid_importance "$importance"; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "Invalid importance '$importance'.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            if [[ "$content" == *"|"* ]]; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "The content contains '|', which is reserved as a field separator.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            if [[ "$comment" == *"|"* ]]; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "The comment contains '|', which is reserved as a field separator.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            item_type+=("$type")
            item_id+=("$id")
            parent_id+=("$parent")
            item_position+=("$position")
            item_status+=("$status")
            item_importance+=("$importance")
            item_content+=("$content")
            item_comment+=("$comment")

            effective_status+=("$status")

            if [[ "$id" =~ ^[0-9]+$ ]]; then
                (( id >= NEXT_ID )) && NEXT_ID=$((id + 1))
            fi

        done < "$file"

        validate_project || return 1

        calculate_all_statuses
    }


    # ------------------------------------------------------------
    # Structural validation
    # ------------------------------------------------------------

    validate_project() {
        local i parent_index

        for i in "${!item_id[@]}"; do

            # IDs must be numeric.
            if ! [[ "${item_id[i]}" =~ ^[0-9]+$ ]]; then
                whiptail \
                    --title "Invalid Project" \
                    --msgbox "Item ID '${item_id[i]}' is not numeric." \
                    8 60
                return 1
            fi

            # Parent 0 means root.
            if [[ "${parent_id[i]}" == "0" ]]; then

                # Root tasks are not allowed.
                if [[ "${item_type[i]}" == "T" ]]; then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Task '${item_content[i]}' has no heading parent." \
                        8 70
                    return 1
                fi

                continue
            fi

            find_index_by_id "${parent_id[i]}"

            if (( RESULT_INDEX < 0 )); then
                whiptail \
                    --title "Invalid Project" \
                    --msgbox "Item '${item_content[i]}' refers to missing parent ID '${parent_id[i]}'." \
                    8 70
                return 1
            fi

            parent_index=$RESULT_INDEX

            # Tasks can only be children of headings.
            if [[ "${item_type[i]}" == "T" &&
                "${item_type[parent_index]}" != "H" ]]; then

                whiptail \
                    --title "Invalid Project" \
                    --msgbox "Task '${item_content[i]}' is under another task.\n\nTasks may only belong to headings." \
                    10 70
                return 1
            fi

            # Detect immediate self-parent.
            if [[ "${item_id[i]}" == "${parent_id[i]}" ]]; then
                whiptail \
                    --title "Invalid Project" \
                    --msgbox "Item '${item_content[i]}' is its own parent." \
                    8 70
                return 1
            fi
        done

        # Detect circular parent chains.
        for i in "${!item_id[@]}"; do
            if ! hierarchy_is_valid_from "$i"; then
                whiptail \
                    --title "Invalid Project" \
                    --msgbox "A circular hierarchy was detected involving:\n\n${item_content[i]}" \
                    10 70
                return 1
            fi
        done

        return 0
    }


    hierarchy_is_valid_from() {
        local start_index="$1"
        local current_index="$start_index"
        local parent
        local -a visited=()

        while :; do

            # If we've seen this item already, there is a cycle.
            for parent in "${visited[@]}"; do
                [[ "$parent" == "$current_index" ]] && return 1
            done

            visited+=("$current_index")

            parent="${parent_id[current_index]}"

            [[ "$parent" == "0" ]] && return 0

            find_index_by_id "$parent"
            (( RESULT_INDEX >= 0 )) || return 1

            current_index=$RESULT_INDEX
        done
    }


    # ------------------------------------------------------------
    # Tree helpers
    # ------------------------------------------------------------
    get_children() {
        local wanted_parent="$1"
        local i
        local position
        local child_index

        CHILDREN=()

        # Output indices sorted by position.
        while IFS=$'\t' read -r position child_index; do
            [[ -n "$child_index" ]] && CHILDREN+=("$child_index")
        done < <(
            for i in "${!item_id[@]}"; do
                if [[ "${parent_id[i]}" == "$wanted_parent" ]]; then
                    printf '%s\t%s\n' "${item_position[i]}" "$i"
                fi
            done |
            sort -n -k1,1 -k2,2
        )
    }

    get_children_old() {
        local wanted_parent="$1"
        local i

        CHILDREN=()

        # Output indices sorted by position.
        while IFS=$'\t' read -r position index; do
            [[ -n "$index" ]] && CHILDREN+=("$index")
        done < <(
            for i in "${!item_id[@]}"; do
                if [[ "${parent_id[i]}" == "$wanted_parent" ]]; then
                    printf '%s\t%s\n' "${item_position[i]}" "$i"
                fi
            done |
            sort -n -k1,1 -k2,2
        )
    }


    is_container() {
        local index="$1"

        get_children "${item_id[index]}"
        (( ${#CHILDREN[@]} > 0 ))
    }


    get_depth() {
        local index="$1"
        local depth=0
        local current="$index"
        local parent

        while [[ "${parent_id[current]}" != "0" ]]; do
            parent="${parent_id[current]}"

            find_index_by_id "$parent"
            (( RESULT_INDEX >= 0 )) || {
                printf '%s' "$depth"
                return
            }

            current=$RESULT_INDEX
            ((depth++))
        done

        printf '%s' "$depth"
    }


    # ------------------------------------------------------------
    # Status calculation
    # ------------------------------------------------------------

    calculate_status() {
        local index="$1"
        local type="${item_type[index]}"
        local status
        local child
        local child_status

        # Tasks always use their stored status.
        if [[ "$type" == "T" ]]; then
            effective_status[index]="${item_status[index]}"
            printf '%s' "${effective_status[index]}"
            return
        fi

        # Find children.
        get_children "${item_id[index]}"

        # Leaf heading: manually controlled.
        if (( ${#CHILDREN[@]} == 0 )); then
            effective_status[index]="${item_status[index]}"
            printf '%s' "${effective_status[index]}"
            return
        fi

        local has_ns=0
        local has_ip=0
        local has_pa=0
        local has_c=0

        # Container heading: calculate recursively.
        for child in "${CHILDREN[@]}"; do
            child_status="$(calculate_status "$child")"

            case "$child_status" in
                NS) has_ns=1 ;;
                IP) has_ip=1 ;;
                PA) has_pa=1 ;;
                C)  has_c=1 ;;
            esac
        done

        # Aggregation rules:
        #
        # Any active work => IN PROGRESS
        # Otherwise any paused work => PAUSED
        # Completed + not-started => IN PROGRESS
        # All completed => COMPLETED
        # All not-started => NOT STARTED

        if (( has_ip )); then
            status="IP"

        elif (( has_pa )); then
            status="PA"

        elif (( has_c && has_ns )); then
            status="IP"

        elif (( has_c )); then
            status="C"

        else
            status="NS"
        fi

        effective_status[index]="$status"
        printf '%s' "$status"
    }


    calculate_all_statuses() {
        local i

        effective_status=()

        for i in "${!item_id[@]}"; do
            effective_status+=("${item_status[i]}")
        done

        # Calculate every item. Recursive calls ensure that children
        # are resolved before their parents.
        for i in "${!item_id[@]}"; do
            calculate_status "$i" >/dev/null
        done
    }


    # ------------------------------------------------------------
    # Status / importance UI
    # ------------------------------------------------------------

    select_status() {
        local current="$1"

        whiptail \
            --title "Change Status" \
            --menu "Select status:" \
            15 60 6 \
            "NS" "Not started" \
            "IP" "In progress" \
            "PA" "Paused" \
            "C"  "Completed" \
            3>&1 1>&2 2>&3
    }


    select_importance() {
        whiptail \
            --title "Change Importance" \
            --menu "Select importance:" \
            15 60 6 \
            "VI" "Very important" \
            "I"  "Important" \
            "N"  "Normal" \
            "NI" "Not important" \
            3>&1 1>&2 2>&3
    }


    # ------------------------------------------------------------
    # Input helpers
    # ------------------------------------------------------------

    add_heading() {
        local parent="$1"
        local text

        text="$(
            whiptail \
                --title "Add Heading" \
                --inputbox "Heading name:" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$text" ]] && return

        if [[ "$text" == *"|"* ]]; then
            whiptail --msgbox "The heading cannot contain '|'.\n\nIt is reserved by the project file format." 9 70
            return
        fi

        add_item "H" "$parent" "$text"
    }


    add_task() {
        local parent="$1"
        local task
        local plan
        local content

        # Parent must be a heading.
        find_index_by_id "$parent" || return

        if [[ "${item_type[RESULT_INDEX]}" != "H" ]]; then
            whiptail \
                --title "Invalid Parent" \
                --msgbox "Tasks can only be added under headings." \
                8 60
            return
        fi

        task="$(
            whiptail \
                --title "Add Task" \
                --inputbox "Task:" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$task" ]] && return

        plan="$(
            whiptail \
                --title "Add Task Plan" \
                --inputbox "Plan for:\n\n$task" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        if [[ -n "$plan" ]]; then
            content="${task}->${plan}"
        else
            content="$task"
        fi

        if [[ "$content" == *"|"* ]]; then
            whiptail \
                --msgbox "Task or plan cannot contain '|'.\n\nIt is reserved by the project file format." \
                9 70
            return
        fi

        add_item "T" "$parent" "$content"
    }

    find_todo_heading() {
        local i

        TODO_HEADING_ID=""

        for i in "${!item_id[@]}"; do
            if [[ "${item_type[i]}" == "H" &&
                  "${parent_id[i]}" == "0" &&
                  "${item_content[i]}" == "TODO" ]]; then

                TODO_HEADING_ID="${item_id[i]}"
                return 0
            fi
        done

        return 1
    }


    find_todo_date_heading() {
        local todo_id="$1"
        local todo_date="$2"
        local child

        TODO_DATE_HEADING_ID=""

        get_children "$todo_id"

        for child in "${CHILDREN[@]}"; do
            if [[ "${item_type[child]}" == "H" &&
                  "${item_content[child]}" == "$todo_date" ]]; then

                TODO_DATE_HEADING_ID="${item_id[child]}"
                return 0
            fi
        done

        return 1
    }


    next_todo_task_number() {
        local date_heading_id="$1"
        local child
        local number
        local max=0

        get_children "$date_heading_id"

        for child in "${CHILDREN[@]}"; do
            [[ "${item_type[child]}" == "T" ]] || continue

            if number="$(get_number_prefix "${item_content[child]}")"; then
                # Treat the prefix as decimal, even if it has leading zeroes.
                number=$((10#$number))

                (( number > max )) && max="$number"
            fi
        done

        printf '%s' "$((max + 1))"
    }


    add_todo_item() {
        local todo_id
        local todo_date
        local date_heading_id
        local todo_number
        local task
        local content

        # Today's date, for example:
        # Tuesday 29 September 2026
        todo_date="$(date '+%A %-d %B %Y')"

        # ------------------------------------------------------------
        # Find or create the top-level TODO heading.
        # ------------------------------------------------------------

        if find_todo_heading; then
            todo_id="$TODO_HEADING_ID"
        else
            # add_item() increments NEXT_ID, so capture the new
            # heading's ID before calling it.
            todo_id="$NEXT_ID"
            add_item "H" "0" "TODO"
        fi

        # ------------------------------------------------------------
        # Find or create today's date heading under TODO.
        # ------------------------------------------------------------

        if find_todo_date_heading "$todo_id" "$todo_date"; then
            date_heading_id="$TODO_DATE_HEADING_ID"
        else
            # Capture the ID that add_item() will assign.
            date_heading_id="$NEXT_ID"
            add_item "H" "$todo_id" "$todo_date"
        fi

        # ------------------------------------------------------------
        # Ask for the TODO task text.
        # ------------------------------------------------------------

        task="$(
            whiptail \
                --title "Add TODO Item" \
                --inputbox "TODO item for $todo_date:" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$task" ]] && return

        if [[ "$task" == *"|"* ]]; then
            whiptail \
                --title "Invalid TODO Item" \
                --msgbox "The TODO item cannot contain '|'.\n\nIt is reserved by the project file format." \
                9 70
            return
        fi

        # ------------------------------------------------------------
        # Determine the next number under today's date heading.
        # ------------------------------------------------------------

        todo_number="$(next_todo_task_number "$date_heading_id")"
        content="${todo_number}. ${task}"

        add_item "T" "$date_heading_id" "$content"

        # ------------------------------------------------------------
        # Keep today's TODO tasks sorted by their numeric prefix.
        # ------------------------------------------------------------

        sort_children "$date_heading_id"

        # Keep TODO as the first root-level heading.
        sort_children "0"        
    }

    find_rules_for_today_heading() {
        local i

        RULES_FOR_TODAY_ID=""

        for i in "${!item_id[@]}"; do
            if [[ "${item_type[i]}" == "H" &&
                  "${parent_id[i]}" == "0" &&
                  "${item_content[i]}" == "RULES FOR TODAY" ]]; then

                RULES_FOR_TODAY_ID="${item_id[i]}"
                return 0
            fi
        done

        return 1
    }


    find_rules_for_today_date_heading() {
        local rules_id="$1"
        local rules_date="$2"
        local child

        RULES_FOR_TODAY_DATE_ID=""

        get_children "$rules_id"

        for child in "${CHILDREN[@]}"; do
            if [[ "${item_type[child]}" == "H" &&
                  "${item_content[child]}" == "$rules_date" ]]; then

                RULES_FOR_TODAY_DATE_ID="${item_id[child]}"
                return 0
            fi
        done

        return 1
    }


    next_rules_for_today_task_number() {
        local date_heading_id="$1"
        local child
        local number
        local max=0

        get_children "$date_heading_id"

        for child in "${CHILDREN[@]}"; do
            [[ "${item_type[child]}" == "T" ]] || continue

            if number="$(get_number_prefix "${item_content[child]}")"; then
                number=$((10#$number))
                (( number > max )) && max="$number"
            fi
        done

        printf '%s' "$((max + 1))"
    }


    add_rules_for_today_item() {
        local rules_id
        local rules_date
        local date_heading_id
        local rules_number
        local task
        local content

        # Today's date.
        rules_date="$(date '+%A %-d %B %Y')"

        # ------------------------------------------------------------
        # Find or create the top-level RULES FOR TODAY heading.
        # ------------------------------------------------------------

        if find_rules_for_today_heading; then
            rules_id="$RULES_FOR_TODAY_ID"
        else
            rules_id="$NEXT_ID"
            add_item "H" "0" "RULES FOR TODAY"
        fi

        # ------------------------------------------------------------
        # Find or create today's date heading.
        # ------------------------------------------------------------

        if find_rules_for_today_date_heading "$rules_id" "$rules_date"; then
            date_heading_id="$RULES_FOR_TODAY_DATE_ID"
        else
            date_heading_id="$NEXT_ID"
            add_item "H" "$rules_id" "$rules_date"
        fi

        # ------------------------------------------------------------
        # Ask for the rule.
        # ------------------------------------------------------------

        task="$(
            whiptail \
                --title "Add Rule for Today" \
                --inputbox "Rule for $rules_date:" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$task" ]] && return

        if [[ "$task" == *"|"* ]]; then
            whiptail \
                --title "Invalid Rule" \
                --msgbox "The rule cannot contain '|'.\n\nIt is reserved by the project file format." \
                9 70
            return
        fi

        # ------------------------------------------------------------
        # Determine next number for today's rules.
        # ------------------------------------------------------------

        rules_number="$(next_rules_for_today_task_number "$date_heading_id")"
        content="${rules_number}. ${task}"

        add_item "T" "$date_heading_id" "$content"

        # Keep today's rules numerically sorted.
        sort_children "$date_heading_id"

        # Keep the special root headings in their required order.
        sort_children "0"
    }    

    add_item() {
        local type="$1"
        local parent="$2"
        local content="$3"

        local position

        position="$(next_position "$parent")"

        item_type+=("$type")
        item_id+=("$NEXT_ID")
        parent_id+=("$parent")
        item_position+=("$position")

        # New items use default status and importance.
        item_status+=("NS")
        item_importance+=("N")

        item_content+=("$content")
        item_comment+=("")
        effective_status+=("NS")

        ((NEXT_ID++))

        calculate_all_statuses
    }


    next_position() {
        local parent="$1"
        local max=-1
        local i

        for i in "${!item_id[@]}"; do
            if [[ "${parent_id[i]}" == "$parent" ]]; then
                (( item_position[i] > max )) && max="${item_position[i]}"
            fi
        done

        printf '%s' "$((max + 1))"
    }


    # ------------------------------------------------------------
    # Edit item
    # ------------------------------------------------------------

    edit_text() {
        local index="$1"
        local new_text

        new_text="$(
            whiptail \
                --title "Edit Text" \
                --inputbox \
                "Current text:" \
                10 80 \
                "${item_content[index]}" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$new_text" ]] && return

        if [[ "$new_text" == *"|"* ]]; then
            whiptail \
                --title "Invalid Text" \
                --msgbox "'|' cannot be used because it is the project-file field separator." \
                8 70
            return
        fi

        item_content[index]="$new_text"
    }

    edit_task() {
        local index="$1"
        local task plan

        if [[ "${item_content[index]}" == *"->"* ]]; then
            task="${item_content[index]%%->*}"
            plan="${item_content[index]#*->}"
        else
            task="${item_content[index]}"
            plan=""
        fi

        task="$(
            whiptail \
                --title "Edit Task" \
                --inputbox "Task:" \
                10 70 \
                "$task" \
                3>&1 1>&2 2>&3
        )" || return

        # Validate task
        if [[ -z "$task" || "$task" == *"|"* ]]; then
            whiptail \
                --title "Invalid Task" \
                --msgbox "Task cannot be blank or contain the | character." \
                8 60
            return
        fi

        plan="$(
            whiptail \
                --title "Edit Plan" \
                --inputbox "Plan:" \
                10 70 \
                "$plan" \
                3>&1 1>&2 2>&3
        )" || return

        # Validate plan
        if [[ "$plan" == *"|"* ]]; then
            whiptail \
                --title "Invalid Plan" \
                --msgbox "Plan cannot contain the | character." \
                8 60
            return
        fi

        # deal with case where there is no ->
        if [[ -n "$plan" ]]; then
            item_content[index]="${task}->${plan}"
        else
            item_content[index]="$task"
        fi
    }

    edit_comment() {            
        local index="$1"
        local existing_comment="${item_comment[index]}"
        local tempfile
        local comment

        if ! tempfile=$(mktemp); then
            return 1
        fi

        # Ensure cleanup on return or exit
        trap 'rm -f -- "$tempfile"' EXIT RETURN

        # Populate with existing comment
        if [[ -n "$existing_comment" ]]; then
            existing_comment="${existing_comment//\[N\]/$'\n'}"
            if ! printf '%s' "$existing_comment" > "$tempfile"; then
                return 1
            fi
        fi

        while :; do
            if ! "$DEFAULT_EDITOR" "$tempfile"; then
                return 1
            fi

            # Read file contents without losing trailing newlines
            comment=$(cat "$tempfile"; printf 'x')
            comment="${comment%x}"

            # Strip the trailing newline added by nano/editor if present
            comment="${comment%$'\n'}"

            # Check for literal reserved string
            if [[ "$comment" == *'[N]'* ]]; then
                whiptail \
                    --title "Invalid Comment" \
                    --msgbox "The sequence [N] is reserved for newlines and cannot be used in a comment." \
                    8 70
                continue
            fi

            # Convert remaining newlines to [N]
            comment="${comment//$'\n'/[N]}"

            item_comment[index]="$comment"
            return 0
        done
    }

    view_comment() {
        local index="$1"
        local comment="${item_comment[index]}"

        [[ -n "$comment" ]] || comment="No comment has been added."

        comment="${comment//\[N\]/$'\n'}"

        whiptail \
            --title "Comment" \
            --msgbox "$comment" \
            20 80
    }

    edit_comment_old() {
        local index="$1"
        local comment

        comment="$(
            whiptail \
                --title "Comment: ${item_content[index]}" \
                --inputbox "Comment (optional):" \
                14 90 \
                "${item_comment[index]}" \
                3>&1 1>&2 2>&3
        )" || return

        if [[ "$comment" == *"|"* || "$comment" == *$'\n'* ]]; then
            whiptail --msgbox "A comment cannot contain '|' or a line break.\n\nThey are reserved by the project file format." 9 70
            return
        fi

        item_comment[index]="$comment"
    }


    view_comment_old() {
        local index="$1"
        local comment="${item_comment[index]}"

        [[ -n "$comment" ]] || comment="No comment has been added."

        whiptail \
            --title "Comment: ${item_content[index]}" \
            --msgbox "$comment" \
            16 90
    }

    # edit_task() {
    #     local index="$1"
    #     local task plan

    #     if [[ "${item_content[index]}" == *"->"* ]]; then
    #         task="${item_content[index]%%->*}"
    #         plan="${item_content[index]#*->}"
    #     else
    #         task="${item_content[index]}"
    #         plan=""
    #     fi

    #     task="$(
    #         whiptail \
    #             --title "Edit Task" \
    #             --inputbox "Task:" \
    #             10 70 \
    #             "$task" \
    #             3>&1 1>&2 2>&3
    #     )" || return

    #     plan="$(
    #         whiptail \
    #             --title "Edit Plan" \
    #             --inputbox "Plan:" \
    #             10 70 \
    #             "$plan" \
    #             3>&1 1>&2 2>&3
    #     )" || return

    #     item_content[index]="${task}->${plan}"
    # }


    # ------------------------------------------------------------
    # Move
    # ------------------------------------------------------------

    is_descendant_of() {
        local index="$1"
        local ancestor_id="$2"
        local current="$index"

        while [[ "${parent_id[current]}" != "0" ]]; do

            if [[ "${parent_id[current]}" == "$ancestor_id" ]]; then
                return 0
            fi

            find_index_by_id "${parent_id[current]}"
            (( RESULT_INDEX >= 0 )) || return 1

            current=$RESULT_INDEX
        done

        return 1
    }


    choose_move_destination() {
        local moving_index="$1"
        local moving_type="${item_type[moving_index]}"
        local i
        local depth
        local indent
        local label
        local options=()

        # Root destination is allowed for headings only.
        if [[ "$moving_type" == "H" ]]; then
            options+=("0" "[ROOT]")
        fi

        for i in "${!item_id[@]}"; do

            # Can't move under itself.
            [[ "$i" == "$moving_index" ]] && continue

            # Destination must be a heading.
            [[ "${item_type[i]}" == "H" ]] || continue

            # A heading cannot be moved under one of its descendants.
            if [[ "$moving_type" == "H" ]]; then
                if is_descendant_of "$i" "${item_id[moving_index]}"; then
                    continue
                fi
            fi

            depth="$(get_depth "$i")"
            indent=""

            for ((j=0; j<depth; j++)); do
                indent+="    "
            done

            label="${indent}${item_content[i]}"

            options+=("${item_id[i]}" "$label")
        done

        (( ${#options[@]} == 0 )) && return 1

        whiptail \
            --title "Move Item" \
            --menu \
            "Move '${item_content[moving_index]}' under:" \
            22 90 15 \
            "${options[@]}" \
            3>&1 1>&2 2>&3
    }


    move_item() {
        local index="$1"
        local old_parent="${parent_id[index]}"
        local new_parent
        local new_position

        new_parent="$(choose_move_destination "$index")" || return

        # Guard--if old_parent is the same as new_parent, no nothing--no move required!
        [[ "$old_parent" == "$new_parent" ]] && return        

        # Tasks cannot be moved to root.
        if [[ "${item_type[index]}" == "T" && "$new_parent" == "0" ]]; then
            whiptail \
                --title "Invalid Move" \
                --msgbox "Tasks must belong to a heading." \
                8 60
            return
        fi

        new_position="$(next_position "$new_parent")"

        parent_id[index]="$new_parent"
        item_position[index]="$new_position"

        normalize_positions "$old_parent"
        normalize_positions "$new_parent"

        calculate_all_statuses
    }


    normalize_positions() {
        local parent="$1"
        local -a children
        local i position=0

        get_children "$parent"
        children=("${CHILDREN[@]}")

        for i in "${children[@]}"; do
            item_position[i]="$position"
            ((position++))
        done
    }

    # ------------------------------------------------------------
    # Reorder: move an item before/after a sibling of the same kind
    # ------------------------------------------------------------

    # Present the three move modes (before / after / under another heading).
    move_item_menu() {
        local index="$1"
        local action
        local type="${item_type[index]}"
        local kind

        if [[ "$type" == "H" ]]; then
            kind="heading"
        else
            kind="task"
        fi

        while :; do

            action="$(
                whiptail \
                    --title "Move: ${item_content[index]}" \
                    --cancel-button "Back" \
                    --menu \
                    "Choose how to move this $kind:" \
                    18 78 10 \
                    "BEFORE" "Move before another $kind on this level" \
                    "AFTER"  "Move after another $kind on this level" \
                    "PARENT" "Move under another heading" \
                    "BACK"   "Back" \
                    3>&1 1>&2 2>&3
            )" || return

            case "$action" in

                BEFORE)
                    move_item_relative "$index" "before"
                    return
                    ;;

                AFTER)
                    move_item_relative "$index" "after"
                    return
                    ;;

                PARENT)
                    move_item "$index"
                    return
                    ;;

                BACK)
                    return
                    ;;
            esac
        done
    }


    # Move item $index before/after (mode) a same-type sibling on the
    # same level. Sibling positions are reassigned sequentially so the
    # position values on the level stay unique and consecutive.
    move_item_relative() {
        local index="$1"
        local mode="$2"   # "before" or "after"
        local parent="${parent_id[index]}"
        local type="${item_type[index]}"
        local kind
        local child
        local n=0
        local target
        local target_index=-1
        local inserted=0
        local pos=0
        local -a candidates=()
        local -a new_order=()

        if [[ "$type" == "H" ]]; then
            kind="heading"
        else
            kind="task"
        fi

        get_children "$parent"

        # Candidates: siblings of the same type, excluding the item
        # itself, in their current (position-sorted) order.
        for child in "${CHILDREN[@]}"; do
            [[ "$child" == "$index" ]] && continue
            [[ "${item_type[child]}" != "$type" ]] && continue

            ((n++))
            candidates+=(
                "${item_id[child]}"
                "$n) ${item_content[child]}"
            )
        done

        if (( n == 0 )); then
            whiptail \
                --title "Move" \
                --msgbox \
                "There is no other $kind on this level to move next to." \
                8 60
            return
        fi

        target="$(
            whiptail \
                --title "Move $mode" \
                --cancel-button "Back" \
                --menu \
                "Move '${item_content[index]}' $mode which item?" \
                18 180 10 \
                "${candidates[@]}" \
                3>&1 1>&2 2>&3
        )" || return

        # Resolve the chosen item ID back to an index.
        find_index_by_id "$target"
        (( RESULT_INDEX >= 0 )) && target_index=$RESULT_INDEX

        if (( target_index < 0 )); then
            return
        fi

        # Rebuild the sibling order of the whole level minus the moving
        # item, then splice it back in before/after the target.
        for child in "${CHILDREN[@]}"; do
            [[ "$child" == "$index" ]] && continue

            if [[ "$child" == "$target_index" ]]; then
                if [[ "$mode" == "before" ]]; then
                    new_order+=("$index" "$child")
                else
                    new_order+=("$child" "$index")
                fi
                inserted=1
            else
                new_order+=("$child")
            fi
        done

        (( inserted )) || return

        # Reassign positions sequentially, keeping the level consistent
        # exactly as normalize_positions() does.
        pos=0
        for child in "${new_order[@]}"; do
            item_position[child]="$pos"
            ((pos++))
        done
    }

    # ------------------------------------------------------------
    # Delete
    # ------------------------------------------------------------

    collect_descendants() {
        local root_index="$1"
        local child

        DELETE_INDICES+=("$root_index")

        get_children "${item_id[root_index]}"

        for child in "${CHILDREN[@]}"; do
            collect_descendants "$child"
        done
    }


    delete_item() {
        local index="$1"
        local id="${item_id[index]}"
        local old_parent="${parent_id[index]}"
        local count
        local i

        DELETE_INDICES=()
        collect_descendants "$index"

        count="${#DELETE_INDICES[@]}"

        if (( count > 1 )); then
            if ! whiptail \
                --title "Delete Heading" \
                --yesno \
                "'${item_content[index]}' contains $((count - 1)) child item(s).\n\nDelete the entire subtree?" \
                12 70; then
                return
            fi
        else
            if ! whiptail \
                --title "Delete Item" \
                --yesno \
                "Delete '${item_content[index]}'?" \
                10 60; then
                return
            fi
        fi

        # Mark items to delete by their IDs.
        declare -A delete_ids=()

        for i in "${DELETE_INDICES[@]}"; do
            delete_ids["${item_id[i]}"]=1
        done

        local -a new_type=()
        local -a new_id=()
        local -a new_parent=()
        local -a new_position=()
        local -a new_status=()
        local -a new_importance=()
        local -a new_content=()
        local -a new_comment=()
        local -a new_effective=()

        for i in "${!item_id[@]}"; do

            if [[ -n "${delete_ids[${item_id[i]}]+x}" ]]; then
                continue
            fi

            new_type+=("${item_type[i]}")
            new_id+=("${item_id[i]}")
            new_parent+=("${parent_id[i]}")
            new_position+=("${item_position[i]}")
            new_status+=("${item_status[i]}")
            new_importance+=("${item_importance[i]}")
            new_content+=("${item_content[i]}")
            new_comment+=("${item_comment[i]}")
            new_effective+=("${effective_status[i]}")
        done

        item_type=("${new_type[@]}")
        item_id=("${new_id[@]}")
        parent_id=("${new_parent[@]}")
        item_position=("${new_position[@]}")
        item_status=("${new_status[@]}")
        item_importance=("${new_importance[@]}")
        item_content=("${new_content[@]}")
        item_comment=("${new_comment[@]}")
        effective_status=("${new_effective[@]}")

        normalize_positions "$old_parent"

        calculate_all_statuses

        # Avoid unused-variable warning in some shells.
        : "$id"
    }


    # ------------------------------------------------------------
    # Save
    # ------------------------------------------------------------

    save_project() {
        local file="$PROJECT_FILE"
        local tmp="${file}.tmp"
        local i

        calculate_all_statuses

        {
            for i in "${!item_id[@]}"; do

                # Store EFFECTIVE status.
                #
                # This means the saved file always reflects the current
                # calculated status of container headings.
                printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
                    "${item_type[i]}" \
                    "${item_id[i]}" \
                    "${parent_id[i]}" \
                    "${item_position[i]}" \
                    "${effective_status[i]}" \
                    "${item_importance[i]}" \
                    "${item_content[i]}" \
                    "${item_comment[i]}"
            done
        } > "$tmp" || {
            rm -f "$tmp"
            whiptail \
                --title "Save Error" \
                --msgbox "Unable to write temporary project file:\n\n$tmp" \
                10 70
            return 1
        }

        if ! mv -- "$tmp" "$file"; then
            rm -f "$tmp"
            whiptail \
                --title "Save Error" \
                --msgbox "Unable to replace project file:\n\n$file" \
                10 70
            return 1
        fi

        save_to_projects_db || {
            rm -f "$tmp" "$file"
            whiptail \
                --title "Save Error" \
                --msgbox "Unable to save entry to projects database:\n\n$file" \
                10 70
            return 1            
        }

        return 0
    }


    # ------------------------------------------------------------
    # Tree rendering
    # ------------------------------------------------------------

    status_symbol() {
        case "$1" in
            NS) printf '%s' "○" ;;
            IP) printf '%s' "▶" ;;
            PA) printf '%s' "Ⅱ" ;;
            C)  printf '%s' "✓" ;;
            *)  printf '%s' "?" ;;
        esac
    }


    importance_symbol() {
        case "$1" in
            VI) printf '%s' "!!" ;;
            I)  printf '%s' "!" ;;
            N)  printf '%s' "-" ;;
            NI) printf '%s' "." ;;
            *)  printf '%s' "?" ;;
        esac
    }


    format_item_label() {
        local index="$1"
        local depth="$2"
        local indent=""
        local kind
        local status
        local importance

        for ((j=0; j<depth; j++)); do
            indent+="    "
        done

        status="${effective_status[index]}"
        importance="${item_importance[index]}"

        if [[ "${item_type[index]}" == "H" ]]; then
            kind="◆"
        else
            kind="•"
        fi

        printf '%s%s %s %s %s' \
            "$indent" \
            "$kind" \
            "$(status_symbol "$status")" \
            "$(importance_symbol "$importance")" \
            "${item_content[index]}"
    }


    build_tree_options() {
        TREE_OPTIONS=()

        build_tree_options_from_parent "0"
    }


    build_tree_options_from_parent() {
        local wanted_parent="$1"
        local child
        local depth
        local label

        get_children "$wanted_parent"

        for child in "${CHILDREN[@]}"; do
            depth="$(get_depth "$child")"
            label="$(format_item_label "$child" "$depth")"

            TREE_OPTIONS+=(
                "${item_id[child]}"
                "$([[ ${#label} -gt 155 ]] && printf '%s...' "${label:0:157}" || printf '%s' "$label")"
            )

            # Only headings can have children.
            if [[ "${item_type[child]}" == "H" ]]; then
                build_tree_options_from_parent "${item_id[child]}"
            fi
        done
    }


    render_tree() {
        local selected_id

        build_tree_options

        if (( ${#TREE_OPTIONS[@]} == 0 )); then
            whiptail \
                --title "Project Goals" \
                --msgbox "This project contains no goals yet." \
                8 60
            return 1
        fi

        selected_id="$(
            whiptail \
                --title "Project Goals" \
                --cancel-button "Back" \
                --menu \
                "Select an item:" \
                24 110 17 \
                "${TREE_OPTIONS[@]}" \
                3>&1 1>&2 2>&3
        )" || return 1

        find_index_by_id "$selected_id"

        if (( RESULT_INDEX < 0 )); then
            return 1
        fi

        ITEM_SELECTED_INDEX=$RESULT_INDEX

        return 0
    }


    # ------------------------------------------------------------
    # Add menu
    # ------------------------------------------------------------

    add_menu() {
        local destination

        destination="$(
            whiptail \
                --title "Add" \
                --menu \
                "What would you like to add?" \
                12 60 4 \
                "H" "Heading" \
                "T" "Task" \
                3>&1 1>&2 2>&3
        )" || return

        if [[ "$destination" == "H" ]]; then
            add_heading "0"
            return
        fi

        if [[ "$destination" == "T" ]]; then
            # A task needs a heading.
            select_heading_for_parent "0" || return
            add_task "$SELECTED_HEADING_ID"
        fi
    }

    select_heading_for_parent() {
        local parent="$1"

        HEADING_OPTIONS=()

        build_heading_options_from_parent "$parent"

        (( ${#HEADING_OPTIONS[@]} == 0 )) && {
            whiptail \
                --title "No Headings" \
                --msgbox "There are no headings available here." \
                8 60
            return 1
        }

        SELECTED_HEADING_ID="$(
            whiptail \
                --title "Select Heading" \
                --menu \
                "Select the heading:" \
                22 90 15 \
                "${HEADING_OPTIONS[@]}" \
                3>&1 1>&2 2>&3
        )" || return 1

        return 0
    }

    build_heading_options_from_parent() {
        local wanted_parent="$1"
        local child
        local depth
        local label

        get_children "$wanted_parent"

        for child in "${CHILDREN[@]}"; do

            [[ "${item_type[child]}" == "H" ]] || continue

            depth="$(get_depth "$child")"
            label="$(format_item_label "$child" "$depth")"

            HEADING_OPTIONS+=(
                "${item_id[child]}"
                "$label"
            )

            build_heading_options_from_parent "${item_id[child]}"
        done
    }

    # -------------------------------------------------------------
    # Sort children  based on item's numerical prefix.
    # eg. 1) heading or 1. task
    # Sorts parent's immediate children either headings or tasks.
    # -------------------------------------------------------------

    # Return the numeric prefix from an item's content.
    #
    # Examples:
    #   "1. Heading one"  -> 1
    #   "3) Heading three" -> 3
    #   "10. Task ten"    -> 10
    #
    # Returns failure if there is no valid numeric prefix.
    get_number_prefix() {
        local content="$1"

        if [[ "$content" =~ ^([0-9]+)[.\)][[:space:]]+ ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi

        return 1
    }


    has_number_prefix() {
        local content="$1"

        [[ "$content" =~ ^[0-9]+[.\)][[:space:]]+ ]]
    }


    sort_numbered_items() {
        local -n items="$1"

        local item
        local number
        local sorted=()
        local entries=()

        for item in "${items[@]}"; do
            number="$(get_number_prefix "${item_content[item]}")" || continue

            # Include the original item index after the number.
            entries+=("$number"$'\t'"$item")
        done

        # Numeric sort by the first field.
        #
        # sort -n is stable on GNU coreutils when --stable is specified.
        if ((${#entries[@]})); then
            mapfile -t entries < <(
                printf '%s\n' "${entries[@]}" |
                    sort -n -k1,1 -s
            )
        fi

        for entry in "${entries[@]}"; do
            sorted+=("${entry#*$'\t'}")
        done

        items=("${sorted[@]}")
    }


    sort_children() {
        local children
        local todo_heading=()
        local rules_for_today_heading=()
        local numbered_headings=()
        local unnumbered_headings=()
        local numbered_tasks=()
        local unnumbered_tasks=()

        get_children "$1"   # arg is item id NOT index.
        children=("${CHILDREN[@]}")

        for child in "${children[@]}"; do
            case "${item_type[child]}" in
                H)
                    # TODO is always first when it is a root-level heading.
                    if [[ "$1" == "0" &&
                        "${item_content[child]}" == "TODO" ]]; then
                        todo_heading+=("$child")
                    elif [[ "$1" == "0" &&
                            "${item_content[child]}" == "RULES FOR TODAY" ]]; then

                        rules_for_today_heading+=("$child")                        
                    elif has_number_prefix "${item_content[child]}"; then
                        numbered_headings+=("$child")
                    else
                        unnumbered_headings+=("$child")
                    fi
                    ;;

                T)
                    if has_number_prefix "${item_content[child]}"; then
                        numbered_tasks+=("$child")
                    else
                        unnumbered_tasks+=("$child")
                    fi
                    ;;
            esac
        done

        sort_numbered_items numbered_headings
        sort_numbered_items numbered_tasks

        children=(
            "${todo_heading[@]}"
            "${rules_for_today_heading[@]}"
            "${numbered_headings[@]}"
            "${unnumbered_headings[@]}"
            "${numbered_tasks[@]}"
            "${unnumbered_tasks[@]}"
        )

        # Update global 0-based positions.
        for position in "${!children[@]}"; do
            item_position[children[position]]="$position"
        done
    }

    # ------------------------------------------------------------
    # Item action menu
    # ------------------------------------------------------------

    item_menu() {
        local index="$1"
        local action
        local type="${item_type[index]}"

        while :; do

            if [[ "$type" == "H" ]]; then

                action="$(
                    whiptail \
                        --title "${item_content[index]}" \
                        --cancel-button "Back" \
                        --menu \
                        "Status: $(status_name "${effective_status[index]}")\nImportance: $(importance_name "${item_importance[index]}")" \
                        24 80 12 \
                        "TEXT" "Change text" \
                        "STATUS" "Change status" \
                        "IMPORTANCE" "Change importance" \
                        "COMMENT" "Add / edit comment" \
                        "VIEW_COMMENT" "View comment" \
                        "ADD_H" "Add heading" \
                        "ADD_T" "Add task" \
                        "MOVE" "Move" \
                        "SORT" "Sort children by number prefix" \
                        "DELETE" "Delete" \
                        "BACK" "Back" \
                        3>&1 1>&2 2>&3
                )" || return

            else

                action="$(
                    whiptail \
                        --title "${item_content[index]}" \
                        --cancel-button "Back" \
                        --menu \
                        "Status: $(status_name "${effective_status[index]}")\nImportance: $(importance_name "${item_importance[index]}")" \
                        20 75 8 \
                        "TEXT" "Change task / plan" \
                        "STATUS" "Change status" \
                        "IMPORTANCE" "Change importance" \
                        "COMMENT" "Add / edit comment" \
                        "VIEW_COMMENT" "View comment" \
                        "MOVE" "Move" \
                        "DELETE" "Delete" \
                        "BACK" "Back" \
                        3>&1 1>&2 2>&3
                )" || return

            fi

            case "$action" in

                TEXT)
                    if [[ "$type" == "T" ]]; then
                        edit_task "$index"
                    else
                        edit_text "$index"
                    fi
                    ;;

                STATUS)
                    change_status "$index"
                    ;;

                IMPORTANCE)
                    change_importance "$index"
                    ;;

                COMMENT)
                    edit_comment "$index"
                    ;;

                VIEW_COMMENT)
                    view_comment "$index"
                    ;;

                ADD_H)
                    add_heading "${item_id[index]}"
                    ;;

                ADD_T)
                    add_task "${item_id[index]}"
                    ;;

                MOVE)
                    #move_item "$index"
                    move_item_menu "$index"

                    # The arrays may have changed but this item itself
                    # still exists, so locate it again.
                    find_index_by_id "${item_id[index]}"
                    (( RESULT_INDEX >= 0 )) && index=$RESULT_INDEX
                    ;;
                SORT)
                    sort_children "${item_id[index]}"
                    ;;                    

                DELETE)
                    local deleted_id="${item_id[index]}"

                    delete_item "$index"

                    find_index_by_id "$deleted_id"

                    if (( RESULT_INDEX < 0 )); then
                        return
                    fi

                    index=$RESULT_INDEX
                    type="${item_type[index]}"
                    ;;

                BACK)
                    return
                    ;;
            esac

            calculate_all_statuses
        done
    }


    change_status() {
        local index="$1"
        local new_status

        # Container headings are derived from their children.
        if [[ "${item_type[index]}" == "H" ]] && is_container "$index"; then

            new_status="$(
                whiptail \
                    --title "Container Heading" \
                    --menu \
                    "'${item_content[index]}' is a container heading.\n\nSelect an operation:" \
                    16 75 5 \
                    "C" "Complete entire goal" \
                    "PA" "Pause unfinished descendants" \
                    "RESET" "Reset descendants to not started" \
                    3>&1 1>&2 2>&3
            )" || return

            case "$new_status" in
                C)
                    set_subtree_status "$index" "C"
                    ;;

                PA)
                    set_unfinished_subtree_status "$index" "PA"
                    ;;

                RESET)
                    set_subtree_status "$index" "NS"
                    ;;
            esac

            calculate_all_statuses
            return
        fi

        new_status="$(select_status "${item_status[index]}")" || return

        item_status[index]="$new_status"

        calculate_all_statuses
    }


    change_importance() {
        local index="$1"
        local new_importance

        new_importance="$(
            select_importance "${item_importance[index]}"
        )" || return

        item_importance[index]="$new_importance"
    }


    set_subtree_status() {
        local root_index="$1"
        local new_status="$2"
        local child

        item_status[root_index]="$new_status"

        get_children "${item_id[root_index]}"

        for child in "${CHILDREN[@]}"; do
            set_subtree_status "$child" "$new_status"
        done
    }


    set_unfinished_subtree_status() {
        local root_index="$1"
        local child

        if [[ "${effective_status[root_index]}" != "C" ]]; then
            item_status[root_index]="PA"
        fi

        get_children "${item_id[root_index]}"

        for child in "${CHILDREN[@]}"; do
            set_unfinished_subtree_status "$child"
        done
    }


    # ------------------------------------------------------------
    # Main project UI
    # ------------------------------------------------------------

    project_menu() {
        local choice
        local project_file_tr="${PROJECT_FILE:0:80}"
        (( ${#PROJECT_FILE} > 80 )) && project_file_tr+="..."

        local tree_page=0
        local tree_page_size=25   # tree items per page

        # Remember the saved state so Back can detect unsaved changes.
        local PROJECT_SAVED_SIG
        sort_children "0"
        calculate_all_statuses
        PROJECT_SAVED_SIG="$(project_state_sig)"

        while :; do

            sort_children "0"
            calculate_all_statuses
            build_tree_options

            # --- paginate TREE_OPTIONS ---
            local tree_total=$(( ${#TREE_OPTIONS[@]} / 2 ))
            local tree_pages=$(( (tree_total + tree_page_size - 1) / tree_page_size ))
            (( tree_pages == 0 )) && tree_pages=1
            (( tree_page >= tree_pages )) && tree_page=$(( tree_pages - 1 ))
            (( tree_page < 0 )) && tree_page=0
            local tree_start=$(( tree_page * tree_page_size * 2 ))
            local tree_chunk=("${TREE_OPTIONS[@]:tree_start:tree_page_size*2}")

            # static action rows first
            local menu_items=(
                "SYMBOLS" "Help"
                "ADD_H" "Add top-level heading"
                "ADD_T" "Add task"
                "ADD_TODO" "Add TODO item"
                "ADD_RULES" "Add RULES FOR TODAY item"                
                "SORT" "Sort root's children by number prefix"
                "SAVE" "Save changes"
                "REVERT" "Discard changes and reload from disk"
                "---" "PROJECT TREE BELOW ---"
                "" ""
            )

            # navigation rows (only when applicable)
            (( tree_page > 0 )) && menu_items+=("__prev__" "<< Previous page")
            (( tree_page < tree_pages - 1 )) && menu_items+=("__next__" "Next page >>")

            # then the current page of tree items
            menu_items+=("${tree_chunk[@]}")

            choice="$(
                whiptail \
                    --title "Manage Goals" \
                    --cancel-button "Back" \
                    --menu \
                    "Project: $project_file_tr (Page $((tree_page + 1))/$tree_pages)" \
                    45 180 37 \
                    -- \
                    "${menu_items[@]}" \
                    3>&1 1>&2 2>&3
            )" || { project_confirm_leave && break; continue; }

            case "$choice" in
                SYMBOLS)
                    whiptail \
                        --title "Symbol Help" \
                        --msgbox "$(print_symbol_help)" \
                        20 80                
                    ;;

                __prev__)
                    (( tree_page > 0 )) && (( tree_page-- ))
                    continue
                    ;;
                __next__)
                    (( tree_page < tree_pages - 1 )) && (( tree_page++ ))
                    continue
                    ;;

                "---"|"")
                    continue
                    ;;

                ADD_H)
                    add_heading "0"
                    ;;

                ADD_T)
                    if select_heading_for_parent "0"; then
                        add_task "$SELECTED_HEADING_ID"
                    fi
                    ;;

                ADD_TODO)
                    add_todo_item
                    ;;

                ADD_RULES)
                    add_rules_for_today_item
                    ;;                                    

                SORT)
                    sort_children "0"
                    ;;

                SAVE)
                    if save_project; then
                        PROJECT_SAVED_SIG="$(project_state_sig)"
                        whiptail \
                            --title "Saved" \
                            --msgbox "Project saved successfully." \
                            8 50
                    fi
                    ;;

                REVERT)
                    if whiptail \
                        --title "Revert Project" \
                        --yesno \
                        "Discard unsaved changes and reload the project from disk?" \
                        10 70; then

                        if load_project "$PROJECT_FILE"; then
                            sort_children "0"
                            calculate_all_statuses
                            PROJECT_SAVED_SIG="$(project_state_sig)"
                            whiptail \
                                --title "Reverted" \
                                --msgbox "Unsaved changes discarded; project reloaded." \
                                8 50
                        fi
                    fi
                    ;;

                *)
                    # Tree entries use their persistent item ID as the menu tag.
                    find_index_by_id "$choice"
                    if (( RESULT_INDEX >= 0 )); then
                        item_menu "$RESULT_INDEX"
                    fi
                    ;;
            esac
        done        
    }

    # ------------------------------------------------------------
    # Start
    # ------------------------------------------------------------

    if ! command -v whiptail >/dev/null 2>&1; then
        printf 'Error: whiptail is not installed.\n' >&2
        exit 1
    fi

    if ! load_project "$PROJECT_FILE"; then
        exit 1
    fi

    project_menu   
}

add_project_old() {
    local project_title=""
    local project_path=""
    local headings=()
    local indent_levels=()

    # Function to rebuild heading menu with visual indentation
    rebuild_heading_menu() {
        heading_menu=("Add new heading" "")
        for i in "${!headings[@]}"; do
            indent_spaces=$(( indent_levels[i] * 4 ))
            indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
            heading_menu+=("$i" "${indented_heading:0:130}")
        done
    }

    # Main project menu
    while true; do
		local project_action
        project_action=$(whiptail --menu "Project Configuration" 15 150 3 \
            "Project title" "Current: ${project_title:-<not set>}" \
            "Project path" "Status: ${project_path:-(will be generated)}" \
            "Proceed" "" 3>&1 1>&2 2>&3) || return 1

        case $project_action in
            "Project title")
		# FIX: FILTER BANNED CHAR |.
		local old_project_title
		old_project_title="$project_title" # save project title

                project_title=$(whiptail --inputbox "Enter project title" 8 78 "$project_title" 3>&1 1>&2 2>&3)

		# FIX: FILTER BANNED CHAR |.
		if [[ "$project_title" =~ \| ]]; then
			project_title="$old_project_title"	# Revert
			whiptail --title "Attention" --msgbox "Project title cannot contain | character." 8 40
			continue
		fi
		# END FIX.

                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title can't be empty." 8 45
                    continue
                }
                project_path="${PROJECTS_DIR}/${project_title}-$(date "+%d%m%Y-%H%M%S").txt"
                ;;
	    "Project path")
		continue
		;;
            "Proceed")
                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title is required." 8 45
                    continue
                }
                break
                ;;
            *) return 1 ;;
        esac
    done

    # Headings management
    while true; do
        rebuild_heading_menu
        local heading_action
        heading_action=$(whiptail --menu "Project: ${project_title}" 20 150 10 -- \
            "${heading_menu[@]}" "Save and return" "" 3>&1 1>&2 2>&3) || return 1

        case $heading_action in
            "Add new heading")
				local new_heading
                new_heading=$(whiptail --inputbox "Enter new heading:" 8 78 3>&1 1>&2 2>&3)
                if [[ -n "$new_heading" ]]; then
                    headings+=("$new_heading")
                    indent_levels+=(0)
                fi
                ;;
            "Save and return")
                break
                ;;
            *)
                if [[ "$heading_action" =~ ^[0-9]+$ ]]; then
                    local selected_index=$heading_action
                    local heading_operation
                    heading_operation=$(whiptail --menu "Heading Operations" 20 60 7 \
                        "Change text" "" \
                        "Move before" "" \
                        "Move after" "" \
                        "Indent left" "" \
                        "Indent right" "" \
                        "Remove heading" "" 3>&1 1>&2 2>&3)

                    case $heading_operation in
                        "Change text")
							local new_text
                            new_text=$(whiptail --inputbox "Enter new heading text:" 8 78 \
                                "${headings[$selected_index]}" 3>&1 1>&2 2>&3)
                            headings[$selected_index]="$new_text"
                            ;;
                        "Move before"|"Move after")
                            # LOGIC ERROR FIX: IF HEADINGS COUNT IS LESS THAN OR EQUAL TO ONE, CONTINUE.
                            [[ ${#headings[@]} -le 1 ]] && continue

                            # Get target position using indices
                            local targets=()
                            for i in "${!headings[@]}"; do
                                [[ $i -ne $selected_index ]] && {
                                    indent_spaces=$(( indent_levels[i] * 4 ))
                                    indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
                                    targets+=("$i" "$indented_heading")
                                }
                            done

							local target_index
                            target_index=$(whiptail --menu "Select target heading:" 20 150 10 \
                                "${targets[@]}" 3>&1 1>&2 2>&3)
                            [[ -z "$target_index" ]] && continue
                            target_index=$((target_index))

                            # Store original positions
                            local original_source_pos=$selected_index
                            local original_target_pos=$target_index
                            local moving_heading="${headings[$original_source_pos]}"
                            local moving_indent="${indent_levels[$original_source_pos]}"

                            # Remove source from original position
                            headings=(
                                "${headings[@]:0:$original_source_pos}"
                                "${headings[@]:$((original_source_pos+1))}"
                            )
                            indent_levels=(
                                "${indent_levels[@]:0:$original_source_pos}"
                                "${indent_levels[@]:$((original_source_pos+1))}"
                            )

                            # Adjust target index for new array
                            if (( original_source_pos < original_target_pos )); then
                                adjusted_target_pos=$((original_target_pos - 1))
                            else
                                adjusted_target_pos=$original_target_pos
                            fi

                            # Apply "Move after" adjustment
                            if [[ "$heading_operation" == "Move after" ]]; then
                                ((adjusted_target_pos++))
                            fi

                            # Insert at new position
                            headings=(
                                "${headings[@]:0:$adjusted_target_pos}"
                                "$moving_heading"
                                "${headings[@]:$adjusted_target_pos}"
                            )
                            indent_levels=(
                                "${indent_levels[@]:0:$adjusted_target_pos}"
                                "$moving_indent"
                                "${indent_levels[@]:$adjusted_target_pos}"
                            )
                            ;;                            
                        "Indent right")
                            (( indent_levels[$selected_index]++ ))
                            ;;
                        "Indent left")
                            (( indent_levels[$selected_index] = indent_levels[$selected_index] > 0 ? indent_levels[$selected_index]-1 : 0 ))
                            ;;
                        "Remove heading")
                            headings=("${headings[@]:0:$selected_index}" "${headings[@]:$((selected_index+1))}")
                            indent_levels=("${indent_levels[@]:0:$selected_index}" "${indent_levels[@]:$((selected_index+1))}")
                            ;;
                        *) ;;
                    esac
                fi
                ;;
        esac
    done

    # Save project file
    {
        for i in "${!headings[@]}"; do
            printf "%$((indent_levels[i]*4))s%s\n" "" "${headings[$i]}"
        done
    } > "$project_path"

    # Update projects database
    echo "${project_title}|${project_path}|" >> "$PROJECTS_DB"
}

edit_project() {
    # Check if projects database exists and has entries
    [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]] && {
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

    # Pick a project by full path. __APPLY_GLOB__ matches the project file
    # name and __RESET_GLOB__ clears the glob.
    GOALS_PROJECT_GLOB=""
    goals_select_project "Edit Project" || return 1

    local -a lines=()
    local selected_index=$(( GOALS_SELECTED_PROJECT_LINENO - 1 ))

    # DIRTY FIX: OVERWRITE LINES TO CONTAIN ALL LINES FROM PROJECTS_DB.
    mapfile -t lines < "$PROJECTS_DB"

    # Parse selected project
    local old_title old_path old_notes
    IFS='|' read -r old_title old_path old_notes <<< "${lines[$selected_index]}"

    # Verify project file exists
    [[ ! -f "$old_path" ]] && {
        whiptail --msgbox "Project file not found: $old_path" 10 60
        return 1
    }

    save_to_projects_db() {
        local entry="${project_title}|${project_path}|"
        [[ -z "$project_title" || -z "$project_path" ]] && return

        if grep -Fxq -- "$entry" "$PROJECTS_DB" 2>/dev/null; then
            return 0  # already present
        fi

        printf '%s\n' "$entry" >> "$PROJECTS_DB"
    }

    # ============================================================
    # Babyrus - Goal / Project Manager
    #
    # Project file format:
    #
    # TYPE|ID|PARENT_ID|POSITION|STATUS|IMPORTANCE|CONTENT|COMMENT
    #
    # H|1|0|0|NS|N|Programming
    # H|2|1|0|IP|I|Bash
    # H|3|2|0|IP|VI|Whiptail
    # T|4|3|0|C|VI|create checklist menu->implement checklist
    # T|5|3|1|NS|I|support pagination->add prev/next
    #
    # TYPE:
    #   H = heading
    #   T = task
    #
    # STATUS:
    #   NS = not started
    #   IP = in progress
    #   PA = paused
    #   C  = completed
    #
    # IMPORTANCE:
    #   VI = very important
    #   I  = important
    #   N  = normal
    #   NI = not important
    #
    # ============================================================


    # ------------------------------------------------------------
    # Configuration
    # ------------------------------------------------------------

    PROJECT_FILE="$old_path"

    declare -a item_type
    declare -a item_id
    declare -a parent_id
    declare -a item_position
    declare -a item_status
    declare -a item_importance
    declare -a item_content
    declare -a item_comment

    # Calculated/effective status.
    #
    # For tasks:
    #     effective_status == stored status
    #
    # For leaf headings:
    #     effective_status == stored status
    #
    # For container headings:
    #     effective_status is calculated from children.
    #
    declare -a effective_status

    NEXT_ID=1

    # Return status/importance to their friendly names when displaying.
    status_name() {
        case "$1" in
            NS) printf '%s' "Not started" ;;
            IP) printf '%s' "In progress" ;;
            PA) printf '%s' "Paused" ;;
            C)  printf '%s' "Completed" ;;
            *)  printf '%s' "$1" ;;
        esac
    }

    importance_name() {
        case "$1" in
            VI) printf '%s' "Very important" ;;
            I)  printf '%s' "Important" ;;
            N)  printf '%s' "Normal" ;;
            NI) printf '%s' "Not important" ;;
            *)  printf '%s' "$1" ;;
        esac
    }


    # ------------------------------------------------------------
    # Validation helpers
    # ------------------------------------------------------------

    valid_status() {
        case "$1" in
            NS|IP|PA|C) return 0 ;;
            *) return 1 ;;
        esac
    }

    valid_importance() {
        case "$1" in
            VI|I|N|NI) return 0 ;;
            *) return 1 ;;
        esac
    }

    valid_type() {
        [[ "$1" == "H" || "$1" == "T" ]]
    }

    # Find array index for persistent item ID.
    #
    # Returns:
    #   global variable RESULT_INDEX
    #
    find_index_by_id() {
        local wanted_id="$1"
        local i

        RESULT_INDEX=-1

        for i in "${!item_id[@]}"; do
            if [[ "${item_id[i]}" == "$wanted_id" ]]; then
                RESULT_INDEX=$i
                return 0
            fi
        done

        return 1
    }


    # ------------------------------------------------------------
    # Project loading
    # ------------------------------------------------------------

    load_project() {
        local file="${1:-$PROJECT_FILE}"
        local line
        local type id parent position status importance content comment

        item_type=()
        item_id=()
        parent_id=()
        item_position=()
        item_status=()
        item_importance=()
        item_content=()
        item_comment=()
        effective_status=()

        NEXT_ID=1

        [[ -f "$file" ]] || return 0

        while IFS= read -r line || [[ -n "$line" ]]; do

            # Ignore empty lines.
            [[ -z "$line" ]] && continue

            # Comments may be useful during development.
            [[ "$line" == \#* ]] && continue

            IFS='|' read -r type id parent position status importance content comment <<< "$line"

            if [[ -z "$content" ]]; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "Invalid line:\n\n$line" \
                    10 70
                return 1
            fi

            if ! valid_type "$type"; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "Invalid item type '$type'.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            if ! valid_status "$status"; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "Invalid status '$status'.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            if ! valid_importance "$importance"; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "Invalid importance '$importance'.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            if [[ "$content" == *"|"* ]]; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "The content contains '|', which is reserved as a field separator.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            if [[ "$comment" == *"|"* ]]; then
                whiptail \
                    --title "Invalid Project File" \
                    --msgbox "The comment contains '|', which is reserved as a field separator.\n\nLine:\n$line" \
                    10 70
                return 1
            fi

            item_type+=("$type")
            item_id+=("$id")
            parent_id+=("$parent")
            item_position+=("$position")
            item_status+=("$status")
            item_importance+=("$importance")
            item_content+=("$content")
            item_comment+=("$comment")

            effective_status+=("$status")

            if [[ "$id" =~ ^[0-9]+$ ]]; then
                (( id >= NEXT_ID )) && NEXT_ID=$((id + 1))
            fi

        done < "$file"

        validate_project || return 1

        calculate_all_statuses
    }


    # ------------------------------------------------------------
    # Structural validation
    # ------------------------------------------------------------

    validate_project() {
        local i parent_index

        for i in "${!item_id[@]}"; do

            # IDs must be numeric.
            if ! [[ "${item_id[i]}" =~ ^[0-9]+$ ]]; then
                whiptail \
                    --title "Invalid Project" \
                    --msgbox "Item ID '${item_id[i]}' is not numeric." \
                    8 60
                return 1
            fi

            # Parent 0 means root.
            if [[ "${parent_id[i]}" == "0" ]]; then

                # Root tasks are not allowed.
                if [[ "${item_type[i]}" == "T" ]]; then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Task '${item_content[i]}' has no heading parent." \
                        8 70
                    return 1
                fi

                continue
            fi

            find_index_by_id "${parent_id[i]}"

            if (( RESULT_INDEX < 0 )); then
                whiptail \
                    --title "Invalid Project" \
                    --msgbox "Item '${item_content[i]}' refers to missing parent ID '${parent_id[i]}'." \
                    8 70
                return 1
            fi

            parent_index=$RESULT_INDEX

            # Tasks can only be children of headings.
            if [[ "${item_type[i]}" == "T" &&
                "${item_type[parent_index]}" != "H" ]]; then

                whiptail \
                    --title "Invalid Project" \
                    --msgbox "Task '${item_content[i]}' is under another task.\n\nTasks may only belong to headings." \
                    10 70
                return 1
            fi

            # Detect immediate self-parent.
            if [[ "${item_id[i]}" == "${parent_id[i]}" ]]; then
                whiptail \
                    --title "Invalid Project" \
                    --msgbox "Item '${item_content[i]}' is its own parent." \
                    8 70
                return 1
            fi
        done

        # Detect circular parent chains.
        for i in "${!item_id[@]}"; do
            if ! hierarchy_is_valid_from "$i"; then
                whiptail \
                    --title "Invalid Project" \
                    --msgbox "A circular hierarchy was detected involving:\n\n${item_content[i]}" \
                    10 70
                return 1
            fi
        done

        return 0
    }


    hierarchy_is_valid_from() {
        local start_index="$1"
        local current_index="$start_index"
        local parent
        local -a visited=()

        while :; do

            # If we've seen this item already, there is a cycle.
            for parent in "${visited[@]}"; do
                [[ "$parent" == "$current_index" ]] && return 1
            done

            visited+=("$current_index")

            parent="${parent_id[current_index]}"

            [[ "$parent" == "0" ]] && return 0

            find_index_by_id "$parent"
            (( RESULT_INDEX >= 0 )) || return 1

            current_index=$RESULT_INDEX
        done
    }


    # ------------------------------------------------------------
    # Tree helpers
    # ------------------------------------------------------------
    get_children() {
        local wanted_parent="$1"
        local i
        local position
        local child_index

        CHILDREN=()

        # Output indices sorted by position.
        while IFS=$'\t' read -r position child_index; do
            [[ -n "$child_index" ]] && CHILDREN+=("$child_index")
        done < <(
            for i in "${!item_id[@]}"; do
                if [[ "${parent_id[i]}" == "$wanted_parent" ]]; then
                    printf '%s\t%s\n' "${item_position[i]}" "$i"
                fi
            done |
            sort -n -k1,1 -k2,2
        )
    }

    get_children_old() {
        local wanted_parent="$1"
        local i

        CHILDREN=()

        # Output indices sorted by position.
        while IFS=$'\t' read -r position index; do
            [[ -n "$index" ]] && CHILDREN+=("$index")
        done < <(
            for i in "${!item_id[@]}"; do
                if [[ "${parent_id[i]}" == "$wanted_parent" ]]; then
                    printf '%s\t%s\n' "${item_position[i]}" "$i"
                fi
            done |
            sort -n -k1,1 -k2,2
        )
    }


    is_container() {
        local index="$1"

        get_children "${item_id[index]}"
        (( ${#CHILDREN[@]} > 0 ))
    }


    get_depth() {
        local index="$1"
        local depth=0
        local current="$index"
        local parent

        while [[ "${parent_id[current]}" != "0" ]]; do
            parent="${parent_id[current]}"

            find_index_by_id "$parent"
            (( RESULT_INDEX >= 0 )) || {
                printf '%s' "$depth"
                return
            }

            current=$RESULT_INDEX
            ((depth++))
        done

        printf '%s' "$depth"
    }


    # ------------------------------------------------------------
    # Status calculation
    # ------------------------------------------------------------

    calculate_status() {
        local index="$1"
        local type="${item_type[index]}"
        local status
        local child
        local child_status

        # Tasks always use their stored status.
        if [[ "$type" == "T" ]]; then
            effective_status[index]="${item_status[index]}"
            printf '%s' "${effective_status[index]}"
            return
        fi

        # Find children.
        get_children "${item_id[index]}"

        # Leaf heading: manually controlled.
        if (( ${#CHILDREN[@]} == 0 )); then
            effective_status[index]="${item_status[index]}"
            printf '%s' "${effective_status[index]}"
            return
        fi

        local has_ns=0
        local has_ip=0
        local has_pa=0
        local has_c=0

        # Container heading: calculate recursively.
        for child in "${CHILDREN[@]}"; do
            child_status="$(calculate_status "$child")"

            case "$child_status" in
                NS) has_ns=1 ;;
                IP) has_ip=1 ;;
                PA) has_pa=1 ;;
                C)  has_c=1 ;;
            esac
        done

        # Aggregation rules:
        #
        # Any active work => IN PROGRESS
        # Otherwise any paused work => PAUSED
        # Completed + not-started => IN PROGRESS
        # All completed => COMPLETED
        # All not-started => NOT STARTED

        if (( has_ip )); then
            status="IP"

        elif (( has_pa )); then
            status="PA"

        elif (( has_c && has_ns )); then
            status="IP"

        elif (( has_c )); then
            status="C"

        else
            status="NS"
        fi

        effective_status[index]="$status"
        printf '%s' "$status"
    }


    calculate_all_statuses() {
        local i

        effective_status=()

        for i in "${!item_id[@]}"; do
            effective_status+=("${item_status[i]}")
        done

        # Calculate every item. Recursive calls ensure that children
        # are resolved before their parents.
        for i in "${!item_id[@]}"; do
            calculate_status "$i" >/dev/null
        done
    }


    # ------------------------------------------------------------
    # Status / importance UI
    # ------------------------------------------------------------

    select_status() {
        local current="$1"

        whiptail \
            --title "Change Status" \
            --menu "Select status:" \
            15 60 6 \
            "NS" "Not started" \
            "IP" "In progress" \
            "PA" "Paused" \
            "C"  "Completed" \
            3>&1 1>&2 2>&3
    }


    select_importance() {
        whiptail \
            --title "Change Importance" \
            --menu "Select importance:" \
            15 60 6 \
            "VI" "Very important" \
            "I"  "Important" \
            "N"  "Normal" \
            "NI" "Not important" \
            3>&1 1>&2 2>&3
    }


    # ------------------------------------------------------------
    # Input helpers
    # ------------------------------------------------------------

    add_heading() {
        local parent="$1"
        local text

        text="$(
            whiptail \
                --title "Add Heading" \
                --inputbox "Heading name:" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$text" ]] && return

        if [[ "$text" == *"|"* ]]; then
            whiptail --msgbox "The heading cannot contain '|'.\n\nIt is reserved by the project file format." 9 70
            return
        fi

        add_item "H" "$parent" "$text"
    }


    add_task() {
        local parent="$1"
        local task
        local plan
        local content

        # Parent must be a heading.
        find_index_by_id "$parent" || return

        if [[ "${item_type[RESULT_INDEX]}" != "H" ]]; then
            whiptail \
                --title "Invalid Parent" \
                --msgbox "Tasks can only be added under headings." \
                8 60
            return
        fi

        task="$(
            whiptail \
                --title "Add Task" \
                --inputbox "Task:" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$task" ]] && return

        plan="$(
            whiptail \
                --title "Add Task Plan" \
                --inputbox "Plan for:\n\n$task" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        if [[ -n "$plan" ]]; then
            content="${task}->${plan}"
        else
            content="$task"
        fi

        if [[ "$content" == *"|"* ]]; then
            whiptail \
                --msgbox "Task or plan cannot contain '|'.\n\nIt is reserved by the project file format." \
                9 70
            return
        fi

        add_item "T" "$parent" "$content"
    }

    find_todo_heading() {
        local i

        TODO_HEADING_ID=""

        for i in "${!item_id[@]}"; do
            if [[ "${item_type[i]}" == "H" &&
                  "${parent_id[i]}" == "0" &&
                  "${item_content[i]}" == "TODO" ]]; then

                TODO_HEADING_ID="${item_id[i]}"
                return 0
            fi
        done

        return 1
    }


    find_todo_date_heading() {
        local todo_id="$1"
        local todo_date="$2"
        local child

        TODO_DATE_HEADING_ID=""

        get_children "$todo_id"

        for child in "${CHILDREN[@]}"; do
            if [[ "${item_type[child]}" == "H" &&
                  "${item_content[child]}" == "$todo_date" ]]; then

                TODO_DATE_HEADING_ID="${item_id[child]}"
                return 0
            fi
        done

        return 1
    }


    next_todo_task_number() {
        local date_heading_id="$1"
        local child
        local number
        local max=0

        get_children "$date_heading_id"

        for child in "${CHILDREN[@]}"; do
            [[ "${item_type[child]}" == "T" ]] || continue

            if number="$(get_number_prefix "${item_content[child]}")"; then
                # Treat the prefix as decimal, even if it has leading zeroes.
                number=$((10#$number))

                (( number > max )) && max="$number"
            fi
        done

        printf '%s' "$((max + 1))"
    }

    find_rules_for_today_heading() {
        local i

        RULES_FOR_TODAY_ID=""

        for i in "${!item_id[@]}"; do
            if [[ "${item_type[i]}" == "H" &&
                  "${parent_id[i]}" == "0" &&
                  "${item_content[i]}" == "RULES FOR TODAY" ]]; then

                RULES_FOR_TODAY_ID="${item_id[i]}"
                return 0
            fi
        done

        return 1
    }


    find_rules_for_today_date_heading() {
        local rules_id="$1"
        local rules_date="$2"
        local child

        RULES_FOR_TODAY_DATE_ID=""

        get_children "$rules_id"

        for child in "${CHILDREN[@]}"; do
            if [[ "${item_type[child]}" == "H" &&
                  "${item_content[child]}" == "$rules_date" ]]; then

                RULES_FOR_TODAY_DATE_ID="${item_id[child]}"
                return 0
            fi
        done

        return 1
    }


    next_rules_for_today_task_number() {
        local date_heading_id="$1"
        local child
        local number
        local max=0

        get_children "$date_heading_id"

        for child in "${CHILDREN[@]}"; do
            [[ "${item_type[child]}" == "T" ]] || continue

            if number="$(get_number_prefix "${item_content[child]}")"; then
                number=$((10#$number))
                (( number > max )) && max="$number"
            fi
        done

        printf '%s' "$((max + 1))"
    }


    add_rules_for_today_item() {
        local rules_id
        local rules_date
        local date_heading_id
        local rules_number
        local task
        local content

        # Today's date.
        rules_date="$(date '+%A %-d %B %Y')"

        # ------------------------------------------------------------
        # Find or create the top-level RULES FOR TODAY heading.
        # ------------------------------------------------------------

        if find_rules_for_today_heading; then
            rules_id="$RULES_FOR_TODAY_ID"
        else
            rules_id="$NEXT_ID"
            add_item "H" "0" "RULES FOR TODAY"
        fi

        # ------------------------------------------------------------
        # Find or create today's date heading.
        # ------------------------------------------------------------

        if find_rules_for_today_date_heading "$rules_id" "$rules_date"; then
            date_heading_id="$RULES_FOR_TODAY_DATE_ID"
        else
            date_heading_id="$NEXT_ID"
            add_item "H" "$rules_id" "$rules_date"
        fi

        # ------------------------------------------------------------
        # Ask for the rule.
        # ------------------------------------------------------------

        task="$(
            whiptail \
                --title "Add Rule for Today" \
                --inputbox "Rule for $rules_date:" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$task" ]] && return

        if [[ "$task" == *"|"* ]]; then
            whiptail \
                --title "Invalid Rule" \
                --msgbox "The rule cannot contain '|'.\n\nIt is reserved by the project file format." \
                9 70
            return
        fi

        # ------------------------------------------------------------
        # Determine next number for today's rules.
        # ------------------------------------------------------------

        rules_number="$(next_rules_for_today_task_number "$date_heading_id")"
        content="${rules_number}. ${task}"

        add_item "T" "$date_heading_id" "$content"

        # Keep today's rules numerically sorted.
        sort_children "$date_heading_id"

        # Keep the special root headings in their required order.
        sort_children "0"
    }

    add_todo_item() {
        local todo_id
        local todo_date
        local date_heading_id
        local todo_number
        local task
        local content

        # Today's date, for example:
        # Tuesday 29 September 2026
        todo_date="$(date '+%A %-d %B %Y')"

        # ------------------------------------------------------------
        # Find or create the top-level TODO heading.
        # ------------------------------------------------------------

        if find_todo_heading; then
            todo_id="$TODO_HEADING_ID"
        else
            # add_item() increments NEXT_ID, so capture the new
            # heading's ID before calling it.
            todo_id="$NEXT_ID"
            add_item "H" "0" "TODO"
        fi

        # ------------------------------------------------------------
        # Find or create today's date heading under TODO.
        # ------------------------------------------------------------

        if find_todo_date_heading "$todo_id" "$todo_date"; then
            date_heading_id="$TODO_DATE_HEADING_ID"
        else
            # Capture the ID that add_item() will assign.
            date_heading_id="$NEXT_ID"
            add_item "H" "$todo_id" "$todo_date"
        fi

        # ------------------------------------------------------------
        # Ask for the TODO task text.
        # ------------------------------------------------------------

        task="$(
            whiptail \
                --title "Add TODO Item" \
                --inputbox "TODO item for $todo_date:" \
                10 70 \
                "" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$task" ]] && return

        if [[ "$task" == *"|"* ]]; then
            whiptail \
                --title "Invalid TODO Item" \
                --msgbox "The TODO item cannot contain '|'.\n\nIt is reserved by the project file format." \
                9 70
            return
        fi

        # ------------------------------------------------------------
        # Determine the next number under today's date heading.
        # ------------------------------------------------------------

        todo_number="$(next_todo_task_number "$date_heading_id")"
        content="${todo_number}. ${task}"

        add_item "T" "$date_heading_id" "$content"

        # ------------------------------------------------------------
        # Keep today's TODO tasks sorted by their numeric prefix.
        # ------------------------------------------------------------

        sort_children "$date_heading_id"

        # Keep TODO as the first root-level heading.
        sort_children "0"        
    }

    add_item() {
        local type="$1"
        local parent="$2"
        local content="$3"

        local position

        position="$(next_position "$parent")"

        item_type+=("$type")
        item_id+=("$NEXT_ID")
        parent_id+=("$parent")
        item_position+=("$position")

        # New items use default status and importance.
        item_status+=("NS")
        item_importance+=("N")

        item_content+=("$content")
        item_comment+=("")
        effective_status+=("NS")

        ((NEXT_ID++))

        calculate_all_statuses
    }


    next_position() {
        local parent="$1"
        local max=-1
        local i

        for i in "${!item_id[@]}"; do
            if [[ "${parent_id[i]}" == "$parent" ]]; then
                (( item_position[i] > max )) && max="${item_position[i]}"
            fi
        done

        printf '%s' "$((max + 1))"
    }


    # ------------------------------------------------------------
    # Edit item
    # ------------------------------------------------------------

    edit_text() {
        local index="$1"
        local new_text

        new_text="$(
            whiptail \
                --title "Edit Text" \
                --inputbox \
                "Current text:" \
                10 80 \
                "${item_content[index]}" \
                3>&1 1>&2 2>&3
        )" || return

        [[ -z "$new_text" ]] && return

        if [[ "$new_text" == *"|"* ]]; then
            whiptail \
                --title "Invalid Text" \
                --msgbox "'|' cannot be used because it is the project-file field separator." \
                8 70
            return
        fi

        item_content[index]="$new_text"
    }

    edit_task() {
        local index="$1"
        local task plan

        if [[ "${item_content[index]}" == *"->"* ]]; then
            task="${item_content[index]%%->*}"
            plan="${item_content[index]#*->}"
        else
            task="${item_content[index]}"
            plan=""
        fi

        task="$(
            whiptail \
                --title "Edit Task" \
                --inputbox "Task:" \
                10 70 \
                "$task" \
                3>&1 1>&2 2>&3
        )" || return

        # Validate task
        if [[ -z "$task" || "$task" == *"|"* ]]; then
            whiptail \
                --title "Invalid Task" \
                --msgbox "Task cannot be blank or contain the | character." \
                8 60
            return
        fi

        plan="$(
            whiptail \
                --title "Edit Plan" \
                --inputbox "Plan:" \
                10 70 \
                "$plan" \
                3>&1 1>&2 2>&3
        )" || return

        # Validate plan
        if [[ "$plan" == *"|"* ]]; then
            whiptail \
                --title "Invalid Plan" \
                --msgbox "Plan cannot contain the | character." \
                8 60
            return
        fi

        # deal with case where there is no ->
        if [[ -n "$plan" ]]; then
            item_content[index]="${task}->${plan}"
        else
            item_content[index]="$task"
        fi
    }

    edit_comment() {            
        local index="$1"
        local existing_comment="${item_comment[index]}"
        local tempfile
        local comment

        if ! tempfile=$(mktemp); then
            return 1
        fi

        # Ensure cleanup on return or exit
        trap 'rm -f -- "$tempfile"' EXIT RETURN

        # Populate with existing comment
        if [[ -n "$existing_comment" ]]; then
            existing_comment="${existing_comment//\[N\]/$'\n'}"
            if ! printf '%s' "$existing_comment" > "$tempfile"; then
                return 1
            fi
        fi

        while :; do
            if ! "$DEFAULT_EDITOR" "$tempfile"; then
                return 1
            fi

            # Read file contents without losing trailing newlines
            comment=$(cat "$tempfile"; printf 'x')
            comment="${comment%x}"

            # Strip the trailing newline added by nano/editor if present
            comment="${comment%$'\n'}"

            # Check for literal reserved string
            if [[ "$comment" == *'[N]'* ]]; then
                whiptail \
                    --title "Invalid Comment" \
                    --msgbox "The sequence [N] is reserved for newlines and cannot be used in a comment." \
                    8 70
                continue
            fi

            # Convert remaining newlines to [N]
            comment="${comment//$'\n'/[N]}"

            item_comment[index]="$comment"
            return 0
        done
    }

    view_comment() {
        local index="$1"
        local comment="${item_comment[index]}"

        [[ -n "$comment" ]] || comment="No comment has been added."

        comment="${comment//\[N\]/$'\n'}"

        whiptail \
            --title "Comment" \
            --msgbox "$comment" \
            20 80
    }

    edit_comment_old() {
        local index="$1"
        local comment

        comment="$(
            whiptail \
                --title "Comment: ${item_content[index]}" \
                --inputbox "Comment (optional):" \
                14 90 \
                "${item_comment[index]}" \
                3>&1 1>&2 2>&3
        )" || return

        if [[ "$comment" == *"|"* || "$comment" == *$'\n'* ]]; then
            whiptail --msgbox "A comment cannot contain '|' or a line break.\n\nThey are reserved by the project file format." 9 70
            return
        fi

        item_comment[index]="$comment"
    }


    view_comment_old() {
        local index="$1"
        local comment="${item_comment[index]}"

        [[ -n "$comment" ]] || comment="No comment has been added."

        whiptail \
            --title "Comment: ${item_content[index]}" \
            --msgbox "$comment" \
            16 90
    }

    # edit_task() {
    #     local index="$1"
    #     local task plan

    #     if [[ "${item_content[index]}" == *"->"* ]]; then
    #         task="${item_content[index]%%->*}"
    #         plan="${item_content[index]#*->}"
    #     else
    #         task="${item_content[index]}"
    #         plan=""
    #     fi

    #     task="$(
    #         whiptail \
    #             --title "Edit Task" \
    #             --inputbox "Task:" \
    #             10 70 \
    #             "$task" \
    #             3>&1 1>&2 2>&3
    #     )" || return

    #     plan="$(
    #         whiptail \
    #             --title "Edit Plan" \
    #             --inputbox "Plan:" \
    #             10 70 \
    #             "$plan" \
    #             3>&1 1>&2 2>&3
    #     )" || return

    #     item_content[index]="${task}->${plan}"
    # }


    # ------------------------------------------------------------
    # Move
    # ------------------------------------------------------------

    is_descendant_of() {
        local index="$1"
        local ancestor_id="$2"
        local current="$index"

        while [[ "${parent_id[current]}" != "0" ]]; do

            if [[ "${parent_id[current]}" == "$ancestor_id" ]]; then
                return 0
            fi

            find_index_by_id "${parent_id[current]}"
            (( RESULT_INDEX >= 0 )) || return 1

            current=$RESULT_INDEX
        done

        return 1
    }


    choose_move_destination() {
        local moving_index="$1"
        local moving_type="${item_type[moving_index]}"
        local i
        local depth
        local indent
        local label
        local options=()

        # Root destination is allowed for headings only.
        if [[ "$moving_type" == "H" ]]; then
            options+=("0" "[ROOT]")
        fi

        for i in "${!item_id[@]}"; do

            # Can't move under itself.
            [[ "$i" == "$moving_index" ]] && continue

            # Destination must be a heading.
            [[ "${item_type[i]}" == "H" ]] || continue

            # A heading cannot be moved under one of its descendants.
            if [[ "$moving_type" == "H" ]]; then
                if is_descendant_of "$i" "${item_id[moving_index]}"; then
                    continue
                fi
            fi

            depth="$(get_depth "$i")"
            indent=""

            for ((j=0; j<depth; j++)); do
                indent+="    "
            done

            label="${indent}${item_content[i]}"

            options+=("${item_id[i]}" "$label")
        done

        (( ${#options[@]} == 0 )) && return 1

        whiptail \
            --title "Move Item" \
            --menu \
            "Move '${item_content[moving_index]}' under:" \
            22 90 15 \
            "${options[@]}" \
            3>&1 1>&2 2>&3
    }


    move_item() {
        local index="$1"
        local old_parent="${parent_id[index]}"
        local new_parent
        local new_position

        new_parent="$(choose_move_destination "$index")" || return

        # Guard--if old_parent is the same as new_parent, no nothing--no move required!
        [[ "$old_parent" == "$new_parent" ]] && return

        # Tasks cannot be moved to root.
        if [[ "${item_type[index]}" == "T" && "$new_parent" == "0" ]]; then
            whiptail \
                --title "Invalid Move" \
                --msgbox "Tasks must belong to a heading." \
                8 60
            return
        fi

        new_position="$(next_position "$new_parent")"

        parent_id[index]="$new_parent"
        item_position[index]="$new_position"

        normalize_positions "$old_parent"
        normalize_positions "$new_parent"

        calculate_all_statuses
    }


    normalize_positions() {
        local parent="$1"
        local -a children
        local i position=0

        get_children "$parent"
        children=("${CHILDREN[@]}")

        for i in "${children[@]}"; do
            item_position[i]="$position"
            ((position++))
        done
    }

    # ------------------------------------------------------------
    # Reorder: move an item before/after a sibling of the same kind
    # ------------------------------------------------------------

    # Present the three move modes (before / after / under another heading).
    move_item_menu() {
        local index="$1"
        local action
        local type="${item_type[index]}"
        local kind

        if [[ "$type" == "H" ]]; then
            kind="heading"
        else
            kind="task"
        fi

        while :; do

            action="$(
                whiptail \
                    --title "Move: ${item_content[index]}" \
                    --cancel-button "Back" \
                    --menu \
                    "Choose how to move this $kind:" \
                    18 78 10 \
                    "BEFORE" "Move before another $kind on this level" \
                    "AFTER"  "Move after another $kind on this level" \
                    "PARENT" "Move under another heading" \
                    "BACK"   "Back" \
                    3>&1 1>&2 2>&3
            )" || return

            case "$action" in

                BEFORE)
                    move_item_relative "$index" "before"
                    return
                    ;;

                AFTER)
                    move_item_relative "$index" "after"
                    return
                    ;;

                PARENT)
                    move_item "$index"
                    return
                    ;;

                BACK)
                    return
                    ;;
            esac
        done
    }


    # Move item $index before/after (mode) a same-type sibling on the
    # same level. Sibling positions are reassigned sequentially so the
    # position values on the level stay unique and consecutive.
    move_item_relative() {
        local index="$1"
        local mode="$2"   # "before" or "after"
        local parent="${parent_id[index]}"
        local type="${item_type[index]}"
        local kind
        local child
        local n=0
        local target
        local target_index=-1
        local inserted=0
        local pos=0
        local -a candidates=()
        local -a new_order=()

        if [[ "$type" == "H" ]]; then
            kind="heading"
        else
            kind="task"
        fi

        get_children "$parent"

        # Candidates: siblings of the same type, excluding the item
        # itself, in their current (position-sorted) order.
        for child in "${CHILDREN[@]}"; do
            [[ "$child" == "$index" ]] && continue
            [[ "${item_type[child]}" != "$type" ]] && continue

            ((n++))
            candidates+=(
                "${item_id[child]}"
                "$n) ${item_content[child]}"
            )
        done

        if (( n == 0 )); then
            whiptail \
                --title "Move" \
                --msgbox \
                "There is no other $kind on this level to move next to." \
                8 60
            return
        fi

        target="$(
            whiptail \
                --title "Move $mode" \
                --cancel-button "Back" \
                --menu \
                "Move '${item_content[index]}' $mode which item?" \
                18 180 10 \
                "${candidates[@]}" \
                3>&1 1>&2 2>&3
        )" || return

        # Resolve the chosen item ID back to an index.
        find_index_by_id "$target"
        (( RESULT_INDEX >= 0 )) && target_index=$RESULT_INDEX

        if (( target_index < 0 )); then
            return
        fi

        # Rebuild the sibling order of the whole level minus the moving
        # item, then splice it back in before/after the target.
        for child in "${CHILDREN[@]}"; do
            [[ "$child" == "$index" ]] && continue

            if [[ "$child" == "$target_index" ]]; then
                if [[ "$mode" == "before" ]]; then
                    new_order+=("$index" "$child")
                else
                    new_order+=("$child" "$index")
                fi
                inserted=1
            else
                new_order+=("$child")
            fi
        done

        (( inserted )) || return

        # Reassign positions sequentially, keeping the level consistent
        # exactly as normalize_positions() does.
        pos=0
        for child in "${new_order[@]}"; do
            item_position[child]="$pos"
            ((pos++))
        done
    }

    # ------------------------------------------------------------
    # Delete
    # ------------------------------------------------------------

    collect_descendants() {
        local root_index="$1"
        local child

        DELETE_INDICES+=("$root_index")

        get_children "${item_id[root_index]}"

        for child in "${CHILDREN[@]}"; do
            collect_descendants "$child"
        done
    }


    delete_item() {
        local index="$1"
        local id="${item_id[index]}"
        local old_parent="${parent_id[index]}"
        local count
        local i

        DELETE_INDICES=()
        collect_descendants "$index"

        count="${#DELETE_INDICES[@]}"

        if (( count > 1 )); then
            if ! whiptail \
                --title "Delete Heading" \
                --yesno \
                "'${item_content[index]}' contains $((count - 1)) child item(s).\n\nDelete the entire subtree?" \
                12 70; then
                return
            fi
        else
            if ! whiptail \
                --title "Delete Item" \
                --yesno \
                "Delete '${item_content[index]}'?" \
                10 60; then
                return
            fi
        fi

        # Mark items to delete by their IDs.
        declare -A delete_ids=()

        for i in "${DELETE_INDICES[@]}"; do
            delete_ids["${item_id[i]}"]=1
        done

        local -a new_type=()
        local -a new_id=()
        local -a new_parent=()
        local -a new_position=()
        local -a new_status=()
        local -a new_importance=()
        local -a new_content=()
        local -a new_comment=()
        local -a new_effective=()

        for i in "${!item_id[@]}"; do

            if [[ -n "${delete_ids[${item_id[i]}]+x}" ]]; then
                continue
            fi

            new_type+=("${item_type[i]}")
            new_id+=("${item_id[i]}")
            new_parent+=("${parent_id[i]}")
            new_position+=("${item_position[i]}")
            new_status+=("${item_status[i]}")
            new_importance+=("${item_importance[i]}")
            new_content+=("${item_content[i]}")
            new_comment+=("${item_comment[i]}")
            new_effective+=("${effective_status[i]}")
        done

        item_type=("${new_type[@]}")
        item_id=("${new_id[@]}")
        parent_id=("${new_parent[@]}")
        item_position=("${new_position[@]}")
        item_status=("${new_status[@]}")
        item_importance=("${new_importance[@]}")
        item_content=("${new_content[@]}")
        item_comment=("${new_comment[@]}")
        effective_status=("${new_effective[@]}")

        normalize_positions "$old_parent"

        calculate_all_statuses

        # Avoid unused-variable warning in some shells.
        : "$id"
    }


    # ------------------------------------------------------------
    # Save
    # ------------------------------------------------------------

    save_project() {
        local file="$PROJECT_FILE"
        local tmp="${file}.tmp"
        local i

        calculate_all_statuses

        {
            for i in "${!item_id[@]}"; do

                # Store EFFECTIVE status.
                #
                # This means the saved file always reflects the current
                # calculated status of container headings.
                printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
                    "${item_type[i]}" \
                    "${item_id[i]}" \
                    "${parent_id[i]}" \
                    "${item_position[i]}" \
                    "${effective_status[i]}" \
                    "${item_importance[i]}" \
                    "${item_content[i]}" \
                    "${item_comment[i]}"
            done
        } > "$tmp" || {
            rm -f "$tmp"
            whiptail \
                --title "Save Error" \
                --msgbox "Unable to write temporary project file:\n\n$tmp" \
                10 70
            return 1
        }

        if ! mv -- "$tmp" "$file"; then
            rm -f "$tmp"
            whiptail \
                --title "Save Error" \
                --msgbox "Unable to replace project file:\n\n$file" \
                10 70
            return 1
        fi

        save_to_projects_db || {
            rm -f "$tmp" "$file"
            whiptail \
                --title "Save Error" \
                --msgbox "Unable to save entry to projects database:\n\n$file" \
                10 70
            return 1            
        }

        return 0
    }


    # ------------------------------------------------------------
    # Tree rendering
    # ------------------------------------------------------------

    status_symbol() {
        case "$1" in
            NS) printf '%s' "○" ;;
            IP) printf '%s' "▶" ;;
            PA) printf '%s' "Ⅱ" ;;
            C)  printf '%s' "✓" ;;
            *)  printf '%s' "?" ;;
        esac
    }


    importance_symbol() {
        case "$1" in
            VI) printf '%s' "!!" ;;
            I)  printf '%s' "!" ;;
            N)  printf '%s' "-" ;;
            NI) printf '%s' "." ;;
            *)  printf '%s' "?" ;;
        esac
    }


    format_item_label() {
        local index="$1"
        local depth="$2"
        local indent=""
        local kind
        local status
        local importance

        for ((j=0; j<depth; j++)); do
            indent+="    "
        done

        status="${effective_status[index]}"
        importance="${item_importance[index]}"

        if [[ "${item_type[index]}" == "H" ]]; then
            kind="◆"
        else
            kind="•"
        fi

        printf '%s%s %s %s %s' \
            "$indent" \
            "$kind" \
            "$(status_symbol "$status")" \
            "$(importance_symbol "$importance")" \
            "${item_content[index]}"
    }


    build_tree_options() {
        TREE_OPTIONS=()

        build_tree_options_from_parent "0"
    }


    build_tree_options_from_parent() {
        local wanted_parent="$1"
        local child
        local depth
        local label

        get_children "$wanted_parent"

        for child in "${CHILDREN[@]}"; do
            depth="$(get_depth "$child")"
            label="$(format_item_label "$child" "$depth")"

            TREE_OPTIONS+=(
                "${item_id[child]}"
                "$([[ ${#label} -gt 155 ]] && printf '%s...' "${label:0:157}" || printf '%s' "$label")"
            )

            # Only headings can have children.
            if [[ "${item_type[child]}" == "H" ]]; then
                build_tree_options_from_parent "${item_id[child]}"
            fi
        done
    }


    render_tree() {
        local selected_id

        build_tree_options

        if (( ${#TREE_OPTIONS[@]} == 0 )); then
            whiptail \
                --title "Project Goals" \
                --msgbox "This project contains no goals yet." \
                8 60
            return 1
        fi

        selected_id="$(
            whiptail \
                --title "Project Goals" \
                --cancel-button "Back" \
                --menu \
                "Select an item:" \
                24 110 17 \
                "${TREE_OPTIONS[@]}" \
                3>&1 1>&2 2>&3
        )" || return 1

        find_index_by_id "$selected_id"

        if (( RESULT_INDEX < 0 )); then
            return 1
        fi

        ITEM_SELECTED_INDEX=$RESULT_INDEX

        return 0
    }


    # ------------------------------------------------------------
    # Add menu
    # ------------------------------------------------------------

    add_menu() {
        local destination

        destination="$(
            whiptail \
                --title "Add" \
                --menu \
                "What would you like to add?" \
                12 60 4 \
                "H" "Heading" \
                "T" "Task" \
                3>&1 1>&2 2>&3
        )" || return

        if [[ "$destination" == "H" ]]; then
            add_heading "0"
            return
        fi

        if [[ "$destination" == "T" ]]; then
            # A task needs a heading.
            select_heading_for_parent "0" || return
            add_task "$SELECTED_HEADING_ID"
        fi
    }

    select_heading_for_parent() {
        local parent="$1"

        HEADING_OPTIONS=()

        build_heading_options_from_parent "$parent"

        (( ${#HEADING_OPTIONS[@]} == 0 )) && {
            whiptail \
                --title "No Headings" \
                --msgbox "There are no headings available here." \
                8 60
            return 1
        }

        SELECTED_HEADING_ID="$(
            whiptail \
                --title "Select Heading" \
                --menu \
                "Select the heading:" \
                22 90 15 \
                "${HEADING_OPTIONS[@]}" \
                3>&1 1>&2 2>&3
        )" || return 1

        return 0
    }

    build_heading_options_from_parent() {
        local wanted_parent="$1"
        local child
        local depth
        local label

        get_children "$wanted_parent"

        for child in "${CHILDREN[@]}"; do

            [[ "${item_type[child]}" == "H" ]] || continue

            depth="$(get_depth "$child")"
            label="$(format_item_label "$child" "$depth")"

            HEADING_OPTIONS+=(
                "${item_id[child]}"
                "$label"
            )

            build_heading_options_from_parent "${item_id[child]}"
        done
    }

    # -------------------------------------------------------------
    # Sort children  based on item's numerical prefix.
    # eg. 1) heading or 1. task
    # Sorts parent's immediate children either headings or tasks.
    # -------------------------------------------------------------

    # Return the numeric prefix from an item's content.
    #
    # Examples:
    #   "1. Heading one"  -> 1
    #   "3) Heading three" -> 3
    #   "10. Task ten"    -> 10
    #
    # Returns failure if there is no valid numeric prefix.
    get_number_prefix() {
        local content="$1"

        if [[ "$content" =~ ^([0-9]+)[.\)][[:space:]]+ ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi

        return 1
    }


    has_number_prefix() {
        local content="$1"

        [[ "$content" =~ ^[0-9]+[.\)][[:space:]]+ ]]
    }


    sort_numbered_items() {
        local -n items="$1"

        local item
        local number
        local sorted=()
        local entries=()

        for item in "${items[@]}"; do
            number="$(get_number_prefix "${item_content[item]}")" || continue

            # Include the original item index after the number.
            entries+=("$number"$'\t'"$item")
        done

        # Numeric sort by the first field.
        #
        # sort -n is stable on GNU coreutils when --stable is specified.
        if ((${#entries[@]})); then
            mapfile -t entries < <(
                printf '%s\n' "${entries[@]}" |
                    sort -n -k1,1 -s
            )
        fi

        for entry in "${entries[@]}"; do
            sorted+=("${entry#*$'\t'}")
        done

        items=("${sorted[@]}")
    }


    sort_children() {
        local children
        local todo_heading=()
        local rules_for_today_heading=()
        local numbered_headings=()
        local unnumbered_headings=()
        local numbered_tasks=()
        local unnumbered_tasks=()

        get_children "$1"   # arg is item id NOT index.
        children=("${CHILDREN[@]}")

        for child in "${children[@]}"; do
            case "${item_type[child]}" in
                H)
                    # TODO is always first when it is a root-level heading.
                    if [[ "$1" == "0" &&
                        "${item_content[child]}" == "TODO" ]]; then
                        todo_heading+=("$child")
                    elif [[ "$1" == "0" &&
                            "${item_content[child]}" == "RULES FOR TODAY" ]]; then

                        rules_for_today_heading+=("$child")                        
                    elif has_number_prefix "${item_content[child]}"; then
                        numbered_headings+=("$child")
                    else
                        unnumbered_headings+=("$child")
                    fi
                    ;;

                T)
                    if has_number_prefix "${item_content[child]}"; then
                        numbered_tasks+=("$child")
                    else
                        unnumbered_tasks+=("$child")
                    fi
                    ;;
            esac
        done

        sort_numbered_items numbered_headings
        sort_numbered_items numbered_tasks

        children=(
            "${todo_heading[@]}"
            "${rules_for_today_heading[@]}"
            "${numbered_headings[@]}"
            "${unnumbered_headings[@]}"
            "${numbered_tasks[@]}"
            "${unnumbered_tasks[@]}"
        )

        # Update global 0-based positions.
        for position in "${!children[@]}"; do
            item_position[children[position]]="$position"
        done
    }

    # ------------------------------------------------------------
    # Item action menu
    # ------------------------------------------------------------

    item_menu() {
        local index="$1"
        local action
        local type="${item_type[index]}"

        while :; do

            if [[ "$type" == "H" ]]; then

                action="$(
                    whiptail \
                        --title "${item_content[index]}" \
                        --cancel-button "Back" \
                        --menu \
                        "Status: $(status_name "${effective_status[index]}")\nImportance: $(importance_name "${item_importance[index]}")" \
                        24 80 12 \
                        "TEXT" "Change text" \
                        "STATUS" "Change status" \
                        "IMPORTANCE" "Change importance" \
                        "COMMENT" "Add / edit comment" \
                        "VIEW_COMMENT" "View comment" \
                        "ADD_H" "Add heading" \
                        "ADD_T" "Add task" \
                        "MOVE" "Move" \
                        "SORT" "Sort children by number prefix" \
                        "DELETE" "Delete" \
                        "BACK" "Back" \
                        3>&1 1>&2 2>&3
                )" || return

            else

                action="$(
                    whiptail \
                        --title "${item_content[index]}" \
                        --cancel-button "Back" \
                        --menu \
                        "Status: $(status_name "${effective_status[index]}")\nImportance: $(importance_name "${item_importance[index]}")" \
                        20 75 8 \
                        "TEXT" "Change task / plan" \
                        "STATUS" "Change status" \
                        "IMPORTANCE" "Change importance" \
                        "COMMENT" "Add / edit comment" \
                        "VIEW_COMMENT" "View comment" \
                        "MOVE" "Move" \
                        "DELETE" "Delete" \
                        "BACK" "Back" \
                        3>&1 1>&2 2>&3
                )" || return

            fi

            case "$action" in

                TEXT)
                    if [[ "$type" == "T" ]]; then
                        edit_task "$index"
                    else
                        edit_text "$index"
                    fi
                    ;;

                STATUS)
                    change_status "$index"
                    ;;

                IMPORTANCE)
                    change_importance "$index"
                    ;;

                COMMENT)
                    edit_comment "$index"
                    ;;

                VIEW_COMMENT)
                    view_comment "$index"
                    ;;

                ADD_H)
                    add_heading "${item_id[index]}"
                    ;;

                ADD_T)
                    add_task "${item_id[index]}"
                    ;;

                MOVE)
                    #move_item "$index"
                    move_item_menu "$index"

                    # The arrays may have changed but this item itself
                    # still exists, so locate it again.
                    find_index_by_id "${item_id[index]}"
                    (( RESULT_INDEX >= 0 )) && index=$RESULT_INDEX
                    ;;

                SORT)
                    sort_children "${item_id[index]}"
                    ;;

                DELETE)
                    local deleted_id="${item_id[index]}"

                    delete_item "$index"

                    find_index_by_id "$deleted_id"

                    if (( RESULT_INDEX < 0 )); then
                        return
                    fi

                    index=$RESULT_INDEX
                    type="${item_type[index]}"
                    ;;

                BACK)
                    return
                    ;;
            esac

            calculate_all_statuses
        done
    }


    change_status() {
        local index="$1"
        local new_status

        # Container headings are derived from their children.
        if [[ "${item_type[index]}" == "H" ]] && is_container "$index"; then

            new_status="$(
                whiptail \
                    --title "Container Heading" \
                    --menu \
                    "'${item_content[index]}' is a container heading.\n\nSelect an operation:" \
                    16 75 5 \
                    "C" "Complete entire goal" \
                    "PA" "Pause unfinished descendants" \
                    "RESET" "Reset descendants to not started" \
                    3>&1 1>&2 2>&3
            )" || return

            case "$new_status" in
                C)
                    set_subtree_status "$index" "C"
                    ;;

                PA)
                    set_unfinished_subtree_status "$index" "PA"
                    ;;

                RESET)
                    set_subtree_status "$index" "NS"
                    ;;
            esac

            calculate_all_statuses
            return
        fi

        new_status="$(select_status "${item_status[index]}")" || return

        item_status[index]="$new_status"

        calculate_all_statuses
    }


    change_importance() {
        local index="$1"
        local new_importance

        new_importance="$(
            select_importance "${item_importance[index]}"
        )" || return

        item_importance[index]="$new_importance"
    }


    set_subtree_status() {
        local root_index="$1"
        local new_status="$2"
        local child

        item_status[root_index]="$new_status"

        get_children "${item_id[root_index]}"

        for child in "${CHILDREN[@]}"; do
            set_subtree_status "$child" "$new_status"
        done
    }


    set_unfinished_subtree_status() {
        local root_index="$1"
        local child

        if [[ "${effective_status[root_index]}" != "C" ]]; then
            item_status[root_index]="PA"
        fi

        get_children "${item_id[root_index]}"

        for child in "${CHILDREN[@]}"; do
            set_unfinished_subtree_status "$child"
        done
    }


    # ------------------------------------------------------------
    # Main project UI
    # ------------------------------------------------------------

    project_menu() {
        local choice
        local project_file_tr="${PROJECT_FILE:0:80}"
        (( ${#PROJECT_FILE} > 80 )) && project_file_tr+="..."

        local tree_page=0
        local tree_page_size=25   # tree items per page        

        # Remember the saved state so Back can detect unsaved changes.
        local PROJECT_SAVED_SIG
        sort_children "0"
        calculate_all_statuses
        PROJECT_SAVED_SIG="$(project_state_sig)"

        while :; do

            sort_children "0"
            calculate_all_statuses
            build_tree_options

            # --- paginate TREE_OPTIONS ---
            local tree_total=$(( ${#TREE_OPTIONS[@]} / 2 ))
            local tree_pages=$(( (tree_total + tree_page_size - 1) / tree_page_size ))
            (( tree_pages == 0 )) && tree_pages=1
            (( tree_page >= tree_pages )) && tree_page=$(( tree_pages - 1 ))
            (( tree_page < 0 )) && tree_page=0
            local tree_start=$(( tree_page * tree_page_size * 2 ))
            local tree_chunk=("${TREE_OPTIONS[@]:tree_start:tree_page_size*2}")

            # static action rows first
            local menu_items=(
                "SYMBOLS" "Help"
                "ADD_H" "Add top-level heading"
                "ADD_T" "Add task"
                "ADD_TODO" "Add TODO item"
                "ADD_RULES" "Add RULES FOR TODAY item"            
                "SORT" "Sort root's children by number prefix"
                "SAVE" "Save changes"
                "REVERT" "Discard changes and reload from disk"
                "---" "PROJECT TREE BELOW ---"
                "" ""
            )

            # navigation rows (only when applicable)
            (( tree_page > 0 )) && menu_items+=("__prev__" "<< Previous page")
            (( tree_page < tree_pages - 1 )) && menu_items+=("__next__" "Next page >>")

            # then the current page of tree items
            menu_items+=("${tree_chunk[@]}")

            choice="$(
                whiptail \
                    --title "Manage Goals" \
                    --cancel-button "Back" \
                    --menu \
                    "Project: $project_file_tr (Page $((tree_page + 1))/$tree_pages)" \
                    45 180 37 \
                    -- \
                    "${menu_items[@]}" \
                    3>&1 1>&2 2>&3
            )" || { project_confirm_leave && break; continue; }

            case "$choice" in
                SYMBOLS)
                    whiptail \
                        --title "Symbol Help" \
                        --msgbox "$(print_symbol_help)" \
                        20 80                
                    ;;

                __prev__)
                    (( tree_page > 0 )) && (( tree_page-- ))
                    continue
                    ;;
                __next__)
                    (( tree_page < tree_pages - 1 )) && (( tree_page++ ))
                    continue
                    ;;                

                "---"|"")
                    continue
                    ;;

                ADD_H)
                    add_heading "0"
                    ;;

                ADD_T)
                    if select_heading_for_parent "0"; then
                        add_task "$SELECTED_HEADING_ID"
                    fi
                    ;;

                ADD_TODO)
                    add_todo_item
                    ;;    

                ADD_RULES)
                    add_rules_for_today_item
                    ;;            

                SORT)
                    sort_children "0"
                    ;;

                SAVE)
                    if save_project; then
                        PROJECT_SAVED_SIG="$(project_state_sig)"
                        whiptail \
                            --title "Saved" \
                            --msgbox "Project saved successfully." \
                            8 50
                    fi
                    ;;

                REVERT)
                    if whiptail \
                        --title "Revert Project" \
                        --yesno \
                        "Discard unsaved changes and reload the project from disk?" \
                        10 70; then

                        if load_project "$PROJECT_FILE"; then
                            sort_children "0"
                            calculate_all_statuses
                            PROJECT_SAVED_SIG="$(project_state_sig)"
                            whiptail \
                                --title "Reverted" \
                                --msgbox "Unsaved changes discarded; project reloaded." \
                                8 50
                        fi
                    fi
                    ;;

                *)
                    # Tree entries use their persistent item ID as the menu tag.
                    find_index_by_id "$choice"
                    if (( RESULT_INDEX >= 0 )); then
                        item_menu "$RESULT_INDEX"
                    fi
                    ;;
            esac
        done        
    }

    # ------------------------------------------------------------
    # Start
    # ------------------------------------------------------------

    if ! command -v whiptail >/dev/null 2>&1; then
        printf 'Error: whiptail is not installed.\n' >&2
        exit 1
    fi

    if ! load_project "$PROJECT_FILE"; then
        exit 1
    fi

    project_menu            
}  

edit_project_old() {
    # Check if projects database exists and has entries
    [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]] && {
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 </dev/tty >/dev/tty
        return 1
    }

#    # Read all projects into array
#    local lines=()
#    mapfile -t lines < "$PROJECTS_DB"
#
#    # Create selection menu
#    local menu_options=()
#    for index in "${!lines[@]}"; do
#        IFS='|' read -r title _ _ <<< "${lines[$index]}"
#        menu_options+=("$index" "$title")
#    done

    # FIX: ADD FILTERING
    # Read all projects into array
    local lines=()
    #mapfile -t lines < "$PROJECTS_DB"
    mapfile -d '' -t lines < <(filter_projects_by_name)		# get filtered lines from utility function. \0 delimited.

    # CRITICAL ERROR!!!
    # Instead of $index store matching index from $PROJECTS_DB file.
    # Create selection menu
    #local menu_options=()
    #for index in "${!lines[@]}"; do
    #    IFS='|' read -r title _ _ <<< "${lines[$index]}"
    #    menu_options+=("$index" "$title")
    #done

    local menu_options=()
    local title line lineno
    for line in "${lines[@]}"; do
        IFS='|' read -r title _ _ <<< "$line"
        lineno=$(grep -Fxnm1 "$line" "$PROJECTS_DB" | cut -d: -f1)

	# Store matching index from PROJECTS_DB file.
        [[ -n "$lineno" ]] && menu_options+=($((lineno-1)) "$title")
    done
    # END FIX.

    # Paginate menu options
    paginate_get_projects "Edit Project" "${menu_options[@]}"
    local selected_index
    selected_index="$SELECTED_ITEM_PROJECT"
    [[ -z "$selected_index" ]] && return 1

    # Let user select project
    #local selected_index
    #selected_index=$(whiptail --menu "Select a project to edit:" 20 150 10 \
    #    "${menu_options[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1

    # DIRTY FIX: OVERWRITE LINES TO CONTAIN ALL LINES FROM PROJECTS_DB.
    mapfile -t lines < "$PROJECTS_DB"

    # Parse selected project
    local old_title old_path old_notes
    IFS='|' read -r old_title old_path old_notes <<< "${lines[$selected_index]}"

    # Verify project file exists
    [[ ! -f "$old_path" ]] && {
        whiptail --msgbox "Project file not found: $old_path" 10 60
        return 1
    }

    # Dirty fix. $selected_index_file to point to the project file.
    local selected_index_file="$selected_index"

    # Load existing headings and indentation
    local headings=()
    local indent_levels=()
    # Read the selected project file line by line
    # and populate headings and indent_levels
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local spaces="${line%%[^ ]*}"
        local length=${#spaces}
        local indent=$(( length / 4 ))
        local heading="${line#$spaces}"
        headings+=("$heading")
        indent_levels+=("$indent")
    done < "$old_path"

    # Main project menu
    local project_title="$old_title"
    local project_path="$old_path"
    local new_title project_action
    while true; do
        project_action=$(whiptail --menu "Project Configuration" 15 150 3 \
            "Project title" "Current: ${project_title:-<not set>}" \
            "Project path" "Status: ${project_path}" \
            "Proceed" "" 3>&1 1>&2 2>&3) || return 1

        case "$project_action" in
            "Project title")
		# FIX: FILTER BANNED CHAR |.
		local old_project_title
		old_project_title="$project_title" # save project title

                new_title=$(whiptail --inputbox "Enter project title:" 8 78 \
                    "$project_title" 3>&1 1>&2 2>&3)

		# FIX: FILTER BANNED CHAR |.
		if [[ "$new_title" =~ \| ]]; then
			project_title="$old_project_title"	# Revert
			whiptail --title "Attention" --msgbox "Project title cannot contain | character." 8 40
			continue
		fi
		# END FIX.

                if [[ -z "$new_title" ]]; then
                    whiptail --msgbox "Project title can't be empty." 8 45
                    continue
                fi
                project_title="$new_title"
                ;;
            "Project path")
				continue
				;;
            "Proceed")
                [[ -z "$project_title" ]] && {
                    whiptail --msgbox "Project title is required." 8 45
                    continue
                }
                break
                ;;
            *) return 1 ;;            
        esac
    done

    # Headings management
    local heading_menu
    rebuild_heading_menu() {
        heading_menu=("Add new heading" "")
        for i in "${!headings[@]}"; do
            indent_spaces=$(( indent_levels[i] * 4 ))
            indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
            heading_menu+=("$i" "${indented_heading:0:130}")
        done
    }

    while true; do
        rebuild_heading_menu
        local heading_action
        heading_action=$(whiptail --menu "Project: ${project_title}" 20 150 10 -- \
            "${heading_menu[@]}" "Save and return" "" 3>&1 1>&2 2>&3) || return 1

        case "$heading_action" in
            "Add new heading")
				local new_heading
                new_heading=$(whiptail --inputbox "Enter new heading:" 8 78 3>&1 1>&2 2>&3)
                [[ -n "$new_heading" ]] && {
                    headings+=("$new_heading")
                    indent_levels+=(0)
                }
                ;;
            "Save and return")
                break
                ;;
            *)
                if [[ "$heading_action" =~ ^[0-9]+$ ]]; then
                    local selected_index=$heading_action
                    local heading_operation
                    heading_operation=$(whiptail --menu "Heading Operations" 20 60 7 \
                        "Change text" "" \
                        "Move before" "" \
                        "Move after" "" \
                        "Indent left" "" \
                        "Indent right" "" \
                        "Remove heading" "" 3>&1 1>&2 2>&3)

                    case "$heading_operation" in
                        "Change text")
							local new_text
                            new_text=$(whiptail --inputbox "Enter new heading text:" 8 78 \
                                "${headings[$selected_index]}" 3>&1 1>&2 2>&3)
                            headings[$selected_index]="$new_text"	# what happens when new text is ""?
                            ;;
                        "Move before"|"Move after")
                            # LOGIC ERROR FIX: IF HEADINGS COUNT IS LESS THAN OR EQUAL TO ONE, CONTINUE.
                            [[ ${#headings[@]} -le 1 ]] && continue

                            local targets=()
                            for i in "${!headings[@]}"; do
                                [[ $i -ne $selected_index ]] && {
                                    indent_spaces=$(( indent_levels[i] * 4 ))
                                    indented_heading=$(printf "%${indent_spaces}s%s" "" "${headings[$i]}")
                                    targets+=("$i" "$indented_heading")
                                }
                            done

                            local target_index
                            target_index=$(whiptail --menu "Select target heading:" 20 150 10 \
                                "${targets[@]}" 3>&1 1>&2 2>&3)
                            [[ -z "$target_index" ]] && continue

                            local original_source_pos=$selected_index
                            local original_target_pos=$target_index
                            local moving_heading="${headings[$original_source_pos]}"
                            local moving_indent="${indent_levels[$original_source_pos]}"

                            # Remove source heading
                            headings=("${headings[@]:0:$original_source_pos}" 
                                "${headings[@]:$((original_source_pos+1))}")
                            indent_levels=("${indent_levels[@]:0:$original_source_pos}" 
                                "${indent_levels[@]:$((original_source_pos+1))}")

                            # Adjust target position
                            if (( original_source_pos < original_target_pos )); then
                                adjusted_target_pos=$((original_target_pos - 1))
                            else
                                adjusted_target_pos=$original_target_pos
                            fi

                            [[ "$heading_operation" == "Move after" ]] && ((adjusted_target_pos++))

                            # Insert at new position
                            headings=("${headings[@]:0:$adjusted_target_pos}" 
                                "$moving_heading" 
                                "${headings[@]:$adjusted_target_pos}")
                            indent_levels=("${indent_levels[@]:0:$adjusted_target_pos}" 
                                "$moving_indent" 
                                "${indent_levels[@]:$adjusted_target_pos}")
                            ;;
                        "Indent right")
                            (( indent_levels[$selected_index]++ ))
                            ;;
                        "Indent left")
                            (( indent_levels[$selected_index] = indent_levels[$selected_index] > 0 ? 
                                indent_levels[$selected_index]-1 : 0 ))
                            ;;
                        "Remove heading")
                            headings=("${headings[@]:0:$selected_index}" 
                                "${headings[@]:$((selected_index+1))}")
                            indent_levels=("${indent_levels[@]:0:$selected_index}" 
                                "${indent_levels[@]:$((selected_index+1))}")
                            ;;
                        *) ;;
                    esac
                fi
                ;;
        esac
    done

    # Save updated project file
    {
        for i in "${!headings[@]}"; do
            printf "%$((indent_levels[i]*4))s%s\n" "" "${headings[$i]}"
        done
    } > "$project_path"

    # Update projects database: Dirty fix here too.
    lines[$selected_index_file]="${project_title}|${project_path}|${old_notes}"
    printf "%s\n" "${lines[@]}" > "$PROJECTS_DB"
}

print_project() {
    #local line_num=0		# can't use this any more.
    local options=("<< Back" "")

    # Check if database file exists and is valid
    if [ ! -f "$PROJECTS_DB" ]; then
        whiptail --msgbox "Project database '$PROJECTS_DB' not found." 8 40 >/dev/tty
        return 1
    elif [ ! -s "$PROJECTS_DB" ]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    fi

    # Pick a project by full path. __APPLY_GLOB__ matches the project file
    # name and __RESET_GLOB__ clears the glob.
    GOALS_PROJECT_GLOB=""
    local line_

    # Continuous selection loop
    while true; do
        goals_select_project "View Project Content" || return 1
        line_="$GOALS_SELECTED_PROJECT_LINE"

        local title_ path_
        IFS='|' read -r title_ path_ _ <<< "$line_"

        if [ ! -e "$path_" ]; then
            whiptail --msgbox "Error: Project file '$path_' not found." 10 50 >/dev/tty
            return 1
        elif [ -d "$path_" ]; then
            whiptail --msgbox "Error: '$path_' is a directory, not a file." 10 50 >/dev/tty
            return 1
        elif [ ! -r "$path_" ]; then
            whiptail --msgbox "Error: Cannot read project file '$path_'." 10 50 >/dev/tty
            return 1
        fi

        local tmpfile
        tmpfile=$(mktemp) || {
            whiptail --msgbox "Error: Failed to create temporary file." 10 50 >/dev/tty
            return 1
        }
        cat "$path_" > "$tmpfile"
        whiptail --scrolltext --title "$title_" --textbox "$tmpfile" 20 150
        rm -f "$tmpfile"
    done
}

delete_project() {
    # Check if projects database exists and is readable
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --title "Error" --msgbox "No projects found." 8 40
        return 1
    fi

    # __APPLY_GLOB__ matches the project file name; __RESET_GLOB__ clears it.
    GOALS_PROJECT_GLOB=""

    while :; do
        goals_select_project "Delete Project" || return 1

        local line_to_delete="$GOALS_SELECTED_PROJECT_LINE"
        local project_path="$GOALS_SELECTED_PROJECT_PATH"

        # Confirmation dialog
        whiptail --title "Confirm Deletion" --yesno "Permanently delete project:\n$project_path" \
            --yes-button "Delete" --no-button "Cancel" 10 60 || return 1

        # Verify the project path is valid
        local project_real
        project_real=$(realpath "$project_path") || {
            whiptail --title "Error" --msgbox "Invalid project path:\n$project_path" 8 60
            return 1
        }

        # Delete project files/directory
        if ! rm -rf "$project_real"; then
            whiptail --title "Error" --msgbox "Failed to delete project files:\n$project_real" 8 60
            return 1
        fi

        # Delete entry from database
        local tempfile
        tempfile=$(mktemp) || return 1

        # build tempfile by removing line to be deleted from projects db and save to it
        grep -vFx -- "$line_to_delete" "$PROJECTS_DB" > "$tempfile"
        local grep_status=$?

        if (( grep_status <= 1 )) && mv "$tempfile" "$PROJECTS_DB"; then
            :   # the picker re-reads PROJECTS_DB on the next iteration
        else
            rm -f "$tempfile"
            whiptail --title "Error" --msgbox "Project couldn't be deleted." 8 50
            return 1
        fi
    done
}

associate_note_to_project() {
    local temp_file

    # Check if databases exist
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi
    if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
        whiptail --msgbox "No notes found. Add at least one note and try again." 8 40 </dev/tty >/dev/tty
        return 1
    fi

    # Select Project: __APPLY_GLOB__ matches the project file name,
    # __RESET_GLOB__ clears the glob.
    GOALS_PROJECT_GLOB=""
    goals_select_project "Select Project" || return 1
    local selected_project_path="$GOALS_SELECTED_PROJECT_PATH"

    # Select Note Tag to Filter Notes: [NO TAG], [ANY TAG] or a tag.
    # __FILTER__ narrows the tag list by a literal substring.
    # If the chosen filter matches no notes, tell the user and show the tag
    # menu again so a different filter can be chosen.
    local selected_note_tag note_title note_path note_tags rest
    local -a note_candidates=() all_note_paths=()
    while :; do
        goals_select_note_tag_filter || return 1
        selected_note_tag="$GOALS_SELECTED_NOTE_TAG"

        # Collect the notes that satisfy the chosen tag filter.
        note_candidates=()
        all_note_paths=()
        while IFS='|' read -r note_title note_path note_tags rest; do
            [[ -n "$note_path" ]] || continue
            all_note_paths+=("$note_path")
            case "$selected_note_tag" in
                "[ANY TAG]")
                    note_candidates+=("$note_path")
                    ;;
                "[NO TAG]")
                    [[ -z "$note_tags" ]] && note_candidates+=("$note_path")
                    ;;
                *)
                    goals_note_has_tag "$note_tags" "$selected_note_tag" && note_candidates+=("$note_path")
                    ;;
            esac
        done < "$NOTES_DB"

        (( ${#note_candidates[@]} > 0 )) && break

        case "$selected_note_tag" in
            "[ANY TAG]")
                whiptail --msgbox "No notes found. Add at least one note and try again." 8 60
                ;;
            "[NO TAG]")
                whiptail --msgbox "There are no notes with no associated tag found." 8 60
                ;;
            *)
                whiptail --msgbox "Tag '${selected_note_tag}' has no associated notes yet." 8 60
                ;;
        esac
    done

    # Choose Note to Associate: full note paths plus their tags.
    # __APPLY_GLOB__ matches note file names; __FILTER_BY_TAG__ filters by tag.
    # The tag chosen above is only the STARTING tag filter: the picker gets
    # every note so the filter can be changed (e.g. to [ANY TAG]) from inside it.
    local GOALS_NOTE_TAGMENU_FULL=1   # full tag menu inside __FILTER_BY_TAG__
    GOALS_NOTE_GLOB=""
    GOALS_NOTE_TAGFILTER="$selected_note_tag"   # shown as the starting tag filter

    while :; do
        goals_pick_note "Choose Note to Associate" "Choose a note to associate with the project" \
            "${all_note_paths[@]}" || return 1
        local selected_note_path="$GOALS_PICKED_NOTE_PATH"

        temp_file=$(mktemp) || return 1
        local project_found=0 line_updated=0 duplicate_detected=0
        local line title path notes new_notes new_line note
        local -a notes_array=()

        # Process PROJECTS_DB
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            IFS='|' read -r title path notes <<< "$line"
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$notes"
                local duplicate=0
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50
                    duplicate_detected=1
                    printf '%s\n' "$title|$path|$notes" >> "$temp_file"
                else
                    if [[ -z "$notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    printf '%s\n' "$new_line" >> "$temp_file"
                    line_updated=1
                fi
            else
                printf '%s\n' "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm -f "$temp_file"
                continue
            else
                rm -f "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                continue
            fi
        else
            rm -f "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            continue
        fi
    done
}

dissociate_note_from_project() {
    find_tags_for_linked_note() {
        local path_to_note_file="$1"
        local matching_tags_str=""

        # Ensure NOTES_DB is defined and exists
        if [[ -z "$NOTES_DB" || ! -f "$NOTES_DB" ]]; then
            echo "Error: NOTES_DB not defined or file not found." >&2
            return 1
        fi

        # Extract the tags (3rd field) for the matching note
        matching_tags_str=$(awk -F'|' -v path="$path_to_note_file" '$2 == path {print $3}' "$NOTES_DB")

        echo "$matching_tags_str"
    }

    #local PROJECTS_DB=${PROJECTS_DB:-"$HOME/projects_db"}

    # Check if database exists
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    fi

    # Select Project: __APPLY_GLOB__ matches the project file name,
    # __RESET_GLOB__ clears the glob.
    GOALS_PROJECT_GLOB=""
    goals_select_project "Select Project" || return 1

    # Load full DB lines for editing later
    local lines=()
    mapfile -t lines < "$PROJECTS_DB"

    local selected_project=$(( GOALS_SELECTED_PROJECT_LINENO - 1 ))
    local title path notes line
    line="${lines[selected_project]}"
    IFS='|' read -r title path notes <<< "$line"

    truncate_note_tags_by_tag() {
        local tags="$1"
        local inner
        local -a tag_array
        local count
        local extra

        # Remove surrounding [ ]
        inner="${tags#[}"
        inner="${inner%]}"

        # Empty list
        if [[ -z "$inner" ]]; then
            printf '[]\n'
            return
        fi

        # Split on commas
        IFS=',' read -r -a tag_array <<< "$inner"

        count=${#tag_array[@]}

        if (( count <= 3 )); then
            printf '[%s]\n' "$inner"
            return
        fi

        extra=$((count - 3))

        printf '[%s,%s,%s +%d]\n' \
            "${tag_array[0]}" \
            "${tag_array[1]}" \
            "${tag_array[2]}" \
            "$extra"
    }

    GOALS_NOTE_GLOB=""
    GOALS_NOTE_TAGFILTER=""

    # Begin dissociation loop
    while true; do
        if [[ -z "$notes" ]]; then
            whiptail --msgbox "Selected project has no associated notes." 10 60 >/dev/tty
            return 1
        fi

        # Split notes into array
        local -a notes_arr
        IFS=',' read -ra notes_arr <<< "$notes"

        if [[ ${#notes_arr[@]} -eq 0 ]]; then
            whiptail --msgbox "No notes left to dissociate." 10 60 >/dev/tty
            return 1
        fi

        # Choose Note to Dissociate: full note paths plus their tags.
        # __APPLY_GLOB__ matches note file names; __FILTER_BY_TAG__ filters by tag.
        goals_pick_note "Choose Note to Dissociate" "Choose a note to dissociate from the project" \
            "${notes_arr[@]}" || break
        local selected_note="$GOALS_PICKED_NOTE_INDEX"
        local note_index
        # Remove selected note from list
        local -a new_notes=()
        for note_index in "${!notes_arr[@]}"; do
            if [[ $note_index -ne $selected_note ]]; then
                new_notes+=("${notes_arr[note_index]}")
            fi
        done

        # Join remaining notes into CSV
        local new_notes_str=""
        if [[ ${#new_notes[@]} -gt 0 ]]; then
            new_notes_str=$(IFS=','; printf '%s' "${new_notes[*]}")
        fi

        # Update database entry in memory
        lines[selected_project]="$title|$path|$new_notes_str"
        notes="$new_notes_str"  # Update current project notes for next loop

        # Write database back to file
        local tmp_db
        tmp_db=$(mktemp) || return 1
        printf "%s\n" "${lines[@]}" > "$tmp_db"
        mv -- "$tmp_db" "$PROJECTS_DB" || { rm -- "$tmp_db"; return 1; }

        whiptail --msgbox "Note successfully dissociated from project." 10 60 >/dev/tty

        # If no notes left, exit loop automatically
        [[ -z "$notes" ]] && {
            whiptail --msgbox "All notes have been dissociated from this project." 10 60 >/dev/tty
            break
        }
    done
}

# ---------------------------------------------------------------------------
# Goal Management: individual linked-note URL, ebook and tag actions.
# These helpers are shared by the project-file and shortlisted-project flows.
# ---------------------------------------------------------------------------

goals_glob_matches() {
    local value="${1,,}" pattern="${2,,}"
    [[ "$value" == $pattern ]]
}

goals_load_note_urls() {
    local selected_path="$1" urls_name="$2" titles_name="$3"
    local -n out_urls="$urls_name" out_titles="$titles_name"
    local GS=$'\x1D' US=$'\x1F' RS=$'\x1E'
    local line payload entry url title
    local -a entries=()

    out_urls=()
    out_titles=()
    [[ -r "$URLS_DB" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "${selected_path}${GS}"* ]] || continue
        payload="${line#*"$GS"}"
        IFS="$RS" read -r -a entries <<< "$payload"
        for entry in "${entries[@]}"; do
            [[ -n "$entry" ]] || continue
            IFS="$US" read -r url title <<< "$entry"
            out_urls+=("$url")
            out_titles+=("$title")
        done
        break
    done < "$URLS_DB"
}

goals_save_note_urls() {
    local selected_path="$1" urls_name="$2" titles_name="$3"
    local -n saved_urls="$urls_name" saved_titles="$titles_name"
    local GS=$'\x1D' US=$'\x1F' RS=$'\x1E'
    local new_entry="${selected_path}${GS}" line i tmp_file

    for i in "${!saved_urls[@]}"; do
        new_entry+="${saved_urls[i]}${US}${saved_titles[i]}${RS}"
    done
    new_entry="${new_entry%$RS}"

    tmp_file=$(mktemp) || return 1
    {
        if [[ -r "$URLS_DB" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
                [[ "$line" == "${selected_path}${GS}"* ]] || printf '%s\n' "$line"
            done < "$URLS_DB"
        fi
        ((${#saved_urls[@]} == 0)) || printf '%s\n' "$new_entry"
    } > "$tmp_file" || { rm -f -- "$tmp_file"; return 1; }

    mv -- "$tmp_file" "$URLS_DB"
}

# Set GOALS_URL_PICKED_INDEX to the selected array index. Globs match either
# the complete URL or its title, case-insensitively.
goals_pick_url_index() {
    local menu_title="$1" menu_prompt="$2" urls_name="$3" titles_name="$4"
    local -n pick_urls="$urls_name" pick_titles="$titles_name"
    local url_glob="" new_glob choice url title i
    local page=1 page_size=50 total total_pages start end k
    local -a visible=() menu_items=()

    GOALS_URL_PICKED_INDEX=""
    while :; do
        visible=()
        for i in "${!pick_urls[@]}"; do
            if [[ -z "$url_glob" ]] || \
               goals_glob_matches "${pick_urls[i]}" "$url_glob" || \
               goals_glob_matches "${pick_titles[i]}" "$url_glob"; then
                visible+=("$i")
            fi
        done

        total=${#visible[@]}
        total_pages=$(( (total + page_size - 1) / page_size ))
        (( total_pages < 1 )) && total_pages=1
        (( page > total_pages )) && page=$total_pages
        start=$(( (page - 1) * page_size ))
        end=$(( start + page_size ))
        (( end > total )) && end=$total

        menu_items=(
            "__APPLY_GLOB__" "Apply glob (matches URL or title)"
            "__RESET_GLOB__" "Reset glob"
        )
        (( page > 1 )) && menu_items+=("__PREV_PAGE__" "<< Previous page")
        for (( k=start; k<end; k++ )); do
            i=${visible[k]}
            menu_items+=("$i" "${pick_urls[i]} - ${pick_titles[i]}")
        done
        (( page < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page >>")

        local status="URL glob: ${url_glob:-none}  |  ${total} URL(s) shown"
        (( total == 0 )) && status+=$'\nNo URLs match the current glob.'
        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "$menu_prompt (page $page/$total_pages)\n$status" \
            35 155 25 "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            __APPLY_GLOB__)
                if new_glob=$(whiptail --title "Apply URL Glob" --inputbox \
                    "Enter a case-insensitive glob to match the URL or URL title. Use * and ? as wildcards; leave empty to show all URLs." \
                    11 90 "$url_glob" 3>&1 1>&2 2>&3); then
                    url_glob="$new_glob"
                    page=1
                fi
                ;;
            __RESET_GLOB__) url_glob=""; page=1 ;;
            __PREV_PAGE__) (( page > 1 )) && page=$((page - 1)) ;;
            __NEXT_PAGE__) (( page < total_pages )) && page=$((page + 1)) ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || continue
                (( choice >= 0 && choice < ${#pick_urls[@]} )) || continue
                GOALS_URL_PICKED_INDEX="$choice"
                return 0
                ;;
        esac
    done
}

goals_open_url_for_note() {
    local selected_path="$1" selected_index
    local -a urls=() titles=()
    [[ -n "$selected_path" ]] || return 1
    goals_load_note_urls "$selected_path" urls titles
    if ((${#urls[@]} == 0)); then
        whiptail --title "Choose URL to open" --msgbox \
            "No URLs are associated with this note." 8 60
        return 1
    fi

    goals_pick_url_index "Choose URL to open" "Choose URL to open:" urls titles || return 1
    selected_index="$GOALS_URL_PICKED_INDEX"
    nohup "$URL_BROWSER" "${urls[selected_index]}" >/dev/null 2>&1 &
}

goals_manage_urls_for_note() {
    local selected_path="$1" choice index sub_choice
    local new_url new_title current_url current_title
    local url_glob="" new_glob prompt
    local url_regex='^(https?:\/\/)?(www\.)?([a-zA-Z0-9-]+\.)+[A-Za-z]{2,}(:[0-9]+)?(\/\S*)?$'
    local -a urls=() titles=() menu_items=() visible_indexes=()
    [[ -n "$selected_path" ]] || return 1
    touch "$URLS_DB"
    goals_load_note_urls "$selected_path" urls titles

    while :; do
        # Keep the action items visible while filtering only the existing URL
        # associations. The glob is case-insensitive and matches either the
        # complete URL or its title.
        visible_indexes=()
        menu_items=(
            "__APPLY_GLOB__" "Apply glob (matches URL or title)"
            "__RESET_GLOB__" "Reset glob"
            "Register URL" "Register a new URL"
            "Save and return" "Save URL associations"
        )
        for index in "${!urls[@]}"; do
            if [[ -z "$url_glob" ]] || \
               goals_glob_matches "${urls[index]}" "$url_glob" || \
               goals_glob_matches "${titles[index]}" "$url_glob"; then
                visible_indexes+=("$index")
                menu_items+=("$index" "${urls[index]} - ${titles[index]}")
            fi
        done

        prompt="Manage URLs for: $selected_path\nURL glob: ${url_glob:-none} | ${#visible_indexes[@]} of ${#urls[@]} association(s) shown"
        ((${#visible_indexes[@]} > 0)) || prompt+=$'\nNo URL associations match the current glob.'

        # This is a full-width content menu with a 50-row list capacity.
        # The colon prevents the shared wrapper from classifying it as a
        # compact navigation menu.
        choice=$(whiptail --title "URL Associations" --cancel-button "Back" \
            --menu "$prompt" 35 155 25 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            __APPLY_GLOB__)
                if new_glob=$(whiptail --title "Apply URL Glob" --inputbox \
                    "Enter a case-insensitive glob to match the complete URL or its title. Use * for any characters and ? for one character. Leave empty to show all associations." \
                    11 90 "$url_glob" 3>&1 1>&2 2>&3); then
                    url_glob="$new_glob"
                fi
                ;;
            __RESET_GLOB__)
                url_glob=""
                ;;
            "Register URL")
                new_url=$(whiptail --title "Register URL" --inputbox "Enter URL:" 8 70 3>&1 1>&2 2>&3) || continue
                if [[ ! "$new_url" =~ $url_regex ]]; then
                    whiptail --msgbox "Invalid URL format. Please enter a valid URL." 8 60
                    continue
                fi
                new_title=$(whiptail --title "Register URL" --inputbox "Enter URL title:" 8 70 3>&1 1>&2 2>&3) || continue
                if [[ -z "$new_url" || -z "$new_title" ]]; then
                    whiptail --msgbox "URL and title cannot be empty." 8 50
                    continue
                fi
                urls+=("$new_url")
                titles+=("$new_title")
                ;;
            "Save and return")
                goals_save_note_urls "$selected_path" urls titles || return 1
                whiptail --msgbox "URL associations saved successfully." 8 60
                return 0
                ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || continue
                index="$choice"
                (( index >= 0 && index < ${#urls[@]} )) || continue
                # Ignore stale / filtered-out numeric choices.
                local is_visible=0 visible_index
                for visible_index in "${visible_indexes[@]}"; do
                    [[ "$visible_index" == "$index" ]] && { is_visible=1; break; }
                done
                (( is_visible )) || continue
                sub_choice=$(whiptail --title "Manage URL" --menu "Choose an action:" 12 60 2 \
                    "Change values" "Edit URL and title" \
                    "Delete URL" "Delete this association" 3>&1 1>&2 2>&3) || continue
                case "$sub_choice" in
                    "Change values")
                        current_url="${urls[index]}"
                        current_title="${titles[index]}"
                        new_url=$(whiptail --title "Edit URL" --inputbox "Edit URL:" 8 70 "$current_url" 3>&1 1>&2 2>&3) || continue
                        if [[ ! "$new_url" =~ $url_regex ]]; then
                            whiptail --msgbox "Invalid URL format. Please enter a valid URL." 8 60
                            continue
                        fi
                        new_title=$(whiptail --title "Edit URL" --inputbox "Edit URL title:" 8 70 "$current_title" 3>&1 1>&2 2>&3) || continue
                        [[ -n "$new_url" && -n "$new_title" ]] || {
                            whiptail --msgbox "URL and title cannot be empty." 8 50
                            continue
                        }
                        urls[index]="$new_url"
                        titles[index]="$new_title"
                        ;;
                    "Delete URL")
                        unset 'urls[index]' 'titles[index]'
                        urls=("${urls[@]}")
                        titles=("${titles[@]}")
                        ;;
                esac
                ;;
        esac
    done
}

goals_dissociate_urls_from_note() {
    local selected_path="$1" choice selected_index
    local -a urls=() titles=() menu_items=()
    [[ -n "$selected_path" ]] || return 1
    touch "$URLS_DB"
    goals_load_note_urls "$selected_path" urls titles
    if ((${#urls[@]} == 0)); then
        whiptail --title "Dissociate URL from note" --msgbox \
            "No URLs are associated with this note. Associate a URL and try again." 9 70
        return 1
    fi

    while :; do
        menu_items=("Remove URL" "Choose a URL to remove" "Save and return" "Save URL changes")
        # Blank prompt avoids compact-navigation sizing: full terminal width and
        # the shared 50-row content-list capacity are used.
        choice=$(whiptail --title "Dissociate URL from note" --cancel-button "Back" \
            --menu "" 35 155 25 "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1
        case "$choice" in
            "Remove URL")
                goals_pick_url_index "Select URL to remove" "Select a URL to remove:" urls titles || continue
                selected_index="$GOALS_URL_PICKED_INDEX"
                unset 'urls[selected_index]' 'titles[selected_index]'
                urls=("${urls[@]}")
                titles=("${titles[@]}")
                if ((${#urls[@]} == 0)); then
                    whiptail --title "No URLs" --msgbox \
                        "All URL associations have been selected for removal. Choose Save and return to apply the change." 10 75
                fi
                ;;
            "Save and return")
                goals_save_note_urls "$selected_path" urls titles || return 1
                whiptail --msgbox "URL associations updated." 8 50
                return 0
                ;;
        esac
    done
}

goals_write_note_tag_line() {
    local note_title="$1" note_path="$2" new_tags="$3" rest="$4"
    local new_line="$note_title|$note_path|$new_tags|$rest" tmp_file
    tmp_file=$(mktemp) || return 1
    awk -F'|' -v path="$note_path" -v replacement="$new_line" '
        $2 == path { print replacement; found=1; next }
        { print }
        END { if (!found) exit 1 }
    ' "$NOTES_DB" > "$tmp_file" || { rm -f -- "$tmp_file"; return 1; }
    mv -- "$tmp_file" "$NOTES_DB"
}

goals_add_tag_to_note() {
    local selected_note_line="$1"
    local note_title note_path note_tags rest tag selected_tag
    local -a candidates=()
    IFS='|' read -r note_title note_path note_tags rest <<< "$selected_note_line"
    [[ -r "$NOTES_TAGS_DB" ]] || return 1

    while IFS= read -r tag || [[ -n "$tag" ]]; do
        [[ -n "$tag" ]] || continue
        goals_note_has_tag "$note_tags" "$tag" && continue
        candidates+=("$tag")
    done < "$NOTES_TAGS_DB"
    if ((${#candidates[@]} == 0)); then
        whiptail --msgbox "There are no tags available to add." 8 50
        return 1
    fi

    goals_select_note_tag_filter --title "Add tag" --prompt "Select a tag to add" \
        --pins "" --tags "${candidates[@]}" || return 1
    selected_tag="$GOALS_SELECTED_NOTE_TAG"
    if [[ -n "$note_tags" ]]; then note_tags+=",$selected_tag"; else note_tags="$selected_tag"; fi
    goals_write_note_tag_line "$note_title" "$note_path" "$note_tags" "$rest"
}

goals_remove_tag_from_note() {
    local selected_note_line="$1"
    local note_title note_path note_tags rest tag selected_tag updated_tags=""
    local -a note_tag_array=() new_tags=()
    IFS='|' read -r note_title note_path note_tags rest <<< "$selected_note_line"
    if [[ -z "$note_tags" ]]; then
        whiptail --msgbox "This note has no tags to remove." 8 50
        return 1
    fi

    IFS=',' read -r -a note_tag_array <<< "$note_tags"
    goals_select_note_tag_filter --title "Remove tag" --prompt "Select a tag to remove" \
        --pins "" --tags "${note_tag_array[@]}" || return 1
    selected_tag="$GOALS_SELECTED_NOTE_TAG"

    for tag in "${note_tag_array[@]}"; do
        [[ "$tag" == "$selected_tag" ]] && continue
        [[ -n "$tag" ]] && new_tags+=("$tag")
    done
    ((${#new_tags[@]} > 0)) && updated_tags=$(IFS=,; printf '%s' "${new_tags[*]}")
    goals_write_note_tag_line "$note_title" "$note_path" "$updated_tags" "$rest"
}

open_note_ebook_page_from_project() {
    local selected_line="$1" ebooks_part selected_ebook chapters_part
    local ebook_path glob="" new_glob choice page_value
    local page=1 page_size=50 total total_pages start end i k
    local -a ebooks=() visible=() menu_items=()

    [[ -n "$selected_line" ]] || return 1
    ebooks_part="$(cut -d'|' -f4 <<< "$selected_line")"
    if [[ -z "$ebooks_part" ]]; then
        whiptail --title "Select an ebook" --msgbox \
            "No ebooks are associated with this note." 8 60
        return 1
    fi
    IFS=';' read -r -a ebooks <<< "$ebooks_part"

    while :; do
        visible=()
        for i in "${!ebooks[@]}"; do
            ebook_path="${ebooks[i]%%#*}"
            if [[ -z "$glob" ]] || goals_glob_matches "$ebook_path" "$glob" || \
               goals_glob_matches "${ebook_path##*/}" "$glob"; then
                visible+=("$i")
            fi
        done

        total=${#visible[@]}
        total_pages=$(( (total + page_size - 1) / page_size ))
        (( total_pages < 1 )) && total_pages=1
        (( page > total_pages )) && page=$total_pages
        start=$(( (page - 1) * page_size ))
        end=$(( start + page_size ))
        (( end > total )) && end=$total

        menu_items=(
            "__APPLY_GLOB__" "Apply glob (matches ebook file path or file name)"
            "__RESET_GLOB__" "Reset glob"
        )
        (( page > 1 )) && menu_items+=("__PREV_PAGE__" "<< Previous page")
        for (( k=start; k<end; k++ )); do
            i=${visible[k]}
            menu_items+=("$i" "${ebooks[i]%%#*}")
        done
        (( page < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page >>")

        choice=$(whiptail --title "Select an ebook" --cancel-button "Back" \
            --menu "Choose an ebook (page $page/$total_pages)\nFile path/name glob: ${glob:-none}  |  ${total} ebook(s) shown" \
            35 155 25 "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1
        case "$choice" in
            __APPLY_GLOB__)
                if new_glob=$(whiptail --title "Apply eBook Glob" --inputbox \
                    "Enter a case-insensitive glob to match the full ebook file path or file name. Use * and ? as wildcards; leave empty to show all ebooks." \
                    11 90 "$glob" 3>&1 1>&2 2>&3); then
                    glob="$new_glob"
                    page=1
                fi
                ;;
            __RESET_GLOB__) glob=""; page=1 ;;
            __PREV_PAGE__) (( page > 1 )) && page=$((page - 1)) ;;
            __NEXT_PAGE__) (( page < total_pages )) && page=$((page + 1)) ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || continue
                (( choice >= 0 && choice < ${#ebooks[@]} )) || continue
                selected_ebook="${ebooks[choice]}"
                break
                ;;
        esac
    done

    [[ -n "$selected_ebook" ]] || return 1
    chapters_part="${selected_ebook#*#}"
    if [[ "$selected_ebook" == *#* && -n "$chapters_part" ]]; then
        local selected_chapter
        selected_chapter=$(get_chapters "$selected_ebook") || return 1
        if [[ "$selected_chapter" == ">> Just open" ]]; then
            handle_no_chapters "$selected_ebook"
            return
        fi
        [[ -n "$selected_chapter" ]] || return 1
        page_value=$(extract_page "$selected_chapter")
        [[ -n "$page_value" ]] || return 1
        open_evince "$selected_ebook" "$page_value"
    else
        handle_no_chapters "$selected_ebook"
    fi
}

do_stuff_with_project_file() {
    local selected_project_title

    truncate_tag() {
        local tags="$1"
        local max_len=60    # tweak this!

        # If already within limit, print unchanged
        if (( ${#tags} <= max_len )); then
            echo "$tags"
            return
        fi

        # Split into an array (preserve tags with spaces)
        IFS=',' read -r -a arr <<< "$tags"

        local latest_tag="${arr[-1]}"
        local result=""
        local sep=""

        # Try adding tags until adding another exceeds limit
        for (( i=0; i<${#arr[@]}-1; i++ )); do
            local t="${arr[$i]}"
            local candidate="${result}${sep}${t}"

            # If not enough room even if we later add ", ..., latest_tag", stop
            local future="${candidate}, ..., ${latest_tag}"
            if (( ${#future} > max_len )); then
                break
            fi

            result="$candidate"
            sep=", "
        done

        # If we couldn't include any tags (very tight width), result may be empty
        if [[ -z "$result" ]]; then
            echo "... , ${latest_tag}"
        else
            echo "${result}, ..., ${latest_tag}"
        fi
    }

    show_note_menu() {
        selected_project_title="$1"
        # might as well truncate it here.
        (( ${#selected_project_title} > 50 )) && selected_project_title="${selected_project_title:0:50}..."
        shift

        local note_menu_options=("$@")
        local page=0
        local per_page=50    # adjust this to my liking
        # Status info: active filters and how many linked notes are visible.
        local filter_summary
        filter_summary="\nTag filter: ${TAG_FILTER_BY:-none}   |   Title glob: ${GLOB_FILTER_BY:-none}"
        filter_summary+="\nShowing ${#note_lines[@]} of ${LINKED_NOTES_TOTAL:-?} linked notes"
        local total_items=$(( ${#note_menu_options[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local selected_note_tag=""

        while true; do
            local start=$(( page * per_page ))
            local end=$(( start + per_page ))
            if (( end > total_items )); then end=$total_items; fi

            # Build current page menu items
            local menu_items=()
            for ((i=start; i<end; i++)); do
                local idx=$(( i * 2 ))
                menu_items+=( "${note_menu_options[idx]}" "${note_menu_options[idx+1]}" )
            done

            # Add navigation options
            if (( page > 0 )); then
                menu_items+=( "<< Prev" "" )
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=( ">> Next" "" )
            fi

            # Display menu
            selected_note_tag=$(whiptail --title "Linked Notes for ${selected_project_title} (Page $((page+1))/$total_pages)" \
                --menu "Select a linked note:${filter_summary}" 35 155 25 "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

            # Handle navigation
            case "$selected_note_tag" in
                "<< Prev") ((page--));;
                ">> Next") ((page++));;
                *) echo "$selected_note_tag"; return 0;;
            esac
        done
    }

    open_url_assoc_to_chosen_note() {
        goals_open_url_for_note "$note_path"
    }

    assoc_url_to_chosen_note() {
        goals_manage_urls_for_note "$note_path"
    }

    dissoc_url_from_chosen_note() {
        goals_dissociate_urls_from_note "$note_path"
    }

    associate_chosen_note_to_project() {
        # Get note path from arg
        local note_path="$1"
        [[ -z "$note_path" ]] && return 1

        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        # Do not ask for a glob up front. Select Project offers
        # __APPLY_GLOB__ / __RESET_GLOB__ and matches project file names.
        local GOALS_PROJECT_RESTRICT_FILE=""
        local GOALS_PROJECT_TITLE_MODE=""
        GOALS_PROJECT_GLOB=""
        goals_select_project "Select Project" || { rm -f -- "$temp_file"; return 1; }
        local selected_project_path="$GOALS_SELECTED_PROJECT_PATH"
        [[ -n "$selected_project_path" ]] || { rm -f -- "$temp_file"; return 1; }

        # User already chosen $note_path as chosen note file.
        local selected_note_path
        selected_note_path="$note_path"

        [[ -z "$selected_note_path" ]] && return 1

        # Process PROJECTS_DB
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                #echo >> "$temp_file"
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                return 1
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                return 1
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            return 1
        fi
    }

    print_chosen_note() {
        print_file_from_do_stuff_project() {
            # Check if file argument is provided
            if [ -z "$1" ]; then
                return 1
            fi

            local file_to_print="$1"

            # Check if file exists
            if [ ! -f "$file_to_print" ]; then
                echo "Error: File '$file_to_print' does not exist." >&2
                return 1
            fi

            # Get list of printers
            local printers
            printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')            

            # Edge case: no printers found.
            [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

            # Convert printer list into whiptail menu format
            local menu_items=()
            for p in $printers; do
                menu_items+=("$p" "")
            done

            # Show whiptail menu to select printer
            local selected_printer
            selected_printer=$(whiptail --title "Select Printer" \
                --menu "Choose a printer:" 20 60 10 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            # Check if user cancelled
            if [ $? -ne 0 ]; then
                return 1
            fi

            # Print the file
            if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
                lpr -P "$selected_printer" "$file_to_print"
                if [ $? -eq 0 ]; then
                    whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
                else
                    whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                    return 1
                fi            
            else
                :  # do nothing if No or Cancel
            fi
        }

        local selected_path="$1"       
        print_file_from_do_stuff_project "$selected_path"
    }

    associate_new_note_to_project_from_do_stuff() {
        # note path is the new note you've just created from select notes menu.
        local NEW_NOTE_PATH="$note_path"
        [[ -z "$NEW_NOTE_PATH" ]] && return 1

        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        local selected_project_path
        selected_project_path="$1"
        [[ -z "$selected_project_path" ]] && return 1

        local selected_note_path="$NEW_NOTE_PATH"

        # WE'VE SELECTED PROJECT FILE AND NOTE FILE AT THIS POINT!!!!

        # Process PROJECTS_DB - update each line (only change line of selected project file)
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then set duplicate and break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                return 1
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                return 1
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            return 1
        fi
    }

    associate_note_to_project_from_do_stuff() {
        # Link note: pick a starting tag filter, then tick the notes to link.
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        local selected_project_path="$1"
        [[ -z "$selected_project_path" ]] && return 1

        # Notes already linked to the project are not offered again.
        local -A linked_map=()
        local pl_title pl_path pl_notes lnp
        while IFS='|' read -r pl_title pl_path pl_notes; do
            [[ "$pl_path" == "$selected_project_path" ]] || continue
            while IFS= read -r lnp; do
                [[ -n "$lnp" ]] && linked_map["$lnp"]=1
            done < <(tr ',' '\n' <<< "$pl_notes")
            break
        done < "$PROJECTS_DB"

        # Select Note Tag to Filter Notes: [NO TAG], [ANY TAG] or a tag, with
        # __FILTER__ (literal substring) and __RESET_FILTER__.
        local selected_note_tag note_title note_path note_tags rest
        local -a note_candidates=() all_note_paths=()
        while :; do
            goals_select_note_tag_filter || return 1
            selected_note_tag="$GOALS_SELECTED_NOTE_TAG"

            note_candidates=()
            all_note_paths=()
            while IFS='|' read -r note_title note_path note_tags rest; do
                [[ -n "$note_path" ]] || continue
                [[ -n "${linked_map[$note_path]:-}" ]] && continue
                all_note_paths+=("$note_path")
                case "$selected_note_tag" in
                    "[ANY TAG]") note_candidates+=("$note_path") ;;
                    "[NO TAG]")  [[ -z "$note_tags" ]] && note_candidates+=("$note_path") ;;
                    *)           goals_note_has_tag "$note_tags" "$selected_note_tag" && note_candidates+=("$note_path") ;;
                esac
            done < "$NOTES_DB"

            (( ${#note_candidates[@]} > 0 )) && break

            case "$selected_note_tag" in
                "[ANY TAG]") whiptail --msgbox "There are no notes left to link to this project." 8 60 ;;
                "[NO TAG]")  whiptail --msgbox "There are no notes with no associated tag found." 8 60 ;;
                *)           whiptail --msgbox "Tag '${selected_note_tag}' has no notes available to link." 8 60 ;;
            esac
        done

        # Choose Note to Associate: the chosen tag is the starting tag filter;
        # the status shows the current tag filter and glob.
        GOALS_NOTE_GLOB=""
        GOALS_NOTE_TAGFILTER="$selected_note_tag"
        local -a selected_note_paths=() remaining=()
        local temp_file project_found line_updated added_count line title path notes np new_notes
        local -A already=()
        while :; do
            goals_pick_notes_multi "Choose Note to Associate" \
                "Choose notes to link to the project" \
                "__add__" "Link the selected notes to the project" top \
                "${all_note_paths[@]}" || return 1
            selected_note_paths=("${GOALS_PICKED_PATHS[@]}")

            temp_file=$(mktemp) || return 1
            project_found=0; line_updated=0; added_count=0
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                IFS='|' read -r title path notes <<< "$line"
                if [[ "$path" == "$selected_project_path" ]]; then
                    project_found=1
                    already=()
                    while IFS= read -r np; do
                        [[ -n "$np" ]] && already["$np"]=1
                    done < <(tr ',' '\n' <<< "$notes")
                    new_notes="$notes"
                    for np in "${selected_note_paths[@]}"; do
                        [[ -n "${already[$np]:-}" ]] && continue
                        new_notes="${new_notes:+$new_notes,}$np"
                        already["$np"]=1
                        added_count=$((added_count + 1))
                    done
                    (( added_count > 0 )) && line_updated=1
                    printf '%s\n' "$title|$path|$new_notes" >> "$temp_file"
                else
                    printf '%s\n' "$line" >> "$temp_file"
                fi
            done < "$PROJECTS_DB"

            if (( ! project_found )); then
                rm -f "$temp_file"
                whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
                continue
            fi
            if (( ! line_updated )); then
                rm -f "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                continue
            fi

            mv "$temp_file" "$PROJECTS_DB"
            whiptail --msgbox "$added_count note(s) successfully associated with the project." 10 60

            # The linked notes are no longer offered.
            for np in "${selected_note_paths[@]}"; do linked_map["$np"]=1; done
            remaining=()
            for np in "${all_note_paths[@]}"; do
                [[ -z "${linked_map[$np]:-}" ]] && remaining+=("$np")
            done
            all_note_paths=("${remaining[@]}")
            if (( ${#all_note_paths[@]} == 0 )); then
                whiptail --msgbox "All available notes are now linked to this project." 8 60
                return 0
            fi
        done
    }

    dissociate_note_from_project_from_do_stuff() {
        # Unlink note: tick the linked notes to unlink. Glob (file name) and tag
        # filters are available inside the picker.
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Error: PROJECTS_DB file '$PROJECTS_DB' not found or empty." 10 60
            return 1
        fi

        local -a lines=()
        mapfile -t lines < "$PROJECTS_DB"

        local selected_project_path="$1"
        shift

        # With --filtered-notes only the notes visible in the main menu are offered.
        local restrict_to_filtered_notes=false
        local -A filtered_note_paths=()
        if [[ "${1:-}" == "--filtered-notes" ]]; then
            restrict_to_filtered_notes=true
            shift
            local filtered_note_line filtered_note_path
            for filtered_note_line in "$@"; do
                IFS='|' read -r _ filtered_note_path _ <<< "$filtered_note_line"
                [[ -n "$filtered_note_path" ]] && filtered_note_paths["$filtered_note_path"]=1
            done
        fi

        local selected_project
        selected_project=$(awk -F'|' -v path="$selected_project_path" '$2 == path { print NR; exit }' "$PROJECTS_DB")
        [[ -z "$selected_project" ]] && return 1
        ((selected_project--))

        local title path notes
        IFS='|' read -r title path notes <<< "${lines[selected_project]}"

        GOALS_NOTE_GLOB=""
        GOALS_NOTE_TAGFILTER=""

        local -a notes_arr=() candidates=() picked=() new_notes=()
        local -A picked_map=()
        local np new_notes_str tmp_db
        while true; do
            if [[ -z "$notes" ]]; then
                whiptail --msgbox "Selected project has no associated notes." 10 60
                return 1
            fi

            notes_arr=(); candidates=()
            IFS=',' read -ra notes_arr <<< "$notes"
            for np in "${notes_arr[@]}"; do
                [[ -z "$np" ]] && continue
                if [[ "$restrict_to_filtered_notes" == true && -z "${filtered_note_paths[$np]:-}" ]]; then
                    continue
                fi
                candidates+=("$np")
            done
            if (( ${#candidates[@]} == 0 )); then
                whiptail --msgbox "No linked notes match the current filter." 10 60
                return 1
            fi

            goals_pick_notes_multi "Choose Note to Dissociate" \
                "Choose notes to unlink from the project" \
                "__remove__" "Unlink the selected notes from the project" top \
                "${candidates[@]}" || return 1
            picked=("${GOALS_PICKED_PATHS[@]}")

            picked_map=()
            for np in "${picked[@]}"; do picked_map["$np"]=1; done
            new_notes=()
            for np in "${notes_arr[@]}"; do
                [[ -z "$np" ]] && continue
                [[ -z "${picked_map[$np]:-}" ]] && new_notes+=("$np")
            done
            new_notes_str=""
            (( ${#new_notes[@]} > 0 )) && new_notes_str=$(IFS=','; printf '%s' "${new_notes[*]}")

            lines[selected_project]="$title|$path|$new_notes_str"
            notes="$new_notes_str"

            tmp_db=$(mktemp) || return 1
            printf '%s\n' "${lines[@]}" > "$tmp_db"
            mv -- "$tmp_db" "$PROJECTS_DB" || { rm -f -- "$tmp_db"; return 1; }

            whiptail --msgbox "${#picked[@]} note(s) successfully dissociated from project." 10 60
            if [[ -z "$notes" ]]; then
                whiptail --msgbox "All notes have been dissociated from this project." 10 60
                break
            fi
        done
    }

    edit_plan() {
        #####################################
        # get selected project path as $1
        #####################################

        # Check if projects database exists and has entries
        [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]] && {
            whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 </dev/tty >/dev/tty
            return 1
        }

        save_to_projects_db() {
            local entry="${project_title}|${project_path}|"
            [[ -z "$project_title" || -z "$project_path" ]] && return

            if grep -Fxq -- "$entry" "$PROJECTS_DB" 2>/dev/null; then
                return 0  # already present
            fi

            printf '%s\n' "$entry" >> "$PROJECTS_DB"
        }

        # ============================================================
        # Babyrus - Goal / Project Manager
        #
        # Project file format:
        #
        # TYPE|ID|PARENT_ID|POSITION|STATUS|IMPORTANCE|CONTENT|COMMENT
        #
        # H|1|0|0|NS|N|Programming
        # H|2|1|0|IP|I|Bash
        # H|3|2|0|IP|VI|Whiptail
        # T|4|3|0|C|VI|create checklist menu->implement checklist
        # T|5|3|1|NS|I|support pagination->add prev/next
        #
        # TYPE:
        #   H = heading
        #   T = task
        #
        # STATUS:
        #   NS = not started
        #   IP = in progress
        #   PA = paused
        #   C  = completed
        #
        # IMPORTANCE:
        #   VI = very important
        #   I  = important
        #   N  = normal
        #   NI = not important
        #
        # ============================================================


        # ------------------------------------------------------------
        # Configuration
        # ------------------------------------------------------------

        PROJECT_FILE="$1"

        # Verify project file exists
        [[ ! -f "$PROJECT_FILE" ]] && {
            whiptail --msgbox "Project file not found: ${PROJECT_FILE}" 10 60
            return 1
        }    

        declare -a item_type
        declare -a item_id
        declare -a parent_id
        declare -a item_position
        declare -a item_status
        declare -a item_importance
        declare -a item_content
        declare -a item_comment

        # Calculated/effective status.
        #
        # For tasks:
        #     effective_status == stored status
        #
        # For leaf headings:
        #     effective_status == stored status
        #
        # For container headings:
        #     effective_status is calculated from children.
        #
        declare -a effective_status

        NEXT_ID=1

        # Return status/importance to their friendly names when displaying.
        status_name() {
            case "$1" in
                NS) printf '%s' "Not started" ;;
                IP) printf '%s' "In progress" ;;
                PA) printf '%s' "Paused" ;;
                C)  printf '%s' "Completed" ;;
                *)  printf '%s' "$1" ;;
            esac
        }

        importance_name() {
            case "$1" in
                VI) printf '%s' "Very important" ;;
                I)  printf '%s' "Important" ;;
                N)  printf '%s' "Normal" ;;
                NI) printf '%s' "Not important" ;;
                *)  printf '%s' "$1" ;;
            esac
        }


        # ------------------------------------------------------------
        # Validation helpers
        # ------------------------------------------------------------

        valid_status() {
            case "$1" in
                NS|IP|PA|C) return 0 ;;
                *) return 1 ;;
            esac
        }

        valid_importance() {
            case "$1" in
                VI|I|N|NI) return 0 ;;
                *) return 1 ;;
            esac
        }

        valid_type() {
            [[ "$1" == "H" || "$1" == "T" ]]
        }

        # Find array index for persistent item ID.
        #
        # Returns:
        #   global variable RESULT_INDEX
        #
        find_index_by_id() {
            local wanted_id="$1"
            local i

            RESULT_INDEX=-1

            for i in "${!item_id[@]}"; do
                if [[ "${item_id[i]}" == "$wanted_id" ]]; then
                    RESULT_INDEX=$i
                    return 0
                fi
            done

            return 1
        }


        # ------------------------------------------------------------
        # Project loading
        # ------------------------------------------------------------

        load_project() {
            local file="${1:-$PROJECT_FILE}"
            local line
            local type id parent position status importance content comment

            item_type=()
            item_id=()
            parent_id=()
            item_position=()
            item_status=()
            item_importance=()
            item_content=()
            item_comment=()
            effective_status=()

            NEXT_ID=1

            [[ -f "$file" ]] || return 0

            while IFS= read -r line || [[ -n "$line" ]]; do

                # Ignore empty lines.
                [[ -z "$line" ]] && continue

                # Comments may be useful during development.
                [[ "$line" == \#* ]] && continue

                IFS='|' read -r type id parent position status importance content comment <<< "$line"

                if [[ -z "$content" ]]; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "Invalid line:\n\n$line" \
                        10 70
                    return 1
                fi

                if ! valid_type "$type"; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "Invalid item type '$type'.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                if ! valid_status "$status"; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "Invalid status '$status'.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                if ! valid_importance "$importance"; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "Invalid importance '$importance'.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                if [[ "$content" == *"|"* ]]; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "The content contains '|', which is reserved as a field separator.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                if [[ "$comment" == *"|"* ]]; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "The comment contains '|', which is reserved as a field separator.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                item_type+=("$type")
                item_id+=("$id")
                parent_id+=("$parent")
                item_position+=("$position")
                item_status+=("$status")
                item_importance+=("$importance")
                item_content+=("$content")
                item_comment+=("$comment")

                effective_status+=("$status")

                if [[ "$id" =~ ^[0-9]+$ ]]; then
                    (( id >= NEXT_ID )) && NEXT_ID=$((id + 1))
                fi

            done < "$file"

            validate_project || return 1

            calculate_all_statuses
        }


        # ------------------------------------------------------------
        # Structural validation
        # ------------------------------------------------------------

        validate_project() {
            local i parent_index

            for i in "${!item_id[@]}"; do

                # IDs must be numeric.
                if ! [[ "${item_id[i]}" =~ ^[0-9]+$ ]]; then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Item ID '${item_id[i]}' is not numeric." \
                        8 60
                    return 1
                fi

                # Parent 0 means root.
                if [[ "${parent_id[i]}" == "0" ]]; then

                    # Root tasks are not allowed.
                    if [[ "${item_type[i]}" == "T" ]]; then
                        whiptail \
                            --title "Invalid Project" \
                            --msgbox "Task '${item_content[i]}' has no heading parent." \
                            8 70
                        return 1
                    fi

                    continue
                fi

                find_index_by_id "${parent_id[i]}"

                if (( RESULT_INDEX < 0 )); then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Item '${item_content[i]}' refers to missing parent ID '${parent_id[i]}'." \
                        8 70
                    return 1
                fi

                parent_index=$RESULT_INDEX

                # Tasks can only be children of headings.
                if [[ "${item_type[i]}" == "T" &&
                    "${item_type[parent_index]}" != "H" ]]; then

                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Task '${item_content[i]}' is under another task.\n\nTasks may only belong to headings." \
                        10 70
                    return 1
                fi

                # Detect immediate self-parent.
                if [[ "${item_id[i]}" == "${parent_id[i]}" ]]; then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Item '${item_content[i]}' is its own parent." \
                        8 70
                    return 1
                fi
            done

            # Detect circular parent chains.
            for i in "${!item_id[@]}"; do
                if ! hierarchy_is_valid_from "$i"; then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "A circular hierarchy was detected involving:\n\n${item_content[i]}" \
                        10 70
                    return 1
                fi
            done

            return 0
        }


        hierarchy_is_valid_from() {
            local start_index="$1"
            local current_index="$start_index"
            local parent
            local -a visited=()

            while :; do

                # If we've seen this item already, there is a cycle.
                for parent in "${visited[@]}"; do
                    [[ "$parent" == "$current_index" ]] && return 1
                done

                visited+=("$current_index")

                parent="${parent_id[current_index]}"

                [[ "$parent" == "0" ]] && return 0

                find_index_by_id "$parent"
                (( RESULT_INDEX >= 0 )) || return 1

                current_index=$RESULT_INDEX
            done
        }


        # ------------------------------------------------------------
        # Tree helpers
        # ------------------------------------------------------------
        get_children() {
            local wanted_parent="$1"
            local i
            local position
            local child_index

            CHILDREN=()

            # Output indices sorted by position.
            while IFS=$'\t' read -r position child_index; do
                [[ -n "$child_index" ]] && CHILDREN+=("$child_index")
            done < <(
                for i in "${!item_id[@]}"; do
                    if [[ "${parent_id[i]}" == "$wanted_parent" ]]; then
                        printf '%s\t%s\n' "${item_position[i]}" "$i"
                    fi
                done |
                sort -n -k1,1 -k2,2
            )
        }

        get_children_old() {
            local wanted_parent="$1"
            local i

            CHILDREN=()

            # Output indices sorted by position.
            while IFS=$'\t' read -r position index; do
                [[ -n "$index" ]] && CHILDREN+=("$index")
            done < <(
                for i in "${!item_id[@]}"; do
                    if [[ "${parent_id[i]}" == "$wanted_parent" ]]; then
                        printf '%s\t%s\n' "${item_position[i]}" "$i"
                    fi
                done |
                sort -n -k1,1 -k2,2
            )
        }


        is_container() {
            local index="$1"

            get_children "${item_id[index]}"
            (( ${#CHILDREN[@]} > 0 ))
        }


        get_depth() {
            local index="$1"
            local depth=0
            local current="$index"
            local parent

            while [[ "${parent_id[current]}" != "0" ]]; do
                parent="${parent_id[current]}"

                find_index_by_id "$parent"
                (( RESULT_INDEX >= 0 )) || {
                    printf '%s' "$depth"
                    return
                }

                current=$RESULT_INDEX
                ((depth++))
            done

            printf '%s' "$depth"
        }


        # ------------------------------------------------------------
        # Status calculation
        # ------------------------------------------------------------

        calculate_status() {
            local index="$1"
            local type="${item_type[index]}"
            local status
            local child
            local child_status

            # Tasks always use their stored status.
            if [[ "$type" == "T" ]]; then
                effective_status[index]="${item_status[index]}"
                printf '%s' "${effective_status[index]}"
                return
            fi

            # Find children.
            get_children "${item_id[index]}"

            # Leaf heading: manually controlled.
            if (( ${#CHILDREN[@]} == 0 )); then
                effective_status[index]="${item_status[index]}"
                printf '%s' "${effective_status[index]}"
                return
            fi

            local has_ns=0
            local has_ip=0
            local has_pa=0
            local has_c=0

            # Container heading: calculate recursively.
            for child in "${CHILDREN[@]}"; do
                child_status="$(calculate_status "$child")"

                case "$child_status" in
                    NS) has_ns=1 ;;
                    IP) has_ip=1 ;;
                    PA) has_pa=1 ;;
                    C)  has_c=1 ;;
                esac
            done

            # Aggregation rules:
            #
            # Any active work => IN PROGRESS
            # Otherwise any paused work => PAUSED
            # Completed + not-started => IN PROGRESS
            # All completed => COMPLETED
            # All not-started => NOT STARTED

            if (( has_ip )); then
                status="IP"

            elif (( has_pa )); then
                status="PA"

            elif (( has_c && has_ns )); then
                status="IP"

            elif (( has_c )); then
                status="C"

            else
                status="NS"
            fi

            effective_status[index]="$status"
            printf '%s' "$status"
        }


        calculate_all_statuses() {
            local i

            effective_status=()

            for i in "${!item_id[@]}"; do
                effective_status+=("${item_status[i]}")
            done

            # Calculate every item. Recursive calls ensure that children
            # are resolved before their parents.
            for i in "${!item_id[@]}"; do
                calculate_status "$i" >/dev/null
            done
        }


        # ------------------------------------------------------------
        # Status / importance UI
        # ------------------------------------------------------------

        select_status() {
            local current="$1"

            whiptail \
                --title "Change Status" \
                --menu "Select status:" \
                15 60 6 \
                "NS" "Not started" \
                "IP" "In progress" \
                "PA" "Paused" \
                "C"  "Completed" \
                3>&1 1>&2 2>&3
        }


        select_importance() {
            whiptail \
                --title "Change Importance" \
                --menu "Select importance:" \
                15 60 6 \
                "VI" "Very important" \
                "I"  "Important" \
                "N"  "Normal" \
                "NI" "Not important" \
                3>&1 1>&2 2>&3
        }


        # ------------------------------------------------------------
        # Input helpers
        # ------------------------------------------------------------

        add_heading() {
            local parent="$1"
            local text

            text="$(
                whiptail \
                    --title "Add Heading" \
                    --inputbox "Heading name:" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$text" ]] && return

            if [[ "$text" == *"|"* ]]; then
                whiptail --msgbox "The heading cannot contain '|'.\n\nIt is reserved by the project file format." 9 70
                return
            fi

            add_item "H" "$parent" "$text"
        }


        add_task() {
            local parent="$1"
            local task
            local plan
            local content

            # Parent must be a heading.
            find_index_by_id "$parent" || return

            if [[ "${item_type[RESULT_INDEX]}" != "H" ]]; then
                whiptail \
                    --title "Invalid Parent" \
                    --msgbox "Tasks can only be added under headings." \
                    8 60
                return
            fi

            task="$(
                whiptail \
                    --title "Add Task" \
                    --inputbox "Task:" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$task" ]] && return

            plan="$(
                whiptail \
                    --title "Add Task Plan" \
                    --inputbox "Plan for:\n\n$task" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            if [[ -n "$plan" ]]; then
                content="${task}->${plan}"
            else
                content="$task"
            fi

            if [[ "$content" == *"|"* ]]; then
                whiptail \
                    --msgbox "Task or plan cannot contain '|'.\n\nIt is reserved by the project file format." \
                    9 70
                return
            fi

            add_item "T" "$parent" "$content"
        }

        find_todo_heading() {
            local i

            TODO_HEADING_ID=""

            for i in "${!item_id[@]}"; do
                if [[ "${item_type[i]}" == "H" &&
                    "${parent_id[i]}" == "0" &&
                    "${item_content[i]}" == "TODO" ]]; then

                    TODO_HEADING_ID="${item_id[i]}"
                    return 0
                fi
            done

            return 1
        }


        find_todo_date_heading() {
            local todo_id="$1"
            local todo_date="$2"
            local child

            TODO_DATE_HEADING_ID=""

            get_children "$todo_id"

            for child in "${CHILDREN[@]}"; do
                if [[ "${item_type[child]}" == "H" &&
                    "${item_content[child]}" == "$todo_date" ]]; then

                    TODO_DATE_HEADING_ID="${item_id[child]}"
                    return 0
                fi
            done

            return 1
        }


        next_todo_task_number() {
            local date_heading_id="$1"
            local child
            local number
            local max=0

            get_children "$date_heading_id"

            for child in "${CHILDREN[@]}"; do
                [[ "${item_type[child]}" == "T" ]] || continue

                if number="$(get_number_prefix "${item_content[child]}")"; then
                    # Treat the prefix as decimal, even if it has leading zeroes.
                    number=$((10#$number))

                    (( number > max )) && max="$number"
                fi
            done

            printf '%s' "$((max + 1))"
        }

        find_rules_for_today_heading() {
            local i

            RULES_FOR_TODAY_ID=""

            for i in "${!item_id[@]}"; do
                if [[ "${item_type[i]}" == "H" &&
                    "${parent_id[i]}" == "0" &&
                    "${item_content[i]}" == "RULES FOR TODAY" ]]; then

                    RULES_FOR_TODAY_ID="${item_id[i]}"
                    return 0
                fi
            done

            return 1
        }


        find_rules_for_today_date_heading() {
            local rules_id="$1"
            local rules_date="$2"
            local child

            RULES_FOR_TODAY_DATE_ID=""

            get_children "$rules_id"

            for child in "${CHILDREN[@]}"; do
                if [[ "${item_type[child]}" == "H" &&
                    "${item_content[child]}" == "$rules_date" ]]; then

                    RULES_FOR_TODAY_DATE_ID="${item_id[child]}"
                    return 0
                fi
            done

            return 1
        }


        next_rules_for_today_task_number() {
            local date_heading_id="$1"
            local child
            local number
            local max=0

            get_children "$date_heading_id"

            for child in "${CHILDREN[@]}"; do
                [[ "${item_type[child]}" == "T" ]] || continue

                if number="$(get_number_prefix "${item_content[child]}")"; then
                    number=$((10#$number))
                    (( number > max )) && max="$number"
                fi
            done

            printf '%s' "$((max + 1))"
        }


        add_rules_for_today_item() {
            local rules_id
            local rules_date
            local date_heading_id
            local rules_number
            local task
            local content

            # Today's date.
            rules_date="$(date '+%A %-d %B %Y')"

            # ------------------------------------------------------------
            # Find or create the top-level RULES FOR TODAY heading.
            # ------------------------------------------------------------

            if find_rules_for_today_heading; then
                rules_id="$RULES_FOR_TODAY_ID"
            else
                rules_id="$NEXT_ID"
                add_item "H" "0" "RULES FOR TODAY"
            fi

            # ------------------------------------------------------------
            # Find or create today's date heading.
            # ------------------------------------------------------------

            if find_rules_for_today_date_heading "$rules_id" "$rules_date"; then
                date_heading_id="$RULES_FOR_TODAY_DATE_ID"
            else
                date_heading_id="$NEXT_ID"
                add_item "H" "$rules_id" "$rules_date"
            fi

            # ------------------------------------------------------------
            # Ask for the rule.
            # ------------------------------------------------------------

            task="$(
                whiptail \
                    --title "Add Rule for Today" \
                    --inputbox "Rule for $rules_date:" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$task" ]] && return

            if [[ "$task" == *"|"* ]]; then
                whiptail \
                    --title "Invalid Rule" \
                    --msgbox "The rule cannot contain '|'.\n\nIt is reserved by the project file format." \
                    9 70
                return
            fi

            # ------------------------------------------------------------
            # Determine next number for today's rules.
            # ------------------------------------------------------------

            rules_number="$(next_rules_for_today_task_number "$date_heading_id")"
            content="${rules_number}. ${task}"

            add_item "T" "$date_heading_id" "$content"

            # Keep today's rules numerically sorted.
            sort_children "$date_heading_id"

            # Keep the special root headings in their required order.
            sort_children "0"
        }

        add_todo_item() {
            local todo_id
            local todo_date
            local date_heading_id
            local todo_number
            local task
            local content

            # Today's date, for example:
            # Tuesday 29 September 2026
            todo_date="$(date '+%A %-d %B %Y')"

            # ------------------------------------------------------------
            # Find or create the top-level TODO heading.
            # ------------------------------------------------------------

            if find_todo_heading; then
                todo_id="$TODO_HEADING_ID"
            else
                # add_item() increments NEXT_ID, so capture the new
                # heading's ID before calling it.
                todo_id="$NEXT_ID"
                add_item "H" "0" "TODO"
            fi

            # ------------------------------------------------------------
            # Find or create today's date heading under TODO.
            # ------------------------------------------------------------

            if find_todo_date_heading "$todo_id" "$todo_date"; then
                date_heading_id="$TODO_DATE_HEADING_ID"
            else
                # Capture the ID that add_item() will assign.
                date_heading_id="$NEXT_ID"
                add_item "H" "$todo_id" "$todo_date"
            fi

            # ------------------------------------------------------------
            # Ask for the TODO task text.
            # ------------------------------------------------------------

            task="$(
                whiptail \
                    --title "Add TODO Item" \
                    --inputbox "TODO item for $todo_date:" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$task" ]] && return

            if [[ "$task" == *"|"* ]]; then
                whiptail \
                    --title "Invalid TODO Item" \
                    --msgbox "The TODO item cannot contain '|'.\n\nIt is reserved by the project file format." \
                    9 70
                return
            fi

            # ------------------------------------------------------------
            # Determine the next number under today's date heading.
            # ------------------------------------------------------------

            todo_number="$(next_todo_task_number "$date_heading_id")"
            content="${todo_number}. ${task}"

            add_item "T" "$date_heading_id" "$content"

            # ------------------------------------------------------------
            # Keep today's TODO tasks sorted by their numeric prefix.
            # ------------------------------------------------------------

            sort_children "$date_heading_id"

            # Keep TODO as the first root-level heading.
            sort_children "0"            
        }        


        add_item() {
            local type="$1"
            local parent="$2"
            local content="$3"

            local position

            position="$(next_position "$parent")"

            item_type+=("$type")
            item_id+=("$NEXT_ID")
            parent_id+=("$parent")
            item_position+=("$position")

            # New items use default status and importance.
            item_status+=("NS")
            item_importance+=("N")

            item_content+=("$content")
            item_comment+=("")
            effective_status+=("NS")

            ((NEXT_ID++))

            calculate_all_statuses
        }


        next_position() {
            local parent="$1"
            local max=-1
            local i

            for i in "${!item_id[@]}"; do
                if [[ "${parent_id[i]}" == "$parent" ]]; then
                    (( item_position[i] > max )) && max="${item_position[i]}"
                fi
            done

            printf '%s' "$((max + 1))"
        }


        # ------------------------------------------------------------
        # Edit item
        # ------------------------------------------------------------

        edit_text() {
            local index="$1"
            local new_text

            new_text="$(
                whiptail \
                    --title "Edit Text" \
                    --inputbox \
                    "Current text:" \
                    10 80 \
                    "${item_content[index]}" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$new_text" ]] && return

            if [[ "$new_text" == *"|"* ]]; then
                whiptail \
                    --title "Invalid Text" \
                    --msgbox "'|' cannot be used because it is the project-file field separator." \
                    8 70
                return
            fi

            item_content[index]="$new_text"
        }

    edit_task() {
        local index="$1"
        local task plan

        if [[ "${item_content[index]}" == *"->"* ]]; then
            task="${item_content[index]%%->*}"
            plan="${item_content[index]#*->}"
        else
            task="${item_content[index]}"
            plan=""
        fi

        task="$(
            whiptail \
                --title "Edit Task" \
                --inputbox "Task:" \
                10 70 \
                "$task" \
                3>&1 1>&2 2>&3
        )" || return

        # Validate task
        if [[ -z "$task" || "$task" == *"|"* ]]; then
            whiptail \
                --title "Invalid Task" \
                --msgbox "Task cannot be blank or contain the | character." \
                8 60
            return
        fi

        plan="$(
            whiptail \
                --title "Edit Plan" \
                --inputbox "Plan:" \
                10 70 \
                "$plan" \
                3>&1 1>&2 2>&3
        )" || return

        # Validate plan
        if [[ "$plan" == *"|"* ]]; then
            whiptail \
                --title "Invalid Plan" \
                --msgbox "Plan cannot contain the | character." \
                8 60
            return
        fi

        # deal with case where there is no ->
        if [[ -n "$plan" ]]; then
            item_content[index]="${task}->${plan}"
        else
            item_content[index]="$task"
        fi
    }

        edit_comment() {            
            local index="$1"
            local existing_comment="${item_comment[index]}"
            local tempfile
            local comment

            if ! tempfile=$(mktemp); then
                return 1
            fi

            # Ensure cleanup on return or exit
            trap 'rm -f -- "$tempfile"' EXIT RETURN

            # Populate with existing comment
            if [[ -n "$existing_comment" ]]; then
                existing_comment="${existing_comment//\[N\]/$'\n'}"
                if ! printf '%s' "$existing_comment" > "$tempfile"; then
                    return 1
                fi
            fi

            while :; do
                if ! "$DEFAULT_EDITOR" "$tempfile"; then
                    return 1
                fi

                # Read file contents without losing trailing newlines
                comment=$(cat "$tempfile"; printf 'x')
                comment="${comment%x}"

                # Strip the trailing newline added by nano/editor if present
                comment="${comment%$'\n'}"

                # Check for literal reserved string
                if [[ "$comment" == *'[N]'* ]]; then
                    whiptail \
                        --title "Invalid Comment" \
                        --msgbox "The sequence [N] is reserved for newlines and cannot be used in a comment." \
                        8 70
                    continue
                fi

                # Convert remaining newlines to [N]
                comment="${comment//$'\n'/[N]}"

                item_comment[index]="$comment"
                return 0
            done
        }

        view_comment() {
            local index="$1"
            local comment="${item_comment[index]}"

            [[ -n "$comment" ]] || comment="No comment has been added."

            comment="${comment//\[N\]/$'\n'}"

            whiptail \
                --title "Comment" \
                --msgbox "$comment" \
                20 80
        }

        edit_comment_old() {
            local index="$1"
            local comment

            comment="$(
                whiptail \
                    --title "Comment: ${item_content[index]}" \
                    --inputbox "Comment (optional):" \
                    14 90 \
                    "${item_comment[index]}" \
                    3>&1 1>&2 2>&3
            )" || return

            if [[ "$comment" == *"|"* || "$comment" == *$'\n'* ]]; then
                whiptail --msgbox "A comment cannot contain '|' or newline.\n\nThey are reserved by the project file format." 9 70
                return
            fi

            item_comment[index]="$comment"
        }


        view_comment_old() {
            local index="$1"
            local comment="${item_comment[index]}"

            [[ -n "$comment" ]] || comment="No comment has been added."

            whiptail \
                --title "Comment: ${item_content[index]}" \
                --msgbox "$comment" \
                16 90
        }

        # edit_task() {
        #     local index="$1"
        #     local task plan

        #     if [[ "${item_content[index]}" == *"->"* ]]; then
        #         task="${item_content[index]%%->*}"
        #         plan="${item_content[index]#*->}"
        #     else
        #         task="${item_content[index]}"
        #         plan=""
        #     fi

        #     task="$(
        #         whiptail \
        #             --title "Edit Task" \
        #             --inputbox "Task:" \
        #             10 70 \
        #             "$task" \
        #             3>&1 1>&2 2>&3
        #     )" || return

        #     plan="$(
        #         whiptail \
        #             --title "Edit Plan" \
        #             --inputbox "Plan:" \
        #             10 70 \
        #             "$plan" \
        #             3>&1 1>&2 2>&3
        #     )" || return

        #     item_content[index]="${task}->${plan}"
        # }


        # ------------------------------------------------------------
        # Move
        # ------------------------------------------------------------

        is_descendant_of() {
            local index="$1"
            local ancestor_id="$2"
            local current="$index"

            while [[ "${parent_id[current]}" != "0" ]]; do

                if [[ "${parent_id[current]}" == "$ancestor_id" ]]; then
                    return 0
                fi

                find_index_by_id "${parent_id[current]}"
                (( RESULT_INDEX >= 0 )) || return 1

                current=$RESULT_INDEX
            done

            return 1
        }


        choose_move_destination() {
            local moving_index="$1"
            local moving_type="${item_type[moving_index]}"
            local i
            local depth
            local indent
            local label
            local options=()

            # Root destination is allowed for headings only.
            if [[ "$moving_type" == "H" ]]; then
                options+=("0" "[ROOT]")
            fi

            for i in "${!item_id[@]}"; do

                # Can't move under itself.
                [[ "$i" == "$moving_index" ]] && continue

                # Destination must be a heading.
                [[ "${item_type[i]}" == "H" ]] || continue

                # A heading cannot be moved under one of its descendants.
                if [[ "$moving_type" == "H" ]]; then
                    if is_descendant_of "$i" "${item_id[moving_index]}"; then
                        continue
                    fi
                fi

                depth="$(get_depth "$i")"
                indent=""

                for ((j=0; j<depth; j++)); do
                    indent+="    "
                done

                label="${indent}${item_content[i]}"

                options+=("${item_id[i]}" "$label")
            done

            (( ${#options[@]} == 0 )) && return 1

            whiptail \
                --title "Move Item" \
                --menu \
                "Move '${item_content[moving_index]}' under:" \
                22 90 15 \
                "${options[@]}" \
                3>&1 1>&2 2>&3
        }


        move_item() {
            local index="$1"
            local old_parent="${parent_id[index]}"
            local new_parent
            local new_position

            new_parent="$(choose_move_destination "$index")" || return

            # Guard--if old_parent is the same as new_parent, no nothing--no move required!
            [[ "$old_parent" == "$new_parent" ]] && return            

            # Tasks cannot be moved to root.
            if [[ "${item_type[index]}" == "T" && "$new_parent" == "0" ]]; then
                whiptail \
                    --title "Invalid Move" \
                    --msgbox "Tasks must belong to a heading." \
                    8 60
                return
            fi

            new_position="$(next_position "$new_parent")"

            parent_id[index]="$new_parent"
            item_position[index]="$new_position"

            normalize_positions "$old_parent"
            normalize_positions "$new_parent"

            calculate_all_statuses
        }


        normalize_positions() {
            local parent="$1"
            local -a children
            local i position=0

            get_children "$parent"
            children=("${CHILDREN[@]}")

            for i in "${children[@]}"; do
                item_position[i]="$position"
                ((position++))
            done
        }

        # ------------------------------------------------------------
        # Reorder: move an item before/after a sibling of the same kind
        # ------------------------------------------------------------

        # Present the three move modes (before / after / under another heading).
        move_item_menu() {
            local index="$1"
            local action
            local type="${item_type[index]}"
            local kind

            if [[ "$type" == "H" ]]; then
                kind="heading"
            else
                kind="task"
            fi

            while :; do

                action="$(
                    whiptail \
                        --title "Move: ${item_content[index]}" \
                        --cancel-button "Back" \
                        --menu \
                        "Choose how to move this $kind:" \
                        18 78 10 \
                        "BEFORE" "Move before another $kind on this level" \
                        "AFTER"  "Move after another $kind on this level" \
                        "PARENT" "Move under another heading" \
                        "BACK"   "Back" \
                        3>&1 1>&2 2>&3
                )" || return

                case "$action" in

                    BEFORE)
                        move_item_relative "$index" "before"
                        return
                        ;;

                    AFTER)
                        move_item_relative "$index" "after"
                        return
                        ;;

                    PARENT)
                        move_item "$index"
                        return
                        ;;

                    BACK)
                        return
                        ;;
                esac
            done
        }


        # Move item $index before/after (mode) a same-type sibling on the
        # same level. Sibling positions are reassigned sequentially so the
        # position values on the level stay unique and consecutive.
        move_item_relative() {
            local index="$1"
            local mode="$2"   # "before" or "after"
            local parent="${parent_id[index]}"
            local type="${item_type[index]}"
            local kind
            local child
            local n=0
            local target
            local target_index=-1
            local inserted=0
            local pos=0
            local -a candidates=()
            local -a new_order=()

            if [[ "$type" == "H" ]]; then
                kind="heading"
            else
                kind="task"
            fi

            get_children "$parent"

            # Candidates: siblings of the same type, excluding the item
            # itself, in their current (position-sorted) order.
            for child in "${CHILDREN[@]}"; do
                [[ "$child" == "$index" ]] && continue
                [[ "${item_type[child]}" != "$type" ]] && continue

                ((n++))
                candidates+=(
                    "${item_id[child]}"
                    "$n) ${item_content[child]}"
                )
            done

            if (( n == 0 )); then
                whiptail \
                    --title "Move" \
                    --msgbox \
                    "There is no other $kind on this level to move next to." \
                    8 60
                return
            fi

            target="$(
                whiptail \
                    --title "Move $mode" \
                    --cancel-button "Back" \
                    --menu \
                    "Move '${item_content[index]}' $mode which item?" \
                    18 180 10 \
                    "${candidates[@]}" \
                    3>&1 1>&2 2>&3
            )" || return

            # Resolve the chosen item ID back to an index.
            find_index_by_id "$target"
            (( RESULT_INDEX >= 0 )) && target_index=$RESULT_INDEX

            if (( target_index < 0 )); then
                return
            fi

            # Rebuild the sibling order of the whole level minus the moving
            # item, then splice it back in before/after the target.
            for child in "${CHILDREN[@]}"; do
                [[ "$child" == "$index" ]] && continue

                if [[ "$child" == "$target_index" ]]; then
                    if [[ "$mode" == "before" ]]; then
                        new_order+=("$index" "$child")
                    else
                        new_order+=("$child" "$index")
                    fi
                    inserted=1
                else
                    new_order+=("$child")
                fi
            done

            (( inserted )) || return

            # Reassign positions sequentially, keeping the level consistent
            # exactly as normalize_positions() does.
            pos=0
            for child in "${new_order[@]}"; do
                item_position[child]="$pos"
                ((pos++))
            done
        }


        # ------------------------------------------------------------
        # Delete
        # ------------------------------------------------------------

        collect_descendants() {
            local root_index="$1"
            local child

            DELETE_INDICES+=("$root_index")

            get_children "${item_id[root_index]}"

            for child in "${CHILDREN[@]}"; do
                collect_descendants "$child"
            done
        }


        delete_item() {
            local index="$1"
            local id="${item_id[index]}"
            local old_parent="${parent_id[index]}"
            local count
            local i

            DELETE_INDICES=()
            collect_descendants "$index"

            count="${#DELETE_INDICES[@]}"

            if (( count > 1 )); then
                if ! whiptail \
                    --title "Delete Heading" \
                    --yesno \
                    "'${item_content[index]}' contains $((count - 1)) child item(s).\n\nDelete the entire subtree?" \
                    12 70; then
                    return
                fi
            else
                if ! whiptail \
                    --title "Delete Item" \
                    --yesno \
                    "Delete '${item_content[index]}'?" \
                    10 60; then
                    return
                fi
            fi

            # Mark items to delete by their IDs.
            declare -A delete_ids=()

            for i in "${DELETE_INDICES[@]}"; do
                delete_ids["${item_id[i]}"]=1
            done

            local -a new_type=()
            local -a new_id=()
            local -a new_parent=()
            local -a new_position=()
            local -a new_status=()
            local -a new_importance=()
            local -a new_content=()
            local -a new_comment=()
            local -a new_effective=()

            for i in "${!item_id[@]}"; do

                if [[ -n "${delete_ids[${item_id[i]}]+x}" ]]; then
                    continue
                fi

                new_type+=("${item_type[i]}")
                new_id+=("${item_id[i]}")
                new_parent+=("${parent_id[i]}")
                new_position+=("${item_position[i]}")
                new_status+=("${item_status[i]}")
                new_importance+=("${item_importance[i]}")
                new_content+=("${item_content[i]}")
                new_comment+=("${item_comment[i]}")
                new_effective+=("${effective_status[i]}")
            done

            item_type=("${new_type[@]}")
            item_id=("${new_id[@]}")
            parent_id=("${new_parent[@]}")
            item_position=("${new_position[@]}")
            item_status=("${new_status[@]}")
            item_importance=("${new_importance[@]}")
            item_content=("${new_content[@]}")
            item_comment=("${new_comment[@]}")
            effective_status=("${new_effective[@]}")

            normalize_positions "$old_parent"

            calculate_all_statuses

            # Avoid unused-variable warning in some shells.
            : "$id"
        }


        # ------------------------------------------------------------
        # Save
        # ------------------------------------------------------------

        save_project() {
            local file="$PROJECT_FILE"
            local tmp="${file}.tmp"
            local i

            calculate_all_statuses

            {
                for i in "${!item_id[@]}"; do

                    # Store EFFECTIVE status.
                    #
                    # This means the saved file always reflects the current
                    # calculated status of container headings.
                    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
                        "${item_type[i]}" \
                        "${item_id[i]}" \
                        "${parent_id[i]}" \
                        "${item_position[i]}" \
                        "${effective_status[i]}" \
                        "${item_importance[i]}" \
                        "${item_content[i]}" \
                        "${item_comment[i]}"
                done
            } > "$tmp" || {
                rm -f "$tmp"
                whiptail \
                    --title "Save Error" \
                    --msgbox "Unable to write temporary project file:\n\n$tmp" \
                    10 70
                return 1
            }

            if ! mv -- "$tmp" "$file"; then
                rm -f "$tmp"
                whiptail \
                    --title "Save Error" \
                    --msgbox "Unable to replace project file:\n\n$file" \
                    10 70
                return 1
            fi

            save_to_projects_db || {
                rm -f "$tmp" "$file"
                whiptail \
                    --title "Save Error" \
                    --msgbox "Unable to save entry to projects database:\n\n$file" \
                    10 70
                return 1            
            }

            return 0
        }


        # ------------------------------------------------------------
        # Tree rendering
        # ------------------------------------------------------------

        status_symbol() {
            case "$1" in
                NS) printf '%s' "○" ;;
                IP) printf '%s' "▶" ;;
                PA) printf '%s' "Ⅱ" ;;
                C)  printf '%s' "✓" ;;
                *)  printf '%s' "?" ;;
            esac
        }


        importance_symbol() {
            case "$1" in
                VI) printf '%s' "!!" ;;
                I)  printf '%s' "!" ;;
                N)  printf '%s' "-" ;;
                NI) printf '%s' "." ;;
                *)  printf '%s' "?" ;;
            esac
        }


        format_item_label() {
            local index="$1"
            local depth="$2"
            local indent=""
            local kind
            local status
            local importance

            for ((j=0; j<depth; j++)); do
                indent+="    "
            done

            status="${effective_status[index]}"
            importance="${item_importance[index]}"

            if [[ "${item_type[index]}" == "H" ]]; then
                kind="◆"
            else
                kind="•"
            fi

            printf '%s%s %s %s %s' \
                "$indent" \
                "$kind" \
                "$(status_symbol "$status")" \
                "$(importance_symbol "$importance")" \
                "${item_content[index]}"
        }


        build_tree_options() {
            TREE_OPTIONS=()

            build_tree_options_from_parent "0"
        }


        build_tree_options_from_parent() {
            local wanted_parent="$1"
            local child
            local depth
            local label

            get_children "$wanted_parent"

            for child in "${CHILDREN[@]}"; do
                depth="$(get_depth "$child")"
                label="$(format_item_label "$child" "$depth")"

                TREE_OPTIONS+=(
                    "${item_id[child]}"
                    "$([[ ${#label} -gt 155 ]] && printf '%s...' "${label:0:157}" || printf '%s' "$label")"
                )

                # Only headings can have children.
                if [[ "${item_type[child]}" == "H" ]]; then
                    build_tree_options_from_parent "${item_id[child]}"
                fi
            done
        }


        render_tree() {
            local selected_id

            build_tree_options

            if (( ${#TREE_OPTIONS[@]} == 0 )); then
                whiptail \
                    --title "Project Goals" \
                    --msgbox "This project contains no goals yet." \
                    8 60
                return 1
            fi

            selected_id="$(
                whiptail \
                    --title "Project Goals" \
                    --cancel-button "Back" \
                    --menu \
                    "Select an item:" \
                    24 110 17 \
                    "${TREE_OPTIONS[@]}" \
                    3>&1 1>&2 2>&3
            )" || return 1

            find_index_by_id "$selected_id"

            if (( RESULT_INDEX < 0 )); then
                return 1
            fi

            ITEM_SELECTED_INDEX=$RESULT_INDEX

            return 0
        }


        # ------------------------------------------------------------
        # Add menu
        # ------------------------------------------------------------

        add_menu() {
            local destination

            destination="$(
                whiptail \
                    --title "Add" \
                    --menu \
                    "What would you like to add?" \
                    12 60 4 \
                    "H" "Heading" \
                    "T" "Task" \
                    3>&1 1>&2 2>&3
            )" || return

            if [[ "$destination" == "H" ]]; then
                add_heading "0"
                return
            fi

            if [[ "$destination" == "T" ]]; then
                # A task needs a heading.
                select_heading_for_parent "0" || return
                add_task "$SELECTED_HEADING_ID"
            fi
        }

        select_heading_for_parent() {
            local parent="$1"

            HEADING_OPTIONS=()

            build_heading_options_from_parent "$parent"

            (( ${#HEADING_OPTIONS[@]} == 0 )) && {
                whiptail \
                    --title "No Headings" \
                    --msgbox "There are no headings available here." \
                    8 60
                return 1
            }

            SELECTED_HEADING_ID="$(
                whiptail \
                    --title "Select Heading" \
                    --menu \
                    "Select the heading:" \
                    22 90 15 \
                    "${HEADING_OPTIONS[@]}" \
                    3>&1 1>&2 2>&3
            )" || return 1

            return 0
        }

        build_heading_options_from_parent() {
            local wanted_parent="$1"
            local child
            local depth
            local label

            get_children "$wanted_parent"

            for child in "${CHILDREN[@]}"; do

                [[ "${item_type[child]}" == "H" ]] || continue

                depth="$(get_depth "$child")"
                label="$(format_item_label "$child" "$depth")"

                HEADING_OPTIONS+=(
                    "${item_id[child]}"
                    "$label"
                )

                build_heading_options_from_parent "${item_id[child]}"
            done
        }

        # -------------------------------------------------------------
        # Sort children  based on item's numerical prefix.
        # eg. 1) heading or 1. task
        # Sorts parent's immediate children either headings or tasks.
        # -------------------------------------------------------------

        # Return the numeric prefix from an item's content.
        #
        # Examples:
        #   "1. Heading one"  -> 1
        #   "3) Heading three" -> 3
        #   "10. Task ten"    -> 10
        #
        # Returns failure if there is no valid numeric prefix.
        get_number_prefix() {
            local content="$1"

            if [[ "$content" =~ ^([0-9]+)[.\)][[:space:]]+ ]]; then
                printf '%s\n' "${BASH_REMATCH[1]}"
                return 0
            fi

            return 1
        }


        has_number_prefix() {
            local content="$1"

            [[ "$content" =~ ^[0-9]+[.\)][[:space:]]+ ]]
        }


        sort_numbered_items() {
            local -n items="$1"

            local item
            local number
            local sorted=()
            local entries=()

            for item in "${items[@]}"; do
                number="$(get_number_prefix "${item_content[item]}")" || continue

                # Include the original item index after the number.
                entries+=("$number"$'\t'"$item")
            done

            # Numeric sort by the first field.
            #
            # sort -n is stable on GNU coreutils when --stable is specified.
            if ((${#entries[@]})); then
                mapfile -t entries < <(
                    printf '%s\n' "${entries[@]}" |
                        sort -n -k1,1 -s
                )
            fi

            for entry in "${entries[@]}"; do
                sorted+=("${entry#*$'\t'}")
            done

            items=("${sorted[@]}")
        }


        sort_children() {
            local children
            local todo_heading=()
            local rules_for_today_heading=()
            local numbered_headings=()
            local unnumbered_headings=()
            local numbered_tasks=()
            local unnumbered_tasks=()

            get_children "$1"   # arg is item id NOT index.
            children=("${CHILDREN[@]}")

            for child in "${children[@]}"; do
                case "${item_type[child]}" in
                    H)
                        # TODO is always first when it is a root-level heading.
                        if [[ "$1" == "0" &&
                            "${item_content[child]}" == "TODO" ]]; then
                            todo_heading+=("$child")
                        elif [[ "$1" == "0" &&
                                "${item_content[child]}" == "RULES FOR TODAY" ]]; then

                            rules_for_today_heading+=("$child")                            
                        elif has_number_prefix "${item_content[child]}"; then
                            numbered_headings+=("$child")
                        else
                            unnumbered_headings+=("$child")
                        fi
                        ;;

                    T)
                        if has_number_prefix "${item_content[child]}"; then
                            numbered_tasks+=("$child")
                        else
                            unnumbered_tasks+=("$child")
                        fi
                        ;;
                esac
            done

            sort_numbered_items numbered_headings
            sort_numbered_items numbered_tasks

            children=(
                "${todo_heading[@]}"
                "${rules_for_today_heading[@]}"
                "${numbered_headings[@]}"
                "${unnumbered_headings[@]}"
                "${numbered_tasks[@]}"
                "${unnumbered_tasks[@]}"
            )

            # Update global 0-based positions.
            for position in "${!children[@]}"; do
                item_position[children[position]]="$position"
            done
        }

        # ------------------------------------------------------------
        # Item action menu
        # ------------------------------------------------------------

        item_menu() {
            local index="$1"
            local action
            local type="${item_type[index]}"

            while :; do

                if [[ "$type" == "H" ]]; then

                    action="$(
                        whiptail \
                            --title "${item_content[index]}" \
                            --cancel-button "Back" \
                            --menu \
                            "Status: $(status_name "${effective_status[index]}")\nImportance: $(importance_name "${item_importance[index]}")" \
                            24 80 12 \
                            "TEXT" "Change text" \
                            "STATUS" "Change status" \
                            "IMPORTANCE" "Change importance" \
                            "COMMENT" "Add / edit comment" \
                            "VIEW_COMMENT" "View comment" \
                            "ADD_H" "Add heading" \
                            "ADD_T" "Add task" \
                            "MOVE" "Move" \
                            "SORT" "Sort children by number prefix" \
                            "DELETE" "Delete" \
                            "BACK" "Back" \
                            3>&1 1>&2 2>&3
                    )" || return

                else

                    action="$(
                        whiptail \
                            --title "${item_content[index]}" \
                            --cancel-button "Back" \
                            --menu \
                            "Status: $(status_name "${effective_status[index]}")\nImportance: $(importance_name "${item_importance[index]}")" \
                            20 75 8 \
                            "TEXT" "Change task / plan" \
                            "STATUS" "Change status" \
                            "IMPORTANCE" "Change importance" \
                            "COMMENT" "Add / edit comment" \
                            "VIEW_COMMENT" "View comment" \
                            "MOVE" "Move" \
                            "DELETE" "Delete" \
                            "BACK" "Back" \
                            3>&1 1>&2 2>&3
                    )" || return

                fi

                case "$action" in

                    TEXT)
                        if [[ "$type" == "T" ]]; then
                            edit_task "$index"
                        else
                            edit_text "$index"
                        fi
                        ;;

                    STATUS)
                        change_status "$index"
                        ;;

                    IMPORTANCE)
                        change_importance "$index"
                        ;;

                    COMMENT)
                        edit_comment "$index"
                        ;;

                    VIEW_COMMENT)
                        view_comment "$index"
                        ;;

                    ADD_H)
                        add_heading "${item_id[index]}"
                        ;;

                    ADD_T)
                        add_task "${item_id[index]}"
                        ;;

                    MOVE)
                        #move_item "$index"
                        move_item_menu "$index"

                        # The arrays may have changed but this item itself
                        # still exists, so locate it again.
                        find_index_by_id "${item_id[index]}"
                        (( RESULT_INDEX >= 0 )) && index=$RESULT_INDEX
                        ;;

                    SORT)
                        sort_children "${item_id[index]}"
                        ;;

                    DELETE)
                        local deleted_id="${item_id[index]}"

                        delete_item "$index"

                        find_index_by_id "$deleted_id"

                        if (( RESULT_INDEX < 0 )); then
                            return
                        fi

                        index=$RESULT_INDEX
                        type="${item_type[index]}"
                        ;;

                    BACK)
                        return
                        ;;
                esac

                calculate_all_statuses
            done
        }


        change_status() {
            local index="$1"
            local new_status

            # Container headings are derived from their children.
            if [[ "${item_type[index]}" == "H" ]] && is_container "$index"; then

                new_status="$(
                    whiptail \
                        --title "Container Heading" \
                        --menu \
                        "'${item_content[index]}' is a container heading.\n\nSelect an operation:" \
                        16 75 5 \
                        "C" "Complete entire goal" \
                        "PA" "Pause unfinished descendants" \
                        "RESET" "Reset descendants to not started" \
                        3>&1 1>&2 2>&3
                )" || return

                case "$new_status" in
                    C)
                        set_subtree_status "$index" "C"
                        ;;

                    PA)
                        set_unfinished_subtree_status "$index" "PA"
                        ;;

                    RESET)
                        set_subtree_status "$index" "NS"
                        ;;
                esac

                calculate_all_statuses
                return
            fi

            new_status="$(select_status "${item_status[index]}")" || return

            item_status[index]="$new_status"

            calculate_all_statuses
        }


        change_importance() {
            local index="$1"
            local new_importance

            new_importance="$(
                select_importance "${item_importance[index]}"
            )" || return

            item_importance[index]="$new_importance"
        }


        set_subtree_status() {
            local root_index="$1"
            local new_status="$2"
            local child

            item_status[root_index]="$new_status"

            get_children "${item_id[root_index]}"

            for child in "${CHILDREN[@]}"; do
                set_subtree_status "$child" "$new_status"
            done
        }


        set_unfinished_subtree_status() {
            local root_index="$1"
            local child

            if [[ "${effective_status[root_index]}" != "C" ]]; then
                item_status[root_index]="PA"
            fi

            get_children "${item_id[root_index]}"

            for child in "${CHILDREN[@]}"; do
                set_unfinished_subtree_status "$child"
            done
        }


        # ------------------------------------------------------------
        # Main project UI
        # ------------------------------------------------------------

        project_menu() {
            local choice
            local project_file_tr="${PROJECT_FILE:0:80}"
            (( ${#PROJECT_FILE} > 80 )) && project_file_tr+="..."

            local tree_page=0
            local tree_page_size=25   # tree items per page            

            # Remember the saved state so Back can detect unsaved changes.
            local PROJECT_SAVED_SIG
            sort_children "0"
            calculate_all_statuses
            PROJECT_SAVED_SIG="$(project_state_sig)"

            while :; do

                sort_children "0"
                calculate_all_statuses
                build_tree_options

                # --- paginate TREE_OPTIONS ---
                local tree_total=$(( ${#TREE_OPTIONS[@]} / 2 ))
                local tree_pages=$(( (tree_total + tree_page_size - 1) / tree_page_size ))
                (( tree_pages == 0 )) && tree_pages=1
                (( tree_page >= tree_pages )) && tree_page=$(( tree_pages - 1 ))
                (( tree_page < 0 )) && tree_page=0
                local tree_start=$(( tree_page * tree_page_size * 2 ))
                local tree_chunk=("${TREE_OPTIONS[@]:tree_start:tree_page_size*2}")

                # static action rows first
                local menu_items=(
                    "SYMBOLS" "Help"
                    "ADD_H" "Add top-level heading"
                    "ADD_T" "Add task"
                    "ADD_TODO" "Add TODO item"
                    "ADD_RULES" "Add RULES FOR TODAY item"                 
                    "SORT" "Sort root's children by number prefix"
                    "SAVE" "Save changes"
                    "REVERT" "Discard changes and reload from disk"
                    "---" "PROJECT TREE BELOW ---"
                    "" ""
                )

                # navigation rows (only when applicable)
                (( tree_page > 0 )) && menu_items+=("__prev__" "<< Previous page")
                (( tree_page < tree_pages - 1 )) && menu_items+=("__next__" "Next page >>")

                # then the current page of tree items
                menu_items+=("${tree_chunk[@]}")

                choice="$(
                    whiptail \
                        --title "Manage Goals" \
                        --cancel-button "Back" \
                        --menu \
                        "Project: $project_file_tr (Page $((tree_page + 1))/$tree_pages)" \
                        45 180 37 \
                        -- \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3
                )" || { project_confirm_leave && break; continue; }

                case "$choice" in
                    SYMBOLS)
                        whiptail \
                            --title "Symbol Help" \
                            --msgbox "$(print_symbol_help)" \
                            20 80                
                        ;;

                    __prev__)
                        (( tree_page > 0 )) && (( tree_page-- ))
                        continue
                        ;;
                    __next__)
                        (( tree_page < tree_pages - 1 )) && (( tree_page++ ))
                        continue
                        ;;                        

                    "---"|"")
                        continue
                        ;;

                    ADD_H)
                        add_heading "0"
                        ;;

                    ADD_T)
                        if select_heading_for_parent "0"; then
                            add_task "$SELECTED_HEADING_ID"
                        fi
                        ;;

                    ADD_RULES)
                        add_rules_for_today_item
                        ;;                    

                    ADD_TODO)
                        add_todo_item
                        ;;                    

                    SORT)
                        sort_children "0"
                        ;;

                    SAVE)
                        if save_project; then
                            PROJECT_SAVED_SIG="$(project_state_sig)"
                            whiptail \
                                --title "Saved" \
                                --msgbox "Project saved successfully." \
                                8 50
                        fi
                        ;;

                    REVERT)
                        if whiptail \
                            --title "Revert Project" \
                            --yesno \
                            "Discard unsaved changes and reload the project from disk?" \
                            10 70; then

                            if load_project "$PROJECT_FILE"; then
                                sort_children "0"
                                calculate_all_statuses
                                PROJECT_SAVED_SIG="$(project_state_sig)"
                                whiptail \
                                    --title "Reverted" \
                                    --msgbox "Unsaved changes discarded; project reloaded." \
                                    8 50
                            fi
                        fi
                        ;;

                    *)
                        # Tree entries use their persistent item ID as the menu tag.
                        find_index_by_id "$choice"
                        if (( RESULT_INDEX >= 0 )); then
                            item_menu "$RESULT_INDEX"
                        fi
                        ;;
                esac
            done
        }

        # ------------------------------------------------------------
        # Start
        # ------------------------------------------------------------

        if ! command -v whiptail >/dev/null 2>&1; then
            printf 'Error: whiptail is not installed.\n' >&2
            exit 1
        fi

        if ! load_project "$PROJECT_FILE"; then
            return 1
        fi

        project_menu    
    }

    truncate_note_tags_by_tag() {
        local tags="$1"
        local inner
        local -a tag_array
        local count
        local extra

        # Remove surrounding [ ]
        inner="${tags#[}"
        inner="${inner%]}"

        # Empty list
        if [[ -z "$inner" ]]; then
            printf '[]\n'
            return
        fi

        # Split on commas
        IFS=',' read -r -a tag_array <<< "$inner"

        count=${#tag_array[@]}

        if (( count <= 3 )); then
            printf '[%s]\n' "$inner"
            return
        fi

        extra=$((count - 3))

        printf '[%s,%s,%s +%d]\n' \
            "${tag_array[0]}" \
            "${tag_array[1]}" \
            "${tag_array[2]}" \
            "$extra"
    }

    # Select Project: rows show project titles. __APPLY_GLOB__ matches project
    # titles and __RESET_GLOB__ clears the glob (no glob is asked up front).
    local -a projects=()
    GOALS_PROJECT_GLOB=""
    local GOALS_PROJECT_TITLE_MODE=1
    goals_select_project "Select Project" || return 1
    GOALS_PROJECT_TITLE_MODE=""
    local selected_project_tag="$GOALS_SELECTED_PROJECT_LINENO"
    mapfile -t projects < "$PROJECTS_DB"

    local selected_project_path
    local note_lines=()
    local note_menu_options=()

    # MOVED OUT OF WHILE LOOP!!!
    refresh_all_linked_notes() {
        mapfile -t projects < "$PROJECTS_DB"    # Reload from PROJECTS DB file.
        local selected_project_index=$((selected_project_tag - 1))
        local selected_project_line="${projects[$selected_project_index]}"

        local associated_notes
        IFS='|' read -r selected_project_title selected_project_path associated_notes <<< "$selected_project_line"

        # Process associated notes
        local note_paths=()
        IFS=',' read -ra note_paths <<< "$associated_notes"
        note_lines=()
        note_menu_options=()

        # Filters first, then the actions.
        note_menu_options+=("__FILTER_BY_TAG__" "Filter linked notes by tag")
        note_menu_options+=("__RESET_FILTER__" "Reset the tag filter")
        note_menu_options+=("__APPLY_GLOB__" "Apply glob (matches note titles)")
        note_menu_options+=("__RESET_GLOB__" "Reset the title glob")
        note_menu_options+=("Manage plan" "")
        note_menu_options+=("Create new note tag" "")
        note_menu_options+=("Create new linked note" "")
        note_menu_options+=("Open ebook" "")
        note_menu_options+=("Open URL" "")
        note_menu_options+=("Link note" "")
        note_menu_options+=("Unlink note" "")
        note_menu_options+=("Add tag to linked notes" "")
        note_menu_options+=("Remove tag from linked notes" "")

        local trunc_tag

        # First collect all matching note lines.
        for np in "${note_paths[@]}"; do
            while IFS= read -r line; do
                IFS='|' read -r title path tags _ <<< "$line"

                if [ "$path" = "$np" ]; then
                    note_lines+=("$line")
                    break
                fi
            done < "$NOTES_DB"
        done

        # Sort note_lines alphabetically by title--guarded.
        if ((${#note_lines[@]} > 0)); then
            mapfile -t note_lines < <(
                printf '%s\n' "${note_lines[@]}" |
                sort -t'|' -k1,1f
            )
        fi

        # Build menu options in the exact same order as note_lines.
        for i in "${!note_lines[@]}"; do
            IFS='|' read -r title path tags _ <<< "${note_lines[$i]}"

            trunc_tag="$(truncate_note_tags_by_tag "[${tags}]")"

            note_menu_options+=("$((i + 1))" "$title $trunc_tag")
        done

        # Refresh code end.
    }

    #-- Helpers for refresh_filtered_linked_notes()
    retrieve_linked_notes() {
        local selected_project_path="$1"
        local project_line
        local project_title
        local project_path
        local linked_notes
        local note_path

        # Find the project line whose second field matches the selected path
        while IFS= read -r project_line; do
            IFS='|' read -r project_title project_path linked_notes <<< "$project_line"

            if [[ "$project_path" == "$selected_project_path" ]]; then
                break
            fi

            linked_notes=""
        done < "$PROJECTS_DB"

        # No matching project or no linked notes
        [[ -z "$linked_notes" ]] && return 0

        # Extract each comma-separated note path
        local IFS=','
        read -r -a note_paths <<< "$linked_notes"

        # Find and print each corresponding line from NOTES_DB
        for note_path in "${note_paths[@]}"; do
            while IFS= read -r note_line; do
                IFS='|' read -r note_title note_db_path note_tags note_rest <<< "$note_line"

                if [[ "$note_db_path" == "$note_path" ]]; then
                    printf '%s\n' "$note_line"
                    break
                fi
            done < "$NOTES_DB"
        done
    }

    filter_linked_notes_by_tag() {
        local selected_tag="$1"
        shift

        local line
        local title
        local note_path
        local note_tags
        local rest
        local current_tag

        for line in "$@"; do
            IFS='|' read -r title note_path note_tags rest <<< "$line"

            # NEW: 'NO TAG' sentinel matches linked notes with an empty tag field.
            if [[ "$selected_tag" == "[NO TAG]" ]]; then
                [[ -z "$note_tags" ]] && printf '%s\n' "$line"
                continue
            fi

            IFS=',' read -ra tag_array <<< "$note_tags"

            for current_tag in "${tag_array[@]}"; do
                if [[ "$current_tag" == "$selected_tag" ]]; then
                    printf '%s\n' "$line"
                    break
                fi
            done
        done
    }    
    #-- Helpers end.

    # Apply a Bash glob to the note title (case-insensitive). The glob matches
    # the whole title, so use *text* for a contains-style match.
    filter_linked_notes_by_glob() {
        local pattern="$1"
        shift

        local line title lower_pattern="${pattern,,}"
        for line in "$@"; do
            IFS='|' read -r title _ _ _ <<< "$line"
            # Keep the right-hand pattern unquoted so Bash interprets glob syntax.
            if [[ "${title,,}" == $lower_pattern ]]; then
                printf '%s\n' "$line"
            fi
        done
    }

    local TAG_FILTER_BY=""
    local GLOB_FILTER_BY=""

    # Return linked notes after applying both active filters. This helper is
    # shared by the menu and all actions that operate on the visible note list.
    get_current_filtered_linked_notes() {
        local -a current_notes=()
        mapfile -t current_notes < <(
            retrieve_linked_notes "$selected_project_path"
        )

        if [[ -n "$TAG_FILTER_BY" && "$TAG_FILTER_BY" != "[ANY TAG]" ]]; then
            mapfile -t current_notes < <(
                filter_linked_notes_by_tag "$TAG_FILTER_BY" "${current_notes[@]}"
            )
        fi

        if [[ -n "$GLOB_FILTER_BY" ]]; then
            mapfile -t current_notes < <(
                filter_linked_notes_by_glob "$GLOB_FILTER_BY" "${current_notes[@]}"
            )
        fi

        ((${#current_notes[@]} > 0)) && printf '%s\n' "${current_notes[@]}"
    }

    # Get notes matching the glob without applying the current tag filter. This
    # lets the user change the tag filter while the glob remains in force.
    get_linked_notes_matching_glob() {
        local -a current_notes=()
        mapfile -t current_notes < <(
            retrieve_linked_notes "$selected_project_path"
        )

        if [[ -n "$GLOB_FILTER_BY" ]]; then
            mapfile -t current_notes < <(
                filter_linked_notes_by_glob "$GLOB_FILTER_BY" "${current_notes[@]}"
            )
        fi

        ((${#current_notes[@]} > 0)) && printf '%s\n' "${current_notes[@]}"
    }

    refresh_filtered_linked_notes() {
        local line title path tags trunc_tag
        local -a filtered_linked_notes=()

        mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)

        # Keep the visible list alphabetically sorted by title.
        if ((${#filtered_linked_notes[@]} > 0)); then
            mapfile -t filtered_linked_notes < <(
                printf '%s\n' "${filtered_linked_notes[@]}" |
                sort -t'|' -k1,1f
            )
        fi

        note_lines=()
        note_menu_options=()
        LINKED_NOTES_TOTAL=$(retrieve_linked_notes "$selected_project_path" | grep -c .)

        # Filters first, then the actions.
        note_menu_options+=("__FILTER_BY_TAG__" "Filter linked notes by tag")
        note_menu_options+=("__RESET_FILTER__" "Reset the tag filter")
        note_menu_options+=("__APPLY_GLOB__" "Apply glob (matches note titles)")
        note_menu_options+=("__RESET_GLOB__" "Reset the title glob")
        note_menu_options+=("Manage plan" "")
        note_menu_options+=("Create new note tag" "")
        note_menu_options+=("Create new linked note" "")
        note_menu_options+=("Open ebook" "")
        note_menu_options+=("Open URL" "")
        note_menu_options+=("Link note" "")
        note_menu_options+=("Unlink note" "")
        note_menu_options+=("Add tag to linked notes" "")
        note_menu_options+=("Remove tag from linked notes" "")

        for line in "${filtered_linked_notes[@]}"; do
            [[ -z "$line" ]] && continue
            IFS='|' read -r title path tags _ <<< "$line"
            note_lines+=("$line")
            trunc_tag="$(truncate_note_tags_by_tag "[${tags}]")"
            note_menu_options+=("${#note_lines[@]}" "$title $trunc_tag")
        done
    }

    refresh_all_linked_notes

    # FIX: WHILE LOOP TO ALLOW MULTIPLE LINKED NOTE SELECTIONS
    while :; do
        refresh_filtered_linked_notes

        paginate_tags_menu() {
            local title="$1"
            shift
            local items=("$@")
            local per_page=20
            local total_items=$(( ${#items[@]} / 2 ))
            local total_pages=$(( (total_items + per_page - 1) / per_page ))
            local current_page=1
            local choice start_index end_index menu_items tag desc

            while true; do
                # Calculate start and end indices for current page
                start_index=$(( (current_page - 1) * per_page * 2 ))
                end_index=$(( start_index + per_page * 2 ))
                menu_items=()

                # Add items for current page
                for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                    tag="${items[i]}"
                    desc="${items[i+1]}"
                    menu_items+=("$tag" "$desc")
                done

                # Add navigation options
                if (( current_page > 1 )); then
                    menu_items+=("<< Prev" "")
                fi
                if (( current_page < total_pages )); then
                    menu_items+=(">> Next" "")
                fi

                # Show whiptail menu
                choice=$(whiptail --title "$title" \
                    --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                    "${menu_items[@]}" 3>&1 1>&2 2>&3)

                [[ $? -ne 0 ]] && return 1  # Cancel pressed

                case "$choice" in
                    ">> Next")
                        (( current_page++ ))
                        ;;
                    "<< Prev")
                        (( current_page-- ))
                        ;;
                    *)
                        # Return selected tag
                        printf '%s\n' "$choice"
                        return 0
                        ;;
                esac
            done
        }

        choose_tag_goal() {
            # Choose Tag: [NO TAG] creates the note without a tag. __FILTER__
            # narrows the tag list by a literal substring; __RESET_FILTER__ clears it.
            goals_select_note_tag_filter --title "Choose Tag" \
                --prompt "Choose a tag for the new linked note" --pins "NO" \
                --no-tag-desc "Create the note without any tag" || return 1
            printf '%s' "$GOALS_SELECTED_NOTE_TAG"
        }

        add_tag_to_notes_from_filtered() {
            whiptail --title "Attention" --msgbox \
"Step 1: Select tag to add.
Step 2: Select multiple notes to add the tag to.

Tag you have chosen will be added to the selected notes." 10 60
            local notes_db="${NOTES_DB:-}"
            local tags_db="${NOTES_TAGS_DB:-}"
            local page_size="${PAGE_SIZE:-30}"

            if [[ -z $notes_db || ! -r $notes_db || ! -w $notes_db ]]; then
                printf 'ERROR: NOTES_DB must be set and writable: %s\n' "${notes_db:-<unset>}" >&2
                return 1
            fi

            if [[ -z $tags_db || ! -r $tags_db ]]; then
                printf 'ERROR: NOTES_TAGS_DB must be set and readable: %s\n' "${tags_db:-<unset>}" >&2
                return 1
            fi

            if ! command -v whiptail >/dev/null 2>&1; then
                printf 'ERROR: whiptail is not installed.\n' >&2
                return 1
            fi

            if [[ $# -eq 0 ]]; then
                printf 'ERROR: pass filtered note lines as arguments.\n' >&2
                return 1
            fi

            local -a all_notes=("$@")
            local total="${#all_notes[@]}"

            (( total == 0 )) && {
                whiptail --msgbox "No filtered notes found. Add a note and try again." 8 50
                return 1
            }

            local page_count=$(( (total + page_size - 1) / page_size ))

            local tmp_sel=""
            local tmp_db=""
            trap 'rm -f -- "$tmp_sel" "$tmp_db"' RETURN

            local -a tag_menu=()
            local tag
            while IFS= read -r tag || [[ -n $tag ]]; do
                [[ -n $tag ]] || continue
                tag_menu+=("$tag" "")
            done < "$tags_db"

            if (( ${#tag_menu[@]} == 0 )); then
                whiptail --msgbox "No note tags found. Add a tag and try again." 8 50
                return 1
            fi

            local selected_tag
            # Select tag: __FILTER__ narrows the tag list by a literal substring,
            # __RESET_FILTER__ clears it.
            local -a tag_list=()
            local tk
            for (( tk = 0; tk < ${#tag_menu[@]}; tk += 2 )); do
                tag_list+=("${tag_menu[tk]}")
            done
            goals_select_note_tag_filter --title "Select tag" \
                --prompt "Choose the tag to add to the notes" --pins "" \
                --tags "${tag_list[@]}" || return 1
            selected_tag="$GOALS_SELECTED_NOTE_TAG"

            # Select notes: full note paths with their tags.
            local -a all_paths=()
            local ln_ ln_path_
            for ln_ in "${all_notes[@]}"; do
                IFS='|' read -r _ ln_path_ _ <<< "$ln_"
                [[ -n "$ln_path_" ]] && all_paths+=("$ln_path_")
            done

            GOALS_NOTE_GLOB=""
            GOALS_NOTE_TAGFILTER=""
            local -A selected_paths=()
            local sp_
            while :; do
                goals_pick_notes_multi "Select notes" "Tag to add: $selected_tag" \
                    "__add_tag__" "Add tag to selected notes" top \
                    "${all_paths[@]}" || return 1

                selected_paths=()
                for sp_ in "${GOALS_PICKED_PATHS[@]}"; do selected_paths["$sp_"]=1; done

                local selected_count="${#selected_paths[@]}"

                if ! whiptail --title "Confirm" \
                    --yesno "Add tag \"$selected_tag\" to $selected_count selected note(s)?" \
                    10 70; then
                    continue
                fi

                    tmp_sel=$(mktemp "${TMPDIR:-/tmp}/notes_sel.XXXXXX") || return 1
                    tmp_db=$(mktemp "${notes_db}.XXXXXX") || { rm -f -- "$tmp_sel"; return 1; }

                    {
                        local p
                        for p in "${!selected_paths[@]}"; do
                            printf '%s\n' "$p"
                        done
                    } > "$tmp_sel"

                    awk -F'|' -v OFS='|' -v tag="$selected_tag" -v selfile="$tmp_sel" '
                        BEGIN {
                            while ((getline p < selfile) > 0) sel[p] = 1
                            close(selfile)
                        }

                        function has_tag(tags, tag,   n, a, i) {
                            if (tags == "") return 0
                            n = split(tags, a, /,/)
                            for (i = 1; i <= n; i++) {
                                if (a[i] == tag) return 1
                            }
                            return 0
                        }

                        function append_tag(tags, tag,   n, a, i, out) {
                            if (tags == "") return tag
                            n = split(tags, a, /,/)
                            out = ""
                            for (i = 1; i <= n; i++) {
                                if (a[i] == "" || a[i] == tag) continue
                                out = (out == "" ? a[i] : out "," a[i])
                            }
                            return (out == "" ? tag : out "," tag)
                        }

                        {
                            if (sel[$2] && !has_tag($3, tag)) {
                                $3 = append_tag($3, tag)
                            }
                            print
                        }
                    ' "$notes_db" > "$tmp_db" || { rm -f -- "$tmp_sel" "$tmp_db"; return 1; }

                    mv -- "$tmp_db" "$notes_db" || { rm -f -- "$tmp_sel" "$tmp_db"; return 1; }
                    rm -f -- "$tmp_sel"
                    tmp_sel=""

                    whiptail --msgbox "Tag \"$selected_tag\" added to selected notes." 8 60
                    return 0
            done
        }

        retrieve_linked_notes() {
            local selected_project_path="$1"
            local project_line
            local project_title
            local project_path
            local linked_notes
            local note_path

            # Find the project line whose second field matches the selected path
            while IFS= read -r project_line; do
                IFS='|' read -r project_title project_path linked_notes <<< "$project_line"

                if [[ "$project_path" == "$selected_project_path" ]]; then
                    break
                fi

                linked_notes=""
            done < "$PROJECTS_DB"

            # No matching project or no linked notes
            [[ -z "$linked_notes" ]] && return 0

            # Extract each comma-separated note path
            local IFS=','
            read -r -a note_paths <<< "$linked_notes"

            # Find and print each corresponding line from NOTES_DB
            for note_path in "${note_paths[@]}"; do
                while IFS= read -r note_line; do
                    IFS='|' read -r note_title note_db_path note_tags note_rest <<< "$note_line"

                    if [[ "$note_db_path" == "$note_path" ]]; then
                        printf '%s\n' "$note_line"
                        break
                    fi
                done < "$NOTES_DB"
            done
        }

        retrieve_linked_note_tags() {
            local line
            local tags
            local tag

            declare -A seen_tags=()

            for line in "$@"; do
                # Extract the third field (tags)
                IFS='|' read -r _ _ tags _ <<< "$line"

                # Extract comma-separated tags
                local IFS=','
                read -r -a tag_array <<< "$tags"

                for tag in "${tag_array[@]}"; do
                    [[ -z "$tag" ]] && continue
                    seen_tags["$tag"]=1
                done
            done

            # Print unique tags alphabetically
            printf '%s\n' "${!seen_tags[@]}" | sort
        }

        remove_linked_note_tag() {
            local tag="$1"
            shift

            local matched_line
            local title
            local note_path
            local note_tags
            local rest
            local new_tags
            local current_tag
            local found

            # Nothing to process
            [[ $# -eq 0 ]] && return 0

            # Create a temporary file
            local temp_file
            temp_file=$(mktemp) || return 1

            while IFS= read -r line; do
                local should_update=false

                # Check whether this line is one of the matched lines
                for matched_line in "$@"; do
                    if [[ "$line" == "$matched_line" ]]; then
                        should_update=true
                        break
                    fi
                done

                if [[ "$should_update" == true ]]; then
                    # NOTES_DB:
                    # note title|note path|tag1,tag2|rest
                    IFS='|' read -r title note_path note_tags rest <<< "$line"

                    new_tags=""

                    # Remove the requested tag
                    local old_ifs="$IFS"
                    IFS=','
                    read -r -a tag_array <<< "$note_tags"
                    IFS="$old_ifs"

                    for current_tag in "${tag_array[@]}"; do
                        [[ "$current_tag" == "$tag" ]] && continue

                        if [[ -z "$new_tags" ]]; then
                            new_tags="$current_tag"
                        else
                            new_tags+=",$current_tag"
                        fi
                    done

                    # Reconstruct the line
                    printf '%s|%s|%s|%s\n' \
                        "$title" \
                        "$note_path" \
                        "$new_tags" \
                        "$rest"
                else
                    # Leave all other lines unchanged
                    printf '%s\n' "$line"
                fi
            done < "$NOTES_DB" > "$temp_file"

            # Replace the original database
            mv "$temp_file" "$NOTES_DB"
        }

        filter_linked_notes_by_tag() {
            local selected_tag="$1"
            shift

            local line
            local title
            local note_path
            local note_tags
            local rest
            local current_tag

            for line in "$@"; do
                IFS='|' read -r title note_path note_tags rest <<< "$line"

                # NEW: 'NO TAG' sentinel matches linked notes with an empty tag field.
                if [[ "$selected_tag" == "[NO TAG]" ]]; then
                    [[ -z "$note_tags" ]] && printf '%s\n' "$line"
                    continue
                fi

                IFS=',' read -ra tag_array <<< "$note_tags"

                for current_tag in "${tag_array[@]}"; do
                    if [[ "$current_tag" == "$selected_tag" ]]; then
                        printf '%s\n' "$line"
                        break
                    fi
                done
            done
        }

        add_note_tag_stuff() {
            local subject=""
            local topic=""
            local tag_name=""
            local choice

            while true; do
                # Construct tag name
                if [[ -n "$subject" && -n "$topic" ]]; then
                    tag_name="${subject}->${topic}"
                else
                    tag_name="$subject"
                fi

                # Silently remove banned characters
                tag_name="${tag_name//[|,#:;]/}"

                choice=$(
                    whiptail \
                        --title "Add Note Tag" \
                        --menu "Create a new tag (formatted 'subject->topic'):" \
                        18 70 8 \
                        "Subject" "${subject:-<not set>}" \
                        "Topic" "${topic:-<not set>}" \
                        "Tag Name" "'${tag_name}'" \
                        "Save" "" \
                        3>&1 1>&2 2>&3
                ) || return 1

                case "$choice" in
                    Subject)
                        subject=$(
                            whiptail \
                                --title "Subject" \
                                --inputbox "Enter subject:" \
                                10 60 "$subject" \
                                3>&1 1>&2 2>&3
                        ) || continue
                        ;;

                    Topic)
                        topic=$(
                            whiptail \
                                --title "Topic" \
                                --inputbox "Enter topic (optional):" \
                                10 60 "$topic" \
                                3>&1 1>&2 2>&3
                        ) || continue
                        ;;

                    Save)
                        # Reconstruct again to ensure latest values
                        if [[ -n "$subject" && -n "$topic" ]]; then
                            tag_name="${subject}->${topic}"
                        else
                            tag_name="$subject"
                        fi

                        # Remove banned characters
                        tag_name="${tag_name//[|,#:;]/}"

                        # Trim whitespace
                        tag_name="$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$tag_name")"

                        if [[ -z "$tag_name" ]]; then
                            whiptail \
                                --title "Error" \
                                --msgbox "Tag Name cannot be empty." \
                                8 40
                            continue
                        fi

                        if [[ "$tag_name" == "ANY TAG" ]]; then
                            whiptail \
                                --title "Error" \
                                --msgbox "'ANY TAG' is a reserved tag name." \
                                8 45
                            continue
                        fi

                        if grep -Fxq -- "$tag_name" "$NOTES_TAGS_DB"; then
                            whiptail \
                                --title "Duplicate" \
                                --msgbox "Tag already exists." \
                                8 40
                            continue
                        fi

                        {
                            cat "$NOTES_TAGS_DB"
                            printf '%s\n' "$tag_name"
                        } | sort -u > "${NOTES_TAGS_DB}.tmp" &&
                            mv "${NOTES_TAGS_DB}.tmp" "$NOTES_TAGS_DB"

                        whiptail \
                            --title "Success" \
                            --msgbox "Tag added:\n\n$tag_name" \
                            10 50

                        return 0
                        ;;
                esac
            done
        }

        open_urls_filtered() {
            # Control characters:
            #   Ctrl-] = ^] = Group Separator
            #   Ctrl-^ = ^^ = Record Separator
            #   Ctrl-_ = ^_ = Unit Separator
            local CTRL_GS=$'\035'
            local CTRL_RS=$'\036'
            local CTRL_US=$'\037'

            _spawn() {
                nohup "$@" >/dev/null 2>&1 </dev/null &
            }

            _dialog_msg() {
                local message=$1
                local height=${2:-10}
                local width=${3:-60}

                whiptail --msgbox "$message" "$height" "$width" \
                    3>&1 1>&2 2>&3
            }

            if (($# == 0)); then
                _dialog_msg "No note records were supplied." 10 55
                return 1
            fi

            if [[ ! -r ${URLS_DB:?URLS_DB is not set} ]]; then
                _dialog_msg "URLS_DB is not readable: $URLS_DB" 10 65
                return 1
            fi

            local line note_path dbline record
            local title entry url description
            local selected_note selected_url
            local id=1

            local -a note_items=()
            local -a url_note_paths=()
            local -a url_items=()

            local -A note_path_by_id=()
            local -A url_by_id=()

            # ------------------------------------------------------------
            # Build menu of linked notes that have at least one URL.
            # ------------------------------------------------------------

            for line in "$@"; do
                # NOTES_DB format:
                # note title|note path|tag1,tag2|ebook information
                IFS='|' read -r title note_path _ <<< "$line"
                note_path=${note_path%$'\r'}

                [[ -n $note_path ]] || continue

                # Check whether this note has at least one URL.
                local has_url=0

                while IFS= read -r dbline || [[ -n $dbline ]]; do
                    [[ $dbline == "$note_path$CTRL_GS"* ]] || continue

                    record=${dbline#*"$CTRL_GS"}

                    local -a url_records=()
                    IFS="$CTRL_RS" read -r -a url_records <<< "$record"

                    for entry in "${url_records[@]}"; do
                        [[ -n $entry ]] || continue

                        if [[ $entry == *"$CTRL_US"* ]]; then
                            url=${entry%%"$CTRL_US"*}
                        else
                            url=$entry
                        fi

                        [[ -n $url ]] || continue

                        has_url=1
                        break
                    done

                    ((has_url)) && break
                done < "$URLS_DB"

                # Only add notes that actually have URLs.
                if ((has_url)); then
                    note_path_by_id[$id]=$note_path

                    # Show title in the menu. Fall back to note path if needed.
                    [[ -n $title ]] || title=$note_path

                    note_items+=("$id" "$title")
                    url_note_paths+=("$note_path")
                    ((++id))
                fi
            done

            if ((${#note_items[@]} == 0)); then
                _dialog_msg "None of the supplied notes have associated URLs." 10 65
                return 1
            fi

            GOALS_NOTE_GLOB=""
            GOALS_NOTE_TAGFILTER=""
            local GOALS_NOTE_TITLE_MODE=1
            local GOALS_NOTE_TAGMENU_FULL=1
            while :; do
                # ------------------------------------------------------------
                # Select a note.
                # ------------------------------------------------------------

                # Select Note: titles with tags; glob matches note titles;
                # __FILTER_BY_TAG__ offers [ANY TAG], [NO TAG] and the tags.
                goals_pick_note "Select Note" "Choose a linked note" \
                    "${url_note_paths[@]}" || return 1
                note_path="$GOALS_PICKED_NOTE_PATH"

                # ------------------------------------------------------------
                # Build URL menu for the selected note.
                # ------------------------------------------------------------

                id=1
                url_items=()
                url_by_id=()

                while IFS= read -r dbline || [[ -n $dbline ]]; do
                    [[ $dbline == "$note_path$CTRL_GS"* ]] || continue

                    record=${dbline#*"$CTRL_GS"}

                    local -a url_records=()
                    IFS="$CTRL_RS" read -r -a url_records <<< "$record"

                    for entry in "${url_records[@]}"; do
                        [[ -n $entry ]] || continue

                        if [[ $entry == *"$CTRL_US"* ]]; then
                            url=${entry%%"$CTRL_US"*}
                            description=${entry#*"$CTRL_US"}
                        else
                            url=$entry
                            description=""
                        fi

                        [[ -n $url ]] || continue

                        url_by_id[$id]=$url

                        if [[ -n $description ]]; then
                            url_items+=("$id" "$description $url")
                        else
                            url_items+=("$id" "$url")
                        fi

                        ((++id))
                    done
                done < "$URLS_DB"

                if ((${#url_items[@]} == 0)); then
                    _dialog_msg "No URLs were found for the selected note." 10 65
                    return 1
                fi

                # Select URL: __APPLY_GLOB__ matches the URL or its description.
                local url_glob="" new_url_glob shown_urls k_
                local -a url_menu=()
                while :; do
                    url_menu=(
                        "__APPLY_GLOB__" "Apply glob (matches URL or description)"
                        "__RESET_GLOB__" "Reset glob"
                    )
                    shown_urls=0
                    for (( k_ = 0; k_ < ${#url_items[@]}; k_ += 2 )); do
                        if [[ -n $url_glob ]]; then
                            [[ "${url_items[k_+1],,}" == ${url_glob,,} ]] || continue
                        fi
                        url_menu+=("${url_items[k_]}" "${url_items[k_+1]}")
                        shown_urls=$((shown_urls + 1))
                    done

                    selected_url=$(
                        whiptail \
                            --title "Select URL" \
                            --cancel-button "Back" \
                            --menu "Choose a URL to open:\nGlob: ${url_glob:-none}   ($shown_urls of $(( ${#url_items[@]} / 2 )) URLs shown)" \
                            20 155 10 \
                            "${url_menu[@]}" \
                            3>&1 1>&2 2>&3
                    ) || break

                    case $selected_url in
                        __APPLY_GLOB__)
                            if new_url_glob=$(whiptail --title "Apply URL Glob" --inputbox \
                                "Enter a case-insensitive glob to match URLs or their descriptions (for example: *github*). Leave empty to show all URLs." \
                                11 90 "$url_glob" 3>&1 1>&2 2>&3); then
                                url_glob=$new_url_glob
                            fi
                            continue
                            ;;
                        __RESET_GLOB__)
                            url_glob=""
                            continue
                            ;;
                    esac

                    [[ -n $selected_url ]] || continue

                    url=${url_by_id[$selected_url]-}
                    [[ -n $url ]] || continue

                    _spawn "$URL_BROWSER" --new-window -- "$url"
                done
            done
        }

        open_ebook_filtered() {
            _spawn() {
                nohup "$@" >/dev/null 2>&1 </dev/null &
            }

            _dialog_msg() {
                local message=$1
                local height=${2:-10}
                local width=${3:-60}

                whiptail --msgbox "$message" "$height" "$width" \
                    3>&1 1>&2 2>&3
            }

            if (($# == 0)); then
                _dialog_msg "No note records were supplied." 10 55
                return 1
            fi

            if [[ ! -r ${NOTES_DB:?NOTES_DB is not set} ]]; then
                _dialog_msg "NOTES_DB is not readable: $NOTES_DB" 10 65
                return 1
            fi

            local line
            local note_path
            local dbline
            local db_note_path
            local db_bookspec

            local entry
            local ebook
            local bookmark_spec

            local title
            local selected_note
            local selected_ebook

            local action
            local status

            local id

            local -a note_items=()
            local -a ebook_note_paths=()
            local -A note_path_by_id=()

            local -a ebook_items=()
            local -A ebook_by_id=()
            local -A bookmarks_by_id=()

            # ------------------------------------------------------------
            # Build menu of linked notes that have at least one ebook.
            # ------------------------------------------------------------

            id=1

            for line in "$@"; do
                # NOTES_DB format:
                # note title|note path|tag1,tag2|ebook information
                IFS='|' read -r title note_path _ <<< "$line"
                note_path=${note_path%$'\r'}

                [[ -n $note_path ]] || continue

                local has_ebook=0

                # Find the NOTES_DB record whose second field exactly matches
                # the note path.
                while IFS= read -r dbline || [[ -n $dbline ]]; do
                    IFS='|' read -r _ db_note_path _ db_bookspec <<< "$dbline"

                    [[ $db_note_path == "$note_path" ]] || continue

                    # Ebook records are separated by semicolons:
                    # /book/one.pdf#bookmark:10,other:20;/book/two.pdf#
                    local -a ebook_records=()
                    IFS=';' read -r -a ebook_records <<< "$db_bookspec"

                    for entry in "${ebook_records[@]}"; do
                        [[ -n $entry ]] || continue

                        if [[ $entry == *'#'* ]]; then
                            ebook=${entry%%#*}
                        else
                            ebook=$entry
                        fi

                        [[ -n $ebook ]] || continue

                        has_ebook=1
                        break
                    done

                    ((has_ebook)) && break
                done < "$NOTES_DB"

                # Only show notes that have at least one ebook.
                if ((has_ebook)); then
                    [[ -n $title ]] || title=$note_path

                    note_path_by_id[$id]=$note_path
                    note_items+=("$id" "$title")
                    ebook_note_paths+=("$note_path")

                    ((++id))
                fi
            done

            if ((${#note_items[@]} == 0)); then
                _dialog_msg \
                    "None of the supplied notes have associated ebook files." \
                    10 70
                return 1
            fi

            # ------------------------------------------------------------
            # Select note.
            # ------------------------------------------------------------

            # Select Note: titles with tags; glob matches note titles;
            # __FILTER_BY_TAG__ offers [ANY TAG], [NO TAG] and the tags.
            GOALS_NOTE_GLOB=""
            GOALS_NOTE_TAGFILTER=""
            local GOALS_NOTE_TITLE_MODE=1
            local GOALS_NOTE_TAGMENU_FULL=1
            goals_pick_note "Select Note" "Choose a linked note" \
                "${ebook_note_paths[@]}" || return 1
            note_path="$GOALS_PICKED_NOTE_PATH"

            # ------------------------------------------------------------
            # Build ebook menu for the selected note.
            # ------------------------------------------------------------

            id=1
            ebook_items=()
            ebook_by_id=()
            bookmarks_by_id=()

            while IFS= read -r dbline || [[ -n $dbline ]]; do
                IFS='|' read -r _ db_note_path _ db_bookspec <<< "$dbline"

                [[ $db_note_path == "$note_path" ]] || continue

                local -a ebook_records=()
                IFS=';' read -r -a ebook_records <<< "$db_bookspec"

                for entry in "${ebook_records[@]}"; do
                    [[ -n $entry ]] || continue

                    # Separate ebook path from bookmark list.
                    if [[ $entry == *'#'* ]]; then
                        ebook=${entry%%#*}
                        bookmark_spec=${entry#*#}
                    else
                        ebook=$entry
                        bookmark_spec=""
                    fi

                    [[ -n $ebook ]] || continue

                    ebook_by_id[$id]=$ebook
                    bookmarks_by_id[$id]=$bookmark_spec

                    ebook_items+=("$id" "$ebook")

                    ((++id))
                done

                # There should only be one matching note record.
                break
            done < "$NOTES_DB"

            if ((${#ebook_items[@]} == 0)); then
                _dialog_msg \
                    "No ebook files were found for the selected note." \
                    10 65
                return 1
            fi

            # ------------------------------------------------------------
            # Select ebook.
            # ------------------------------------------------------------

            selected_ebook=$(
                whiptail \
                    --title "Select Ebook" \
                    --cancel-button "Back" \
                    --menu "Choose an ebook to open in zathura:" \
                    22 100 14 \
                    "${ebook_items[@]}" \
                    3>&1 1>&2 2>&3
            )
            status=$?

            ((status != 0)) && return "$status"

            ebook=${ebook_by_id[$selected_ebook]-}
            bookmark_spec=${bookmarks_by_id[$selected_ebook]-}

            [[ -n $ebook ]] || return 1

            # ------------------------------------------------------------
            # Choose how to open the ebook.
            # ------------------------------------------------------------

            action=$(
                whiptail \
                    --title "Open Ebook" \
                    --cancel-button "Back" \
                    --menu "How should zathura open this ebook?" \
                    15 90 4 \
                    "open"       "Just open" \
                    "bookmarks"  "Browse bookmarks" \
                    3>&1 1>&2 2>&3
            )
            status=$?

            ((status != 0)) && return "$status"

            case $action in
                open)
                    _spawn "$(get_open_command "$ebook")" -- "$ebook"
                    ;;

                bookmarks)
                    # ----------------------------------------------------
                    # Build bookmark menu.
                    #
                    # Bookmark format:
                    # bookmark label:page,another bookmark:another page
                    # ----------------------------------------------------

                    local bookmark
                    local label
                    local page
                    local bookmark_id

                    local bookmark_selection
                    local bookmark_status

                    bookmark_id=1

                    local -a bookmark_items=()
                    local -A page_by_id=()

                    if [[ -n $bookmark_spec ]]; then
                        local -a bookmarks=()
                        IFS=',' read -r -a bookmarks <<< "$bookmark_spec"

                        for bookmark in "${bookmarks[@]}"; do
                            [[ -n $bookmark ]] || continue
                            [[ $bookmark == *:* ]] || continue

                            label=${bookmark%:*}
                            page=${bookmark##*:}

                            [[ $page =~ ^[0-9]+$ ]] || continue

                            page_by_id[$bookmark_id]=$page

                            bookmark_items+=(
                                "$bookmark_id"
                                "$label    [page $page]"
                            )

                            ((++bookmark_id))
                        done
                    fi

                    if ((${#bookmark_items[@]} == 0)); then
                        _dialog_msg \
                            "This ebook has no valid bookmarks in NOTES_DB." \
                            10 65
                        return 1
                    fi

                    # ----------------------------------------------------
                    # Select bookmark.
                    # ----------------------------------------------------

                    bookmark_selection=$(
                        whiptail \
                            --title "Select Bookmark" \
                            --cancel-button "Back" \
                            --menu "Choose a bookmark:" \
                            22 90 14 \
                            "${bookmark_items[@]}" \
                            3>&1 1>&2 2>&3
                    )
                    bookmark_status=$?

                    ((bookmark_status != 0)) && return "$bookmark_status"

                    page=${page_by_id[$bookmark_selection]-}
                    [[ -n $page ]] || return 1


                    local cmd__ vcmd__
                    cmd__="$(get_open_command "$ebook")"
                    vcmd__="${VIEWER_COMMANDS["$cmd__"]}"

                    [[ -n "$vcmd__" ]] || return 1

                    read -r -a viewer_cmd__ <<< "$vcmd__"
                    _spawn "${viewer_cmd__[@]}" "$page" -- "$ebook"

                    #_spawn "$vcmd__" "$page" -- "$ebook"
                    ;;

                *)
                    return 1
                    ;;
            esac
        }



        # FIX: PAGINATE LINKED NOTE SELECTION
        local selected_note_tag
        selected_note_tag="$(show_note_menu "$selected_project_title" "${note_menu_options[@]}")" || return 1

        # Handle case when user selects "Create new lnked note".
        if [[ "$selected_note_tag" == "Create new linked note" ]]; then
            local chosen_tag_goal
            chosen_tag_goal="$(choose_tag_goal)" || continue
            if [[ "$chosen_tag_goal" == "[NO TAG]" ]]; then
                add_note || continue
            else
                add_note "$chosen_tag_goal" || continue
            fi

            associate_new_note_to_project_from_do_stuff "$selected_project_path"
            continue    # Continue since we need to update the linked notes list now.
        elif [[ "$selected_note_tag" == "Link note" ]]; then
            associate_note_to_project_from_do_stuff "$selected_project_path" || continue
            continue    # Display list of linked notes again after associating a note.   
        elif [[ "$selected_note_tag" == "Unlink note" ]]; then
            mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)
            dissociate_note_from_project_from_do_stuff \
                "$selected_project_path" --filtered-notes "${filtered_linked_notes[@]}" || continue
            continue    # Display list of linked notes again after dissociating notes.
        elif [[ "$selected_note_tag" == "Manage plan" ]]; then
            edit_plan "$selected_project_path" || continue
            continue
        elif [[ "$selected_note_tag" == "Add tag to linked notes" ]]; then
            mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)
            if ((${#filtered_linked_notes[@]} == 0)); then
                whiptail --title "No Matching Notes" --msgbox \
                    "No linked notes match the active filters." 8 60
                continue
            fi
            add_tag_to_notes_from_filtered "${filtered_linked_notes[@]}"
            continue
        elif [[ "$selected_note_tag" == "Remove tag from linked notes" ]]; then
            # Work only with notes that satisfy both active filters.
            local notes_for_tag_workflow=()
            mapfile -t notes_for_tag_workflow < <(get_current_filtered_linked_notes)

            # ------------------------------------------------------------
            # Retrieve tags from the relevant linked notes.
            # ------------------------------------------------------------

            local note_tags=()

            mapfile -t note_tags < <(
                retrieve_linked_note_tags "${notes_for_tag_workflow[@]}"
            )

            # Remove the last element if it's empty.
            [[ -z "${note_tags[-1]}" ]] && unset 'note_tags[-1]'

            if (( ${#note_tags[@]} == 0 )); then
                whiptail \
                    --title "No Matching Tags" \
                    --msgbox "There are no matching tags." \
                    10 50 \
                    3>&1 1>&2 2>&3 </dev/tty >/dev/tty

                continue
            fi

            # ------------------------------------------------------------
            # Build tag menu.
            # ------------------------------------------------------------

            local chosen_tag_for_removal
            local tag_menu_options=()
            local tag

            for tag in "${note_tags[@]}"; do
                tag_menu_options+=("$tag" "")
            done

            # ------------------------------------------------------------
            # Select tag.
            # ------------------------------------------------------------

            # if ! chosen_tag_for_removal=$(whiptail \
            #     --title "Remove Linked Note Tag" \
            #     --menu "Select a tag to remove:" \
            #     20 80 10 \
            #     "${tag_menu_options[@]}" \
            #     3>&1 1>&2 2>&3 </dev/tty >/dev/tty
            # ); then
            #     continue
            # fi

            # Remove Linked Note Tag: __FILTER__ narrows the list by a literal
            # substring, __RESET_FILTER__ clears it.
            goals_select_note_tag_filter --title "Remove Linked Note Tag" \
                --prompt "Select a tag to remove" --pins "" \
                --tags "${note_tags[@]}" || continue
            chosen_tag_for_removal="$GOALS_SELECTED_NOTE_TAG"

            # ------------------------------------------------------------
            # Find NOTES_DB lines containing the selected tag, then
            # extract the note path from field 2.
            # ------------------------------------------------------------

            local notes_with_selected_tag=()
            local note_line
            local note_path

            while IFS= read -r note_line; do

                [[ -z "$note_line" ]] && continue

                # NOTES_DB format:
                # title|path|tags|rest
                IFS='|' read -r _ note_path _ _ <<< "$note_line"

                [[ -n "$note_path" ]] &&
                    notes_with_selected_tag+=("$note_path")

            done < <(
                filter_linked_notes_by_tag \
                    "$chosen_tag_for_removal" \
                    "${notes_for_tag_workflow[@]}"
            )

            if (( ${#notes_with_selected_tag[@]} == 0 )); then
                whiptail \
                    --title "No Matching Notes" \
                    --msgbox \
                    "There are no linked notes with the tag \"$chosen_tag_for_removal\"." \
                    10 70 \
                    3>&1 1>&2 2>&3 </dev/tty >/dev/tty

                continue
            fi

            # ------------------------------------------------------------
            # Paginated checklist settings.
            # ------------------------------------------------------------

            # Select notes: __REMOVE__ at the top, full note paths with their
            # tags, glob (file name) and tag filters.
            GOALS_NOTE_GLOB=""
            GOALS_NOTE_TAGFILTER=""
            local selected_notes_for_removal=()
            local rm_path_ matching_line__
            while :; do
                goals_pick_notes_multi "Select Notes" \
                    "Select notes to remove the tag \"$chosen_tag_for_removal\" from" \
                    "__remove__" "Remove the tag from the selected notes" top \
                    "${notes_with_selected_tag[@]}" || break

                selected_notes_for_removal=()
                for rm_path_ in "${GOALS_PICKED_PATHS[@]}"; do
                    matching_line__=$(
                        awk -F'|' -v path="$rm_path_" '$2 == path { print; exit }' "$NOTES_DB"
                    )
                    [[ -n "$matching_line__" ]] &&
                        selected_notes_for_removal+=("$matching_line__")
                done

                if (( ${#selected_notes_for_removal[@]} == 0 )); then
                    whiptail --title "No Notes Selected" --msgbox \
                        "Select at least one note before choosing \"__remove__\"." 10 70
                    continue
                fi

                if remove_linked_note_tag \
                    "$chosen_tag_for_removal" \
                    "${selected_notes_for_removal[@]}"
                then
                    whiptail --title "Tag Removed" --msgbox \
                        "The tag \"$chosen_tag_for_removal\" has been removed from the selected notes." \
                        10 80
                    break
                fi
            done
            continue
        elif [[ "$selected_note_tag" == "__FILTER_BY_TAG__" ]]; then
            # Offer [ANY TAG], [NO TAG] and the tags of the linked notes that match
            # the title glob. __FILTER__ narrows the tag list (literal substring)
            # and __RESET_FILTER__ clears that narrowing.
            local -a filter_tags=()
            mapfile -t linked_notes_array < <(get_linked_notes_matching_glob)
            if ((${#linked_notes_array[@]} > 0)); then
                mapfile -t filter_tags < <(
                    retrieve_linked_note_tags "${linked_notes_array[@]}" | sed '/^$/d'
                )
            fi
            if goals_select_note_tag_filter --title "Filter Linked Notes" \
                --prompt "Choose a tag to filter the linked notes by" \
                --no-tag-desc "Show only linked notes that have no tag" \
                --any-tag-desc "Show linked notes with or without tags" \
                --tags "${filter_tags[@]}"; then
                TAG_FILTER_BY="$GOALS_SELECTED_NOTE_TAG"
            fi
            continue
        elif [[ "$selected_note_tag" == "__RESET_FILTER__" ]]; then
            TAG_FILTER_BY=""
            continue
        elif [[ "$selected_note_tag" == "__APPLY_GLOB__" ]]; then
            local new_glob
            new_glob=$(whiptail \
                --title "Apply Glob to Linked Note Titles" \
                --inputbox \
                "Enter a case-insensitive Bash glob for note titles.
Examples: *Python* or Meeting-??

Leave the pattern non-empty; use * to match all titles." \
                13 80 "$GLOB_FILTER_BY" \
                3>&1 1>&2 2>&3) || continue

            if [[ -z "$new_glob" ]]; then
                whiptail --title "Empty Glob" --msgbox \
                    "The glob cannot be empty. Use * to match all titles, or choose __RESET_GLOB__ to clear the glob filter." \
                    10 75
                continue
            fi

            GLOB_FILTER_BY="$new_glob"
            continue
        elif [[ "$selected_note_tag" == "__RESET_GLOB__" ]]; then
            GLOB_FILTER_BY=""
            continue
        elif [[ "$selected_note_tag" == "Create new note tag" ]]; then
            add_note_tag_stuff
            continue
        elif [[ "$selected_note_tag" == "Open URL" ]]; then
            mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)
            open_urls_filtered "${filtered_linked_notes[@]}"
            continue
        elif [[ "$selected_note_tag" == "Open ebook" ]]; then
            mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)
            open_ebook_filtered "${filtered_linked_notes[@]}"
            continue
        fi

        #-- Helper fn's for 'Add tag to item' and 'Remove tag from item'
        add_tag_to_item() {
            goals_add_tag_to_note "$1"
        }


        remove_tag_from_item() {
            goals_remove_tag_from_note "$1"
        }
        #-- Helpers end.        

        local selected_note_index=$((selected_note_tag - 1))
        local selected_note_line="${note_lines[$selected_note_index]}"

        # Action selection
        local action
        action=$(whiptail --menu "Note Action" 24 60 11 \
            "1" "View Note" \
            "2" "Copy note content to clipboard" \
            "3" "Open ebooks linked to note" \
            "4" "Edit Note" \
            "5" "Open linked URL" \
            "6" "Associate URL to note" \
            "7" "Dissociate URL from note" \
            "8" "Associate Note to Project" \
            "9" "Print Note using Printer" \
            "10" "Add tag to item" \
            "11" "Remove tag from item" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue    # i want to return to list of linked note files so continue

        case "$action" in
            "1")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                #whiptail --scrolltext --title "$note_title" --textbox "$note_path" 35 150
                
                # FIX: USE DIALOG INSTEAD BECAUSE WHIPTAIL FAILS HERE.
                # Specifically, \n \t etc gets translated.
                # The shared dialog() wrapper applies the same palette as Whiptail.
                #dialog --exit-label "Back" --title "$note_title" --textbox "$note_path" 35 150
                # Word wrap width 145
                local tmpfile=$(mktemp)
                fold -s -w 145 "$note_path" > "$tmpfile"
                dialog --no-mouse --exit-label "Back" --title "$note_title" --textbox "$tmpfile" 35 150
                rm -f "$tmpfile"
                clear
                ;;
            "2")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                # Save $note_path to xclip
                cat "$note_path" | xclip -sel clip
                whiptail --msgbox "Copied to clipboard!" 8 50 >/dev/tty
                ;;
            "3")
                open_note_ebook_page_from_project "$selected_note_line"
                ;;
            "4")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                edit_note "$note_path"
                ;;
            "5")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                open_url_assoc_to_chosen_note
                ;;
            "6")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                assoc_url_to_chosen_note
                ;;
            "7")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                dissoc_url_from_chosen_note
                ;;
            "8")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                associate_chosen_note_to_project "$note_path"
                ;;
            "9")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                print_chosen_note "$note_path"
                ;;
            "10")
                add_tag_to_item "$selected_note_line"
                ;;
            "11")
                remove_tag_from_item "$selected_note_line"
                ;;
        esac
    done
}

open_url_assoc_to_note_from_project() {
    touch "$URLS_DB" "$PROJECTS_DB"

    local GS=$'\x1D'  # separates note path and rest
    local US=$'\x1F'  # separates url and url title
    local RS=$'\x1E'  # separates urls

    # Check if Projects database exists
    if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    fi

    # Check if URLs database exists
    if [[ ! -f "$URLS_DB" || ! -s "$URLS_DB" ]]; then
        whiptail --msgbox "No URLs found. Associate at least one URL and try again." 8 40 >/dev/tty
        return 1
    fi

    local -a note_paths_array=() urls=() titles=() entries=() url_menu_items=()
    local chosen_project notes_field np selected_path line entry url title
    local url_glob choice new_glob shown i

    # __APPLY_GLOB__ matches the project file name; __RESET_GLOB__ clears it.
    GOALS_PROJECT_GLOB=""

    while true; do
        goals_select_project "Choose Project to Open URL from Associated Note" || return 1
        chosen_project="$GOALS_SELECTED_PROJECT_PATH"
        notes_field="$GOALS_SELECTED_PROJECT_NOTES"

        # Notes linked to the chosen project
        note_paths_array=()
        while IFS= read -r np; do
            [[ -n "$np" ]] && note_paths_array+=("$np")
        done < <(tr ',' '\n' <<< "$notes_field")

        if (( ${#note_paths_array[@]} == 0 )); then
            whiptail --msgbox "The selected project has no associated notes." 8 60 >/dev/tty
            continue
        fi

        # Select Note: full paths plus tags; glob matches note file names;
        # __FILTER_BY_TAG__ filters by the notes' tags.
        GOALS_NOTE_GLOB=""
        GOALS_NOTE_TAGFILTER=""
        goals_pick_note "Select Note" "Choose a note to open URLs" \
            "${note_paths_array[@]}" || continue
        selected_path="$GOALS_PICKED_NOTE_PATH"

        # Extract URLs for selected note
        urls=()
        titles=()
        while IFS= read -r line; do
            # Only for the matched line...
            if [[ "$line" == "${selected_path}${GS}"* ]]; then
                IFS="$RS" read -ra entries <<< "${line#*$GS}"
                for entry in "${entries[@]}"; do
                    IFS="$US" read -r url title <<< "$entry"
                    urls+=("$url")
                    titles+=("$title")
                done
                break
            fi
        done < "$URLS_DB"

        if [[ ${#urls[@]} -eq 0 ]]; then
            whiptail --msgbox "No URLs found for selected note!" 8 50 >/dev/tty
            continue
        fi

        # URL selection loop. __APPLY_GLOB__ matches the URL or its title.
        url_glob=""
        while true; do
            url_menu_items=("<< Back" "" "__APPLY_GLOB__" "Apply glob (matches URL or title)" "__RESET_GLOB__" "Reset glob")
            shown=0
            for i in "${!urls[@]}"; do
                if [[ -n "$url_glob" ]]; then
                    [[ "${urls[i],,}" == ${url_glob,,} || "${titles[i],,}" == ${url_glob,,} ]] || continue
                fi
                url_menu_items+=("$i" "${urls[i]} - ${titles[i]:0:50}")
                shown=$((shown + 1))
            done

            choice=$(whiptail --title "URLs for $selected_path" --cancel-button "Back" \
                --menu "Choose URL to open:\nGlob: ${url_glob:-none} ($shown of ${#urls[@]} URLs shown)" \
                20 155 10 "${url_menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || break
            [[ -z "$choice" ]] && break

            case "$choice" in
                "<< Back")
                    break
                    ;;
                __APPLY_GLOB__)
                    if new_glob=$(whiptail --title "Apply URL Glob" --inputbox \
                        "Enter a case-insensitive glob to match URLs or their titles (for example: *github*). Leave empty to show all URLs." \
                        11 90 "$url_glob" 3>&1 1>&2 2>&3 </dev/tty); then
                        url_glob="$new_glob"
                    fi
                    ;;
                __RESET_GLOB__)
                    url_glob=""
                    ;;
                *)
                    if [[ "$choice" =~ ^[0-9]+$ && -n "${urls[$choice]}" ]]; then
                        nohup "$URL_BROWSER" "${urls[$choice]}" >/dev/null 2>&1 &   # to make sure browser stays open
                    fi
                    ;;
            esac
        done
    done
}

print_project_to_printer_from_main() {
    print_file_from_do_stuff_project_from_main() {
        # Check if file argument is provided
        if [ -z "$1" ]; then
            return 1
        fi

        local file_to_print="$1"

        # Check if file exists
        if [ ! -f "$file_to_print" ]; then
            echo "Error: File '$file_to_print' does not exist." >&2
            return 1
        fi

        # Get list of printers
        local printers
        printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')            

        # Edge case: no printers found.
        [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

        # Convert printer list into whiptail menu format
        local menu_items=()
        for p in $printers; do
            menu_items+=("$p" "")
        done

        # Show whiptail menu to select printer
        local selected_printer
        selected_printer=$(whiptail --title "Select Printer" \
            --menu "Choose a printer:" 20 60 10 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3)

        # Check if user cancelled
        if [ $? -ne 0 ]; then
            return 1
        fi

        # Print the file
        if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
            lpr -P "$selected_printer" "$file_to_print"
            if [ $? -eq 0 ]; then
                whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
            else
                whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                return 1
            fi            
        else
            :  # do nothing if No or Cancel
        fi
    }

    get_project_title_from_project_path() {
        local project_path="$1"
        local project_title

        project_title=$(awk -F'|' -v path="$project_path" '
            $2 == path {
                print $1
                exit
            }
        ' "$PROJECTS_DB")

        echo "$project_title"
    }
    
    # Pick a project by full path. __APPLY_GLOB__ matches the project file
    # name and __RESET_GLOB__ clears the glob.
    GOALS_PROJECT_GLOB=""
    local line_

    # Check if database file exists and is valid
    if [ ! -f "$PROJECTS_DB" ]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    elif [ ! -s "$PROJECTS_DB" ]; then
        whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 >/dev/tty
        return 1
    fi

    # Continuous selection loop
    while true; do
        goals_select_project "Print Project using Printer" || return 1
        line_="$GOALS_SELECTED_PROJECT_LINE"

        local title_ path_
        IFS='|' read -r title_ path_ _ <<< "$line_"

        if [ ! -e "$path_" ]; then
            whiptail --msgbox "Error: Project file '$path_' not found." 10 50 >/dev/tty
            return 1
        elif [ -d "$path_" ]; then
            whiptail --msgbox "Error: '$path_' is a directory, not a file." 10 50 >/dev/tty
            return 1
        elif [ ! -r "$path_" ]; then
            whiptail --msgbox "Error: Cannot read project file '$path_'." 10 50 >/dev/tty
            return 1
        fi

        local action
        action=$(whiptail --title "Actions" --menu "Choose an action:" 10 40 2 \
                "View Project" "" \
                "Print Project" "" \
                3>&1 1>&2 2>&3) || :        

        case "$action" in
            "View Project")

                local tmpfile
                tmpfile=$(mktemp)
                fold -s -w 145 "$path_" > "$tmpfile"
                # NOTE: PROJECT_TITLE IS NOT EXTRACTED YET! -- FIXED?
                local project_title="$(get_project_title_from_project_path "$path_")"
                dialog --no-mouse --exit-label "Back" --title "$project_title" --textbox "$tmpfile" 35 150                
                rm -f "$tmpfile"
                clear
                ;;
            "Print Project")
                print_file_from_do_stuff_project_from_main "$path_"
                ;;
            *)
                :
                ;;

        esac              
    done
}

# Utility function used to record add/remove project file to shortlist so history can be viewed.
save_action_shortlisted() {
    local proj_path="$1"
    local action="$2"

    # Ensure $SHORTLISTED_HISTORY file exists
    touch "$SHORTLISTED_HISTORY"

    # Get current timestamp
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Append timestamp, action, and project path to the history file
    echo "[$timestamp] $action $proj_path" >> "$SHORTLISTED_HISTORY"
}

add_to_shortlist() {
    add_item_to_shortlist() {
        [[ -s "$PROJECTS_DB" ]] || {
            whiptail --msgbox "No projects found. Add at least one project and try again." 8 60
            return 1
        }

        # No initial glob prompt: the picker offers __APPLY_GLOB__ and
        # __RESET_GLOB__, matching the project file name (case-insensitively).
        local GOALS_PROJECT_RESTRICT_FILE=""
        local GOALS_PROJECT_TITLE_MODE=""
        GOALS_PROJECT_GLOB=""
        goals_select_project "Select Project" || return 1
        printf '%s\n' "$GOALS_SELECTED_PROJECT_PATH"
    }

    # Ensure file exists
    touch "$PROJECTS_DB_SHORTLISTED"

    local choice new_item
    local page=0
    local page_size=50 # a common optimal page size.

    while true; do
        # Read shortlisted projects
        mapfile -t shortlisted < "$PROJECTS_DB_SHORTLISTED"

        local total=${#shortlisted[@]}
        local max_page=0
        (( total > 0 )) && max_page=$(( (total - 1) / page_size ))

        (( page < 0 )) && page=0
        (( page > max_page )) && page=$max_page

        local start=$(( page * page_size ))
        local end=$(( start + page_size ))

        # Build menu
        local menu_items=(
            "Add item" ""
        )

        # Navigation
        (( page > 0 )) && menu_items+=( "<< Prev" "" )
        (( page < max_page )) && menu_items+=( "Next >>" "" )

        # Paginated shortlisted items (4 per page)
        for ((i=start; i<end && i<total; i++)); do
            [[ -n "${shortlisted[i]}" ]] && menu_items+=( "${shortlisted[i]}" "" )
        done

        choice=$(whiptail \
            --title "Shortlisted Projects" \
            --cancel-button "Back" \
            --menu "Page $((page+1)) of $((max_page+1))" \
            20 155 10 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            "Add item")
                new_item=$(add_item_to_shortlist)
                [[ -z "$new_item" ]] && continue

                if ! whiptail --title "Confirm" --yesno "Do you want to add this project?" 8 40; then
                    continue
                fi

                if grep -Fxq -- "$new_item" "$PROJECTS_DB_SHORTLISTED"; then
                    whiptail --title "Duplicate" \
                             --msgbox "This project is already in the shortlist:\n\n$new_item" \
                             10 70
                else
                    echo "$new_item" >> "$PROJECTS_DB_SHORTLISTED"
                    save_action_shortlisted "$new_item" "ADDED"
                fi
                ;;
            "<< Prev")
                ((page--))
                ;;
            "Next >>")
                ((page++))
                ;;
            *)
                # shortlisted item selected — currently no-op (by design)
                :
                ;;
        esac
    done
}

remove_from_shortlist() {
    touch "$PROJECTS_DB_SHORTLISTED"
    [[ -s "$PROJECTS_DB_SHORTLISTED" ]] || {
        whiptail --title "Shortlisted Projects" --msgbox "There are no projects in the shortlist." 8 60
        return 1
    }

    # Restrict the shared picker to shortlisted paths. Its glob is applied to
    # project file names, with __APPLY_GLOB__ / __RESET_GLOB__ controls.
    local GOALS_PROJECT_RESTRICT_FILE="$PROJECTS_DB_SHORTLISTED"
    local GOALS_PROJECT_TITLE_MODE=""
    local selected_path tmp_file
    GOALS_PROJECT_GLOB=""

    while :; do
        goals_select_project "Select Project to Remove from Shortlist" || return 1
        selected_path="$GOALS_SELECTED_PROJECT_PATH"
        [[ -n "$selected_path" ]] || continue

        if whiptail --title "Remove from Shortlist" --yesno \
            "Are you sure you want to remove this project from the shortlist?\n\n$selected_path" 12 80; then
            tmp_file=$(mktemp) || return 1
            awk -v selected="$selected_path" '$0 != selected { print }' \
                "$PROJECTS_DB_SHORTLISTED" > "$tmp_file" || {
                    rm -f -- "$tmp_file"
                    return 1
                }
            mv -- "$tmp_file" "$PROJECTS_DB_SHORTLISTED" || return 1
            save_action_shortlisted "$selected_path" "REMOVED"
            whiptail --msgbox "Removed from shortlist:\n\n$selected_path" 10 80
        fi

        [[ -s "$PROJECTS_DB_SHORTLISTED" ]] || {
            whiptail --title "Shortlisted Projects" --msgbox "The shortlist is now empty." 8 60
            return 0
        }
    done
}

view_shortlist_history() {
    # Ensure the history file exists
    touch "$SHORTLISTED_HISTORY"

    if [[ ! -s "$SHORTLISTED_HISTORY" ]]; then
        # File is empty, show message
        whiptail --title "Shortlisted History" --msgbox "No history yet." 10 50
    else
        # File has content, show in textbox
        local tmp_file
        tmp_file=$(mktemp)
        cat "$SHORTLISTED_HISTORY" > "$tmp_file"
        whiptail --title "Shortlisted History" --textbox "$tmp_file" 20 80 --scrolltext
        rm -f "$tmp_file"
    fi
}

trim_shortlisted_history() {
    # Ensure the file exists
    [[ -f "$SHORTLISTED_HISTORY" ]] || return

    # Keep only the last 200 lines
    tail -n 200 "$SHORTLISTED_HISTORY" > "${SHORTLISTED_HISTORY}.tmp" && mv "${SHORTLISTED_HISTORY}.tmp" "$SHORTLISTED_HISTORY"
}

do_stuff_shortlisted() {
    local selected_project_title

    truncate_tag() {
        local tags="$1"
        local max_len=60    # tweak this!

        # If already within limit, print unchanged
        if (( ${#tags} <= max_len )); then
            echo "$tags"
            return
        fi

        # Split into an array (preserve tags with spaces)
        IFS=',' read -r -a arr <<< "$tags"

        local latest_tag="${arr[-1]}"
        local result=""
        local sep=""

        # Try adding tags until adding another exceeds limit
        for (( i=0; i<${#arr[@]}-1; i++ )); do
            local t="${arr[$i]}"
            local candidate="${result}${sep}${t}"

            # If not enough room even if we later add ", ..., latest_tag", stop
            local future="${candidate}, ..., ${latest_tag}"
            if (( ${#future} > max_len )); then
                break
            fi

            result="$candidate"
            sep=", "
        done

        # If we couldn't include any tags (very tight width), result may be empty
        if [[ -z "$result" ]]; then
            echo "... , ${latest_tag}"
        else
            echo "${result}, ..., ${latest_tag}"
        fi
    }

    show_note_menu() {
        selected_project_title="$1"
        # might as well truncate it here.
        (( ${#selected_project_title} > 50 )) && selected_project_title="${selected_project_title:0:50}..."
        shift

        local note_menu_options=("$@")
        local page=0
        local per_page=50    # adjust this to my liking
        # Status info: active filters and how many linked notes are visible.
        local filter_summary
        filter_summary="\nTag filter: ${TAG_FILTER_BY:-none}   |   Title glob: ${GLOB_FILTER_BY:-none}"
        filter_summary+="\nShowing ${#note_lines[@]} of ${LINKED_NOTES_TOTAL:-?} linked notes"
        local total_items=$(( ${#note_menu_options[@]} / 2 ))
        local total_pages=$(( (total_items + per_page - 1) / per_page ))
        local selected_note_tag=""

        while true; do
            local start=$(( page * per_page ))
            local end=$(( start + per_page ))
            if (( end > total_items )); then end=$total_items; fi

            # Build current page menu items
            local menu_items=()
            for ((i=start; i<end; i++)); do
                local idx=$(( i * 2 ))
                menu_items+=( "${note_menu_options[idx]}" "${note_menu_options[idx+1]}" )
            done

            # Add navigation options
            if (( page > 0 )); then
                menu_items+=( "<< Prev" "" )
            fi
            if (( page < total_pages - 1 )); then
                menu_items+=( ">> Next" "" )
            fi

            # Display menu
            selected_note_tag=$(whiptail --title "Linked Notes for ${selected_project_title} (Page $((page+1))/$total_pages)" \
                --menu "Select a linked note:${filter_summary}" 35 155 25 "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

            # Handle navigation
            case "$selected_note_tag" in
                "<< Prev") ((page--));;
                ">> Next") ((page++));;
                *) echo "$selected_note_tag"; return 0;;
            esac
        done
    }

    open_url_assoc_to_chosen_note() {
        goals_open_url_for_note "$note_path"
    }

    assoc_url_to_chosen_note() {
        goals_manage_urls_for_note "$note_path"
    }

    dissoc_url_from_chosen_note() {
        goals_dissociate_urls_from_note "$note_path"
    }

    associate_chosen_note_to_project() {
        # Get note path from arg
        local note_path="$1"
        [[ -z "$note_path" ]] && return 1

        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        # Do not ask for a glob up front. Select Project offers
        # __APPLY_GLOB__ / __RESET_GLOB__ and matches project file names.
        local GOALS_PROJECT_RESTRICT_FILE=""
        local GOALS_PROJECT_TITLE_MODE=""
        GOALS_PROJECT_GLOB=""
        goals_select_project "Select Project" || { rm -f -- "$temp_file"; return 1; }
        local selected_project_path="$GOALS_SELECTED_PROJECT_PATH"
        [[ -n "$selected_project_path" ]] || { rm -f -- "$temp_file"; return 1; }

        # User already chosen $note_path as chosen note file.
        local selected_note_path
        selected_note_path="$note_path"

        [[ -z "$selected_note_path" ]] && return 1

        # Process PROJECTS_DB
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                #echo >> "$temp_file"
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                return 1
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                return 1
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            return 1
        fi
    }

    print_chosen_note() {
        print_file_from_do_stuff_project() {
            # Check if file argument is provided
            if [ -z "$1" ]; then
                return 1
            fi

            local file_to_print="$1"

            # Check if file exists
            if [ ! -f "$file_to_print" ]; then
                echo "Error: File '$file_to_print' does not exist." >&2
                return 1
            fi

            # Get list of printers
            local printers
            printers=$(lpstat -p | awk '/^printer/ && /enabled/ {print $2}')            

            # Edge case: no printers found.
            [[ -z "$printers" ]] && { whiptail --title "Attention" --msgbox "No printers found." 8 40; return 1; }

            # Convert printer list into whiptail menu format
            local menu_items=()
            for p in $printers; do
                menu_items+=("$p" "")
            done

            # Show whiptail menu to select printer
            local selected_printer
            selected_printer=$(whiptail --title "Select Printer" \
                --menu "Choose a printer:" 20 60 10 \
                "${menu_items[@]}" 3>&1 1>&2 2>&3)

            # Check if user cancelled
            if [ $? -ne 0 ]; then
                return 1
            fi

            # Print the file
            if whiptail --title "Print Note" --yesno "Send '$file_to_print' to printer '$selected_printer'?" 12 80; then
                lpr -P "$selected_printer" "$file_to_print"
                if [ $? -eq 0 ]; then
                    whiptail --title "Success" --msgbox "File '$file_to_print' sent to printer '$selected_printer'." 12 80
                else
                    whiptail --title "Error" --msgbox "Failed to print '$file_to_print'." 12 80
                    return 1
                fi            
            else
                :  # do nothing if No or Cancel
            fi
        }

        local selected_path="$1"       
        print_file_from_do_stuff_project "$selected_path"
    }

    associate_new_note_to_project_from_shortlist() {
        # note path is the new note you've just created from select notes menu.
        local NEW_NOTE_PATH="$note_path"
        [[ -z "$NEW_NOTE_PATH" ]] && return 1

        local temp_file line_updated duplicate_detected project_found
        temp_file=$(mktemp) || return 1
        line_updated=0
        duplicate_detected=0
        project_found=0

        # Check if databases exist
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        local selected_project_path
        selected_project_path="$1"
        [[ -z "$selected_project_path" ]] && return 1

        local selected_note_path="$NEW_NOTE_PATH"

        # WE'VE SELECTED PROJECT FILE AND NOTE FILE AT THIS POINT!!!!

        # Process PROJECTS_DB - update each line (only change line of selected project file)
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                continue
            fi

            IFS='|' read -r title path notes <<< "$line"
            # If there is matched line...
            if [[ "$path" == "$selected_project_path" ]]; then
                project_found=1
                current_notes="$notes"
                local notes_array=()

                # Check for duplicates
                IFS=',' read -ra notes_array <<< "$current_notes"
                local duplicate=0	# Reset for each iteration.
                # If duplicate found then set duplicate and break out of for loop here.
                for note in "${notes_array[@]}"; do
                    [[ "$note" == "$selected_note_path" ]] && duplicate=1 && break
                done

                if (( duplicate )); then
                    whiptail --msgbox "Note is already associated with the selected project. No changes made." 10 50

                    # reset
                    line_updated=0

                    duplicate_detected=1
                    # Rebuild original line
                    new_line="$title|$path|$current_notes"
                    # There is no fourth field!!!!
                    # [[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# No change.
                else
                    # reset
                    duplicate_detected=0

                    # Update notes
                    # If there is no previously associated note...
                    if [[ -z "$current_notes" ]]; then
                        new_notes="$selected_note_path"
                    else
                        new_notes="$current_notes,$selected_note_path"
                    fi
                    new_line="$title|$path|$new_notes"
                    #[[ -n "$rest" ]] && new_line+="|$rest"
                    echo "$new_line" >> "$temp_file"	# Changes made.
                    line_updated=1
                fi
            else
                # Just leave the line unchanged.
                echo "$line" >> "$temp_file"
            fi
        done < "$PROJECTS_DB"

        # Handle processing results
        if (( project_found )); then
            if (( line_updated && !duplicate_detected )); then
                mv "$temp_file" "$PROJECTS_DB"
                whiptail --msgbox "Note successfully associated with the project." 10 50
            elif (( duplicate_detected )); then
                rm "$temp_file"
                #whiptail --msgbox "Duplicate found. No changes were made to the project entry." 10 50
                return 1
            else
                rm "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                return 1
            fi
        else
            rm "$temp_file"
            whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
            return 1
        fi
    }

    associate_note_to_project_from_shortlist() {
        # Link note: pick a starting tag filter, then tick the notes to link.
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Please add at least one project and try again." 8 60
            return 1
        fi
        if [[ ! -f "$NOTES_DB" || ! -s "$NOTES_DB" ]]; then
            whiptail --msgbox "Please add at least one note and try again." 8 60
            return 1
        fi

        local selected_project_path="$1"
        [[ -z "$selected_project_path" ]] && return 1

        # Notes already linked to the project are not offered again.
        local -A linked_map=()
        local pl_title pl_path pl_notes lnp
        while IFS='|' read -r pl_title pl_path pl_notes; do
            [[ "$pl_path" == "$selected_project_path" ]] || continue
            while IFS= read -r lnp; do
                [[ -n "$lnp" ]] && linked_map["$lnp"]=1
            done < <(tr ',' '\n' <<< "$pl_notes")
            break
        done < "$PROJECTS_DB"

        # Select Note Tag to Filter Notes: [NO TAG], [ANY TAG] or a tag, with
        # __FILTER__ (literal substring) and __RESET_FILTER__.
        local selected_note_tag note_title note_path note_tags rest
        local -a note_candidates=() all_note_paths=()
        while :; do
            goals_select_note_tag_filter || return 1
            selected_note_tag="$GOALS_SELECTED_NOTE_TAG"

            note_candidates=()
            all_note_paths=()
            while IFS='|' read -r note_title note_path note_tags rest; do
                [[ -n "$note_path" ]] || continue
                [[ -n "${linked_map[$note_path]:-}" ]] && continue
                all_note_paths+=("$note_path")
                case "$selected_note_tag" in
                    "[ANY TAG]") note_candidates+=("$note_path") ;;
                    "[NO TAG]")  [[ -z "$note_tags" ]] && note_candidates+=("$note_path") ;;
                    *)           goals_note_has_tag "$note_tags" "$selected_note_tag" && note_candidates+=("$note_path") ;;
                esac
            done < "$NOTES_DB"

            (( ${#note_candidates[@]} > 0 )) && break

            case "$selected_note_tag" in
                "[ANY TAG]") whiptail --msgbox "There are no notes left to link to this project." 8 60 ;;
                "[NO TAG]")  whiptail --msgbox "There are no notes with no associated tag found." 8 60 ;;
                *)           whiptail --msgbox "Tag '${selected_note_tag}' has no notes available to link." 8 60 ;;
            esac
        done

        # Choose Note to Associate: the chosen tag is the starting tag filter;
        # the status shows the current tag filter and glob.
        GOALS_NOTE_GLOB=""
        GOALS_NOTE_TAGFILTER="$selected_note_tag"
        local -a selected_note_paths=() remaining=()
        local temp_file project_found line_updated added_count line title path notes np new_notes
        local -A already=()
        while :; do
            goals_pick_notes_multi "Choose Note to Associate" \
                "Choose notes to link to the project" \
                "__add__" "Link the selected notes to the project" top \
                "${all_note_paths[@]}" || return 1
            selected_note_paths=("${GOALS_PICKED_PATHS[@]}")

            temp_file=$(mktemp) || return 1
            project_found=0; line_updated=0; added_count=0
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                IFS='|' read -r title path notes <<< "$line"
                if [[ "$path" == "$selected_project_path" ]]; then
                    project_found=1
                    already=()
                    while IFS= read -r np; do
                        [[ -n "$np" ]] && already["$np"]=1
                    done < <(tr ',' '\n' <<< "$notes")
                    new_notes="$notes"
                    for np in "${selected_note_paths[@]}"; do
                        [[ -n "${already[$np]:-}" ]] && continue
                        new_notes="${new_notes:+$new_notes,}$np"
                        already["$np"]=1
                        added_count=$((added_count + 1))
                    done
                    (( added_count > 0 )) && line_updated=1
                    printf '%s\n' "$title|$path|$new_notes" >> "$temp_file"
                else
                    printf '%s\n' "$line" >> "$temp_file"
                fi
            done < "$PROJECTS_DB"

            if (( ! project_found )); then
                rm -f "$temp_file"
                whiptail --msgbox "Selected project not found in database. It may have been removed." 10 50
                continue
            fi
            if (( ! line_updated )); then
                rm -f "$temp_file"
                whiptail --msgbox "No changes were made to the project entry." 10 50
                continue
            fi

            mv "$temp_file" "$PROJECTS_DB"
            whiptail --msgbox "$added_count note(s) successfully associated with the project." 10 60

            # The linked notes are no longer offered.
            for np in "${selected_note_paths[@]}"; do linked_map["$np"]=1; done
            remaining=()
            for np in "${all_note_paths[@]}"; do
                [[ -z "${linked_map[$np]:-}" ]] && remaining+=("$np")
            done
            all_note_paths=("${remaining[@]}")
            if (( ${#all_note_paths[@]} == 0 )); then
                whiptail --msgbox "All available notes are now linked to this project." 8 60
                return 0
            fi
        done
    }

    dissociate_note_from_project_from_shortlist() {
        # Unlink note: tick the linked notes to unlink. Glob (file name) and tag
        # filters are available inside the picker.
        if [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]]; then
            whiptail --msgbox "Error: PROJECTS_DB file '$PROJECTS_DB' not found or empty." 10 60
            return 1
        fi

        local -a lines=()
        mapfile -t lines < "$PROJECTS_DB"

        local selected_project_path="$1"
        shift

        # With --filtered-notes only the notes visible in the main menu are offered.
        local restrict_to_filtered_notes=false
        local -A filtered_note_paths=()
        if [[ "${1:-}" == "--filtered-notes" ]]; then
            restrict_to_filtered_notes=true
            shift
            local filtered_note_line filtered_note_path
            for filtered_note_line in "$@"; do
                IFS='|' read -r _ filtered_note_path _ <<< "$filtered_note_line"
                [[ -n "$filtered_note_path" ]] && filtered_note_paths["$filtered_note_path"]=1
            done
        fi

        local selected_project
        selected_project=$(awk -F'|' -v path="$selected_project_path" '$2 == path { print NR; exit }' "$PROJECTS_DB")
        [[ -z "$selected_project" ]] && return 1
        ((selected_project--))

        local title path notes
        IFS='|' read -r title path notes <<< "${lines[selected_project]}"

        GOALS_NOTE_GLOB=""
        GOALS_NOTE_TAGFILTER=""

        local -a notes_arr=() candidates=() picked=() new_notes=()
        local -A picked_map=()
        local np new_notes_str tmp_db
        while true; do
            if [[ -z "$notes" ]]; then
                whiptail --msgbox "Selected project has no associated notes." 10 60
                return 1
            fi

            notes_arr=(); candidates=()
            IFS=',' read -ra notes_arr <<< "$notes"
            for np in "${notes_arr[@]}"; do
                [[ -z "$np" ]] && continue
                if [[ "$restrict_to_filtered_notes" == true && -z "${filtered_note_paths[$np]:-}" ]]; then
                    continue
                fi
                candidates+=("$np")
            done
            if (( ${#candidates[@]} == 0 )); then
                whiptail --msgbox "No linked notes match the current filter." 10 60
                return 1
            fi

            goals_pick_notes_multi "Choose Note to Dissociate" \
                "Choose notes to unlink from the project" \
                "__remove__" "Unlink the selected notes from the project" top \
                "${candidates[@]}" || return 1
            picked=("${GOALS_PICKED_PATHS[@]}")

            picked_map=()
            for np in "${picked[@]}"; do picked_map["$np"]=1; done
            new_notes=()
            for np in "${notes_arr[@]}"; do
                [[ -z "$np" ]] && continue
                [[ -z "${picked_map[$np]:-}" ]] && new_notes+=("$np")
            done
            new_notes_str=""
            (( ${#new_notes[@]} > 0 )) && new_notes_str=$(IFS=','; printf '%s' "${new_notes[*]}")

            lines[selected_project]="$title|$path|$new_notes_str"
            notes="$new_notes_str"

            tmp_db=$(mktemp) || return 1
            printf '%s\n' "${lines[@]}" > "$tmp_db"
            mv -- "$tmp_db" "$PROJECTS_DB" || { rm -f -- "$tmp_db"; return 1; }

            whiptail --msgbox "${#picked[@]} note(s) successfully dissociated from project." 10 60
            if [[ -z "$notes" ]]; then
                whiptail --msgbox "All notes have been dissociated from this project." 10 60
                break
            fi
        done
    }

    edit_plan() {
        #####################################
        # get selected project path as $1
        #####################################

        # Check if projects database exists and has entries
        [[ ! -f "$PROJECTS_DB" || ! -s "$PROJECTS_DB" ]] && {
            whiptail --msgbox "No projects found. Add at least one project and try again." 8 40 </dev/tty >/dev/tty
            return 1
        }

        save_to_projects_db() {
            local entry="${project_title}|${project_path}|"
            [[ -z "$project_title" || -z "$project_path" ]] && return

            if grep -Fxq -- "$entry" "$PROJECTS_DB" 2>/dev/null; then
                return 0  # already present
            fi

            printf '%s\n' "$entry" >> "$PROJECTS_DB"
        }

        # ============================================================
        # Babyrus - Goal / Project Manager
        #
        # Project file format:
        #
        # TYPE|ID|PARENT_ID|POSITION|STATUS|IMPORTANCE|CONTENT|COMMENT
        #
        # H|1|0|0|NS|N|Programming
        # H|2|1|0|IP|I|Bash
        # H|3|2|0|IP|VI|Whiptail
        # T|4|3|0|C|VI|create checklist menu->implement checklist
        # T|5|3|1|NS|I|support pagination->add prev/next
        #
        # TYPE:
        #   H = heading
        #   T = task
        #
        # STATUS:
        #   NS = not started
        #   IP = in progress
        #   PA = paused
        #   C  = completed
        #
        # IMPORTANCE:
        #   VI = very important
        #   I  = important
        #   N  = normal
        #   NI = not important
        #
        # ============================================================


        # ------------------------------------------------------------
        # Configuration
        # ------------------------------------------------------------

        PROJECT_FILE="$1"

        # Verify project file exists
        [[ ! -f "$PROJECT_FILE" ]] && {
            whiptail --msgbox "Project file not found: ${PROJECT_FILE}" 10 60
            return 1
        }    

        declare -a item_type
        declare -a item_id
        declare -a parent_id
        declare -a item_position
        declare -a item_status
        declare -a item_importance
        declare -a item_content
        declare -a item_comment

        # Calculated/effective status.
        #
        # For tasks:
        #     effective_status == stored status
        #
        # For leaf headings:
        #     effective_status == stored status
        #
        # For container headings:
        #     effective_status is calculated from children.
        #
        declare -a effective_status

        NEXT_ID=1

        # Return status/importance to their friendly names when displaying.
        status_name() {
            case "$1" in
                NS) printf '%s' "Not started" ;;
                IP) printf '%s' "In progress" ;;
                PA) printf '%s' "Paused" ;;
                C)  printf '%s' "Completed" ;;
                *)  printf '%s' "$1" ;;
            esac
        }

        importance_name() {
            case "$1" in
                VI) printf '%s' "Very important" ;;
                I)  printf '%s' "Important" ;;
                N)  printf '%s' "Normal" ;;
                NI) printf '%s' "Not important" ;;
                *)  printf '%s' "$1" ;;
            esac
        }


        # ------------------------------------------------------------
        # Validation helpers
        # ------------------------------------------------------------

        valid_status() {
            case "$1" in
                NS|IP|PA|C) return 0 ;;
                *) return 1 ;;
            esac
        }

        valid_importance() {
            case "$1" in
                VI|I|N|NI) return 0 ;;
                *) return 1 ;;
            esac
        }

        valid_type() {
            [[ "$1" == "H" || "$1" == "T" ]]
        }

        # Find array index for persistent item ID.
        #
        # Returns:
        #   global variable RESULT_INDEX
        #
        find_index_by_id() {
            local wanted_id="$1"
            local i

            RESULT_INDEX=-1

            for i in "${!item_id[@]}"; do
                if [[ "${item_id[i]}" == "$wanted_id" ]]; then
                    RESULT_INDEX=$i
                    return 0
                fi
            done

            return 1
        }


        # ------------------------------------------------------------
        # Project loading
        # ------------------------------------------------------------

        load_project() {
            local file="${1:-$PROJECT_FILE}"
            local line
            local type id parent position status importance content comment

            item_type=()
            item_id=()
            parent_id=()
            item_position=()
            item_status=()
            item_importance=()
            item_content=()
            item_comment=()
            effective_status=()

            NEXT_ID=1

            [[ -f "$file" ]] || return 0

            while IFS= read -r line || [[ -n "$line" ]]; do

                # Ignore empty lines.
                [[ -z "$line" ]] && continue

                # Comments may be useful during development.
                [[ "$line" == \#* ]] && continue

                IFS='|' read -r type id parent position status importance content comment <<< "$line"

                if [[ -z "$content" ]]; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "Invalid line:\n\n$line" \
                        10 70
                    return 1
                fi

                if ! valid_type "$type"; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "Invalid item type '$type'.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                if ! valid_status "$status"; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "Invalid status '$status'.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                if ! valid_importance "$importance"; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "Invalid importance '$importance'.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                if [[ "$content" == *"|"* ]]; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "The content contains '|', which is reserved as a field separator.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                if [[ "$comment" == *"|"* ]]; then
                    whiptail \
                        --title "Invalid Project File" \
                        --msgbox "The comment contains '|', which is reserved as a field separator.\n\nLine:\n$line" \
                        10 70
                    return 1
                fi

                item_type+=("$type")
                item_id+=("$id")
                parent_id+=("$parent")
                item_position+=("$position")
                item_status+=("$status")
                item_importance+=("$importance")
                item_content+=("$content")
                item_comment+=("$comment")

                effective_status+=("$status")

                if [[ "$id" =~ ^[0-9]+$ ]]; then
                    (( id >= NEXT_ID )) && NEXT_ID=$((id + 1))
                fi

            done < "$file"

            validate_project || return 1

            calculate_all_statuses
        }


        # ------------------------------------------------------------
        # Structural validation
        # ------------------------------------------------------------

        validate_project() {
            local i parent_index

            for i in "${!item_id[@]}"; do

                # IDs must be numeric.
                if ! [[ "${item_id[i]}" =~ ^[0-9]+$ ]]; then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Item ID '${item_id[i]}' is not numeric." \
                        8 60
                    return 1
                fi

                # Parent 0 means root.
                if [[ "${parent_id[i]}" == "0" ]]; then

                    # Root tasks are not allowed.
                    if [[ "${item_type[i]}" == "T" ]]; then
                        whiptail \
                            --title "Invalid Project" \
                            --msgbox "Task '${item_content[i]}' has no heading parent." \
                            8 70
                        return 1
                    fi

                    continue
                fi

                find_index_by_id "${parent_id[i]}"

                if (( RESULT_INDEX < 0 )); then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Item '${item_content[i]}' refers to missing parent ID '${parent_id[i]}'." \
                        8 70
                    return 1
                fi

                parent_index=$RESULT_INDEX

                # Tasks can only be children of headings.
                if [[ "${item_type[i]}" == "T" &&
                    "${item_type[parent_index]}" != "H" ]]; then

                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Task '${item_content[i]}' is under another task.\n\nTasks may only belong to headings." \
                        10 70
                    return 1
                fi

                # Detect immediate self-parent.
                if [[ "${item_id[i]}" == "${parent_id[i]}" ]]; then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "Item '${item_content[i]}' is its own parent." \
                        8 70
                    return 1
                fi
            done

            # Detect circular parent chains.
            for i in "${!item_id[@]}"; do
                if ! hierarchy_is_valid_from "$i"; then
                    whiptail \
                        --title "Invalid Project" \
                        --msgbox "A circular hierarchy was detected involving:\n\n${item_content[i]}" \
                        10 70
                    return 1
                fi
            done

            return 0
        }


        hierarchy_is_valid_from() {
            local start_index="$1"
            local current_index="$start_index"
            local parent
            local -a visited=()

            while :; do

                # If we've seen this item already, there is a cycle.
                for parent in "${visited[@]}"; do
                    [[ "$parent" == "$current_index" ]] && return 1
                done

                visited+=("$current_index")

                parent="${parent_id[current_index]}"

                [[ "$parent" == "0" ]] && return 0

                find_index_by_id "$parent"
                (( RESULT_INDEX >= 0 )) || return 1

                current_index=$RESULT_INDEX
            done
        }


        # ------------------------------------------------------------
        # Tree helpers
        # ------------------------------------------------------------
        get_children() {
            local wanted_parent="$1"
            local i
            local position
            local child_index

            CHILDREN=()

            # Output indices sorted by position.
            while IFS=$'\t' read -r position child_index; do
                [[ -n "$child_index" ]] && CHILDREN+=("$child_index")
            done < <(
                for i in "${!item_id[@]}"; do
                    if [[ "${parent_id[i]}" == "$wanted_parent" ]]; then
                        printf '%s\t%s\n' "${item_position[i]}" "$i"
                    fi
                done |
                sort -n -k1,1 -k2,2
            )
        }

        get_children_old() {
            local wanted_parent="$1"
            local i

            CHILDREN=()

            # Output indices sorted by position.
            while IFS=$'\t' read -r position index; do
                [[ -n "$index" ]] && CHILDREN+=("$index")
            done < <(
                for i in "${!item_id[@]}"; do
                    if [[ "${parent_id[i]}" == "$wanted_parent" ]]; then
                        printf '%s\t%s\n' "${item_position[i]}" "$i"
                    fi
                done |
                sort -n -k1,1 -k2,2
            )
        }


        is_container() {
            local index="$1"

            get_children "${item_id[index]}"
            (( ${#CHILDREN[@]} > 0 ))
        }


        get_depth() {
            local index="$1"
            local depth=0
            local current="$index"
            local parent

            while [[ "${parent_id[current]}" != "0" ]]; do
                parent="${parent_id[current]}"

                find_index_by_id "$parent"
                (( RESULT_INDEX >= 0 )) || {
                    printf '%s' "$depth"
                    return
                }

                current=$RESULT_INDEX
                ((depth++))
            done

            printf '%s' "$depth"
        }


        # ------------------------------------------------------------
        # Status calculation
        # ------------------------------------------------------------

        calculate_status() {
            local index="$1"
            local type="${item_type[index]}"
            local status
            local child
            local child_status

            # Tasks always use their stored status.
            if [[ "$type" == "T" ]]; then
                effective_status[index]="${item_status[index]}"
                printf '%s' "${effective_status[index]}"
                return
            fi

            # Find children.
            get_children "${item_id[index]}"

            # Leaf heading: manually controlled.
            if (( ${#CHILDREN[@]} == 0 )); then
                effective_status[index]="${item_status[index]}"
                printf '%s' "${effective_status[index]}"
                return
            fi

            local has_ns=0
            local has_ip=0
            local has_pa=0
            local has_c=0

            # Container heading: calculate recursively.
            for child in "${CHILDREN[@]}"; do
                child_status="$(calculate_status "$child")"

                case "$child_status" in
                    NS) has_ns=1 ;;
                    IP) has_ip=1 ;;
                    PA) has_pa=1 ;;
                    C)  has_c=1 ;;
                esac
            done

            # Aggregation rules:
            #
            # Any active work => IN PROGRESS
            # Otherwise any paused work => PAUSED
            # Completed + not-started => IN PROGRESS
            # All completed => COMPLETED
            # All not-started => NOT STARTED

            if (( has_ip )); then
                status="IP"

            elif (( has_pa )); then
                status="PA"

            elif (( has_c && has_ns )); then
                status="IP"

            elif (( has_c )); then
                status="C"

            else
                status="NS"
            fi

            effective_status[index]="$status"
            printf '%s' "$status"
        }


        calculate_all_statuses() {
            local i

            effective_status=()

            for i in "${!item_id[@]}"; do
                effective_status+=("${item_status[i]}")
            done

            # Calculate every item. Recursive calls ensure that children
            # are resolved before their parents.
            for i in "${!item_id[@]}"; do
                calculate_status "$i" >/dev/null
            done
        }


        # ------------------------------------------------------------
        # Status / importance UI
        # ------------------------------------------------------------

        select_status() {
            local current="$1"

            whiptail \
                --title "Change Status" \
                --menu "Select status:" \
                15 60 6 \
                "NS" "Not started" \
                "IP" "In progress" \
                "PA" "Paused" \
                "C"  "Completed" \
                3>&1 1>&2 2>&3
        }


        select_importance() {
            whiptail \
                --title "Change Importance" \
                --menu "Select importance:" \
                15 60 6 \
                "VI" "Very important" \
                "I"  "Important" \
                "N"  "Normal" \
                "NI" "Not important" \
                3>&1 1>&2 2>&3
        }


        # ------------------------------------------------------------
        # Input helpers
        # ------------------------------------------------------------

        add_heading() {
            local parent="$1"
            local text

            text="$(
                whiptail \
                    --title "Add Heading" \
                    --inputbox "Heading name:" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$text" ]] && return

            if [[ "$text" == *"|"* ]]; then
                whiptail --msgbox "The heading cannot contain '|'.\n\nIt is reserved by the project file format." 9 70
                return
            fi

            add_item "H" "$parent" "$text"
        }


        add_task() {
            local parent="$1"
            local task
            local plan
            local content

            # Parent must be a heading.
            find_index_by_id "$parent" || return

            if [[ "${item_type[RESULT_INDEX]}" != "H" ]]; then
                whiptail \
                    --title "Invalid Parent" \
                    --msgbox "Tasks can only be added under headings." \
                    8 60
                return
            fi

            task="$(
                whiptail \
                    --title "Add Task" \
                    --inputbox "Task:" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$task" ]] && return

            plan="$(
                whiptail \
                    --title "Add Task Plan" \
                    --inputbox "Plan for:\n\n$task" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            if [[ -n "$plan" ]]; then
                content="${task}->${plan}"
            else
                content="$task"
            fi

            if [[ "$content" == *"|"* ]]; then
                whiptail \
                    --msgbox "Task or plan cannot contain '|'.\n\nIt is reserved by the project file format." \
                    9 70
                return
            fi

            add_item "T" "$parent" "$content"
        }

        find_todo_heading() {
            local i

            TODO_HEADING_ID=""

            for i in "${!item_id[@]}"; do
                if [[ "${item_type[i]}" == "H" &&
                    "${parent_id[i]}" == "0" &&
                    "${item_content[i]}" == "TODO" ]]; then

                    TODO_HEADING_ID="${item_id[i]}"
                    return 0
                fi
            done

            return 1
        }


        find_todo_date_heading() {
            local todo_id="$1"
            local todo_date="$2"
            local child

            TODO_DATE_HEADING_ID=""

            get_children "$todo_id"

            for child in "${CHILDREN[@]}"; do
                if [[ "${item_type[child]}" == "H" &&
                    "${item_content[child]}" == "$todo_date" ]]; then

                    TODO_DATE_HEADING_ID="${item_id[child]}"
                    return 0
                fi
            done

            return 1
        }


        next_todo_task_number() {
            local date_heading_id="$1"
            local child
            local number
            local max=0

            get_children "$date_heading_id"

            for child in "${CHILDREN[@]}"; do
                [[ "${item_type[child]}" == "T" ]] || continue

                if number="$(get_number_prefix "${item_content[child]}")"; then
                    # Treat the prefix as decimal, even if it has leading zeroes.
                    number=$((10#$number))

                    (( number > max )) && max="$number"
                fi
            done

            printf '%s' "$((max + 1))"
        }

        find_rules_for_today_heading() {
            local i

            RULES_FOR_TODAY_ID=""

            for i in "${!item_id[@]}"; do
                if [[ "${item_type[i]}" == "H" &&
                    "${parent_id[i]}" == "0" &&
                    "${item_content[i]}" == "RULES FOR TODAY" ]]; then

                    RULES_FOR_TODAY_ID="${item_id[i]}"
                    return 0
                fi
            done

            return 1
        }


        find_rules_for_today_date_heading() {
            local rules_id="$1"
            local rules_date="$2"
            local child

            RULES_FOR_TODAY_DATE_ID=""

            get_children "$rules_id"

            for child in "${CHILDREN[@]}"; do
                if [[ "${item_type[child]}" == "H" &&
                    "${item_content[child]}" == "$rules_date" ]]; then

                    RULES_FOR_TODAY_DATE_ID="${item_id[child]}"
                    return 0
                fi
            done

            return 1
        }


        next_rules_for_today_task_number() {
            local date_heading_id="$1"
            local child
            local number
            local max=0

            get_children "$date_heading_id"

            for child in "${CHILDREN[@]}"; do
                [[ "${item_type[child]}" == "T" ]] || continue

                if number="$(get_number_prefix "${item_content[child]}")"; then
                    number=$((10#$number))
                    (( number > max )) && max="$number"
                fi
            done

            printf '%s' "$((max + 1))"
        }


        add_rules_for_today_item() {
            local rules_id
            local rules_date
            local date_heading_id
            local rules_number
            local task
            local content

            # Today's date.
            rules_date="$(date '+%A %-d %B %Y')"

            # ------------------------------------------------------------
            # Find or create the top-level RULES FOR TODAY heading.
            # ------------------------------------------------------------

            if find_rules_for_today_heading; then
                rules_id="$RULES_FOR_TODAY_ID"
            else
                rules_id="$NEXT_ID"
                add_item "H" "0" "RULES FOR TODAY"
            fi

            # ------------------------------------------------------------
            # Find or create today's date heading.
            # ------------------------------------------------------------

            if find_rules_for_today_date_heading "$rules_id" "$rules_date"; then
                date_heading_id="$RULES_FOR_TODAY_DATE_ID"
            else
                date_heading_id="$NEXT_ID"
                add_item "H" "$rules_id" "$rules_date"
            fi

            # ------------------------------------------------------------
            # Ask for the rule.
            # ------------------------------------------------------------

            task="$(
                whiptail \
                    --title "Add Rule for Today" \
                    --inputbox "Rule for $rules_date:" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$task" ]] && return

            if [[ "$task" == *"|"* ]]; then
                whiptail \
                    --title "Invalid Rule" \
                    --msgbox "The rule cannot contain '|'.\n\nIt is reserved by the project file format." \
                    9 70
                return
            fi

            # ------------------------------------------------------------
            # Determine next number for today's rules.
            # ------------------------------------------------------------

            rules_number="$(next_rules_for_today_task_number "$date_heading_id")"
            content="${rules_number}. ${task}"

            add_item "T" "$date_heading_id" "$content"

            # Keep today's rules numerically sorted.
            sort_children "$date_heading_id"

            # Keep the special root headings in their required order.
            sort_children "0"
        }

        add_todo_item() {
            local todo_id
            local todo_date
            local date_heading_id
            local todo_number
            local task
            local content

            # Today's date, for example:
            # Tuesday 29 September 2026
            todo_date="$(date '+%A %-d %B %Y')"

            # ------------------------------------------------------------
            # Find or create the top-level TODO heading.
            # ------------------------------------------------------------

            if find_todo_heading; then
                todo_id="$TODO_HEADING_ID"
            else
                # add_item() increments NEXT_ID, so capture the new
                # heading's ID before calling it.
                todo_id="$NEXT_ID"
                add_item "H" "0" "TODO"
            fi

            # ------------------------------------------------------------
            # Find or create today's date heading under TODO.
            # ------------------------------------------------------------

            if find_todo_date_heading "$todo_id" "$todo_date"; then
                date_heading_id="$TODO_DATE_HEADING_ID"
            else
                # Capture the ID that add_item() will assign.
                date_heading_id="$NEXT_ID"
                add_item "H" "$todo_id" "$todo_date"
            fi

            # ------------------------------------------------------------
            # Ask for the TODO task text.
            # ------------------------------------------------------------

            task="$(
                whiptail \
                    --title "Add TODO Item" \
                    --inputbox "TODO item for $todo_date:" \
                    10 70 \
                    "" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$task" ]] && return

            if [[ "$task" == *"|"* ]]; then
                whiptail \
                    --title "Invalid TODO Item" \
                    --msgbox "The TODO item cannot contain '|'.\n\nIt is reserved by the project file format." \
                    9 70
                return
            fi

            # ------------------------------------------------------------
            # Determine the next number under today's date heading.
            # ------------------------------------------------------------

            todo_number="$(next_todo_task_number "$date_heading_id")"
            content="${todo_number}. ${task}"

            add_item "T" "$date_heading_id" "$content"

            # ------------------------------------------------------------
            # Keep today's TODO tasks sorted by their numeric prefix.
            # ------------------------------------------------------------

            sort_children "$date_heading_id"

            # Keep TODO as the first root-level heading.
            sort_children "0"            
        }        


        add_item() {
            local type="$1"
            local parent="$2"
            local content="$3"

            local position

            position="$(next_position "$parent")"

            item_type+=("$type")
            item_id+=("$NEXT_ID")
            parent_id+=("$parent")
            item_position+=("$position")

            # New items use default status and importance.
            item_status+=("NS")
            item_importance+=("N")

            item_content+=("$content")
            item_comment+=("")
            effective_status+=("NS")

            ((NEXT_ID++))

            calculate_all_statuses
        }


        next_position() {
            local parent="$1"
            local max=-1
            local i

            for i in "${!item_id[@]}"; do
                if [[ "${parent_id[i]}" == "$parent" ]]; then
                    (( item_position[i] > max )) && max="${item_position[i]}"
                fi
            done

            printf '%s' "$((max + 1))"
        }


        # ------------------------------------------------------------
        # Edit item
        # ------------------------------------------------------------

        edit_text() {
            local index="$1"
            local new_text

            new_text="$(
                whiptail \
                    --title "Edit Text" \
                    --inputbox \
                    "Current text:" \
                    10 80 \
                    "${item_content[index]}" \
                    3>&1 1>&2 2>&3
            )" || return

            [[ -z "$new_text" ]] && return

            if [[ "$new_text" == *"|"* ]]; then
                whiptail \
                    --title "Invalid Text" \
                    --msgbox "'|' cannot be used because it is the project-file field separator." \
                    8 70
                return
            fi

            item_content[index]="$new_text"
        }

    edit_task() {
        local index="$1"
        local task plan

        if [[ "${item_content[index]}" == *"->"* ]]; then
            task="${item_content[index]%%->*}"
            plan="${item_content[index]#*->}"
        else
            task="${item_content[index]}"
            plan=""
        fi

        task="$(
            whiptail \
                --title "Edit Task" \
                --inputbox "Task:" \
                10 70 \
                "$task" \
                3>&1 1>&2 2>&3
        )" || return

        # Validate task
        if [[ -z "$task" || "$task" == *"|"* ]]; then
            whiptail \
                --title "Invalid Task" \
                --msgbox "Task cannot be blank or contain the | character." \
                8 60
            return
        fi

        plan="$(
            whiptail \
                --title "Edit Plan" \
                --inputbox "Plan:" \
                10 70 \
                "$plan" \
                3>&1 1>&2 2>&3
        )" || return

        # Validate plan
        if [[ "$plan" == *"|"* ]]; then
            whiptail \
                --title "Invalid Plan" \
                --msgbox "Plan cannot contain the | character." \
                8 60
            return
        fi

        # deal with case where there is no ->
        if [[ -n "$plan" ]]; then
            item_content[index]="${task}->${plan}"
        else
            item_content[index]="$task"
        fi
    }

        edit_comment() {            
            local index="$1"
            local existing_comment="${item_comment[index]}"
            local tempfile
            local comment

            if ! tempfile=$(mktemp); then
                return 1
            fi

            # Ensure cleanup on return or exit
            trap 'rm -f -- "$tempfile"' EXIT RETURN

            # Populate with existing comment
            if [[ -n "$existing_comment" ]]; then
                existing_comment="${existing_comment//\[N\]/$'\n'}"
                if ! printf '%s' "$existing_comment" > "$tempfile"; then
                    return 1
                fi
            fi

            while :; do
                if ! "$DEFAULT_EDITOR" "$tempfile"; then
                    return 1
                fi

                # Read file contents without losing trailing newlines
                comment=$(cat "$tempfile"; printf 'x')
                comment="${comment%x}"

                # Strip the trailing newline added by nano/editor if present
                comment="${comment%$'\n'}"

                # Check for literal reserved string
                if [[ "$comment" == *'[N]'* ]]; then
                    whiptail \
                        --title "Invalid Comment" \
                        --msgbox "The sequence [N] is reserved for newlines and cannot be used in a comment." \
                        8 70
                    continue
                fi

                # Convert remaining newlines to [N]
                comment="${comment//$'\n'/[N]}"

                item_comment[index]="$comment"
                return 0
            done
        }

        view_comment() {
            local index="$1"
            local comment="${item_comment[index]}"

            [[ -n "$comment" ]] || comment="No comment has been added."

            comment="${comment//\[N\]/$'\n'}"

            whiptail \
                --title "Comment" \
                --msgbox "$comment" \
                20 80
        }

        edit_comment_old() {
            local index="$1"
            local comment

            comment="$(
                whiptail \
                    --title "Comment: ${item_content[index]}" \
                    --inputbox "Comment (optional):" \
                    14 90 \
                    "${item_comment[index]}" \
                    3>&1 1>&2 2>&3
            )" || return

            if [[ "$comment" == *"|"* || "$comment" == *$'\n'* ]]; then
                whiptail --msgbox "A comment cannot contain '|' or newline.\n\nThey are reserved by the project file format." 9 70
                return
            fi

            item_comment[index]="$comment"
        }


        view_comment_old() {
            local index="$1"
            local comment="${item_comment[index]}"

            [[ -n "$comment" ]] || comment="No comment has been added."

            whiptail \
                --title "Comment: ${item_content[index]}" \
                --msgbox "$comment" \
                16 90
        }

        # edit_task() {
        #     local index="$1"
        #     local task plan

        #     if [[ "${item_content[index]}" == *"->"* ]]; then
        #         task="${item_content[index]%%->*}"
        #         plan="${item_content[index]#*->}"
        #     else
        #         task="${item_content[index]}"
        #         plan=""
        #     fi

        #     task="$(
        #         whiptail \
        #             --title "Edit Task" \
        #             --inputbox "Task:" \
        #             10 70 \
        #             "$task" \
        #             3>&1 1>&2 2>&3
        #     )" || return

        #     plan="$(
        #         whiptail \
        #             --title "Edit Plan" \
        #             --inputbox "Plan:" \
        #             10 70 \
        #             "$plan" \
        #             3>&1 1>&2 2>&3
        #     )" || return

        #     item_content[index]="${task}->${plan}"
        # }


        # ------------------------------------------------------------
        # Move
        # ------------------------------------------------------------

        is_descendant_of() {
            local index="$1"
            local ancestor_id="$2"
            local current="$index"

            while [[ "${parent_id[current]}" != "0" ]]; do

                if [[ "${parent_id[current]}" == "$ancestor_id" ]]; then
                    return 0
                fi

                find_index_by_id "${parent_id[current]}"
                (( RESULT_INDEX >= 0 )) || return 1

                current=$RESULT_INDEX
            done

            return 1
        }


        choose_move_destination() {
            local moving_index="$1"
            local moving_type="${item_type[moving_index]}"
            local i
            local depth
            local indent
            local label
            local options=()

            # Root destination is allowed for headings only.
            if [[ "$moving_type" == "H" ]]; then
                options+=("0" "[ROOT]")
            fi

            for i in "${!item_id[@]}"; do

                # Can't move under itself.
                [[ "$i" == "$moving_index" ]] && continue

                # Destination must be a heading.
                [[ "${item_type[i]}" == "H" ]] || continue

                # A heading cannot be moved under one of its descendants.
                if [[ "$moving_type" == "H" ]]; then
                    if is_descendant_of "$i" "${item_id[moving_index]}"; then
                        continue
                    fi
                fi

                depth="$(get_depth "$i")"
                indent=""

                for ((j=0; j<depth; j++)); do
                    indent+="    "
                done

                label="${indent}${item_content[i]}"

                options+=("${item_id[i]}" "$label")
            done

            (( ${#options[@]} == 0 )) && return 1

            whiptail \
                --title "Move Item" \
                --menu \
                "Move '${item_content[moving_index]}' under:" \
                22 90 15 \
                "${options[@]}" \
                3>&1 1>&2 2>&3
        }


        move_item() {
            local index="$1"
            local old_parent="${parent_id[index]}"
            local new_parent
            local new_position

            new_parent="$(choose_move_destination "$index")" || return

            # Guard--if old_parent is the same as new_parent, no nothing--no move required!
            [[ "$old_parent" == "$new_parent" ]] && return            

            # Tasks cannot be moved to root.
            if [[ "${item_type[index]}" == "T" && "$new_parent" == "0" ]]; then
                whiptail \
                    --title "Invalid Move" \
                    --msgbox "Tasks must belong to a heading." \
                    8 60
                return
            fi

            new_position="$(next_position "$new_parent")"

            parent_id[index]="$new_parent"
            item_position[index]="$new_position"

            normalize_positions "$old_parent"
            normalize_positions "$new_parent"

            calculate_all_statuses
        }


        normalize_positions() {
            local parent="$1"
            local -a children
            local i position=0

            get_children "$parent"
            children=("${CHILDREN[@]}")

            for i in "${children[@]}"; do
                item_position[i]="$position"
                ((position++))
            done
        }

        # ------------------------------------------------------------
        # Reorder: move an item before/after a sibling of the same kind
        # ------------------------------------------------------------

        # Present the three move modes (before / after / under another heading).
        move_item_menu() {
            local index="$1"
            local action
            local type="${item_type[index]}"
            local kind

            if [[ "$type" == "H" ]]; then
                kind="heading"
            else
                kind="task"
            fi

            while :; do

                action="$(
                    whiptail \
                        --title "Move: ${item_content[index]}" \
                        --cancel-button "Back" \
                        --menu \
                        "Choose how to move this $kind:" \
                        18 78 10 \
                        "BEFORE" "Move before another $kind on this level" \
                        "AFTER"  "Move after another $kind on this level" \
                        "PARENT" "Move under another heading" \
                        "BACK"   "Back" \
                        3>&1 1>&2 2>&3
                )" || return

                case "$action" in

                    BEFORE)
                        move_item_relative "$index" "before"
                        return
                        ;;

                    AFTER)
                        move_item_relative "$index" "after"
                        return
                        ;;

                    PARENT)
                        move_item "$index"
                        return
                        ;;

                    BACK)
                        return
                        ;;
                esac
            done
        }


        # Move item $index before/after (mode) a same-type sibling on the
        # same level. Sibling positions are reassigned sequentially so the
        # position values on the level stay unique and consecutive.
        move_item_relative() {
            local index="$1"
            local mode="$2"   # "before" or "after"
            local parent="${parent_id[index]}"
            local type="${item_type[index]}"
            local kind
            local child
            local n=0
            local target
            local target_index=-1
            local inserted=0
            local pos=0
            local -a candidates=()
            local -a new_order=()

            if [[ "$type" == "H" ]]; then
                kind="heading"
            else
                kind="task"
            fi

            get_children "$parent"

            # Candidates: siblings of the same type, excluding the item
            # itself, in their current (position-sorted) order.
            for child in "${CHILDREN[@]}"; do
                [[ "$child" == "$index" ]] && continue
                [[ "${item_type[child]}" != "$type" ]] && continue

                ((n++))
                candidates+=(
                    "${item_id[child]}"
                    "$n) ${item_content[child]}"
                )
            done

            if (( n == 0 )); then
                whiptail \
                    --title "Move" \
                    --msgbox \
                    "There is no other $kind on this level to move next to." \
                    8 60
                return
            fi

            target="$(
                whiptail \
                    --title "Move $mode" \
                    --cancel-button "Back" \
                    --menu \
                    "Move '${item_content[index]}' $mode which item?" \
                    18 180 10 \
                    "${candidates[@]}" \
                    3>&1 1>&2 2>&3
            )" || return

            # Resolve the chosen item ID back to an index.
            find_index_by_id "$target"
            (( RESULT_INDEX >= 0 )) && target_index=$RESULT_INDEX

            if (( target_index < 0 )); then
                return
            fi

            # Rebuild the sibling order of the whole level minus the moving
            # item, then splice it back in before/after the target.
            for child in "${CHILDREN[@]}"; do
                [[ "$child" == "$index" ]] && continue

                if [[ "$child" == "$target_index" ]]; then
                    if [[ "$mode" == "before" ]]; then
                        new_order+=("$index" "$child")
                    else
                        new_order+=("$child" "$index")
                    fi
                    inserted=1
                else
                    new_order+=("$child")
                fi
            done

            (( inserted )) || return

            # Reassign positions sequentially, keeping the level consistent
            # exactly as normalize_positions() does.
            pos=0
            for child in "${new_order[@]}"; do
                item_position[child]="$pos"
                ((pos++))
            done
        }


        # ------------------------------------------------------------
        # Delete
        # ------------------------------------------------------------

        collect_descendants() {
            local root_index="$1"
            local child

            DELETE_INDICES+=("$root_index")

            get_children "${item_id[root_index]}"

            for child in "${CHILDREN[@]}"; do
                collect_descendants "$child"
            done
        }


        delete_item() {
            local index="$1"
            local id="${item_id[index]}"
            local old_parent="${parent_id[index]}"
            local count
            local i

            DELETE_INDICES=()
            collect_descendants "$index"

            count="${#DELETE_INDICES[@]}"

            if (( count > 1 )); then
                if ! whiptail \
                    --title "Delete Heading" \
                    --yesno \
                    "'${item_content[index]}' contains $((count - 1)) child item(s).\n\nDelete the entire subtree?" \
                    12 70; then
                    return
                fi
            else
                if ! whiptail \
                    --title "Delete Item" \
                    --yesno \
                    "Delete '${item_content[index]}'?" \
                    10 60; then
                    return
                fi
            fi

            # Mark items to delete by their IDs.
            declare -A delete_ids=()

            for i in "${DELETE_INDICES[@]}"; do
                delete_ids["${item_id[i]}"]=1
            done

            local -a new_type=()
            local -a new_id=()
            local -a new_parent=()
            local -a new_position=()
            local -a new_status=()
            local -a new_importance=()
            local -a new_content=()
            local -a new_comment=()
            local -a new_effective=()

            for i in "${!item_id[@]}"; do

                if [[ -n "${delete_ids[${item_id[i]}]+x}" ]]; then
                    continue
                fi

                new_type+=("${item_type[i]}")
                new_id+=("${item_id[i]}")
                new_parent+=("${parent_id[i]}")
                new_position+=("${item_position[i]}")
                new_status+=("${item_status[i]}")
                new_importance+=("${item_importance[i]}")
                new_content+=("${item_content[i]}")
                new_comment+=("${item_comment[i]}")
                new_effective+=("${effective_status[i]}")
            done

            item_type=("${new_type[@]}")
            item_id=("${new_id[@]}")
            parent_id=("${new_parent[@]}")
            item_position=("${new_position[@]}")
            item_status=("${new_status[@]}")
            item_importance=("${new_importance[@]}")
            item_content=("${new_content[@]}")
            item_comment=("${new_comment[@]}")
            effective_status=("${new_effective[@]}")

            normalize_positions "$old_parent"

            calculate_all_statuses

            # Avoid unused-variable warning in some shells.
            : "$id"
        }


        # ------------------------------------------------------------
        # Save
        # ------------------------------------------------------------

        save_project() {
            local file="$PROJECT_FILE"
            local tmp="${file}.tmp"
            local i

            calculate_all_statuses

            {
                for i in "${!item_id[@]}"; do

                    # Store EFFECTIVE status.
                    #
                    # This means the saved file always reflects the current
                    # calculated status of container headings.
                    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
                        "${item_type[i]}" \
                        "${item_id[i]}" \
                        "${parent_id[i]}" \
                        "${item_position[i]}" \
                        "${effective_status[i]}" \
                        "${item_importance[i]}" \
                        "${item_content[i]}" \
                        "${item_comment[i]}"
                done
            } > "$tmp" || {
                rm -f "$tmp"
                whiptail \
                    --title "Save Error" \
                    --msgbox "Unable to write temporary project file:\n\n$tmp" \
                    10 70
                return 1
            }

            if ! mv -- "$tmp" "$file"; then
                rm -f "$tmp"
                whiptail \
                    --title "Save Error" \
                    --msgbox "Unable to replace project file:\n\n$file" \
                    10 70
                return 1
            fi

            save_to_projects_db || {
                rm -f "$tmp" "$file"
                whiptail \
                    --title "Save Error" \
                    --msgbox "Unable to save entry to projects database:\n\n$file" \
                    10 70
                return 1            
            }

            return 0
        }


        # ------------------------------------------------------------
        # Tree rendering
        # ------------------------------------------------------------

        status_symbol() {
            case "$1" in
                NS) printf '%s' "○" ;;
                IP) printf '%s' "▶" ;;
                PA) printf '%s' "Ⅱ" ;;
                C)  printf '%s' "✓" ;;
                *)  printf '%s' "?" ;;
            esac
        }


        importance_symbol() {
            case "$1" in
                VI) printf '%s' "!!" ;;
                I)  printf '%s' "!" ;;
                N)  printf '%s' "-" ;;
                NI) printf '%s' "." ;;
                *)  printf '%s' "?" ;;
            esac
        }


        format_item_label() {
            local index="$1"
            local depth="$2"
            local indent=""
            local kind
            local status
            local importance

            for ((j=0; j<depth; j++)); do
                indent+="    "
            done

            status="${effective_status[index]}"
            importance="${item_importance[index]}"

            if [[ "${item_type[index]}" == "H" ]]; then
                kind="◆"
            else
                kind="•"
            fi

            printf '%s%s %s %s %s' \
                "$indent" \
                "$kind" \
                "$(status_symbol "$status")" \
                "$(importance_symbol "$importance")" \
                "${item_content[index]}"
        }


        build_tree_options() {
            TREE_OPTIONS=()

            build_tree_options_from_parent "0"
        }


        build_tree_options_from_parent() {
            local wanted_parent="$1"
            local child
            local depth
            local label

            get_children "$wanted_parent"

            for child in "${CHILDREN[@]}"; do
                depth="$(get_depth "$child")"
                label="$(format_item_label "$child" "$depth")"

                TREE_OPTIONS+=(
                    "${item_id[child]}"
                    "$([[ ${#label} -gt 155 ]] && printf '%s...' "${label:0:157}" || printf '%s' "$label")"
                )

                # Only headings can have children.
                if [[ "${item_type[child]}" == "H" ]]; then
                    build_tree_options_from_parent "${item_id[child]}"
                fi
            done
        }


        render_tree() {
            local selected_id

            build_tree_options

            if (( ${#TREE_OPTIONS[@]} == 0 )); then
                whiptail \
                    --title "Project Goals" \
                    --msgbox "This project contains no goals yet." \
                    8 60
                return 1
            fi

            selected_id="$(
                whiptail \
                    --title "Project Goals" \
                    --cancel-button "Back" \
                    --menu \
                    "Select an item:" \
                    24 110 17 \
                    "${TREE_OPTIONS[@]}" \
                    3>&1 1>&2 2>&3
            )" || return 1

            find_index_by_id "$selected_id"

            if (( RESULT_INDEX < 0 )); then
                return 1
            fi

            ITEM_SELECTED_INDEX=$RESULT_INDEX

            return 0
        }


        # ------------------------------------------------------------
        # Add menu
        # ------------------------------------------------------------

        add_menu() {
            local destination

            destination="$(
                whiptail \
                    --title "Add" \
                    --menu \
                    "What would you like to add?" \
                    12 60 4 \
                    "H" "Heading" \
                    "T" "Task" \
                    3>&1 1>&2 2>&3
            )" || return

            if [[ "$destination" == "H" ]]; then
                add_heading "0"
                return
            fi

            if [[ "$destination" == "T" ]]; then
                # A task needs a heading.
                select_heading_for_parent "0" || return
                add_task "$SELECTED_HEADING_ID"
            fi
        }

        select_heading_for_parent() {
            local parent="$1"

            HEADING_OPTIONS=()

            build_heading_options_from_parent "$parent"

            (( ${#HEADING_OPTIONS[@]} == 0 )) && {
                whiptail \
                    --title "No Headings" \
                    --msgbox "There are no headings available here." \
                    8 60
                return 1
            }

            SELECTED_HEADING_ID="$(
                whiptail \
                    --title "Select Heading" \
                    --menu \
                    "Select the heading:" \
                    22 90 15 \
                    "${HEADING_OPTIONS[@]}" \
                    3>&1 1>&2 2>&3
            )" || return 1

            return 0
        }

        build_heading_options_from_parent() {
            local wanted_parent="$1"
            local child
            local depth
            local label

            get_children "$wanted_parent"

            for child in "${CHILDREN[@]}"; do

                [[ "${item_type[child]}" == "H" ]] || continue

                depth="$(get_depth "$child")"
                label="$(format_item_label "$child" "$depth")"

                HEADING_OPTIONS+=(
                    "${item_id[child]}"
                    "$label"
                )

                build_heading_options_from_parent "${item_id[child]}"
            done
        }

        # -------------------------------------------------------------
        # Sort children  based on item's numerical prefix.
        # eg. 1) heading or 1. task
        # Sorts parent's immediate children either headings or tasks.
        # -------------------------------------------------------------

        # Return the numeric prefix from an item's content.
        #
        # Examples:
        #   "1. Heading one"  -> 1
        #   "3) Heading three" -> 3
        #   "10. Task ten"    -> 10
        #
        # Returns failure if there is no valid numeric prefix.
        get_number_prefix() {
            local content="$1"

            if [[ "$content" =~ ^([0-9]+)[.\)][[:space:]]+ ]]; then
                printf '%s\n' "${BASH_REMATCH[1]}"
                return 0
            fi

            return 1
        }


        has_number_prefix() {
            local content="$1"

            [[ "$content" =~ ^[0-9]+[.\)][[:space:]]+ ]]
        }


        sort_numbered_items() {
            local -n items="$1"

            local item
            local number
            local sorted=()
            local entries=()

            for item in "${items[@]}"; do
                number="$(get_number_prefix "${item_content[item]}")" || continue

                # Include the original item index after the number.
                entries+=("$number"$'\t'"$item")
            done

            # Numeric sort by the first field.
            #
            # sort -n is stable on GNU coreutils when --stable is specified.
            if ((${#entries[@]})); then
                mapfile -t entries < <(
                    printf '%s\n' "${entries[@]}" |
                        sort -n -k1,1 -s
                )
            fi

            for entry in "${entries[@]}"; do
                sorted+=("${entry#*$'\t'}")
            done

            items=("${sorted[@]}")
        }


        sort_children() {
            local children
            local todo_heading=()
            local rules_for_today_heading=()
            local numbered_headings=()
            local unnumbered_headings=()
            local numbered_tasks=()
            local unnumbered_tasks=()

            get_children "$1"   # arg is item id NOT index.
            children=("${CHILDREN[@]}")

            for child in "${children[@]}"; do
                case "${item_type[child]}" in
                    H)
                        # TODO is always first when it is a root-level heading.
                        if [[ "$1" == "0" &&
                            "${item_content[child]}" == "TODO" ]]; then
                            todo_heading+=("$child")
                        elif [[ "$1" == "0" &&
                                "${item_content[child]}" == "RULES FOR TODAY" ]]; then

                            rules_for_today_heading+=("$child")                            
                        elif has_number_prefix "${item_content[child]}"; then
                            numbered_headings+=("$child")
                        else
                            unnumbered_headings+=("$child")
                        fi
                        ;;

                    T)
                        if has_number_prefix "${item_content[child]}"; then
                            numbered_tasks+=("$child")
                        else
                            unnumbered_tasks+=("$child")
                        fi
                        ;;
                esac
            done

            sort_numbered_items numbered_headings
            sort_numbered_items numbered_tasks

            children=(
                "${todo_heading[@]}"
                "${rules_for_today_heading[@]}"
                "${numbered_headings[@]}"
                "${unnumbered_headings[@]}"
                "${numbered_tasks[@]}"
                "${unnumbered_tasks[@]}"
            )

            # Update global 0-based positions.
            for position in "${!children[@]}"; do
                item_position[children[position]]="$position"
            done
        }

        # ------------------------------------------------------------
        # Item action menu
        # ------------------------------------------------------------

        item_menu() {
            local index="$1"
            local action
            local type="${item_type[index]}"

            while :; do

                if [[ "$type" == "H" ]]; then

                    action="$(
                        whiptail \
                            --title "${item_content[index]}" \
                            --cancel-button "Back" \
                            --menu \
                            "Status: $(status_name "${effective_status[index]}")\nImportance: $(importance_name "${item_importance[index]}")" \
                            24 80 12 \
                            "TEXT" "Change text" \
                            "STATUS" "Change status" \
                            "IMPORTANCE" "Change importance" \
                            "COMMENT" "Add / edit comment" \
                            "VIEW_COMMENT" "View comment" \
                            "ADD_H" "Add heading" \
                            "ADD_T" "Add task" \
                            "MOVE" "Move" \
                            "SORT" "Sort children by number prefix" \
                            "DELETE" "Delete" \
                            "BACK" "Back" \
                            3>&1 1>&2 2>&3
                    )" || return

                else

                    action="$(
                        whiptail \
                            --title "${item_content[index]}" \
                            --cancel-button "Back" \
                            --menu \
                            "Status: $(status_name "${effective_status[index]}")\nImportance: $(importance_name "${item_importance[index]}")" \
                            20 75 8 \
                            "TEXT" "Change task / plan" \
                            "STATUS" "Change status" \
                            "IMPORTANCE" "Change importance" \
                            "COMMENT" "Add / edit comment" \
                            "VIEW_COMMENT" "View comment" \
                            "MOVE" "Move" \
                            "DELETE" "Delete" \
                            "BACK" "Back" \
                            3>&1 1>&2 2>&3
                    )" || return

                fi

                case "$action" in

                    TEXT)
                        if [[ "$type" == "T" ]]; then
                            edit_task "$index"
                        else
                            edit_text "$index"
                        fi
                        ;;

                    STATUS)
                        change_status "$index"
                        ;;

                    IMPORTANCE)
                        change_importance "$index"
                        ;;

                    COMMENT)
                        edit_comment "$index"
                        ;;

                    VIEW_COMMENT)
                        view_comment "$index"
                        ;;

                    ADD_H)
                        add_heading "${item_id[index]}"
                        ;;

                    ADD_T)
                        add_task "${item_id[index]}"
                        ;;

                    MOVE)
                        #move_item "$index"
                        move_item_menu "$index"

                        # The arrays may have changed but this item itself
                        # still exists, so locate it again.
                        find_index_by_id "${item_id[index]}"
                        (( RESULT_INDEX >= 0 )) && index=$RESULT_INDEX
                        ;;

                    SORT)
                        sort_children "${item_id[index]}"
                        ;;

                    DELETE)
                        local deleted_id="${item_id[index]}"

                        delete_item "$index"

                        find_index_by_id "$deleted_id"

                        if (( RESULT_INDEX < 0 )); then
                            return
                        fi

                        index=$RESULT_INDEX
                        type="${item_type[index]}"
                        ;;

                    BACK)
                        return
                        ;;
                esac

                calculate_all_statuses
            done
        }


        change_status() {
            local index="$1"
            local new_status

            # Container headings are derived from their children.
            if [[ "${item_type[index]}" == "H" ]] && is_container "$index"; then

                new_status="$(
                    whiptail \
                        --title "Container Heading" \
                        --menu \
                        "'${item_content[index]}' is a container heading.\n\nSelect an operation:" \
                        16 75 5 \
                        "C" "Complete entire goal" \
                        "PA" "Pause unfinished descendants" \
                        "RESET" "Reset descendants to not started" \
                        3>&1 1>&2 2>&3
                )" || return

                case "$new_status" in
                    C)
                        set_subtree_status "$index" "C"
                        ;;

                    PA)
                        set_unfinished_subtree_status "$index" "PA"
                        ;;

                    RESET)
                        set_subtree_status "$index" "NS"
                        ;;
                esac

                calculate_all_statuses
                return
            fi

            new_status="$(select_status "${item_status[index]}")" || return

            item_status[index]="$new_status"

            calculate_all_statuses
        }


        change_importance() {
            local index="$1"
            local new_importance

            new_importance="$(
                select_importance "${item_importance[index]}"
            )" || return

            item_importance[index]="$new_importance"
        }


        set_subtree_status() {
            local root_index="$1"
            local new_status="$2"
            local child

            item_status[root_index]="$new_status"

            get_children "${item_id[root_index]}"

            for child in "${CHILDREN[@]}"; do
                set_subtree_status "$child" "$new_status"
            done
        }


        set_unfinished_subtree_status() {
            local root_index="$1"
            local child

            if [[ "${effective_status[root_index]}" != "C" ]]; then
                item_status[root_index]="PA"
            fi

            get_children "${item_id[root_index]}"

            for child in "${CHILDREN[@]}"; do
                set_unfinished_subtree_status "$child"
            done
        }


        # ------------------------------------------------------------
        # Main project UI
        # ------------------------------------------------------------

        project_menu() {
            local choice
            local project_file_tr="${PROJECT_FILE:0:80}"
            (( ${#PROJECT_FILE} > 80 )) && project_file_tr+="..."

            local tree_page=0
            local tree_page_size=25   # tree items per page            

            # Remember the saved state so Back can detect unsaved changes.
            local PROJECT_SAVED_SIG
            sort_children "0"
            calculate_all_statuses
            PROJECT_SAVED_SIG="$(project_state_sig)"

            while :; do

                sort_children "0"
                calculate_all_statuses
                build_tree_options

                # --- paginate TREE_OPTIONS ---
                local tree_total=$(( ${#TREE_OPTIONS[@]} / 2 ))
                local tree_pages=$(( (tree_total + tree_page_size - 1) / tree_page_size ))
                (( tree_pages == 0 )) && tree_pages=1
                (( tree_page >= tree_pages )) && tree_page=$(( tree_pages - 1 ))
                (( tree_page < 0 )) && tree_page=0
                local tree_start=$(( tree_page * tree_page_size * 2 ))
                local tree_chunk=("${TREE_OPTIONS[@]:tree_start:tree_page_size*2}")

                # static action rows first
                local menu_items=(
                    "SYMBOLS" "Help"
                    "ADD_H" "Add top-level heading"
                    "ADD_T" "Add task"
                    "ADD_TODO" "Add TODO item"
                    "ADD_RULES" "Add RULES FOR TODAY item"                 
                    "SORT" "Sort root's children by number prefix"
                    "SAVE" "Save changes"
                    "REVERT" "Discard changes and reload from disk"
                    "---" "PROJECT TREE BELOW ---"
                    "" ""
                )

                # navigation rows (only when applicable)
                (( tree_page > 0 )) && menu_items+=("__prev__" "<< Previous page")
                (( tree_page < tree_pages - 1 )) && menu_items+=("__next__" "Next page >>")

                # then the current page of tree items
                menu_items+=("${tree_chunk[@]}")

                choice="$(
                    whiptail \
                        --title "Manage Goals" \
                        --cancel-button "Back" \
                        --menu \
                        "Project: $project_file_tr (Page $((tree_page + 1))/$tree_pages)" \
                        45 180 37 \
                        -- \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3
                )" || { project_confirm_leave && break; continue; }

                case "$choice" in
                    SYMBOLS)
                        whiptail \
                            --title "Symbol Help" \
                            --msgbox "$(print_symbol_help)" \
                            20 80                
                        ;;

                    __prev__)
                        (( tree_page > 0 )) && (( tree_page-- ))
                        continue
                        ;;
                    __next__)
                        (( tree_page < tree_pages - 1 )) && (( tree_page++ ))
                        continue
                        ;;                        

                    "---"|"")
                        continue
                        ;;

                    ADD_H)
                        add_heading "0"
                        ;;

                    ADD_T)
                        if select_heading_for_parent "0"; then
                            add_task "$SELECTED_HEADING_ID"
                        fi
                        ;;

                    ADD_RULES)
                        add_rules_for_today_item
                        ;;                    

                    ADD_TODO)
                        add_todo_item
                        ;;                    

                    SORT)
                        sort_children "0"
                        ;;

                    SAVE)
                        if save_project; then
                            PROJECT_SAVED_SIG="$(project_state_sig)"
                            whiptail \
                                --title "Saved" \
                                --msgbox "Project saved successfully." \
                                8 50
                        fi
                        ;;

                    REVERT)
                        if whiptail \
                            --title "Revert Project" \
                            --yesno \
                            "Discard unsaved changes and reload the project from disk?" \
                            10 70; then

                            if load_project "$PROJECT_FILE"; then
                                sort_children "0"
                                calculate_all_statuses
                                PROJECT_SAVED_SIG="$(project_state_sig)"
                                whiptail \
                                    --title "Reverted" \
                                    --msgbox "Unsaved changes discarded; project reloaded." \
                                    8 50
                            fi
                        fi
                        ;;

                    *)
                        # Tree entries use their persistent item ID as the menu tag.
                        find_index_by_id "$choice"
                        if (( RESULT_INDEX >= 0 )); then
                            item_menu "$RESULT_INDEX"
                        fi
                        ;;
                esac
            done
        }

        # ------------------------------------------------------------
        # Start
        # ------------------------------------------------------------

        if ! command -v whiptail >/dev/null 2>&1; then
            printf 'Error: whiptail is not installed.\n' >&2
            exit 1
        fi

        if ! load_project "$PROJECT_FILE"; then
            return 1
        fi

        project_menu    
    }

    truncate_note_tags_by_tag() {
        local tags="$1"
        local inner
        local -a tag_array
        local count
        local extra

        # Remove surrounding [ ]
        inner="${tags#[}"
        inner="${inner%]}"

        # Empty list
        if [[ -z "$inner" ]]; then
            printf '[]\n'
            return
        fi

        # Split on commas
        IFS=',' read -r -a tag_array <<< "$inner"

        count=${#tag_array[@]}

        if (( count <= 3 )); then
            printf '[%s]\n' "$inner"
            return
        fi

        extra=$((count - 3))

        printf '[%s,%s,%s +%d]\n' \
            "${tag_array[0]}" \
            "${tag_array[1]}" \
            "${tag_array[2]}" \
            "$extra"
    }

    # Select Project: only shortlisted projects are offered, shown by title.
    # __APPLY_GLOB__ matches project titles and __RESET_GLOB__ clears the glob
    # (no glob is asked up front).
    local -a projects=()
    GOALS_PROJECT_GLOB=""
    local GOALS_PROJECT_TITLE_MODE=1
    local GOALS_PROJECT_RESTRICT_FILE="$PROJECTS_DB_SHORTLISTED"
    goals_select_project "Select Project" || return 1
    GOALS_PROJECT_TITLE_MODE=""
    local selected_project_tag="$GOALS_SELECTED_PROJECT_LINENO"
    mapfile -t projects < "$PROJECTS_DB"

    local selected_project_path
    local note_lines=()
    local note_menu_options=()

    # MOVED OUT OF WHILE LOOP!!!
    refresh_all_linked_notes() {
        mapfile -t projects < "$PROJECTS_DB"    # Reload from PROJECTS DB file.
        local selected_project_index=$((selected_project_tag - 1))
        local selected_project_line="${projects[$selected_project_index]}"

        local associated_notes
        IFS='|' read -r selected_project_title selected_project_path associated_notes <<< "$selected_project_line"

        # Process associated notes
        local note_paths=()
        IFS=',' read -ra note_paths <<< "$associated_notes"
        note_lines=()
        note_menu_options=()

        # Filters first, then the actions.
        note_menu_options+=("__FILTER_BY_TAG__" "Filter linked notes by tag")
        note_menu_options+=("__RESET_FILTER__" "Reset the tag filter")
        note_menu_options+=("__APPLY_GLOB__" "Apply glob (matches note titles)")
        note_menu_options+=("__RESET_GLOB__" "Reset the title glob")
        note_menu_options+=("Manage plan" "")
        note_menu_options+=("Create new note tag" "")
        note_menu_options+=("Create new linked note" "")
        note_menu_options+=("Open ebook" "")
        note_menu_options+=("Open URL" "")
        note_menu_options+=("Link note" "")
        note_menu_options+=("Unlink note" "")
        note_menu_options+=("Add tag to linked notes" "")
        note_menu_options+=("Remove tag from linked notes" "")

        local trunc_tag

        # First collect all matching note lines.
        for np in "${note_paths[@]}"; do
            while IFS= read -r line; do
                IFS='|' read -r title path tags _ <<< "$line"

                if [ "$path" = "$np" ]; then
                    note_lines+=("$line")
                    break
                fi
            done < "$NOTES_DB"
        done

        # Sort note_lines alphabetically by title--guarded.
        if ((${#note_lines[@]} > 0)); then
            mapfile -t note_lines < <(
                printf '%s\n' "${note_lines[@]}" |
                sort -t'|' -k1,1f
            )
        fi

        # Build menu options in the exact same order as note_lines.
        for i in "${!note_lines[@]}"; do
            IFS='|' read -r title path tags _ <<< "${note_lines[$i]}"

            trunc_tag="$(truncate_note_tags_by_tag "[${tags}]")"

            note_menu_options+=("$((i + 1))" "$title $trunc_tag")
        done

        # Refresh code end.
    }

    #-- Helpers for refresh_filtered_linked_notes()
    retrieve_linked_notes() {
        local selected_project_path="$1"
        local project_line
        local project_title
        local project_path
        local linked_notes
        local note_path

        # Find the project line whose second field matches the selected path
        while IFS= read -r project_line; do
            IFS='|' read -r project_title project_path linked_notes <<< "$project_line"

            if [[ "$project_path" == "$selected_project_path" ]]; then
                break
            fi

            linked_notes=""
        done < "$PROJECTS_DB"

        # No matching project or no linked notes
        [[ -z "$linked_notes" ]] && return 0

        # Extract each comma-separated note path
        local IFS=','
        read -r -a note_paths <<< "$linked_notes"

        # Find and print each corresponding line from NOTES_DB
        for note_path in "${note_paths[@]}"; do
            while IFS= read -r note_line; do
                IFS='|' read -r note_title note_db_path note_tags note_rest <<< "$note_line"

                if [[ "$note_db_path" == "$note_path" ]]; then
                    printf '%s\n' "$note_line"
                    break
                fi
            done < "$NOTES_DB"
        done
    }

    filter_linked_notes_by_tag() {
        local selected_tag="$1"
        shift

        local line
        local title
        local note_path
        local note_tags
        local rest
        local current_tag

        for line in "$@"; do
            IFS='|' read -r title note_path note_tags rest <<< "$line"

            # NEW: 'NO TAG' sentinel matches linked notes with an empty tag field.
            if [[ "$selected_tag" == "[NO TAG]" ]]; then
                [[ -z "$note_tags" ]] && printf '%s\n' "$line"
                continue
            fi

            IFS=',' read -ra tag_array <<< "$note_tags"

            for current_tag in "${tag_array[@]}"; do
                if [[ "$current_tag" == "$selected_tag" ]]; then
                    printf '%s\n' "$line"
                    break
                fi
            done
        done
    }    
    #-- Helpers end.

    # Apply a Bash glob to the note title (case-insensitive). The glob matches
    # the whole title, so use *text* for a contains-style match.
    filter_linked_notes_by_glob() {
        local pattern="$1"
        shift

        local line title lower_pattern="${pattern,,}"
        for line in "$@"; do
            IFS='|' read -r title _ _ _ <<< "$line"
            # Keep the right-hand pattern unquoted so Bash interprets glob syntax.
            if [[ "${title,,}" == $lower_pattern ]]; then
                printf '%s\n' "$line"
            fi
        done
    }

    local TAG_FILTER_BY=""
    local GLOB_FILTER_BY=""

    # Return linked notes after applying both active filters. This helper is
    # shared by the menu and all actions that operate on the visible note list.
    get_current_filtered_linked_notes() {
        local -a current_notes=()
        mapfile -t current_notes < <(
            retrieve_linked_notes "$selected_project_path"
        )

        if [[ -n "$TAG_FILTER_BY" && "$TAG_FILTER_BY" != "[ANY TAG]" ]]; then
            mapfile -t current_notes < <(
                filter_linked_notes_by_tag "$TAG_FILTER_BY" "${current_notes[@]}"
            )
        fi

        if [[ -n "$GLOB_FILTER_BY" ]]; then
            mapfile -t current_notes < <(
                filter_linked_notes_by_glob "$GLOB_FILTER_BY" "${current_notes[@]}"
            )
        fi

        ((${#current_notes[@]} > 0)) && printf '%s\n' "${current_notes[@]}"
    }

    # Get notes matching the glob without applying the current tag filter. This
    # lets the user change the tag filter while the glob remains in force.
    get_linked_notes_matching_glob() {
        local -a current_notes=()
        mapfile -t current_notes < <(
            retrieve_linked_notes "$selected_project_path"
        )

        if [[ -n "$GLOB_FILTER_BY" ]]; then
            mapfile -t current_notes < <(
                filter_linked_notes_by_glob "$GLOB_FILTER_BY" "${current_notes[@]}"
            )
        fi

        ((${#current_notes[@]} > 0)) && printf '%s\n' "${current_notes[@]}"
    }

    refresh_filtered_linked_notes() {
        local line title path tags trunc_tag
        local -a filtered_linked_notes=()

        mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)

        # Keep the visible list alphabetically sorted by title.
        if ((${#filtered_linked_notes[@]} > 0)); then
            mapfile -t filtered_linked_notes < <(
                printf '%s\n' "${filtered_linked_notes[@]}" |
                sort -t'|' -k1,1f
            )
        fi

        note_lines=()
        note_menu_options=()
        LINKED_NOTES_TOTAL=$(retrieve_linked_notes "$selected_project_path" | grep -c .)

        # Filters first, then the actions.
        note_menu_options+=("__FILTER_BY_TAG__" "Filter linked notes by tag")
        note_menu_options+=("__RESET_FILTER__" "Reset the tag filter")
        note_menu_options+=("__APPLY_GLOB__" "Apply glob (matches note titles)")
        note_menu_options+=("__RESET_GLOB__" "Reset the title glob")
        note_menu_options+=("Manage plan" "")
        note_menu_options+=("Create new note tag" "")
        note_menu_options+=("Create new linked note" "")
        note_menu_options+=("Open ebook" "")
        note_menu_options+=("Open URL" "")
        note_menu_options+=("Link note" "")
        note_menu_options+=("Unlink note" "")
        note_menu_options+=("Add tag to linked notes" "")
        note_menu_options+=("Remove tag from linked notes" "")

        for line in "${filtered_linked_notes[@]}"; do
            [[ -z "$line" ]] && continue
            IFS='|' read -r title path tags _ <<< "$line"
            note_lines+=("$line")
            trunc_tag="$(truncate_note_tags_by_tag "[${tags}]")"
            note_menu_options+=("${#note_lines[@]}" "$title $trunc_tag")
        done
    }

    refresh_all_linked_notes

    # FIX: WHILE LOOP TO ALLOW MULTIPLE LINKED NOTE SELECTIONS
    while :; do
        refresh_filtered_linked_notes

        paginate_tags_menu() {
            local title="$1"
            shift
            local items=("$@")
            local per_page=20
            local total_items=$(( ${#items[@]} / 2 ))
            local total_pages=$(( (total_items + per_page - 1) / per_page ))
            local current_page=1
            local choice start_index end_index menu_items tag desc

            while true; do
                # Calculate start and end indices for current page
                start_index=$(( (current_page - 1) * per_page * 2 ))
                end_index=$(( start_index + per_page * 2 ))
                menu_items=()

                # Add items for current page
                for ((i = start_index; i < end_index && i < ${#items[@]}; i+=2)); do
                    tag="${items[i]}"
                    desc="${items[i+1]}"
                    menu_items+=("$tag" "$desc")
                done

                # Add navigation options
                if (( current_page > 1 )); then
                    menu_items+=("<< Prev" "")
                fi
                if (( current_page < total_pages )); then
                    menu_items+=(">> Next" "")
                fi

                # Show whiptail menu
                choice=$(whiptail --title "$title" \
                    --menu "Page ${current_page}/${total_pages}" 20 60 12 \
                    "${menu_items[@]}" 3>&1 1>&2 2>&3)

                [[ $? -ne 0 ]] && return 1  # Cancel pressed

                case "$choice" in
                    ">> Next")
                        (( current_page++ ))
                        ;;
                    "<< Prev")
                        (( current_page-- ))
                        ;;
                    *)
                        # Return selected tag
                        printf '%s\n' "$choice"
                        return 0
                        ;;
                esac
            done
        }

        choose_tag_goal() {
            # Choose Tag: [NO TAG] creates the note without a tag. __FILTER__
            # narrows the tag list by a literal substring; __RESET_FILTER__ clears it.
            goals_select_note_tag_filter --title "Choose Tag" \
                --prompt "Choose a tag for the new linked note" --pins "NO" \
                --no-tag-desc "Create the note without any tag" || return 1
            printf '%s' "$GOALS_SELECTED_NOTE_TAG"
        }

        add_tag_to_notes_from_filtered() {
            whiptail --title "Attention" --msgbox \
"Step 1: Select tag to add.
Step 2: Select multiple notes to add the tag to.

Tag you have chosen will be added to the selected notes." 10 60
            local notes_db="${NOTES_DB:-}"
            local tags_db="${NOTES_TAGS_DB:-}"
            local page_size="${PAGE_SIZE:-30}"

            if [[ -z $notes_db || ! -r $notes_db || ! -w $notes_db ]]; then
                printf 'ERROR: NOTES_DB must be set and writable: %s\n' "${notes_db:-<unset>}" >&2
                return 1
            fi

            if [[ -z $tags_db || ! -r $tags_db ]]; then
                printf 'ERROR: NOTES_TAGS_DB must be set and readable: %s\n' "${tags_db:-<unset>}" >&2
                return 1
            fi

            if ! command -v whiptail >/dev/null 2>&1; then
                printf 'ERROR: whiptail is not installed.\n' >&2
                return 1
            fi

            if [[ $# -eq 0 ]]; then
                printf 'ERROR: pass filtered note lines as arguments.\n' >&2
                return 1
            fi

            local -a all_notes=("$@")
            local total="${#all_notes[@]}"

            (( total == 0 )) && {
                whiptail --msgbox "No filtered notes found. Add a note and try again." 8 50
                return 1
            }

            local page_count=$(( (total + page_size - 1) / page_size ))

            local tmp_sel=""
            local tmp_db=""
            trap 'rm -f -- "$tmp_sel" "$tmp_db"' RETURN

            local -a tag_menu=()
            local tag
            while IFS= read -r tag || [[ -n $tag ]]; do
                [[ -n $tag ]] || continue
                tag_menu+=("$tag" "")
            done < "$tags_db"

            if (( ${#tag_menu[@]} == 0 )); then
                whiptail --msgbox "No note tags found. Add a tag and try again." 8 50
                return 1
            fi

            local selected_tag
            # Select tag: __FILTER__ narrows the tag list by a literal substring,
            # __RESET_FILTER__ clears it.
            local -a tag_list=()
            local tk
            for (( tk = 0; tk < ${#tag_menu[@]}; tk += 2 )); do
                tag_list+=("${tag_menu[tk]}")
            done
            goals_select_note_tag_filter --title "Select tag" \
                --prompt "Choose the tag to add to the notes" --pins "" \
                --tags "${tag_list[@]}" || return 1
            selected_tag="$GOALS_SELECTED_NOTE_TAG"

            # Select notes: full note paths with their tags.
            local -a all_paths=()
            local ln_ ln_path_
            for ln_ in "${all_notes[@]}"; do
                IFS='|' read -r _ ln_path_ _ <<< "$ln_"
                [[ -n "$ln_path_" ]] && all_paths+=("$ln_path_")
            done

            GOALS_NOTE_GLOB=""
            GOALS_NOTE_TAGFILTER=""
            local -A selected_paths=()
            local sp_
            while :; do
                goals_pick_notes_multi "Select notes" "Tag to add: $selected_tag" \
                    "__add_tag__" "Add tag to selected notes" top \
                    "${all_paths[@]}" || return 1

                selected_paths=()
                for sp_ in "${GOALS_PICKED_PATHS[@]}"; do selected_paths["$sp_"]=1; done

                local selected_count="${#selected_paths[@]}"

                if ! whiptail --title "Confirm" \
                    --yesno "Add tag \"$selected_tag\" to $selected_count selected note(s)?" \
                    10 70; then
                    continue
                fi

                    tmp_sel=$(mktemp "${TMPDIR:-/tmp}/notes_sel.XXXXXX") || return 1
                    tmp_db=$(mktemp "${notes_db}.XXXXXX") || { rm -f -- "$tmp_sel"; return 1; }

                    {
                        local p
                        for p in "${!selected_paths[@]}"; do
                            printf '%s\n' "$p"
                        done
                    } > "$tmp_sel"

                    awk -F'|' -v OFS='|' -v tag="$selected_tag" -v selfile="$tmp_sel" '
                        BEGIN {
                            while ((getline p < selfile) > 0) sel[p] = 1
                            close(selfile)
                        }

                        function has_tag(tags, tag,   n, a, i) {
                            if (tags == "") return 0
                            n = split(tags, a, /,/)
                            for (i = 1; i <= n; i++) {
                                if (a[i] == tag) return 1
                            }
                            return 0
                        }

                        function append_tag(tags, tag,   n, a, i, out) {
                            if (tags == "") return tag
                            n = split(tags, a, /,/)
                            out = ""
                            for (i = 1; i <= n; i++) {
                                if (a[i] == "" || a[i] == tag) continue
                                out = (out == "" ? a[i] : out "," a[i])
                            }
                            return (out == "" ? tag : out "," tag)
                        }

                        {
                            if (sel[$2] && !has_tag($3, tag)) {
                                $3 = append_tag($3, tag)
                            }
                            print
                        }
                    ' "$notes_db" > "$tmp_db" || { rm -f -- "$tmp_sel" "$tmp_db"; return 1; }

                    mv -- "$tmp_db" "$notes_db" || { rm -f -- "$tmp_sel" "$tmp_db"; return 1; }
                    rm -f -- "$tmp_sel"
                    tmp_sel=""

                    whiptail --msgbox "Tag \"$selected_tag\" added to selected notes." 8 60
                    return 0
            done
        }

        retrieve_linked_notes() {
            local selected_project_path="$1"
            local project_line
            local project_title
            local project_path
            local linked_notes
            local note_path

            # Find the project line whose second field matches the selected path
            while IFS= read -r project_line; do
                IFS='|' read -r project_title project_path linked_notes <<< "$project_line"

                if [[ "$project_path" == "$selected_project_path" ]]; then
                    break
                fi

                linked_notes=""
            done < "$PROJECTS_DB"

            # No matching project or no linked notes
            [[ -z "$linked_notes" ]] && return 0

            # Extract each comma-separated note path
            local IFS=','
            read -r -a note_paths <<< "$linked_notes"

            # Find and print each corresponding line from NOTES_DB
            for note_path in "${note_paths[@]}"; do
                while IFS= read -r note_line; do
                    IFS='|' read -r note_title note_db_path note_tags note_rest <<< "$note_line"

                    if [[ "$note_db_path" == "$note_path" ]]; then
                        printf '%s\n' "$note_line"
                        break
                    fi
                done < "$NOTES_DB"
            done
        }

        retrieve_linked_note_tags() {
            local line
            local tags
            local tag

            declare -A seen_tags=()

            for line in "$@"; do
                # Extract the third field (tags)
                IFS='|' read -r _ _ tags _ <<< "$line"

                # Extract comma-separated tags
                local IFS=','
                read -r -a tag_array <<< "$tags"

                for tag in "${tag_array[@]}"; do
                    [[ -z "$tag" ]] && continue
                    seen_tags["$tag"]=1
                done
            done

            # Print unique tags alphabetically
            printf '%s\n' "${!seen_tags[@]}" | sort
        }

        remove_linked_note_tag() {
            local tag="$1"
            shift

            local matched_line
            local title
            local note_path
            local note_tags
            local rest
            local new_tags
            local current_tag
            local found

            # Nothing to process
            [[ $# -eq 0 ]] && return 0

            # Create a temporary file
            local temp_file
            temp_file=$(mktemp) || return 1

            while IFS= read -r line; do
                local should_update=false

                # Check whether this line is one of the matched lines
                for matched_line in "$@"; do
                    if [[ "$line" == "$matched_line" ]]; then
                        should_update=true
                        break
                    fi
                done

                if [[ "$should_update" == true ]]; then
                    # NOTES_DB:
                    # note title|note path|tag1,tag2|rest
                    IFS='|' read -r title note_path note_tags rest <<< "$line"

                    new_tags=""

                    # Remove the requested tag
                    local old_ifs="$IFS"
                    IFS=','
                    read -r -a tag_array <<< "$note_tags"
                    IFS="$old_ifs"

                    for current_tag in "${tag_array[@]}"; do
                        [[ "$current_tag" == "$tag" ]] && continue

                        if [[ -z "$new_tags" ]]; then
                            new_tags="$current_tag"
                        else
                            new_tags+=",$current_tag"
                        fi
                    done

                    # Reconstruct the line
                    printf '%s|%s|%s|%s\n' \
                        "$title" \
                        "$note_path" \
                        "$new_tags" \
                        "$rest"
                else
                    # Leave all other lines unchanged
                    printf '%s\n' "$line"
                fi
            done < "$NOTES_DB" > "$temp_file"

            # Replace the original database
            mv "$temp_file" "$NOTES_DB"
        }

        filter_linked_notes_by_tag() {
            local selected_tag="$1"
            shift

            local line
            local title
            local note_path
            local note_tags
            local rest
            local current_tag

            for line in "$@"; do
                IFS='|' read -r title note_path note_tags rest <<< "$line"

                # NEW: 'NO TAG' sentinel matches linked notes with an empty tag field.
                if [[ "$selected_tag" == "[NO TAG]" ]]; then
                    [[ -z "$note_tags" ]] && printf '%s\n' "$line"
                    continue
                fi

                IFS=',' read -ra tag_array <<< "$note_tags"

                for current_tag in "${tag_array[@]}"; do
                    if [[ "$current_tag" == "$selected_tag" ]]; then
                        printf '%s\n' "$line"
                        break
                    fi
                done
            done
        }

        add_note_tag_stuff() {
            local subject=""
            local topic=""
            local tag_name=""
            local choice

            while true; do
                # Construct tag name
                if [[ -n "$subject" && -n "$topic" ]]; then
                    tag_name="${subject}->${topic}"
                else
                    tag_name="$subject"
                fi

                # Silently remove banned characters
                tag_name="${tag_name//[|,#:;]/}"

                choice=$(
                    whiptail \
                        --title "Add Note Tag" \
                        --menu "Create a new tag (formatted 'subject->topic'):" \
                        18 70 8 \
                        "Subject" "${subject:-<not set>}" \
                        "Topic" "${topic:-<not set>}" \
                        "Tag Name" "'${tag_name}'" \
                        "Save" "" \
                        3>&1 1>&2 2>&3
                ) || return 1

                case "$choice" in
                    Subject)
                        subject=$(
                            whiptail \
                                --title "Subject" \
                                --inputbox "Enter subject:" \
                                10 60 "$subject" \
                                3>&1 1>&2 2>&3
                        ) || continue
                        ;;

                    Topic)
                        topic=$(
                            whiptail \
                                --title "Topic" \
                                --inputbox "Enter topic (optional):" \
                                10 60 "$topic" \
                                3>&1 1>&2 2>&3
                        ) || continue
                        ;;

                    Save)
                        # Reconstruct again to ensure latest values
                        if [[ -n "$subject" && -n "$topic" ]]; then
                            tag_name="${subject}->${topic}"
                        else
                            tag_name="$subject"
                        fi

                        # Remove banned characters
                        tag_name="${tag_name//[|,#:;]/}"

                        # Trim whitespace
                        tag_name="$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$tag_name")"

                        if [[ -z "$tag_name" ]]; then
                            whiptail \
                                --title "Error" \
                                --msgbox "Tag Name cannot be empty." \
                                8 40
                            continue
                        fi

                        if [[ "$tag_name" == "ANY TAG" ]]; then
                            whiptail \
                                --title "Error" \
                                --msgbox "'ANY TAG' is a reserved tag name." \
                                8 45
                            continue
                        fi

                        if grep -Fxq -- "$tag_name" "$NOTES_TAGS_DB"; then
                            whiptail \
                                --title "Duplicate" \
                                --msgbox "Tag already exists." \
                                8 40
                            continue
                        fi

                        {
                            cat "$NOTES_TAGS_DB"
                            printf '%s\n' "$tag_name"
                        } | sort -u > "${NOTES_TAGS_DB}.tmp" &&
                            mv "${NOTES_TAGS_DB}.tmp" "$NOTES_TAGS_DB"

                        whiptail \
                            --title "Success" \
                            --msgbox "Tag added:\n\n$tag_name" \
                            10 50

                        return 0
                        ;;
                esac
            done
        }

        open_urls_filtered() {
            # Control characters:
            #   Ctrl-] = ^] = Group Separator
            #   Ctrl-^ = ^^ = Record Separator
            #   Ctrl-_ = ^_ = Unit Separator
            local CTRL_GS=$'\035'
            local CTRL_RS=$'\036'
            local CTRL_US=$'\037'

            _spawn() {
                nohup "$@" >/dev/null 2>&1 </dev/null &
            }

            _dialog_msg() {
                local message=$1
                local height=${2:-10}
                local width=${3:-60}

                whiptail --msgbox "$message" "$height" "$width" \
                    3>&1 1>&2 2>&3
            }

            if (($# == 0)); then
                _dialog_msg "No note records were supplied." 10 55
                return 1
            fi

            if [[ ! -r ${URLS_DB:?URLS_DB is not set} ]]; then
                _dialog_msg "URLS_DB is not readable: $URLS_DB" 10 65
                return 1
            fi

            local line note_path dbline record
            local title entry url description
            local selected_note selected_url
            local id=1

            local -a note_items=()
            local -a url_note_paths=()
            local -a url_items=()

            local -A note_path_by_id=()
            local -A url_by_id=()

            # ------------------------------------------------------------
            # Build menu of linked notes that have at least one URL.
            # ------------------------------------------------------------

            for line in "$@"; do
                # NOTES_DB format:
                # note title|note path|tag1,tag2|ebook information
                IFS='|' read -r title note_path _ <<< "$line"
                note_path=${note_path%$'\r'}

                [[ -n $note_path ]] || continue

                # Check whether this note has at least one URL.
                local has_url=0

                while IFS= read -r dbline || [[ -n $dbline ]]; do
                    [[ $dbline == "$note_path$CTRL_GS"* ]] || continue

                    record=${dbline#*"$CTRL_GS"}

                    local -a url_records=()
                    IFS="$CTRL_RS" read -r -a url_records <<< "$record"

                    for entry in "${url_records[@]}"; do
                        [[ -n $entry ]] || continue

                        if [[ $entry == *"$CTRL_US"* ]]; then
                            url=${entry%%"$CTRL_US"*}
                        else
                            url=$entry
                        fi

                        [[ -n $url ]] || continue

                        has_url=1
                        break
                    done

                    ((has_url)) && break
                done < "$URLS_DB"

                # Only add notes that actually have URLs.
                if ((has_url)); then
                    note_path_by_id[$id]=$note_path

                    # Show title in the menu. Fall back to note path if needed.
                    [[ -n $title ]] || title=$note_path

                    note_items+=("$id" "$title")
                    url_note_paths+=("$note_path")
                    ((++id))
                fi
            done

            if ((${#note_items[@]} == 0)); then
                _dialog_msg "None of the supplied notes have associated URLs." 10 65
                return 1
            fi

            GOALS_NOTE_GLOB=""
            GOALS_NOTE_TAGFILTER=""
            local GOALS_NOTE_TITLE_MODE=1
            local GOALS_NOTE_TAGMENU_FULL=1
            while :; do
                # ------------------------------------------------------------
                # Select a note.
                # ------------------------------------------------------------

                # Select Note: titles with tags; glob matches note titles;
                # __FILTER_BY_TAG__ offers [ANY TAG], [NO TAG] and the tags.
                goals_pick_note "Select Note" "Choose a linked note" \
                    "${url_note_paths[@]}" || return 1
                note_path="$GOALS_PICKED_NOTE_PATH"

                # ------------------------------------------------------------
                # Build URL menu for the selected note.
                # ------------------------------------------------------------

                id=1
                url_items=()
                url_by_id=()

                while IFS= read -r dbline || [[ -n $dbline ]]; do
                    [[ $dbline == "$note_path$CTRL_GS"* ]] || continue

                    record=${dbline#*"$CTRL_GS"}

                    local -a url_records=()
                    IFS="$CTRL_RS" read -r -a url_records <<< "$record"

                    for entry in "${url_records[@]}"; do
                        [[ -n $entry ]] || continue

                        if [[ $entry == *"$CTRL_US"* ]]; then
                            url=${entry%%"$CTRL_US"*}
                            description=${entry#*"$CTRL_US"}
                        else
                            url=$entry
                            description=""
                        fi

                        [[ -n $url ]] || continue

                        url_by_id[$id]=$url

                        if [[ -n $description ]]; then
                            url_items+=("$id" "$description $url")
                        else
                            url_items+=("$id" "$url")
                        fi

                        ((++id))
                    done
                done < "$URLS_DB"

                if ((${#url_items[@]} == 0)); then
                    _dialog_msg "No URLs were found for the selected note." 10 65
                    return 1
                fi

                # Select URL: __APPLY_GLOB__ matches the URL or its description.
                local url_glob="" new_url_glob shown_urls k_
                local -a url_menu=()
                while :; do
                    url_menu=(
                        "__APPLY_GLOB__" "Apply glob (matches URL or description)"
                        "__RESET_GLOB__" "Reset glob"
                    )
                    shown_urls=0
                    for (( k_ = 0; k_ < ${#url_items[@]}; k_ += 2 )); do
                        if [[ -n $url_glob ]]; then
                            [[ "${url_items[k_+1],,}" == ${url_glob,,} ]] || continue
                        fi
                        url_menu+=("${url_items[k_]}" "${url_items[k_+1]}")
                        shown_urls=$((shown_urls + 1))
                    done

                    selected_url=$(
                        whiptail \
                            --title "Select URL" \
                            --cancel-button "Back" \
                            --menu "Choose a URL to open:\nGlob: ${url_glob:-none}   ($shown_urls of $(( ${#url_items[@]} / 2 )) URLs shown)" \
                            20 155 10 \
                            "${url_menu[@]}" \
                            3>&1 1>&2 2>&3
                    ) || break

                    case $selected_url in
                        __APPLY_GLOB__)
                            if new_url_glob=$(whiptail --title "Apply URL Glob" --inputbox \
                                "Enter a case-insensitive glob to match URLs or their descriptions (for example: *github*). Leave empty to show all URLs." \
                                11 90 "$url_glob" 3>&1 1>&2 2>&3); then
                                url_glob=$new_url_glob
                            fi
                            continue
                            ;;
                        __RESET_GLOB__)
                            url_glob=""
                            continue
                            ;;
                    esac

                    [[ -n $selected_url ]] || continue

                    url=${url_by_id[$selected_url]-}
                    [[ -n $url ]] || continue

                    _spawn "$URL_BROWSER" --new-window -- "$url"
                done
            done
        }

        open_ebook_filtered() {
            _spawn() {
                nohup "$@" >/dev/null 2>&1 </dev/null &
            }

            _dialog_msg() {
                local message=$1
                local height=${2:-10}
                local width=${3:-60}

                whiptail --msgbox "$message" "$height" "$width" \
                    3>&1 1>&2 2>&3
            }

            if (($# == 0)); then
                _dialog_msg "No note records were supplied." 10 55
                return 1
            fi

            if [[ ! -r ${NOTES_DB:?NOTES_DB is not set} ]]; then
                _dialog_msg "NOTES_DB is not readable: $NOTES_DB" 10 65
                return 1
            fi

            local line
            local note_path
            local dbline
            local db_note_path
            local db_bookspec

            local entry
            local ebook
            local bookmark_spec

            local title
            local selected_note
            local selected_ebook

            local action
            local status

            local id

            local -a note_items=()
            local -a ebook_note_paths=()
            local -A note_path_by_id=()

            local -a ebook_items=()
            local -A ebook_by_id=()
            local -A bookmarks_by_id=()

            # ------------------------------------------------------------
            # Build menu of linked notes that have at least one ebook.
            # ------------------------------------------------------------

            id=1

            for line in "$@"; do
                # NOTES_DB format:
                # note title|note path|tag1,tag2|ebook information
                IFS='|' read -r title note_path _ <<< "$line"
                note_path=${note_path%$'\r'}

                [[ -n $note_path ]] || continue

                local has_ebook=0

                # Find the NOTES_DB record whose second field exactly matches
                # the note path.
                while IFS= read -r dbline || [[ -n $dbline ]]; do
                    IFS='|' read -r _ db_note_path _ db_bookspec <<< "$dbline"

                    [[ $db_note_path == "$note_path" ]] || continue

                    # Ebook records are separated by semicolons:
                    # /book/one.pdf#bookmark:10,other:20;/book/two.pdf#
                    local -a ebook_records=()
                    IFS=';' read -r -a ebook_records <<< "$db_bookspec"

                    for entry in "${ebook_records[@]}"; do
                        [[ -n $entry ]] || continue

                        if [[ $entry == *'#'* ]]; then
                            ebook=${entry%%#*}
                        else
                            ebook=$entry
                        fi

                        [[ -n $ebook ]] || continue

                        has_ebook=1
                        break
                    done

                    ((has_ebook)) && break
                done < "$NOTES_DB"

                # Only show notes that have at least one ebook.
                if ((has_ebook)); then
                    [[ -n $title ]] || title=$note_path

                    note_path_by_id[$id]=$note_path
                    note_items+=("$id" "$title")
                    ebook_note_paths+=("$note_path")

                    ((++id))
                fi
            done

            if ((${#note_items[@]} == 0)); then
                _dialog_msg \
                    "None of the supplied notes have associated ebook files." \
                    10 70
                return 1
            fi

            # ------------------------------------------------------------
            # Select note.
            # ------------------------------------------------------------

            # Select Note: titles with tags; glob matches note titles;
            # __FILTER_BY_TAG__ offers [ANY TAG], [NO TAG] and the tags.
            GOALS_NOTE_GLOB=""
            GOALS_NOTE_TAGFILTER=""
            local GOALS_NOTE_TITLE_MODE=1
            local GOALS_NOTE_TAGMENU_FULL=1
            goals_pick_note "Select Note" "Choose a linked note" \
                "${ebook_note_paths[@]}" || return 1
            note_path="$GOALS_PICKED_NOTE_PATH"

            # ------------------------------------------------------------
            # Build ebook menu for the selected note.
            # ------------------------------------------------------------

            id=1
            ebook_items=()
            ebook_by_id=()
            bookmarks_by_id=()

            while IFS= read -r dbline || [[ -n $dbline ]]; do
                IFS='|' read -r _ db_note_path _ db_bookspec <<< "$dbline"

                [[ $db_note_path == "$note_path" ]] || continue

                local -a ebook_records=()
                IFS=';' read -r -a ebook_records <<< "$db_bookspec"

                for entry in "${ebook_records[@]}"; do
                    [[ -n $entry ]] || continue

                    # Separate ebook path from bookmark list.
                    if [[ $entry == *'#'* ]]; then
                        ebook=${entry%%#*}
                        bookmark_spec=${entry#*#}
                    else
                        ebook=$entry
                        bookmark_spec=""
                    fi

                    [[ -n $ebook ]] || continue

                    ebook_by_id[$id]=$ebook
                    bookmarks_by_id[$id]=$bookmark_spec

                    ebook_items+=("$id" "$ebook")

                    ((++id))
                done

                # There should only be one matching note record.
                break
            done < "$NOTES_DB"

            if ((${#ebook_items[@]} == 0)); then
                _dialog_msg \
                    "No ebook files were found for the selected note." \
                    10 65
                return 1
            fi

            # ------------------------------------------------------------
            # Select ebook.
            # ------------------------------------------------------------

            selected_ebook=$(
                whiptail \
                    --title "Select Ebook" \
                    --cancel-button "Back" \
                    --menu "Choose an ebook to open in zathura:" \
                    22 100 14 \
                    "${ebook_items[@]}" \
                    3>&1 1>&2 2>&3
            )
            status=$?

            ((status != 0)) && return "$status"

            ebook=${ebook_by_id[$selected_ebook]-}
            bookmark_spec=${bookmarks_by_id[$selected_ebook]-}

            [[ -n $ebook ]] || return 1

            # ------------------------------------------------------------
            # Choose how to open the ebook.
            # ------------------------------------------------------------

            action=$(
                whiptail \
                    --title "Open Ebook" \
                    --cancel-button "Back" \
                    --menu "How should zathura open this ebook?" \
                    15 90 4 \
                    "open"       "Just open" \
                    "bookmarks"  "Browse bookmarks" \
                    3>&1 1>&2 2>&3
            )
            status=$?

            ((status != 0)) && return "$status"

            case $action in
                open)
                    _spawn "$(get_open_command "$ebook")" -- "$ebook"
                    ;;

                bookmarks)
                    # ----------------------------------------------------
                    # Build bookmark menu.
                    #
                    # Bookmark format:
                    # bookmark label:page,another bookmark:another page
                    # ----------------------------------------------------

                    local bookmark
                    local label
                    local page
                    local bookmark_id

                    local bookmark_selection
                    local bookmark_status

                    bookmark_id=1

                    local -a bookmark_items=()
                    local -A page_by_id=()

                    if [[ -n $bookmark_spec ]]; then
                        local -a bookmarks=()
                        IFS=',' read -r -a bookmarks <<< "$bookmark_spec"

                        for bookmark in "${bookmarks[@]}"; do
                            [[ -n $bookmark ]] || continue
                            [[ $bookmark == *:* ]] || continue

                            label=${bookmark%:*}
                            page=${bookmark##*:}

                            [[ $page =~ ^[0-9]+$ ]] || continue

                            page_by_id[$bookmark_id]=$page

                            bookmark_items+=(
                                "$bookmark_id"
                                "$label    [page $page]"
                            )

                            ((++bookmark_id))
                        done
                    fi

                    if ((${#bookmark_items[@]} == 0)); then
                        _dialog_msg \
                            "This ebook has no valid bookmarks in NOTES_DB." \
                            10 65
                        return 1
                    fi

                    # ----------------------------------------------------
                    # Select bookmark.
                    # ----------------------------------------------------

                    bookmark_selection=$(
                        whiptail \
                            --title "Select Bookmark" \
                            --cancel-button "Back" \
                            --menu "Choose a bookmark:" \
                            22 90 14 \
                            "${bookmark_items[@]}" \
                            3>&1 1>&2 2>&3
                    )
                    bookmark_status=$?

                    ((bookmark_status != 0)) && return "$bookmark_status"

                    page=${page_by_id[$bookmark_selection]-}
                    [[ -n $page ]] || return 1


                    local cmd__ vcmd__
                    cmd__="$(get_open_command "$ebook")"
                    vcmd__="${VIEWER_COMMANDS["$cmd__"]}"

                    [[ -n "$vcmd__" ]] || return 1

                    read -r -a viewer_cmd__ <<< "$vcmd__"
                    _spawn "${viewer_cmd__[@]}" "$page" -- "$ebook"

                    #_spawn "$vcmd__" "$page" -- "$ebook"
                    ;;

                *)
                    return 1
                    ;;
            esac
        }



        # FIX: PAGINATE LINKED NOTE SELECTION
        local selected_note_tag
        selected_note_tag="$(show_note_menu "$selected_project_title" "${note_menu_options[@]}")" || return 1

        # Handle case when user selects "Create new lnked note".
        if [[ "$selected_note_tag" == "Create new linked note" ]]; then
            local chosen_tag_goal
            chosen_tag_goal="$(choose_tag_goal)" || continue
            if [[ "$chosen_tag_goal" == "[NO TAG]" ]]; then
                add_note || continue
            else
                add_note "$chosen_tag_goal" || continue
            fi

            associate_new_note_to_project_from_shortlist "$selected_project_path"
            continue    # Continue since we need to update the linked notes list now.
        elif [[ "$selected_note_tag" == "Link note" ]]; then
            associate_note_to_project_from_shortlist "$selected_project_path" || continue
            continue    # Display list of linked notes again after associating a note.   
        elif [[ "$selected_note_tag" == "Unlink note" ]]; then
            mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)
            dissociate_note_from_project_from_shortlist \
                "$selected_project_path" --filtered-notes "${filtered_linked_notes[@]}" || continue
            continue    # Display list of linked notes again after dissociating notes.
        elif [[ "$selected_note_tag" == "Manage plan" ]]; then
            edit_plan "$selected_project_path" || continue
            continue
        elif [[ "$selected_note_tag" == "Add tag to linked notes" ]]; then
            mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)
            if ((${#filtered_linked_notes[@]} == 0)); then
                whiptail --title "No Matching Notes" --msgbox \
                    "No linked notes match the active filters." 8 60
                continue
            fi
            add_tag_to_notes_from_filtered "${filtered_linked_notes[@]}"
            continue
        elif [[ "$selected_note_tag" == "Remove tag from linked notes" ]]; then
            # Work only with notes that satisfy both active filters.
            local notes_for_tag_workflow=()
            mapfile -t notes_for_tag_workflow < <(get_current_filtered_linked_notes)

            # ------------------------------------------------------------
            # Retrieve tags from the relevant linked notes.
            # ------------------------------------------------------------

            local note_tags=()

            mapfile -t note_tags < <(
                retrieve_linked_note_tags "${notes_for_tag_workflow[@]}"
            )

            # Remove the last element if it's empty.
            [[ -z "${note_tags[-1]}" ]] && unset 'note_tags[-1]'

            if (( ${#note_tags[@]} == 0 )); then
                whiptail \
                    --title "No Matching Tags" \
                    --msgbox "There are no matching tags." \
                    10 50 \
                    3>&1 1>&2 2>&3 </dev/tty >/dev/tty

                continue
            fi

            # ------------------------------------------------------------
            # Build tag menu.
            # ------------------------------------------------------------

            local chosen_tag_for_removal
            local tag_menu_options=()
            local tag

            for tag in "${note_tags[@]}"; do
                tag_menu_options+=("$tag" "")
            done

            # ------------------------------------------------------------
            # Select tag.
            # ------------------------------------------------------------

            # if ! chosen_tag_for_removal=$(whiptail \
            #     --title "Remove Linked Note Tag" \
            #     --menu "Select a tag to remove:" \
            #     20 80 10 \
            #     "${tag_menu_options[@]}" \
            #     3>&1 1>&2 2>&3 </dev/tty >/dev/tty
            # ); then
            #     continue
            # fi

            # Remove Linked Note Tag: __FILTER__ narrows the list by a literal
            # substring, __RESET_FILTER__ clears it.
            goals_select_note_tag_filter --title "Remove Linked Note Tag" \
                --prompt "Select a tag to remove" --pins "" \
                --tags "${note_tags[@]}" || continue
            chosen_tag_for_removal="$GOALS_SELECTED_NOTE_TAG"

            # ------------------------------------------------------------
            # Find NOTES_DB lines containing the selected tag, then
            # extract the note path from field 2.
            # ------------------------------------------------------------

            local notes_with_selected_tag=()
            local note_line
            local note_path

            while IFS= read -r note_line; do

                [[ -z "$note_line" ]] && continue

                # NOTES_DB format:
                # title|path|tags|rest
                IFS='|' read -r _ note_path _ _ <<< "$note_line"

                [[ -n "$note_path" ]] &&
                    notes_with_selected_tag+=("$note_path")

            done < <(
                filter_linked_notes_by_tag \
                    "$chosen_tag_for_removal" \
                    "${notes_for_tag_workflow[@]}"
            )

            if (( ${#notes_with_selected_tag[@]} == 0 )); then
                whiptail \
                    --title "No Matching Notes" \
                    --msgbox \
                    "There are no linked notes with the tag \"$chosen_tag_for_removal\"." \
                    10 70 \
                    3>&1 1>&2 2>&3 </dev/tty >/dev/tty

                continue
            fi

            # ------------------------------------------------------------
            # Paginated checklist settings.
            # ------------------------------------------------------------

            # Select notes: __REMOVE__ at the top, full note paths with their
            # tags, glob (file name) and tag filters.
            GOALS_NOTE_GLOB=""
            GOALS_NOTE_TAGFILTER=""
            local selected_notes_for_removal=()
            local rm_path_ matching_line__
            while :; do
                goals_pick_notes_multi "Select Notes" \
                    "Select notes to remove the tag \"$chosen_tag_for_removal\" from" \
                    "__remove__" "Remove the tag from the selected notes" top \
                    "${notes_with_selected_tag[@]}" || break

                selected_notes_for_removal=()
                for rm_path_ in "${GOALS_PICKED_PATHS[@]}"; do
                    matching_line__=$(
                        awk -F'|' -v path="$rm_path_" '$2 == path { print; exit }' "$NOTES_DB"
                    )
                    [[ -n "$matching_line__" ]] &&
                        selected_notes_for_removal+=("$matching_line__")
                done

                if (( ${#selected_notes_for_removal[@]} == 0 )); then
                    whiptail --title "No Notes Selected" --msgbox \
                        "Select at least one note before choosing \"__remove__\"." 10 70
                    continue
                fi

                if remove_linked_note_tag \
                    "$chosen_tag_for_removal" \
                    "${selected_notes_for_removal[@]}"
                then
                    whiptail --title "Tag Removed" --msgbox \
                        "The tag \"$chosen_tag_for_removal\" has been removed from the selected notes." \
                        10 80
                    break
                fi
            done
            continue
        elif [[ "$selected_note_tag" == "__FILTER_BY_TAG__" ]]; then
            # Offer [ANY TAG], [NO TAG] and the tags of the linked notes that match
            # the title glob. __FILTER__ narrows the tag list (literal substring)
            # and __RESET_FILTER__ clears that narrowing.
            local -a filter_tags=()
            mapfile -t linked_notes_array < <(get_linked_notes_matching_glob)
            if ((${#linked_notes_array[@]} > 0)); then
                mapfile -t filter_tags < <(
                    retrieve_linked_note_tags "${linked_notes_array[@]}" | sed '/^$/d'
                )
            fi
            if goals_select_note_tag_filter --title "Filter Linked Notes" \
                --prompt "Choose a tag to filter the linked notes by" \
                --no-tag-desc "Show only linked notes that have no tag" \
                --any-tag-desc "Show linked notes with or without tags" \
                --tags "${filter_tags[@]}"; then
                TAG_FILTER_BY="$GOALS_SELECTED_NOTE_TAG"
            fi
            continue
        elif [[ "$selected_note_tag" == "__RESET_FILTER__" ]]; then
            TAG_FILTER_BY=""
            continue
        elif [[ "$selected_note_tag" == "__APPLY_GLOB__" ]]; then
            local new_glob
            new_glob=$(whiptail \
                --title "Apply Glob to Linked Note Titles" \
                --inputbox \
                "Enter a case-insensitive Bash glob for note titles.
Examples: *Python* or Meeting-??

Leave the pattern non-empty; use * to match all titles." \
                13 80 "$GLOB_FILTER_BY" \
                3>&1 1>&2 2>&3) || continue

            if [[ -z "$new_glob" ]]; then
                whiptail --title "Empty Glob" --msgbox \
                    "The glob cannot be empty. Use * to match all titles, or choose __RESET_GLOB__ to clear the glob filter." \
                    10 75
                continue
            fi

            GLOB_FILTER_BY="$new_glob"
            continue
        elif [[ "$selected_note_tag" == "__RESET_GLOB__" ]]; then
            GLOB_FILTER_BY=""
            continue
        elif [[ "$selected_note_tag" == "Create new note tag" ]]; then
            add_note_tag_stuff
            continue
        elif [[ "$selected_note_tag" == "Open URL" ]]; then
            mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)
            open_urls_filtered "${filtered_linked_notes[@]}"
            continue
        elif [[ "$selected_note_tag" == "Open ebook" ]]; then
            mapfile -t filtered_linked_notes < <(get_current_filtered_linked_notes)
            open_ebook_filtered "${filtered_linked_notes[@]}"
            continue
        fi

        #-- Helper fn's for 'Add tag to item' and 'Remove tag from item'
        add_tag_to_item() {
            goals_add_tag_to_note "$1"
        }


        remove_tag_from_item() {
            goals_remove_tag_from_note "$1"
        }
        #-- Helpers end.        

        local selected_note_index=$((selected_note_tag - 1))
        local selected_note_line="${note_lines[$selected_note_index]}"

        # Action selection
        local action
        action=$(whiptail --menu "Note Action" 24 60 11 \
            "1" "View Note" \
            "2" "Copy note content to clipboard" \
            "3" "Open ebooks linked to note" \
            "4" "Edit Note" \
            "5" "Open linked URL" \
            "6" "Associate URL to note" \
            "7" "Dissociate URL from note" \
            "8" "Associate Note to Project" \
            "9" "Print Note using Printer" \
            "10" "Add tag to item" \
            "11" "Remove tag from item" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue    # i want to return to list of linked note files so continue

        case "$action" in
            "1")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                #whiptail --scrolltext --title "$note_title" --textbox "$note_path" 35 150
                
                # FIX: USE DIALOG INSTEAD BECAUSE WHIPTAIL FAILS HERE.
                # Specifically, \n \t etc gets translated.
                # The shared dialog() wrapper applies the same palette as Whiptail.
                #dialog --exit-label "Back" --title "$note_title" --textbox "$note_path" 35 150
                # Word wrap width 145
                local tmpfile=$(mktemp)
                fold -s -w 145 "$note_path" > "$tmpfile"
                dialog --no-mouse --exit-label "Back" --title "$note_title" --textbox "$tmpfile" 35 150
                rm -f "$tmpfile"
                clear
                ;;
            "2")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                # Save $note_path to xclip
                cat "$note_path" | xclip -sel clip
                whiptail --msgbox "Copied to clipboard!" 8 50 >/dev/tty
                ;;
            "3")
                open_note_ebook_page_from_project "$selected_note_line"
                ;;
            "4")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                edit_note "$note_path"
                ;;
            "5")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                open_url_assoc_to_chosen_note
                ;;
            "6")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                assoc_url_to_chosen_note
                ;;
            "7")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                dissoc_url_from_chosen_note
                ;;
            "8")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                associate_chosen_note_to_project "$note_path"
                ;;
            "9")
                IFS='|' read -r note_title note_path _ _ <<< "$selected_note_line"
                print_chosen_note "$note_path"
                ;;
            "10")
                add_tag_to_item "$selected_note_line"
                ;;
            "11")
                remove_tag_from_item "$selected_note_line"
                ;;
        esac
    done
}

do_stuff_with_shortlisted() {
    # Just keep the last 200 lines of history file.
    trim_shortlisted_history

    while true; do
        local choice
        choice=$(whiptail --title "Shortlisted Projects Menu" \
            --menu "Choose an action:" 15 50 6 \
            "1" "Do stuff" \
            "2" "Add to shortlist" \
            "3" "Remove from shortlist" \
            "4" "View history" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            1)
                do_stuff_shortlisted
                ;;
            2)
                add_to_shortlist
                ;;
            3)
                remove_from_shortlist
                ;;
            4)
                view_shortlist_history
                ;;
        esac
    done
}

print_symbol_help() {
    status_symbol() {
        case "$1" in
            NS) printf '%s' "○" ;;
            IP) printf '%s' "▶" ;;
            PA) printf '%s' "Ⅱ" ;;
            C)  printf '%s' "✓" ;;
            *)  printf '%s' "?" ;;
        esac
    }

    importance_symbol() {
        case "$1" in
            VI) printf '%s' "!!" ;;
            I)  printf '%s' "!" ;;
            N)  printf '%s' "-" ;;
            NI) printf '%s' "." ;;
            *)  printf '%s' "?" ;;
        esac
    }

    cat <<EOF
◆   Heading
•   Task/Plan

Status:
  $(status_symbol NS)  Not Started
  $(status_symbol IP)  In Progress
  $(status_symbol PA)  Paused
  $(status_symbol C)   Completed

Importance:
  $(importance_symbol VI)  Very Important
  $(importance_symbol I)   Important
  $(importance_symbol N)   Normal
  $(importance_symbol NI)  Not Important
EOF
}

# ---------------------------------------------------------------------------
# BABYRUS: Build a book from the notes associated with a project.
#
# Integration:
#   1. Add this block at top level, after PROJECTS_DB / NOTES_DB are defined.
#   2. Add both actions to the existing Projects menu:
#        "Build Book from Linked Notes" -> build_book_from_project
#        "Load Existing Book to Edit"   -> babyrus_book_edit_existing
#      Use your menu's existing format and case-selection variable.
#
# Uses the existing BABYRUS database/list globals:
#   PROJECTS_DB, NOTES_DB, BOOKS_LIST
# BOOKS_LIST must be set to the path of the plain-text list of saved book files.
# ---------------------------------------------------------------------------

# Return the selected PROJECTS_DB row from a paginated project-file menu.
# PROJECTS_DB rows are expected to be title|project-path|comma-separated-note-paths|...
babyrus_book_select_project_row() {
    local menu_title="${1:-Select Project File}"
    local row project_title project_path choice page_size=50 page=0 total_pages start end i selected_index
    local term_rows term_cols box_h box_w list_h glob_pattern lower_title no_match_note
    local -a all_rows=() all_paths=() all_titles=() project_rows=() project_paths=() menu_items=()

    if [[ ! -r "$PROJECTS_DB" ]]; then
        whiptail --title "$menu_title" --msgbox \
            "The projects database cannot be read:\n$PROJECTS_DB" 10 75 </dev/tty >/dev/tty
        return 1
    fi
    while IFS= read -r row || [[ -n "$row" ]]; do
        [[ -n "$row" ]] || continue
        IFS='|' read -r project_title project_path _ <<< "$row"
        [[ -n "$project_path" ]] || continue
        all_rows+=("$row"); all_paths+=("$project_path"); all_titles+=("$project_title")
    done < "$PROJECTS_DB"
    ((${#all_rows[@]})) || {
        whiptail --title "$menu_title" --msgbox "There are no project files to choose from." 8 60 </dev/tty >/dev/tty
        return 1
    }

    glob_pattern=""
    while :; do
        project_rows=(); project_paths=()
        for i in "${!all_rows[@]}"; do
            lower_title="${all_paths[$i]##*/}"   # project FILE NAME
            lower_title="${lower_title,,}"
            if [[ -z "$glob_pattern" || "$lower_title" == ${glob_pattern,,} ]]; then
                project_rows+=("${all_rows[$i]}")
                project_paths+=("${all_paths[$i]}")
            fi
        done
        # No message box here: this function runs inside $(...), where a
        # message box cannot be displayed (it would wait for a key press that
        # the user cannot see). The notice is shown in the menu prompt instead.
        no_match_note=""
        ((${#project_rows[@]})) || no_match_note="\nNo project file names match the current glob. Choose Apply glob to change it, or Reset glob to show all projects."
        total_pages=$(( (${#project_rows[@]} + page_size - 1) / page_size ))
        (( total_pages > 0 )) || total_pages=1
        (( page >= total_pages )) && page=$((total_pages - 1))
        read -r term_rows term_cols < <(stty size </dev/tty 2>/dev/null)
        [[ "$term_rows" =~ ^[0-9]+$ ]] || term_rows=$(tput lines 2>/dev/null || echo 40)
        [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=$(tput cols 2>/dev/null || echo 155)
        box_w=170; (( box_w > term_cols - 2 )) && box_w=$((term_cols - 2)); (( box_w < 60 )) && box_w=60
        box_h=$((term_rows - 2)); (( box_h > 60 )) && box_h=60; (( box_h < 20 )) && box_h=20
        list_h=$((box_h - 8)); (( list_h < 5 )) && list_h=5
        start=$((page * page_size)); end=$((start + page_size)); (( end > ${#project_rows[@]} )) && end=${#project_rows[@]}
        menu_items=()
        menu_items+=("__APPLY_GLOB__" "Apply glob")
        menu_items+=("__RESET_GLOB__" "Reset glob")

        (( page > 0 )) && menu_items+=("__PREVIOUS_PAGE__" "<< Previous page")
        for ((i=start; i<end; i++)); do menu_items+=("$((i + 1))" "${project_paths[$i]}"); done
        (( page + 1 < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page >>")

        choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
            --menu "Choose a project file; glob: ${glob_pattern:- (none)} (page $((page + 1)) of $total_pages; ${#project_rows[@]} matches).${no_match_note}" \
            "$box_h" "$box_w" "$list_h" "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        case "$choice" in
            __PREVIOUS_PAGE__) ((page--)); continue ;;
            __NEXT_PAGE__) ((page++)); continue ;;
            __APPLY_GLOB__)
                glob_pattern=$(whiptail --title "Apply Project File Name Glob" --inputbox \
                    "Enter a case-insensitive glob pattern to match project file names (for example: *javascript*)." \
                    10 90 "$glob_pattern" 3>&1 1>&2 2>&3) || continue
                page=0; continue ;;
            __RESET_GLOB__) glob_pattern=""; page=0; continue ;;
            ''|*[!0-9]*) return 1 ;;
        esac
        selected_index=$((choice - 1))
        (( selected_index >= 0 && selected_index < ${#project_rows[@]} )) || continue
        printf '%s\n' "${project_rows[$selected_index]}"
        return 0
    done
}

build_book_from_project() {
    local project_title project_path associated_notes selected_project_line

    if [[ ! -r "$NOTES_DB" ]]; then
        whiptail --title "Build Book" --msgbox \
            "The notes database cannot be read:\n$NOTES_DB" 10 75
        return 1
    fi

    selected_project_line=$(babyrus_book_select_project_row "Select Project for Book") || return 1
    IFS='|' read -r project_title project_path associated_notes <<< "$selected_project_line"
    [[ -n "$project_path" ]] || return 1

    # The following variables are local to this interactive book-building
    # session. Bash's dynamic scoping makes them available to the helpers below.
    local BOOK_PROJECT_TITLE="$project_title"
    local BOOK_PROJECT_PATH="$project_path"
    local BOOK_ORIGINAL_PROJECT_PATH="$project_path"
    local BOOK_TITLE="$project_title"
    local BOOK_TAG_FILTER_BY=""
    local BOOK_GLOB_FILTER_BY=""
    local BOOK_SELECTED_NOTE_PATH=""
    local BOOK_SELECTED_NOTE_TITLE=""
    local BOOK_SELECTED_SECTION_INDEX=""
    local BOOK_FILE_PATH=""
    local BOOK_SAVED=1
    local -a BOOK_BASE_NOTE_LINES=()
    local -a BOOK_SECTION_PATHS=()
    local -a BOOK_SECTION_TITLES=()
    local -a BOOK_SECTION_LEVELS=()
    local -a BOOK_SECTION_NUMBERS=()
    # Keep source-project provenance alongside each section so reordering and
    # removing sections also updates the saved source-project metadata.
    local -a BOOK_SECTION_SOURCE_PROJECT_TITLES=()
    local -a BOOK_SECTION_SOURCE_PROJECT_PATHS=()

    babyrus_book_load_associated_notes "$associated_notes"

    if ((${#BOOK_BASE_NOTE_LINES[@]} == 0)); then
        whiptail --title "Build Book" --msgbox \
            "No linked notes were found for this project. You can choose 'Load another project file' in the book editor to load notes from a different project." \
            10 85
    fi

    local entered_title
    if ! entered_title=$(whiptail --title "Book Title" --inputbox \
        "Enter a title for the book." 9 70 "$BOOK_TITLE" 3>&1 1>&2 2>&3); then
        return 1
    fi
    [[ -n "$entered_title" ]] || {
        whiptail --title "Book Title" --msgbox "The book title cannot be empty." 8 55
        return 1
    }
    BOOK_TITLE="$entered_title"

    babyrus_book_edit_session

}


# Shared interactive editor used for newly built and previously saved books.
babyrus_book_edit_session() {
    while :; do
        local choice
        choice=$(whiptail --title "Build Book: $BOOK_TITLE" --cancel-button "Finish" \
            --menu "Current project: $BOOK_PROJECT_TITLE\nSections: ${#BOOK_SECTION_PATHS[@]}" \
            25 100 12 \
            "1" "Add section from an associated note" \
            "2" "Load another project file" \
            "3" "Move section up (move its subsection block too)" \
            "4" "Move section down (move its subsection block too)" \
            "5" "Change section indentation" \
            "6" "Remove section" \
            "7" "Preview book outline" \
            "8" "Read sections" \
            "9" "Change book title" \
            "10" "Save book to a .txt file" \
            "11" "Show current save path" \
            "12" "Convert book to PDF" \
            3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || {
                if (( BOOK_SAVED == 0 && ${#BOOK_SECTION_PATHS[@]} > 0 )); then
                    if whiptail --title "Unsaved Book" --yesno \
                        "There are unsaved changes. Exit without saving them?" 9 65; then
                        return 0
                    fi
                    continue
                fi
                return 0
            }

        case "$choice" in
            1)
                if babyrus_book_pick_note; then
                    if [[ ! -f "$BOOK_SELECTED_NOTE_PATH" || ! -r "$BOOK_SELECTED_NOTE_PATH" ]]; then
                        whiptail --title "Cannot Add Section" --msgbox \
                            "The selected note file does not exist or cannot be read:\n$BOOK_SELECTED_NOTE_PATH" \
                            10 80
                        continue
                    fi

                    BOOK_SECTION_PATHS+=("$BOOK_SELECTED_NOTE_PATH")
                    BOOK_SECTION_TITLES+=("$BOOK_SELECTED_NOTE_TITLE")
                    BOOK_SECTION_LEVELS+=(1)
                    BOOK_SECTION_SOURCE_PROJECT_TITLES+=("$BOOK_PROJECT_TITLE")
                    BOOK_SECTION_SOURCE_PROJECT_PATHS+=("$BOOK_PROJECT_PATH")
                    BOOK_SAVED=0
                fi
                ;;
            2)
                babyrus_book_load_another_project || :
                ;;
            3|4)
                if babyrus_book_select_section "Select Section to Move"; then
                    local move_direction
                    [[ "$choice" == "3" ]] && move_direction="up" || move_direction="down"
                    babyrus_book_move_section "$move_direction" "$BOOK_SELECTED_SECTION_INDEX"
                fi
                ;;
            5)
                babyrus_book_change_indentation
                ;;
            6)
                if babyrus_book_select_section "Select Section to Remove"; then
                    local remove_index="$BOOK_SELECTED_SECTION_INDEX"
                    local remove_title="${BOOK_SECTION_TITLES[$remove_index]}"
                    if whiptail --title "Remove Book Section" --yesno \
                        "Remove section \"$remove_title\" and all of its subsections from this book draft?" \
                        10 75; then
                        babyrus_book_remove_section "$remove_index"
                    fi
                fi
                ;;
            7)
                outline="$(babyrus_book_outline_text)"
                [[ -n "$outline" ]] || outline="(No sections have been added yet.)"
                whiptail --title "Book Outline Preview" --msgbox "$outline" 24 100
                ;;
            8)
                babyrus_book_read_sections
                ;;
            9)
                if entered_title=$(whiptail --title "Change Book Title" --inputbox \
                    "Enter the new book title." 9 70 "$BOOK_TITLE" 3>&1 1>&2 2>&3); then
                    if [[ -n "$entered_title" ]]; then
                        BOOK_TITLE="$entered_title"
                        BOOK_SAVED=0
                    else
                        whiptail --title "Book Title" --msgbox "The book title cannot be empty." 8 55
                    fi
                fi
                ;;
            10)
                babyrus_book_save
                ;;
            11)
                if [[ -n "$BOOK_FILE_PATH" ]]; then
                    whiptail --title "Book Save Path" --msgbox "$BOOK_FILE_PATH" 8 85
                else
                    whiptail --title "Book Save Path" --msgbox \
                        "The book has not been saved yet. Its suggested path is:\n$(babyrus_book_default_path)" \
                        10 85
                fi
                ;;
            12)
                babyrus_book_convert_to_pdf
                ;;
        esac
    done
}

# Load a saved book from the Projects menu, then open the same editor used
# when building a new book from a project's linked notes.
babyrus_book_edit_existing() {
    local BOOK_PROJECT_TITLE=""
    local BOOK_PROJECT_PATH=""
    local BOOK_ORIGINAL_PROJECT_PATH=""
    local BOOK_TITLE=""
    local BOOK_TAG_FILTER_BY=""
    local BOOK_GLOB_FILTER_BY=""
    local BOOK_SELECTED_NOTE_PATH=""
    local BOOK_SELECTED_NOTE_TITLE=""
    local BOOK_SELECTED_SECTION_INDEX=""
    local BOOK_FILE_PATH=""
    local BOOK_SAVED=1
    local -a BOOK_BASE_NOTE_LINES=()
    local -a BOOK_SECTION_PATHS=()
    local -a BOOK_SECTION_TITLES=()
    local -a BOOK_SECTION_LEVELS=()
    local -a BOOK_SECTION_NUMBERS=()
    # Keep source-project provenance alongside each section so reordering and
    # removing sections also updates the saved source-project metadata.
    local -a BOOK_SECTION_SOURCE_PROJECT_TITLES=()
    local -a BOOK_SECTION_SOURCE_PROJECT_PATHS=()

    babyrus_book_load_existing || return 1
    BOOK_ORIGINAL_PROJECT_PATH="$BOOK_PROJECT_PATH"

    # Restore the available note list from the book's source project, where
    # possible, so the user can add more sections after loading the book.
    if ! babyrus_book_load_notes_for_current_project; then
        whiptail --title "Book Loaded" --msgbox \
            "The saved book was loaded, but its source project could not be matched in PROJECTS_DB.\n\nYou can edit the existing outline, save, and create a PDF. Adding new sections from associated notes will not be available until the source project is registered again." \
            12 85
    fi

    babyrus_book_edit_session
}

# Restore the linked-note choices for the loaded book's source project.
babyrus_book_load_notes_for_current_project() {
    local row project_title project_path associated_notes
    [[ -n "$BOOK_PROJECT_PATH" && -r "$PROJECTS_DB" ]] || return 1

    while IFS= read -r row || [[ -n "$row" ]]; do
        IFS='|' read -r project_title project_path associated_notes _ <<< "$row"
        if [[ "$project_path" == "$BOOK_PROJECT_PATH" ]]; then
            BOOK_BASE_NOTE_LINES=()
            BOOK_PROJECT_TITLE="$project_title"
            babyrus_book_load_associated_notes "$associated_notes"
            return 0
        fi
    done < "$PROJECTS_DB"

    return 1
}

# Switch the linked-note source project without changing the current book outline.
babyrus_book_load_another_project() {
    local selected_project_line project_title project_path associated_notes

    if [[ ! -r "$NOTES_DB" ]]; then
        whiptail --title "Load Another Project File" --msgbox \
            "The notes database cannot be read:\n$NOTES_DB" 10 75
        return 1
    fi

    selected_project_line=$(babyrus_book_select_project_row "Load Another Project File") || return 1
    IFS='|' read -r project_title project_path associated_notes <<< "$selected_project_line"
    [[ -n "$project_path" ]] || return 1

    if [[ "$project_path" != "$BOOK_PROJECT_PATH" || "$project_title" != "$BOOK_PROJECT_TITLE" ]]; then
        BOOK_SAVED=0
    fi

    BOOK_PROJECT_TITLE="$project_title"
    BOOK_PROJECT_PATH="$project_path"
    BOOK_TAG_FILTER_BY=""
    BOOK_GLOB_FILTER_BY=""
    babyrus_book_load_associated_notes "$associated_notes"

    whiptail --title "Project Loaded" --msgbox \
        "Current project: $BOOK_PROJECT_TITLE\n\nLinked notes available: ${#BOOK_BASE_NOTE_LINES[@]}\n\nYour existing book sections have been kept. You can now add notes from this project." \
        11 80
}

# Load NOTES_DB rows associated with a project. Paths are matched as exact
# strings, so spaces in note titles and file paths are preserved.
babyrus_book_load_associated_notes() {
    local associated_notes="$1"
    local IFS=','
    local -a note_paths=()
    local note_path note_line note_title note_db_path

    BOOK_BASE_NOTE_LINES=()
    [[ -n "$associated_notes" ]] || return 0
    read -r -a note_paths <<< "$associated_notes"

    for note_path in "${note_paths[@]}"; do
        [[ -n "$note_path" ]] || continue
        while IFS= read -r note_line || [[ -n "$note_line" ]]; do
            IFS='|' read -r note_title note_db_path _ _ <<< "$note_line"
            if [[ "$note_db_path" == "$note_path" ]]; then
                BOOK_BASE_NOTE_LINES+=("$note_line")
                break
            fi
        done < "$NOTES_DB"
    done

    if ((${#BOOK_BASE_NOTE_LINES[@]} > 1)); then
        mapfile -t BOOK_BASE_NOTE_LINES < <(
            printf '%s\n' "${BOOK_BASE_NOTE_LINES[@]}" | sort -s -t'|' -k1,1f
        )
    fi
}

# Filter records by a tag. The internal sentinel is deliberately different
# from the menu label so an ordinary '[NO TAG]' tag remains selectable.
babyrus_book_filter_notes_by_tag() {
    local selected_tag="$1"
    shift
    local line title note_path note_tags rest current_tag
    local -a tag_array=()

    for line in "$@"; do
        IFS='|' read -r title note_path note_tags rest <<< "$line"
        if [[ "$selected_tag" == "__BABYRUS_BOOK_UNTAGGED__" ]]; then
            [[ -z "$note_tags" ]] && printf '%s\n' "$line"
            continue
        fi

        IFS=',' read -r -a tag_array <<< "$note_tags"
        for current_tag in "${tag_array[@]}"; do
            if [[ "$current_tag" == "$selected_tag" ]]; then
                printf '%s\n' "$line"
                break
            fi
        done
    done
}

# Case-insensitive Bash glob against the whole note title. Use *words* for
# contains-style matching.
babyrus_book_filter_notes_by_glob() {
    local pattern="$1"
    shift
    local lower_pattern="${pattern,,}"
    local line title

    for line in "$@"; do
        IFS='|' read -r title _ _ _ <<< "$line"
        if [[ "${title,,}" == $lower_pattern ]]; then
            printf '%s\n' "$line"
        fi
    done
}

babyrus_book_get_visible_notes() {
    local -a current_notes=("${BOOK_BASE_NOTE_LINES[@]}")

    if [[ -n "$BOOK_TAG_FILTER_BY" ]]; then
        mapfile -t current_notes < <(
            babyrus_book_filter_notes_by_tag "$BOOK_TAG_FILTER_BY" "${current_notes[@]}"
        )
    fi
    if [[ -n "$BOOK_GLOB_FILTER_BY" ]]; then
        mapfile -t current_notes < <(
            babyrus_book_filter_notes_by_glob "$BOOK_GLOB_FILTER_BY" "${current_notes[@]}"
        )
    fi

    ((${#current_notes[@]} > 0)) && printf '%s\n' "${current_notes[@]}"
}

# Get notes after glob filtering only. This allows the user to choose a
# different tag even when a tag filter is already active.
babyrus_book_get_glob_notes() {
    local -a current_notes=("${BOOK_BASE_NOTE_LINES[@]}")
    if [[ -n "$BOOK_GLOB_FILTER_BY" ]]; then
        mapfile -t current_notes < <(
            babyrus_book_filter_notes_by_glob "$BOOK_GLOB_FILTER_BY" "${current_notes[@]}"
        )
    fi
    ((${#current_notes[@]} > 0)) && printf '%s\n' "${current_notes[@]}"
}

babyrus_book_pick_note() {
    local -a visible_notes=() menu_items=()
    local line title path tags choice i filter_status=""
    local page=1 page_size=50 total_pages start end
    local term_rows term_cols box_h box_w list_h

    while :; do
        # Size the dialog for 50 notes per page: fixed width of 155 columns
        # (clamped to the terminal), and as tall as the terminal allows.
        # The list area scrolls if the terminal cannot show all entries at once.
        read -r term_rows term_cols < <(stty size </dev/tty 2>/dev/null)
        [[ "$term_rows" =~ ^[0-9]+$ ]] || term_rows=$(tput lines 2>/dev/null || echo 40)
        [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=$(tput cols 2>/dev/null || echo 155)
        box_w=170
        (( box_w > term_cols - 2 )) && box_w=$(( term_cols - 2 ))
        (( box_w < 60 )) && box_w=60
        box_h=$(( term_rows - 2 ))
        (( box_h > 60 )) && box_h=60
        (( box_h < 20 )) && box_h=20
        # Overhead: borders, message text (up to ~7 lines), blank line, buttons.
        list_h=$(( box_h - 13 ))
        (( list_h < 5 )) && list_h=5

        mapfile -t visible_notes < <(babyrus_book_get_visible_notes)
        menu_items=(
            "__FILTER_TAG__" "Filter by tag"
            "__RESET_TAG__" "Reset tag filter"
            "__APPLY_GLOB__" "Apply glob to note titles"
            "__RESET_GLOB__" "Reset glob"
        )

        total_pages=$(( (${#visible_notes[@]} + page_size - 1) / page_size ))
        (( total_pages < 1 )) && total_pages=1
        # Keep the current page between redraws, even after filter changes.
        (( page > total_pages )) && page=$total_pages
        start=$(( (page - 1) * page_size ))
        end=$(( start + page_size ))
        (( end > ${#visible_notes[@]} )) && end=${#visible_notes[@]}
        (( page > 1 )) && menu_items+=("__PREV_PAGE__" "<< Previous page")
        for ((i = start; i < end; i++)); do
            IFS='|' read -r title path tags _ <<< "${visible_notes[$i]}"
            [[ -n "$tags" ]] || tags="no tags"
            ((${#tags} > 60)) && tags="${tags:0:57}..."
            menu_items+=("$((i + 1))" "$title  [$tags]")
        done
        (( page < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page >>")

        filter_status="Active tag filter: none"
        [[ -n "$BOOK_TAG_FILTER_BY" ]] && {
            if [[ "$BOOK_TAG_FILTER_BY" == "__BABYRUS_BOOK_UNTAGGED__" ]]; then
                filter_status="Active tag filter: [NO TAG]"
            else
                filter_status="Active tag filter: $BOOK_TAG_FILTER_BY"
            fi
        }
        [[ -n "$BOOK_GLOB_FILTER_BY" ]] && \
            filter_status+=$'\nActive title glob: '"$BOOK_GLOB_FILTER_BY"

        choice=$(whiptail --title "Choose Note for Book Section" --cancel-button "Back" \
            --menu "Choose a note to add as a section (page $page/$total_pages, ${#visible_notes[@]} notes).\n$filter_status\n\nOnly associated notes are listed." \
            "$box_h" "$box_w" "$list_h" "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1

        case "$choice" in
            __PREV_PAGE__)
                (( page > 1 )) && ((page--))
                ;;
            __NEXT_PAGE__)
                (( page < total_pages )) && ((page++))
                ;;
            __FILTER_TAG__)
                page=1
                babyrus_book_choose_tag_filter || :
                ;;
            __RESET_TAG__)
                page=1
                BOOK_TAG_FILTER_BY=""
                ;;
            __APPLY_GLOB__)
                page=1
                local new_glob
                if new_glob=$(whiptail --title "Apply Glob to Note Titles" --inputbox \
                    "Enter a case-insensitive Bash glob. Examples: *Python* or Meeting-??\n\nThe pattern matches the whole title; use *text* for a contains match." \
                    12 85 "$BOOK_GLOB_FILTER_BY" 3>&1 1>&2 2>&3); then
                    if [[ -z "$new_glob" ]]; then
                        whiptail --title "Empty Glob" --msgbox \
                            "The glob cannot be empty. Use * to match all titles, or choose Reset glob." 9 75
                    else
                        BOOK_GLOB_FILTER_BY="$new_glob"
                    fi
                fi
                ;;
            __RESET_GLOB__)
                page=1
                BOOK_GLOB_FILTER_BY=""
                ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || continue
                i=$((choice - 1))
                (( i >= start && i < end )) || continue
                IFS='|' read -r BOOK_SELECTED_NOTE_TITLE BOOK_SELECTED_NOTE_PATH _ _ \
                    <<< "${visible_notes[$i]}"
                return 0
                ;;
        esac
    done
}

babyrus_book_choose_tag_filter() {
    local -a glob_notes=() tag_menu_items=()
    local line title path tags tag choice
    local has_untagged=false
    local -A seen_tags=()

    mapfile -t glob_notes < <(babyrus_book_get_glob_notes)
    if ((${#glob_notes[@]} == 0)); then
        whiptail --title "Filter by Tag" --msgbox \
            "No associated notes match the current title glob." 8 65
        return 1
    fi

    for line in "${glob_notes[@]}"; do
        IFS='|' read -r title path tags _ <<< "$line"
        if [[ -z "$tags" ]]; then
            has_untagged=true
            continue
        fi
        local -a split_tags=()
        IFS=',' read -r -a split_tags <<< "$tags"
        for tag in "${split_tags[@]}"; do
            [[ -n "$tag" ]] && seen_tags["$tag"]=1
        done
    done

    [[ "$has_untagged" == true ]] && tag_menu_items+=("[NO TAG]" "Notes without tags")
    if ((${#seen_tags[@]} > 0)); then
        while IFS= read -r tag; do
            [[ -n "$tag" ]] && tag_menu_items+=("$tag" "")
        done < <(printf '%s\n' "${!seen_tags[@]}" | sort -f)
    fi

    if ((${#tag_menu_items[@]} == 0)); then
        whiptail --title "Filter by Tag" --msgbox \
            "No tags are available among notes matching the current title glob." 9 75
        return 1
    fi

    local page=1 page_size=30 total_tags start end j
    total_tags=$(( ${#tag_menu_items[@]} / 2 ))
    while :; do
        local -a page_items=()
        local total_pages=$(( (total_tags + page_size - 1) / page_size ))
        start=$(( (page - 1) * page_size * 2 ))
        end=$(( start + page_size * 2 ))
        (( end > ${#tag_menu_items[@]} )) && end=${#tag_menu_items[@]}
        (( page > 1 )) && page_items+=("__PREV_PAGE__" "<< Previous page")
        for ((j=start; j<end; j+=2)); do
            page_items+=("${tag_menu_items[j]}" "${tag_menu_items[j+1]}")
        done
        (( page < total_pages )) && page_items+=("__NEXT_PAGE__" "Next page >>")
        choice=$(whiptail --title "Filter Associated Notes by Tag" --cancel-button "Back" \
            --menu "Choose a tag (page $page/$total_pages). The current title glob remains active." \
            42 80 30 "${page_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1
        case "$choice" in
            __PREV_PAGE__) ((page--)); continue ;;
            __NEXT_PAGE__) ((page++)); continue ;;
            *) break ;;
        esac
    done

    if [[ "$choice" == "[NO TAG]" ]]; then
        BOOK_TAG_FILTER_BY="__BABYRUS_BOOK_UNTAGGED__"
    else
        BOOK_TAG_FILTER_BY="$choice"
    fi
}

babyrus_book_rebuild_numbers() {
    local -a counters=()
    local i level j number
    BOOK_SECTION_NUMBERS=()

    for i in "${!BOOK_SECTION_LEVELS[@]}"; do
        level="${BOOK_SECTION_LEVELS[$i]}"
        while ((${#counters[@]} < level)); do
            counters+=(0)
        done

        counters[$((level - 1))]=$(( ${counters[$((level - 1))]:-0} + 1 ))
        for ((j = level; j < ${#counters[@]}; j++)); do
            counters[$j]=0
        done

        number="${counters[0]}"
        for ((j = 1; j < level; j++)); do
            number+=".${counters[$j]}"
        done
        BOOK_SECTION_NUMBERS[$i]="$number"
    done
}

babyrus_book_outline_is_valid() {
    local i level previous_level=0
    local count="${#BOOK_SECTION_LEVELS[@]}"
    (( count == 0 )) && return 0

    for i in "${!BOOK_SECTION_LEVELS[@]}"; do
        level="${BOOK_SECTION_LEVELS[$i]}"
        (( level >= 1 )) || return 1
        if (( i == 0 )); then
            (( level == 1 )) || return 1
        else
            (( level <= previous_level + 1 )) || return 1
        fi
        previous_level="$level"
    done
    return 0
}

babyrus_book_outline_text() {
    local i prefix
    babyrus_book_rebuild_numbers
    for i in "${!BOOK_SECTION_PATHS[@]}"; do
        prefix="${BOOK_SECTION_NUMBERS[$i]}"
        (( BOOK_SECTION_LEVELS[$i] == 1 )) && prefix+="."
        printf '%*s%s %s\n' \
            "$(( (BOOK_SECTION_LEVELS[$i] - 1) * 2 ))" "" \
            "$prefix" "${BOOK_SECTION_TITLES[$i]}"
    done
}

babyrus_book_select_section() {
    local menu_title="$1"
    local -a menu_items=()
    local i choice

    if ((${#BOOK_SECTION_PATHS[@]} == 0)); then
        whiptail --title "$menu_title" --msgbox "There are no sections in this book draft." 8 60
        return 1
    fi

    babyrus_book_rebuild_numbers
    for i in "${!BOOK_SECTION_PATHS[@]}"; do
        menu_items+=("$((i + 1))" \
            "${BOOK_SECTION_NUMBERS[$i]} [level ${BOOK_SECTION_LEVELS[$i]}] ${BOOK_SECTION_TITLES[$i]}")
    done

    choice=$(whiptail --title "$menu_title" --cancel-button "Back" \
        --menu "Choose a section." 22 100 14 \
        "${menu_items[@]}" 3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1

    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    BOOK_SELECTED_SECTION_INDEX=$((choice - 1))
    (( BOOK_SELECTED_SECTION_INDEX >= 0 && BOOK_SELECTED_SECTION_INDEX < ${#BOOK_SECTION_PATHS[@]} ))
}

# Let the user choose sections repeatedly and read the current source-note
# content in a scrollable whiptail textbox. The header records the section's
# current outline metadata and provenance without modifying the book.
babyrus_book_read_sections() {
    local index section_number section_title section_level source_path
    local source_project_title source_project_path temp_file
    local term_rows term_cols box_h box_w

    if ((${#BOOK_SECTION_PATHS[@]} == 0)); then
        whiptail --title "Read Sections" --msgbox \
            "There are no sections in this book yet. Add a section first." 8 65
        return 0
    fi

    while :; do
        # Cancelling the section picker returns to the main book editor.
        babyrus_book_select_section "Read Sections: Choose a Section" || return 0
        index="$BOOK_SELECTED_SECTION_INDEX"
        babyrus_book_rebuild_numbers

        section_number="${BOOK_SECTION_NUMBERS[$index]}"
        section_title="${BOOK_SECTION_TITLES[$index]}"
        section_level="${BOOK_SECTION_LEVELS[$index]}"
        source_path="${BOOK_SECTION_PATHS[$index]}"
        source_project_title="${BOOK_SECTION_SOURCE_PROJECT_TITLES[$index]:-${BOOK_PROJECT_TITLE:-Unknown}}"
        source_project_path="${BOOK_SECTION_SOURCE_PROJECT_PATHS[$index]:-${BOOK_PROJECT_PATH:-Unknown}}"

        temp_file=$(mktemp "${TMPDIR:-/tmp}/babyrus-book-section.XXXXXX") || {
            whiptail --title "Read Section" --msgbox \
                "Could not create a temporary file to display this section." 8 70
            return 0
        }

        if ! {
            printf '%s\n' \
                "BOOK: ${BOOK_TITLE:-Untitled}" \
                "SECTION: ${section_number}  ${section_title}" \
                "Outline position: $((index + 1)) of ${#BOOK_SECTION_PATHS[@]}" \
                "Indentation level: $section_level" \
                "Source note title: $section_title" \
                "Source note path: $source_path" \
                "Source project title: $source_project_title" \
                "Source project path: $source_project_path"
            [[ -n "${BOOK_FILE_PATH:-}" ]] && printf 'Saved book path: %s\n' "$BOOK_FILE_PATH"
            printf '\n%s\n\n' '-------------------- SECTION CONTENT --------------------'
            if [[ -f "$source_path" && -r "$source_path" ]]; then
                cat -- "$source_path"
            else
                printf '%s\n' \
                    'The source note file is missing or unreadable, so its contents cannot be displayed.' \
                    '' \
                    "Expected source note path: $source_path"
            fi
        } > "$temp_file"; then
            rm -f -- "$temp_file"
            whiptail --title "Read Section" --msgbox \
                "Could not prepare the section contents for display." 8 70
            return 0
        fi

        read -r term_rows term_cols < <(stty size </dev/tty 2>/dev/null)
        [[ "$term_rows" =~ ^[0-9]+$ ]] || term_rows=$(tput lines 2>/dev/null || echo 40)
        [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=$(tput cols 2>/dev/null || echo 100)
        box_h=$((term_rows - 2)); (( box_h > 60 )) && box_h=60; (( box_h < 12 )) && box_h=12
        box_w=120; (( box_w > term_cols - 2 )) && box_w=$((term_cols - 2)); (( box_w < 60 )) && box_w=60

        whiptail --title "Read Section: ${section_number} ${section_title}" \
            --scrolltext --textbox "$temp_file" "$box_h" "$box_w" </dev/tty >/dev/tty || :
        rm -f -- "$temp_file"
    done
}

# Reorders a section together with all of its descendants, and only among
# siblings with the same outline level.
babyrus_book_move_section() {
    local direction="$1"
    local index="$2"
    local count="${#BOOK_SECTION_LEVELS[@]}"
    local depth end sibling sibling_end j

    depth="${BOOK_SECTION_LEVELS[$index]}"
    end=$((index + 1))
    while (( end < count )) && (( BOOK_SECTION_LEVELS[end] > depth )); do
        ((end++))
    done

    if [[ "$direction" == "up" ]]; then
        sibling=-1
        j=$((index - 1))
        while (( j >= 0 )); do
            if (( BOOK_SECTION_LEVELS[j] < depth )); then
                break
            elif (( BOOK_SECTION_LEVELS[j] == depth )); then
                sibling="$j"
                break
            fi
            ((j--))
        done

        if (( sibling < 0 )); then
            whiptail --title "Move Section Up" --msgbox \
                "There is no previous sibling section at the same indentation level." 9 75
            return 1
        fi

        BOOK_SECTION_PATHS=(
            "${BOOK_SECTION_PATHS[@]:0:$sibling}"
            "${BOOK_SECTION_PATHS[@]:$index:$((end - index))}"
            "${BOOK_SECTION_PATHS[@]:$sibling:$((index - sibling))}"
            "${BOOK_SECTION_PATHS[@]:$end}"
        )
        BOOK_SECTION_TITLES=(
            "${BOOK_SECTION_TITLES[@]:0:$sibling}"
            "${BOOK_SECTION_TITLES[@]:$index:$((end - index))}"
            "${BOOK_SECTION_TITLES[@]:$sibling:$((index - sibling))}"
            "${BOOK_SECTION_TITLES[@]:$end}"
        )
        BOOK_SECTION_LEVELS=(
            "${BOOK_SECTION_LEVELS[@]:0:$sibling}"
            "${BOOK_SECTION_LEVELS[@]:$index:$((end - index))}"
            "${BOOK_SECTION_LEVELS[@]:$sibling:$((index - sibling))}"
            "${BOOK_SECTION_LEVELS[@]:$end}"
        )
        BOOK_SECTION_SOURCE_PROJECT_TITLES=(
            "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:0:$sibling}"
            "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:$index:$((end - index))}"
            "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:$sibling:$((index - sibling))}"
            "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:$end}"
        )
        BOOK_SECTION_SOURCE_PROJECT_PATHS=(
            "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:0:$sibling}"
            "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:$index:$((end - index))}"
            "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:$sibling:$((index - sibling))}"
            "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:$end}"
        )
    else
        if (( end >= count )) || (( BOOK_SECTION_LEVELS[end] != depth )); then
            whiptail --title "Move Section Down" --msgbox \
                "There is no next sibling section at the same indentation level." 9 75
            return 1
        fi

        sibling="$end"
        sibling_end=$((sibling + 1))
        while (( sibling_end < count )) && (( BOOK_SECTION_LEVELS[sibling_end] > depth )); do
            ((sibling_end++))
        done

        BOOK_SECTION_PATHS=(
            "${BOOK_SECTION_PATHS[@]:0:$index}"
            "${BOOK_SECTION_PATHS[@]:$sibling:$((sibling_end - sibling))}"
            "${BOOK_SECTION_PATHS[@]:$index:$((end - index))}"
            "${BOOK_SECTION_PATHS[@]:$sibling_end}"
        )
        BOOK_SECTION_TITLES=(
            "${BOOK_SECTION_TITLES[@]:0:$index}"
            "${BOOK_SECTION_TITLES[@]:$sibling:$((sibling_end - sibling))}"
            "${BOOK_SECTION_TITLES[@]:$index:$((end - index))}"
            "${BOOK_SECTION_TITLES[@]:$sibling_end}"
        )
        BOOK_SECTION_LEVELS=(
            "${BOOK_SECTION_LEVELS[@]:0:$index}"
            "${BOOK_SECTION_LEVELS[@]:$sibling:$((sibling_end - sibling))}"
            "${BOOK_SECTION_LEVELS[@]:$index:$((end - index))}"
            "${BOOK_SECTION_LEVELS[@]:$sibling_end}"
        )
        BOOK_SECTION_SOURCE_PROJECT_TITLES=(
            "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:0:$index}"
            "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:$sibling:$((sibling_end - sibling))}"
            "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:$index:$((end - index))}"
            "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:$sibling_end}"
        )
        BOOK_SECTION_SOURCE_PROJECT_PATHS=(
            "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:0:$index}"
            "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:$sibling:$((sibling_end - sibling))}"
            "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:$index:$((end - index))}"
            "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:$sibling_end}"
        )
    fi

    if babyrus_book_outline_is_valid; then
        BOOK_SAVED=0
    else
        whiptail --title "Move Section" --msgbox \
            "The move would produce an invalid outline. No save was made." 9 75
        return 1
    fi
}

babyrus_book_change_indentation() {
    local index old_level new_level delta end i direction

    babyrus_book_select_section "Select Section to Indent/Outdent" || return 1
    index="$BOOK_SELECTED_SECTION_INDEX"
    old_level="${BOOK_SECTION_LEVELS[$index]}"

    direction=$(whiptail --title "Change Section Indentation" --cancel-button "Back" \
        --menu "Selected section: ${BOOK_SECTION_TITLES[$index]}\nCurrent indentation level: $old_level\n\nChange the selected section and its subsections together." \
        14 85 4 \
        "indent" "Indent one level (make it a subsection)" \
        "outdent" "Outdent one level (make it less nested)" \
        3>&1 1>&2 2>&3 </dev/tty >/dev/tty) || return 1

    if [[ "$direction" == "indent" ]]; then
        new_level=$((old_level + 1))
        if (( index == 0 )) || (( new_level > BOOK_SECTION_LEVELS[index - 1] + 1 )); then
            whiptail --title "Cannot Indent Section" --msgbox \
                "This section cannot be indented further because it would have no valid parent section." 9 78
            return 1
        fi
        delta=1
    else
        new_level=$((old_level - 1))
        if (( new_level < 1 )); then
            whiptail --title "Cannot Outdent Section" --msgbox \
                "A section cannot be outdented above level 1." 8 60
            return 1
        fi
        delta=-1
    fi

    end=$((index + 1))
    while (( end < ${#BOOK_SECTION_LEVELS[@]} )) && (( BOOK_SECTION_LEVELS[end] > old_level )); do
        ((end++))
    done

    local -a previous_levels=("${BOOK_SECTION_LEVELS[@]}")
    for ((i = index; i < end; i++)); do
        BOOK_SECTION_LEVELS[$i]=$(( BOOK_SECTION_LEVELS[i] + delta ))
    done

    if babyrus_book_outline_is_valid; then
        BOOK_SAVED=0
    else
        BOOK_SECTION_LEVELS=("${previous_levels[@]}")
        whiptail --title "Invalid Indentation" --msgbox \
            "That indentation change would make the outline invalid, so it was cancelled." 9 78
        return 1
    fi
}

babyrus_book_remove_section() {
    local index="$1"
    local depth end count="${#BOOK_SECTION_LEVELS[@]}"

    depth="${BOOK_SECTION_LEVELS[$index]}"
    end=$((index + 1))
    while (( end < count )) && (( BOOK_SECTION_LEVELS[end] > depth )); do
        ((end++))
    done

    if (( end > index + 1 )); then
        if ! whiptail --title "Remove Subsections" --yesno \
            "This section has subsections. Remove the selected section and all of its subsections?" 9 78; then
            return 1
        fi
    fi

    BOOK_SECTION_PATHS=("${BOOK_SECTION_PATHS[@]:0:$index}" "${BOOK_SECTION_PATHS[@]:$end}")
    BOOK_SECTION_TITLES=("${BOOK_SECTION_TITLES[@]:0:$index}" "${BOOK_SECTION_TITLES[@]:$end}")
    BOOK_SECTION_LEVELS=("${BOOK_SECTION_LEVELS[@]:0:$index}" "${BOOK_SECTION_LEVELS[@]:$end}")
    BOOK_SECTION_SOURCE_PROJECT_TITLES=("${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:0:$index}" "${BOOK_SECTION_SOURCE_PROJECT_TITLES[@]:$end}")
    BOOK_SECTION_SOURCE_PROJECT_PATHS=("${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:0:$index}" "${BOOK_SECTION_SOURCE_PROJECT_PATHS[@]:$end}")
    BOOK_SAVED=0
}

babyrus_book_default_path() {
    local source_path="${BOOK_ORIGINAL_PROJECT_PATH:-$BOOK_PROJECT_PATH}"
    local base="${source_path%.txt}"
    [[ "$base" == "$source_path" ]] && base="$source_path"
    printf '%s\n' "${base}.book.txt"
}

# Return success if the requested book path points at a project, database, or
# source note. This guards against accidentally overwriting source material.
babyrus_book_is_protected_path() {
    local target="$1"
    local candidate resolved_target resolved_candidate
    local -a protected_paths=("$BOOK_PROJECT_PATH" "$PROJECTS_DB" "$NOTES_DB" "${BOOK_SECTION_PATHS[@]}")

    resolved_target=$(realpath -m -- "$target" 2>/dev/null) || resolved_target="$target"
    for candidate in "${protected_paths[@]}"; do
        [[ -n "$candidate" ]] || continue
        resolved_candidate=$(realpath -m -- "$candidate" 2>/dev/null) || resolved_candidate="$candidate"
        [[ "$resolved_target" == "$resolved_candidate" ]] && return 0
    done
    return 1
}

# Register a successfully saved book as one absolute path per line in BOOKS_LIST.
# Existing entries are compared by resolved path, so saving the same book again
# does not add duplicate entries.
babyrus_book_register_saved_path() {
    local book_path="$1" list_file="${BOOKS_LIST:-}" list_dir row existing_path

    if [[ -z "$list_file" ]]; then
        whiptail --title "Book List Not Configured" --msgbox \
            "BOOKS_LIST is not set. Set it to the path of the saved-books list in BABYRUS configuration." 10 80
        return 1
    fi

    list_file="${list_file/#\~\//$HOME/}"
    list_file=$(realpath -m -- "$list_file" 2>/dev/null) || {
        whiptail --title "Book List Error" --msgbox "Cannot resolve BOOKS_LIST:\n$list_file" 9 75
        return 1
    }
    book_path=$(realpath -m -- "$book_path" 2>/dev/null) || {
        whiptail --title "Book List Error" --msgbox "Cannot resolve the saved book path." 8 60
        return 1
    }

    list_dir=$(dirname -- "$list_file")
    if ! mkdir -p -- "$list_dir"; then
        whiptail --title "Book List Error" --msgbox \
            "Cannot create the directory for BOOKS_LIST:\n$list_dir" 9 80
        return 1
    fi
    if [[ -e "$list_file" && ! -f "$list_file" ]]; then
        whiptail --title "Book List Error" --msgbox \
            "BOOKS_LIST is not a regular file:\n$list_file" 9 75
        return 1
    fi
    if [[ -e "$list_file" && ! -r "$list_file" ]]; then
        whiptail --title "Book List Error" --msgbox \
            "BOOKS_LIST exists but cannot be read:\n$list_file" 9 75
        return 1
    fi

    if [[ -r "$list_file" ]]; then
        while IFS= read -r row || [[ -n "$row" ]]; do
            [[ -n "$row" ]] || continue
            row="${row/#\~\//$HOME/}"
            existing_path=$(realpath -m -- "$row" 2>/dev/null) || existing_path="$row"
            if [[ "$existing_path" == "$book_path" ]]; then
                return 0
            fi
        done < "$list_file"
    fi

    if ! printf '%s\n' "$book_path" >> "$list_file"; then
        whiptail --title "Book List Error" --msgbox \
            "The book was saved, but its path could not be added to BOOKS_LIST:\n$list_file" 10 85
        return 1
    fi
    return 0
}

babyrus_book_save() {
    local default_path destination destination_dir destination_base temp_file
    local i j number heading_prefix generated_at source_index project_title project_path
    local -a source_project_titles=() source_project_paths=()

    if [[ -z "${BOOKS_LIST:-}" ]]; then
        whiptail --title "Book List Not Configured" --msgbox \
            "Set BOOKS_LIST in BABYRUS configuration before saving books, so saved paths can be recorded." 10 82
        return 1
    fi

    if ((${#BOOK_SECTION_PATHS[@]} == 0)); then
        whiptail --title "Save Book" --msgbox \
            "Add at least one section before saving the book." 8 65
        return 1
    fi

    for i in "${!BOOK_SECTION_PATHS[@]}"; do
        if [[ ! -f "${BOOK_SECTION_PATHS[$i]}" || ! -r "${BOOK_SECTION_PATHS[$i]}" ]]; then
            whiptail --title "Cannot Save Book" --msgbox \
                "A source note file does not exist or cannot be read:\n${BOOK_SECTION_PATHS[$i]}" 10 85
            return 1
        fi
    done

    # Build a unique project list in first-use order from the sections that
    # remain in the book. A project with no remaining sections is not listed as
    # a source, even if it was selected earlier during this editing session.
    for i in "${!BOOK_SECTION_PATHS[@]}"; do
        project_title="${BOOK_SECTION_SOURCE_PROJECT_TITLES[$i]:-$BOOK_PROJECT_TITLE}"
        project_path="${BOOK_SECTION_SOURCE_PROJECT_PATHS[$i]:-$BOOK_PROJECT_PATH}"
        [[ -n "$project_path" ]] || continue
        source_index=-1
        for ((j = 0; j < ${#source_project_paths[@]}; j++)); do
            if [[ "${source_project_paths[$j]}" == "$project_path" ]]; then
                source_index=$j
                break
            fi
        done
        if (( source_index < 0 )); then
            source_project_titles+=("$project_title")
            source_project_paths+=("$project_path")
        fi
    done

    default_path="$BOOK_FILE_PATH"
    [[ -n "$default_path" ]] || default_path="$(babyrus_book_default_path)"
    if ! destination=$(whiptail --title "Save Book" --inputbox \
        "Enter the destination path for the generated text book." \
        10 90 "$default_path" 3>&1 1>&2 2>&3); then
        return 1
    fi
    [[ -n "$destination" ]] || {
        whiptail --title "Save Book" --msgbox "The destination path cannot be empty." 8 60
        return 1
    }

    case "$destination" in
        "~/"*) destination="$HOME/${destination#~/}" ;;
    esac
    # This feature always writes plain-text book files.
    [[ "${destination,,}" == *.txt ]] || destination+=".txt"
    # Normalize the destination so BOOKS_LIST stores an absolute path.
    destination=$(realpath -m -- "$destination" 2>/dev/null) || {
        whiptail --title "Save Failed" --msgbox "Cannot resolve the destination path." 8 60
        return 1
    }

    babyrus_book_is_protected_path "$destination" && {
        whiptail --title "Protected Path" --msgbox \
            "The destination is one of the project, database, or source-note files. Choose a different path." \
            10 80
        return 1
    }

    if [[ -e "$destination" ]]; then
        if ! whiptail --title "Overwrite Book File" --yesno \
            "This file already exists. Replace it?\n\n$destination" 10 85; then
            return 1
        fi
    fi

    destination_dir=$(dirname -- "$destination")
    destination_base=$(basename -- "$destination")
    if ! mkdir -p -- "$destination_dir"; then
        whiptail --title "Save Failed" --msgbox \
            "Could not create the destination directory:\n$destination_dir" 9 80
        return 1
    fi

    temp_file=$(mktemp --tmpdir="$destination_dir" ".${destination_base}.tmp.XXXXXX") || {
        whiptail --title "Save Failed" --msgbox \
            "Could not create a temporary file in:\n$destination_dir" 9 80
        return 1
    }

    babyrus_book_rebuild_numbers
    generated_at=$(date '+%Y-%m-%d %H:%M:%S %z')

    if ! {
        printf '%s\n' \
            '[BEGIN BABYRUS BOOK METADATA]' \
            'Format: BABYRUS-BOOK/1' \
            "Book-Title: $BOOK_TITLE" \
            "Source-Project-Title: $BOOK_PROJECT_TITLE" \
            "Source-Project-Path: $BOOK_PROJECT_PATH" \
            "Source-Project-Count: ${#source_project_paths[@]}" \
            "Generated: $generated_at" \
            "Section-Count: ${#BOOK_SECTION_PATHS[@]}" \
            'Numbering-Rule: Calculated from section order and indentation level.'
        for i in "${!source_project_paths[@]}"; do
            printf '%s\n' \
                "Source-Project-$((i + 1))-Title: ${source_project_titles[$i]}" \
                "Source-Project-$((i + 1))-Path: ${source_project_paths[$i]}"
        done
        printf '%s\n\n' '[END BABYRUS BOOK METADATA]' '[BEGIN SECTION MANIFEST]'
        for i in "${!BOOK_SECTION_PATHS[@]}"; do
            project_title="${BOOK_SECTION_SOURCE_PROJECT_TITLES[$i]:-$BOOK_PROJECT_TITLE}"
            project_path="${BOOK_SECTION_SOURCE_PROJECT_PATHS[$i]:-$BOOK_PROJECT_PATH}"
            printf '%s\n' \
                '[BEGIN SECTION METADATA]' \
                "Order: $((i + 1))" \
                "Number: ${BOOK_SECTION_NUMBERS[$i]}" \
                "Indentation-Level: ${BOOK_SECTION_LEVELS[$i]}" \
                "Title: ${BOOK_SECTION_TITLES[$i]}" \
                "Source-Note-Path: ${BOOK_SECTION_PATHS[$i]}" \
                "Source-Project-Title: $project_title" \
                "Source-Project-Path: $project_path" \
                '[END SECTION METADATA]' \
                ''
        done
        printf '%s\n\n' '[END SECTION MANIFEST]' '[BEGIN BOOK CONTENT]'
    } > "$temp_file"; then
        rm -f -- "$temp_file"
        whiptail --title "Save Failed" --msgbox "Could not write the book metadata." 8 60
        return 1
    fi

    for i in "${!BOOK_SECTION_PATHS[@]}"; do
        number="${BOOK_SECTION_NUMBERS[$i]}"
        if ! {
            printf '\n%s\n' "[BEGIN SECTION $((i + 1)) | Number: $number | Level: ${BOOK_SECTION_LEVELS[$i]}]"
            heading_prefix="$number"
            (( BOOK_SECTION_LEVELS[$i] == 1 )) && heading_prefix+="."
            printf '%s\n' "# $heading_prefix ${BOOK_SECTION_TITLES[$i]}"
            printf '%s\n' "[Source note title: ${BOOK_SECTION_TITLES[$i]}]"
            printf '%s\n' "[Source note path: ${BOOK_SECTION_PATHS[$i]}]"
            printf '%s\n\n' '-------------------- CONTENT --------------------'
        } >> "$temp_file"; then
            rm -f -- "$temp_file"
            whiptail --title "Save Failed" --msgbox \
                "Could not write a section heading into the book." 9 70
            return 1
        fi

        if ! cat -- "${BOOK_SECTION_PATHS[$i]}" >> "$temp_file"; then
            rm -f -- "$temp_file"
            whiptail --title "Save Failed" --msgbox \
                "An error occurred while copying a note into the book." 9 70
            return 1
        fi

        if ! printf '\n%s\n\n' "[END SECTION $((i + 1))]" >> "$temp_file"; then
            rm -f -- "$temp_file"
            whiptail --title "Save Failed" --msgbox \
                "Could not write a section ending into the book." 9 70
            return 1
        fi
    done

    if ! printf '%s\n' '[END BOOK CONTENT]' >> "$temp_file"; then
        rm -f -- "$temp_file"
        whiptail --title "Save Failed" --msgbox "Could not finish writing the book file." 8 65
        return 1
    fi

    if ! mv -f -- "$temp_file" "$destination"; then
        rm -f -- "$temp_file"
        whiptail --title "Save Failed" --msgbox \
            "Could not move the completed book into place:\n$destination" 10 85
        return 1
    fi

    BOOK_FILE_PATH="$destination"
    BOOK_SAVED=1
    if ! babyrus_book_register_saved_path "$destination"; then
        whiptail --title "Book Saved, List Update Failed" --msgbox \
            "The book itself was saved successfully:\n$destination\n\nHowever, its path could not be recorded in BOOKS_LIST. Fix the list configuration or permissions before relying on the Load Existing Book to Edit menu." 12 90
        return 1
    fi
    whiptail --title "Book Saved" --msgbox \
        "The book was saved successfully and its full path was recorded in BOOKS_LIST:\n$destination" 11 90
}


# Show registered book files from BOOKS_LIST in a paginated selector.
# Only readable regular files are offered; paths containing spaces are preserved.
babyrus_book_select_existing_path() {
    local list_file="${BOOKS_LIST:-}" row canonical existing duplicate
    local page_size=10 page=0 total_pages start end i choice
    local -a book_paths=() menu_items=()

    if [[ -z "$list_file" ]]; then
        whiptail --title "Load Book" --msgbox \
            "BOOKS_LIST is not set. Configure it in BABYRUS before loading saved books." 9 78 >/dev/tty </dev/tty
        return 1
    fi
    list_file="${list_file/#\~\//$HOME/}"
    list_file=$(realpath -m -- "$list_file" 2>/dev/null) || {
        whiptail --title "Load Book" --msgbox "Cannot resolve BOOKS_LIST:\n$list_file" 9 75 >/dev/tty </dev/tty
        return 1
    }
    if [[ ! -r "$list_file" ]]; then
        whiptail --title "Load Book" --msgbox \
            "The book list does not exist or cannot be read:\n$list_file\n\nSave a book first, or check BOOKS_LIST." 10 80 >/dev/tty </dev/tty
        return 1
    fi

    while IFS= read -r row || [[ -n "$row" ]]; do
        [[ -n "$row" ]] || continue
        row="${row/#\~\//$HOME/}"
        canonical=$(realpath -m -- "$row" 2>/dev/null) || continue
        [[ -f "$canonical" && -r "$canonical" ]] || continue
        duplicate=0
        for existing in "${book_paths[@]}"; do
            if [[ "$existing" == "$canonical" ]]; then duplicate=1; break; fi
        done
        (( duplicate )) || book_paths+=("$canonical")
    done < "$list_file"

    if ((${#book_paths[@]} == 0)); then
        whiptail --title "Load Book" --msgbox \
            "There are no readable book files in:\n$list_file\n\nSave a book first or check the paths in the list." 10 80 >/dev/tty </dev/tty
        return 1
    fi

    total_pages=$(( (${#book_paths[@]} + page_size - 1) / page_size ))
    while :; do
        start=$((page * page_size))
        end=$((start + page_size))
        menu_items=()
        for ((i = start; i < end && i < ${#book_paths[@]}; i++)); do
            menu_items+=("$i" "${book_paths[$i]}")
        done
        (( page > 0 )) && menu_items+=("__PREVIOUS_PAGE__" "Previous page")
        (( page + 1 < total_pages )) && menu_items+=("__NEXT_PAGE__" "Next page")

        choice=$(whiptail --title "Load Existing Book to Edit" \
            --menu "Select a saved book (page $((page + 1)) of $total_pages)." \
            22 100 12 "${menu_items[@]}" 3>&1 1>&2 2>&3 >/dev/tty </dev/tty) || return 1
        case "$choice" in
            __PREVIOUS_PAGE__) ((page--)); continue ;;
            __NEXT_PAGE__) ((page++)); continue ;;
            ''|*[!0-9]*) return 1 ;;
        esac
        (( choice >= 0 && choice < ${#book_paths[@]} )) || return 1
        printf '%s\n' "${book_paths[$choice]}"
        return 0
    done
}

# Load a previously generated BABYRUS book selected from BOOKS_LIST. The
# manifest restores the section outline; source note paths are retained so
# the book can be edited and saved.
babyrus_book_load_existing() {
    local source line title path level number section_project_title section_project_path
    local -a new_paths=() new_titles=() new_levels=() new_source_project_titles=() new_source_project_paths=()
    source=$(babyrus_book_select_existing_path) || return 1
    [[ -n "$source" ]] || return 1
    [[ -r "$source" && -f "$source" ]] || {
        whiptail --title "Load Book" --msgbox "Cannot read this file:\n$source" 9 75
        return 1
    }

    local in_manifest=0 in_section=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            '[BEGIN SECTION MANIFEST]') in_manifest=1; continue ;;
            '[END SECTION MANIFEST]') in_manifest=0; continue ;;
            '[BEGIN SECTION METADATA]')
                if (( in_manifest )); then
                    in_section=1
                    title= path= level= number= section_project_title= section_project_path=
                fi
                continue ;;
            '[END SECTION METADATA]')
                if (( in_manifest && in_section )); then
                    if [[ -n "$path" && -n "$title" && "$level" =~ ^[0-9]+$ ]]; then
                        new_paths+=("$path")
                        new_titles+=("$title")
                        new_levels+=("$level")
                        # Older book files only had one project in the top-level
                        # metadata; use it when section-level provenance is absent.
                        new_source_project_titles+=("${section_project_title:-$BOOK_PROJECT_TITLE}")
                        new_source_project_paths+=("${section_project_path:-$BOOK_PROJECT_PATH}")
                    fi
                fi
                in_section=0; continue ;;
        esac
        (( in_manifest && in_section )) || {
            if [[ "$line" == Book-Title:* ]]; then BOOK_TITLE="${line#Book-Title: }"; fi
            if [[ "$line" == Source-Project-Title:* ]]; then BOOK_PROJECT_TITLE="${line#Source-Project-Title: }"; fi
            if [[ "$line" == Source-Project-Path:* ]]; then BOOK_PROJECT_PATH="${line#Source-Project-Path: }"; fi
            continue
        }
        case "$line" in
            Order:*) ;;
            Number:*) number="${line#Number: }" ;;
            Indentation-Level:*) level="${line#Indentation-Level: }" ;;
            Title:*) title="${line#Title: }" ;;
            Source-Note-Path:*) path="${line#Source-Note-Path: }" ;;
            Source-Project-Title:*) section_project_title="${line#Source-Project-Title: }" ;;
            Source-Project-Path:*) section_project_path="${line#Source-Project-Path: }" ;;
        esac
    done < "$source"

    if ((${#new_paths[@]} == 0)); then
        whiptail --title "Load Book" --msgbox \
            "No BABYRUS section manifest was found. Only BABYRUS book files created by this feature can be loaded for outline editing." 10 85
        return 1
    fi
    BOOK_SECTION_PATHS=("${new_paths[@]}")
    BOOK_SECTION_TITLES=("${new_titles[@]}")
    BOOK_SECTION_LEVELS=("${new_levels[@]}")
    BOOK_SECTION_SOURCE_PROJECT_TITLES=("${new_source_project_titles[@]}")
    BOOK_SECTION_SOURCE_PROJECT_PATHS=("${new_source_project_paths[@]}")
    BOOK_FILE_PATH="$source"
    BOOK_SAVED=1
    if ! babyrus_book_outline_is_valid; then
        BOOK_SECTION_PATHS=(); BOOK_SECTION_TITLES=(); BOOK_SECTION_LEVELS=()
        whiptail --title "Load Book" --msgbox \
            "The saved section outline is invalid. The book was not loaded." 9 75
        return 1
    fi
    whiptail --title "Book Loaded" --msgbox \
        "Loaded ${#BOOK_SECTION_PATHS[@]} sections from:\n$source\n\nYou can now reorder, indent, add, or remove sections and save the book." 11 85
}

# Create a clean Markdown staging file containing only numbered headings and
# note content. Metadata and manifest are intentionally excluded from the PDF.
babyrus_book_convert_to_pdf() {
    local destination destination_dir temp_md temp_pdf temp_txt temp_header i heading_marks heading_prefix converter max_backticks fence_length fence
    if ((${#BOOK_SECTION_PATHS[@]} == 0)); then
        whiptail --title "Convert Book to PDF" --msgbox \
            "Add or load a book with at least one section first." 8 70
        return 1
    fi
    destination="${BOOK_FILE_PATH%.txt}.pdf"
    [[ -n "$BOOK_FILE_PATH" && "$destination" != "$BOOK_FILE_PATH" ]] || \
        destination="$(babyrus_book_default_path)"
    destination="${destination%.txt}.pdf"
    destination=$(whiptail --title "Convert Book to PDF" --inputbox \
        "Enter the destination PDF path." 10 90 "$destination" 3>&1 1>&2 2>&3) || return 1
    [[ -n "$destination" ]] || return 1
    destination="${destination/#\~\//$HOME/}"
    [[ "${destination,,}" == *.pdf ]] || destination+=".pdf"
    if [[ -e "$destination" ]] && ! whiptail --title "Overwrite PDF" --yesno \
        "Replace this PDF?\n$destination" 9 75; then return 1; fi

    converter=""
    command -v pandoc >/dev/null 2>&1 && converter=pandoc
    if [[ -z "$converter" ]] && command -v libreoffice >/dev/null 2>&1; then converter=libreoffice; fi
    if [[ -z "$converter" ]]; then
        whiptail --title "PDF Converter Missing" --msgbox \
            "Install pandoc (recommended) or LibreOffice to convert the book to PDF." 9 78
        return 1
    fi

    destination_dir=$(dirname -- "$destination")
    mkdir -p -- "$destination_dir" || return 1
    temp_md=$(mktemp --tmpdir="$destination_dir" '.babyrus-book.XXXXXX.md') || return 1
    temp_pdf="${temp_md%.md}.pdf"
    babyrus_book_rebuild_numbers
    : > "$temp_md" || return 1
    # Pandoc title-block syntax keeps the book title out of the generated TOC.
    printf '%% %s\n\n' "$BOOK_TITLE" >> "$temp_md"
    for i in "${!BOOK_SECTION_PATHS[@]}"; do
        if [[ ! -r "${BOOK_SECTION_PATHS[$i]}" ]]; then
            rm -f -- "$temp_md" "$temp_pdf"
            whiptail --title "PDF Conversion Failed" --msgbox \
                "Cannot read source note:\n${BOOK_SECTION_PATHS[$i]}" 9 80
            return 1
        fi
        # Markdown heading levels reflect outline indentation. The visible
        # heading text includes the generated numbering.
        heading_marks="$(printf '%*s' "${BOOK_SECTION_LEVELS[$i]}" '' | tr ' ' '#')"
        heading_prefix="${BOOK_SECTION_NUMBERS[$i]}"
        (( BOOK_SECTION_LEVELS[$i] == 1 )) && heading_prefix+="."
        printf '%s %s %s\n\n' "$heading_marks" \
            "$heading_prefix" "${BOOK_SECTION_TITLES[$i]}" >> "$temp_md"
        # Treat note text as literal content: fenced code blocks prevent
        # Markdown syntax in the source note from becoming formatting. Use a
        # fence longer than any source line's leading backtick run so embedded
        # code fences in the note cannot accidentally close this block.
        max_backticks=$(awk '{
            if (match($0, /^[[:space:]]*`+/)) {
                ticks = substr($0, RSTART, RLENGTH)
                sub(/^[[:space:]]*/, "", ticks)
                if (length(ticks) > max) max = length(ticks)
            }
        } END { print max + 0 }' "${BOOK_SECTION_PATHS[$i]}") || {
            rm -f -- "$temp_md" "$temp_pdf"; return 1;
        }
        fence_length=3
        if (( max_backticks >= fence_length )); then
            fence_length=$((max_backticks + 1))
        fi
        fence=$(printf '%*s' "$fence_length" '' | tr ' ' '`')
        printf '%s\n' "$fence" >> "$temp_md"
        cat -- "${BOOK_SECTION_PATHS[$i]}" >> "$temp_md" || {
            rm -f -- "$temp_md" "$temp_pdf"; return 1;
        }
        printf '\n%s\n\n' "$fence" >> "$temp_md"
    done

    if [[ "$converter" == pandoc ]]; then
        # Pandoc normally renders fenced note text as LaTeX's verbatim
        # environment, which does not wrap long lines. Use fvextra to enable
        # wrapping at spaces and, for very long unbroken strings, anywhere.
        # This applies only to the literal note-content blocks; headings and
        # the generated table of contents remain normal Markdown.
        temp_header=$(mktemp --tmpdir="$destination_dir" '.babyrus-book-header.XXXXXX.tex') || {
            rm -f -- "$temp_md" "$temp_pdf"; return 1;
        }
        if ! cat > "$temp_header" <<'BABYRUS_PANDOC_HEADER'
\usepackage{fvextra}
\RecustomVerbatimEnvironment{verbatim}{Verbatim}{
  breaklines=true,
  breakanywhere=true,
  breaksymbolleft={},
  breaksymbolright={}
}
BABYRUS_PANDOC_HEADER
        then
            rm -f -- "$temp_md" "$temp_pdf" "$temp_header"
            whiptail --title "PDF Conversion Failed" --msgbox \
                "Could not prepare the PDF text-wrapping settings." 9 75
            return 1
        fi

        if ! pandoc "$temp_md" -o "$temp_pdf" --toc --pdf-engine=xelatex -H "$temp_header" 2>/dev/null; then
            if ! pandoc "$temp_md" -o "$temp_pdf" --toc -H "$temp_header" 2>/dev/null; then
                rm -f -- "$temp_md" "$temp_pdf" "$temp_header"
                whiptail --title "PDF Conversion Failed" --msgbox \
                    "Pandoc could not create the PDF. Check that a PDF engine such as xelatex and the fvextra LaTeX package are installed." 10 85
                return 1
            fi
        fi
        rm -f -- "$temp_header"
    else
        # LibreOffice converts plain text rather than Markdown. Rebuild a plain
        # text version directly from the sections so the Markdown fence markers
        # are not printed, and so literal backticks that occur in note content
        # are preserved. Include a simple text table of contents as well.
        temp_txt=$(mktemp --tmpdir="$destination_dir" '.babyrus-book.XXXXXX.txt') || {
            rm -f -- "$temp_md" "$temp_pdf"; return 1;
        }
        {
            printf '%s\n\nTable of Contents\n\n' "$BOOK_TITLE"
            for i in "${!BOOK_SECTION_PATHS[@]}"; do
                heading_prefix="${BOOK_SECTION_NUMBERS[$i]}"
                (( BOOK_SECTION_LEVELS[$i] == 1 )) && heading_prefix+="."
                printf '%*s%s %s\n' "$(( (BOOK_SECTION_LEVELS[$i] - 1) * 2 ))" '' \
                    "$heading_prefix" "${BOOK_SECTION_TITLES[$i]}"
            done
            printf '\n'
            for i in "${!BOOK_SECTION_PATHS[@]}"; do
                heading_prefix="${BOOK_SECTION_NUMBERS[$i]}"
                (( BOOK_SECTION_LEVELS[$i] == 1 )) && heading_prefix+="."
                printf '%s %s\n\n' "$heading_prefix" "${BOOK_SECTION_TITLES[$i]}"
                cat -- "${BOOK_SECTION_PATHS[$i]}" || {
                    rm -f -- "$temp_md" "$temp_pdf" "$temp_txt"
                    return 1
                }
                printf '\n\n'
            done
        } > "$temp_txt" || {
            rm -f -- "$temp_md" "$temp_pdf" "$temp_txt"; return 1;
        }
        temp_pdf="${temp_txt%.txt}.pdf"
        if ! libreoffice --headless --convert-to pdf --outdir "$destination_dir" "$temp_txt" >/dev/null 2>&1; then
            rm -f -- "$temp_md" "$temp_pdf" "$temp_txt"
            whiptail --title "PDF Conversion Failed" --msgbox "LibreOffice could not create the PDF." 8 65
            return 1
        fi
        temp_pdf="${temp_txt%.txt}.pdf"
        rm -f -- "$temp_txt"
    fi
    if [[ ! -s "$temp_pdf" ]]; then
        rm -f -- "$temp_md" "$temp_pdf" "${temp_txt:-}"
        whiptail --title "PDF Conversion Failed" --msgbox "The converter did not create a PDF file." 8 65
        return 1
    fi
    mv -f -- "$temp_pdf" "$destination" || {
        rm -f -- "$temp_md" "$temp_pdf"; return 1;
    }
    rm -f -- "$temp_md"
    whiptail --title "PDF Created" --msgbox \
        "Created a PDF containing only the book title, numbered section headings, and note contents:\n$destination" 10 85
}


show_projects_menu() {
    while true; do
	local choice
        choice=$(whiptail --title "Goals Management" --cancel-button "Back" --menu "Choose an option:" 22 68 13 \
            "0" "Symbol Help" \
            "1" "Add New Project" \
            "2" "Edit Existing Project" \
            "3" "Print Project Content on Screen" \
            "4" "Associate Note with Project" \
            "5" "Dissociate Note with Project" \
            "6" "Do Stuff with Linked Notes in Project File" \
            "7" "Open URL from Linked Notes in Project File" \
            "8" "Do Stuff with Shortlisted Projects" \
            "9" "Delete Project" \
            "10" "Print Project using Printer" \
            "11" "Build Book from Linked Notes" \
            "12" "Load Existing Book to Edit" 3>&1 1>&2 2>&3) || return 1

        case $choice in
            0)
                whiptail \
                    --title "Symbol Help" \
                    --msgbox "$(print_symbol_help)" \
                    20 80
                ;;
            1)
                add_project
                ;;
            2)
                edit_project
                ;;
            3)
                print_project
                ;;
            4)
                associate_note_to_project
                ;;
            5)
                dissociate_note_from_project
                ;;
            6)
                do_stuff_with_project_file
                ;;
            7)
                open_url_assoc_to_note_from_project
                ;;
            8)
                do_stuff_with_shortlisted
                ;;
            9)
                delete_project
                ;;
            10)
                print_project_to_printer_from_main
                ;;
            11)
                build_book_from_project    
                ;;
            12)
                babyrus_book_edit_existing
                ;;
            *)
                return 1
                ;;
        esac
    done
}

##############################
# Back up code starts here
###############################

# Files and globs to include in the backup
readonly BACKUP_ENTRIES=(
  "ebooks.db"
  "ebooks.db.backup"
  "ebooks.db.rename.log"
  "tags.db"
  "notes/*.txt"
  "notes/metadata/notes.db"
  "notes/metadata/notes-ebooks.db"
  "notes/metadata/notes-tags.db"
  "projects/*.txt"
  "projects/metadata/projects.db"
  "projects/metadata/projects.db.shortlisted"
  "projects/metadata/projects.db.shortlisted.history"
  "urls/urls.db"
)

# backup_db [output_file]
# Creates a tar.gz of all matching entries in $PWD,
# quietly skipping any that don’t exist.
backup_db() {
  local out="${1:-backup_$(date +%Y%m%d_%H%M%S).tar.gz}"
  local -a files=()

  # Inform user about backup
  whiptail --title "Backup Database" --yesno \
    "This function will backup all database files plus all note files and project files. Do you want me to do backup now?" \
    10 60 || return 1

  # Enable nullglob so unmatched globs disappear instead of staying literal
  shopt -s nullglob
  for pattern in "${BACKUP_ENTRIES[@]}"; do
    for f in $pattern; do
      files+=("$f")
    done
  done
  shopt -u nullglob

  if (( ${#files[@]} == 0 )); then
    whiptail --title "Backup Database" --msgbox \
      "No files found to back up." \
      8 40
    return 1
  fi

  # Create backup
  if tar --ignore-failed-read -czvf "$out" "${files[@]}" &> /dev/null; then
    whiptail --title "Backup Database" --msgbox \
      "Backup complete. (${#files[@]} items archived)\nArchive: $out" \
      10 60
  else
    whiptail --title "Backup Database" --msgbox \
      "Error occurred during backup." \
      8 40
    return 2
  fi
}

# restore_db
# Lets user choose a backup archive to restore into $PWD
restore_db() {
    show_menu() {
        local menu_items=("$@")   # copy array elements
        local total_items=${#menu_items[@]}
        local items_per_page=10
        local total_pages=$(( (total_items + items_per_page*2 - 1) / (items_per_page*2) ))  # ceil division
        local page=0
        local choice

        while true; do
            local start=$((page * items_per_page * 2))
            local end=$((start + items_per_page * 2))
            local page_items=("${menu_items[@]:$start:$((items_per_page * 2))}")

            local menu_list=()
            menu_list+=("${page_items[@]}")            
            (( end < total_items )) && menu_list+=(">> Next" "")
            (( page > 0 )) && menu_list+=("<< Prev" "")

            choice=$(whiptail --title "Restore Database (Page $((page+1))/$total_pages)" \
                --menu "Choose an archive to restore:" 20 78 12 \
                "${menu_list[@]}" \
                3>&1 1>&2 2>&3) || return 1            

            case "$choice" in
                ">> Next") ((page++)) ;;
                "<< Prev") ((page--)) ;;
                *) echo "$choice"; return 0 ;;
            esac
        done
    }

  # Inform user about restore
  whiptail --title "Restore Database" --msgbox \
    "This function will let you choose a backup file to restore." \
    10 60

  # Collect backup files
  local archives=(backup_*.tar.gz)
  if (( ${#archives[@]} == 0 )) || [[ "${archives[0]}" == "backup_*.tar.gz" ]]; then
    whiptail --title "Restore Database" --msgbox \
      "No backup archives found in the current directory." \
      8 40
    return 1
  fi

  # Build menu items: tag each with index
  local menu_items=()
  for idx in "${!archives[@]}"; do
    menu_items+=("$idx" "${archives[$idx]}")
  done

#   # Show menu
#   local choice
#   choice=$(whiptail --title "Restore Database" --menu \
#     "Select an archive to restore:" 15 60 6 \
#     "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

  # FIX: PAGINATE SELECT ARCHIVE
  local choice
  choice="$(show_menu "${menu_items[@]}")" || return 1

  local selected_archive="${archives[$choice]}"

  # Ask user for the last time
  whiptail --title "Restore Database" --yesno \
    "Are you sure you want to restore the selected backup file?" \
    10 60 || return 1
    
  # DEBUG
  #echo tar -xzvf "$selected_archive" -C .
  #exit

  # Perform restore
  if tar -xzvf "$selected_archive" -C . &> /dev/null; then
    whiptail --title "Restore Database" --msgbox \
      "Restore complete. Files from $selected_archive have been extracted." \
      10 60
  else
    whiptail --title "Restore Database" --msgbox \
      "Error occurred during restore of $selected_archive." \
      8 40
    return 2
  fi
}

################################
# HELP
################################

# Help text is maintained separately from the menu so every topic can be
# revised without changing the navigation logic.
babyrus_help_message() {
    local title="$1"
    local content="$2"
    whiptail --scrolltext --title "$title" --cancel-button "Back" \
        --msgbox "$content" 40 120
}

babyrus_help_ebooks() {
    cat <<'BABYRUS_HELP_EBOOKS'
MANAGE eBOOKS — REGISTER, ORGANISE, FIND AND READ

BABYRUS builds a searchable index of ebook files that are already stored on your computer. Registering a file records its path and tags in the BABYRUS database; it does not move the ebook into a BABYRUS folder. You can keep your own directory structure.

1. Build your library

Use File Management to register one ebook, register a selection from a checklist, or add matching files in bulk. Bulk registration is useful when you have a folder of books to import. You can use a glob pattern to narrow the files being considered. The * wildcard matches any sequence of characters and ? matches one character.

The removal options work at different scales: remove one registered entry, choose several from a checklist, remove matching entries in bulk, or work within a selected file path. These File Management removal actions remove registrations from the BABYRUS database; they do not delete the original ebook files from your drive.

2. Organise with tags

Tags let one ebook belong to several subjects without duplicating the file. Register tags in Tag Management, then associate or dissociate them from individual ebooks, checklist selections, bulk results, or files under a selected path. Remove a tag from the global list when it is no longer needed.

3. Find and open books

Search & Lookup lets you inspect registered files, look within a directory, and view the tags in your library. Open & Read lets you find a book by search or by file path, then launches the application configured for that file type.

Use the glob and tag filters together to narrow a large collection. A tag search is especially useful when you remember the subject but not the filename.

4. Keep the library healthy

Maintenance can find database entries whose files are no longer present. It also provides tools to rename and re-register filenames that cause problems, and to revert those renames when needed. Renaming changes the actual filename on disk, so review the selected files and confirmation prompts carefully.

A useful first workflow is to register a small group of ebooks, assign a few meaningful tags, then practise finding and opening them from Search & Lookup and Open & Read.
BABYRUS_HELP_EBOOKS
}

babyrus_help_notes() {
    cat <<'BABYRUS_HELP_NOTES'
MANAGE NOTES — BUILD A CONNECTED KNOWLEDGE COLLECTION

Notes are ordinary text files managed through BABYRUS. Each note has a title and file path, and can be associated with tags, ebooks and their saved reading locations, URLs, and project files. Use Manage Notes for individual note tasks; use the tag and project workspaces when you want to work with a group of related notes.

1. Everyday note management

Add Note creates a note. Edit Note lets you choose an existing note to update. You can print a note, open an ebook associated with it, add or look up note tags, manage URL associations, open an ebook from the global list, and delete notes or remove unused tags from the global tag list.

A note can have more than one tag. When choosing a tag, NO TAG refers to notes without a tag, while ANY TAG includes notes regardless of whether they have one. Use these choices when you need to work with untagged notes as well as categorised notes.

2. Recommended feature: Do Stuff by Tag

This is one of the most useful BABYRUS workflows. Instead of starting with a particular file or project, start with a subject. Choose a tag and BABYRUS opens a workspace containing the notes associated with it. You can change to another tag and return to the original tag without leaving the workflow. The note list can also be narrowed with a filename glob.

From that workspace you can look up note details, create a note that inherits the current tag, copy note content to the clipboard, edit a note, open its associated ebook, associate or dissociate URLs, open a linked URL, print a note, associate notes with projects, and add another tag to the filtered notes. When you start with NO TAG, the create-note and add-tag actions are adjusted for untagged notes.

Try this workflow when researching a subject or returning to a collection of related information. One tag becomes a practical workspace rather than just a label.

3. Connect notes to reference material

Associate an ebook with a note when the note depends on a book or document. Where bookmark information is available, BABYRUS can present the saved reading locations so you can return to the relevant part. Associate URLs to keep web references with the note they support; URLs can be opened, edited or dissociated later.

4. Connect notes to projects

A note can be linked to a project so it is available from that project's workspace. The same note can be useful in more than one project. BABYRUS prevents deletion of a note while it is still associated with a project; unlink it from the relevant project first if you intend to delete it.

Suggested starting point: create a few notes, assign useful tags, associate an ebook or URL where relevant, and then explore Do Stuff by Tag. For goal-related work, continue with Do Stuff with Linked Notes in Project File under Goals Management.
BABYRUS_HELP_NOTES
}

babyrus_help_goals() {
    cat <<'BABYRUS_HELP_GOALS'
MANAGE GOALS — PROJECT PLANS AND LINKED NOTES

Goals Management brings project plans and the notes supporting those plans into one workflow. A project has a title, a project file and a collection of linked notes. You can create a project, edit an existing one, print its contents, associate or dissociate notes, open URLs from linked notes, and delete a project.

1. Create a project plan

Add New Project creates a project. Edit Existing Project opens its plan editor. Plans are organised as nested headings and tasks: headings group related work, and tasks sit under headings. You can add, edit, move and delete items, change their status and importance, and add comments. Statuses include Not started, In progress, Paused and Completed. Importance levels are Very important, Important, Normal and Not important.

Use headings to break a large goal into areas of work, then add actionable tasks beneath them. Update status as work progresses so the plan reflects what is actually happening.

2. Recommended feature: Do Stuff with Linked Notes in Project File

This is a particularly useful way to work on a project. Select a project and BABYRUS gathers the notes linked to it into one workspace. You can create a new linked note, link an existing note, unlink a note, and manage the project's plan without leaving that workspace.

The linked-note list can be filtered by tag or narrowed with a glob; reset either filter to return to the broader list. You can add a tag to, or remove a tag from, the linked notes that match the current filters. You can open an associated ebook or URL, and choose an individual linked note to view, copy, edit, print, manage its URL associations, open its ebooks, associate it with another project, or change its tags.

This workflow is especially valuable for research, study and longer projects: keep the plan in the project file and keep supporting information in notes, then link the two. The note remains a note rather than becoming a duplicate embedded in each project.

3. Shortlist active projects

Do Stuff with Shortlisted Projects gives you a smaller working set when your project database grows. Add projects to the shortlist, work with a shortlisted project, remove projects when they are no longer active, and view the shortlist history. Removing a project from the shortlist does not delete the project itself.

4. Build a book from linked notes

Build Book from Linked Notes starts with a project's associated notes. Add notes as book sections, load notes from another project file, move sections and their subsection blocks, change indentation, remove sections, preview the numbered outline, and read sections. You can change the book title, save the book as a text file, inspect its save path, or convert it to PDF.

A practical approach is to create the project plan first, collect useful material as notes, link the notes to the project, and then use the linked-note workspace or Build Book when you are ready to work with that material.
BABYRUS_HELP_GOALS
}

babyrus_help_configure() {
    cat <<'BABYRUS_HELP_CONFIGURE'
CONFIGURE — CHOOSE THE APPLICATIONS BABYRUS USES

BABYRUS can launch external applications to edit text files, view ebooks and PDFs, and open URLs. Configure lets you choose the default command for each supported file type, as well as the general text editor and web browser.

To change a setting:

1. Select the file extension, DEFAULT_EDITOR or URL_BROWSER.
2. Choose an application from the list.
3. Return to the settings menu and repeat for any other changes.
4. Select Save and confirm when you are ready to write the changes.

The available choices are common Linux applications. BABYRUS checks that the selected command is installed. If a command is missing, install it first and then return to Configure.

The file-type settings are used when BABYRUS opens registered ebooks. DEFAULT_EDITOR is used for the default terminal-based editing workflow, and URL_BROWSER is used when opening associated web links.

Saved settings are written into the configuration block in babyrus.sh. Restart BABYRUS after saving so the updated commands are used by the running session. Keep a backup of your script before manually editing its configuration block.
BABYRUS_HELP_CONFIGURE
}

babyrus_help_help() {
    cat <<'BABYRUS_HELP_HELP'
USING BABYRUS HELP

Choose a topic from this menu to read about the corresponding part of BABYRUS. The help screens are scrollable: use the navigation keys shown by Whiptail to move through the text, and choose Back or press Esc to return to the topic list.

Where to start:

• Manage eBooks explains registration, tags, searching, opening and library maintenance.
• Manage Notes introduces note organisation and the connections between notes, ebooks, URLs and projects. Pay particular attention to Do Stuff by Tag: it provides a focused workspace for a subject.
• Manage Goals explains project plans and linked notes. Do Stuff with Linked Notes in Project File is a useful workflow for keeping project tasks and their supporting information together.

Configure explains how to select external applications. Backup and Restore explain how to protect and recover BABYRUS's local data.

BABYRUS is designed to work with your local files. Take care when removing or renaming files, deleting notes, or restoring a backup, and read confirmation messages before accepting an operation.
BABYRUS_HELP_HELP
}

babyrus_help_backup() {
    cat <<'BABYRUS_HELP_BACKUP'
BACKUP — MAKE A RECOVERY ARCHIVE

Backup creates a compressed .tar.gz archive of BABYRUS's local data. The archive includes the databases and metadata, note text files, project files, the URL database, and the ebook registration and tag databases. The default filename includes a timestamp, for example:

backup_YYYYMMDD_HHMMSS.tar.gz

The archive is created in the current working directory. Keep a copy somewhere separate from the computer or directory that holds your BABYRUS data, so it remains available if the original files are lost or damaged.

Important: the backup contains BABYRUS's records and its note and project text files. It does not copy the external ebook files that are merely registered by path. Make sure your original ebook collection is backed up by your normal file-backup process as well.

Run Backup regularly, especially after adding or editing many notes, projects, tags or associations. Before starting, check that the current working directory is the BABYRUS data directory you intend to back up and that there is enough free disk space for the archive.
BABYRUS_HELP_BACKUP
}

babyrus_help_restore() {
    cat <<'BABYRUS_HELP_RESTORE'
RESTORE — RECOVER FROM A BACKUP ARCHIVE

Restore extracts a previously created BABYRUS backup archive into the current working directory. Choose the archive from the list, check that it is the correct backup, and confirm the operation when prompted.

Restoring replaces files at matching paths with the copies stored in the archive. Any newer database, note or project changes in those files can therefore be overwritten. Make a backup of the current data before restoring if there is anything you may need to keep.

Run BABYRUS from the data directory that should receive the restored files. The archive preserves relative paths, so restoring from a different directory may place the recovered files somewhere other than the directory you expect.

Restore does not recreate external ebook files; it restores BABYRUS's registration records and the note and project files included in the archive. The ebook files themselves must still be available at their registered paths.

After restoring, review your notes, projects and registered ebook paths. If you have any doubt about which archive to use, cancel and inspect the backup files before proceeding.
BABYRUS_HELP_RESTORE
}

# Help in sections. The Notes and Goals topics deliberately signpost two of
# BABYRUS's most useful workflows: Do Stuff by Tag and linked project notes.
show_help() {
    while true; do
        local CHOICE
        CHOICE=$(whiptail --title "Babyrus Help Menu" --cancel-button "Back" \
            --menu "Select a help topic:" 20 60 10 \
            "1" "Help: Manage eBooks" \
            "2" "Help: Manage Notes" \
            "3" "Help: Manage Goals" \
            "4" "Help: Configure" \
            "5" "Help: Help" \
            "6" "Help: Backup" \
            "7" "Help: Restore" 3>&1 1>&2 2>&3) || return 0

        case "$CHOICE" in
            1) babyrus_help_message "Manage eBooks" "$(babyrus_help_ebooks)" ;;
            2) babyrus_help_message "Manage Notes" "$(babyrus_help_notes)" ;;
            3) babyrus_help_message "Manage Goals" "$(babyrus_help_goals)" ;;
            4) babyrus_help_message "Configure" "$(babyrus_help_configure)" ;;
            5) babyrus_help_message "Help" "$(babyrus_help_help)" ;;
            6) babyrus_help_message "Backup" "$(babyrus_help_backup)" ;;
            7) babyrus_help_message "Restore" "$(babyrus_help_restore)" ;;
        esac
    done
}

################################
# Main Menu
################################
# Centre each verse line within the usable width of the compact main menu.
# The wrapper will widen the menu only when the terminal or text requires it.
babyrus_center_main_verse_line() {
    local line="$1" rows cols target_width padding
    read -r rows cols < <(babyrus_terminal_size)
    target_width=$(( BABYRUS_NAV_MENU_WIDTH - 8 ))
    (( target_width > cols - 8 )) && target_width=$(( cols - 8 ))
    (( target_width < 1 )) && target_width=1
    (( ${#line} > target_width )) && target_width=${#line}
    padding=$(( (target_width - ${#line}) / 2 ))
    (( padding < 0 )) && padding=0
    printf '%*s%s' "$padding" "" "$line"
}

msg1="'But the Helper, the Holy Spirit, whom the Father will"
msg2="send in My name, He will teach you all things, and bring"
msg3="to your remembrance all things that I said to you.'"
msg4="†John 14:26"
padded_msg1="$(babyrus_center_main_verse_line "$msg1")"
padded_msg2="$(babyrus_center_main_verse_line "$msg2")"
padded_msg3="$(babyrus_center_main_verse_line "$msg3")"
padded_msg4="$(babyrus_center_main_verse_line "$msg4")"
padded_msg="${padded_msg1}\n${padded_msg2}\n${padded_msg3}\n${padded_msg4}"
MAIN_MENU_STR="
${padded_msg}
"

# About message
about_babyrus() {
    local msg="BABYRUS — a simple, fast, terminal-based productivity tool.
Version: ${BABYRUS_VERSION}
Copyleft © 2025, 2026 Logan Lee — GPLv3.

You are my friends if you do what I command. 
I no longer call you slaves, because a master doesn’t confide in his slaves.
Now you are my friends, 
since I have told you everything the Father told me.
†John 15:14-15"

    whiptail --title "About BABYRUS" --msgbox "$msg" 18 72
}

# Main menu function
show_main_menu() {
    while true; do
        choice=$(whiptail --title "BABYRUS ${BABYRUS_VERSION} Main Menu" --cancel-button "Exit" --menu "$MAIN_MENU_STR" 20 60 8 \
            "eBooks" "Manage eBooks" \
            "Notes" "Manage Notes" \
            "Goals" "Manage Goals" \
            "Configure" "Set Default Apps" \
            "Help" "Read Help" \
	        "Backup" "Backup Everything" \
	        "Restore" "Restore from File" \
            "About" "About BABYRUS" \
            3>&1 1>&2 2>&3)

        if [ $? != 0 ]; then
            exit 0
        fi

        case $choice in
            "eBooks")
                show_ebooks_menu
                ;;
            "Notes")
                manage_notes
                ;;
            "Goals")
                show_projects_menu
                ;;
            "Configure")
                edit_configuration
                ;;
            "Help")
                show_help
                ;;
	        "Backup")
		        backup_db
		        ;;
	        "Restore")
		        restore_db
		        ;;
            "About")
                about_babyrus
                ;;
        esac
    done
}

show_main_menu
