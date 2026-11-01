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
    # Force identical timestamps so separate backup runs exercise unique names.
    $script = Get-Content -LiteralPath $installer -Raw
    $script = $script.Replace("Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'", "'20261020-120000-0000000'")
    Set-Content -LiteralPath $installer -Value $script
    . (Join-Path $repo 'scripts\jsonc.ps1')
    $parsed = ConvertFrom-Jsonc '{"url":"https://example.org/a//b",/* block */"items":[1,2,],}// line'
    Assert ($parsed.url -eq 'https://example.org/a//b' -and $parsed.items.Count -eq 2) 'JSONC comments or trailing commas failed'
    Assert ((ConvertFrom-Jsonc '{"name":"a\"b"}').name -eq 'a"b') 'JSONC escaped quote failed'
    & $installer -Target $target -DryRun
    Assert (-not (Test-Path (Join-Path $target '.config\starship.toml'))) 'Dry-run wrote files'
    foreach ($name in @('Maintenance', 'All')) {
        $option = @{ $name = $true }
        $failed = $false
        $message = ''
        try { & $installer -Target $target -DryRun @option } catch { $failed = $true; $message = $_.Exception.Message }
        Assert $failed 'Maintenance/All accepted a foreign target'
        Assert ($message -match 'HOME real') 'Foreign-target rejection came from an unrelated failure'
    }
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
    $backupBase = Join-Path $target '.local\state\dotfiles\backups'
    $firstSnapshot = Get-ChildItem -LiteralPath $backupBase -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') }
    Assert (@($firstSnapshot).Count -eq 1) 'First backup has no manifest'
    $incomplete = Join-Path $backupBase '20990101-000000-0000000-00000000000000000000000000000000'
    New-Item -ItemType Directory -Path $incomplete | Out-Null
    Set-Content -LiteralPath (Join-Path $incomplete 'manifest.json') -Value '[]'
    & $installer -Target $target -Restore
    Assert ((Get-Content $dest -Raw).Trim() -eq 'local edit') 'Restore lost local edits'
    Remove-Item -LiteralPath $incomplete -Recurse -Force

    Set-Content -LiteralPath $dest -Value 'edit before missing-backup test'
    & $installer -Target $target -Backup
    Assert (@(Get-ChildItem -LiteralPath $backupBase -Directory).Count -eq 2) 'Backups with the same timestamp collided'
    $snapshot = Get-ChildItem -LiteralPath $backupBase -Directory | Sort-Object CreationTimeUtc | Select-Object -Last 1
    Remove-Item -LiteralPath (Join-Path $snapshot.FullName 'starship.toml') -Force
    $beforeMissing = Get-Content $dest -Raw
    $failed = $false
    try { & $installer -Target $target -Restore } catch { $failed = $true }
    Assert $failed 'Restore did not fail on missing backup file'
    Assert ((Get-Content $dest -Raw) -eq $beforeMissing) 'Restore touched destination despite missing backup file'

    Set-Content -LiteralPath $dest -Value 'edit before locked-backup test'
    & $installer -Target $target -Backup
    $snapshot = Get-ChildItem -LiteralPath $backupBase -Directory | Sort-Object CreationTimeUtc | Select-Object -Last 1
    $lockedFile = Join-Path $snapshot.FullName 'starship.toml'
    $stream = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
    $beforeLocked = Get-Content $dest -Raw
    $failed = $false
    try { & $installer -Target $target -Restore } catch { $failed = $true } finally { $stream.Close() }
    Assert $failed 'Restore did not fail on unreadable backup file'
    Assert ((Get-Content $dest -Raw) -eq $beforeLocked) 'Restore touched destination despite unreadable backup file'

    # Every installed item must come back from a backup to its own path.
    $state = Get-Content -LiteralPath (Join-Path $target '.local\state\dotfiles\installed-windows.json') -Raw | ConvertFrom-Json
    $edits = @{}
    foreach ($path in $state.PSObject.Properties.Name) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer) {
            $item = Get-ChildItem -LiteralPath $path -Recurse -File -Force | Sort-Object FullName | Select-Object -First 1
        }
        Set-Content -LiteralPath $item.FullName -Value "edit of $path"
        $edits[$item.FullName] = Get-Content -LiteralPath $item.FullName -Raw
    }
    Assert ($edits.Count -gt 1) 'No installed items to round-trip'
    & $installer -Target $target -Backup
    foreach ($file in $edits.Keys) {
        Assert ((Get-Content -LiteralPath $file -Raw) -ne $edits[$file]) "Backup install kept the edit in $file"
    }
    & $installer -Target $target -Restore
    foreach ($file in $edits.Keys) {
        Assert ((Get-Content -LiteralPath $file -Raw) -eq $edits[$file]) "Restore did not return $file"
    }

    Write-Output 'OK: copies, removed checkout, reinstall, conflicts, restore of every item, missing/unreadable backup safety'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
