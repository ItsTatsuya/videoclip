--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Videoclip - mp4/webm clips creator for mpv.
]]

local mp = require('mp')
local OSD = require('osd_styler')
local p = require('platform')
local h = require('helpers')
local make_encoder = require('encoder.encoder')
local Timings = require('timings_mgr')
local cfg_mgr = require("config.config")

------------------------------------------------------------
-- System-dependent variables

-- Options can be changed in the config file.
-- Config path: ~/.config/mpv/script-opts/videoclip.conf
local config = cfg_mgr.read_config_file()
local encoder = make_encoder.new()
local main_menu
local pref_menu

local CATBOX_MAX_BYTES = 200 * 1024 * 1024
local utils = require('mp.utils')

------------------------------------------------------------
-- Utility functions

local function force_resolution(width, height, clip_fn, ...)
    local cached_prefs = {
        video_width = config.video_width,
        video_height = config.video_height,
    }
    config.video_width = width
    config.video_height = height
    clip_fn(...)
    config.video_width = cached_prefs.video_width
    config.video_height = cached_prefs.video_height
end

local function upload_to_catbox(outfile)
    local info = utils.file_info(outfile)
    if info and info.size and info.size > CATBOX_MAX_BYTES then
        h.notify_error("Error: file is larger than catbox's 200 MB limit.", "error", 4)
        return
    end

    local endpoint = config.litterbox and 'https://litterbox.catbox.moe/resources/internals/api.php' or 'https://catbox.moe/user/api.php'
    h.notify("Uploading to " .. (config.litterbox and "litterbox.catbox.moe..." or "catbox.moe..."), "info", 9999)

    local args = {
        p.curl_exe, '-s',
        '-F', 'reqtype=fileupload',
        '-F', 'fileToUpload=@' .. outfile,
        endpoint,
    }
    if config.litterbox then
        table.insert(args, 5, 'time=' .. config.litterbox_expire)
        table.insert(args, 5, '-F')
    end

    h.subprocess_async(args, function(_, r, _)
        if not r or r.status < 0 or r.status > 99 then
            h.notify_error("Error: Failed to upload. Make sure cURL is installed and in your PATH.", "error", 3)
            return
        elseif r.status ~= 0 then
            h.notify_error("Error: Failed to upload to " .. (config.litterbox and "litterbox.catbox.moe" or "catbox.moe"), "error", 3)
            return
        end

        local url = h.strip(r.stdout or "")
        mp.msg.info("Catbox URL: " .. url)
        p.copy_or_open_url(url)
    end)
end

local function upload_to_custom(outfile)
    h.notify("Upload to custom destination", "info", 9999)

    local raw_args = h.parse_command_args(config.custom_upload_command)
    local exec_args = {}

    for _, arg in ipairs(raw_args) do
        local clean_arg = arg:gsub('%%f', function()
            return outfile
        end)
        table.insert(exec_args, clean_arg)
    end

    if #exec_args == 0 then
        h.notify_error("Error: custom_upload_command is empty.", "error", 2)
        return
    end

    h.subprocess_async(exec_args, function(_, r, _)
        if not r or r.status ~= 0 then
            h.notify_error("Error: Upload failed with exit code " .. tostring(r and r.status or "?"), "error", 2)
            mp.msg.error("Upload stderr: " .. ((r and r.stderr) or ""))
            return
        end

        local url = h.strip(r.stdout or "")
        mp.msg.info("Upload URL: " .. url)
        p.copy_or_open_url(url)
    end)
end

local function upload_video(outfile)
    if config.custom_upload_command ~= '' then
        upload_to_custom(outfile)
    else
        upload_to_catbox(outfile)
    end
end

local function fmt_upload_dest()
    local upload_dest
    if config.custom_upload_command ~= '' then
        upload_dest = 'custom upload'
    elseif config.litterbox then
        upload_dest = 'litterbox.catbox.moe (' .. config.litterbox_expire .. ')'
    else
        upload_dest = 'catbox.moe'
    end

    return upload_dest
end

local function clear_preview_loop()
    mp.set_property("ab-loop-a", "no")
    mp.set_property("ab-loop-b", "no")
