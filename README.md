<h1 align="center">Babyrus</h1>
<p align="center">
  <img src="./logo.png" alt="Babyrus logo" width="200">
</p>

## Project Overview

**Babyrus** is a fast, terminal-based productivity tool designed for developers. It is built to help you manage eBooks and URLs, take notes, and track project goals directly from the command line.

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

### 🔍 Searching in Babyrus

Babyrus supports three different search methods. Use the method indicated by the program:

1. **Literal Substring Match**  
   A simple substring search. The `*` character is treated literally, not as a wildcard.

2. **Globbing**  
   Uses wildcards like `*stallman*`.

3. **Boolean Search**  
   Similar to globbing, but allows logical operators:  
   - `||` for OR  
   - `&&` for AND

### Requirements

Babyrus requires the following dependencies:

  * `bash >= 5.2.21`
  * `whiptail`
  * `wmctrl`

**To install on Ubuntu/Debian:**

```bash
sudo apt install whiptail wmctrl
```

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

The script uses external applications for various tasks. You can customize these in the script itself.

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
DEFAULT_EDITOR="nano"        # Used for note editing within the terminal
URL_BROWSER="google-chrome"  # Used to open external URLs
DEFAULT_VIEWER="evince"      # Used to view eBooks
```

**Note:** Ensure all configured applications are installed on your system. The script will exit if a required dependency is not found.

### Viewer Compatibility

If you change `DEFAULT_VIEWER` from `evince`, you may need to update the `open_evince()` function to ensure compatibility with your chosen application's command-line arguments.

For example, if your new viewer does not support the `-p` flag for jumping to a specific page, you will need to modify this section:

```bash
# Before (Evince-specific)
"$DEFAULT_VIEWER" -p "$page" "$ebook_path"

# After (Example for a viewer that does not support -p)
"$DEFAULT_VIEWER" "$ebook_path"
```

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

-----

[See a demo video](https://www.youtube.com/watch?v=i6dbxa1750M)
