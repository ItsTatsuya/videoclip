--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Various helper functions.
]]

local mp = require('mp')
local utils = require('mp.utils')
local this = {}
local ass_start = mp.get_property_osd("osd-ass-cc/0")

local WINDOWS_RESERVED = {
    CON = true, PRN = true, AUX = true, NUL = true,
    COM1 = true, COM2 = true, COM3 = true, COM4 = true, COM5 = true,
    COM6 = true, COM7 = true, COM8 = true, COM9 = true,
    LPT1 = true, LPT2 = true, LPT3 = true, LPT4 = true, LPT5 = true,
    LPT6 = true, LPT7 = true, LPT8 = true, LPT9 = true,
}

this.is_wayland = function()
    return os.getenv('WAYLAND_DISPLAY') ~= nil
end

this.is_win = function()
    local platform = mp.get_property("platform")
    if platform then
        return platform == "windows"
    end
    return package.config:sub(1, 1) == '\\' or (os.getenv("OS") or ""):match("Windows") ~= nil
end

this.is_mac = function()
    local platform = mp.get_property("platform")
    if platform then
        return platform == "darwin"
    end
    return false
end

this.ass_escape = function(str)
    if str == nil then
        return ""
    end
    str = tostring(str)
    str = str:gsub('\\', '\\\\')
    str = str:gsub('{', '\\{')
    str = str:gsub('\n', '\\N')
    return str
end

this.notify = function(message, level, duration)
    level = level or 'info'
    duration = duration or 1
    mp.msg[level](message)
    mp.osd_message(ass_start .. "{\\fs12}{\\bord0.75}" .. this.ass_escape(message), duration)
end

this.notify_error = function(message, level, duration)
    level = level or 'error'
    duration = duration or 1
    mp.msg[level](message)
    mp.osd_message(ass_start .. "{\\fs12}{\\bord0.75}{\\c&H7171f8&}" .. this.ass_escape(message), duration)
end

this.subprocess = function(args, stdin)
    local command_table = {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = args,
        stdin_data = (stdin or ""),
    }
    return mp.command_native(command_table)
end

this.subprocess_async = function(args, on_complete)
    local command_table = {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = args,
    }
    return mp.command_native_async(command_table, on_complete)
end

this.remove_extension = function(filename)
    return filename:gsub('%.%w+$', '')
end

this.remove_text_in_brackets = function(str)
    return str:gsub('%b[]', '')
end

this.remove_special_characters = function(str)
    return str:gsub('[%-_]', ' '):gsub('[%c%p]', ''):gsub('%s+', ' ')
end

this.strip = function(str)
    return str:gsub("^%s*(.-)%s*$", "%1")
end

this.two_digit = function(num)
    return string.format("%02d", num)
end

this.twelve_hour = function(num)
    local hour = num % 12
    if hour == 0 then
        hour = 12
    end
    local sign = (num < 12) and "am" or "pm"
    return { sign = sign, hour = hour }
end

this.expand_path = function(str)
    return mp.command_native({"expand-path", str})
end

-- Locale-safe seconds -> "123.456" (never uses a comma decimal).
this.format_timestamp = function(timestamp)
    local ms_total = math.floor((tonumber(timestamp) or 0) * 1000 + 0.5)
    if ms_total < 0 then
        ms_total = 0
    end
    local sec = math.floor(ms_total / 1000)
    local frac = ms_total % 1000
    return string.format("%d.%03d", sec, frac)
end

this.human_readable_time = function(seconds)
    if type(seconds) ~= 'number' or seconds < 0 then
        return 'empty'
    end

    local parts = {}

    parts.h = math.floor(seconds / 3600)
    parts.m = math.floor(seconds / 60) % 60
    parts.s = math.floor(seconds % 60)
    parts.ms = math.floor((seconds * 1000) % 1000)

    local ret = string.format("%02dm%02ds%03dms", parts.m, parts.s, parts.ms)

    if parts.h > 0 then
        ret = string.format('%dh%s', parts.h, ret)
    end

    return ret
end

this.quote_if_necessary = function(args)
    local ret = {}
    for _, v in ipairs(args) do
        if v:find(" ", 1, true) or v:find("[", 1, true) then
            table.insert(ret, (v:find("'") and string.format('"%s"', v) or string.format("'%s'", v)))
        else
            table.insert(ret, v)
        end
    end
    return ret
