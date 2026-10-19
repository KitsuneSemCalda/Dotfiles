# Dotfiles for Omarchy — Samsung Book NP550XDA

See also the [architecture analysis and diagrams](../docs/architecture.md),
covering the modifications to the base system and the installers' limitations.
The [capture pipeline](../docs/capture.md) documents OBS profiles, PipeWire
audio buses, scene setup, hardware limits and benchmark steps.

Initial dotfiles baseline for the Samsung NP550XDA-KF2BR, running Omarchy with
Hyprland. The full snapshot used to make these decisions is at
[`hardware/inxi-Fz.txt`](hardware/inxi-Fz.txt).

## Machine profile

- Intel Core i5-1135G7, 4 cores / 8 threads
- 16 GiB of RAM
- Intel Iris Xe (`i915`)
- 1920×1080 internal display
- Samsung NVMe, approximately 256 GiB
- Battery capacity observed at 30.7% of design capacity
- Btrfs filesystem with swapfile and zram

The current choices follow this profile: scale 1, interface font size 14,
terminal font size 11, preferred monitor mode and EDID color management for
the internal BOE panel, plus moderate visual effects for the Iris Xe.
The power profile is left to Omarchy's own
`omarchy powerprofiles init`, which already runs at session start and picks
`power-saver` or `balanced`/`performance` from the AC/battery signal.

## Closed-lid use with an external monitor

Omarchy already handles clamshell mode: with an external monitor connected,
closing the lid disables the internal panel and keeps the session on the external
screen; opening the lid enables the panel again. Without an external screen,
closing the lid locks and suspends the notebook. Connect an external keyboard and
mouse and keep the notebook on a hard, ventilated surface. The internal `eDP-1`
monitor rule stays on one line because Omarchy's clamshell helper reads its
scale and position when it restores the panel. The expected internal scale is 1.

To check after installation, connect the monitor and run `hyprctl monitors all`.
Close and reopen the lid, then confirm that `eDP-1` returns at scale 1. The
stock shortcut `Super+Ctrl+Delete` toggles the internal display manually when an
external display is active. Omarchy's monitor watcher recovers the internal
panel if the external display disappears.

The installed `systemd-logind` already has `HandleLidSwitch=suspend` and
`HandleLidSwitchDocked=ignore`; Omarchy's lid handler takes care of the display.
Check effective settings with `systemd-analyze cat-config systemd/logind.conf`.
There is no extra logind drop-in to install for this machine.

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
home/.local/bin/home-dropbox-backup         # copies HOME to Dropbox; previews restores
home/.local/bin/home-dropbox-monthly        # monthly compressed home archive chain
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

The app profile includes Bitwarden, AppFlowy, PrismLauncher, CurseForge, and
the web apps Amazon Shopping, Mercado Livre, Pinterest, Z Ai, WebMotors,
Panini Brasil, GitHub, GitLab, Codeberg, Copilot, Claude, ChatGPT, Grok, and
Gemini. It also removes any previously installed HEY or Basecamp web app and
any 1Password installation (package, AUR package, or browser extension) via
`omarchy remove service`, since neither is part of this profile.
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
`install.sh`: the udev
rule (asks for sudo), an OpenRGB build with the driver, the launcher, and a hook
that colours the keyboard with each Omarchy theme's accent. It needs the Qt 6
build dependencies of OpenRGB and takes a while on the first run.

The EK75 knob on this machine sends repeated mute events even when untouched.
`--ek75-knob` installs `scripts/udev/61-ek75-knob.hwdb` into
`/etc/udev/hwdb.d/` and updates the hardware database. The rule matches only
the EK75's secondary input interface in wired and 2.4 GHz modes; it disables
its mute and volume events while leaving ordinary typing available. Other
EK75 media shortcuts that send those same events may also be affected.
The option is included in `--all`. Reconnect the keyboard after installation
to apply the rule to an already connected device. It requires `sudo`, and
`--restore` does not remove system rules. After repairing the knob, remove
`/etc/udev/hwdb.d/61-ek75-knob.hwdb`, run `sudo systemd-hwdb --strict update`,
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
or `--home-backup`. `--apps` uses the official repositories for
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
OmaStore, fonts, theme, OpenRGB, the EK75 knob rule and the home backup timer:

```bash
perl ./omarchy.pl --all --backup
```

Add `--reboot` to request a normal system reboot only after every requested step
succeeds and `hyprctl reload`/`hyprctl configerrors` pass. A failed installer or
invalid Hyprland configuration prevents the reboot. `--all` without `--reboot`
does not reboot; `--dry-run` never executes either installation commands or reboot.
Run the real installation inside the Omarchy desktop session, with a terminal
available for package-manager and HyprGlass administrator prompts.

The installer copies the files under `home/`, preserving executable permissions.
Legacy links to this checkout are replaced automatically. You can remove the
checkout after installation; pull or clone it again and rerun the installer
to update. Locally edited files require `--backup` before replacement. No
system configuration was changed when this repository was created; `--all` is the
option that applies external changes.

## Home ↔ Dropbox synchronization

