# babyrus
<img src="./babyrus.jpeg" height=110>

> Associate ebooks with tags, store notes and associate them with ebooks, manage goals in tree form

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

