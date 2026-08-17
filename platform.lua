--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

OS-related constants and functions.
]]

local h = require('helpers')
local mp = require('mp')
local utils = require('mp.utils')
local this = {}

local function get_fallback_video_dir()
    return utils.join_path(
            h.query_user_home_dir(),
            (this.platform == this.Platform.macos and "Movies" or "Videos")
    )
end

local function get_fallback_music_dir()
    return utils.join_path(h.query_user_home_dir(), "Music")
end

this.Platform = {
    gnu_linux = "gnu_linux",
    macos = "macos",
    windows = "windows",
}
this.platform = (
        h.is_win() and this.Platform.windows
                or h.is_mac() and this.Platform.macos
                or this.Platform.gnu_linux
)
this.default_video_folder = (function()
    if this.platform == this.Platform.gnu_linux then
        return h.query_xdg_user_dir("VIDEOS") or get_fallback_video_dir()
    else
        return get_fallback_video_dir()
    end
end)()
this.default_audio_folder = (function()
    if this.platform == this.Platform.gnu_linux then
        return h.query_xdg_user_dir("MUSIC") or get_fallback_music_dir()
    else
        return get_fallback_music_dir()
    end
end)()
this.curl_exe = (this.platform == this.Platform.windows and 'curl.exe' or 'curl')
this.open_utility = (
        this.platform == this.Platform.windows and 'explorer.exe'
                or this.platform == this.Platform.macos and 'open'
                or this.platform == this.Platform.gnu_linux and 'xdg-open'
)
this.open = function(file_or_url)
    return mp.commandv('run', this.open_utility, file_or_url)
end

local function copy_via_mpv(text)
    return pcall(mp.set_property, "clipboard/text", text)
end

this.clipboard = (function()
    local self = {}
    if this.platform == this.Platform.windows then
        self.clip_exe = "powershell.exe"
        -- $input reads stdin so the value is never interpolated into the command string.
        self.copy = function(text)
            return h.subprocess({
                self.clip_exe,
                '-NoProfile',
                '-NonInteractive',
                '-Command',
                'Set-Clipboard -Value $input',
            }, text)
        end
    else
        if this.platform == this.Platform.macos then
            self.clip_exe = "pbcopy"
            self.copy = function(text)
                return h.subprocess({ "pbcopy" }, text)
            end
        elseif h.is_wayland() then
            self.clip_exe = "wl-copy"
            self.copy = function(text)
                return h.subprocess({ "wl-copy" }, text)
            end
        else
            self.clip_exe = "xclip"
            self.copy = function(text)
                return h.subprocess({ "xclip", "-i", "-selection", "clipboard" }, text)
            end
        end
    end
    return self
end)()

this.copy_or_open_url = function(url)
    if copy_via_mpv(url) then
        h.notify("Done! Copied URL to clipboard.", "info", 2)
        return { status = 0 }
    end

    local cb = this.clipboard.copy(url)
    if not cb or cb.status ~= 0 then
        local msg = string.format(
                "Failed to copy URL to clipboard, trying to open in browser instead. Make sure %s is installed.",
                this.clipboard.clip_exe
        )
        h.notify_error(msg, "warn", 4)
        this.open(url)
        return cb or { status = 1 }
    end

    h.notify("Done! Copied URL to clipboard.", "info", 2)
    return cb
end

return this
