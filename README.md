# Dotfiles

![CI](https://github.com/KitsuneSemCalda/Dotfiles/actions/workflows/installers.yml/badge.svg)
![Perl](https://img.shields.io/badge/installer-perl-39457e?logo=perl&logoColor=white)
![PowerShell](https://img.shields.io/badge/installer-powershell-5391fe?logo=powershell&logoColor=white)
![Built for Omarchy](https://img.shields.io/badge/built%20for-omarchy-1793d1)

> Personal setup for Omarchy (Hyprland) and Windows 11, a library of
> AI coding-agent skills, and inferctl for local AI benchmarks and resource control.

Installers copy configuration files instead of symlinking them, so you can move
or delete this clone afterwards and the installed configuration keeps working.
The separate inferctl project is built from source. CI runs the Linux installer
tests on Ubuntu and the Windows tests with Windows PowerShell and PowerShell 7.

## What's inside

| Module | What it is | Installer |
|--------|------------|-----------|
| [`SamsungBook-Np550xda/Omarchy`](SamsungBook-Np550xda/Omarchy/README.md) | Hyprland (Lua), Alacritty, btop, GTK, fonts, starship, webapps, power profile, Dareu EK75 OpenRGB support and an optional Docker stack | `omarchy.pl` (Perl) |
| [`SamsungBook-Np550xda/Windows-11`](SamsungBook-Np550xda/Windows-11/README.md) | GlazeWM, PowerShell profile, Windows Terminal scheme, Rainmeter HUD and a debloat script | `win11.ps1` (PowerShell) |
| [`Skill-Library`](Skill-Library/README.md) | Curated `SKILL.md` skills for Claude Code, Codex and other agent CLIs | `install.pl` / `install.ps1` |
| [`inferctl`](SamsungBook-Np550xda/Omarchy/calibration/inferctl/README.md) | Linux hardware profiling, AI benchmarks, admission control and measured tuning for LM Studio, llama.cpp and ComfyUI | Separate Go build; not installed by the dotfile installer |

The machine profiles are tied to one laptop, the Samsung NP550XDA-KF2BR. The
[architecture notes](SamsungBook-Np550xda/docs/architecture.md) explain the
layers, what changes on the base system and the limits of restoring it, with
Mermaid diagrams.

The Omarchy profile also includes local full backups with a budgeted Dropbox
copy, scheduled maintenance, monitor recovery, and OmaTuber/OBS integration.
The [maintenance guide](SamsungBook-Np550xda/docs/maintenance.md) covers both
operating systems. [Capture setup](SamsungBook-Np550xda/docs/capture.md) covers
OBS profiles, audio routing and the OmaTuber scene.

## Quick start

```sh
git clone https://github.com/KitsuneSemCalda/Dotfiles.git
cd Dotfiles

# Omarchy
perl SamsungBook-Np550xda/Omarchy/omarchy.pl

# Windows 11 (PowerShell)
./SamsungBook-Np550xda/Windows-11/win11.ps1
```

Run the installer with `--dry-run` on Omarchy or `-DryRun` on Windows before
applying changes. Use `--backup` or `-Backup` to preserve edited configuration.
On Omarchy, ordinary installation also prepares the sandboxed AI aliases,
ai-memory service, Intel GPU APIs and shared model directories. It can install
packages and request administrator authorization. See the
[Omarchy installation notes](SamsungBook-Np550xda/Omarchy/README.md#installation)
for the full scope. `--all` and `-All` also enable scheduled maintenance;
Omarchy's `--all` includes backups and OmaTuber.

Only want the skills, on any machine?

```sh
perl Skill-Library/install.pl --list      # see skills and detected agents
perl Skill-Library/install.pl --dry-run   # preview without copying
perl Skill-Library/install.pl             # install into every detected agent
```

## Skill library

Each skill teaches an agent something non-obvious about a real workflow. The
current set:

`algorithmic-project-review` · `anti-ai-mediocrity` · `blog-reader-panel` ·
`github-project-health` · `github-resolution` · `humanizer` · `i-have-adhd` ·
`iss-audit` · `learn-from-work` · `loop` · `ponytail` · `pr-audit` · `pr-bump` ·
`preserve-my-english` · `price-research-webapps` · `principled-refactoring` · `product-readme` ·
`quantify-ambition` · `release` · `skeptical-research` ·
`software-product-review` · `software-project-analysis`

The format is the same `SKILL.md` convention Claude Code and Codex share, so a
skill needs no per-agent adaptation. See the
[Skill-Library README](Skill-Library/README.md) for details.

## Local AI workloads

inferctl compares throughput and resource measurements before recommending a
profile. It supports LM Studio/llmster, native llama.cpp services through
systemd/cgroups v2, and ComfyUI through its API or disposable Docker containers.
Models, workflows and hardware have separate profiles. Recommended settings are
saved for review and are never activated automatically.

Start with the [inferctl README](SamsungBook-Np550xda/Omarchy/calibration/inferctl/README.md).
The [validation record](SamsungBook-Np550xda/Omarchy/calibration/inferctl/docs/validation.md)
separates synthetic tests from host results. The Qwen3-0.6B control completed a
real LM Studio benchmark; its small differences do not establish a performance
gain. Docker was tested in CPU mode, and ComfyUI completed a graph without an AI
model. Image/video generation, GPU containers and speculative decoding still
need workload tests.

Full HOME and Btrfs archives stay outside Dropbox. A single cloud `latest.zip`
contains selected essentials, with a default budget below 1.8 GB for the whole
local Dropbox tree. Cloud-only files are not measured. See
[backup storage and migration](SamsungBook-Np550xda/Omarchy/README.md#local-backups-and-budgeted-dropbox-publication).

## Related

[**iae**](https://github.com/KitsuneSemCalda/iae) is a tmux workspace with an
editor, coding agent, shell and git panes that re-lays itself out as you resize
the terminal. It is built for the same Omarchy setup.

## Testing

```sh
python3 SamsungBook-Np550xda/tests/install.py        # Linux installer
pwsh ./SamsungBook-Np550xda/tests/install.ps1        # Windows installer
```

Both run in CI ([workflow](.github/workflows/installers.yml)).

The workflow also runs Linux checks for backups, maintenance, hardware recovery
and OmaTuber integration. Test inferctl separately with `make check` from
`SamsungBook-Np550xda/Omarchy/calibration/inferctl`: it runs Go race tests,
Python tool tests and `go vet`. Real systemd and Docker checks are opt-in and
documented in the inferctl validation guide. Unit tests do not establish model
performance or a working graphical session.

## License

[BSD 3-Clause](LICENSE).
