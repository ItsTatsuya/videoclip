--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder provides interface for creating audio/video clips.
]]

local mp = require('mp')
local h = require('helpers')
local utils = require('mp.utils')
local this = {}

this.busy = false
this.alive = nil
this.player = 'mpv'

local function opt(name, value)
    if value == nil then
        return name
    end
    return name .. tostring(value)
end

local function get_cfg(overrides, key)
    if overrides and overrides[key] ~= nil then
        return overrides[key]
    end
    return this.config[key]
end

local function is_hdr()
    local gamma = mp.get_property("video-params/gamma") or ""
    return gamma == "pq" or gamma == "hlg" or gamma == "v-log" or gamma == "s-log1" or gamma == "s-log2"
end

local function should_tonemap(overrides)
    local mode = get_cfg(overrides, 'tonemap')
    if mode == 'no' then
        return false
    end
    if mode == 'hable' then
        return true
    end
    return is_hdr()
end

local function video_codec_for(overrides)
    local format = this.config.video_format
    local encoder = get_cfg(overrides, 'video_encoder')
    if format == 'mp4' then
        if encoder == 'nvenc' then
            return 'h264_nvenc'
        end
        return 'libx264'
    elseif format == 'vp9' then
        return 'libvpx-vp9'
    end
    return 'libvpx'
end

local function video_audio_codec()
    if this.config.video_format == 'mp4' then
        return 'aac'
    end
    return 'libopus'
end

local function audio_only_codec()
    if this.config.audio_format == 'aac' then
        return 'aac'
    end
    if this.config.audio_format == 'mp3' then
        return 'libmp3lame'
    end
    return 'libopus'
end

local function audio_bitrate_for(codec)
    local br = this.config.audio_bitrate
    local n = tonumber((br or ""):match("%d+")) or 32
    if (codec == 'aac' or codec == 'libmp3lame') and n < 96 then
        return '128k'
    end
    return br
end

local function copy_video_extension()
    local filename = mp.get_property("filename") or ""
    local ext = filename:match("(%.[%w]+)$")
    if ext then
        local lower = ext:lower()
        if lower == ".mp4" or lower == ".mkv" or lower == ".webm" or lower == ".mov" or lower == ".avi" then
            return lower
        end
    end
    return ".mkv"
end

local function copy_audio_extension()
    local codec = mp.get_property("audio-codec-name") or ""
    if codec == "aac" then
        return ".m4a"
    elseif codec == "opus" then
        return ".opus"
    elseif codec == "mp3" then
        return ".mp3"
    elseif codec == "flac" then
        return ".flac"
    end
    return ".mka"
end

local function clean_filename(filename)
    filename = h.remove_extension(filename)
    if this.config.clean_filename then
        filename = h.remove_text_in_brackets(filename)
        filename = h.remove_special_characters(filename)
        filename = h.strip(filename)
    end
    return filename
end

local function construct_output_filename_noext()
    local filename = mp.get_property("filename") or "clip"
    local title = mp.get_property("media-title") or filename
    local date = os.date("*t")

    if title == filename then
        filename = clean_filename(filename)
        title = filename
    else
        filename = clean_filename(filename)
        title = h.clean_forbidden_characters(title)
    end

    local built = h.apply_template(this.config.filename_template, {
        n = h.truncate_utf8_bytes(filename, 200),
        t = h.truncate_utf8_bytes(title, 200),
        s = h.human_readable_time(this.timings['start']),
        e = h.human_readable_time(this.timings['end']),
        d = h.human_readable_time(this.timings['end'] - this.timings['start']),
        Y = date.year,
        M = h.two_digit(date.month),
        D = h.two_digit(date.day),
        H = h.two_digit(date.hour),
        I = h.two_digit(h.twelve_hour(date.hour)['hour']),
        P = h.twelve_hour(date.hour)['sign'],
        N = h.two_digit(date.min),
        S = h.two_digit(date.sec),
    })

    return h.sanitize_filename(built)
end

function this.get_ext_subs_paths()
    local track_list = mp.get_property_native('track-list') or {}
    local external_subs_list = {}
    for _, track in pairs(track_list) do
        if track.type == 'sub' and track.external == true then
            external_subs_list[track.id] = track['external-filename']
        end
    end
    return external_subs_list
