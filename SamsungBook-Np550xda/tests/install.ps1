# Run on Windows with powershell -NoProfile -File tests/install.ps1 or pwsh.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$repo = Join-Path $root 'repo'
$target = Join-Path $root 'target'
function Assert($condition, $message) { if (-not $condition) { throw $message } }
try {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\Windows-11') -Destination $repo -Recurse
    $installer = Join-Path $repo 'win11.ps1'
    & $installer -Target $target -DryRun
    Assert (-not (Test-Path (Join-Path $target '.config\starship.toml'))) 'Dry-run wrote files'
    & $installer -Target $target
    $dest = Join-Path $target '.config\starship.toml'
    $skin = Join-Path $target 'Documents\Rainmeter\Skins\AincradHUD\HUD.ini'
    Assert (-not (Get-Item $dest).LinkType) 'Installed a link'
    $expected = Get-Content $dest -Raw
    Move-Item -LiteralPath $repo -Destination "$repo-moved"
    Assert ((Get-Content $dest -Raw) -eq $expected) 'Depends on checkout'
    Assert (Test-Path $skin) 'Skin depends on checkout'
    Move-Item -LiteralPath "$repo-moved" -Destination $repo
    & $installer -Target $target
    Set-Content -LiteralPath $dest -Value 'local edit'
    $failed = $false
    try { & $installer -Target $target } catch { $failed = $true }
    Assert $failed 'Overwrote local edits'
    & $installer -Target $target -Backup
    & $installer -Target $target -Restore
    Assert ((Get-Content $dest -Raw).Trim() -eq 'local edit') 'Restore lost local edits'

    $backupBase = Join-Path $target '.local\state\dotfiles\backups'

    Set-Content -LiteralPath $dest -Value 'edit before missing-backup test'
    & $installer -Target $target -Backup
    $snapshot = Get-ChildItem -LiteralPath $backupBase -Directory | Sort-Object Name | Select-Object -Last 1
    Remove-Item -LiteralPath (Join-Path $snapshot.FullName 'starship.toml') -Force
    $beforeMissing = Get-Content $dest -Raw
    $failed = $false
    try { & $installer -Target $target -Restore } catch { $failed = $true }
    Assert $failed 'Restore did not fail on missing backup file'
    Assert ((Get-Content $dest -Raw) -eq $beforeMissing) 'Restore touched destination despite missing backup file'

    Set-Content -LiteralPath $dest -Value 'edit before locked-backup test'
    & $installer -Target $target -Backup
    $snapshot = Get-ChildItem -LiteralPath $backupBase -Directory | Sort-Object Name | Select-Object -Last 1
    $lockedFile = Join-Path $snapshot.FullName 'starship.toml'
    $stream = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
    $beforeLocked = Get-Content $dest -Raw
    $failed = $false
    try { & $installer -Target $target -Restore } catch { $failed = $true } finally { $stream.Close() }
    Assert $failed 'Restore did not fail on unreadable backup file'
    Assert ((Get-Content $dest -Raw) -eq $beforeLocked) 'Restore touched destination despite unreadable backup file'

    Write-Output 'OK: copies, removed checkout, reinstall, conflicts, restore, missing/unreadable backup safety'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
