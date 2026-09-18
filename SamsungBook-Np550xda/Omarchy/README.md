# Dotfiles for Omarchy — Samsung Book NP550XDA

See also the [architecture analysis and diagrams](../docs/architecture.md),
covering the modifications to the base system and the installers' limitations.

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

The initial choices follow this profile: scale 1 and interface/terminal
fonts at size 20, plus `preferred` monitor mode, moderate visual
effects for the Iris Xe, and a `balanced` power profile by default. At session
startup, the included Perl utility selects `power-saver` if the battery is
discharging with 25% charge or less; otherwise it selects `balanced`.
There is no continuous monitoring.

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
│   ├── omarchy/shell.toml      # Omarchy interface base size
│   └── starship.toml
└── .local/bin/
    └── omarchy-power-profile  # power-profile selector written in Perl
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
theme and the [Feader-RSS](https://github.com/KitsuneSemCalda/Feader-RSS) plugin, with
feed configuration at `~/.config/omarchy/rss-reader.json`.

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

The restore only replaces symlinks that still point to this repository (or
creates files that are missing). If it finds manual changes at the
destination, it aborts the whole operation to avoid overwriting them. Use
`--restore --dry-run` to review the chosen backup before restoring.

The installer also runs [`Skill-Library/install.pl`](../../Skill-Library/README.md)
after the symlinks, installing every skill from the library into every AI
agent CLI detected on this machine (`~/.claude`, `~/.codex`,
`~/.config/opencode`). This step is unconditional (not behind a flag), like
the symlinks themselves, but only runs against the real HOME — it is skipped
when `--target` points elsewhere for testing.

The steps can also be run separately with `--fonts`, `--apps`,
`--plugin`, or `--theme`. `--apps` uses the official repositories for
PrismLauncher and the AUR packages for Bitwarden, AppFlowy, and CurseForge,
installs the web apps listed above (skipping any already present), and
removes HEY/Basecamp and 1Password if it finds them installed.

To also apply fonts, apps, plugin, and theme — including network
operations and possible package-manager password prompts:

```bash
perl ./omarchy.pl --all --backup
```

The installer creates symlinks for the files under `home/`. No
system configuration was changed when this repository was created; `--all` is the
option that applies external changes.

## Docker stack

`docker/docker-compose.yml` brings up five services, all published only on
`127.0.0.1` (none are reachable over the local network):

- **postgres** (`17-alpine`) and **redis** (`7-alpine`) — general-purpose
  database and cache for local projects, ports `5432` and `6379`.
- **[FrankMD](https://github.com/akitaonrails/FrankMD)** (`1.0.1`) —
  self-hosted Markdown notes editor, port `7591`, stores files in
  `~/Documents/notes` (no database).
- **[ai-memory](https://github.com/akitaonrails/ai-memory)** (`2.3.0`) —
  persistent memory shared across AI agents, port `49374`. The
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
