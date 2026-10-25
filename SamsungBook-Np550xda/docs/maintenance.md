# Automatic analysis and maintenance

Both profiles support local rules without an AI provider or API key. The runner
does not upload diagnostic reports; existing backup tools may include their
local state folders. Install with `omarchy.pl --maintenance --backup` or
`win11.ps1 -Maintenance -Backup`. Both complete-install options (`--all`/`-All`)
include maintenance; ordinary file installation does not enable it.

Installation enables future scheduling and configures balanced power on AC and
power saving on battery. It does not immediately install updates. Power settings
are saved before changes and restored on disable only where they still match the
values installed by this feature. Later manual choices are preserved.

## Schedule and eligibility

The lightweight diagnosis runs at the first scheduler check each local day.
Maintenance is due once per calendar week starting Sunday and is checked every
15 minutes between 03:00 and 06:00 local time. Missed Sundays are retried during
the following nights. The computer must be plugged in and idle for at least
15 minutes. Unknown power or idle information postpones heavy work. Nothing
wakes the machine.

Eligibility is checked again before each phase. A package transaction already
started may finish after 06:00, after unplugging, or after the user returns;
the next phase waits. Linux transactions hold a sleep inhibitor. No routine
requests a reboot, kills an application, or restarts the desktop shell.
Vendor installers and the independent Windows Update service retain their own
behavior; this feature cannot promise a machine-wide ban on reboots, especially
on Windows Home.

Omarchy uses UPower and logind, with a fallback to the shell's `idle status` IPC.
The fallback requires an active idle cycle and estimates a conservative idle
duration from its configured timeout and latest cycle event. **Stay Awake
disables that signal and therefore postpones heavy maintenance.** The daily
diagnosis still runs. A graphical session must exist for this user timer;
lingering is not enabled. On Windows, WTS session input timestamps cover active
console/remote sessions; unavailable timestamps postpone maintenance. User app
updates need the user's logged-on session. No passwords are stored.

## Diagnosis and actions

Reports collect free space, available memory, resource-heavy process names,
recent system errors, stopped/failed services, battery data, update availability,
and existing backup job results. Missing permissions, unsupported hardware and
missing tools are reported as unavailable, rather than interpreted as healthy.
Linux SMART checks use smartmontools; Windows uses Storage cmdlets. Neither
can guarantee the future reliability of a disk. Stopped Windows automatic
services include legitimate trigger-start services and are recommendations,
not instructions to disable or restart them.

Warnings include volumes below 15% free or 10 GiB free and memory below 10%
available. Updates need at least 10 GiB on the system volume; native updaters
may impose higher requirements. Cleanup can still run when space is low.

- Linux: clean old `/tmp` and `/var/tmp` entries using systemd-tmpfiles and
  old thumbnail-cache files. Package pruning keeps two versions when the native
  `paccache.timer` does not already own the job. Reuse an enabled `fstrim.timer`;
  otherwise perform trim during the maintenance window.
- Windows: delete only top-level regular files older than seven days in the
  account's standard local Temp directory and Windows Temp. Recent, accessed,
  locked or reparse entries are preserved. Custom Temp locations are skipped.
  Reuse enabled ScheduledDefrag; otherwise retrim healthy SSD volumes.
- Downloads, personal files, projects, credentials and the Recycle Bin are not
  cleanup targets. Orphan packages, failed services and startup changes are
  recommendations; there is no automatic debloat or service disabling.

## Updates and recovery

Linux follows the packaged Omarchy update order: prune, snapshot, keyrings,
system packages, migrations, post-update hooks, AUR and mise. Flatpak system
and user installations follow when present. It calls native Omarchy helpers
by phase and deliberately omits the interactive restart stage. Snapshots are
required before package changes. No partial `pacman -Su` update is introduced.
The development-checkout updater is not used: `/usr/share/omarchy` is the
supported distribution layout.

Only fixed root operations are exposed through a root-owned helper and sudo
policy. User migrations and hooks remain in the user context; a private `sudo
-n` adapter prevents background password prompts. **If a migration or hook
needs additional administrative operations, the routine reports a failure and
waits for an interactive `omarchy update` instead of granting generic sudo.**
After resolving the problem, completed phases remain recorded and the next
window resumes the pending work. Distribution migrations and user hooks can
themselves change configuration or restart services as part of their normal
behavior; inspect them when an update needs intervention.

