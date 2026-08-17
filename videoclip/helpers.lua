--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Various helper functions.
]]

local mp = require('mp')
local utils = require('mp.utils')
local this = {}
local ass_start = mp.get_property_osd("osd-ass-cc/0")

this.unpack = unpack or table.unpack

this.is_empty = function(var)
    return var == nil or var == '' or (type(var) == 'table' and next(var) == nil)
end

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
        args = args
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

this.expand_path = function(str)
    return mp.command_native({ "expand-path", str })
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

--- Split a command string into argv-style tokens, honoring double quotes.
--- Pure: depends only on the input string.
--- Examples:
---    parse_command_args('curl -F file=@x') → { "curl", "-F", "file=@x" }
---    parse_command_args('curl -F "a b"') → { "curl", "-F", "a b" }
---    parse_command_args('') → {}
this.parse_command_args = function(cmd_str)
    local args = {}
    local buffer = ""
    local in_quote = false

    for i = 1, #cmd_str do
        local c = cmd_str:sub(i, i)
        if c == '"' then
            in_quote = not in_quote
        elseif c:match("%s") and not in_quote then
            if not this.is_empty(buffer) then
                table.insert(args, buffer)
                buffer = ""
            end
        else
            buffer = buffer .. c
        end
    end

    if not this.is_empty(buffer) then
        table.insert(args, buffer)
    end

    return args
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

local WINDOWS_RESERVED = {
    CON = true, PRN = true, AUX = true, NUL = true,
    COM1 = true, COM2 = true, COM3 = true, COM4 = true, COM5 = true,
    COM6 = true, COM7 = true, COM8 = true, COM9 = true,
    LPT1 = true, LPT2 = true, LPT3 = true, LPT4 = true, LPT5 = true,
    LPT6 = true, LPT7 = true, LPT8 = true, LPT9 = true,
}

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

this.clean_forbidden_characters = function(title)
    return title:gsub('[<>:"/\\|%?%*]+', '.')
end

this.repr = function(value)
    --- Return a test-friendly string representation of a value.
    if type(value) == 'table' then
        return utils.format_json(value)
    else
        return value
    end
end

this.equal = function(first, last)
    --- Test whether two values are equal.
    return this.repr(first) == this.repr(last)
end

this.assert_equals = function(actual, expected)
    --- Raise an error if actual and expected are not equal.
    if this.equal(actual, expected) == false then
        error(string.format("TEST FAILED: Expected '%s', got '%s'", this.repr(expected), this.repr(actual)))
    end
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

function this.partial(callable, ...)
    local preset = { ... }
    return function(...)
        local args = {}

        for i = 1, #preset do
            args[#args + 1] = preset[i]
        end
        for i = 1, select("#", ...) do
            args[#args + 1] = select(i, ...)
        end

        return callable(this.unpack(args))
    end
end

this.run_tests = function()
    --- Run unit tests for helper functions.
    this.assert_equals(this.is_empty(nil), true)
    this.assert_equals(this.is_empty(''), true)
    this.assert_equals(this.is_empty({}), true)
    this.assert_equals(this.is_empty('x'), false)

    this.assert_equals(this.remove_extension('video.mkv'), 'video')
    this.assert_equals(this.remove_text_in_brackets('a [b] c'), 'a  c')
    this.assert_equals(this.remove_special_characters('a-b_c!'), 'a b c')
    this.assert_equals(this.strip('  abc  '), 'abc')
    this.assert_equals(this.two_digit(7), '07')
    this.assert_equals(this.twelve_hour(13).hour, 1)
    this.assert_equals(this.twelve_hour(13).sign, 'pm')
    this.assert_equals(this.twelve_hour(0).hour, 12)
    this.assert_equals(this.twelve_hour(0).sign, 'am')
    this.assert_equals(this.twelve_hour(12).hour, 12)
    this.assert_equals(this.twelve_hour(12).sign, 'pm')
    this.assert_equals(this.format_timestamp(1.234), '1.234')
    this.assert_equals(this.format_timestamp(1.23456), '1.235')

    this.assert_equals(this.human_readable_time(-1), 'empty')
    this.assert_equals(this.human_readable_time(61.234), '01m01s234ms')
    this.assert_equals(this.clean_forbidden_characters('a:b?c'), 'a.b.c')
    this.assert_equals(this.repr({ a = 1 }), utils.format_json({ a = 1 }))
    this.assert_equals(this.repr({ a = 1 }), '{"a":1}')
    this.assert_equals(this.equal({ a = 1 }, { a = 1 }), true)
    this.assert_equals(this.truncate_utf8_bytes('abcdef', 3), 'abc')

    local function greet(greeting, name)
        return greeting .. ", " .. name
    end

    this.assert_equals(this.partial(greet, "Hello")("Lua"), "Hello, Lua")

    this.assert_equals(this.parse_command_args('curl -F file=@x'), { "curl", "-F", "file=@x" })
    this.assert_equals(this.parse_command_args('curl -F "a b"'), { "curl", "-F", "a b" })
    this.assert_equals(this.parse_command_args(''), {})
    this.assert_equals(this.parse_command_args('  a  b  '), { "a", "b" })
end

return this
