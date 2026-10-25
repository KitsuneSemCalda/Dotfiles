# Dotfiles for Windows 11 — Samsung Book NP550XDA

See also the [architecture analysis and diagrams](../docs/architecture.md),
covering the modifications to the base system and the installers' limitations.
The [capture pipeline](../docs/capture.md) documents the Windows OBS profiles,
per-app audio capture, scene setup and benchmark steps.

Initial dotfiles baseline for the same Samsung NP550XDA-KF2BR from the
[Omarchy profile](../Omarchy/README.md), now booting Windows 11. Visual theme
inspired by Sword Art Online, reusing the palette and material from the
[Sword Art Omarchy](https://github.com/KitsuneSemCalda/Sword-Art-Omarchy) theme
already built for Hyprland — so both operating systems share the
same visual identity. The hardware snapshot used for these decisions is at
[`hardware/hardware-profile.txt`](hardware/hardware-profile.txt).

## Rules followed

1. **Main theme: Sword Art Online.** A palette identical to the Omarchy
   theme (background `#08090a`, panel `#16181b`, cyan accent `#3ee8ff`, HP red
   `#ff3b5c`, MP blue `#4f8dff`) applied end to end:
   - Wallpapers and palette: [Sword-Art-Omarchy](https://github.com/KitsuneSemCalda/Sword-Art-Omarchy)
     (the same 3 carbon-texture 4K wallpapers from the original
     theme — `win11.ps1 -Theme` downloads and applies them automatically).
   - Desktop widgets (CPU/RAM/disk/clock/network): **AincradHUD**, a
     single custom Rainmeter skin (`home/rainmeter/AincradHUD`), replacing
     the earlier plan to download and recolor the
     [SAO-Skin-Pack](https://github.com/rensatsu/SAO-Skin-Pack) from a third party.
     Reason for the switch: SAO-Skin-Pack spread the same information across 8
     separate windows (with duplicated CPU/RAM/clock) and its RSS skin
     depended on an external feed that went offline, stalling the
     widget's update. AincradHUD consolidates everything into a single panel,
     with no network dependency. See "Desktop widgets (Rainmeter)" below.
   - Prompt: [Starship](https://starship.rs) (`starship.toml`, already with
     `git_branch`/`git_status` in the palette above) instead of a hand-written
     PowerShell `prompt` function — a native binary, with no need
     to run `git.exe` on every rendered line.
2. **Keep Omarchy's keybinds where possible.** Windows has no native
   tiling compositor, so `GlazeWM` (https://github.com/glzr-io/glazewm,
   FOSS, Rust, the tiling WM for Windows closest to Hyprland/i3) gets a
   configuration with the shortcuts from the
   [Omarchy hotkeys manual](https://omarchy.org/manual/hotkeys/)
   remapped to `SUPER`, with borders in the same palette (focus = cyan accent,
   inactive = theme gray `#4a5058`). Where there is no Windows equivalent
   (`Ctrl+Alt+Del` is reserved by the OS, for example), it is documented rather
   than forced — see the full table further below.

GlazeWM and Rainmeter are the two visual pieces of the setup (windows and desktop
HUD, respectively) and should remain the tools used for
that — any future theme evolution should touch the shared palette
(`#08090a`/`#16181b`/`#3ee8ff`/`#ff3b5c`/`#4f8dff`) rather than swap the
tooling.

## Machine profile

- Intel Core i5-1135G7, 4 cores / 8 threads
- 16 GiB of RAM
- Intel Iris Xe
- 1920×1080 internal display
- Samsung NVMe, approximately 256 GiB
- Windows 11 Home Single Language

## Structure

```text
home/
├── glazewm/config.yaml                  # tiling WM + Omarchy keybinds
├── starship.toml                        # identical to the one used on Omarchy
├── powershell/Microsoft.PowerShell_profile.ps1
├── rainmeter/AincradHUD/HUD.ini         # custom HUD (CPU/RAM/disk/network/clock)
└── windows-terminal/
    └── sword-art-online.scheme.json     # Sword Art Omarchy palette
hardware/
└── hardware-profile.txt
win11.ps1                              # installer and orchestrator
scripts/hardware-profile.ps1             # updates the snapshot (no PII)
scripts/debloat.ps1                      # conservative debloat + optimization
scripts/clamshell.ps1                    # AC/battery lid actions and restore
scripts/ek75-keyboard.ps1                # adds US-International keyboard layout
```

Just like on Omarchy, the configuration files stay in each tool's
native format (YAML for GlazeWM, JSON for Windows Terminal, TOML
for Starship) and PowerShell only handles automation/installation.

## Tools used

All from existing, maintained projects — nothing written from scratch:

| Role on Omarchy         | Tool on Windows                                                  |
|-------------------------|-----------------------------------------------------------------|
| Hyprland (tiling WM)    | [GlazeWM](https://github.com/glzr-io/glazewm)                   |
| Alacritty (terminal)    | Windows Terminal                                                 |
| Starship (prompt)       | Starship (same `starship.toml`)                                  |
| btop                    | [btop4win](https://github.com/aristocratos/btop4win)             |
| Omarchy's menu/launcher | PowerToys Run                                                    |
| Feader-RSS / widgets    | AincradHUD (custom Rainmeter skin — see below)                   |

## App profile

Equivalent to `omarchy.pl`'s `ensure_apps()`: `-Apps`/`-All` also installs,
via `winget`, the personal app profile alongside the theme's tools.

| App           | winget package                   |
|---------------|----------------------------------|
| Steam         | `Valve.Steam`                    |
| Prism Launcher| `PrismLauncher.PrismLauncher`    |
| Git           | `Git.Git`                        |
| Claude        | `Anthropic.Claude`               |
| Codex CLI     | `OpenAI.Codex`                   |
| Bitwarden     | `Bitwarden.Bitwarden`            |
| Obsidian      | `Obsidian.Obsidian`              |
| AppFlowy      | `AppFlowy.AppFlowy`              |
| VS Code       | `Microsoft.VisualStudioCode`     |
| Go            | `GoLang.Go`                      |
| Node.js       | `OpenJS.NodeJS`                  |
| Python        | `Python.Python.3.13`             |
| Lua           | `DEVCOM.Lua`                     |

`-Apps`/`-All` also runs `Install-PowerShellModules`, which installs (via
`Install-Module -Scope CurrentUser`, no admin needed) the modules used by
the profile: `Terminal-Icons` (icons in `Get-ChildItem`), `PSFzf` (Ctrl+T
fuzzy-finds files, Ctrl+R searches history — depends on the `fzf` binary, installed
via `junegunn.fzf` above), and `z` (fast directory jumping by frequency of
use). The profile attempts to load the modules once, on the second call to the
`prompt` function, and initializes Starship at that same moment. Subsequent calls
use the prompt installed by Starship. It does not use `PowerShell.OnIdle`.

## Automatic maintenance

`pwsh ./win11.ps1 -Maintenance -Backup` enables daily diagnosis, power preferences
and weekly automatic maintenance; `-All` includes it. Updates run between 03:00
and 06:00 from Sunday onward, on AC and after 15 minutes idle. Missed windows
retry the next night. No passwords are saved and no reboot is requested.
The independent Windows Update service retains its own reboot behavior.

The scripts are copied to `%ProgramFiles%\DotfilesMaintenance`. Run its
`maintenance.ps1 -Mode Simulate`, `-Mode Status` or `-Mode Disable` to inspect
eligibility, read reports or disable future runs. See [maintenance commands,
security boundaries and limits](../docs/maintenance.md).

## Debloat and optimization

`scripts/debloat.ps1` is intentionally conservative and built from
the **actual** `Get-AppxPackage` output on this machine (not a generic list downloaded from
the internet) — that's why it doesn't touch Defender, Windows Update, OneDrive, Edge,
WSL, Dev Home, anything from Samsung (it can control real hardware), or
apps clearly installed on purpose (Claude, ChatGPT Desktop, Dropbox,
Spotify). What it does:

- Removes bloatware not used in this profile: Clipchamp, Bing News/Weather,
  Get Help, Solitaire Collection, Feedback Hub, the new Outlook, Teams
  (consumer), Copilot, and Family Safety.
- Disables (does not delete — reversible with `Enable-ScheduledTask`) known
  telemetry/diagnostics scheduled tasks (Compatibility Appraiser,
  CEIP, Disk Diagnostic, Feedback, Error Reporting).
- Enables Storage Sense (automatic cleanup of Windows temp files).
- Cleans `%TEMP%`, `C:\Windows\Temp`, and the Recycle Bin.

Disabling the system tasks requires administrator rights; if run without
elevation, the script relaunches itself elevated (`-Verb RunAs`) and prompts
for UAC confirmation.

```powershell
pwsh ./scripts/debloat.ps1              # just shows what would be done
pwsh ./scripts/debloat.ps1 -Apply       # actually applies it (prompts UAC)
```

## Keybinds: Omarchy → Windows (GlazeWM)

| Omarchy shortcut        | Action                        | On Windows                                |
|-------------------------|-----------------------------|------------------------------------------|
| `Super+Return`          | Terminal                    | `Super+Return` → Windows Terminal        |
| `Super+W` / `Super+Q`   | Close window                | same                                      |
| `Super+T`               | Toggle tiling/floating       | same                                      |
| `Super+F`               | Fullscreen                  | same                                      |
| `Super+Arrow`           | Move focus                  | same (+ `Super+HJKL` as a bonus)          |
| `Super+Shift+Arrow`     | Swap window positions        | same                                      |
| `Super+1..4`            | Go to workspace              | `Super+1..9` (GlazeWM allows more)        |
| `Super+Shift+1..4`      | Move window to workspace     | `Super+Shift+1..9`                        |
| `Super+Tab` / `+Shift`  | Next/previous workspace      | same                                      |
| `Super+Ctrl+Tab`        | Previous workspace           | same                                      |
| `Super+Ctrl+L`          | Lock screen                  | same (Windows also has native `Win+L`)    |
| `Super+Ctrl+T`          | Activity monitor             | `Super+Ctrl+T` → Task Manager             |
| `Super+Ctrl+D`          | Display panel                | `Super+Ctrl+D` → Display settings         |
| `Super+Ctrl+A`          | Audio panel                  | `Super+Ctrl+A` → Sound settings           |
| `Super+Ctrl+P`          | Power panel                  | `Super+Ctrl+P` → Power settings           |
| `Super+Shift+Return`    | Browser                     | same (opens the default browser)          |
| `Super+Shift+F`         | File manager                 | `Super+Shift+F` → Explorer                |
| `Super+Shift+N`         | Editor                       | `Super+Shift+N` → VS Code (swap freely)   |
| `Super+Shift+R`         | Reload config                | same                                      |

No direct Windows equivalent (documented, not forced):

- `Super+Space` (Omarchy menu) → the launcher here is **PowerToys Run**.
  Set its shortcut to `Win+Space` in PowerToys → PowerToys Run →
  "Activation shortcut" (the factory default is `Alt+Space`). Since Windows
  uses `Win+Space` to switch keyboard language by default, disable that
  combination under Settings → Time & language → Input → Advanced
  keyboard shortcuts, or PowerToys Run will not open.
- `Super+Escape` (system menu) — no equivalent native panel.
- `Ctrl+Alt+Del` (close all windows) — reserved by Windows
  (Secure Attention Sequence); no app can intercept it.
- `Super+C` / `Super+V` (copy/paste) — Windows already uses `Ctrl+C`/`Ctrl+V`
  globally; remapping this would break the rest of the system.

GlazeWM also gains a few extra shortcuts that don't exist on Omarchy
(`Super+M` minimize, `Super+V` toggle tiling direction, `Super+R` resize
mode, `Super+Shift+X` exit GlazeWM) — all documented as comments in
`home/glazewm/config.yaml` itself.

## Installation

### EK75 and Fifine K688

The notebook's built-in keyboard is ABNT2 and the EK75 is ANSI. Add the
United States-International layout without removing existing layouts:

```powershell
pwsh ./win11.ps1 -Ek75 -Backup
```

Use `Win+Space` to select United States-International when typing on the EK75,
and return to Portuguese (Brazil) ABNT2 when typing on the notebook. Windows
does not assign these layouts to individual keyboards through this setup; the
active layout applies to both. `-Ek75` is separate from `-All` because it adds
a user keyboard layout. The EK75's RGB and macros can be configured with
the [official DAREU EK75 Windows driver](https://dareu.com/pt/pages/driver).
The Linux `--ek75-knob` rule does not apply on Windows; if the volume knob
misfires here too, first check the keyboard firmware and driver before making
system-wide media-key remaps.

Connect the Fifine K688 by USB. In **Settings → System → Sound → Input**,
select the `fifine Microphone` recording device, then check its level and the
microphone's physical mute and gain controls. In OBS, select the same device
for the microphone source. Leave the K688 playback device unselected unless
headphones are plugged into the microphone for direct monitoring. The K688
was not connected during this setup, so its Windows device ID and input level
have not been measured.

### Closed-lid use with an external monitor

Connect an external monitor, keyboard and mouse, and keep the notebook on a
hard, ventilated surface. To keep Windows running when the lid closes **on AC
power**, while retaining sleep on battery, run:

```powershell
pwsh ./win11.ps1 -Clamshell -Backup
```

The `-Clamshell` action is separate from `-All`, because Windows' lid setting
is per power source, not conditional on whether a monitor is attached. On AC,
closing the lid will also keep the machine running if the monitor is unplugged.
Lock or sleep it manually before packing it away. For an external-only desktop,
select **Second screen only** with `Win+P`. To return to the old lid actions, run
`pwsh ./scripts/clamshell.ps1 -Restore`. The original AC and battery values are
saved under `%LOCALAPPDATA%\dotfiles\clamshell-power.json` for the active power
scheme. The dotfile installer's `-Restore` concerns copied files and does not
restore Windows power settings.

Use `pwsh ./scripts/clamshell.ps1` to inspect the active scheme's lid actions.
Some Windows installations require an elevated terminal to change power
settings; if `powercfg` denies access, rerun the command as administrator.
`-DryRun -Clamshell` prints the planned action without changing it.

Installs independent copies of configuration files and the Rainmeter skin.
Developer Mode is not required. Legacy links to this checkout are replaced
when you rerun the installer. The clone can be removed afterward; rerun the
installer from an updated clone to update installed copies. Local edits are
protected by content checks recorded in `.local/state/dotfiles/installed-windows.json`.

See what would be done, without touching anything:

```powershell
pwsh ./win11.ps1 -DryRun -All
```

Install while preserving existing files in
`$env:USERPROFILE\.local\state\dotfiles\backups\`:

```powershell
pwsh ./win11.ps1 -Backup
```

Restore the most recent backup with a readable, nonempty manifest. Backup
directories have unique names even when two installations start within the
same second. Each backed-up item's real destination and a
post-install content hash are recorded in that backup's `manifest.json`, so
restore writes to the same paths `-Backup` originally moved them from and
aborts with no changes if any destination was modified after installation.
An interrupted installation may leave a partial backup; its recorded items
remain available for restore. Empty backup directories are skipped.
See the [restore details](../docs/architecture.md#installation-conflicts-and-restore-scope)
for the full mapping:

```powershell
pwsh ./win11.ps1 -Restore
```

The installer also runs [`Skill-Library/install.ps1`](../../Skill-Library/README.md)
after the copies, installing every skill from the library into every AI
agent CLI detected on this machine (`.claude`, `.codex`, `.config/opencode`
under `$env:USERPROFILE`). This is a native PowerShell port of the Perl
installer used on the Omarchy side, with no Perl dependency on Windows. Like
the copies, it is unconditional (not behind a flag), but only runs against
the real `$HOME` — it is skipped when `-Target` points elsewhere for testing.

The steps can also run separately with `-Fonts` (Lexend + JetBrainsMono Nerd
Font, per-user, no admin), `-Theme` (Windows Terminal color scheme,
wallpaper, and the recolored Rainmeter skin), or `-Apps` (`winget install` for
GlazeWM, Windows Terminal, PowerToys, Starship, Rainmeter, and `fzf`, plus the
[personal app profile](#app-profile) and PowerShell modules above; already-installed
packages are skipped, and any real `winget install` failure aborts before the
final success message). For everything at once:

```powershell
pwsh ./win11.ps1 -All -Backup
```

`-Fonts`, `-Theme`, and `-Apps` only run against the real `$HOME`; `-Target` is
only for testing file installation in another directory.

JetBrainsMono Nerd Font is pinned to an explicit
[nerd-fonts release](https://github.com/ryanoasis/nerd-fonts/releases)
(`$nerdFontsVersion` in `Install-NerdFont`) instead of `.../releases/latest`,
so re-running `-Fonts` always installs the same build. To deliberately
upgrade it, bump `$nerdFontsVersion` to the new tag and re-run `-Fonts`.

## Desktop widgets (Rainmeter)

For the "SAO HUD" desktop aesthetic (the visual equivalent of
Omarchy's Feader-RSS), `home/rainmeter/AincradHUD/HUD.ini` is a single
panel vendored in this repo (no download at install time, no
third-party license dependency): clock, HP (CPU load), MP
(free memory), inventory (free space on the C: drive), and network
uplink/downlink, with HUD-style borders and a red alert when CPU/RAM go
above ~80% or the disk drops below 15% free.

`win11.ps1 -Backup` copies the whole folder to
`Documents\Rainmeter\Skins\AincradHUD` (the same mechanism as the other
config files, just on a folder instead of a single file). `-Theme` activates
the skin (`Active=1` + `AlwaysOnTop=1` in `Rainmeter.ini`) and deactivates
any leftover from an old third-party package at
`Sword Art Online\SAO *`, if present — that package (separate skins for
CPU/RAM/clock/disk/battery/RSS, no recolor, with an RSS skin
pointing to a feed that went offline) was discontinued in this repo in favor
of the single panel.

## Updating the hardware snapshot

```powershell
pwsh ./scripts/hardware-profile.ps1            # prints to screen
pwsh ./scripts/hardware-profile.ps1 -Save      # writes hardware/hardware-profile.txt
```

Unlike the `inxi -Fz` used on Omarchy, this script uses CIM/WMI
directly and never includes owner email, product key, or network
data — only what's needed for configuration decisions (CPU, RAM, GPU,
disk, battery).
