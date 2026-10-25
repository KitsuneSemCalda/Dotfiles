# Shared functions; importing this file performs no maintenance. PowerShell 5.1.
function Get-MaintenanceWeek {
    param([datetime]$Now = (Get-Date))
    return $Now.Date.AddDays(-[int]$Now.DayOfWeek).ToString('yyyy-MM-dd')
}

function Test-MaintenanceWindow {
    param([datetime]$Now, $AC, $IdleSeconds)
    return ($Now.Hour -ge 3 -and $Now.Hour -lt 6 -and $AC -eq $true -and
        $null -ne $IdleSeconds -and $IdleSeconds -ge 900)
}

function New-MaintenanceTaskTemplates {
    $trigger = New-ScheduledTaskTrigger -Daily -At '03:00'
    $trigger.Repetition = New-CimInstance -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName MSFT_TaskRepetitionPattern -ClientOnly -Property @{
        Interval='PT15M'; Duration='PT3H'; StopAtDurationEnd=$false
    }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfIdle -IdleDuration (New-TimeSpan -Minutes 15) -IdleWaitTimeout (New-TimeSpan -Hours 3) -DontStopOnIdleEnd -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::Zero)
    $userTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 15)
    $userSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::Zero)
    return @{ SystemTrigger=$trigger; SystemSettings=$settings; UserTrigger=$userTrigger; UserSettings=$userSettings }
}

function Initialize-MaintenanceNative {
    if ('DotfilesMaintenance.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[assembly: DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
namespace DotfilesMaintenance {
  public static class Native {
    [StructLayout(LayoutKind.Sequential)] public struct PowerStatus {
      public byte AC, BatteryFlag, BatteryPercent, Reserved;
      public uint LifeTime, FullLifeTime;
    }
    [StructLayout(LayoutKind.Sequential)] struct Session {
      public uint Id; public IntPtr Name; public int State;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Info {
      public int State; public uint Id, InBytes, OutBytes, InFrames, OutFrames, InCompressed, OutCompressed;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Station;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=17)] public string Domain;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=21)] public string User;
      public long Connect, Disconnect, LastInput, Logon, Current;
    }
    [DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out PowerStatus status);
    [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
    [DllImport("wtsapi32.dll")] static extern bool WTSEnumerateSessions(IntPtr server, int reserved, int version, out IntPtr data, out int count);
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode)] static extern bool WTSQuerySessionInformation(IntPtr server, uint session, int kind, out IntPtr data, out int bytes);
    [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr data);
    [DllImport("powrprof.dll")] public static extern uint PowerGetUserConfiguredACPowerMode(out Guid mode);
    [DllImport("powrprof.dll")] public static extern uint PowerGetUserConfiguredDCPowerMode(out Guid mode);
    [DllImport("powrprof.dll")] public static extern uint PowerSetUserConfiguredACPowerMode(ref Guid mode);
    [DllImport("powrprof.dll")] public static extern uint PowerSetUserConfiguredDCPowerMode(ref Guid mode);
    public static double IdleSeconds() {
      IntPtr data; int count; double idle = Double.MaxValue; bool found=false;
      if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out data, out count)) return -1;
      try {
        for (int i=0; i<count; i++) {
          Session session=(Session)Marshal.PtrToStructure(IntPtr.Add(data, i*Marshal.SizeOf(typeof(Session))), typeof(Session));
          if (session.State != 0) continue; // WTSActive
          IntPtr detail; int size;
          if (!WTSQuerySessionInformation(IntPtr.Zero, session.Id, 24, out detail, out size)) return -1;
          try {
            if (size < Marshal.SizeOf(typeof(Info))) return -1;
            Info info=(Info)Marshal.PtrToStructure(detail, typeof(Info));
            if (info.LastInput <= 0 || info.Current < info.LastInput) return -1;
            idle=Math.Min(idle, (info.Current-info.LastInput)/10000000.0); found=true;
          } finally { WTSFreeMemory(detail); }
        }
      } finally { WTSFreeMemory(data); }
      return found ? idle : -1;
    }
  }
}
'@
}

