local mp = require('mp')
local h = require('helpers')
local utils = require('mp.utils')
local fixtures = require('test_fixtures')
local encoder = require('encoder.encoder')
local Timings = require('timings_mgr')

local function option(args, key)
    for i, value in ipairs(args) do
        if value == key then return args[i + 1] end
    end
end

local original_async, original_info = h.subprocess_async, utils.file_info
local jobs, completed = {}, nil
mp.add_periodic_timer = function() return { kill = function() end } end
h.subprocess_async = function(args, callback)
    jobs[#jobs + 1] = { args = args, callback = callback }
end
utils.file_info = function(path)
    if path == '/tmp/clip.mp4' then return { is_file = true } end
    return original_info(path)
end
local cfg = fixtures.make_config({ video_encoder = 'nvenc', use_ffmpeg = true, filename_template = 'clip' })
local timings = Timings:new({ start = 1, ['end'] = 2 })
local instance = encoder.new().init(cfg, timings)
instance.create_clip('video', function(path) completed = path end)
assert(#jobs == 1)
assert(jobs[1].args[#jobs[1].args] == '/tmp/clip-2.mp4')
local original_path = mp.get_property('path')
mp.set_property('path', '/tmp/changed.mkv')
timings.start, timings['end'] = 10, 20
cfg.video_encoder, cfg.use_ffmpeg, cfg.video_height = 'cpu', false, 1080
jobs[1].callback(true, { status = 1 }, nil)
assert(#jobs == 2)
assert(option(jobs[2].args, '-i') == original_path)
assert(option(jobs[2].args, '-ss') == '1.000')
assert(option(jobs[2].args, '-c:v') == 'libx264')
assert(option(jobs[2].args, '-vf'):find('scale=-2:480', 1, true))
assert(jobs[2].args[#jobs[2].args] == '/tmp/clip-2.mp4')
jobs[2].callback(true, { status = 0 }, nil)
assert(completed == '/tmp/clip-2.mp4')
assert(cfg.video_encoder == 'cpu' and cfg.use_ffmpeg == false)
mp.set_property('path', original_path)
h.subprocess_async, utils.file_info = original_async, original_info

-- Unsupported FFmpeg options stop before spawning an encoder.
for _, settings in ipairs({ { hdr_to_sdr = true }, { sid = '1' } }) do
    jobs = {}
    h.subprocess_async = function() jobs[#jobs + 1] = true end
    cfg = fixtures.make_config({ use_ffmpeg = true, hdr_to_sdr = settings.hdr_to_sdr or false })
    instance = encoder.new().init(cfg, Timings:new({ start = 1, ['end'] = 2 }))
    fixtures.with_properties(function() instance.create_clip('video') end, { sid = settings.sid or 'no' })
    assert(#jobs == 0)
end
h.subprocess_async = original_async

-- Container compatibility applies to video without changing audio-only exports.
for _, format in ipairs({ 'aac', 'mp3' }) do
    cfg = fixtures.make_config({ video_format = 'vp9', audio_format = format })
    local ff = require('encoder.ffmpeg').new(cfg, timings)
    assert(option(ff.mkargs_video('/tmp/out.webm'), '-c:a') == 'libopus')
    assert(option(ff.mkargs_audio('/tmp/out.audio'), '-c:a') == cfg.audio_codec)
    local mv = require('encoder.mpv').new(cfg, timings)
    assert(table.concat(mv.mkargs_video('/tmp/out.webm'), ' '):find('--oac=libopus', 1, true))
end

local platform = require('platform')
local old_set, old_copy = mp.set_property, platform.clipboard.copy
local copies = 0
mp.set_property = function() return nil, 'property unavailable' end
platform.clipboard.copy = function() copies = copies + 1; return { status = 0 } end
platform.copy_or_open_url('https://example.com/clip')
assert(copies == 1)
mp.set_property = function() return true end
platform.copy_or_open_url('https://example.com/clip')
assert(copies == 1)
mp.set_property, platform.clipboard.copy = old_set, old_copy

-- Closed-menu script messages must never draw an overlay.
local messages, events, draws, bindings, rendered = {}, {}, 0, {}, ''
mp.create_osd_overlay = function()
    return { update = function(self) draws = draws + 1; rendered = self.data end, remove = function() end }
end
mp.register_script_message = function(name, fn) messages[name] = fn end
mp.register_event = function(name, fn) events[name] = fn end
mp.add_key_binding = function() end
mp.add_forced_key_binding = function(key, name, fn) bindings[name] = fn end
mp.remove_key_binding = function() end
mp.get_property_number = function(name) return tonumber(mp.get_property(name)) end
require('videoclip')
events['file-loaded']()
messages['videoclip-set-start']()
messages['videoclip-set-end']()
messages['videoclip-reset']()
assert(draws == 0)
messages['videoclip-menu-open']()
assert(draws == 1)
messages['videoclip-reset']()
assert(draws == 2)
assert(rendered:find('Press s to set the start', 1, true))
messages['videoclip-set-start']('12.5')
messages['videoclip-set-end']('20')
assert(rendered:find('00:12.500', 1, true) and rendered:find('7.500 seconds', 1, true))
bindings['videoclip-main-p']()
assert(rendered:find('Resolution', 1, true))
assert(not rendered:find('NVENC tune', 1, true))
bindings['videoclip-pref-N']()
assert(rendered:find('GPU (Auto)', 1, true))
assert(not rendered:find('NVENC tune', 1, true))
bindings['videoclip-pref-N']()
assert(rendered:find('CPU', 1, true) and not rendered:find('GPU (Auto)', 1, true))
bindings['videoclip-pref-N']()
assert(rendered:find('GPU (Auto)', 1, true))
bindings['videoclip-pref-C']()
assert(not rendered:find('Resolution', 1, true))
assert(not rendered:find('Quality', 1, true))
assert(rendered:find('Save', 1, true) and rendered:find('Back', 1, true))
-- Hidden controls cannot mutate settings for another mode or page.
local copy_view = rendered
bindings['videoclip-pref-r']()
bindings['videoclip-pref-N']()
assert(rendered == copy_view)
bindings['videoclip-pref-C']()
assert(rendered:find('480p', 1, true))
bindings['videoclip-pref-2']()
assert(rendered:find('Audio format', 1, true))
assert(not rendered:find('Resolution', 1, true))
bindings['videoclip-pref-3']()
assert(rendered:find('Folders', 1, true))
assert(rendered:find('[3 Upload]', 1, true))
assert(not rendered:find('Mode', 1, true))
assert(rendered:find('\\p1', 1, true))
assert(rendered:find('\\pos(', 1, true))
-- Opening the main menu through a message removes the preferences context.
messages['videoclip-menu-open']()
local main_view = rendered
bindings['videoclip-pref-C']()
assert(rendered == main_view)
-- Invalid export keeps the controls available to correct the selection.
messages['videoclip-reset']()
bindings['videoclip-main-c']()
bindings['videoclip-main-p']()
assert(rendered:find('Preferences', 1, true))
messages['videoclip-set-end']('1e999')
messages['videoclip-menu-open']()
assert(not rendered:find('inf', 1, true))
print('Regression tests passed.')
