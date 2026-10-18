param([string]$ScratchRoot = (Join-Path ([IO.Path]::GetTempPath()) ('CollectibleScout-tests-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
$ScratchRoot = [IO.Path]::GetFullPath($ScratchRoot)
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'Install.ps1')
[void][IO.Directory]::CreateDirectory($ScratchRoot)
$script:fixtureIndex = 0
$script:testCount = 0
$script:gameRunning = $false
function Get-Process { param($Name, $ErrorAction) if ($script:gameRunning) { [pscustomobject]@{ProcessName = 'Psychonauts'} } }
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Test([string]$Name, [scriptblock]$Body) { & $Body; $script:testCount++; Write-Output ('PASS ' + $Name) }
function Write-FixtureFile([string]$Path, [string]$Text = '') {
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-TestGame {
    $script:fixtureIndex++
    $path = Join-Path $ScratchRoot ("Game [$script:fixtureIndex] O'Brien")
    foreach ($file in @('Psychonauts.exe', 'AstralatheLauncher.exe', 'Astralathe.dll')) { Write-FixtureFile (Join-Path $path $file) }
    $path
}
function Add-OldScout([string]$Game, [string]$Folder = 'Collectible Scout', [string]$Id = 'com.codex.collectiblescout') {
    $path = Join-Path $Game ('ModResource\' + $Folder)
    Write-FixtureFile (Join-Path $path 'mod.json') ('{"id":"' + $Id + '","name":"Collectible Scout","version":"0.1.0"}')
    Write-FixtureFile (Join-Path $path 'Scripts\CollectibleScout.lua') 'old scanner'
    Write-FixtureFile (Join-Path $path 'mod_boot.lua') 'old boot'
    Write-FixtureFile (Join-Path $path 'astralathe_lua.lua') 'old packaged hotkey'
    Write-FixtureFile (Join-Path $path 'Scripts\OtherHook.lua') 'preserve this extra hook'
    $path
}
function Expect-Failure([scriptblock]$Body, [string]$Pattern) {
    $failure = $null
    try { & $Body | Out-Null } catch { $failure = $_.Exception.Message }
    Assert ($null -ne $failure -and $failure -match $Pattern) ('Expected failure matching ' + $Pattern + '; got ' + $failure)
}

Test 'fresh install copies the scanner and F3, enables the mod and records backups' {
    $game = New-TestGame
    Write-FixtureFile (Join-Path $game 'astralathe_mods.txt') "Other Mod,1`nDisabled Mod,0`n"
    $result = Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive
    Assert ($result.Version -eq '0.2.2' -and $result.HotkeyInstalled) 'Incorrect installation result'
    $installed = Join-Path $game 'ModResource\Collectible Scout'
    foreach ($file in @('mod.json', 'mod_boot.lua', 'astralathe_lua.lua', 'Scripts\CollectibleScout.lua')) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $installed $file)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repo ('CollectibleScout\' + $file))).Hash) ('Payload mismatch: ' + $file)
    }
    Assert ([IO.File]::ReadAllText((Join-Path $game 'astralathe_mods.txt')) -eq "Other Mod,1`nDisabled Mod,0`nCollectible Scout,1`n") 'Other mods or load order changed'
    Assert ([IO.File]::ReadAllText((Join-Path $result.BackupPath 'astralathe_mods.txt')) -eq "Other Mod,1`nDisabled Mod,0`n") 'Original load order not backed up'
    Assert (Test-Path -LiteralPath (Join-Path $result.BackupPath 'backup.json')) 'Missing backup manifest'
    Assert (-not $result.BackupPath.StartsWith((Join-Path $game 'ModResource'))) 'Backup is inside the mod search path'
    Assert ((Get-FileHash -LiteralPath (Join-Path $game 'astralathe_lua.lua')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repo 'CollectibleScout\astralathe_lua.lua')).Hash) 'F3 was not installed'
}

Test 'updating a legacy custom-named install preserves extra files and load order position' {
    $game = New-TestGame
    $old = Add-OldScout $game 'My Scout'
    Write-FixtureFile (Join-Path $game 'astralathe_lua.lua') 'old CollectibleScout shortcut'
    Write-FixtureFile (Join-Path $game 'astralathe_mods.txt') "First,1`nMy Scout,0`nLast,0`n"
    $result = Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive
    Assert ($result.ModPath -eq $old) 'Existing install was duplicated'
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'ModResource\Collectible Scout'))) 'Unnecessary second install created'
    Assert ([IO.File]::ReadAllText((Join-Path $old 'Scripts\OtherHook.lua')) -eq 'preserve this extra hook') 'Extra script changed'
    Assert ([IO.File]::ReadAllText((Join-Path $game 'astralathe_mods.txt')) -eq "First,1`nMy Scout,1`nLast,0`n") 'Load order position changed'
    Assert ([IO.File]::ReadAllText((Join-Path $result.BackupPath 'ModResource\My Scout\Scripts\CollectibleScout.lua')) -eq 'old scanner') 'Old scanner not backed up'
    Assert ([IO.File]::ReadAllText((Join-Path $result.BackupPath 'astralathe_lua.lua')) -eq 'old CollectibleScout shortcut') 'Old F3 not backed up'
}

