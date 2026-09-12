# Videoclip for mpv

Save video and audio clips directly from mpv. Set a start and end time, preview the selection, then save locally or upload to Catbox/Litterbox.

- Video: MP4 or WebM, with CPU encoding or automatic NVIDIA, AMD, and Intel GPU encoding for MP4.
- Audio: AAC (`.m4a`), Opus, or MP3.
- Stream copy: keep the original streams without re-encoding; cuts depend on keyframes.
- Keyboard menus for video, audio, and upload preferences.

## Install

**[Open the installation page](https://itstatsuya.github.io/videoclip/)** or paste one command below. You only need [mpv](https://mpv.io/installation/) installed; **Git is not required**.

The installer downloads the plugin archive, creates `scripts` and `script-opts`, and installs a default config only if one does not already exist. Run it as your normal user, then restart mpv.

### Windows — PowerShell

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://itstatsuya.github.io/videoclip/install.ps1')))
```

[Read the PowerShell installer](docs/install.ps1). It uses `MPV_HOME` when set, otherwise detects `portable_config` beside mpv on PATH or running, and falls back to `%APPDATA%/mpv`.

For a portable player that cannot be detected, or a custom `--config-dir`, pass the actual configuration folder:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://itstatsuya.github.io/videoclip/install.ps1'))) -ConfigDir 'D:/Apps/mpv/portable_config'
```

### Linux / macOS — Terminal

```sh
curl -fsSL https://itstatsuya.github.io/videoclip/install.sh | sh
```

[Read the shell installer](docs/install.sh). It uses `MPV_HOME`, then `XDG_CONFIG_HOME/mpv`, then `~/.config/mpv`. It needs standard `tar` and `curl` tools; no Git or unzip is required.

For a custom directory:

```sh
curl -fsSL https://itstatsuya.github.io/videoclip/install.sh | sh -s -- '/path/to/mpv-config'
```

These installers target standalone mpv. Players that embed mpv may use different script locations. See [mpv configuration locations](https://mpv.io/manual/master/#files).

### Optional tools

- **FFmpeg:** install [FFmpeg](https://ffmpeg.org/download.html) and put it on `PATH` to use stream copy or the FFmpeg backend.
- **Uploads:** install cURL and put it on `PATH` if your system does not already provide it.
- Normal encoding uses the running mpv executable when its `binary_path` property is available. Older mpv versions may need mpv on `PATH`.

### Manual ZIP install (optional)

1. Download [the ZIP](https://github.com/ItsTatsuya/videoclip/archive/refs/heads/master.zip) and extract it.
2. Rename the extracted `videoclip-master` folder to `videoclip` and place it in your mpv `scripts` folder.
3. Create `script-opts` alongside `scripts`.
4. Copy `videoclip/config/default_config.conf` from inside the extracted repository to `script-opts/videoclip.conf`. Keep your existing config if one is already there.
5. Restart mpv and press `c` while a video is loaded.

The one-command installer creates this layout (a manual ZIP or Git install also includes repository files):

```text
mpv/
├── scripts/
│   └── videoclip/
│       ├── main.lua
│       └── videoclip/
│           ├── videoclip.lua
│           └── config/default_config.conf
└── script-opts/
    └── videoclip.conf
```

## Make your first clip

1. Open a video in mpv and press **c** to open Videoclip.
2. Seek to the beginning of your clip and press **s**.
3. Seek to the end and press **e**.
4. Press **l** to preview the range in a loop.
5. Press **c** to save video, or **a** to save audio.

The default output folders are your Videos and Music folders (Movies on macOS for video); Linux uses XDG media folders when available. Their actual paths appear under **p → 3**. Missing output folders are created automatically.

### Main-menu shortcuts

| Key | Action |
| --- | --- |
| `s` / `e` | Set start / end at the current playback time |
| `Shift+s` / `Shift+e` | Set start / end using subtitle timings |
| `[` / `]` | Go to start / end |
| `l` | Toggle preview loop |
| `r` | Reset the range |
| `c` / `a` | Save video / audio |
| `x` | Save video and upload to the configured destination |
| `Shift+c` / `Shift+x` | Save / upload at 1080p height; re-encode mode only |
| `k` | Switch between re-encoding and stream copy |
| `p` | Open preferences |
| `Esc` | Close the menu |

Setting the endpoints in reverse order swaps them automatically. Saving a clip keeps the range; loading another file clears it. Existing output names receive a numeric suffix.

## Preferences and the script-opts folder

**`script-opts` must exist and be writable to save preferences.** It is not present in every mpv installation. The installers above create it, and the script also attempts to create it when you save.

To save settings: press **c → p**, choose a page, change the displayed settings, then press **s** while in preferences.

- **1 — Video:** format, resolution, encoder, quality, subtitles, and HDR conversion.
- **2 — Audio:** audio format, bitrate, and mute.
- **3 — Upload / folders:** upload destination, expiry, and output folder paths.
- **Esc:** return to the main menu.

Changes apply during the current session. Pressing **s** writes the plugin settings to `script-opts/videoclip.conf` for future sessions. Playback mute and subtitle visibility are mpv playback settings and are not saved in this file. Saving rewrites the config and its comments.

### Create script-opts for an existing install

**PowerShell:**

```powershell
$mpvConfig = Join-Path $env:APPDATA 'mpv'
New-Item -ItemType Directory -Force -Path (Join-Path $mpvConfig 'script-opts') | Out-Null
```

**Linux / macOS:**

```sh
mkdir -p "${MPV_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/mpv}/script-opts"
```

For portable or custom installs, use the same configuration directory you installed into. Then press **s** in preferences to create `videoclip.conf`.

### Edit the config manually

| Install | Default preferences file |
| --- | --- |
| Windows | `%APPDATA%/mpv/script-opts/videoclip.conf` |
| Linux / macOS | `~/.config/mpv/script-opts/videoclip.conf` |
| Portable Windows | `portable_config/script-opts/videoclip.conf` beside `mpv.exe` |

Linux/macOS commands respect `MPV_HOME` and `XDG_CONFIG_HOME`. You can edit output folders and other options in this file; see the [example config](videoclip/config/default_config.conf). Restart mpv after manual edits. Use `key=value`, for example:

```ini
video_folder_path=~/Videos/Clips
audio_folder_path=~/Music/Clips
video_height=720
video_encoder=cpu
```

### Encoding notes

- **Subtitles / HDR:** use the mpv backend. FFmpeg re-encoding requires visible subtitles and HDR conversion to be disabled.
- **WebM:** video exports use Opus audio. Audio-only exports and MP4 video use your audio format preference.
- **CPU / GPU:** for MP4 (H.264), press **N** (`Shift+n`) on the Video preferences page to toggle **CPU** and **GPU (Auto)**, or set `video_encoder=gpu` in the config. CPU remains the default.
- **Automatic GPU selection:** works with both the mpv and FFmpeg backends. GPU mode tries NVIDIA NVENC, AMD AMF, then Intel Quick Sync by attempting the export. It remembers the first successful encoder separately for each backend during the current session. If that encoder later fails, it tries the other GPU encoders; if all fail, it retries with CPU. Initial detection can take extra time.
- **GPU requirements:** compatible hardware, drivers, and an mpv/FFmpeg build containing the corresponding encoder are required. GPU mode applies to MP4 re-encoding; WebM uses CPU and stream copy does not encode. Quality values are not directly comparable across encoders. Older `nvenc`, `amf`, and `qsv` config selections load as `gpu`; save preferences to write the updated setting.
- **Stream copy:** requires FFmpeg; preserves codecs and ignores resize/quality options. Subtitles are omitted.
- **Mute:** mute playback for silent video. Unmute before exporting an audio-only clip.
- **Uploads:** `x` sends the clip to the selected service. Litterbox is temporary; Catbox is permanent. Change the destination in preferences.

## Update

**Run the same installation command again**, then restart mpv. Your saved preferences stay in `script-opts/videoclip.conf`.

Before replacing an existing plugin, the installer moves it into `videoclip-backups` in your mpv configuration directory. This backup is outside `scripts`, so mpv will not load two copies. Failed downloads leave the installed plugin untouched.

**Existing Git installations:** the installer will not replace a Git checkout. Continue using `git pull --ff-only` inside that checkout, or move the checkout outside `scripts` before using the one-command installer. Keep `script-opts/videoclip.conf` in place to retain preferences.

## Troubleshooting

- **`c` does nothing:** load a video first, restart mpv, and check that `scripts/videoclip/main.lua` exists in the active configuration directory. Another keybinding may be using `c`.
- **Preferences will not save:** create `script-opts` using the folder-creation commands and check that you can write to it. Use the portable configuration path if applicable.
- **FFmpeg is unavailable:** confirm `ffmpeg -version` works in your shell, then restart mpv.
- **Upload fails:** check that `curl --version` works and try a smaller clip.

To change the opening key, add a line to `input.conf` in the mpv configuration directory, replacing `c` with your preferred key:

```text
c script-binding videoclip-menu-open
```

## Script messages

Other scripts can use these messages:

```text
script-message videoclip-set-start 12.5
script-message videoclip-set-end 20
script-message videoclip-reset
script-message videoclip-create-video
script-message videoclip-create-audio
script-message videoclip-create-video-upload
script-message videoclip-menu-open
```

Omit the time argument to use the current playback position.

## Development

Run the standalone tests from the repository root with either Lua or LuaJIT:

```sh
lua tests/run.lua
lua tests/hardware_encoding.lua
# Or:
luajit tests/run.lua
```

The hardware encoding tests simulate encoder success and failure to check automatic selection, caching, and CPU fallback for both backends; they do not require a GPU. Actual hardware encoding must be verified on supported hardware.

This fork is based on [Ajatt-Tools/videoclip](https://github.com/Ajatt-Tools/videoclip). See [LICENSE](LICENSE) for license terms.

### Installer tests

```sh
python tests/installers.py
```

These use local archive fixtures and temporary directories to check fresh installs, updates, preference preservation, backups, download failures, and Git checkout protection. PowerShell or shell cases are skipped when their runtime is unavailable.

### GitHub Pages

The public landing page and installers live in `docs/`. In repository **Settings → Pages**, publish from **master → /docs**. The `.nojekyll` file enables plain static hosting. Pushing changes to `docs/` updates the site.
