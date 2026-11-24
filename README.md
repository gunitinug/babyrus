# Babyrus

<p align="center">
  <img src="./babyrus%20logo%203%20jan%202026.png" alt="Babyrus logo" width="300">
</p>

## Project Overview

**Babyrus** is a fast, terminal-based productivity and knowledge-management tool designed for hackers and people who enjoy working from the command line.

Built with Bash and Whiptail, Babyrus helps you organise assets (eBooks, audio and video files), manage notes, collect web resources, and plan projects. Its features are interconnected through a flexible tagging and linking system, allowing you to build a personal knowledge base and manage your work from one application.

You can associate notes with assets, saved reading or playback locations, URLs and projects. You can also organise project plans into headings and tasks, maintain their progress, and build books from your linked notes.

---

## ⚠️ Development Status

Babyrus is under active development. Features and workflows may change as the project evolves.

For the latest improvements and fixes, use the latest version from the `main` branch.

---

## Key Features

### Asset Management

An **asset** is any registered file that Babyrus can open: an eBook, an audio file or a video file.

- Register individual assets, multiple selections from a checklist, or files in bulk. Registration lists eBook, audio and video files, and starts with sub-directories included (you can turn recursion off from the list).
- Organise your library using custom tags.
- Associate and dissociate tags individually, from checklists, in bulk, or by file path.
- Search registered assets using filename globbing and tag filters.
- Browse registered files and look up files by their paths.
- Open assets directly using your configured applications: document viewers for eBooks, and your chosen audio and video players for media files.
- Find and remove broken database entries pointing to missing files.
- Clean up filenames during registration, including handling characters that cannot be stored safely in the database.

### Note Management

- Create, edit, print and delete notes.
- Organise notes using multiple tags.
- Associate notes with assets and their saved locations:
  - **eBooks:** chapters with pages (for example `Intro:1-10`).
  - **Audio and video files:** bookmarks with time positions (for example `Intro:4:30` or `Part two:1:02:15`).
- Associate URLs with notes for easy access to external resources.
- Open associated assets and URLs directly from notes, jumping straight to a saved page or time.
- Filter and manage collections of notes using **Do Stuff by Tag**.
- Associate notes with projects and reuse them across multiple projects.

### Project and Goal Management

- Create and manage project files.
- Organise project plans using nested headings and tasks.
- Add comments and manage task status and importance.
- Associate and dissociate notes with projects.
- Work with linked notes through **Do Stuff with Linked Notes in Project File**, including opening their assets at saved bookmarks.
- Filter linked notes using tags and filename globbing.
- Maintain a shortlist of active projects and access shortlist history.
- Print project content or send it to a printer.

### Book Builder

- Build a book from notes associated with a project.
- Add notes as book sections and organise them into a numbered outline.
- Load existing books for further editing.
- Reorder sections, change indentation and remove sections.
- Load additional notes from other project files.
- Preview the book structure and read individual sections.
- Save the resulting book as a text file or convert it to PDF.

### Backup and Restore

- Create compressed `.tar.gz` backups of Babyrus databases, notes and project files.
- Restore data from previously created backup archives.
- Select from available backup archives using a paginated menu.

### User Interface

- Terminal-based menus and checklists using Whiptail and Dialog.
- Consistent light-coloured interface with blue accents.
- Automatically sized menus and content pickers.
- Paginated lists for navigating larger collections.
- Built-in help covering the main features and workflows.

---

## Getting Started

### Installation

Clone the repository and enter the project directory:

```bash
git clone https://github.com/gunitinug/babyrus.git
cd babyrus
```

Make the script executable:

```bash
chmod +x babyrus.sh
```

**Important:** Babyrus uses the current working directory for its databases and data folders. Run the script from the directory where you want your Babyrus data to be stored.

### Running the Application

Launch Babyrus from its working directory:

```bash
./babyrus.sh
```

The main menu provides access to:

- **Manage Assets**
- **Manage Notes**
- **Manage Goals**
- **Set Default Apps**
- **Read Help**
- **Backup Everything**
- **Restore from File**
- **About Babyrus**

---

## Supported File Types

Babyrus classifies assets by file extension.