Test 'repeated installation uses unique backups without duplicate load order entries' {
    $game = New-TestGame
    $first = Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive
    $second = Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive
    Assert ($first.BackupPath -ne $second.BackupPath) 'Backup was overwritten'
    Assert ([IO.File]::ReadAllText((Join-Path $game 'astralathe_mods.txt')) -eq "Collectible Scout,1`n") 'Duplicate load order entries'
}

Test 'an unrelated F3 script is protected until replacement is explicitly selected' {
    $game = New-TestGame
    Write-FixtureFile (Join-Path $game 'astralathe_lua.lua') 'another mod hotkey'
    Expect-Failure { Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive } 'F3 is used by another script'
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'ModResource'))) 'Installer wrote files before checking the F3 conflict'
    $result = Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive -ForceHotkey
    Assert ([IO.File]::ReadAllText((Join-Path $result.BackupPath 'astralathe_lua.lua')) -eq 'another mod hotkey') 'Foreign F3 was not backed up'
}

Test 'keeping an existing F3 script still installs and enables the mod' {
    $game = New-TestGame
    Write-FixtureFile (Join-Path $game 'astralathe_lua.lua') 'keep my hotkey'
    $result = Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive -SkipHotkey
    Assert (-not $result.HotkeyInstalled) 'Hotkey status incorrect'
    Assert ([IO.File]::ReadAllText((Join-Path $game 'astralathe_lua.lua')) -eq 'keep my hotkey') 'F3 was changed'
    Assert ([IO.File]::ReadAllText((Join-Path $game 'astralathe_mods.txt')) -eq "Collectible Scout,1`n") 'Mod was not enabled'
}

Test 'an empty default F3 file can be installed without a conflict prompt' {
    $game = New-TestGame
    Write-FixtureFile (Join-Path $game 'astralathe_lua.lua')
    $result = Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive
    Assert ($result.HotkeyInstalled) 'The empty default hotkey was not installed'
    Assert ((Get-Item -LiteralPath (Join-Path $result.BackupPath 'astralathe_lua.lua')).Length -eq 0) 'Empty original F3 was not backed up'
}

Test 'WhatIf makes no files or backup folders and does not prompt over an F3 conflict' {
    $game = New-TestGame
    Write-FixtureFile (Join-Path $game 'astralathe_lua.lua') 'foreign hotkey'
    Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive -WhatIf | Out-Null
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'CollectibleScout-Backups'))) 'WhatIf created a backup'
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'ModResource'))) 'WhatIf installed a mod'
    Assert ([IO.File]::ReadAllText((Join-Path $game 'astralathe_lua.lua')) -eq 'foreign hotkey') 'WhatIf changed F3'
}

Test 'missing prerequisites and an incomplete package fail before writing anything' {
    $game = New-TestGame
    Remove-Item -LiteralPath (Join-Path $game 'Astralathe.dll')
    Expect-Failure { Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive } 'Install Astralathe first'
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'ModResource'))) 'Missing-Astralathe install changed files'
    $game = New-TestGame
    $incomplete = Join-Path $ScratchRoot 'Incomplete package'
    [void][IO.Directory]::CreateDirectory($incomplete)
    Expect-Failure { Install-CollectibleScout -GamePath $game -PackageRoot $incomplete -NonInteractive } 'Extract the entire release ZIP'
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'ModResource'))) 'Incomplete package changed files'
    Expect-Failure { Install-CollectibleScout -GamePath $incomplete -PackageRoot $repo -NonInteractive } 'does not contain Psychonauts.exe'
}

