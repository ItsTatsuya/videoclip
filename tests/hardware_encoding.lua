-- Run from the project root with Lua. mpv is stubbed; no GPU is required.
package.path = './videoclip/?.lua;' .. package.path
local props = { path = '/tmp/input.mp4', filename = 'input.mp4', ['media-title'] = 'input.mp4',
    platform = 'windows', aid = '1', sid = 'no', mute = 'no', volume = '100',
    ['sub-delay'] = '0', ['sub-visibility'] = 'no', ['secondary-sub-visibility'] = 'no' }
local noop = function() end
local msg = { info = noop, warn = noop, error = noop, debug = noop }
local mp = { msg = msg, get_property_osd = function() return '' end,
    get_property = function(k, default) return props[k] or default or '' end,
    set_property = function(k, v) props[k] = v end,
    get_property_native = function(k)
        if k == 'track-list' then return {} end
        if k == 'current-tracks/audio/codec' then return 'aac' end
        if k == 'mute' or k:find('visibility') then return false end
    end,
    command_native = function(a) if a[1] == 'expand-path' then return a[2] end end,
    add_periodic_timer = function() return { kill = noop } end, osd_message = noop }
package.loaded['mp'] = mp
package.loaded['mp.msg'] = msg
package.loaded['mp.options'] = { read_options = noop }
package.loaded['mp.utils'] = {
    join_path = function(a, b) return a .. '/' .. b end,
    split_path = function(p) return p:match('^(.*[/])([^/]+)$') end,
    file_info = function() return nil end,
    format_json = function(v)
        local parts = {}
        for k, value in pairs(v) do parts[#parts + 1] = tostring(k) .. '=' .. tostring(value) end
        table.sort(parts)
        return table.concat(parts, ',')
    end,
}
package.loaded['platform'] = { default_video_folder = '/tmp', default_audio_folder = '/tmp' }
local fixtures = require('test_fixtures')
local config = require('config.config')
local h = require('helpers')
local function has(args, value) assert(fixtures.contains(args, value), 'Missing ' .. value) end
for _, module in ipairs({ 'config.config', 'encoder.mpv', 'encoder.ffmpeg', 'encoder.encoder' }) do
    require(module).run_tests()
end
for _, vendor in ipairs({ 'nvenc', 'amf', 'qsv' }) do
    for _, use_ffmpeg in ipairs({ false, true }) do
        local cfg = fixtures.make_config({ video_encoder = vendor, use_ffmpeg = use_ffmpeg })
        assert(cfg.video_codec == 'h264_' .. vendor)
        local backend = require(use_ffmpeg and 'encoder.ffmpeg' or 'encoder.mpv').new(cfg, fixtures.make_timings())
        local args = backend.mkargs_video('/tmp/out.mp4')
        has(args, use_ffmpeg and cfg.video_codec or '--ovc=' .. cfg.video_codec)
        assert(not fixtures.contains(args, '-crf'))
        for _, arg in ipairs(args) do assert(not arg:find('ovcopts%-add=crf=')) end
        if vendor == 'amf' then
            has(args, use_ffmpeg and 'cqp' or '--ovcopts-add=rc=cqp')
            has(args, use_ffmpeg and '-qp_p' or '--ovcopts-add=qp_p=23')
        elseif vendor == 'qsv' then
            has(args, use_ffmpeg and '-global_quality' or '--ovcopts-add=global_quality=23')
        end
        if vendor ~= 'nvenc' then
            has(args, use_ffmpeg and 'scale=-2:480,format=nv12' or '--vf-add=format=nv12')
        end
        -- Fail the GPU attempt and verify exactly one CPU retry, preserving preferences.
        local facade = require('encoder.encoder').new()
        facade.init(cfg, fixtures.make_timings(), { check_alive = false })
        facade.is_alive = function() return true end
        h.ensure_dir = function() return true end
        local calls, completed = {}, 0
        h.subprocess_async = function(a, cb) table.insert(calls, { args = a, cb = cb }) end
        facade.create_clip('video', function() completed = completed + 1 end)
        assert(#calls == 1 and facade.is_busy())
        calls[1].cb(true, { status = 1 }, nil)
        assert(#calls == 2)
        has(calls[2].args, use_ffmpeg and 'libx264' or '--ovc=libx264')
        assert(cfg.video_encoder == vendor and cfg.video_codec == 'h264_' .. vendor)
        calls[2].cb(true, { status = 0 }, nil)
        assert(completed == 1 and not facade.is_busy())
    end
    for _, format in ipairs({ 'vp8', 'vp9' }) do
        local cfg = fixtures.make_config({ video_encoder = vendor, video_format = format })
        assert(cfg.video_encoder == 'cpu' and cfg.video_extension == '.webm')
    end
end
print('PASS: existing suites, GPU arguments, format validation and CPU fallback for both backends')
-- Auto detection tries each vendor, caches success, and falls back only after all fail.
for _, use_ffmpeg in ipairs({ false, true }) do
    for success_index = 1, 4 do
        local cfg = fixtures.make_config({ video_encoder = 'gpu', use_ffmpeg = use_ffmpeg })
        local facade = require('encoder.encoder').new()
        facade.init(cfg, fixtures.make_timings(), { check_alive = false })
        facade.is_alive = function() return true end
        local calls, completed = {}, 0
        h.subprocess_async = function(a, cb) calls[#calls + 1] = { args = a, cb = cb } end
        facade.create_clip('video', function() completed = completed + 1 end)
        local codecs = { 'h264_nvenc', 'h264_amf', 'h264_qsv', 'libx264' }
        for i = 1, success_index do
            assert(#calls == i)
            has(calls[i].args, use_ffmpeg and codecs[i] or '--ovc=' .. codecs[i])
            calls[i].cb(true, { status = i == success_index and 0 or 1 }, nil)
        end
        assert(completed == 1 and not facade.is_busy() and cfg.video_encoder == 'gpu')
        calls = {}
        facade.create_clip('video')
        local cached = success_index < 4 and codecs[success_index] or codecs[1]
        has(calls[1].args, use_ffmpeg and cached or '--ovc=' .. cached)
        -- Failure of every attempt must terminate without an endless retry.
        local i = 1
        while calls[i] do
            assert(i <= 4)
            calls[i].cb(true, { status = 1 }, nil)
            i = i + 1
        end
        assert(#calls == 4 and not facade.is_busy())
    end
end
print('PASS: automatic GPU selection, cached detection, CPU fallback and terminal failure')