end

function this.append_embed_subs_args(args)
    local ext_subs_paths = this.get_ext_subs_paths()
    for _, ext_subs_path in pairs(ext_subs_paths) do
        table.insert(args, '--sub-files-append=' .. ext_subs_path)
    end
    return args
end

this.mk_out_path_video = function(clip_filename_noext, overrides)
    local ext
    if get_cfg(overrides, 'copy_streams') then
        ext = copy_video_extension()
    else
        ext = this.config.video_extension
    end
    return utils.join_path(h.expand_path(this.config.video_folder_path), clip_filename_noext .. ext)
end

this.mk_out_path_audio = function(clip_filename_noext, overrides)
    local ext
    if get_cfg(overrides, 'copy_streams') then
        ext = copy_audio_extension()
    else
        ext = this.config.audio_extension
    end
    return utils.join_path(h.expand_path(this.config.audio_folder_path), clip_filename_noext .. ext)
end

local function append_video_codec_opts(args, overrides)
    local codec = video_codec_for(overrides)
    if codec == 'h264_nvenc' then
        -- Safer NVENC defaults: CQ VBR without card-specific AQ / multipass flags.
        table.insert(args, '--ovcopts-add=rc=vbr')
        table.insert(args, opt('--ovcopts-add=cq=', get_cfg(overrides, 'video_quality')))
        table.insert(args, '--ovcopts-add=b=0')
        table.insert(args, opt('--ovcopts-add=preset=', get_cfg(overrides, 'nvenc_preset')))
        table.insert(args, opt('--ovcopts-add=tune=', get_cfg(overrides, 'nvenc_tune')))
    elseif codec == 'libx264' then
        table.insert(args, opt('--ovcopts-add=crf=', get_cfg(overrides, 'video_quality')))
        table.insert(args, opt('--ovcopts-add=preset=', get_cfg(overrides, 'preset')))
    else
        -- libvpx / vp9: constrained quality (CRF + b=0). x264 presets do not apply.
        table.insert(args, opt('--ovcopts-add=crf=', get_cfg(overrides, 'video_quality')))
        table.insert(args, '--ovcopts-add=b=0')
    end
end

local function append_audio_codec_opts(args, codec)
    if codec == 'libopus' then
        table.insert(args, '--oacopts-add=vbr=on')
        table.insert(args, '--oacopts-add=application=voip')
        table.insert(args, '--oacopts-add=compression_level=10')
    end
    table.insert(args, opt('--oacopts-add=b=', audio_bitrate_for(codec)))
end

local function source_path()
    return h.absolute_media_path(mp.get_property('path'))
end

local function prop_or_nil(name)
    local value = mp.get_property(name)
    if value == nil or value == "" then
        return nil
    end
    return value
end

local function append_common_input_args(args)
    local path = source_path()
    if path then
        table.insert(args, path)
    end
    table.insert(args, '--loop-file=no')
    table.insert(args, '--keep-open=no')
    table.insert(args, '--no-ocopy-metadata')
    table.insert(args, opt('--start=', h.format_timestamp(this.timings['start'])))
    table.insert(args, opt('--end=', h.format_timestamp(this.timings['end'])))
    local ytdl_format = prop_or_nil("ytdl-format")
    if ytdl_format then
        table.insert(args, '--ytdl-format=' .. ytdl_format)
    end
    local ytdl_raw = prop_or_nil("ytdl-raw-options")
    if ytdl_raw then
        table.insert(args, '--ytdl-raw-options=' .. ytdl_raw)
    end
end

local function append_scale(args, overrides)
    local width = get_cfg(overrides, 'video_width')
    local height = get_cfg(overrides, 'video_height')
    if width == -2 and height == -2 then
        return
    end
    table.insert(args, string.format('--vf-add=scale=%s:%s', width, height))
end