| Kind | Extensions |
|---|---|
| eBooks and documents | `txt`, `pdf`, `epub`, `mobi`, `azw3`, `djvu` (`djv` too) |
| Audio | `mp3`, `flac`, `wav`, `ogg`, `oga`, `opus`, `m4a`, `aac`, `wma`, `aiff`, `aif`, `ape`, `mka` |
| Video | `mp4`, `mkv`, `avi`, `webm`, `mov`, `wmv`, `flv`, `m4v`, `mpg`, `mpeg`, `ogv`, `3gp` |

All assets are stored in the same database (`ebooks.db`, kept under its original name so existing data keeps working) and share the same tagging, searching and note-association features.

---

## Dependencies

Babyrus requires **Bash 4.4 or newer** and several command-line utilities for its terminal interface, window management and clipboard functionality.

It also requires external applications to open assets, edit text files and browse URLs.

### Core Dependencies

| Dependency | Purpose |
|---|---|
| `bash` 4.4+ | Required Bash version |
| `whiptail` | Terminal menus and checklists |
| `wmctrl` | Window management |
| `dialog` | Dialog interfaces |
| `xclip` | Clipboard operations |

### Default Applications

The following applications are used by the default configuration:

| Application | Purpose |
|---|---|
| `geany` | Opening TXT files |
| `zathura` | Opening PDF files |
| `okular` | Opening EPUB, MOBI and AZW3 files |
| `djview4` | Opening DjVu files (optional) |
| `mpv` | Playing audio and video files (optional until you open a media file) |
| `nano` | Default text editor |
| `firefox` | Opening URLs |

The DjVu viewer is optional at startup. If it is not installed, Babyrus will report the missing application when you attempt to open a DjVu file.

Audio and video players work the same way when your configuration has not chosen them yet (for example, if you are upgrading from an older version): a missing player is only reported when you open an audio or video file. Once you choose a player in **Set Default Apps**, it is checked like the other configured applications.

### PDF Conversion Dependencies

By default, Babyrus uses **Pandoc with XeLaTeX** to convert books created through Book Builder into PDF files.

```bash
PDF_CONVERTER="pandoc"
```

This configuration requires:

- `pandoc`
- `xelatex`
- `kpsewhich`
- `fvextra.sty`
- `lmodern.sty`
- `pzdr.tfm`

The required LaTeX files are supplied by the following packages:

| LaTeX file | Ubuntu package | Fedora package |
|---|---|---|
| `fvextra.sty` | `texlive-latex-extra` | `texlive-fvextra` |
| `lmodern.sty` | `lmodern` | `texlive-lm` |
| `pzdr.tfm` | `texlive-fonts-recommended` | `texlive-zapfding` |

### Installation on Ubuntu

```bash
sudo apt update

sudo apt install \
    whiptail wmctrl dialog xclip \
    geany zathura okular nano firefox mpv \
    pandoc texlive-xetex texlive-latex-extra \
    texlive-fonts-recommended lmodern
```

Ubuntu 24.04's default Bash version satisfies the minimum requirement. Ubuntu 22.04's default Bash 5.1 does not.

### Installation on Fedora

```bash
sudo dnf install \
    newt wmctrl dialog xclip \
    geany zathura okular nano firefox mpv \
    pandoc texlive-xetex texlive-kpathsea \
    texlive-fvextra texlive-lm texlive-zapfding
```

On Fedora, the `newt` package provides `whiptail`. Depending on your repositories, `mpv` may require enabling RPM Fusion.

### Verifying LaTeX Dependencies

After installing the Pandoc and LaTeX packages, verify that the required files are available:

```bash
for file in fvextra.sty lmodern.sty pzdr.tfm; do
    echo -n "$file: "
    kpsewhich "$file" || echo "NOT FOUND"
done
```

If installed correctly, `kpsewhich` will print the location of each file.

### Alternative PDF Converter: LibreOffice

Babyrus also supports LibreOffice as an alternative to Pandoc.

Change the configuration to:

```bash
PDF_CONVERTER="libreoffice"
```

With this setting, Babyrus requires LibreOffice instead of Pandoc, XeLaTeX and the associated LaTeX files.

On Ubuntu:

```bash
sudo apt install libreoffice
```

On Fedora:

