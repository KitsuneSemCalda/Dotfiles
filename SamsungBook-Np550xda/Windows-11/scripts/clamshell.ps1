#!/usr/bin/env pwsh
# Windows PowerShell 5.1 compatible; keep source ASCII for its default encoding.
param(
    [switch]$Apply,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
if ($Apply -and $Restore) { throw 'Use -Apply or -Restore, not both.' }

$statePath = Join-Path $env:LOCALAPPDATA 'dotfiles\clamshell-power.json'

function Invoke-PowerCfg {
    param([string[]]$Arguments)
    $output = & powercfg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg $($Arguments -join ' ') failed: $output" }
    return @($output)
}

function Get-LidSettings {
    $active = (Invoke-PowerCfg -Arguments @('/getactivescheme')) -join "`n"
    $guid = [regex]::Match($active, '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}').Value
    if (-not $guid) { throw 'Could not identify the active power scheme.' }

    # The labels in powercfg output are localized. Its final two hex values
    # are the current AC and DC indices, in that order.
    $query = Invoke-PowerCfg -Arguments @('/qh', $guid, 'SUB_BUTTONS', 'LIDACTION')
    $values = @($query | ForEach-Object {
        if ($_ -match '0x([0-9a-fA-F]{8})\s*$') { [Convert]::ToInt32($Matches[1], 16) }
    })
    if ($values.Count -lt 2 -or $values[-2] -notin 0, 1, 2, 3 -or $values[-1] -notin 0, 1, 2, 3) {
        throw 'Could not read the AC/DC lid actions from powercfg.'
    }
    return [pscustomobject]@{ Scheme = $guid; AC = $values[-2]; DC = $values[-1] }
}

function Set-LidSettings {
    param([string]$Scheme, [int]$AC, [int]$DC)
    Invoke-PowerCfg -Arguments @('/setacvalueindex', $Scheme, 'SUB_BUTTONS', 'LIDACTION', "$AC") | Out-Null
    Invoke-PowerCfg -Arguments @('/setdcvalueindex', $Scheme, 'SUB_BUTTONS', 'LIDACTION', "$DC") | Out-Null
    Invoke-PowerCfg -Arguments @('/setactive', $Scheme) | Out-Null
}

$current = Get-LidSettings
if ($Restore) {
    if (-not (Test-Path -LiteralPath $statePath)) { throw "No saved lid settings at $statePath" }
    $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($current.Scheme -ne $saved.Scheme) { throw 'The active power scheme changed; select the original scheme first.' }
    if (($current.AC -ne 0 -and $current.AC -ne $saved.AC) -or
        ($current.DC -ne 1 -and $current.DC -ne $saved.DC)) {
        throw 'Lid actions changed since setup; refusing to overwrite them.'
    }
    Set-LidSettings -Scheme $saved.Scheme -AC $saved.AC -DC $saved.DC
    Remove-Item -LiteralPath $statePath
    Write-Output "Restored lid actions: AC=$($saved.AC), battery=$($saved.DC)."
    return
}

if (-not $Apply) {
    Write-Output "Power scheme $($current.Scheme): lid actions AC=$($current.AC), battery=$($current.DC)."
    Write-Output 'Run with -Apply to set AC=0 (do nothing), battery=1 (sleep).'
    return
}

if (Test-Path -LiteralPath $statePath) {
    $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($current.Scheme -ne $saved.Scheme -or $current.AC -ne 0 -or $current.DC -ne 1) {
        throw "Saved settings exist at $statePath, but the active scheme or lid actions changed. Restore or resolve them first."
    }
    Write-Output 'Clamshell lid actions are already applied.'
    return
}

if ($current.AC -eq 0 -and $current.DC -eq 1) {
    Write-Output 'Clamshell lid actions are already set; no change needed.'
    return
}

$stateDir = Split-Path -Parent $statePath
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$current | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8
Set-LidSettings -Scheme $current.Scheme -AC 0 -DC 1
Write-Output 'Clamshell lid actions applied: AC=do nothing, battery=sleep.'