this.mkargs_video = function(out_clip_path, overrides)
    local copy = get_cfg(overrides, 'copy_streams')
    local args = { this.player }
    append_common_input_args(args)

    if copy then
        table.insert(args, '--ovc=copy')
        table.insert(args, '--oac=copy')
        table.insert(args, '--no-sub')
        table.insert(args, opt('--o=', out_clip_path))
        return args
    end

    local oac = video_audio_codec()
    table.insert(args, '--hr-seek=yes')
    table.insert(args, '--no-sub')
    table.insert(args, '--audio-channels=2')
    table.insert(args, '--sub-font-provider=auto')
    table.insert(args, '--embeddedfonts=yes')
    table.insert(args, opt('--sub-font=', this.config.sub_font))
    table.insert(args, opt('--ovc=', video_codec_for(overrides)))
    table.insert(args, opt('--oac=', oac))
    table.insert(args, opt('--aid=', mp.get_property("aid") or "no"))
    table.insert(args, opt('--mute=', mp.get_property("mute") or "no"))
    table.insert(args, opt('--volume=', mp.get_property("volume") or "100"))
    table.insert(args, opt('--sid=', mp.get_property("sid") or "no"))
    table.insert(args, opt('--secondary-sid=', mp.get_property("secondary-sid") or "no"))
    table.insert(args, opt('--sub-delay=', mp.get_property("sub-delay") or "0"))
    table.insert(args, opt('--sub-visibility=', mp.get_property("sub-visibility") or "yes"))
    table.insert(args, opt('--secondary-sub-visibility=', mp.get_property("secondary-sub-visibility") or "no"))
    table.insert(args, opt('--sub-back-color=', mp.get_property("sub-back-color") or "00/00/00/00"))
    table.insert(args, opt('--o=', out_clip_path))

    if should_tonemap(overrides) then
        table.insert(args, '--vf-add=zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p')
    else
        table.insert(args, '--vf-add=format=yuv420p')
    end

    append_scale(args, overrides)
    append_video_codec_opts(args, overrides)
    append_audio_codec_opts(args, oac)

    if this.config.video_extension == '.mp4' then
        table.insert(args, '--ovcopts-add=movflags=+faststart')
    end

    local fps = get_cfg(overrides, 'video_fps')
    if fps and fps ~= 'auto' then
        table.insert(args, opt('--vf-add=fps=', fps))
    end

    if mp.get_property("sub-border-style", nil) ~= nil then
        table.insert(args, opt('--sub-border-style=', mp.get_property("sub-border-style")))
    end

    this.append_embed_subs_args(args)
    return args
end

this.mkargs_audio = function(out_clip_path, overrides)
    local copy = get_cfg(overrides, 'copy_streams')
    local args = { this.player }
    append_common_input_args(args)
    table.insert(args, '--video=no')
    table.insert(args, '--no-sub')

    if copy then
        table.insert(args, '--oac=copy')
        table.insert(args, opt('--o=', out_clip_path))
        return args
    end

    local oac = audio_only_codec()
    table.insert(args, '--hr-seek=yes')
    table.insert(args, '--audio-channels=2')
    table.insert(args, opt('--oac=', oac))
    table.insert(args, opt('--volume=', mp.get_property("volume") or "100"))
    table.insert(args, opt('--aid=', mp.get_property("aid") or "no"))
    table.insert(args, opt('--mute=', mp.get_property("mute") or "no"))
    append_audio_codec_opts(args, oac)
    table.insert(args, opt('--o=', out_clip_path))
    return args
end

local function stop_progress()
    this.busy = false
    if this.progress_timer then
        this.progress_timer:kill()
        this.progress_timer = nil
    end
end

local function start_progress(output_file_path)
    this.busy = true
    this.encode_started_at = os.time()
    if this.progress_timer then
        this.progress_timer:kill()
    end
    local function tick()
        local elapsed = os.time() - this.encode_started_at
        h.notify(string.format("Encoding… %ds  %s", elapsed, output_file_path), "info", 2)
    end
    tick()
    this.progress_timer = mp.add_periodic_timer(1, tick)
end

local function fail_message(output_file_path, ret)
    local detail = h.first_line(ret and (ret.stderr or ret.stdout) or "", 160)
    if detail ~= "" then
        return string.format("Couldn't create clip %s. %s", output_file_path, detail)
    end
    return string.format("Couldn't create clip %s.", output_file_path)
end

local function encode_failed(ret)
    if not ret then
        return true
    end
    if ret.status ~= 0 then
        return true
    end
    local stdout = ret.stdout or ""
    local stderr = ret.stderr or ""
    return stdout:match("could not open") ~= nil or stderr:match("could not open") ~= nil