```bash
sudo dnf install libreoffice
```

You only need to install the dependencies for the PDF converter you have selected.

---

## Configuration

Babyrus allows you to configure the external applications used to open different file types.

Open:

**Main Menu → Set Default Apps**

You can configure the following settings:

| Setting | Default | Choices |
|---|---|---|
| TXT | `geany` | Geany, Kate, Mousepad, Gedit, GNOME Text Editor, FeatherPad, Xed, VS Code |
| PDF | `zathura` | Evince, Okular, Zathura, Atril, xpdf, MuPDF, Firefox |
| EPUB | `okular` | Calibre, Foliate, Okular, Bookworm, Thorium Reader |
| MOBI | `okular` | Calibre, Okular |
| AZW3 | `okular` | Calibre, Okular |
| DjVu | `djview4` | djview4, djview, Evince, Okular, Zathura |
| Audio | `mpv` | mpv, mpg123, vlc, aplay, paplay, ogg123, ffplay, cvlc |
| Video | `mpv` | mpv, vlc, ffplay, mplayer |
| Default Editor | `nano` | nano, vim, nvim, emacs, micro, helix |
| URL Browser | `firefox` | Firefox, Chromium, Chrome, Brave, Vivaldi, Opera, qutebrowser, lynx, w3m |
| PDF Converter | `pandoc` | pandoc, libreoffice |

The configuration block in `babyrus.sh` looks like this:

```bash
declare -A EXTENSION_COMMANDS=(
    ["txt"]="geany"
    ["pdf"]="zathura"
    ["epub"]="okular"
    ["mobi"]="okular"
    ["azw3"]="okular"
    ["djvu"]="djview4"
    ["audio"]="mpv"
    ["video"]="mpv"
)

DEFAULT_EDITOR="nano"
URL_BROWSER="firefox"
PDF_CONVERTER="pandoc"
```

The `audio` player is used for every audio extension and the `video` player for every video extension. Babyrus only accepts a player that is installed on your system.

When you save configuration changes, Babyrus creates a backup of the previous script named `babyrus.sh.bak` before updating the configuration block.

**Note:** Ensure that your configured applications are installed. Babyrus checks its required dependencies and configured applications during startup.

### First-Run Configuration

The first-run configuration screen can be triggered by changing the `FIRST_RUN` variable in `babyrus.sh`:

```bash
#+++ FIRST RUN +++#
FIRST_RUN=0
#+++ FIRST RUN END +++#
```

When the configuration is saved, Babyrus automatically resets this variable to `1`.

You can also change application settings at any time through the main menu.

---

## Audio and Video Playback

### Bookmarks

Notes can store bookmarks for audio and video assets. A bookmark is a name plus a time position in `M:SS` or `H:MM:SS` format, for example:

```text
Intro:4:30
Part two:1:02:15
Q&A:45:00-52:30
```

A range (`start-end`) is accepted; the player opens at its start. When you open the asset from a note, a project, or a shortlisted project, you can choose a bookmark and playback starts at that time.

### Player Behaviour

- **Seeking:** mpv, vlc, cvlc, ffplay, mplayer and ogg123 start at the bookmarked time. mpg123 seeks approximately, because it can only skip whole frames. aplay and paplay cannot seek, so Babyrus tells you and plays from the start.
- **Format fallback:** some command-line players only handle a few formats (mpg123: MP3, aplay: WAV, paplay and ogg123: a small set). If your chosen player cannot play a file, Babyrus uses another installed player that can.
- **Terminal players:** players without a window (mpv for audio, mpg123, ogg123, paplay, aplay, cvlc, and ffplay for audio) run inside the terminal. Press `q` or `Ctrl-C` to stop playback and return to Babyrus. Players with their own window (vlc, mplayer, and mpv/ffplay for video) are launched in the background.

---

## Searching and Filtering

Babyrus provides two main search methods, depending on the type of information being searched.

### 1. Literal Substring Matching

Used primarily for filtering tag names.

The search text is treated literally, not as a wildcard or regular expression.

For example:

- Searching for `math` matches tags containing `math`.
- Searching for `?` looks for an actual question mark.
- Searching for `*` looks for an actual asterisk.