`--home-backup` installs Unison and enables a user systemd timer that runs every
15 minutes. It synchronizes the selected home files in both directions with
`~/Dropbox/Backups/SamsungBook-Np550xda/Omarchy/home/current/`. A file changed
on either side updates the other side at the next run. Simultaneous edits are
kept as conflicts for manual review; the service reports a skipped path rather
than choosing a winner. Deleting a file in the home removes it from `current/`
and keeps an older version under `home/history/unison/`. Deletions arriving
from Dropbox do not delete files in the home. Up to three backup versions per
path are retained. Dropbox syncs the local `current/` and `history/` folders to
the account. A successful Unison run proves the local replicas agree; check the
Dropbox client or website to confirm cloud upload.

Two additional timers run daily and create at most one archive for each calendar
month, retrying after a failed run. The user timer writes a GNU tar incremental
chain compressed with zstd under `home/monthly/home/YYYY-MM.tar.zst`; each month
also has a `.snar` state file, `.sha256` checksum and `.meta` parent record.
The first archive is full; later archives require every ancestor back to that
full archive. The system timer creates a read-only Btrfs snapshot of `/` and
exports a compressed `btrfs send` stream under `home/monthly/btrfs/`. The first
stream is full, later streams use the previous month's snapshot as parent when
its archive is intact. It keeps only the newest local snapshot under
`/var/lib/home-dropbox-backup/snapshots/`; exported streams stay in Dropbox.
This captures the root subvolume at monthly dates. The separate `@home`,
`@pkg` and `@log` subvolumes are not part of the root stream; the selected home
files are covered by the home archive and live replica. Existing Snapper
pre-update snapshots are separate recovery points and are not individually
exported by this timer.

The script stores its Unison archive, lock and last-success marker in
`${XDG_STATE_HOME:-~/.local/state}/home-dropbox-backup/`, with exclusions in
`${XDG_CONFIG_HOME:-~/.config}/home-dropbox-backup/excludes`. The XDG user
directories, active projects, configuration, and credentials are included.
The exclusion file skips the Dropbox folder itself, caches, Steam and container
data, reinstallable toolchains and build outputs, and the existing 64 GB
`~/Projects/omastore-fork-backups` directory. Edit it before the first run if
you need those items. The synchronized copy includes credentials such as `~/.ssh` in
plain text, as requested; anyone with access to the Dropbox account can read
them. The script refuses to start if the disk has less than 10 GiB free.

```bash
perl ./omarchy.pl --home-backup --backup
home-dropbox-backup --dry-run
home-dropbox-monthly --dry-run
systemctl --user start home-dropbox-backup.service
systemctl --user list-timers 'home-dropbox-*'
systemctl list-timers 'home-btrfs-monthly*'
cat ~/.local/state/home-dropbox-backup/last-success
journalctl --user -u home-dropbox-backup.service -n 50
```

On a reinstall, install and sign in to Dropbox, wait for `home/current/` to
download, then preview restoration before applying it:

```bash
home-dropbox-backup --restore
home-dropbox-backup --restore --apply
```

Restoration copies files from `current/` into the home without deleting newer
local files. Older versions in `history/` can be copied manually as needed.
For a monthly recovery, verify all `.sha256` files with `sha256sum -c`, then
extract the full home archive followed by each incremental archive in date
order into a new, empty directory. For example, with archive names `2026-10`
and `2026-11`:

```bash
cd ~/Dropbox/Backups/SamsungBook-Np550xda/Omarchy/home/monthly/home
sha256sum -c 2026-10.sha256 2026-11.sha256
mkdir -p /mnt/recovery/home
zstd -dc 2026-10.tar.zst | tar -xG -C /mnt/recovery/home -f -
zstd -dc 2026-11.tar.zst | tar -xG -C /mnt/recovery/home -f -
```

Mount a recovery filesystem at `/mnt/recovery` first. Extract into an empty
directory because incremental tar archives also record deletions. For Btrfs,
verify the checksums and receive each `.send.zst` in parent order onto a Btrfs
filesystem; receiving the full stream and then its incremental descendants
recreates the dated root snapshots. For example, from `monthly/btrfs/`:

```bash
sha256sum -c 2026-10.sha256 2026-11.sha256
zstd -dc 2026-10.send.zst | sudo btrfs receive /mnt/recovery
zstd -dc 2026-11.send.zst | sudo btrfs receive /mnt/recovery
```

Use each `.meta` file to find its parent; if a month is `kind=full`, start a
new receive chain with that archive. The Btrfs stream is for system recovery
and does not replace a reinstall of packages, bootloader or the other
subvolumes.
Install this script from the dotfiles checkout first, or run it from the
checkout's `home/.local/bin/` path. The timer only runs while the user manager
is active; missed runs trigger after the next login. Resolve skipped conflicts
with `home-dropbox-backup --review` from a terminal; the timestamp in
`~/.local/state/home-dropbox-backup/last-conflicts` marks the latest run with
skipped paths. Files changed during a run are retried by the next timer
activation and recorded in `last-partial`; the current copy of those files may
be older until the application stops writing. Sockets, temporary database side
files and caches are excluded. Verify that the Dropbox account is linked and
syncing with `dropbox-cli status`; a local Unison success does not confirm cloud
upload.

## Docker stack

`docker/docker-compose.yml` brings up five services published on the host so
they are reachable from trusted devices on the local network:

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
