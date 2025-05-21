# babyrus
<img src="./babyrus.jpeg" height=110>

> Associate ebooks with tags, store notes and associate them with ebooks and urls, manage goals in tree form

# What is babyrus?
Babyrus is a terminal-based productivity program designed to help you organise your projects, manage notes, and keep track of your digital resources—especially e-books and web links. It provides a structured workflow made up of three core layers: Manage eBooks, Manage Notes, and Manage Goals. You can start by creating a project and setting goals, then write related notes, and finally associate those notes with useful resources like e-books or URLs. Each component is tightly integrated to support your planning and execution process, making Babyrus a practical tool for turning ideas into organised action.

One of Babyrus’s standout features is the ability to register e-books and store chapter:page pairs. This means you can open a specific book directly to a relevant section using an external viewer like Evince, allowing for precise and efficient reading. Notes can also store a list of associated URLs, making it easy to open YouTube videos, websites, or online articles directly from Babyrus. With support for tagging, filtering, and bulk e-book management, Babyrus scales well—from managing a few files to handling thousands—while staying focused on helping you stay organised and make progress on your goals.

# How to start program
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
declare -A EXTENSION_COMMANDS=(
    ["txt"]="gnome-text-editor"
    ["pdf"]="evince"
    ["epub"]="okular"
    ["mobi"]="xdg-open"
    ["azw3"]="xdg-open"
)
```

These define external app to use for each extension. Make sure you have all of the apps installed. The script will exit if they are not found.

# Manual
The manual file is available in the repo (but at this time it is being written).