function Get-MaintenanceConditions {
    Initialize-MaintenanceNative
    $power = New-Object DotfilesMaintenance.Native+PowerStatus
    $ac = $null
    if ([DotfilesMaintenance.Native]::GetSystemPowerStatus([ref]$power) -and $power.AC -ne 255) {
        $ac = ($power.AC -eq 1)
    }
    $idle = [DotfilesMaintenance.Native]::IdleSeconds()
    if ($idle -lt 0) { $idle = $null }
    return @{ AC = $ac; IdleSeconds = $idle }
}

function Get-MaintenanceWinget {
    $package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller | Where-Object { $_.PublisherId -eq '8wekyb3d8bbwe' } | Select-Object -First 1
    if (-not $package) { throw 'Microsoft App Installer/winget unavailable for this user' }
    $trusted = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'WindowsApps'
    $path = Join-Path $package.InstallLocation 'winget.exe'
    if (-not [IO.Path]::GetFullPath($path).StartsWith($trusted.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $path)) { throw 'winget is outside its trusted WindowsApps installation' }
    return $path
}

function Write-MaintenanceJson {
    param([string]$Path, $Data)
    $Data | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$Path.tmp" -Encoding UTF8
    Move-Item -LiteralPath "$Path.tmp" -Destination $Path -Force
}

function Read-MaintenanceProgress {
    param([string]$Path)
    $result = @{ Week = ''; Done = @(); Diagnosed = '' }
    if (Test-Path -LiteralPath $Path) {
        $saved = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        foreach ($property in $saved.PSObject.Properties) { $result[$property.Name] = $property.Value }
    }
    return $result
}

function Invoke-MaintenanceSteps {
    param([string[]]$Phases, [hashtable]$Progress, [string]$ProgressPath,
          [scriptblock]$Eligible, [scriptblock]$Execute)
    $actions = [ordered]@{}
    foreach ($phase in $Phases) {
        if ($Progress.Done -contains $phase) { continue }
        if (-not (& $Eligible)) {
            $actions[$phase] = @{ Status='pending'; Detail='Outside maintenance conditions' }; break
        }
        try {
            $detail = & $Execute $phase
            $actions[$phase] = @{ Status='ok'; Detail=$detail }
            $Progress.Done = @($Progress.Done) + $phase
            Write-MaintenanceJson $ProgressPath $Progress
        } catch {
            $actions[$phase] = @{ Status='failed'; Detail=$_.Exception.Message }
            if ($phase -eq 'WindowsUpdate' -or $phase -eq 'Applications') { break }
        }
    }
    return $actions
}

function Clear-MaintenanceTemp {
    param([string]$Root, [datetime]$Now = (Get-Date))
    if (-not (Test-Path -LiteralPath $Root)) { return 0L }
    $rootItem = Get-Item -LiteralPath $Root -Force
    if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { return 0L }
    $parent = $rootItem.Parent
    while ($parent) {
        if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { return 0L }
        $parent = $parent.Parent
    }
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($rootItem.FullName)
    $bytes = 0L
    while ($queue.Count) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction SilentlyContinue)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            # Only top-level regular files: never traverse a mutable temp directory tree as SYSTEM.
            if ($item.PSIsContainer) { continue }
            if ($item.LastWriteTime -ge $Now.AddDays(-7) -or $item.LastAccessTime -ge $Now.AddDays(-7) -or $item.CreationTime -ge $Now.AddDays(-7)) { continue }
            try {
                $size = $item.Length
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                $bytes += $size
            } catch { } # Locked/inaccessible temporary files are left for a later run.
        }
    }
    return $bytes
}

