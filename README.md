# babyrus

<img src="./babyrus.jpeg" height="110">

> A terminal-based productivity tool to manage eBooks, notes, and goals—structured and streamlined.

---

## 🚀 What is Babyrus?

[![Watch the demo on YouTube](https://github.com/gunitinug/babyrus/blob/main/babyrus.png)](https://www.youtube.com/watch?v=i6dbxa1750M)

**Click on the image for a short demo video of Babyrus in action.**

**Babyrus** is a terminal-based productivity application that helps you manage projects, take notes, and organize digital resources—especially **eBooks** and **URLs**. It provides a structured workflow across three core layers:

* **Manage eBooks**
* **Manage Notes**
* **Manage Goals**

You start by setting up a project and defining your goals, then write notes, and finally link those notes to relevant resources like eBooks or websites. Each layer works seamlessly together to support your planning, learning, and execution process.

### ⚠️ Stay Up to Date

Babyrus is under active development and regularly refined. **To ensure the best experience, always use the latest commit** from the `main` branch, as new features and improvements are frequently added.

### 📖 Key Features

* Associate eBooks with notes and tags
* Register `chapter:page` pairs to jump to specific eBook sections (using external viewers like *Evince*)
* Link notes with URLs (e.g., YouTube, online articles)
* Organize and filter by **tags**
* Handle large libraries with bulk eBook management
* Designed to scale—from a few notes to thousands of files

---

## 🛠️ Getting Started

Clone the repository:

```bash
git clone https://github.com/gunitinug/babyrus.git
cd babyrus/
chmod +x babyrus.sh
```

Run the program:

```bash
./babyrus.sh
```

---

## ✅ Requirements

Babyrus requires:

* `bash >= 5.2.21`
* `whiptail`
* `wmctrl`

To install the dependencies on Ubuntu:

```bash
sudo apt install whiptail wmctrl
```

---

## ⚙️ Configuration

Update the following section in the script to define which external apps to use:

```bash
# External apps for eBook handling
declare -A EXTENSION_COMMANDS=(
    ["txt"]="gnome-text-editor"
    ["pdf"]="evince"
    ["epub"]="okular"
    ["mobi"]="xdg-open"
    ["azw3"]="xdg-open"
)

# Editors/viewers for other sections
DEFAULT_EDITOR="nano"         # Used inside the terminal
URL_BROWSER="google-chrome"   # Used to open URLs
DEFAULT_VIEWER="evince"       # Used to view eBooks
```

Ensure all specified programs are installed. The script will exit if any are missing.

---

## ⚠️ Note on Changing Default Viewer

If you change `DEFAULT_VIEWER` from `evince` to another app, update this function accordingly:

```bash
open_evince() {
    local selected_ebook="$1"
    local page="$2"
    [[ -z "$selected_ebook" ]] && return 1

    local ebook_path=$(cut -d'#' -f1 <<< "$selected_ebook")
    [[ -f "$ebook_path" ]] || {
        whiptail --msgbox "Ebook not found: $ebook_path" 20 80
        return 1
    }

    if [ -z "$page" ]; then
        "$DEFAULT_VIEWER" "$ebook_path" &> /dev/null & disown
    else
        "$DEFAULT_VIEWER" -p "$page" "$ebook_path" &> /dev/null & disown
        # ⚠️ Adjust this line if your viewer does not support the -p option
    fi
}
```

Replace the `-p "$page"` argument as needed for compatibility with your chosen viewer.

---

## 📚 Manual

A user manual is included in the repository, but is currently in progress. Stay tuned!

---

## 📁 Files Managed by Babyrus

Babyrus creates and manages the following files and directories. If deleted, blank versions will be regenerated when you run the script again. Backups are saved as `backup_*.tar.gz` in the `babyrus/` folder. You can back up or restore files via the main menu.

```bash
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
  "urls/urls.db"
)
```

---

## 🧪 Call for Testers

Your feedback helps make Babyrus better! Here’s how you can contribute:

* **Try it out** — Follow the setup instructions and use Babyrus normally.
* **Report bugs** — Found a bug or unexpected behavior? Report it via the [Issues tab](https://github.com/gunitinug/babyrus/issues).
* **Suggest improvements** — Got ideas to make Babyrus more powerful or user-friendly? Let me know!

No coding skills required—your real-world experience and input are just as valuable.

---

## 👤 Author

**Logan Lee**
📧 [logan.wonki.lee@gmail.com](mailto:logan.wonki.lee@gmail.com)

Feel free to reach out with questions, ideas, or just to say hi!

---

## 📝 License

Babyrus is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License](https://www.gnu.org/licenses/gpl-3.0.html) as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

A copy of the license is included in this repository as [`LICENSE`](./LICENSE).
