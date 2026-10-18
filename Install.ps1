[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$GamePath,
    [switch]$SkipHotkey,
    [switch]$ForceHotkey,
    [switch]$NonInteractive
)

function Get-ScoutSteamRoots {
    $roots = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        $properties = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($properties.SteamPath) { $roots += $properties.SteamPath }
        if ($properties.InstallPath) { $roots += $properties.InstallPath }
    }
    if (${env:ProgramFiles(x86)}) { $roots += Join-Path ${env:ProgramFiles(x86)} 'Steam' }
    if ($env:ProgramFiles) { $roots += Join-Path $env:ProgramFiles 'Steam' }
    $roots | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
}

function Get-ScoutGameCandidates {
    param([AllowEmptyCollection()][string[]]$SteamRoots = @(Get-ScoutSteamRoots))
    $libraries = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $SteamRoots) {
        [void]$libraries.Add([IO.Path]::GetFullPath($root))
        foreach ($relative in @('steamapps\libraryfolders.vdf', 'config\libraryfolders.vdf')) {
            $libraryFile = Join-Path $root $relative
            if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { continue }
            $vdf = [IO.File]::ReadAllText($libraryFile)
            # Support both current "path" entries and older numbered entries.
            foreach ($match in [regex]::Matches($vdf, '(?im)^\s*"(?:path|\d+)"\s*"((?:\\.|[^"\\])*)"')) {
                $path = $match.Groups[1].Value.Replace('\\', '\')
                if ([IO.Path]::IsPathRooted($path)) { [void]$libraries.Add([IO.Path]::GetFullPath($path)) }
            }
        }
    }
    $found = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($library in $libraries) {
        $manifest = Join-Path $library 'steamapps\appmanifest_3830.acf'
        $directoryName = 'Psychonauts'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            $match = [regex]::Match([IO.File]::ReadAllText($manifest), '"installdir"\s*"([^"\\]+)"')
            if ($match.Success) { $directoryName = $match.Groups[1].Value }
        }
        $candidate = [IO.Path]::GetFullPath((Join-Path $library ('steamapps\common\' + $directoryName)))
        if (Test-Path -LiteralPath (Join-Path $candidate 'Psychonauts.exe') -PathType Leaf) {
            if ($found.Add($candidate)) { $candidate }
        }
    }
}

function Select-ScoutGameFolder {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = [Windows.Forms.FolderBrowserDialog]::new()
    try {
        $dialog.Description = 'Choose the Psychonauts folder containing Psychonauts.exe.'
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
        throw 'Installation cancelled. Nothing was changed.'
    } finally { $dialog.Dispose() }
}

function Install-CollectibleScout {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$GamePath,
        [string]$PackageRoot = $PSScriptRoot,
        [switch]$SkipHotkey,
        [switch]$ForceHotkey,
        [switch]$NonInteractive
    )
    $ErrorActionPreference = 'Stop'
    $utf8 = [Text.UTF8Encoding]::new($false)
    $sourceRoot = Join-Path $PackageRoot 'CollectibleScout'
    $payloadFiles = @('mod.json', 'mod_boot.lua', 'astralathe_lua.lua', 'Scripts\CollectibleScout.lua')
    foreach ($relative in $payloadFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Leaf)) {
            throw 'Extract the entire release ZIP before running Install.cmd.'
        }
    }
    $metadata = [IO.File]::ReadAllText((Join-Path $sourceRoot 'mod.json')) | ConvertFrom-Json
    if ($metadata.id -ne 'com.lorenzo.collectiblescout' -or -not $metadata.version) { throw 'The mod package is not valid.' }
    if (-not $GamePath) {
        $candidates = @(Get-ScoutGameCandidates)
        if ($candidates.Count -eq 1) {
            $GamePath = $candidates[0]
        } elseif ($NonInteractive) {
            throw 'Could not select one Psychonauts install automatically. Supply -GamePath.'
        } else {
            $GamePath = Select-ScoutGameFolder
        }
    }
    $GamePath = [IO.Path]::GetFullPath($GamePath.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'Psychonauts.exe') -PathType Leaf)) {
        throw 'This folder does not contain Psychonauts.exe.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'AstralatheLauncher.exe') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $GamePath 'Astralathe.dll') -PathType Leaf)) {
        throw 'Install Astralathe first: https://gitlab.com/scrunguscrungus/astralathe/-/wikis/Installing%20Astralathe'
    }
    if (Get-Process -Name Psychonauts -ErrorAction SilentlyContinue) { throw 'Close Psychonauts, then run Install.cmd again.' }

    $modResource = Join-Path $GamePath 'ModResource'
    $existing = @()
    if (Test-Path -LiteralPath $modResource -PathType Container) {
        foreach ($folder in Get-ChildItem -LiteralPath $modResource -Directory) {
            $isScout = $folder.Name -in @('Collectible Scout', 'CollectibleScout')
            $existingJson = Join-Path $folder.FullName 'mod.json'
            if (Test-Path -LiteralPath $existingJson -PathType Leaf) {
                try {
                    $existingMetadata = [IO.File]::ReadAllText($existingJson) | ConvertFrom-Json
                    if ($existingMetadata.id -in @($metadata.id, 'com.codex.collectiblescout')) { $isScout = $true }
                } catch {
                    if (-not $isScout) { continue }
                }
            }
            if ($isScout) { $existing += $folder }
        }
    }
    if ($existing.Count -gt 1) { throw 'Multiple Collectible Scout folders were found in ModResource. Keep one install before updating.' }
    $folderName = 'Collectible Scout'
    if ($existing.Count -eq 1) { $folderName = $existing[0].Name }
    $destinationRoot = Join-Path $modResource $folderName
    $hotkeyPath = Join-Path $GamePath 'astralathe_lua.lua'
    if (-not $SkipHotkey -and -not $ForceHotkey -and (Test-Path -LiteralPath $hotkeyPath -PathType Leaf)) {
        $hotkey = [IO.File]::ReadAllText($hotkeyPath)
        if (-not [string]::IsNullOrWhiteSpace($hotkey) -and -not $hotkey.Contains('CollectibleScout') -and -not $WhatIfPreference) {
            if ($NonInteractive) { throw 'F3 is used by another script. Use -SkipHotkey to keep it or -ForceHotkey to replace it with a backup.' }
            $answer = Read-Host 'F3 currently runs another script. Use F3 for Collectible Scout instead (a backup will be saved)? [y/N]'
            if ($answer -notmatch '^(?i:y|yes)$') { $SkipHotkey = $true }
        }
    }

    $plan = [Collections.Generic.List[object]]::new()
    foreach ($relative in $payloadFiles) {
        $plan.Add(@{path = Join-Path $destinationRoot $relative; bytes = [IO.File]::ReadAllBytes((Join-Path $sourceRoot $relative))})
    }
    if (-not $SkipHotkey) {
        $plan.Add(@{path = $hotkeyPath; bytes = [IO.File]::ReadAllBytes((Join-Path $sourceRoot 'astralathe_lua.lua'))})
    }
    $loadOrderPath = Join-Path $GamePath 'astralathe_mods.txt'
    $lines = [Collections.Generic.List[string]]::new()
    $added = $false
    if (Test-Path -LiteralPath $loadOrderPath -PathType Leaf) {
        foreach ($line in [IO.File]::ReadAllLines($loadOrderPath)) {
            if (($line -split ',', 2)[0] -eq $folderName) {
                if (-not $added) { $lines.Add($folderName + ',1'); $added = $true }
            } else { $lines.Add($line) }
        }
    }
    if (-not $added) { $lines.Add($folderName + ',1') }
    $plan.Add(@{path = $loadOrderPath; bytes = $utf8.GetBytes(($lines -join "`n") + "`n")})

    $gamePrefix = $GamePath.TrimEnd('\') + '\'
    foreach ($item in $plan) {
        $item.path = [IO.Path]::GetFullPath($item.path)
        if (-not $item.path.StartsWith($gamePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'An install path is outside the game folder.' }
        $item.relative = $item.path.Substring($gamePrefix.Length)
        $item.existed = Test-Path -LiteralPath $item.path -PathType Leaf
    }
    if (-not $PSCmdlet.ShouldProcess($GamePath, ('Install and enable Collectible Scout ' + $metadata.version))) { return }
    $backupRoot = Join-Path $GamePath ('CollectibleScout-Backups\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + 'Z-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void][IO.Directory]::CreateDirectory($backupRoot)
    # Back up every file before writing the first update. Other mod files stay in place.
    foreach ($item in $plan) {
        if ($item.existed) {
            $item.backup = Join-Path $backupRoot $item.relative
            [void][IO.Directory]::CreateDirectory((Split-Path $item.backup -Parent))
            Copy-Item -LiteralPath $item.path -Destination $item.backup
        }
    }
    $manifest = @{version = $metadata.version; gamePath = $GamePath; files = @($plan | ForEach-Object { @{path = $_.relative; existed = $_.existed} })}
    [IO.File]::WriteAllText((Join-Path $backupRoot 'backup.json'), ($manifest | ConvertTo-Json -Depth 5), $utf8)
    $attempted = [Collections.Generic.List[object]]::new()
    try {
        foreach ($item in $plan) {
            $attempted.Add($item)
            [void][IO.Directory]::CreateDirectory((Split-Path $item.path -Parent))
            [IO.File]::WriteAllBytes($item.path, $item.bytes)
        }
    } catch {
        $installError = $_
        for ($index = $attempted.Count - 1; $index -ge 0; $index--) {
            $item = $attempted[$index]
            try {
                if ($item.existed) { Copy-Item -LiteralPath $item.backup -Destination $item.path -Force }
                elseif (Test-Path -LiteralPath $item.path -PathType Leaf) { Remove-Item -LiteralPath $item.path -Force }
            } catch { Write-Warning ('Could not restore ' + $item.path + '. Backup: ' + $backupRoot) }
        }
        throw $installError
    }
    [pscustomobject]@{Version = $metadata.version; GamePath = $GamePath; ModPath = $destinationRoot; BackupPath = $backupRoot; HotkeyInstalled = -not $SkipHotkey}
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $result = Install-CollectibleScout -GamePath $GamePath -SkipHotkey:$SkipHotkey -ForceHotkey:$ForceHotkey -NonInteractive:$NonInteractive -WhatIf:$WhatIfPreference
        if ($null -ne $result) {
            Write-Output ('Collectible Scout ' + $result.Version + ' installed and enabled.')
            Write-Output ('Game: ' + $result.GamePath)
            Write-Output ('Backup: ' + $result.BackupPath)
            if ($result.HotkeyInstalled) { Write-Output 'Launch Psychonauts through AstralatheLauncher.exe, then press F3 to scan.' }
            else { Write-Output 'Your existing F3 script was kept. Launch the game through AstralatheLauncher.exe.' }
        }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        if ($_.Exception.GetBaseException() -is [UnauthorizedAccessException]) {
            Write-Host 'Windows denied write access. Right-click Install.cmd and choose Run as administrator.'
        }
        exit 1
    }
}