end

local function preview_loop_active()
    local a = mp.get_property("ab-loop-a")
    return a ~= nil and a ~= "no"
end

------------------------------------------------------------
-- Menu interface

local Menu = {}
Menu.__index = Menu

function Menu:new(parent)
    local o = {
        parent = parent,
        overlay = parent and parent.overlay or mp.create_osd_overlay('ass-events'),
        keybindings = { },
        binding_prefix = parent and 'videoclip-pref-' or 'videoclip-main-',
    }
    return setmetatable(o, self)
end

function Menu:binding_name(key)
    return self.binding_prefix .. key
end

function Menu:overlay_draw(text)
    self.overlay.data = text
    self.overlay:update()
end

function Menu:open()
    if self.parent then
        self.parent:close()
    end
    self.open_state = true
    for _, val in pairs(self.keybindings) do
        mp.add_forced_key_binding(val.key, self:binding_name(val.key), val.fn)
    end
    self:update()
end

function Menu:close()
    self.open_state = false
    for _, val in pairs(self.keybindings) do
        mp.remove_key_binding(self:binding_name(val.key))
    end
    if self.parent then
        self.parent:open()
    else
        self.overlay:remove()
    end
end

function Menu:update()
    local osd = OSD:new():config(config)
    osd:append('Dummy menu.'):newline()
    self:overlay_draw(osd:get_text())
end

------------------------------------------------------------
-- Main menu

main_menu = Menu:new()
main_menu.timings = Timings:new()

main_menu.keybindings = {
    { key = 's', fn = function()
        main_menu:set_time('start')
    end },
    { key = 'e', fn = function()
        main_menu:set_time('end')
    end },
    { key = 'S', fn = function()
        main_menu:set_time_sub('start')
    end },
    { key = 'E', fn = function()
        main_menu:set_time_sub('end')
    end },
    { key = '[', fn = function()
        main_menu:seek_to('start')
    end },
    { key = ']', fn = function()
        main_menu:seek_to('end')
    end },
    { key = 'l', fn = function()
        main_menu:toggle_preview()
    end },
    { key = 'r', fn = function()
        main_menu:reset_timings()
    end },
    { key = 'k', fn = function()
        config.copy_streams = not config.copy_streams
        main_menu:update()
    end },
    { key = 'c', fn = function()
        main_menu:create_clip('video')
    end },
    { key = 'C', fn = function()
        force_resolution(1920, -2, main_menu.create_clip, main_menu, 'video')
    end },
    { key = 'a', fn = function()
        main_menu:create_clip('audio')
    end },
    { key = 'x', fn = function()
        main_menu:create_clip('video', upload_video)
    end },
    { key = 'X', fn = function()
        force_resolution(1920, -2, main_menu.create_clip, main_menu, 'video', upload_video)
    end },
    { key = 'p', fn = function()
        pref_menu:open()
    end },
    { key = 'ESC', fn = function()
        main_menu:close()
    end },
}

function main_menu:set_time(property)
    self.timings[property] = math.max(0, mp.get_property_number('time-pos') or 0)
    if self.timings:normalize() then
        h.notify("Start/end swapped.", "info", 1)
    end
    self:update()
end

function main_menu:set_time_sub(property)
    local sub_delay = mp.get_property_native("sub-delay")
    local time_pos = mp.get_property_number(string.format("sub-%s", property))

    if time_pos == nil then
        h.notify_error("Warning: No subtitles visible.", "warn", 2)
        return
    end

    self.timings[property] = math.max(0, time_pos + (sub_delay or 0))
    if self.timings:normalize() then
        h.notify("Start/end swapped.", "info", 1)
    end
    self:update()
end

function main_menu:seek_to(property)
    local time_pos = self.timings[property]
    if type(time_pos) ~= 'number' or time_pos < 0 then
        h.notify_error("No " .. property .. " time set.", "warn", 1)
        return
    end
    mp.set_property_number("time-pos", time_pos)
end