Windows uses the built-in Windows Update Agent COM API for assigned software
updates, excluding optional/preview updates, drivers and feature upgrades.
App updates use Microsoft's installed winget binary, silent mode and no
interactive prompts. Default package pins are respected. Firmware flashing,
optional drivers and major Windows version changes remain manual. Linux
firmware/microcode *packages* remain part of normal complete system updates;
no BIOS/UEFI flashing command runs.

Each phase records success or failure independently. Completed phases are not
repeated during that week. Package failures block dependent update phases;
independent cleanup failures do not hide or prevent other maintenance.
Concurrent routine instances are excluded, and Linux also shares Omarchy's
manual-update lock. Existing package-manager locks are never deleted.
Review the report and native updater output after failures; there is no
automatic rollback of packages or deletion of conflicting packages.

## Commands and reports

Omarchy:

```bash
dotfiles-maintenance simulate   # no files or settings changed
dotfiles-maintenance analyze    # collect a report now
dotfiles-maintenance status
dotfiles-maintenance run        # still requires the maintenance conditions
dotfiles-maintenance disable    # stop future runs and restore owned power settings
dotfiles-maintenance enable
systemctl --user status dotfiles-maintenance.timer
```

Reports are under `${XDG_STATE_HOME:-~/.local/state}/dotfiles-maintenance/`.
The root helper is `/usr/local/libexec/dotfiles-maintenance-root`; scripts and
systemd units are copied into root-owned locations and do not depend on the
checkout. Disabling does not delete reports or interrupt an active package
transaction. It leaves the fixed helper and sudo policy installed for re-enable.

Windows (PowerShell; elevate for installation, disable and protected-state runs):

```powershell
$maintenance = Join-Path $env:ProgramFiles 'DotfilesMaintenance\maintenance.ps1'
& $maintenance -Mode Simulate
& $maintenance -Mode Analyze
& $maintenance -Mode Status
& $maintenance -Mode Run
& $maintenance -Mode Disable
& $maintenance -Mode Install  # re-enable
```

The protected installation is in Program Files. SYSTEM reports are under
`%ProgramData%\DotfilesMaintenance\system`; elevated user reports are under
`%ProgramData%\DotfilesMaintenance\user-<SID>`. A manual non-elevated diagnosis
uses `%LOCALAPPDATA%\dotfiles\maintenance` instead. `Status` reads both contexts.
Tasks are `DotfilesMaintenance-System`, `DotfilesMaintenance-Applications` and
`DotfilesMaintenance-User`. The system task uses SYSTEM; the app task uses the
same logged-on administrator that installed it, with no saved credentials.
The ordinary user task uses a limited token for diagnosis and user-temp
cleanup: it never deletes user-writable paths as administrator. An elevated
manual `Run` handles app updates; an ordinary `Run` handles user-temp cleanup.
Elevation using another account is rejected. Executables, modules and elevated
state use protected paths.

Each run produces JSON plus a text report, with the last result at `latest.*`.
Reports retain 90 days. Notifications appear only when the set of problems
changes, including recovery. Windows system changes are recorded in the
Application event log with source `DotfilesMaintenance`; user results use a
native notification. Disabling stops new phases without killing transactions.
Linux phase output is bounded to its final 24,000 bytes, so verbose AUR builds
do not accumulate their entire output in memory.

## Validation

Tests simulate updates and cover time windows, missing power/idle data, missed
windows, cleanup boundaries, links, low disk space, partial failures and resume.
Windows tests also build task definitions without registering them and compile
the native interop declarations. CI runs Windows PowerShell 5.1 and PowerShell 7.
Real Windows Update, WTS and task registration require validation on a Windows
machine; Linux-hosted PowerShell tests do not establish those behaviors.

Official API references: [Windows Update Agent](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/portal-client),
[winget upgrade](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade),
and [Windows power mode APIs](https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-powersetuserconfigureddcpowermode).
