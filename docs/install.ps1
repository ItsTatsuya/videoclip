# Videoclip installer for Windows PowerShell 5.1+ / PowerShell 7.
# Run again to update. Preferences remain outside the plugin directory.
param([string]$ConfigDir)

& {
    $ErrorActionPreference = 'Stop'
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