end

local function run_encode(clip_type, output_file_path, overrides, on_complete, tried_cpu_fallback)
    local args
    if clip_type == 'video' then
        args = this.mkargs_video(output_file_path, overrides)
    else
        args = this.mkargs_audio(output_file_path, overrides)
    end

    print("The following args will be executed:", table.concat(h.quote_if_necessary(args), " "))

    local process_result = function(_, ret, _)
        if encode_failed(ret)
                and clip_type == 'video'
                and video_codec_for(overrides) == 'h264_nvenc'
                and not tried_cpu_fallback then
            h.notify("NVENC failed, retrying with CPU…", "warn", 3)
            mp.msg.error(ret and (ret.stderr or ret.stdout) or "nvenc failed")
            local cpu_overrides = {}
            for key, value in pairs(overrides or {}) do
                cpu_overrides[key] = value
            end
            cpu_overrides.video_encoder = 'cpu'
            run_encode(clip_type, output_file_path, cpu_overrides, on_complete, true)
            return
        end

        stop_progress()

        if encode_failed(ret) then
            if ret and ret.stderr and ret.stderr ~= "" then
                mp.msg.error(ret.stderr)
            end
            if ret and ret.stdout and ret.stdout ~= "" then
                mp.msg.error(ret.stdout)
            end
            h.notify_error(fail_message(output_file_path, ret), "error", 6)
            return
        end

        h.notify(string.format("Clip saved to %s.", output_file_path), "info", 2)
        if on_complete then
            on_complete(output_file_path)
        end
    end

    h.subprocess_async(args, process_result)
end

this.create_clip = function(clip_type, on_complete, overrides)
    if clip_type == nil then
        return
    end

    if this.busy then
        h.notify_error("Already encoding.", "warn", 2)
        return
    end

    if this.alive == false then
        h.notify_error("mpv encoder is not available.", "error", 4)
        return
    end

    if not source_path() then
        h.notify_error("No file is loaded.", "warn", 2)
        return
    end

    if not this.timings:validate() then
        h.notify_error("Wrong timings. Aborting.", "warn", 2)
        return
    end

    if clip_type == 'audio' and mp.get_property_native("mute") then
        h.notify_error("Audio is muted. Unmute or create a video clip.", "warn", 3)
        return
    end

    if get_cfg(overrides, 'copy_streams') and clip_type == 'video' and mp.get_property_native("sub-visibility") then
        h.notify("Stream copy cannot burn in subtitles. Subs will be omitted.", "warn", 3)
    end

    local clip_filename_noext = construct_output_filename_noext()
    local output_file_path
    if clip_type == 'video' then
        output_file_path = this.mk_out_path_video(clip_filename_noext, overrides)
    else
        output_file_path = this.mk_out_path_audio(clip_filename_noext, overrides)
    end
    output_file_path = h.unique_path(output_file_path)

    local output_dir_path = utils.split_path(output_file_path)
    if not h.ensure_dir(output_dir_path) then
        h.notify_error(string.format("Error: could not create folder %s.", output_dir_path), "error", 5)
        return
    end

    start_progress(output_file_path)
    run_encode(clip_type, output_file_path, overrides, on_complete, false)
end

this.set_encoder_alive = function()
    local binary = mp.get_property("binary_path")
    if binary and binary ~= "" then
        this.alive = true
        this.player = binary
        return
    end

    local args_mpvnet = { 'mpvnet', '--version' }
    local process_result_mpvnet = function(_, ret, _)
        if ret.status ~= 0 then
            this.alive = false
        else
            this.alive = true
            this.player = 'mpvnet'
        end
    end

    local args = { 'mpv', '--version' }
    local process_result = function(_, ret, _)
        if ret.status ~= 0 or not ret.stdout or string.match(ret.stdout, "mpv") == nil then
            h.subprocess_async(args_mpvnet, process_result_mpvnet)
        else
            this.alive = true
            this.player = 'mpv'
        end
    end
    h.subprocess_async(args, process_result)
end

this.init = function(config, timings_mgr)
    this.config = config
    this.timings = timings_mgr
    this.set_encoder_alive()
end

return this
