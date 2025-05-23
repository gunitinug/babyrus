# babyrus
<img src="./babyrus.jpeg" height=110>

> Associate ebooks with tags, store notes and associate them with ebooks and urls, manage goals in tree form

## What is babyrus?
**Babyrus** is a terminal-based productivity program designed to help you organise your projects, manage notes, and keep track of your digital resources—especially **e-books and web links**. It provides a structured workflow made up of three core layers: **Manage eBooks**, **Manage Notes**, and **Manage Goals**. You can start by creating a project and setting goals, then write related notes, and finally associate those notes with useful resources like e-books or URLs. Each component is tightly integrated to support your planning and execution process, making Babyrus a practical tool for turning ideas into organised action.

One of *Babyrus*’s standout features is the ability to register e-books and store **chapter:page pairs**. This means you can open a specific book directly to a relevant section using an external viewer like *Evince*, allowing for precise and efficient reading. Notes can also store a list of associated **URLs**, making it easy to open *YouTube* videos, websites, or online articles directly from *Babyrus*. With support for **tagging**, **filtering**, and **bulk e-book management**, *Babyrus* scales well—from managing a few files to handling thousands—while staying focused on helping you stay organised and make progress on your goals.

## How to start program
First, `git clone` the repo:

`$ git clone https://github.com/gunitinug/babyrus.git`

Wait until you have the repo downloaded to your computer, `cd` to directory `babyrus`:

```
$ cd babyrus/
$ chmod +x babyrus.sh
```

to make `babyrus.sh` executable.

To start program:

`$ ./babyrus.sh`

## Requirements

The script will check for `bash version >=5.2.21`. Script will exit if you fail this requirement.

The script requires the following programs:
- whiptail
- wmctrl

Script will exit if any one of them are not installed. In ubuntu you can do this to install them:

`$ sudo apt install whiptail wmctrl`

In addition, tweak this code block:

```bash
# Tweak this to set external apps.
# These apps are used in 'Manage eBooks' section only!
declare -A EXTENSION_COMMANDS=(
    ["txt"]="gnome-text-editor"
    ["pdf"]="evince"
    ["epub"]="okular"
    ["mobi"]="xdg-open"
    ["azw3"]="xdg-open"
)

# Tweak these to set external apps for other sections.
# DEFAULT_EDITOR is a terminal-based editor runs inside current terminal.
DEFAULT_EDITOR="nano" # runs in the same terminal as babyrus.
URL_BROWSER="google-chrome"
DEFAULT_VIEWER="evince"
```

These define external app to use for each extension. Make sure you have all of the apps installed. The script will exit if they are not found.

## Attention
If you change `DEFAULT_VIEWER` variable to something other than evince then you may need to tweak this code block:

```bash
open_evince() {
    local selected_ebook="$1"
    local page="$2"
    [[ -z "$selected_ebook" ]] && return 1   # Allow empty pages to just open the document.

    local ebook_path=$(cut -d'#' -f1 <<< "$selected_ebook")
    [[ -f "$ebook_path" ]] || { whiptail --msgbox "Ebook not found: $ebook_path" 20 80; return 1; }

    #evince -p "$page" "$ebook_path" &> /dev/null & disown

    if [ -z "$page" ]; then
        #evince "$ebook_path" &> /dev/null & disown
	"$DEFAULT_VIEWER" "$ebook_path" &> /dev/null & disown
    else
        #evince -p "$page" "$ebook_path" &> /dev/null & disown
	"$DEFAULT_VIEWER" -p "$page" "$ebook_path" &> /dev/null & disown   # Might need to tweak this line.
    fi
}
```

The line you need to tweak is:

```bash
"$DEFAULT_VIEWER" -p "$page" "$ebook_path" &> /dev/null & disown   # Might need to tweak this line.
```

The reason is that `evince -p $page` works but other viewer may have different command for opening file at `$page`.

## Manual
The manual file is available in the repo (but at this time it is being written).

## All files created and managed by babyrus
Here are all the directories and files created and managed by babyrus. If you delete these files, blank files will be generated for you next time you run babyrus again. Back up files are generated and placed on the babyrus folder as `backup_*.tar.gz`. You can choose to back up and restore files from main menu.

```bash
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
  "urls/urls.db"
)
```

## Author
Logan Lee

Feel free to contact me at [logan.wonki.lee@gmail.com](mailto:logan.wonki.lee@gmail.com) if you have any questions or suggestions.
