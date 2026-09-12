#!/bin/sh
# Git-free Videoclip install/update for Linux and macOS.
set -eu

config_dir=${1:-${MPV_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/mpv}}
case "$config_dir" in /*) ;; *) config_dir="$PWD/$config_dir" ;; esac
target="$config_dir/scripts/videoclip"
if [ -e "$target/.git" ]; then
    echo "This is a Git checkout. Use git pull or move it out of scripts first: $target" >&2
    exit 1
fi
if [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target/main.lua" ]; }; then
    echo "Move the unrecognized or linked installation aside first: $target" >&2
    exit 1
fi
command -v tar >/dev/null 2>&1 || { echo 'tar is required.' >&2; exit 1; }
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
trap 'exit 1' HUP INT TERM
echo 'Downloading Videoclip...'
url='https://github.com/ItsTatsuya/videoclip/archive/refs/heads/master.tar.gz'
if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 2 --connect-timeout 20 "$url" -o "$temporary/archive.tar.gz"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$temporary/archive.tar.gz" "$url"
else
    echo 'Install curl or wget to download Videoclip.' >&2
    exit 1
fi
tar -xzf "$temporary/archive.tar.gz" -C "$temporary"
source_dir="$temporary/videoclip-master"
for required in main.lua videoclip/main.lua videoclip/videoclip.lua videoclip/config/default_config.conf; do
    if [ ! -f "$source_dir/$required" ]; then
        echo 'Incomplete download. Your installed plugin has not been changed.' >&2
        exit 1
    fi
done
mkdir -p "$config_dir/scripts" "$config_dir/script-opts"
stage=$(mktemp -d "$config_dir/videoclip-stage.XXXXXX")
cp "$source_dir/main.lua" "$source_dir/LICENSE" "$stage/"
cp -R "$source_dir/videoclip" "$stage/"
if [ ! -e "$config_dir/script-opts/videoclip.conf" ]; then
    cp "$source_dir/videoclip/config/default_config.conf" "$config_dir/script-opts/videoclip.conf"
fi
backup=''
if [ -e "$target" ]; then
    mkdir -p "$config_dir/videoclip-backups"
    backup=$(mktemp -d "$config_dir/videoclip-backups/previous.XXXXXX")
    mv "$target" "$backup/videoclip"
fi
if ! mv "$stage" "$target"; then
    if [ -n "$backup" ] && [ ! -e "$target" ]; then mv "$backup/videoclip" "$target"; fi
    echo "Installation failed. Staged files: $stage" >&2
    exit 1
fi
printf 'Installed: %s\nPreferences: %s\n' "$target" "$config_dir/script-opts/videoclip.conf"
if [ -n "$backup" ]; then printf 'Previous version: %s/videoclip\n' "$backup"; fi
echo 'Restart mpv, open a video, and press c. Press p then s to save preferences.'
