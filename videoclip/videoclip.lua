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
local active_menu

local CATBOX_MAX_BYTES = 200 * 1024 * 1024
local utils = require('mp.utils')

------------------------------------------------------------
-- Utility functions

local function force_resolution(width, height, clip_fn, ...)
    if config.copy_streams then
        h.notify_error('Switch to re-encode mode with k to resize a clip.', 'warn', 3)
        return
    end
    local cached_prefs = {
        video_width = config.video_width,
        video_height = config.video_height,
    }
    config.video_width = width
    config.video_height = height
    local ok, err = pcall(clip_fn, ...)
    config.video_width = cached_prefs.video_width
    config.video_height = cached_prefs.video_height
    if not ok then error(err) end
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
    local lines, longest, line_units = {}, 1, 0
    for line in (text .. '\\N'):gmatch('(.-)\\N') do
        lines[#lines + 1] = line
        line_units = line_units + (line == '' and 0.35 or 1.15)
        local cell_index = 0
        for cell in (line .. '\t'):gmatch('(.-)\t') do
            local plain = cell:gsub('{[^}]*}', ''):gsub('\\h', ' ')
            local length = 0
            for _ in plain:gmatch('[%z\1-\127\194-\244]') do length = length + 1 end
            local offset = cell_index == 0 and 0 or cell_index == 1 and 5.6 or 16
            longest = math.max(longest, length + offset / 0.55)
            cell_index = cell_index + 1
        end
    end
    local screen_w, screen_h = 1280, 720
    if mp.get_osd_size then screen_w, screen_h = mp.get_osd_size() end
    if not screen_w or not screen_h or screen_w <= 0 or screen_h <= 0 then screen_w, screen_h = 1280, 720 end
    local canvas_w = 720 * (screen_w or 1280) / math.max(1, screen_h or 720)
    local size = math.max(1, math.min(config.font_size * 0.85, 650 / line_units, (canvas_w - 64) / (longest * 0.55)))
    local width = math.min(canvas_w - 24, longest * size * 0.55 + 32)
    local height = line_units * size + 24
    local align = tonumber(config.osd_align) or 7
    local column, band = (align - 1) % 3, math.floor((align - 1) / 3)
    local x = column == 0 and 12 or column == 1 and (canvas_w - width) / 2 or canvas_w - width - 12
    local y = band == 2 and 12 or band == 1 and (720 - height) / 2 or 708 - height
    -- Blur only the backdrop drawing; text stays crisp in separate ASS events.
    local events = { string.format('{\\an7\\pos(%.2f,%.2f)\\bord0\\shad0\\blur8\\1c&H101010&\\1a&H90&\\p1}m 0 0 l %.2f 0 %.2f %.2f 0 %.2f{\\p0}', x + 6, y + 6, width - 12, width - 12, height - 12, height - 12) }
    local line_y = y + 12
    for _, line in ipairs(lines) do
        local cell_index = 0
        for cell in (line .. '\t'):gmatch('(.-)\t') do
            local offset = cell_index == 0 and 0 or cell_index == 1 and size * 5.6 or size * 16
            cell = cell:gsub('{\\fs[^}]+}', ''):gsub('{\\an%d}', '')
            events[#events + 1] = string.format('{\\an7\\pos(%.2f,%.2f)\\fs%.2f\\bord0.6\\shad0\\1c&HFFFFFF&}%s', x + 16 + offset, line_y, size, cell)
            cell_index = cell_index + 1
        end
        line_y = line_y + size * (line == '' and 0.35 or 1.15)
    end
    self.overlay.res_x, self.overlay.res_y = canvas_w, 720
    self.overlay.data = table.concat(events, '\n')
    self.overlay:update()
end

function Menu:open()
    if active_menu and active_menu ~= self then active_menu:close(true) end
    active_menu = self
    self.open_state = true
    for _, val in pairs(self.keybindings) do
        local binding = val
        mp.add_forced_key_binding(binding.key, self:binding_name(binding.key), function()
            if self.open_state and (not self.visible_keys or self.visible_keys[binding.key]) then binding.fn() end
        end)
    end
    self:update()
end

function Menu:close(switching)
    self.open_state = false
    for _, val in pairs(self.keybindings) do
        mp.remove_key_binding(self:binding_name(val.key))
    end
    if active_menu == self then active_menu = nil end
    if self.parent and not switching then
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
        force_resolution(-2, 1080, main_menu.create_clip, main_menu, 'video')
    end },
    { key = 'a', fn = function()
        main_menu:create_clip('audio')
    end },
    { key = 'x', fn = function()
        main_menu:create_clip('video', upload_video)
    end },
    { key = 'X', fn = function()
        force_resolution(-2, 1080, main_menu.create_clip, main_menu, 'video', upload_video)
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

local function menu_time(seconds)
    if seconds < 0 or seconds ~= seconds or seconds == math.huge then return '—' end
    local ms = math.floor(seconds * 1000 + 0.5)
    return string.format('%02d:%02d.%03d', math.floor(ms / 60000), math.floor(ms / 1000) % 60, ms % 1000)
end

function main_menu:update()
    if not self.open_state then return end
    local osd = OSD:new():config(config)
    local ready = self.timings:validate()
    osd:submenu('Videoclip'):newline()
    self.last_busy = encoder.is_busy()
    if encoder.is_busy() then osd:append('Encoding…')
    elseif ready then osd:selected('Range ready')
    elseif self.timings.start < 0 then osd:append('Press s to set the start')
    elseif self.timings['end'] < 0 then osd:append('Press e to set the end')
    else osd:append('End must be after start') end
    osd:newline():append('Start: '):bold(menu_time(self.timings['start'])):append('    End: '):bold(menu_time(self.timings['end']))
    if ready then osd:newline():hint(string.format('Duration: %.3f seconds', self.timings:duration())) end
    osd:newline()
    local backend = (config.use_ffmpeg or config.copy_streams) and 'ffmpeg' or 'mpv'
    if not encoder.is_alive(backend) then osd:red(backend .. ' is unavailable.'):newline() end
    osd:newline():submenu('Selection'):newline()
    osd:tab():item('s / e: '):append('Set start / end'):newline()
    osd:tab():item('Shift+s / Shift+e: '):append('Use subtitle times'):newline()
    osd:tab():item('[ / ]: '):append('Go to start / end'):newline()
    osd:tab():item('l: '):append(preview_loop_active() and 'Stop preview loop' or 'Preview loop')
        :append('    '):item('r: '):append('Reset'):newline()
    osd:newline():submenu('Export'):newline()
    osd:tab():item('c: '):append('Save video    '):item('a: '):append('Save audio'):newline()
    osd:tab():item('x: '):append('Upload to ' .. (config.custom_upload_command ~= '' and 'custom host' or config.litterbox and 'Litterbox' or 'Catbox')):newline()
    if not config.copy_streams then osd:tab():item('Shift+c / Shift+x: '):append('Export at 1080p'):newline() end
    osd:tab():item('k: '):append('Mode: ' .. (config.copy_streams and 'Stream copy' or 'Re-encode')):newline()
    osd:newline():item('p: '):append('Preferences    '):item('Esc: '):append('Close')
    self:overlay_draw(osd:get_text())
end

function main_menu:create_clip(clip_type, on_complete_fn)
    if encoder.create_clip(clip_type, on_complete_fn) then self:close() end
end

------------------------------------------------------------
-- Preferences

pref_menu = Menu:new(main_menu)
pref_menu.page = 'Video'

pref_menu.keybindings = {
    { key = '1', fn = function() pref_menu.page = 'Video'; pref_menu:update() end },
    { key = '2', fn = function() pref_menu.page = 'Audio'; pref_menu:update() end },
    { key = '3', fn = function() pref_menu.page = 'Upload'; pref_menu:update() end },
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
    if config.video_width == -2 and config.video_height == -2 then return 'Source size' end
    if config.video_width == -2 then return config.video_height .. 'p' end
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
    local visible = mp.get_property('sub-visibility') == 'yes' or mp.get_property('secondary-sub-visibility') == 'yes'
    mp.set_property('sub-visibility', visible and 'no' or 'yes')
    mp.set_property('secondary-sub-visibility', visible and 'no' or 'yes')
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
    self.visible_keys = { ['1'] = true, ['2'] = true, ['3'] = true, s = true, ESC = true, q = true }
    local function row(key, label, value)
        self.visible_keys[key] = true
        local display_key = key:match('^%u$') and 'Shift+' .. key:lower() or key
        osd:item(display_key):append('\t'):append(label)
        if value ~= nil then osd:append('\t'):append(value) end
        osd:newline()
    end
    local function section(label)
        osd:newline():submenu(label):newline()
    end
    osd:submenu('Preferences'):newline()
    for i, page in ipairs({ 'Video', 'Audio', 'Upload' }) do
        local label = i .. ' ' .. page
        if self.page == page then osd:selected('[' .. label .. ']') else osd:muted(label) end
        osd:append('    ')
    end
    osd:newline()
    if self.page ~= 'Upload' then row('C', 'Mode', config.copy_streams and 'Stream copy' or 'Re-encode') end
    if self.page == 'Video' then
        if config.copy_streams then
            osd:tab():append('Original streams · keyframe cuts · no subtitle burning'):newline()
        else
            row('g', 'Backend', config.use_ffmpeg and 'FFmpeg' or 'mpv')
            section('Video')
            row('f', 'Format', config.video_format == 'mp4' and 'MP4 (H.264)' or 'WebM (' .. config.video_format:upper() .. ')')
            row('r', 'Resolution', self:get_selected_resolution())
            row('F', 'Frame rate', config.video_fps == 'auto' and 'Source' or config.video_fps)
            if config.video_format == 'mp4' then row('N', 'Encoder', config.video_encoder == 'nvenc' and 'NVIDIA GPU' or 'CPU') end
            row('Q', 'Quality', config.video_quality)
            osd:hint('Lower quality values give more detail.'):newline()
            if self:nvenc_active() then
                row('P', 'NVENC preset', config.nvenc_preset)
                row('T', 'NVENC tune', config.nvenc_tune)
            else
                row('b', 'Bitrate', config.video_bitrate)
                if config.video_format == 'mp4' then row('P', 'Preset', config.preset) end
            end
            row('h', 'HDR to SDR', config.hdr_to_sdr and 'On' or 'Off')
        end
        if not config.copy_streams then
            section('Subtitles')
            local visible = mp.get_property('sub-visibility') == 'yes' or mp.get_property('secondary-sub-visibility') == 'yes'
            row('e', 'Subtitles', visible and 'On' or 'Off')
            osd:hint('Also changes subtitles during playback.'):newline()
            if config.use_ffmpeg then osd:hint('Subtitles / HDR: press g to use mpv.'):newline() end
        end
    elseif self.page == 'Audio' then
        section('Audio')
        row('m', 'Mute audio', mp.get_property('mute') == 'yes' and 'On' or 'Off')
        if mp.get_property('mute') == 'yes' then osd:hint('Unmute to save an audio clip.'):newline() end
        if not config.copy_streams then
            row('a', 'Audio format', config.audio_format)
            row('B', 'Audio bitrate', config.audio_bitrate)
            osd:hint('Applies to audio clips and MP4 video.'):newline()
            if config.video_format ~= 'mp4' then osd:hint('WebM video uses Opus.'):newline() end
        else
            osd:tab():append('Copy mode keeps the original audio codec.'):newline()
        end
    else
        section('Upload')
        if config.custom_upload_command ~= '' then
            osd:tab():append('Custom upload command'):newline()
        else
            row('x', 'Destination', config.litterbox and 'Litterbox' or 'Catbox')
            if config.litterbox then row('z', 'Expires after', config.litterbox_expire) end
        end
        section('Folders')
        osd:tab():append('Video · '):append(h.ass_escape(h.ellipsize_middle(config.video_folder_path:gsub('\\', '/'), 48))):newline()
        osd:tab():append('Audio · '):append(h.ass_escape(h.ellipsize_middle(config.audio_folder_path:gsub('\\', '/'), 48))):newline()
    end
    osd:newline():item('s: '):append('Save    '):item('Esc: '):append('Back')
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
        if not n or n ~= n or n == math.huge or n == -math.huge then
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

-- Refresh a reopened menu when an asynchronous encode finishes.
mp.add_periodic_timer(0.5, function()
    if main_menu.open_state and main_menu.last_busy ~= encoder.is_busy() then main_menu:update() end
end)
