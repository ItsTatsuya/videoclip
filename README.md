![screenshot](https://github.com/Lemmmy/videoclip/assets/858456/855bff15-b0cd-4c12-a9ac-40a5e01d3b83)

# videoclip

[![Chat](https://img.shields.io/badge/chat-join-green)](https://tatsumoto-ren.github.io/blog/join-our-community.html)
![GitHub](https://img.shields.io/github/license/Ajatt-Tools/videoclip)
![GitHub top language](https://img.shields.io/github/languages/top/Ajatt-Tools/videoclip)
[![Patreon](https://img.shields.io/badge/support-patreon-orange)](https://tatsumoto.neocities.org/blog/donating-to-tatsumoto.html)

Easily create video and audio clips with mpv in a few keypresses.
Videoclips are saved as `.mp4` or `.webm` (or copied in the source container).
Audio clips are saved as `.m4a`, `.opus`, or `.mp3`.
Subtitles can be burned into re-encoded clips.

## Prerequisites

1) [Install mpv](https://mpv.io/installation/).
2) Encoding uses the same `mpv` binary that is playing the file
   (`binary_path`). A portable install does not need to be on `PATH`.

   If you are on an older mpv without `binary_path`, add the directory
   where `mpv` is installed to the
   [PATH](https://www.mojeek.com/search?q=path+variable).

## Installation

### Using git

Clone the repository to the `mpv/scripts` directory.
The command below works on the GNU operating system with `git` installed.

``` bash
git clone 'https://github.com/Ajatt-Tools/videoclip.git' ~/.config/mpv/scripts/videoclip
```

To update the user-script on demand later, you can execute:

``` bash
cd ~/.config/mpv/scripts/videoclip && git pull
```

### Manually

Download
[the repository](https://github.com/Ajatt-Tools/videoclip/archive/refs/heads/master.zip)
and extract the folder containing
`videoclip.lua`
to your [mpv scripts](https://github.com/mpv-player/mpv/wiki/User-Scripts) directory:

| OS | Location |
| --- | --- |
| GNU/Linux | `~/.config/mpv/scripts/` |
| Windows | `C:/Users/Username/AppData/Roaming/mpv/scripts/` |

Note: in [Celluloid](https://www.archlinux.org/packages/community/x86_64/celluloid/)
user scripts are installed by switching to the "Plugins" tab
in the preferences dialog and dropping the files there.

<details>

<summary>Expected directory tree</summary>

```
~/.config/mpv/scripts
|-- other_addon_1
|-- other_addon_2
`-- videoclip
    |-- main.lua
    |-- ...
    `-- videoclip.lua
```

</details>

## Configuration

The config file should be created by the user, if needed.

| OS | Config location |
| --- | --- |
| GNU/Linux | `~/.config/mpv/script-opts/videoclip.conf` |
| Windows | `C:/Users/Username/AppData/Roaming/mpv/script-opts/videoclip.conf` |

If a parameter is not specified in the config file, the default value will be used.
mpv doesn't tolerate spaces before and after `=`.

Example configuration file:

```
# Absolute paths to the folders where generated clips will be placed.
# `~` is supported, but environment variables (e.g. `$HOME`) are not supported due to mpv limitations.
video_folder_path=~/Videos
audio_folder_path=~/Music

# Menu size
font_size=24

# OSD settings. Line alignment: https://aegisub.org/docs/3.2/ASS_Tags/#\an
osd_align=7
osd_outline=1.5

# Clean filenames (remove special characters) (yes or no)
clean_filename=yes

# Video settings
video_width=-2
video_height=480
# Kept for compatibility. Re-encodes use quality (CRF/CQ), not bitrate.
video_bitrate=1M
# Available video formats: mp4, vp9, vp8
# Video clips use AAC inside mp4 and Opus inside webm.
video_format=mp4
# Video encoder: cpu (libx264) or nvenc (h264_nvenc, NVIDIA GPU).
# NVENC only applies when video_format=mp4. Failed NVENC encodes retry on CPU.
video_encoder=cpu
# The range of the scale is 0–51, where 0 is lossless,
# 23 is the default, and 51 is worst quality possible.
# Insane values like 9999 still work but produce the worst quality.
# For NVENC this maps to CQ (constant quality) in VBR mode.
video_quality=23
# Use the slowest preset that you have patience for (CPU/libx264 only).
# https://trac.ffmpeg.org/wiki/Encode/H.264
preset=faster
# NVENC preset p1 (fastest) through p7 (slowest, best quality).
nvenc_preset=p5
# NVENC tune: hq (quality), ll (low latency), ull, lossless.
nvenc_tune=hq

# Copy streams instead of re-encoding (fast, lossless, keyframe-accurate).
# Subtitles cannot be burned in while copying.
copy_streams=no
# HDR tone-map: auto (when source is HDR), hable (always), no (never).
tonemap=auto

# In the preferences menu (press p):
#   Q - cycle quality CRF/CQ (15-35, lower = better quality)
#   P - cycle encoder preset (libx264 names, or p1-p7 when NVENC is on)
#   T - cycle NVENC tune (only when NVENC is on)
#   F - cycle FPS (auto, 24, 25, 30, 50, 60)
#   k - toggle stream copy
#   n - cycle tone-map mode
# FPS / framerate. Set to "auto" or a number.
video_fps=auto
#video_fps=60

# Audio settings (audio-only clips)
# Available formats: opus (.opus), aac (.m4a), or mp3 (.mp3)
audio_format=opus
# Opus sounds good at low bitrates 32-64k, but aac and mp3 require 128-256k.
# AAC/MP3 encodes below 96k are raised to 128k automatically.
audio_bitrate=32k

# Catbox.moe upload settings
# Whether uploads should go to litterbox instead of catbox.
# catbox files are stored permanently, while litterbox is temporary
litterbox=yes
# If using litterbox, time until video expires
# Available values: 1h, 12h, 24h, 72h
litterbox_expire=72h

# Custom upload command (replaces catbox.moe)
# Use %f as placeholder for the file path
# Example for 0x0.st:
# custom_upload_command=curl -F'file=@%f' https://0x0.st
# You can also make a bash script and set custom_upload_command to `bash ~/path/to/upload.sh %f` to achieve more customizability.
custom_upload_command=

# Filename format
# Available tags: %n = filename, %t = title, %s = start, %e = end, %d = duration,
#                 %Y = year, %M = months, %D = day, %H = hours (24), %I = hours (12),
#                 %P = am/pm %N = minutes, %S = seconds
# Title will fallback to filename if it's not present
#filename_template=%n_%s-%e(%d)
filename_template=%n_%s-%e
```

### Key bindings

| OS | Config location |
| --- | --- |
| GNU/Linux | `~/.config/mpv/input.conf` |
| Windows | `C:/Users/Username/AppData/Roaming/mpv/input.conf` |

Add this line if you want to change the key that opens the script's menu.

```
c script-binding videoclip-menu-open
```

Other scripts or `input.conf` can drive videoclip without the menu:

```
script-message videoclip-set-start
script-message videoclip-set-end
script-message videoclip-set-start 12.5
script-message videoclip-set-end 20
script-message videoclip-reset
script-message videoclip-create-video
script-message videoclip-create-audio
script-message videoclip-create-video-upload
script-message videoclip-menu-open
```

## Usage

- Open a file in mpv and press `c` to open the script menu.
- Set the start point (`s`) and end point (`e`). If you set them in
  the wrong order they are swapped automatically.
- `[` / `]` seek to the start / end. `l` loops the selection for a preview.
- Press `c` to create a video clip, `a` for audio, `x` to create and upload.
  Shift+`c` / Shift+`x` force a 1080p-tall encode (ignored in stream-copy mode).
- `k` toggles stream copy (lossless remux, cuts on keyframes).
- `r` resets timings. Times are also cleared when you open a new file.
  Creating a clip no longer wipes the current range.

It is possible to create silent videoclips.
To do that, first mute audio in mpv.
The default key binding is `m`.
Muted playback will not create a silent *audio* clip; unmute first.

If a video has visible subtitles, they will be burned in when re-encoding.
Toggle them off in mpv if you don't want any subtitles to be visible.
The default key binding is `v`. Stream copy cannot burn in subtitles.

Existing output files are not overwritten; a `-2`, `-3`, … suffix is added.
Missing output folders are created automatically. mp4 outputs use `faststart`.
