#!/usr/bin/env bash

#set -euo pipefail  # removed strict error-handling

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

  # Show menu
  local choice
  choice=$(whiptail --title "Restore Database" --menu \
    "Select an archive to restore:" 15 60 6 \
    "${menu_items[@]}" 3>&1 1>&2 2>&3) || return 1

  local selected_archive="${archives[$choice]}"

  # Ask user for the last time
  whiptail --title "Restore Database" --yesno \
    "Are you sure you want to restore the selected backup file?" \
    10 60 || return 1
    
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

# Test!!!!
#backup_db
restore_db