function main_menu:toggle_preview()
    if not self.timings:validate() then
        h.notify_error("Set start and end first.", "warn", 2)
        return
    end
    local current_a = mp.get_property_number("ab-loop-a")
    if preview_loop_active() and current_a == self.timings['start'] then
        clear_preview_loop()
        h.notify("Preview loop cleared.", "info", 1)
    else
        mp.set_property_number("ab-loop-a", self.timings['start'])
        mp.set_property_number("ab-loop-b", self.timings['end'])
        mp.set_property_number("time-pos", self.timings['start'])
        mp.set_property_native("pause", false)
        h.notify("Looping selection.", "info", 1)
    end
    self:update()
end

function main_menu:reset_timings()
    self.timings:reset()
    clear_preview_loop()
    self:update()
end

main_menu.open = function()
    Menu.open(main_menu)
end

function main_menu:update()
    local osd = OSD:new():config(config)
    if not config.use_ffmpeg and not config.copy_streams and not encoder.is_alive("mpv") then
        osd:red("Error: "):append("mpv is not found in the PATH."):newline()
    end
    if (config.use_ffmpeg or config.copy_streams) and not encoder.is_alive("ffmpeg") then
        osd:red("Error: "):append("ffmpeg is not found in the PATH. FFmpeg encoder is unavailable."):newline()
    end
    osd:submenu('Timings '):italics('(+shift use sub timings)'):newline()
    osd:tab():item('s: '):append('start time '):item(h.human_readable_time(self.timings['start'])):newline()
    osd:tab():item('e: '):append('end time '):item(h.human_readable_time(self.timings['end'])):newline()
    osd:tab():item('[: '):append('seek to start'):newline()
    osd:tab():item(']: '):append('seek to end'):newline()
    osd:tab():item('l: '):append(preview_loop_active() and 'clear preview loop' or 'preview loop'):newline()
    osd:tab():item('r: '):append('reset'):newline()
    osd:submenu('Create clip '):italics('(+shift to force fullHD preset)'):newline()
    if config.copy_streams then
        osd:tab():append("stream copy (lossless, keyframe-accurate)"):newline()
    end
    osd:tab():item('c: '):append('video clip'):newline()
    osd:tab():item('a: '):append('audio clip'):newline()
    osd:tab():item('x: '):append('video clip to ' .. fmt_upload_dest()):newline()
    osd:tab():item('k: '):append('stream copy: '):append(config.copy_streams and 'yes' or 'no'):newline()

    osd:submenu('Options '):newline()
    osd:tab():item('p: '):append('Open preferences'):newline()
    osd:tab():item('ESC: '):append('Close'):newline()

    self:overlay_draw(osd:get_text())
end

function main_menu:create_clip(clip_type, on_complete_fn)
    self:close()
    encoder.create_clip(clip_type, on_complete_fn)
end

------------------------------------------------------------
-- Preferences

pref_menu = Menu:new(main_menu)

pref_menu.keybindings = {
    { key = 'f', fn = function()
        pref_menu:cycle_video_formats()
    end },
    { key = 'a', fn = function()
        pref_menu:cycle_audio_formats()
    end },
    { key = 'm', fn = function()
        pref_menu:toggle_mute_audio()
    end },
    { key = 'r', fn = function()
        pref_menu:cycle_resolutions()
    end },
    { key = 'b', fn = function()
        pref_menu:cycle_video_bitrates()
    end },
    { key = 'B', fn = function()
        pref_menu:cycle_audio_bitrates()
    end },
    { key = 'e', fn = function()
        pref_menu:toggle_embed_subtitles()
    end },
    { key = 'g', fn = function()
        pref_menu:toggle_use_ffmpeg()
    end },
    { key = 'C', fn = function()
        pref_menu:toggle_copy_streams()
    end },
    { key = 'N', fn = function()
        pref_menu:cycle_video_encoders()
    end },
    { key = 'P', fn = function()
        pref_menu:cycle_preset()
    end },
    { key = 'T', fn = function()
        pref_menu:cycle_nvenc_tune()
    end },
    { key = 'Q', fn = function()
        pref_menu:cycle_video_quality()
    end },
    { key = 'F', fn = function()
        pref_menu:cycle_fps()
    end },
    { key = 'h', fn = function()
        pref_menu:toggle_hdr()
    end },
    { key = 'x', fn = function()
        pref_menu:toggle_catbox()
    end },
    { key = 'z', fn = function()
        pref_menu:cycle_litterbox_expiration()
    end },
    { key = 's', fn = function()
        pref_menu:save()
    end },
    { key = 'c', fn = function()
    end },
    { key = 'ESC', fn = function()
        pref_menu:close()
    end },
    { key = 'q', fn = function()
        pref_menu:close()
    end },
}

