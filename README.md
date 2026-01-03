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

### 🔍 Searching in Babyrus

Babyrus provides three different search methods, whichever is most suitable for the search task at hand. Use the method indicated by the program. The rule of thumb is to use literal substring match for filtering tags and other methods for filtering file names.

1. **Literal Substring Match**  
   A simple substring search. The `*` character is treated literally, not as a wildcard. Special characters like `?` or `.` are also treated literally.

2. **Globbing**  
   Uses wildcards like `*stallman*`. You can include spaces and `*` and `?`.

3. **Boolean Search**  
   Similar to globbing, but allows logical operators:  
   - `||` for OR  
   - `&&` for AND

   Spaces are allowed but for now `?` is not implemented.

### Requirements

Babyrus requires the following dependencies:

  * `bash >= 5.2.21`
  * `whiptail`
  * `wmctrl`
  * `dialog`

**To install on Ubuntu/Debian:**

```bash
sudo apt install whiptail wmctrl dialog
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

To set default apps for different extensions (eg. .pdf or .epub), go to `Main Menu -> Configure` then change settings from there.

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

-----

[See a demo video](https://www.youtube.com/watch?v=i6dbxa1750M)