function Get-MaintenanceAnalysis {
    $warnings = @()
    $checks = [ordered]@{}
    $collectors = [ordered]@{
        Volumes = { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, Size, FreeSpace }
        Memory = { Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory }
        Processes = { Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name, WorkingSet64, CPU }
        FailedServices = { Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State='Stopped'" | Select-Object Name, ExitCode }
        Errors = { Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-1) } -MaxEvents 30 -ErrorAction Stop | Select-Object TimeCreated, Id, ProviderName, Message }
        Storage = { Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus }
        Battery = { Get-CimInstance Win32_Battery | Select-Object Name, EstimatedChargeRemaining, BatteryStatus }
        Backup = { Get-ScheduledTask | Where-Object { $_.TaskName -match 'backup|file.?history' } | ForEach-Object { $info = $_ | Get-ScheduledTaskInfo; [pscustomobject]@{ Name=$_.TaskName; LastRun=$info.LastRunTime; Result=$info.LastTaskResult } } }
    }
    foreach ($name in $collectors.Keys) {
        try { $checks[$name] = @{ Status='ok'; Data=@(& $collectors[$name]) } }
        catch { $checks[$name] = @{ Status='unavailable'; Error=$_.Exception.Message } }
    }
    foreach ($volume in @($checks.Volumes.Data)) {
        if ($volume.Size -and ($volume.FreeSpace -lt 10GB -or $volume.FreeSpace / $volume.Size -lt .15)) { $warnings += "Low disk space: $($volume.DeviceID)" }
    }
    foreach ($memory in @($checks.Memory.Data)) {
        if ($memory.TotalVisibleMemorySize -and $memory.FreePhysicalMemory / $memory.TotalVisibleMemorySize -lt .1) { $warnings += 'Memory pressure: less than 10% available' }
    }
    foreach ($disk in @($checks.Storage.Data)) {
        if ($disk.HealthStatus -ne 'Healthy') { $warnings += "Storage health: $($disk.FriendlyName) $($disk.HealthStatus)" }
    }
    if (@($checks.FailedServices.Data).Count -gt 0) { $warnings += 'Stopped automatic services: review report (some may be trigger-start services)' }
    $reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    if ($reboot) { $warnings += 'Windows restart pending' }
    return @{ Time=(Get-Date).ToString('o'); Checks=$checks; Warnings=$warnings; RebootPending=$reboot }
}

function Save-MaintenanceReport {
    param([string]$State, $Report, [switch]$System)
    $lastMaintenance = Join-Path $State 'last-maintenance.json'
    if ($Report.Actions) { Write-MaintenanceJson $lastMaintenance $Report }
    elseif (Test-Path -LiteralPath $lastMaintenance) {
        $saved = Get-Content -LiteralPath $lastMaintenance -Raw | ConvertFrom-Json
        $Report.Actions = [ordered]@{}
        foreach ($property in $saved.Actions.PSObject.Properties) { $Report.Actions[$property.Name] = $property.Value }
        $Report.PreviousMaintenance = $saved.Time
    }
    $reports = Join-Path $State 'reports'
    New-Item -ItemType Directory -Path $reports -Force | Out-Null
    $name = (Get-Date).ToString('yyyyMMdd-HHmmss-fffffff')
    Write-MaintenanceJson (Join-Path $reports "$name.json") $Report
    Write-MaintenanceJson (Join-Path $State 'latest.json') $Report
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add("Time: $($Report.Time)")
    foreach ($warning in @($Report.Warnings)) { $lines.Add("Warning: $warning") }
    $checks = if ($Report.Checks) { $Report.Checks } else { $Report.After.Checks }
    foreach ($volume in @($checks.Volumes.Data)) {
        if ($volume.Size) { $lines.Add(('Volume {0}: {1:N1} GiB free of {2:N1} GiB' -f $volume.DeviceID, ($volume.FreeSpace / 1GB), ($volume.Size / 1GB))) }
    }
    foreach ($memory in @($checks.Memory.Data)) {
        if ($memory.TotalVisibleMemorySize) { $lines.Add(('Memory available: {0:N1}%' -f (100 * $memory.FreePhysicalMemory / $memory.TotalVisibleMemorySize))) }
    }
    foreach ($name in $Report.Actions.Keys) {
        $lines.Add("$name`: $($Report.Actions[$name].Status) - $($Report.Actions[$name].Detail)")
    }
    foreach ($name in $checks.Keys) { $lines.Add("$name`: $($checks[$name] | ConvertTo-Json -Depth 8 -Compress)") }
    $text = $lines -join "`r`n"
    Set-Content -LiteralPath (Join-Path $reports "$name.txt") -Value $text -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $State 'latest.txt') -Value $text -Encoding UTF8
    Get-ChildItem -LiteralPath $reports -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | Remove-Item -Force
    $issues = @($Report.Warnings)
    if ($Report.Actions) {
        $issues += @($Report.Actions.Keys | Where-Object { $Report.Actions[$_].Status -in 'failed','pending' } | ForEach-Object { "$_`: $($Report.Actions[$_].Status)" })
    }
    $signature = (@($issues | Sort-Object -Unique) -join "`n")
    $marker = Join-Path $State 'last-notification.txt'
    $previous = if (Test-Path -LiteralPath $marker) { [IO.File]::ReadAllText($marker) } else { '' }
    if ($signature -ne $previous) {
        try {
        if ($System) {
            Write-EventLog -LogName Application -Source DotfilesMaintenance -EventId 100 -EntryType Information -Message $(if ($signature) { $signature } else { 'Previous maintenance issues resolved' }) -ErrorAction SilentlyContinue
        } else {
            # A native nonmodal notification; no PowerShell Gallery dependency.
            Add-Type -AssemblyName System.Windows.Forms
            $icon = New-Object System.Windows.Forms.NotifyIcon
            try {
                $icon.Icon = [System.Drawing.SystemIcons]::Information
                $icon.Visible = $true
                $icon.ShowBalloonTip(8000, 'Dotfiles maintenance', $(if ($signature) { $signature } else { 'Previous maintenance issues resolved' }), [System.Windows.Forms.ToolTipIcon]::Info)
                Start-Sleep -Seconds 8
            } finally { $icon.Dispose() }
        }
        [IO.File]::WriteAllText($marker, $signature)
        } catch { Write-Warning "Notification unavailable: $($_.Exception.Message)" }
    }
}