end

this.query_xdg_user_dir = function(name)
    local r = this.subprocess({ "xdg-user-dir", name })
    if r.status == 0 then
        return this.strip(r.stdout)
    end
    return nil
end

this.query_user_home_dir = function()
    --- "USERPROFILE" is used on ReactOS and other Windows-like systems.
    return os.getenv("HOME") or os.getenv("USERPROFILE") or "."
end

this.clean_forbidden_characters = function(title)
    return title:gsub('[<>:"/\\|%?%*]+', '.')
end

this.truncate_utf8_bytes = function(s, max_bytes)
    local size = #s
    local idx = 1

    if size <= max_bytes then
        return s
    end

    while idx <= size do
        local b = s:byte(idx)
        local char_len = 1
        if not b then
            break
        end

        if b <= 0x7F then
            char_len = 1
        elseif b >= 0xC2 and b <= 0xDF then
            char_len = 2
        elseif b >= 0xE0 and b <= 0xEF then
            char_len = 3
        elseif b >= 0xF0 and b <= 0xF4 then
            char_len = 4
        else
            break
        end

        if idx - 1 + char_len > max_bytes then
            break
        end

        idx = idx + char_len
    end

    if idx <= 1 then
        return "new_file"
    end
    return s:sub(1, idx - 1)
end

this.sanitize_filename = function(name)
    name = this.clean_forbidden_characters(name or "")
    name = this.strip(name)
    name = name:gsub("[%.%s]+$", "")
    if name == "" then
        name = "clip"
    end
    local stem = name:match("^([^%.]+)") or name
    if WINDOWS_RESERVED[stem:upper()] then
        name = "_" .. name
    end
    return this.truncate_utf8_bytes(name, 200)
end

this.next_in_list = function(list, current)
    local selected = 1
    for i, value in ipairs(list) do
        if value == current then
            selected = i
            break
        end
    end
    return list[selected + 1] or list[1]
end

this.absolute_media_path = function(path)
    if not path or path == "" then
        return nil
    end
    if path:match("://") then
        return path
    end
    if this.is_win() then
        if path:match("^%a:[/\\]") or path:match("^\\\\") then
            return path
        end
    elseif path:match("^/") then
        return path
    end
    local pwd = mp.get_property("working-directory")
    if pwd and pwd ~= "" then
        return utils.join_path(pwd, path)
    end
    return path
end

this.first_line = function(text, max_len)
    if not text or text == "" then
        return ""
    end
    local line = text:match("([^\r\n]+)") or text
    line = this.strip(line)
    max_len = max_len or 160
    if #line > max_len then
        line = line:sub(1, max_len) .. "..."
    end
    return line
end

this.ensure_dir = function(path)
    if not path or path == "" then
        return false
    end
    local info = utils.file_info(path)
    if info and info.is_dir then
        return true
    end
    local result
    if this.is_win() then
        result = this.subprocess({ "cmd", "/c", "mkdir", path })
    else
        result = this.subprocess({ "mkdir", "-p", path })
    end
    info = utils.file_info(path)
    return info ~= nil and info.is_dir == true and result ~= nil
end

this.unique_path = function(path)
    if not utils.file_info(path) then
        return path
    end
    local dir, file = utils.split_path(path)
    local stem, ext = file:match("^(.*)(%.[^%.]+)$")
    if not stem then
        stem, ext = file, ""
    end
    local i = 2
    local candidate = path
    while utils.file_info(candidate) do
        candidate = utils.join_path(dir, stem .. "-" .. i .. ext)
        i = i + 1
        if i > 999 then
            break
        end
    end
    return candidate
end

this.ellipsize_middle = function(str, max_len)
    str = tostring(str or "")
    if #str <= max_len then
        return str
    end
    local keep = math.floor((max_len - 3) / 2)
    return str:sub(1, keep) .. "..." .. str:sub(#str - keep + 1)
end

this.apply_template = function(template, vars)
    return (template:gsub("%%(.)", function(key)
        if key == "%" then
            return "%"
        end
        local value = vars[key]
        if value == nil then
            return "%" .. key
        end
        return tostring(value)
    end))
end

return this