Test 'a running game prevents installation' {
    $game = New-TestGame
    $script:gameRunning = $true
    try { Expect-Failure { Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive } 'Close Psychonauts' }
    finally { $script:gameRunning = $false }
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'ModResource'))) 'Running-game check changed files'
}

Test 'duplicate scanner installs are caught before modification' {
    $game = New-TestGame
    $first = Add-OldScout $game 'Collectible Scout'
    $second = Add-OldScout $game 'CollectibleScout' 'com.lorenzo.collectiblescout'
    Expect-Failure { Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive } 'Multiple Collectible Scout folders'
    Assert ([IO.File]::ReadAllText((Join-Path $first 'Scripts\CollectibleScout.lua')) -eq 'old scanner') 'First install was changed'
    Assert ([IO.File]::ReadAllText((Join-Path $second 'Scripts\CollectibleScout.lua')) -eq 'old scanner') 'Second install was changed'
}

Test 'a later write failure restores the old scanner and F3 from backups' {
    $game = New-TestGame
    $old = Add-OldScout $game
    Write-FixtureFile (Join-Path $game 'astralathe_lua.lua') 'old CollectibleScout hotkey'
    # A directory in place of the final destination forces failure after payload writes.
    [void][IO.Directory]::CreateDirectory((Join-Path $game 'astralathe_mods.txt'))
    Expect-Failure { Install-CollectibleScout -GamePath $game -PackageRoot $repo -NonInteractive } 'denied|directory'
    Assert ([IO.File]::ReadAllText((Join-Path $old 'Scripts\CollectibleScout.lua')) -eq 'old scanner') 'Old scanner was not restored'
    Assert ([IO.File]::ReadAllText((Join-Path $old 'mod_boot.lua')) -eq 'old boot') 'Old boot script was not restored'
    Assert ([IO.File]::ReadAllText((Join-Path $game 'astralathe_lua.lua')) -eq 'old CollectibleScout hotkey') 'Old F3 was not restored'
    Assert ([IO.File]::ReadAllText((Join-Path $old 'Scripts\OtherHook.lua')) -eq 'preserve this extra hook') 'Extra hook changed during rollback'
}

Test 'secondary Steam libraries and renamed game directories are discovered' {
    $steam = Join-Path $ScratchRoot 'Steam root'
    $library = Join-Path $ScratchRoot 'Steam library [secondary]'
    $vdfPath = $library.Replace('\', '\\')
    Write-FixtureFile (Join-Path $steam 'steamapps\libraryfolders.vdf') ("`"libraryfolders`"`n{`n`t`"1`"`n`t{`n`t`t`"path`" `"$vdfPath`"`n`t}`n}")
    Write-FixtureFile (Join-Path $library 'steamapps\appmanifest_3830.acf') '"AppState" { "appid" "3830" "installdir" "Renamed Psychonauts" }'
    $game = Join-Path $library 'steamapps\common\Renamed Psychonauts'
    Write-FixtureFile (Join-Path $game 'Psychonauts.exe')
    $found = @(Get-ScoutGameCandidates -SteamRoots @($steam, $steam))
    Assert ($found.Count -eq 1 -and $found[0] -eq $game) 'Secondary library detection failed'
}

Test 'legacy Steam library lists and default game directories are discovered' {
    $steam = Join-Path $ScratchRoot 'Old Steam root'
    $library = Join-Path $ScratchRoot 'Old Steam library'
    $vdfPath = $library.Replace('\', '\\')
    Write-FixtureFile (Join-Path $steam 'config\libraryfolders.vdf') ("`"LibraryFolders`"`n{`n`t`"1`" `"$vdfPath`"`n}")
    $game = Join-Path $library 'steamapps\common\Psychonauts'
    Write-FixtureFile (Join-Path $game 'Psychonauts.exe')
    $found = @(Get-ScoutGameCandidates -SteamRoots @($steam))
    Assert ($found.Count -eq 1 -and $found[0] -eq $game) 'Old Steam library detection failed'
    Assert (@(Get-ScoutGameCandidates -SteamRoots @()).Count -eq 0) 'Empty library list found a game'
}

Write-Output ("$script:testCount installer tests passed using PowerShell " + $PSVersionTable.PSVersion)
Write-Output ('Fixtures: ' + $ScratchRoot)