function Get-MaintenancePowerModes {
    Initialize-MaintenanceNative
    $ac = [guid]::Empty; $dc = [guid]::Empty
    if ([DotfilesMaintenance.Native]::PowerGetUserConfiguredACPowerMode([ref]$ac) -ne 0 -or
        [DotfilesMaintenance.Native]::PowerGetUserConfiguredDCPowerMode([ref]$dc) -ne 0) { throw 'Power mode API unavailable' }
    return @{ AC=$ac; DC=$dc }
}

function Set-MaintenancePowerMode {
    param([ValidateSet('AC','DC')][string]$Supply, [guid]$Mode)
    Initialize-MaintenanceNative
    $code = if ($Supply -eq 'AC') { [DotfilesMaintenance.Native]::PowerSetUserConfiguredACPowerMode([ref]$Mode) }
        else { [DotfilesMaintenance.Native]::PowerSetUserConfiguredDCPowerMode([ref]$Mode) }
    if ($code -ne 0) { throw "Power mode configuration failed for $Supply ($code)" }
}

function Set-MaintenancePower {
    param([string]$State, [switch]$Restore)
    $path = Join-Path $State 'power.json'
    if ($Restore -and -not (Test-Path -LiteralPath $path)) { return }
    $saved = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } else { $null }
    if (-not $Restore -and $saved -and $saved.Applied) { return }
    $current = Get-MaintenancePowerModes
    $ac = $current.AC; $dc = $current.DC
    $balanced = [guid]::Empty
    $efficient = [guid]'961cc777-2547-4f9d-8174-7d86181b8a7a'
    if ($Restore) {
        if (-not (Test-Path -LiteralPath $path)) { return }
        if ($ac -eq $balanced) { Set-MaintenancePowerMode 'AC' ([guid]$saved.AC) }
        if ($dc -eq $efficient) { Set-MaintenancePowerMode 'DC' ([guid]$saved.DC) }
        Remove-Item -LiteralPath $path
        return
    }
    if (-not $saved) {
        Write-MaintenanceJson $path @{ AC=$ac.ToString(); DC=$dc.ToString(); Applied=$false }
    }
    Set-MaintenancePowerMode 'AC' $balanced
    Set-MaintenancePowerMode 'DC' $efficient
    $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $saved | Add-Member -NotePropertyName Applied -NotePropertyValue $true -Force
    Write-MaintenanceJson $path $saved
}