pref_menu.resolutions = {
    { w = config.video_width, h = config.video_height, },
    { w = -2, h = -2, },
    { w = -2, h = 240, },
    { w = -2, h = 360, },
    { w = -2, h = 480, },
    { w = -2, h = 720, },
    { w = -2, h = 1080, },
    { w = -2, h = 1440, },
    { w = -2, h = 2160, },
    selected = 1,
}
pref_menu.audio_bitrates = {
    config.audio_bitrate,
    '32k',
    '64k',
    '128k',
    '192k',
    '256k',
    '384k',
    selected = 1,
}
pref_menu.video_bitrates = {
    config.video_bitrate,
    '500k',
    '1M',
    '2M',
    '4M',
    '8M',
    '16M',
    selected = 1,
}

pref_menu.vid_formats = { 'mp4', 'vp9', 'vp8', }
pref_menu.vid_encoders = { 'cpu', 'nvenc', }
pref_menu.nvenc_presets = { 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', }
pref_menu.nvenc_tunes = { 'hq', 'll', 'ull', 'lossless', }
pref_menu.video_qualities = { 15, 18, 20, 23, 26, 28, 32, 35, selected = 1, }
pref_menu.aud_formats = { 'aac', 'opus', 'mp3', }
pref_menu.litterbox_expirations = { '1h', '12h', '24h', '72h', }
pref_menu.fps_values = { 'auto', '24', '25', '30', '50', '60', }
pref_menu.preset_list = {
    'ultrafast', 'superfast', 'veryfast', 'faster', 'fast',
    'medium', 'slow', 'slower', 'veryslow',
}

for i, quality in ipairs(pref_menu.video_qualities) do
    if config.video_quality == quality then
        pref_menu.video_qualities.selected = i
        break
    end
end

function pref_menu:get_selected_resolution()
    return string.format(
            '%s x %s',
            config.video_width == -2 and 'auto' or config.video_width,
            config.video_height == -2 and 'auto' or config.video_height
    )
end

function pref_menu:cycle_resolutions()
    self.resolutions.selected = self.resolutions.selected + 1 > #self.resolutions and 1 or self.resolutions.selected + 1
    local res = self.resolutions[self.resolutions.selected]
    config.video_width = res.w
    config.video_height = res.h
    self:update()
end

--- Cycle through a list of bitrate presets and update the corresponding config value.
--- @param bitrates_key string key into self (e.g. 'audio_bitrates', 'video_bitrates')
--- @param config_key string key into config (e.g. 'audio_bitrate', 'video_bitrate')
function pref_menu:cycle_bitrates(bitrates_key, config_key)
    self[bitrates_key].selected = self[bitrates_key].selected + 1 > #self[bitrates_key] and 1 or self[bitrates_key].selected + 1
    config[config_key] = self[bitrates_key][self[bitrates_key].selected]
    self:update()
end

function pref_menu:cycle_audio_bitrates()
    self:cycle_bitrates('audio_bitrates', 'audio_bitrate')
end

function pref_menu:cycle_video_bitrates()
    self:cycle_bitrates('video_bitrates', 'video_bitrate')
end

function pref_menu:cycle_formats(config_type)
    local formats
    if config_type == 'video_format' then
        formats = pref_menu.vid_formats
    else
        formats = pref_menu.aud_formats
    end

    local selected = 1
    for i, format in ipairs(formats) do
        if config[config_type] == format then
            selected = i
            break
        end
    end
    config[config_type] = formats[selected + 1] or formats[1]
    cfg_mgr.set_encoding_settings(config)
    self:update()
end

function pref_menu:cycle_video_formats()
    pref_menu:cycle_formats('video_format')
end

function pref_menu:cycle_audio_formats()
    pref_menu:cycle_formats('audio_format')
end

function pref_menu:toggle_mute_audio()
    mp.commandv("cycle", "mute")
    self:update()
end

function pref_menu:toggle_embed_subtitles()
    mp.commandv("cycle", "sub-visibility")
    self:update()
end

function pref_menu:toggle_use_ffmpeg()
    config.use_ffmpeg = not config.use_ffmpeg
    self:update()
end

function pref_menu:toggle_copy_streams()
    config.copy_streams = not config.copy_streams
    self:update()
end

function pref_menu:nvenc_active()
    return config.video_format == 'mp4' and config.video_encoder == 'nvenc'
end

function pref_menu:cycle_video_encoders()
    if config.video_format ~= 'mp4' then
        h.notify_error("NVENC is only available for mp4 (H.264).", "warn", 2)
        return
    end
    config.video_encoder = h.next_in_list(self.vid_encoders, config.video_encoder)
    cfg_mgr.set_encoding_settings(config)
    self:update()
end

function pref_menu:cycle_preset()
    if self:nvenc_active() then
        config.nvenc_preset = h.next_in_list(self.nvenc_presets, config.nvenc_preset)
    else
        config.preset = h.next_in_list(self.preset_list, config.preset)
    end
    self:update()
end

function pref_menu:cycle_nvenc_tune()
    if not self:nvenc_active() then
        return
    end
    config.nvenc_tune = h.next_in_list(self.nvenc_tunes, config.nvenc_tune)
    self:update()
end

function pref_menu:cycle_video_quality()
    self.video_qualities.selected = self.video_qualities.selected + 1 > #self.video_qualities
            and 1 or self.video_qualities.selected + 1
    config.video_quality = self.video_qualities[self.video_qualities.selected]
    self:update()
end

function pref_menu:cycle_fps()
    config.video_fps = h.next_in_list(self.fps_values, tostring(config.video_fps))
    self:update()
end

function pref_menu:toggle_hdr()
    config.hdr_to_sdr = not config.hdr_to_sdr
    self:update()
end

function pref_menu:toggle_catbox()
    config['litterbox'] = not config['litterbox']
    self:update()
end

function pref_menu:cycle_litterbox_expiration()
    if not config['litterbox'] then
        return
    end
    local expirations = pref_menu.litterbox_expirations

    local selected = 1
    for i, expiration in ipairs(expirations) do
        if config['litterbox_expire'] == expiration then
            selected = i
            break
        end
    end
    config['litterbox_expire'] = expirations[selected + 1] or expirations[1]
    self:update()
end

function pref_menu:update()
    local osd = OSD:new():config(config)
    osd:submenu('Preferences'):newline()
    osd:tab():item('r: Video resolution: '):append(self:get_selected_resolution()):newline()
    osd:tab():item('b: Video bitrate: '):append(config.video_bitrate):newline()
    osd:tab():item('f: Video format: '):append(config.video_format):newline()
    if config.video_format == 'mp4' then
        osd:tab():item('N: Video encoder: '):append(config.video_encoder):newline()
    else
        osd:tab():color("b0b0b0"):text('N: Video encoder: '):append("N/A (mp4 only)"):newline()
    end
    if self:nvenc_active() and not config.copy_streams then
        osd:tab():item('P: NVENC preset: '):append(config.nvenc_preset):newline()
        osd:tab():item('T: NVENC tune: '):append(config.nvenc_tune):newline()
    elseif not config.copy_streams then
        osd:tab():item('P: Encoder preset: '):append(config.preset):newline()
    end
    osd:tab():item('Q: Quality (CRF/CQ): '):append(tostring(config.video_quality)):newline()
    osd:tab():item('F: FPS: '):append(tostring(config.video_fps)):newline()
    osd:tab():item('a: Audio format: '):append(config.audio_format):append(' (audio clips)'):newline()
    osd:tab():item('B: Audio bitrate: '):append(config.audio_bitrate):newline()
    osd:tab():item('g: Use FFmpeg: '):append(config.use_ffmpeg and 'yes' or 'no'):newline()
    osd:tab():item('C: Copy streams: '):append(config.copy_streams and 'yes' or 'no'):newline()
    osd:tab():item('h: HDR to SDR: '):append(config.hdr_to_sdr and 'yes' or 'no'):newline()
    osd:tab():item('m: Mute audio: '):append(mp.get_property("mute")):newline()
    osd:tab():item('e: Embed subtitles: '):append(mp.get_property("sub-visibility")):newline()
    osd:submenu('Folders'):newline()
    osd:tab():append('Video: '):append(h.ass_escape(h.ellipsize_middle(config.video_folder_path, 48))):newline()
    osd:tab():append('Audio: '):append(h.ass_escape(h.ellipsize_middle(config.audio_folder_path, 48))):newline()
    osd:submenu('Catbox'):newline()
    osd:tab():item('x: Using: '):append(config.litterbox and 'Litterbox (temporary)' or 'Catbox (permanent)'):newline()
    if config.litterbox then
        osd:tab():item('z: Litterbox expires after: '):append(config.litterbox_expire):newline()
    else
        osd:tab():color("b0b0b0"):text('z: Litterbox expires after: '):append("N/A"):newline()
    end
    osd:submenu('Save'):newline()
    osd:tab():item('s: Save preferences'):newline()
    self:overlay_draw(osd:get_text())
end

function pref_menu:save()
    local result, error = cfg_mgr.save_config_file(config)
    if h.is_empty(error) then
        h.notify(result, "info", 4)
    else
        h.notify(error, "error", 4)
    end
end

------------------------------------------------------------
-- Tests

local function run_tests()
    h.run_tests()
    cfg_mgr.run_tests()
    require('encoder.utils').run_tests()
    require('encoder.mpv').run_tests()
    require('encoder.ffmpeg').run_tests()
    make_encoder.run_tests()
end

local function pcall_tests()
    if os.getenv("VIDEOCLIP_TEST") == "TRUE" then
        mp.msg.warn("RUNNING TESTS")
        local success, err = pcall(run_tests)
        if success then
            mp.msg.warn("TESTS PASSED")
        else
            mp.msg.error("TESTS FAILED")
            mp.msg.error(err)
        end
        mp.commandv("quit")
    end
end

------------------------------------------------------------
-- Finally, set an 'entry point' in mpv

local main = (function()
    local main_executed = false
    return function()
        if main_executed then
            main_menu.timings:reset()
            return
        else
            main_executed = true
        end

        cfg_mgr.validate_config(config)
        encoder.init(config, main_menu.timings)
        pcall_tests()
        mp.add_key_binding('c', 'videoclip-menu-open', main_menu.open)
        mp.msg.info("Press 'c' to open the videoclip menu.")
    end
end)()

local function message_set_time(property, value)
    if value ~= nil and value ~= "" then
        local n = tonumber(value)
        if not n then
            h.notify_error("Invalid time: " .. tostring(value), "warn", 2)
            return
        end
        main_menu.timings[property] = math.max(0, n)
    else
        main_menu:set_time(property)
        return
    end
    if main_menu.timings:normalize() then
        h.notify("Start/end swapped.", "info", 1)
    end
    if main_menu.open_state then
        main_menu:update()
    end
end

mp.register_script_message("videoclip-menu-open", main_menu.open)
mp.register_script_message("videoclip-set-start", function(value)
    message_set_time('start', value)
end)
mp.register_script_message("videoclip-set-end", function(value)
    message_set_time('end', value)
end)
mp.register_script_message("videoclip-reset", function()
    main_menu:reset_timings()
end)
mp.register_script_message("videoclip-create-video", function()
    encoder.create_clip('video')
end)
mp.register_script_message("videoclip-create-audio", function()
    encoder.create_clip('audio')
end)
mp.register_script_message("videoclip-create-video-upload", function()
    encoder.create_clip('video', upload_video)
end)

mp.register_event("file-loaded", function()
    clear_preview_loop()
    main()
    if main_menu.open_state then
        main_menu:update()
    end
end)
