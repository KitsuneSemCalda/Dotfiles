# Pure policy, filesystem and orchestration tests. No real update or task registration.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Windows-11\scripts\maintenance\common.ps1')
function Assert($condition, $message) { if (-not $condition) { throw $message } }
$directory = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-maintenance-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
try {
    $sunday = [datetime]'2026-10-25T03:30:00'
    Assert (Test-MaintenanceWindow $sunday $true 900) 'Eligible Sunday rejected'
    Assert (Test-MaintenanceWindow $sunday.AddDays(1) $true 900) 'Missed Sunday did not retry Monday'
    foreach ($inputs in @(@($false,900), @($null,900), @($true,$null), @($true,899))) {
        Assert (-not (Test-MaintenanceWindow $sunday $inputs[0] $inputs[1])) 'Unknown/unsafe conditions accepted'
    }
    Assert (-not (Test-MaintenanceWindow $sunday.AddHours(3) $true 900)) 'Window did not close at 06:00'
    Assert ((Get-MaintenanceWeek $sunday) -eq (Get-MaintenanceWeek $sunday.AddDays(6))) 'Week changed before Sunday'
    Assert ((Get-MaintenanceWeek $sunday) -ne (Get-MaintenanceWeek $sunday.AddDays(7))) 'Week did not change on Sunday'

    $temp = Join-Path $directory 'temp'; $documents = Join-Path $directory 'documents'
    New-Item -ItemType Directory -Path $temp,$documents | Out-Null
    Set-Content -LiteralPath (Join-Path $documents 'keep') -Value 'document'
    Set-Content -LiteralPath (Join-Path $temp 'old') -Value 'old'
    Set-Content -LiteralPath (Join-Path $temp 'recent') -Value 'recent'
    (Get-Item -LiteralPath (Join-Path $temp 'recent')).LastWriteTime = (Get-Date).AddDays(20)
    $linkCreated = $false
    try { New-Item -ItemType SymbolicLink -Path (Join-Path $temp 'link') -Target $documents -ErrorAction Stop | Out-Null; $linkCreated=$true } catch { Write-Output 'Symbolic link fixture unavailable on this runner' }
    $bytes = Clear-MaintenanceTemp $temp (Get-Date).AddDays(10)
    Assert ($bytes -gt 0) 'No old temporary files removed'
    Assert (-not (Test-Path -LiteralPath (Join-Path $temp 'old'))) 'Old file survived'
    Assert (Test-Path -LiteralPath (Join-Path $temp 'recent')) 'Recent file removed'
    Assert (Test-Path -LiteralPath (Join-Path $documents 'keep')) 'Cleanup escaped temporary tree'
    if ($linkCreated) {
        Assert ((Clear-MaintenanceTemp (Join-Path $temp 'link') (Get-Date).AddDays(100)) -eq 0) 'Cleanup traversed symlink root'
        # Remove only the link before the test fixture's recursive teardown.
        (Get-Item -LiteralPath (Join-Path $temp 'link')).Delete()
    }

    $progressPath = Join-Path $directory 'progress.json'
    $progress = @{ Week=(Get-MaintenanceWeek $sunday); Done=@() }
    $script:executed = @()
    $actions = Invoke-MaintenanceSteps -Phases @('Temporary','WindowsUpdate','Applications') -Progress $progress -ProgressPath $progressPath -Eligible { $true } -Execute {
        param($phase)
        $script:executed += $phase
        if ($phase -eq 'WindowsUpdate') { throw 'simulated update failure' }
        return 'simulated success'
    }
    Assert ($actions.WindowsUpdate.Status -eq 'failed') 'Partial failure reported as success'
    Assert ($progress.Done.Count -eq 1 -and $progress.Done[0] -eq 'Temporary') 'Failed stage marked complete'
    Assert ($script:executed -notcontains 'Applications') 'Updates continued after prerequisite failure'
    $restored = Read-MaintenanceProgress $progressPath
    $script:executed = @()
    $actions = Invoke-MaintenanceSteps -Phases @('Temporary','WindowsUpdate','Applications') -Progress $restored -ProgressPath $progressPath -Eligible { $true } -Execute {
        param($phase); $script:executed += $phase; return 'simulated success'
    }
    Assert ($script:executed.Count -eq 2 -and $script:executed[0] -eq 'WindowsUpdate') 'Resume repeated completed work'
    $script:executed = @()
    $script:gates = 0
    $progress.Done = @()
    $actions = Invoke-MaintenanceSteps -Phases @('Temporary','WindowsUpdate') -Progress $progress -ProgressPath $progressPath -Eligible {
        $script:gates++; return ($script:gates -eq 1)
    } -Execute { param($phase); $script:executed += $phase; return 'simulated success' }
    Assert ($script:executed.Count -eq 1) 'New work started after return of user/battery transition'
    Assert ($actions.WindowsUpdate.Status -eq 'pending') 'Lost eligibility was not recorded'

    $script:power = @{ AC=[guid]'ded574b5-45a0-4f42-8737-46345c09c238'; DC=[guid]::Empty }
    $script:failPower = $true
    function Get-MaintenancePowerModes { return $script:power.Clone() }
    function Set-MaintenancePowerMode {
        param($Supply, $Mode)
        if ($script:failPower -and $Supply -eq 'DC') { throw 'simulated native power failure' }
        $script:power[$Supply] = $Mode
    }
    $powerState = Join-Path $directory 'power'; New-Item -ItemType Directory -Path $powerState | Out-Null
    $failed = $false
    try { Set-MaintenancePower $powerState } catch { $failed = $true }
    Assert $failed 'Partial power configuration did not fail'
    $saved = Get-Content -LiteralPath (Join-Path $powerState 'power.json') -Raw | ConvertFrom-Json
    Assert (-not $saved.Applied) 'Failed power setup was marked applied'
    $script:failPower = $false
    Set-MaintenancePower $powerState
    $saved = Get-Content -LiteralPath (Join-Path $powerState 'power.json') -Raw | ConvertFrom-Json
    Assert ($saved.Applied -and $saved.AC -eq 'ded574b5-45a0-4f42-8737-46345c09c238') 'Retry lost original power state'
    $script:power.AC = [guid]'961cc777-2547-4f9d-8174-7d86181b8a7a' # later manual choice
    Set-MaintenancePower $powerState
    Assert ($script:power.AC -ne [guid]::Empty) 'Reinstall overwrote a manual power choice'
    Set-MaintenancePower $powerState -Restore
    Assert ($script:power.AC -eq [guid]'961cc777-2547-4f9d-8174-7d86181b8a7a') 'Restore overwrote a manual power choice'
    Assert ($script:power.DC -eq [guid]::Empty) 'Owned battery setting was not restored'

    # Validate C# layouts/signatures without invoking platform APIs on a Linux runner.
    Initialize-MaintenanceNative
    if ($env:OS -eq 'Windows_NT') {
        $templates = New-MaintenanceTaskTemplates
        Assert ($templates.SystemTrigger.Repetition.Interval -eq 'PT15M') 'System task repetition incorrect'
        Assert ($templates.SystemTrigger.Repetition.Duration -eq 'PT3H') 'System task window incorrect'
        Assert (-not $templates.SystemSettings.WakeToRun) 'Task would wake the computer'
        Assert (-not $templates.SystemSettings.StopIfGoingOnBatteries) 'Task would kill a package transaction on battery'
        Assert (-not $templates.SystemSettings.IdleSettings.StopOnIdleEnd) 'Task would kill a package transaction when user returns'
        Assert ($templates.SystemSettings.RunOnlyIfIdle) 'System task lacks scheduler idle gate'
        Assert ($templates.SystemSettings.DisallowStartIfOnBatteries) 'System task can start on battery'
        Assert (-not $templates.UserSettings.DisallowStartIfOnBatteries) 'Light user diagnosis cannot run on battery'
        $preview = & (Join-Path $PSScriptRoot '..\Windows-11\scripts\maintenance\maintenance.ps1') -Mode Install -DryRun
        Assert ($preview -match 'Would install') 'Installer dry run failed'
    }
    $files = @(Get-ChildItem (Join-Path $PSScriptRoot '..\Windows-11\scripts\maintenance') -Filter '*.ps1')
    $files += Get-Item (Join-Path $PSScriptRoot '..\Windows-11\win11.ps1')
    foreach ($file in $files) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
        Assert (-not $errors) "PowerShell parse errors: $file $errors"
    }
    Write-Output 'OK: maintenance windows, missing signals, cleanup boundaries, partial failure, resume, idle transition and native bindings'
} finally { Remove-Item -LiteralPath $directory -Recurse -Force }
