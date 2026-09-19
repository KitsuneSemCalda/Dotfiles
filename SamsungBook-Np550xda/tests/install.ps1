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
    Write-Output 'OK: copies, removed checkout, reinstall, conflicts and restore'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
