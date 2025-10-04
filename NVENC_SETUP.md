# NVENC GPU Acceleration Setup

This videoclip configuration now uses **NVIDIA NVENC** hardware acceleration for fast, high-quality video encoding with small file sizes.

## What Changed

### 1. Video Codec

- **Changed from**: `libx264` (CPU encoding)
- **Changed to**: `h264_nvenc` (NVIDIA GPU encoding)
- **Benefits**: 5-10x faster encoding with minimal quality loss

### 2. Optimized Settings for Quality + Small Size

#### Video Quality (CRF)

- **Set to**: `20` (was `23`)
- **Range**: 15-25 recommended for NVENC
- Lower = better quality but larger file
- Higher = smaller file but lower quality

#### Preset

- **Set to**: `p5` (was `faster`)
- **NVENC Presets**:
  - `p1` = Fastest encoding, lower quality
  - `p4` = Balanced
  - `p5` = Good quality (recommended)
  - `p6` = Better quality, slower
  - `p7` = Best quality, slowest

#### Bitrate

- **Set to**: `2M` (was `1M`)
- Increased slightly for better quality with NVENC
- Adjust based on your needs: `1M`, `2M`, `3M`, etc.

### 3. NVENC-Specific Optimizations

The encoder now includes advanced NVENC features for better compression:

- **Variable Bitrate (VBR)**: Allocates more bits to complex scenes
- **Spatial AQ**: Improves quality in detailed areas
- **Temporal AQ**: Improves quality across time/motion
- **Lookahead (32 frames)**: Better encoding decisions
- **B-frame optimization**: Smaller file sizes
- **Multipass encoding (qres)**: Better quality at target bitrate

## Requirements

### Hardware

- NVIDIA GPU with NVENC support:
  - GTX 600 series or newer
  - RTX series (recommended)
  - Quadro series

### Software

- **FFmpeg with NVENC support** must be installed
- Check if NVENC is available:
  ```powershell
  ffmpeg -codecs | Select-String nvenc
  ```
  You should see `h264_nvenc` listed.

### Installing FFmpeg with NVENC (Windows)

1. **Download FFmpeg** with NVENC support:

   - Visit: https://www.gyan.dev/ffmpeg/builds/
   - Download: `ffmpeg-git-full.7z`

2. **Extract and Add to PATH**:

   ```powershell
   # Extract to C:\ffmpeg
   # Add C:\ffmpeg\bin to your PATH
   ```

3. **Verify NVENC**:
   ```powershell
   ffmpeg -codecs | Select-String nvenc
   ```

## Configuration Options

Edit `videoclip.conf` or the script to customize:

```lua
-- Video quality (CRF): 15-25 for NVENC
video_quality = 20

-- Preset: p1 (fast) to p7 (slow/best)
preset = 'p5'

-- Bitrate: Adjust for quality/size balance
video_bitrate = '2M'

-- Format: Keep as mp4 for NVENC
video_format = 'mp4'

-- Resolution: -2 = auto maintain aspect ratio
video_height = 480  -- 480p, 720p, 1080p, etc.
video_width = -2    -- auto
```

## Quality vs Size Comparison

### High Quality, Medium Size

```lua
video_quality = 18
preset = 'p6'
video_bitrate = '3M'
```

### Balanced (Default)

```lua
video_quality = 20
preset = 'p5'
video_bitrate = '2M'
```

### Smaller Size, Good Quality

```lua
video_quality = 23
preset = 'p4'
video_bitrate = '1.5M'
```

### Very Small Size

```lua
video_quality = 26
preset = 'p4'
video_bitrate = '1M'
```

## Fallback to CPU Encoding

If NVENC is not available or you want to use CPU encoding:

1. Change `video_format` to use CPU codec in `videoclip.lua`:

   ```lua
   config.video_codec = 'libx264'  -- Instead of h264_nvenc
   config.preset = 'faster'         -- Use CPU presets
   ```

2. CPU presets: `ultrafast`, `superfast`, `veryfast`, `faster`, `fast`, `medium`, `slow`, `slower`, `veryslow`

## Usage

Press `c` in mpv to open the videoclip menu, then:

- `s` = Set start time
- `e` = Set end time
- `c` = Create video clip (now uses NVENC!)
- `C` = Create 1080p clip
- `a` = Create audio clip
- `p` = Open preferences

## Troubleshooting

### "Unknown encoder 'h264_nvenc'" Error

**Solution**: Your FFmpeg doesn't support NVENC. Install FFmpeg with NVENC support (see Installation section above).

### Poor Quality Output

**Try**:

1. Lower CRF value: `video_quality = 18`
2. Higher bitrate: `video_bitrate = '3M'`
3. Better preset: `preset = 'p6'`

### File Size Too Large

**Try**:

1. Higher CRF value: `video_quality = 23`
2. Lower bitrate: `video_bitrate = '1.5M'`
3. Faster preset: `preset = 'p4'`

### Encoding Too Slow

**Try**:

1. Faster preset: `preset = 'p3'` or `p4`
2. GPU might be under heavy load from other applications

## Performance Expectations

With NVENC enabled:

- **Encoding Speed**: 3-10x realtime (depends on GPU)
- **GPU Usage**: 20-40% on modern GPUs
- **CPU Usage**: Minimal (5-10%)
- **Quality**: Near-identical to libx264 medium preset
- **File Size**: Comparable to libx264 with proper settings

## Additional Tips

1. **Monitor GPU Usage**: Use GPU-Z or Task Manager to confirm NVENC is active
2. **Test Settings**: Try different presets/quality values to find your sweet spot
3. **Resolution Matters**: Higher resolutions benefit more from NVENC speed
4. **Audio Quality**: Keep at `32k` for opus (good quality, small size)

## Questions?

- NVENC Documentation: https://docs.nvidia.com/video-technologies/
- FFmpeg NVENC Guide: https://trac.ffmpeg.org/wiki/HWAccelIntro
