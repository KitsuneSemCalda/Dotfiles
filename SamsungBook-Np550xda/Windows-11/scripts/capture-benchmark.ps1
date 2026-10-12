param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [int]$Seconds = 600,
    [Parameter(Mandatory = $true)][string]$Output
)
$rows = @()
for ($i = 0; $i -lt $Seconds; $i++) {
    $obs = Get-Process obs64 -ErrorAction SilentlyContinue | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem
    $rows += [pscustomobject]@{
        Timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        Scenario = $Scenario
        RamUsedMiB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024)
        ObsWorkingSetMiB = if ($obs) { [math]::Round($obs.WorkingSet64 / 1MB) } else { $null }
        ObsCpuSeconds = if ($obs) { $obs.CPU } else { $null }
        RenderLagPct = $null
        EncodeLagPct = $null
        DroppedFramesPct = $null
        Notes = $null
    }
    Start-Sleep -Seconds 1
}
$parent = Split-Path -Parent $Output
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$rows | Export-Csv -LiteralPath $Output -NoTypeInformation -Encoding utf8
