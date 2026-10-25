# Dotfiles for Omarchy — Samsung Book NP550XDA

See also the [architecture analysis and diagrams](../docs/architecture.md),
covering the modifications to the base system and the installers' limitations.
The [capture pipeline](../docs/capture.md) documents OBS profiles, PipeWire
audio buses, scene setup, hardware limits and benchmark steps.
For OmaTuber and OBS browser support, close OBS and run
`perl ./omarchy.pl --omatuber --backup` (also included in `--all`). See the
[OmaTuber first-use steps](../docs/capture.md#omatuber-no-omarchy).

Dotfiles for the Samsung NP550XDA-KF2BR, running Omarchy with
Hyprland. The full snapshot used to make these decisions is at
[`hardware/inxi-Fz.txt`](hardware/inxi-Fz.txt).

## Machine profile

- Intel Core i5-1135G7, 4 cores / 8 threads
- 16 GiB of RAM
- Intel Iris Xe (`i915`)
- 1920×1080 internal display
- Samsung NVMe, 256 GB (about 238.5 GiB)
- Battery capacity observed at 30.7% of design capacity
- Btrfs filesystem with swapfile and zram

The current choices follow this profile: scale 1, shell font size 14,
terminal font size 11, preferred monitor mode and EDID color management for
the internal BOE panel, plus moderate visual effects for the Iris Xe.
GTK and the fontconfig minimum remain at 20; the shell and terminal settings
do not impose a common physical font size across applications.
The power profile is left to Omarchy's own
`omarchy powerprofiles init`, which already runs at session start and picks
`power-saver` or `balanced`/`performance` from the AC/battery signal.

## Closed-lid use with an external monitor

The desk's Samsung SMB2030N (serial HXOZB03691) has an explicit rule in
`home/.config/hypr/monitors.lua`, matched by its description rather than its HDMI
port: 1600×900 at 60 Hz, scale 1, SDR sRGB, 8-bit output and VRR off. Its EDID
lists 1600×900 as preferred even though it also accepts 1080p signals. Other
external monitors retain the generic preferred-mode rule. This establishes the
display configuration; it is not a measured color calibration. No measured ICC
profile is installed, and brightness/contrast could not be controlled through
DDC/CI on the tested connection.

Omarchy already handles clamshell mode: with an external monitor connected,
closing the lid disables the internal panel and keeps the session on the external
screen; opening the lid enables the panel again. Without an external screen,
closing the lid on battery locks and suspends the notebook. On AC it stays awake
even if HDMI temporarily disappears. Connect an external keyboard and
mouse and keep the notebook on a hard, ventilated surface. The internal `eDP-1`
monitor rule stays on one line because Omarchy's clamshell helper reads its
scale and position when it restores the panel. The expected internal scale is 1.

To check after installation, connect the monitor and run `hyprctl monitors all`.
Close and reopen the lid, then confirm that `eDP-1` returns at scale 1. The
stock shortcut `Super+Ctrl+Delete` toggles the internal display manually when an
external display is active. Omarchy's monitor watcher recovers the internal
panel if the external display disappears.

`--clamshell` (included in `--all`) installs
`/etc/systemd/logind.conf.d/60-dotfiles-clamshell.conf`: suspend when undocked
on battery, and ignore the lid on AC power or when docked. It checks for Omarchy's
lid and monitor helpers and validates Hyprland before installing the policy.
The installer reloads logind to apply settings. Check effective settings with
`systemd-analyze cat-config systemd/logind.conf`.

`--clamshell` also enables the user timer `dotfiles-clamshell-recover.timer`.
Every five seconds it invokes Omarchy's own clamshell reconciliation under the
same lock as the stock monitor watcher. This recovers missed lid/display state
changes even if that watcher exits. Each run is limited to 20 seconds, and the
timer stops with the graphical session. If an enabled output has no valid video
mode, it also retries a Hyprland reload at most once per minute, respecting
Omarchy's reload guard. It does not wake valid displays that are idle. A black
display that still reports a valid mode cannot be diagnosed by this check alone.
On attach or lid transitions it focuses the external display, preferring the
desk Samsung, and enables its DPMS when the lid is closed. It leaves focus and
DPMS alone between transitions.
Check it with `systemctl --user status dotfiles-clamshell-recover.timer` and
`journalctl --user -u dotfiles-clamshell-recover.service`.

## Connected hardware setup

Install the setup tools and capture a hardware inventory:

```sh
perl omarchy.pl --backup --calibrate --clamshell
calibrate-devices
```

`--calibrate` is included in `--all`; installation records an inventory without
opening interactive windows. Run `calibrate-devices` in a terminal after
connecting new devices. Its menu covers monitors (advertised modes and scale),
mouse/touchpad (per-device sensitivity and natural scrolling), audio/microphone
(default devices, profiles and levels through pavucontrol), webcam (preview,
formats and supported controls through qv4l2), and Bluetooth pairing.
The inventory also includes USB and PCI devices; unsupported hardware needs
its own setup rather than guessed settings.

Monitor and pointer adjustments are stored outside the managed dotfiles in
`~/.config/dotfiles-hardware/`. Changes require confirmation within 15 seconds;
unconfirmed or invalid changes are reverted. Omarchy's display toggles load
after these overrides so clamshell recovery continues working. Audio settings
are managed by WirePlumber; webcam control persistence depends on the camera
and application. Color measurement requires a colorimeter and a measured
profile; EDID color handling is not a measured calibration.

The Compose file keeps locale sequences and Omarchy emoji shortcuts, then
maps acute + c/C to ç/Ç. The session explicitly selects this Compose file and
GTK/Qt composition modules. Log out and back in after installation, then test
`ç Ç á é ã õ` in GTK, Qt and Chromium applications.

## EK75 keyboard and Fifine K688 microphone

The internal notebook keyboard uses `br/abnt2`; both observed EK75 interfaces
use `us/intl` through `home/.config/hypr/input.lua`. `--ek75-knob` suppresses
the faulty volume/mute knob events on the EK75's secondary USB interface, and
`--openrgb` installs the EK75 lighting integration. Both options are included
in `--all`. The EK75 receiver currently identifies as USB `260d:0042`.

Connect the Fifine K688 over USB, then run `select-k688-microphone`. It finds
the live Fifine input node and makes it the default recording source through
WirePlumber. If the recording buses were already started, run
`systemctl --user restart capture-audio.service` so `capture_microphone` follows
the K688 instead of the earlier source. The K688 was not connected during this
setup, so its input level and mute state still need a recording check.

The customized `kitsuneforgering.audio` panel hides the `capture_*` buses and
their `loopback-*` streams from **the Omarchy audio panel only**. They remain
available to OBS, `pavucontrol`, and application routing. Its complete source
is in `home/.config/omarchy/plugins/kitsuneforgering.audio/`; the normal dotfile
copy and `--plugin` install it directly from this repository. No separate
GitHub repository is needed. The panel is a copy of Omarchy's built-in audio
plugin; when Omarchy updates that plugin, compare its changes before updating
this copy.

## Structure

```text
home/
├── .aliasrc                 # Bash aliases for Codex and Claude via ai-memory
├── .config/
│   ├── alacritty/alacritty.toml
│   ├── btop/btop.conf
│   ├── fontconfig/fonts.conf   # Lexend as sans-serif
│   ├── gtk-3.0/settings.ini
│   ├── gtk-4.0/settings.ini
│   ├── hypr/                   # Omarchy's native Lua configuration
│   ├── omarchy/rss-reader.json # Feader-RSS feeds
│   ├── omarchy/shell.json      # saved bar layout, adapted for Glass
│   ├── omarchy/plugins/kitsuneforgering.audio/ # audio picker without capture buses
│   ├── omarchy/island.json     # current island preferences
│   ├── omarchy-liquid-glass/   # retained Liquid Glass preferences
│   ├── omarchy/shell.toml      # Omarchy interface base size
│   └── starship.toml
hardware/
└── inxi-Fz.txt
docker/
├── docker-compose.yml           # postgres, redis, frankmd, ai-memory, pihole
└── .env.example                 # documented variables (the real .env stays out of git)
omarchy.pl                       # installer and orchestrator, written in Perl
scripts/hardware-profile.pl     # updates the snapshot via inxi
scripts/docker-stack.pl         # brings up the Docker stack and wires the AI agents
scripts/hooks/pihole-dns-recover.sh       # post-boot hook: re-points resolved at Pi-hole
scripts/hooks/pihole-dns-resume-watch.sh  # systemd --user service: reruns the recovery on every resume
scripts/hooks/pihole-dns-resume.service   # unit installed for the script above
scripts/udev/61-ek75-knob.hwdb             # suppresses the faulty EK75 knob
home/.local/bin/select-k688-microphone      # selects the connected USB input
home/.local/bin/home-dropbox-backup         # local working copy; previews restores
home/.local/bin/home-dropbox-monthly        # local full ZIPs and budgeted cloud essentials
home/.local/bin/backup-zip                  # verified ZIP publication/migration
home/.config/home-dropbox-backup/excludes   # backup exclusions
home/.config/systemd/user/home-dropbox-backup.{service,timer}
home/.config/systemd/user/home-dropbox-monthly.{service,timer}
scripts/btrfs-monthly-backup               # root-only Btrfs send exporter
scripts/systemd/home-btrfs-monthly.{service,timer}
```

Perl is used for the repository's automation and tooling. The
configuration files remain in Lua/TOML because those are Omarchy's and
Hyprland's native formats.

Lexend is applied to the interface via fontconfig and the GTK settings; the
terminal keeps using JetBrainsMono Nerd Font, which is monospaced. The
Lexend files are downloaded by the installer and are not copied into
the repository.

The app profile includes Bitwarden, AppFlowy, PrismLauncher, CurseForge,
ChatGPT Desktop (the official binary repackaged by AUR `chatgpt-desktop`),
Claude Desktop (the pinned official Linux .deb repackaged by the local recipe), and
the web apps Amazon Shopping, Mercado Livre, Pinterest, Z Ai, WebMotors,
Panini Brasil, GitHub, GitLab, Codeberg, Copilot, Grok, and
Gemini. It also removes any previously installed HEY or Basecamp web app and
any 1Password installation (package, AUR package, or browser extension) via
`omarchy remove service`, since neither is part of this profile.
`--apps` and `--all` replace the ChatGPT and Claude web launchers only after both
desktop packages and their commands are present. To run only that migration:
`bash scripts/install-ai-desktops.sh`. The Claude recipe downloads its official
package with a pinned SHA-256; no `.deb` needs to be stored in the repository.
It also registers the [Sword Art Omarchy](https://github.com/KitsuneSemCalda/Sword-Art-Omarchy)
theme. `--plugin` (also `--plugins`) reinstalls three external shell plugins
in the current profile: Feader RSS, Spaces, and
[Glass](https://plugins.omarchy.org/plugin.html?id=kitsuneforgering.glass).
It also validates and enables the local audio panel shipped in this repository.
Spaces replaces the built-in workspace switcher; Glass provides the bar and menu. `SUPER + SPACE`
opens the Glass menu.
Feader RSS feeds live at `~/.config/omarchy/rss-reader.json`.

The saved bar layout under `home/` preserves the current Spaces, media and
island preferences while selecting the Glass menu button and bar.
Older Liquid Glass preferences and Hyprland settings remain in this dotfile
snapshot, but `--plugin` no longer installs or enables Liquid Glass.

`--omastore` reinstalls OmaStore's checksum-verified release into `~/.local`;
`--all` includes it, while `--plugin` does not. The plugin installer uses the
published Glass plugin repository; unpublished edits to a local checkout
are not part of a fresh installation.
The source checkouts used by the plugin installers stay under
`~/.local/share/dotfiles/sources/` and survive removal of this dotfiles clone.

Existing plugin directories are preserved under
`~/.local/state/dotfiles/plugin-backups/<timestamp>/` before replacement.
These are manual recovery copies; `--restore` handles the separate dotfile
backups, not application versions, compiled plugins or services.

The keyboard's RGB lighting needs the
[Dareu EK75 OpenRGB driver](https://github.com/KitsuneSemCalda/Dareu-EK75-OpenRGB-Compat),
because the packaged `openrgb` has no support for it. `--openrgb` clones it to
`~/.local/share/dareu-ek75-openrgb`, or updates an existing clone, then runs its
installer steps: an OpenRGB build with the driver, the launcher, and a hook
that colours the keyboard with each Omarchy theme's accent. The udev rule is
installed in the installer's single `pkexec` call. It needs the Qt 6
build dependencies of OpenRGB and takes a while on the first run.
The installer first installs missing packages, including `openrgb` (whose menu
entry the launcher needs), `base-devel`, Qt 6, HID/USB libraries and `mbedtls3`.

The EK75 knob on this machine sends repeated mute events even when untouched.
`--ek75-knob` installs `scripts/udev/61-ek75-knob.hwdb` into
`/etc/udev/hwdb.d/` and updates the hardware database. The rule matches only
the EK75's secondary input interface in wired and 2.4 GHz modes; it disables
its mute and volume events while leaving ordinary typing available. Other
EK75 media shortcuts that send those same events may also be affected.
The option is included in `--all`. Reconnect the keyboard after installation
to apply the rule to an already connected device. It uses `pkexec`, and
`--restore` does not remove system rules. After repairing the knob, remove
`/etc/udev/hwdb.d/61-ek75-knob.hwdb`, run `pkexec systemd-hwdb --strict update`,
and reconnect the keyboard to restore its original behavior.

```bash
perl ./omarchy.pl --ek75-knob
```

## Installation

The installer changes nothing by default when a conflicting file exists. See
first what it would do:

```bash
perl ./omarchy.pl --dry-run
```

To install while preserving existing files in
`~/.local/state/dotfiles/backups/`:

```bash
perl ./omarchy.pl --backup
```

To undo the installation by restoring the most recent backup without deleting
your copy:

```bash
perl ./omarchy.pl --restore
```

The restore only replaces unchanged installed copies, legacy links to this
repository, or missing files. Installed content hashes are recorded under
`~/.local/state/dotfiles/installed.json`. If it finds manual changes at the
destination, it aborts the whole operation to avoid overwriting them. Use
`--restore --dry-run` to review the chosen backup before restoring.

The installer also runs [`Skill-Library/install.pl`](../../Skill-Library/README.md)
after the copies, installing every skill from the library into every AI
agent CLI detected on this machine (`~/.claude`, `~/.codex`,
`~/.config/opencode`). This step is unconditional (not behind a flag), like
the copies themselves, but only runs against the real HOME — it is skipped
when `--target` points elsewhere for testing.

The steps can also be run separately with `--fonts`, `--apps`,
`--bookmarks`, `--plugin`, `--omastore`, `--theme`, `--openrgb`, `--ek75-knob`,
`--clamshell`, `--calibrate`, `--maintenance`, `--ai-memory`, `--ai-jail`,
or `--home-backup`.
`--apps` uses the official repositories for
PrismLauncher and the AUR packages for Bitwarden, AppFlowy, and CurseForge,
installs the web apps listed above (skipping any already present), and
removes HEY/Basecamp and 1Password if it finds them installed.
`--apps` and `--bookmarks` add FrankMD, Pi-hole and ai-memory to the Chromium
bookmarks bar, opening `http://127.0.0.1:7591/`,
`http://127.0.0.1:8080/admin/` and `http://127.0.0.1:49374/web`
in normal browser tabs. Existing bookmarks are preserved, duplicates are
skipped, and a copy of the file is saved under
`~/.local/state/dotfiles/bookmark-backups/` before changes. Close Chromium
before running either option; the Default profile must already exist.

To reinstall the complete profile, including bookmarks, apps, plugins,
OmaStore, fonts, theme, OpenRGB, the EK75 knob rule, clamshell configuration,
hardware inventory, automatic maintenance, ai-memory MCP/hooks, ai-jail and
the home backup timers:

```bash
perl ./omarchy.pl --all --backup
```

Add `--reboot` to request a normal system reboot only after every requested step
succeeds and `hyprctl reload`/`hyprctl configerrors` pass. A failed installer or
invalid Hyprland configuration prevents the reboot. `--all` without `--reboot`
does not reboot; `--dry-run` never executes either installation commands or reboot.
Run the real installation inside the Omarchy desktop session, with a terminal
available for package-manager and HyprGlass administrator prompts.
The OpenRGB udev rule, EK75 knob rule and system backup timer share one
`pkexec` authorization when selected together.

The installer copies the files under `home/`, preserving executable permissions.
The Codex and Claude aliases in `home/.aliasrc` use
`ai-jail --forward-port 49374 ai-memory run --yolo codex` (or `claude`).
The launcher and harness run inside ai-jail, with the local ai-memory service
reachable through port 49374; `--yolo` selects the harness's unattended mode.
The aliases map only ai-memory's cache and data directories read-write in addition
to ai-jail's default project and harness state mounts. The installer prepares
the verified native launch client on the host before enabling these aliases.
Both tools must be installed (`--all` or `--ai-memory --ai-jail`). Bash must
source `~/.aliasrc` from `~/.bashrc` for them to be active. The profile includes
a `.bashrc` that loads it after the Omarchy defaults, in interactive shells.
Install with `--backup` to preserve an existing `.bashrc` before replacement.
A new terminal loads changes to the alias file.
When installing the profile into the real HOME, the installer prepares missing
alias dependencies before copying any dotfiles and aborts if setup fails.
This also applies without `--all`; test targets and standalone home backup skip
this dependency setup.
Legacy links to this checkout are replaced automatically. You can remove the
checkout after installation; pull or clone it again and rerun the installer
to update. Locally edited files require `--backup` before replacement. The normal real-HOME
installation also prepares AI alias dependencies and Intel GPU API packages,
starts ai-memory when needed, centralizes model paths and checks GPU discovery.
Optional actions add their own package, service or system changes; `--all`
enables all of them. Inspect the dry-run before applying the profile.

## Automatic maintenance

`perl ./omarchy.pl --maintenance --backup` enables daily local diagnosis and
weekly maintenance; `--all` includes it. Updates run between 03:00 and 06:00
from Sunday onward, only on AC and after 15 minutes idle. Missed windows retry
the next night. It does not wake the laptop or request a reboot. Stay Awake
postpones heavy work. See [maintenance commands, reports and limits](../docs/maintenance.md).

Use `dotfiles-maintenance simulate` to inspect eligibility without changes,
`dotfiles-maintenance status` to read results, and `dotfiles-maintenance disable`
to stop scheduling and restore owned power preferences.

## Local backups and budgeted Dropbox publication

`--home-backup` installs the backup helpers, dependencies and user/system timers.
It is included in `--all`. Use `--backup` to preserve changed installed scripts.
The Dropbox account must already be linked for cloud publication.

Every 15 minutes, Unison updates the one-way working copy in
`~/.local/state/home-dropbox-backup/current/`. Changes to this copy never flow
back to HOME. Up to three previous versions per path remain in `history/unison/`.
Ordinary SQLite databases are normalized with Python's online backup API,
including committed WAL data. Database errors, conflicts and interrupted runs
block publication; encrypted databases require their application's own export.

Daily retry timers save one complete ZIP per month **outside Dropbox**:

```text
~/.local/state/home-dropbox-backup/
├── current/
├── history/unison/
└── archives/
    ├── home/
    │   ├── history.zip
    │   └── 2026/2026-10-24.zip
    └── btrfs/
        ├── history.zip
        └── 2026/2026-10-24.zip

~/Dropbox/Backups/SamsungBook-Np550xda/Omarchy/latest.zip
```

Completed years are consolidated locally into a `history.zip` for HOME and one
for Btrfs. Original monthly and legacy annual ZIPs remain nested inside them,
with outer DEFLATE level 9 compression. Their contents are compared using
SHA-256 before originals are removed. Local history has no 2 GB cloud limit;
recursive ZIP compression is not a quota or deduplication mechanism. Local
archives occupy the same computer's storage and are not an off-device backup.

On upgrade, old managed ZIPs in Dropbox's `home/` and `btrfs/` backup directories
are copied to the local archives, verified byte for byte, and only then removed
from the synchronized directories. Interrupted copies can be retried; conflicting
local files stop migration without replacing either version. Other Dropbox
files are never selected for removal. The older `current/history/monthly`
layout is first preserved in a local legacy ZIP before its working copy moves.
Moving these old ZIPs out of Dropbox also removes their cloud copies when the
client processes the changes; their verified local copies remain.

After a successful synchronization within the last hour, the daily HOME job
refreshes the single cloud `latest.zip`, even if this month's local archive
already exists. The default selection is:

```text
Documents
Work
.config
.ssh
.gnupg
.local/bin
.aliasrc
.bashrc
.gitconfig
.XCompose
```

Selections refer to the filtered working copy, not the live HOME. Existing
Unison exclusions still apply. Files outside this list remain in local complete
backups. To customize, create `~/.config/home-dropbox-backup/cloud-includes`
with one relative path per line (`#` comments allowed); this replaces the default
list. Missing selections are skipped, but an empty selection is rejected.
Nothing is silently dropped to make an oversized selection fit. ZIPs include
credentials when selected and are compressed, not encrypted.

Publication counts **all files in the local Dropbox tree**, subtracts the old
`latest.zip`, adds the new ZIP, and requires the total to be strictly below
**1,800,000,000 bytes**. This leaves 200 MB below the assumed 2 GB account quota.
`HOME_BACKUP_DROPBOX_BUDGET_BYTES` can lower this total budget (maximum 2 GB).
An oversized result leaves the local backups and previous cloud ZIP intact.
Staging is outside Dropbox; an atomic rename replaces the current ZIP without
exposing a second temporary ZIP to the sync client. This requires staging and
Dropbox to share a filesystem.

This is a local budget check, not a Dropbox account API query. Files or shared
folders existing only in the cloud are not measured; lower the budget to reserve
space for them. Concurrent uploads from other devices are also outside this
check. Confirm the actual account usage and completed uploads with Dropbox;
a locally created ZIP does not establish cloud protection.

```bash
perl ./omarchy.pl --home-backup --backup
home-dropbox-backup --dry-run
home-dropbox-monthly --dry-run
home-dropbox-monthly --list
systemctl --user start home-dropbox-monthly.service
dropbox-cli status
```

`--dry-run` does not relocate old cloud files. Full archives require additional
local disk space: the default reserve is 10 GiB beyond staging. The user backup
respects `XDG_STATE_HOME`; the root Btrfs exporter uses the fixed HOME-relative
state directory shown above.

Restore the cloud selection by verifying `latest.zip` with `unzip -t`, then
extracting into an empty recovery directory. Local HOME ZIPs preserve Unix
permissions and symbolic links. The working-copy restore remains preview-first:

```bash
home-dropbox-backup --restore
home-dropbox-backup --restore --apply
```

Local Btrfs ZIPs contain a full `root.send` and `manifest.json`. They do not need
older streams, and are validated with `btrfs receive --dump` before the source
snapshot is deleted. For recovery, use a mounted Btrfs recovery filesystem:

```bash
unzip -t 2026-10-24.zip
unzip -p 2026-10-24.zip root.send | sudo btrfs receive /mnt/recovery
```

The root stream omits separate subvolumes such as `@home`, `@pkg` and `@log`.
HOME is covered by its own local archive. Snapper recovery points stay separate.
For history archives, extract the desired nested ZIP first; legacy annual ZIPs
require a further extraction. A real recovery drill remains necessary to verify
the complete restore procedure.

## Docker stack

`docker/docker-compose.yml` brings up five services. Postgres, Redis, FrankMD
and ai-memory bind to `127.0.0.1`, so they are reachable only from this
machine. Pi-hole's DNS and web UI are also reachable from the local network:

- **postgres** (`17-alpine`) and **redis** (`7-alpine`) — general-purpose
  database and cache for local projects, ports `5432` and `6379`.
- **[FrankMD](https://github.com/akitaonrails/FrankMD)** (`1.0.1`) —
  self-hosted Markdown notes editor, port `7591`, stores files in
  `~/Documents/notes` (no database).
- **[ai-memory](https://github.com/akitaonrails/ai-memory)** (`2.3.0`) —
  persistent memory shared across AI agents, port `49374`, with its built-in
  web interface at `/web`. The
  `~/.local/bin/ai-memory` wrapper (`scripts/docker-stack.pl --agents`) is
  downloaded from the matching `v2.3.0` GitHub release and verified against a
  SHA-256 checksum pinned in `ensure_wrapper()`, not fetched at run time.
  After verification, the managed wrapper's image and release download defaults
  are pinned to `2.3.0` too, including its native launch client.
- **pihole** (`2026.07.2`) — local DNS, port `53` and admin UI on `8080`.

Every image and the wrapper download use an explicit version, never `latest`,
so re-running the stack always reproduces the same result. To deliberately
upgrade one: pick the new version from its releases/tags page, update the tag
in `docker/docker-compose.yml` (or, for the wrapper, both `$version` and the
`$expected` checksum in `ensure_wrapper()` in `scripts/docker-stack.pl`, using
the `.sha256` asset published alongside that release), then run
`docker compose config --quiet` and `perl scripts/docker-stack.pl --up` to
confirm the stack still comes up healthy before committing the bump.

First run (creates `docker/.env` with random secrets, the notes
folder, and brings up the containers):

```bash
perl scripts/docker-stack.pl --up
```

Wire ai-memory to every already-installed AI agent (currently detects
`claude`, `codex`, `gemini`, `cursor-agent`, `opencode`, and `grok` on the
`PATH`, via `install-mcp`/`install-hooks`):

```bash
perl scripts/docker-stack.pl --agents
```

The main installer includes both integrations in `--all`. Run them separately with:

```bash
perl ./omarchy.pl --ai-memory --ai-jail --backup
```

`--ai-memory` installs Docker dependencies, enables `docker.socket`, starts only
the ai-memory Compose service, installs the verified wrapper, and applies MCP
and hooks to detected agents. Docker must already be accessible to the current
user; the installer does not change group membership. Existing `docker/.env`
values are preserved. `scripts/docker-stack.pl --memory --agents` runs the
service and agent setup directly without starting the other services or changing DNS.

`--ai-jail` installs the AUR package `ai-jail-bin` and `bubblewrap`. ai-jail is
a sandbox launcher. The Codex and Claude aliases invoke it around
`ai-memory run --yolo`, forwarding the local memory port 49374.

Make Pi-hole this machine's default DNS (waits for the container to become
healthy before applying; delegates to `omarchy dns Custom` with
`127.0.0.1` and fallback `1.1.1.1`, which is Omarchy's native mechanism —
this avoids reimplementing it via `nmcli` directly, which on this machine
also manages Docker's bridges and could break the containers'
packet forwarding if touched directly):

```bash
perl scripts/docker-stack.pl --dns
```

`omarchy dns` (with no argument) can show "Cloudflare" even with Pi-hole
active — its detection only checks whether `1.1.1.1` appears in the list, which is
exactly the fallback. Confirm the real server with `resolvectl status`
(`Current DNS Server: 127.0.0.1`).

`--up` also installs two DNS recovery triggers that fix DNS "reverting" to
the `1.1.1.1` fallback: Pi-hole's container can still be starting when
`systemd-resolved` first tries `127.0.0.1`, so `resolved` marks it bad and
keeps using the fallback for the rest of the session even once Pi-hole is
healthy — resetting the interface's DNS list back to `127.0.0.1 1.1.1.1`
does not reliably win Cloudflare's spot back either, since `resolved` only
re-picks a "current" server once the one it is already using drops out of
the list. Both triggers run the same recovery: wait for the container's
health check, then narrow the active interface's DNS list down to just
Pi-hole (`resolvectl dns <iface> 127.0.0.1`), forcing `resolved` to pick it
unambiguously; the system-wide `FallbackDNS` in `/etc/systemd/resolved.conf`
(set by `omarchy dns Custom`) still covers Pi-hole going down mid-session.
This is an unprivileged `resolve1` D-Bus call, so no password prompt.

- A `post-boot` hook (`scripts/hooks/pihole-dns-recover.sh`, via `omarchy
  hook install`) — runs once per reboot.
- A `systemd --user` service (`scripts/hooks/pihole-dns-resume-watch.sh` +
  `pihole-dns-resume.service`) that watches `login1`'s `PrepareForSleep`
  D-Bus signal, the same mechanism Omarchy's own pre-suspend lock monitor
  uses, and reruns the recovery on every **resume from suspend**. The
  post-boot hook alone only fires once per reboot; on a laptop that suspends
  far more often than it reboots, `resolved` never re-evaluates `127.0.0.1`
  on its own after a resume, so without this second trigger DNS stayed stuck
  on the `1.1.1.1` fallback for the rest of the day after the first resume
  of a session.

Install/reinstall both on their own with:

```bash
perl scripts/docker-stack.pl --dns-hook
```

Check the resume watcher's state with `systemctl --user status
pihole-dns-resume.service`.

Revert DNS to automatic (`omarchy dns DHCP`), stop the stack, or just
check the containers' state:

```bash
perl scripts/docker-stack.pl --dns-revert
perl scripts/docker-stack.pl --down
perl scripts/docker-stack.pl --status
```

Any action accepts `--dry-run`. ai-memory's optional API keys
(LLM summarization and semantic search) are left blank in `docker/.env` until
filled in manually; without them, memory works with text search only.

## Updating the hardware snapshot

The report can just be printed:

```bash
perl scripts/hardware-profile.pl
```

To replace the versioned snapshot with a fresh `inxi -Fz` collection:

```bash
perl scripts/hardware-profile.pl --save
```

After installing or changing Hyprland Lua files, validate them in the
graphical environment with `hyprctl reload` and `hyprctl configerrors`, per Omarchy's
documentation.


## Inferctl and local ComfyUI

The local AI governor, benchmarker and tuning project lives in
[`calibration/inferctl/`](calibration/inferctl/README.md). Its container setup is documented in
[`calibration/inferctl/deploy/comfyui/`](calibration/inferctl/deploy/comfyui/README.md).

The dotfile installer does not build inferctl, start ComfyUI or run a calibration.
Build and test it separately with `make check` and `make build` in its directory.
Profiles distinguish hardware, backend, model, workload and usage mode; measured
throughput and safety constraints determine which candidates can be recommended.
Recommended profiles are saved separately and are not activated automatically.

The [validation record](calibration/inferctl/docs/validation.md) includes host
tests for the Qwen3-0.6B LM Studio control, transient systemd limits and CPU
Docker integration. The Qwen comparison did not establish a performance gain.
ComfyUI's real API smoke test used a graph without an AI model. GPU containers,
image/video generation, thermal tuning under sustained load and speculative
decoding still need their own workload tests.

### Armazenamento de modelos de IA

A aplicação normal dos dotfiles executa `setup-ai-models` e centraliza os pesos
em `~/.ai/models/lmstudio` e `~/.ai/models/comfyui`. Os caminhos `~/.lmstudio/models`
e `~/.local/share/inferctl/comfyui/models` são links para essas pastas.
O comando também pode ser executado manualmente; reaplicá-lo não copia os pesos.
Diretórios existentes são movidos; destinos conflitantes ou links inesperados
interrompem a operação sem sobrescrever arquivos. Os pesos ficam fora do Git.

A separação preserva a estrutura publisher/model do LM Studio e as categorias
checkpoints, diffusion_models, loras e latent_upscale_models do ComfyUI.
O Docker continua usando os caminhos originais; recriações resolvem os links
para o armazenamento central. A pasta externa do LM Studio continua disponível
para os modelos explicitamente registrados em extra_model_paths.yaml.

### Aceleração Intel

A instalação normal prepara Vulkan, OpenCL, Level Zero e VA-API e executa
`check-ai-acceleration` para verificar acesso e descoberta da GPU.
Os modelos ficam em `~/.ai/models`, mantidos por `setup-ai-models`.
Veja [dependências, verificações e limites de suporte](docs/ai-acceleration.md).
