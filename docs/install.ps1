# Videoclip installer for Windows PowerShell 5.1+ / PowerShell 7.
# Run again to update. Preferences remain outside the plugin directory.
# -SkipFfmpeg is intended for offline installer tests or externally managed dependencies.
param(
    [string]$ConfigDir,
    [switch]$SkipFfmpeg
)

& {
    $ErrorActionPreference = 'Stop'

    $ffmpegPackageId = 'Gyan.FFmpeg.Shared'
    $ffmpegArchiveUri = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'

    function Test-FfmpegExecutable {
        param([string]$Path)

        if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $false
        }
        try {
            $output = & $Path '-version' 2>&1
            return ($LASTEXITCODE -eq 0 -and (($output -join "`n") -match '(?im)^ffmpeg version'))
        } catch {
            return $false
        }
    }

    function Normalize-InstallerPath {
        param([string]$Path)

        $normalized = $Path.Trim().Trim('"')
        try { $normalized = [IO.Path]::GetFullPath($normalized) } catch { }
        while ($normalized.Length -gt 3 -and
                ($normalized.EndsWith([char]92) -or $normalized.EndsWith([char]47))) {
            $normalized = $normalized.Substring(0, $normalized.Length - 1)
        }
        return $normalized
    }

    function Test-SameInstallerPath {
        param(
            [string]$Left,
            [string]$Right
        )
        if (-not $Left -or -not $Right) { return $false }
        return (Normalize-InstallerPath $Left) -ieq (Normalize-InstallerPath $Right)
    }

    function Get-FfmpegExecutable {
        param([string]$AdditionalRoot)

        $candidates = @()
        foreach ($commandName in @('ffmpeg.exe', 'ffmpeg')) {
            $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue
            if ($command) { $candidates += $command.Path }
        }

        $knownPaths = @()
        if ($env:ProgramData) {
            $knownPaths += Join-Path $env:ProgramData 'chocolatey\bin\ffmpeg.exe'
        }
        if ($env:USERPROFILE) {
            $knownPaths += Join-Path $env:USERPROFILE 'scoop\shims\ffmpeg.exe'
        }
        if ($env:LOCALAPPDATA) {
            $knownPaths += Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe'
        }
        if ($env:ProgramFiles) {
            $knownPaths += Join-Path $env:ProgramFiles 'ffmpeg\bin\ffmpeg.exe'
            $knownPaths += Join-Path $env:ProgramFiles 'FFmpeg\bin\ffmpeg.exe'
        }
        if (${env:ProgramFiles(x86)}) {
            $knownPaths += Join-Path ${env:ProgramFiles(x86)} 'ffmpeg\bin\ffmpeg.exe'
            $knownPaths += Join-Path ${env:ProgramFiles(x86)} 'FFmpeg\bin\ffmpeg.exe'
        }
        if ($AdditionalRoot) { $knownPaths += $AdditionalRoot }

        foreach ($knownPath in $knownPaths) {
            if (Test-Path -LiteralPath $knownPath -PathType Leaf) {
                $candidates += $knownPath
            } elseif (Test-Path -LiteralPath $knownPath -PathType Container) {
                $candidates += Get-ChildItem -LiteralPath $knownPath -Filter 'ffmpeg.exe' -File -Recurse -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName
            }
        }

        # A portable winget package may not update the current process PATH.
        if ($env:LOCALAPPDATA) {
            $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
            if (Test-Path -LiteralPath $wingetPackages -PathType Container) {
                $candidates += Get-ChildItem -LiteralPath $wingetPackages -Filter 'ffmpeg.exe' -File -Recurse -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName
            }
        }

        foreach ($candidate in $candidates) {
            if (Test-FfmpegExecutable $candidate) { return $candidate }
        }
        return $null
    }

    function Add-FfmpegToUserPath {
        param([string]$Directory)

        if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
            throw "FFmpeg directory does not exist: $Directory"
        }
        $Directory = Normalize-InstallerPath $Directory
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $userEntries = if ($userPath) { $userPath -split ';' } else { @() }
        $inUserPath = $false
        foreach ($entry in $userEntries) {
            if (Test-SameInstallerPath $entry $Directory) {
                $inUserPath = $true
                break
            }
        }
        if (-not $inUserPath) {
            $newUserPath = if ($userPath) { "$userPath;$Directory" } else { $Directory }
            [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
            Write-Host "Added FFmpeg to the user PATH: $Directory"
        }

        $processEntries = if ($env:Path) { $env:Path -split ';' } else { @() }
        $inProcessPath = $false
        foreach ($entry in $processEntries) {
            if (Test-SameInstallerPath $entry $Directory) {
                $inProcessPath = $true
                break
            }
        }
        if (-not $inProcessPath) {
            $env:Path = if ($env:Path) { "$Directory;$env:Path" } else { $Directory }
        }
    }

    function Refresh-ProcessPath {
        $values = @(
            [Environment]::GetEnvironmentVariable('Path', 'Process'),
            [Environment]::GetEnvironmentVariable('Path', 'User'),
            [Environment]::GetEnvironmentVariable('Path', 'Machine')
        )
        $entries = @()
        foreach ($value in $values) {
            if ($value) { $entries += $value -split ';' }
        }
        $env:Path = ($entries | Where-Object { $_ }) -join ';'
    }

    function Install-FfmpegFromArchive {
        param([string]$InstallRoot)

        $temporary = Join-Path ([IO.Path]::GetTempPath()) ('videoclip-ffmpeg-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $temporary | Out-Null
            $zip = Join-Path $temporary 'ffmpeg.zip'
            Write-Host "Downloading FFmpeg from $ffmpegArchiveUri..."
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $ffmpegArchiveUri -OutFile $zip
            New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
            Expand-Archive -LiteralPath $zip -DestinationPath $InstallRoot -Force
        } finally {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        return Get-FfmpegExecutable -AdditionalRoot $InstallRoot
    }

    function Ensure-Ffmpeg {
        Refresh-ProcessPath
        $ffmpeg = Get-FfmpegExecutable
        if (-not $ffmpeg) {
            $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
            if ($winget) {
                Write-Host 'FFmpeg was not found. Installing it with winget...'
                try {
                    & $winget.Path install --id $ffmpegPackageId --exact --source winget `
                        --accept-source-agreements --accept-package-agreements --disable-interactivity
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "winget exited with code $LASTEXITCODE. Trying the portable fallback."
                    }
                } catch {
                    Write-Warning "winget could not install FFmpeg: $($_.Exception.Message)"
                }
                Refresh-ProcessPath
                $ffmpeg = Get-FfmpegExecutable
            }
        }

        if (-not $ffmpeg) {
            if (-not $env:LOCALAPPDATA) {
                throw 'FFmpeg is required, but LOCALAPPDATA is unavailable for the portable fallback.'
            }
            $installRoot = Join-Path $env:LOCALAPPDATA 'videoclip\ffmpeg'
            try {
                $ffmpeg = Install-FfmpegFromArchive -InstallRoot $installRoot
            } catch {
                throw "FFmpeg is required for stream copy and the FFmpeg backend, but installation failed. Install FFmpeg manually and put it on PATH. $($_.Exception.Message)"
            }
        }

        if (-not $ffmpeg) {
            throw 'FFmpeg installation finished without a usable ffmpeg.exe.'
        }
        Add-FfmpegToUserPath -Directory (Split-Path -Parent $ffmpeg)
        if (-not (Test-FfmpegExecutable $ffmpeg)) {
            throw "FFmpeg was found at $ffmpeg but could not be executed."
        }
        Write-Host "FFmpeg is ready: $ffmpeg"
    }

    if (-not $ConfigDir) { $ConfigDir = $env:MPV_HOME }
    if (-not $ConfigDir) {
        $mpvExe = Get-Command mpv.exe -ErrorAction SilentlyContinue
        if (-not $mpvExe) {
            $mpvExe = Get-Process mpv -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($mpvExe -and $mpvExe.Path) {
            $portable = Join-Path (Split-Path -Parent $mpvExe.Path) 'portable_config'
            if (Test-Path -LiteralPath $portable -PathType Container) { $ConfigDir = $portable }
        }
    }
    if (-not $ConfigDir) { $ConfigDir = Join-Path $env:APPDATA 'mpv' }
    $ConfigDir = [IO.Path]::GetFullPath($ConfigDir)
    $scripts = Join-Path $ConfigDir 'scripts'
    $options = Join-Path $ConfigDir 'script-opts'
    $target = Join-Path $scripts 'videoclip'
    if (Test-Path -LiteralPath (Join-Path $target '.git')) {
        throw "This is a Git checkout. Update it with git pull, or move it out of scripts before installing: $target"
    }
    if ((Test-Path -LiteralPath $target) -and
        -not (Test-Path -LiteralPath (Join-Path $target 'main.lua') -PathType Leaf)) {
        throw "The destination contains an unrecognized install. Move it aside first: $target"
    }
    # Do not follow a junction/symlink when moving an existing installation.
    if ((Test-Path -LiteralPath $target) -and
        ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "The plugin directory is a link. Use its real configuration directory: $target"
    }
    if (-not $SkipFfmpeg) { Ensure-Ffmpeg }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('videoclip-' + [guid]::NewGuid().ToString('N'))
    $backup = $null
    $stage = $null
    try {
        New-Item -ItemType Directory -Path $temporary | Out-Null
        $zip = Join-Path $temporary 'videoclip.zip'
        Write-Host 'Downloading Videoclip...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/ItsTatsuya/videoclip/archive/refs/heads/master.zip' -OutFile $zip
        Expand-Archive -LiteralPath $zip -DestinationPath $temporary
        $source = Join-Path $temporary 'videoclip-master'
        foreach ($required in @('main.lua', 'videoclip/main.lua', 'videoclip/videoclip.lua', 'videoclip/config/default_config.conf')) {
            if (-not (Test-Path -LiteralPath (Join-Path $source $required) -PathType Leaf)) {
                throw 'The download is incomplete. Your installed plugin has not been changed.'
            }
        }
        New-Item -ItemType Directory -Force -Path $scripts, $options | Out-Null
        # Stage on the same volume, outside scripts so mpv cannot load it early.
        $stage = Join-Path $ConfigDir ('videoclip-stage-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage | Out-Null
        Copy-Item -LiteralPath (Join-Path $source 'main.lua'), (Join-Path $source 'LICENSE') -Destination $stage
        Copy-Item -LiteralPath (Join-Path $source 'videoclip') -Destination $stage -Recurse
        $configFile = Join-Path $options 'videoclip.conf'
        if (-not (Test-Path -LiteralPath $configFile)) {
            Copy-Item -LiteralPath (Join-Path $source 'videoclip/config/default_config.conf') -Destination $configFile
        }
        if (Test-Path -LiteralPath $target) {
            $backupRoot = Join-Path $ConfigDir 'videoclip-backups'
            New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
            $backup = Join-Path $backupRoot ([guid]::NewGuid().ToString('N'))
            # Both paths are literal children of the chosen configuration directory.
            Move-Item -LiteralPath $target -Destination $backup
        }
        try { Move-Item -LiteralPath $stage -Destination $target }
        catch {
            if ($backup -and -not (Test-Path -LiteralPath $target)) {
                Move-Item -LiteralPath $backup -Destination $target
            }
            throw
        }
        $stage = $null
        Write-Host "Installed: $target"
        Write-Host "Preferences: $configFile"
        if ($backup) { Write-Host "Previous version: $backup" }
        Write-Host 'Restart mpv, open a video, and press c. Press p then s to save preferences.'
    }
    finally {
        # Only remove this invocation's randomly named temporary download directory.
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $resolvedTemp = [IO.Path]::GetFullPath($temporary)
        if ($resolvedTemp.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedTemp) -match '^videoclip-[a-f0-9]{32}$' -and
            (Test-Path -LiteralPath $resolvedTemp)) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
        # Leave a failed staging directory intact for diagnosis; never delete an install.
        if ($stage) { Write-Warning "Unfinished staging directory: $stage" }
    }
}
