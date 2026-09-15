# Dotfiles for Windows 11 — Samsung Book NP550XDA

See also the [architecture analysis and diagrams](../docs/architecture.md),
covering the modifications to the base system and the installers' limitations.

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

Requires **Developer Mode** enabled (Settings → Privacy &
security → For developers) to create symlinks without being
an administrator — the same idea as `omarchy.pl`, which also never changes anything
by default when a conflicting file exists.

See what would be done, without touching anything:

```powershell
pwsh ./win11.ps1 -DryRun -All
```

Install while preserving existing files in
`$env:USERPROFILE\.local\state\dotfiles\backups\`:

```powershell
pwsh ./win11.ps1 -Backup
```

**Known limitation:** `-Restore` selects the most recent backup, but does not
reuse the installation's destination map and can restore files to the
wrong location. See the [restore analysis](../docs/architecture.md#installation-conflicts-and-restore-scope)
before using this option; it is not a reliable reversal:

```powershell
pwsh ./win11.ps1 -Restore
```

The steps can also run separately with `-Fonts` (Lexend + JetBrainsMono Nerd
Font, per-user, no admin), `-Theme` (Windows Terminal color scheme,
wallpaper, and the recolored Rainmeter skin), or `-Apps` (`winget install` for
GlazeWM, Windows Terminal, PowerToys, Starship, and Rainmeter). For everything at
once:

```powershell
pwsh ./win11.ps1 -All -Backup
```

`-Fonts`, `-Theme`, and `-Apps` only run against the real `$HOME`; `-Target` is
only for testing symlink creation in another directory.

If symlink creation fails even with Developer Mode enabled in the
registry (`AllowDevelopmentWithoutDevLicense`), the privilege sometimes only
applies to normal interactive sessions — automated/non-interactive
sessions may not inherit it. In that case, run elevated:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-File .\win11.ps1 -All -Backup'
```

## Desktop widgets (Rainmeter)

For the "SAO HUD" desktop aesthetic (the visual equivalent of
Omarchy's Feader-RSS), `home/rainmeter/AincradHUD/HUD.ini` is a single
panel vendored in this repo (no download at install time, no
third-party license dependency): clock, HP (CPU load), MP
(free memory), inventory (free space on the C: drive), and network
uplink/downlink, with HUD-style borders and a red alert when CPU/RAM go
above ~80% or the disk drops below 15% free.

`win11.ps1 -Backup` symlinks the whole folder to
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
