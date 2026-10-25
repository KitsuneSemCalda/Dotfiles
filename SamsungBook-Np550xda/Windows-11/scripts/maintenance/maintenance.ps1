# Windows PowerShell 5.1 and PowerShell 7. No profile is loaded by scheduled tasks.
param(
    [ValidateSet('Analyze','Run','Simulate','Status','Install','Disable')][string]$Mode = 'Analyze',
    [switch]$System,
    [switch]$Scheduled,
    [switch]$DryRun,
    [string]$OwnerSid = ''
)
$ErrorActionPreference = 'Stop'
if ($System -and $Mode -in 'Install','Disable') { throw '-System is reserved for the scheduled system worker' }
$windowsRoot = [IO.Directory]::GetParent([Environment]::SystemDirectory).FullName
$savedModulePath = $env:PSModulePath
try {
    # Scheduled elevated code must not autoload user-writable modules or executables.
    $env:PSModulePath = Join-Path $windowsRoot 'System32\WindowsPowerShell\v1.0\Modules'
    . (Join-Path $PSScriptRoot 'common.ps1')
    $controlRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'DotfilesMaintenance'
    $systemState = Join-Path $controlRoot 'system'
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($OwnerSid -and $identity.User.Value -ne $OwnerSid) { throw 'Elevate as the same user; installing for a different administrator is not supported' }
    $isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $protectedUserState = Join-Path $controlRoot ('user-' + $identity.User.Value)
    $state = if ($System) { $systemState } elseif ($isAdmin) { $protectedUserState } else { Join-Path $env:LOCALAPPDATA 'dotfiles\maintenance' }
    $profileKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $identity.User.Value
    $profileDirectory = if (-not $System) { (Get-ItemProperty -LiteralPath $profileKey).ProfileImagePath } else { '' }

    if ($Mode -eq 'Install') {
        if ($DryRun) { Write-Output 'Would install protected maintenance scripts, system/user tasks and AC/DC power preferences'; return }
        if (-not $isAdmin) {
            $process = Start-Process (Join-Path $windowsRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Mode','Install','-OwnerSid',$identity.User.Value) -Verb RunAs -Wait -PassThru
            if ($process.ExitCode) { throw "Maintenance installation failed ($($process.ExitCode))" }
            return
        }
        $destination = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'DotfilesMaintenance'
        foreach ($directory in @($destination, $controlRoot, $systemState, $state)) {
            if ((Test-Path -LiteralPath $directory) -and ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refusing reparse directory: $directory" }
            if (Test-Path -LiteralPath $directory) {
                $existingAcl = Get-Acl -LiteralPath $directory
                $owner = $existingAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value
                if ($owner -notin 'S-1-5-18','S-1-5-32-544') { throw "Existing maintenance directory is not owned by SYSTEM/Administrators: $directory" }
                foreach ($access in $existingAcl.Access) {
                    $sid = $access.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
                    if ($access.AccessControlType -eq 'Allow' -and $sid -notin 'S-1-5-18','S-1-5-32-544' -and
                        ($access.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write)) { throw "Existing maintenance directory is writable by an untrusted principal: $directory" }
                }
            }
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $acl = New-Object Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true, $false)
            $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
            $readerSid = if ($directory -eq $state -or $directory -eq $systemState) { $identity.User.Value } else { 'S-1-5-32-545' }
            foreach ($entry in @(@('S-1-5-18','FullControl'), @('S-1-5-32-544','FullControl'), @($readerSid,'ReadAndExecute'))) {
                $sid = New-Object Security.Principal.SecurityIdentifier($entry[0])
                $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, $entry[1], 'ContainerInherit,ObjectInherit', 'None', 'Allow')
                $acl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $directory -AclObject $acl
        }
        foreach ($file in @('common.ps1','maintenance.ps1')) {
            $targetFile = Join-Path $destination $file
            if ((Test-Path -LiteralPath $targetFile) -and ((Get-Item -LiteralPath $targetFile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refusing reparse script: $targetFile" }
            if ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot $file)) -ne [IO.Path]::GetFullPath($targetFile)) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $targetFile -Force }
        }
        $operationLock = Join-Path $controlRoot 'operation.lock'
        if (-not (Test-Path -LiteralPath $operationLock)) { [IO.File]::WriteAllText($operationLock, '') }
        Remove-Item -LiteralPath (Join-Path $controlRoot 'disabled') -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $state -Force | Out-Null
        Set-MaintenancePower -State $state
        if (-not [Diagnostics.EventLog]::SourceExists('DotfilesMaintenance')) { New-EventLog -LogName Application -Source DotfilesMaintenance }
        $engine = Join-Path $windowsRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $installed = Join-Path $destination 'maintenance.ps1'
        $templates = New-MaintenanceTaskTemplates
        # WakeToRun is deliberately not enabled. No task is killed during a package transaction.
        $action = New-ScheduledTaskAction -Execute $engine -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$installed`" -Mode Run -System -Scheduled"
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName 'DotfilesMaintenance-System' -Action $action -Trigger $templates.SystemTrigger -Settings $templates.SystemSettings -Principal $principal -Force | Out-Null
        $action = New-ScheduledTaskAction -Execute $engine -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$installed`" -Mode Run -Scheduled"
        # Ordinary diagnosis and user-temp cleanup never receive an elevated token.
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName 'DotfilesMaintenance-User' -Action $action -Trigger $templates.UserTrigger -Settings $templates.UserSettings -Principal $principal -Force | Out-Null
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName 'DotfilesMaintenance-Applications' -Action $action -Trigger $templates.SystemTrigger -Settings $templates.SystemSettings -Principal $principal -Force | Out-Null
        Write-Output "Installed. Reports: $state and $systemState. No immediate updates were run."
        return
    }
    if ($Mode -eq 'Disable') {
        if (-not $isAdmin) {
            $process = Start-Process (Join-Path $windowsRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Mode','Disable','-OwnerSid',$identity.User.Value) -Verb RunAs -Wait -PassThru
            if ($process.ExitCode) { throw 'Maintenance disable failed' }; return
        }
        Get-ScheduledTask -TaskName 'DotfilesMaintenance-System','DotfilesMaintenance-User','DotfilesMaintenance-Applications' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
        [IO.File]::WriteAllText((Join-Path $controlRoot 'disabled'), '')
        Set-MaintenancePower -State $state -Restore
        Write-Output 'Disabled future executions; an active package transaction is allowed to finish.'
        return
    }
    if ($Mode -eq 'Status') {
        foreach ($directory in @($state, $protectedUserState, $systemState) | Select-Object -Unique) {
            $path = Join-Path $directory 'latest.txt'
            if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path } else { Write-Output "No report at $path" }
        }
        return
    }
    if ($Mode -eq 'Simulate' -or $DryRun) {
        $conditions = Get-MaintenanceConditions
        @{ Conditions=$conditions; Eligible=(Test-MaintenanceWindow (Get-Date) $conditions.AC $conditions.IdleSeconds); System=$System; Reboot=$false; Window='03:00-06:00, weekly from Sunday'; Actions=@('Updates','Temporary files older than 7 days','Native SSD maintenance') } | ConvertTo-Json -Depth 4
        return
    }
    if ($System -and -not $identity.IsSystem) { throw '-System execution requires the SYSTEM scheduled task' }
    New-Item -ItemType Directory -Path $state -Force | Out-Null
    $lock = $null
    $operationLock = $null
    try {
        try { $lock = [IO.File]::Open((Join-Path $state 'lock'), 'OpenOrCreate', 'ReadWrite', 'None') } catch [IO.IOException] { return }
        $progressPath = Join-Path $state 'progress.json'
        $progress = Read-MaintenanceProgress $progressPath
        $today = (Get-Date).ToString('yyyy-MM-dd')
        if ($Mode -eq 'Analyze' -or $progress.Diagnosed -ne $today) {
            $analysis = Get-MaintenanceAnalysis
            if ($System) {
                try {
                    $search = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
                    $analysis.Checks.Updates = @{ Status='ok'; Data=@($search.Updates | ForEach-Object { $_.Title }) }
                } catch { $analysis.Checks.Updates = @{ Status='unavailable'; Error=$_.Exception.Message } }
            } else {
                try {
                    $winget = Get-MaintenanceWinget
                    $output = & $winget upgrade --disable-interactivity 2>&1 | Out-String
                    $analysis.Checks.AppUpdates = @{ Code=$LASTEXITCODE; Output=$output }
                } catch { $analysis.Checks.AppUpdates = @{ Status='unavailable'; Error=$_.Exception.Message } }
            }
            Save-MaintenanceReport $state $analysis -System:$System
            $progress.Diagnosed = $today
            Write-MaintenanceJson $progressPath $progress
        }
        if ($Mode -eq 'Analyze') { return }
        if (Test-Path -LiteralPath (Join-Path $controlRoot 'disabled')) { return }
        $week = Get-MaintenanceWeek
        if ($progress.Week -ne $week) { $progress.Week = $week; $progress.Done = @() }
        $phases = if ($System) { @('Temporary','SSD','WindowsUpdate') } elseif ($isAdmin) { @('Applications') } else { @('Temporary') }
        if (@($phases | Where-Object { $progress.Done -notcontains $_ }).Count -eq 0) { return }
        $conditions = Get-MaintenanceConditions
        if (-not (Test-MaintenanceWindow (Get-Date) $conditions.AC $conditions.IdleSeconds)) {
            if (-not $Scheduled) { Write-Output 'Deferred: requires 03:00-06:00, AC power and 15 minutes idle' }; return
        }
        # Both contexts can read this protected file; FileShare.None serializes maintenance.
        try { $operationLock = [IO.File]::Open((Join-Path $controlRoot 'operation.lock'), 'Open', 'Read', 'None') } catch [IO.IOException] { return }
        $report = @{ Time=(Get-Date).ToString('o'); Before=(Get-MaintenanceAnalysis); Actions=[ordered]@{}; Warnings=@() }
        $report.Actions = Invoke-MaintenanceSteps -Phases $phases -Progress $progress -ProgressPath $progressPath -Eligible {
            $conditions = Get-MaintenanceConditions
            return (-not (Test-Path -LiteralPath (Join-Path $controlRoot 'disabled')) -and (Test-MaintenanceWindow (Get-Date) $conditions.AC $conditions.IdleSeconds))
        } -Execute {
            param($phase)
            $previousExecutionState = [DotfilesMaintenance.Native]::SetThreadExecutionState(2147483649)
            if (-not $previousExecutionState) { throw 'Cannot inhibit automatic sleep during maintenance' }
            try {
                $detail = ''
                if ($phase -in 'WindowsUpdate','Applications') {
                    $systemDrive = [IO.Path]::GetPathRoot($windowsRoot).TrimEnd('\')
                    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$systemDrive'"
                    if (-not $drive -or $drive.FreeSpace -lt 10GB) { throw 'Updates deferred: less than 10 GiB free or free space unknown' }
                }
                switch ($phase) {
                    'WindowsUpdate' {
                        if ((Get-MaintenanceAnalysis).RebootPending) { throw 'Restart pending; complete it manually before more system updates' }
                        $session = New-Object -ComObject Microsoft.Update.Session
                        $search = $session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software' and IsAssigned=1")
                        $updates = New-Object -ComObject Microsoft.Update.UpdateColl
                        foreach ($update in $search.Updates) {
                            $upgrade = @($update.Categories | Where-Object { $_.CategoryID -eq 'e6cf1350-c01b-414d-a61f-263d14d133b4' }).Count -gt 0
                            if ($update.BrowseOnly -or $update.IsBeta -or $upgrade) { continue }
                            if (-not $update.EulaAccepted) { $update.AcceptEula() }
                            [void]$updates.Add($update)
                        }
                        if ($updates.Count) {
                            $downloader = $session.CreateUpdateDownloader(); $downloader.Updates = $updates
                            $download = $downloader.Download()
                            if ([int]$download.ResultCode -ne 2) { throw "Update download failed or partial ($($download.ResultCode))" }
                            $installer = $session.CreateUpdateInstaller()
                            $installer.Updates = $updates; $installer.ForceQuiet = $true; $installer.AllowSourcePrompts = $false
                            if ($installer.RebootRequiredBeforeInstallation) { throw 'Restart required before installation' }
                            $installed = $installer.Install()
                            if ([int]$installed.ResultCode -ne 2) { throw "Update installation failed or partial ($($installed.ResultCode))" }
                            $detail = "Installed $($updates.Count) update(s); reboot pending=$($installed.RebootRequired)"
                        } else { $detail = 'No eligible system updates' }
                    }
                    'Applications' {
                        $winget = Get-MaintenanceWinget
                        $detail = & $winget upgrade --all --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
                        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "winget failed ($LASTEXITCODE): $detail" }
                    }
                    'SSD' {
                        $native = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName ScheduledDefrag -ErrorAction SilentlyContinue
                        if ($native -and $native.State -ne 'Disabled') { $detail = 'Existing ScheduledDefrag owns volume optimization' }
                        else {
                            $ssds = @(Get-PhysicalDisk | Where-Object { $_.MediaType -eq 'SSD' -and $_.HealthStatus -eq 'Healthy' })
                            foreach ($disk in $ssds) {
                                $serial = ([string]$disk.SerialNumber).Trim()
                                $logicalDisks = @(Get-Disk | Where-Object { $serial -and ([string]$_.SerialNumber).Trim() -eq $serial })
                                if ($logicalDisks.Count -ne 1) { throw "Cannot uniquely map SSD $($disk.FriendlyName) to a disk; no trim performed for it" }
                                $volumes = @($logicalDisks[0] | Get-Partition | Get-Volume | Where-Object DriveLetter)
                                foreach ($volume in $volumes) { Optimize-Volume -DriveLetter $volume.DriveLetter -ReTrim -ErrorAction Stop }
                            }
                            $detail = "SSD retrim inspected $($ssds.Count) physical disk(s)"
                        }
                    }
                    'Temporary' {
                        $root = if ($System) { Join-Path $windowsRoot 'Temp' } else { $env:TEMP }
                        # Canonical allowlist, independent of a custom TEMP pointing at user documents.
                        $allowed = if ($System) { Join-Path $windowsRoot 'Temp' } else { Join-Path $profileDirectory 'AppData\Local\Temp' }
                        if ([IO.Path]::GetFullPath($root).TrimEnd('\') -ne [IO.Path]::GetFullPath($allowed).TrimEnd('\')) { throw 'Temporary path is outside the maintenance allowlist' }
                        $detail = "Removed $(Clear-MaintenanceTemp $root) bytes"
                    }
                }
                return $detail
            } finally { [void][DotfilesMaintenance.Native]::SetThreadExecutionState($previousExecutionState) }
        }
        $report.After = Get-MaintenanceAnalysis
        $report.Warnings = @($report.After.Warnings)
        Save-MaintenanceReport $state $report -System:$System
        if (@($report.Actions.Values | Where-Object { $_.Status -eq 'failed' }).Count) { exit 1 }
    } finally { if ($operationLock) { $operationLock.Dispose() }; if ($lock) { $lock.Dispose() } }
} finally { $env:PSModulePath = $savedModulePath }
