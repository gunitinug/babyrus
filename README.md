<p align="center">
  <img src="./babyrus%20logo%203%20jan%202026.png" alt="Babyrus logo"/ width=300>
</p>

## Project Overview

**Babyrus** is a fast, terminal-based productivity tool designed for hackers. It is built to help you manage eBooks and URLs, take notes, and track project goals directly from the command line.

The application integrates these features to streamline your workflow: define project goals, link notes to relevant resources (e.g., eBooks, URLs), and organize everything with a flexible tagging system.

-----

## ⚠️ Development Status

Babyrus is under active development. For the most stable and feature-rich experience, it is recommended to pull the latest `main` branch.

-----

## Key Features

### Babyrus: Key Features

* **Effortless Organization:** Create a personalized knowledge base by associating notes and tags with your eBooks and external URLs.
* **Seamless Workflow:** Quickly open an eBook to a specific page or jump to a URL directly from your notes.
* **Goal Tracking:** Create project files to keep track of your goals and centralize all related notes.
* **Built for Growth:** Handle thousands of notes and files with a powerful and efficient architecture.

-----

## Getting Started

## First run ##
When you first run BABYRUS, you will be prompted to set default apps. This is so that the program will run the next time you run BABYRUS. Set default apps per extension then quit and restart the program. Next time BABYRUS is run, you will be shown the main menu.

### 🔍 Searching in Babyrus

Babyrus provides two different search methods, whichever is most suitable for the search task at hand. Use the method indicated by the program. The rule of thumb is to use literal substring match for filtering tags and globbing for filtering file names.

1. **Literal Substring Match**  
   A simple substring search. The `*` character is treated literally, not as a wildcard. Special characters like `?` or `.` are also treated literally.

2. **Globbing**  
   Uses wildcards like `*stallman*`. You can include spaces and `*` and `?`.

### Requirements

Babyrus requires the following dependencies:

  * `bash >= 5.2.21`
  * `whiptail`
  * `wmctrl`
  * `dialog`
  * `xclip`

**To install on Ubuntu/Debian:**

```bash
sudo apt install whiptail wmctrl dialog xclip
```
Plus of course your chosen default editor (terminal-based), viewers and web browser that you can setup by visiting `Main Menu -> Configure` menu. Also, `wmctrl` and `xclip` only work with X11 not Wayland.

BABYRUS will not launch if any of the programs defined in `Main Menu -> Configure` menu are not installed. For default setting here is the command to install them:
```bash
sudo apt install gnome-text-editor zathura okular nano
```
Plus, the default browser is set as `google-chrome` so download and install it from official google chrome website.

You can then change your default apps from `Main Menu -> Configure`.

### Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/gunitinug/babyrus.git
cd babyrus/
chmod +x babyrus.sh
```

### Running the Application

Launch the application from the project directory:

```bash
./babyrus.sh
```

-----

## Configuration

To set default apps for different extensions (eg. .pdf or .epub), go to `Main Menu -> Configure` then change settings from there. 

Babyrus supports the following extensions:

```bash
declare -A EXTENSION_COMMANDS=(
    ["txt"]="gnome-text-editor"
    ["pdf"]="zathura"
    ["epub"]="okular"
    ["mobi"]="okular"
    ["azw3"]="okular"
)
```

At the moment we support the following viewers:

```bash
declare -A VIEWER_COMMANDS=(
    # PDF viewers
    ["evince"]="evince -p"
    ["okular"]="okular -p"
    ["zathura"]="zathura -P"
    ["mupdf"]="mupdf"
    ["qpdfview"]="qpdfview"

    # EPUB/MOBI/AZW3 viewers
    ["calibre"]="ebook-viewer --open-at"    
)
````
You can also configure default editor and web browser from the `Configure` menu.

```bash
DEFAULT_EDITOR="nano" # runs in the same terminal as babyrus.
URL_BROWSER="google-chrome"
```

File `babyrus.sh.bak` is created to save old `babyrus.sh` executable.

**Note:** Ensure all configured applications are installed on your system. The script will exit if a required dependency is not found.

-----

## File Structure

Babyrus manages the following files and directories. Deleting these will result in the application regenerating blank versions on the next run.

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
  "projects/metadata/projects.db.shortlisted"
  "projects/metadata/projects.db.shortlisted.history"
  "urls/urls.db"
)
```

The application provides a built-in backup and restore feature via the main menu. Backups are saved as `backup_*.tar.gz` within the `babyrus/` directory.

-----

## Contribution

We welcome contributions and feedback to improve Babyrus.

  * **Report Bugs:** Please open an issue on the [GitHub Issues tab](https://github.com/gunitinug/babyrus/issues) if you encounter any bugs or unexpected behavior.
  * **Suggest Features:** We are always open to ideas for new features or improvements.
  * **Testing:** Your real-world usage and feedback are invaluable.

-----

## Author

**Logan Lee**
📧 [logan.wonki.lee@gmail.com](mailto:logan.wonki.lee@gmail.com)

-----

## License

Babyrus is free software licensed under the [GNU General Public License, Version 3](https://www.gnu.org/licenses/gpl-3.0.html). A copy of the license is available in the repository as `LICENSE`.