Tag filtering is case-insensitive.

### 2. Globbing

Used to filter filenames and file paths, as well as project and note selections in supported workflows.

Globbing supports:

- `*` — matches any sequence of characters.
- `?` — matches a single character.

Examples:

```text
*schaum*
*programming*.pdf
/books/*/math*.pdf
*lecture*.mp4
```

Globbing is case-insensitive in the relevant file-selection workflows.

### Combining Filters

Some workflows allow you to combine a filename glob with a tag filter. This is useful when managing a large collection of assets or notes.

You can also reset individual filters without leaving the current workflow.

### Recursion

The file lists of **Add Files In Bulk**, **Register Asset** and **Register Assets From Checklist** start with sub-directories included. Use `__NON_RECURSE__` to list only the selected directory, and `__RECURSE__` to include sub-directories again.

---

## Filename Cleanup

Babyrus performs filename cleanup when registering assets.

Some characters cannot be safely stored in the database. When affected files are encountered, Babyrus displays the affected filenames and asks whether you want to allow the renaming operation.

The cleanup process can also:

- Replace certain special characters with underscores.
- Replace leading hyphens.
- Remove unnecessary ISBN and hash information from filenames.

**Important:** Filename cleanup can rename the actual files on your drive, not just their database entries. Review the affected filenames before confirming the operation.

---

## File Structure

Babyrus stores its databases and supporting files relative to the current working directory.

The main directory structure is:

```text
babyrus/
├── babyrus.sh
├── babyrus.sh.bak
├── ebooks.db
├── ebooks.db.backup
├── ebooks.db.rename.log
├── tags.db
│
├── notes/
│   ├── *.txt
│   └── metadata/
│       ├── notes.db
│       ├── notes-ebooks.db
│       └── notes-tags.db
│
├── projects/
│   ├── *.txt
│   └── metadata/
│       ├── projects.db
│       ├── projects.db.shortlisted
│       └── projects.db.shortlisted.history
│
└── urls/
    └── urls.db
```

Babyrus automatically creates the required directories and database files when they are missing.

The databases store information about registered assets, tags, notes, project files, URLs and their associations. The asset database keeps its original file names (`ebooks.db`, `notes-ebooks.db`) even though it now holds audio and video files too, so existing installations need no migration.

**Important:** Registered assets remain in their original locations. Babyrus stores their file paths rather than copying the actual files into its own directory.

Do not delete database files or folders unless you intend to reset the corresponding Babyrus data. Missing databases are recreated as empty files when the application starts.

---

## Backup and Restore

Babyrus provides built-in backup and restore functionality through the main menu.

### Backup

Select:

**Main Menu → Backup Everything**

Babyrus creates a compressed archive containing:

- Asset registration and tag databases.
- Notes and their metadata.
- Project files and project metadata.
- URL database.
- Supporting asset database backup files.

The default archive filename uses a timestamp:

```text
backup_YYYYMMDD_HHMMSS.tar.gz
```

Backups are created in the current working directory.

### Restore

Select:

**Main Menu → Restore from File**

Choose an existing `backup_*.tar.gz` archive and confirm the restoration.

**Important considerations:**

- Restoring replaces files at matching paths with the contents of the selected archive.
- Newer changes may be overwritten.
- It is recommended to create a backup of your current data before restoring.
- Backup archives do not include the original asset files (eBooks, audio and video) registered in Babyrus. Those files must be backed up separately.

For additional safety, keep copies of your backup archives somewhere outside your Babyrus directory.

---

## Contribution

Contributions, suggestions and feedback are welcome.

- **Report Bugs:** Open an issue through the [GitHub Issues page](https://github.com/gunitinug/babyrus/issues) if you encounter bugs or unexpected behaviour.
- **Suggest Features:** Ideas for new features and improvements are always welcome.
- **Testing:** Feedback from real-world usage helps improve Babyrus.

---

## Author

**Logan Lee**

📧 [logan.wonki.lee@gmail.com](mailto:logan.wonki.lee@gmail.com)

---

## License

Babyrus is free software licensed under the [GNU General Public License, Version 3](https://www.gnu.org/licenses/gpl-3.0.html).

A copy of the license is available in the repository as `LICENSE`.
