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
3) Optional: install [FFmpeg](https://www.ffmpeg.org/download.html) and add it
   to `PATH` for the FFmpeg backend and for lossless stream copy.

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

### Using make

Clone the repository first, then install to `~/.config/mpv` by running:

``` bash
git clone 'https://github.com/Ajatt-Tools/videoclip.git'
cd videoclip
make install
```

The installation target copies the `videoclip/` directory to `~/.config/mpv/scripts/`.
If none exists, installs the example config to `~/.config/mpv/script-opts/videoclip.conf`.

To uninstall, run:

``` bash
make uninstall
```

To install to a different mpv config directory, set `PREFIX`:

``` bash
make PREFIX="$HOME/.config/mpv" install
```

### Manually

1) Download
   [the latest release](https://github.com/Ajatt-Tools/videoclip/releases)
   or [the master branch (trunk)](https://github.com/Ajatt-Tools/videoclip/archive/refs/heads/master.zip)
2) Extract the `videoclip/` directory from the zip file
   to your [mpv scripts](https://github.com/mpv-player/mpv/wiki/User-Scripts) directory.

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

The example configuration file is stored in
[`videoclip/config/default_config.conf`](videoclip/config/default_config.conf).
Release pages also provide it as `videoclip.conf`.

Copy it to your `script-opts` directory and edit it as needed.

Extra options on this fork: `video_encoder` (`cpu`/`nvenc`), `nvenc_preset`, `nvenc_tune`, and `audio_format=mp3`.

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

Preferences also expose upstream's FFmpeg backend (`g`) and stream copy (`C`).
Stream copy always uses FFmpeg. NVENC is available for mp4 re-encodes (`N` in preferences).

## Running tests

Run tests without mpv or a media file:

```bash
lua tests/run.lua
luajit tests/run.lua
```

Run tests inside a real mpv instance with a local media file:

```bash
VIDEOCLIP_TEST=TRUE mpv --msg-level=all=no,videoclip=warn "/path/to/video.mkv"
```
