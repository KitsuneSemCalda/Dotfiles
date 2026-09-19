# Dotfiles

![CI](https://github.com/KitsuneSemCalda/Dotfiles/actions/workflows/installers.yml/badge.svg)
![Perl](https://img.shields.io/badge/installer-perl-39457e?logo=perl&logoColor=white)
![PowerShell](https://img.shields.io/badge/installer-powershell-5391fe?logo=powershell&logoColor=white)
![Built for Omarchy](https://img.shields.io/badge/built%20for-omarchy-1793d1)

> Personal setup for **Omarchy (Hyprland)** and **Windows 11**, plus a library
> of **AI coding-agent skills** that installs into every agent CLI on the machine.

Installers **copy** files instead of symlinking them, so you can move or delete
this clone afterwards and the installed configuration keeps working. Both
installers are tested on Linux and Windows in CI on every push.

## What's inside

| Module | What it is | Installer |
|--------|------------|-----------|
| [`SamsungBook-Np550xda/Omarchy`](SamsungBook-Np550xda/Omarchy/README.md) | Hyprland (Lua), Alacritty, btop, GTK, fonts, starship, webapps, power profile and an optional Docker stack | `omarchy.pl` (Perl) |
| [`SamsungBook-Np550xda/Windows-11`](SamsungBook-Np550xda/Windows-11/README.md) | GlazeWM, PowerShell profile, Windows Terminal scheme, Rainmeter HUD and a debloat script | `win11.ps1` (PowerShell) |
| [`Skill-Library`](Skill-Library/README.md) | Curated `SKILL.md` skills for Claude Code, Codex and other agent CLIs | `install.pl` / `install.ps1` |

The machine profiles are tied to one laptop, the Samsung NP550XDA-KF2BR. The
[architecture notes](SamsungBook-Np550xda/docs/architecture.md) explain the
layers, what changes on the base system and the limits of restoring it, with
Mermaid diagrams.

## Quick start

```sh
git clone https://github.com/KitsuneSemCalda/Dotfiles.git
cd Dotfiles

# Omarchy
perl SamsungBook-Np550xda/Omarchy/omarchy.pl

# Windows 11 (PowerShell)
./SamsungBook-Np550xda/Windows-11/win11.ps1
```

Only want the skills, on any machine?

```sh
perl Skill-Library/install.pl --list      # see skills and detected agents
perl Skill-Library/install.pl --dry-run   # preview without copying
perl Skill-Library/install.pl             # install into every detected agent
```

## Skill library

Each skill teaches an agent something non-obvious about a real workflow. The
current set:

`algorithmic-project-review` · `blog-reader-panel` · `github-project-health` ·
`humanizer` · `i-have-adhd` · `learn-from-work` · `ponytail` ·
`preserve-my-english` · `quantify-ambition`

The format is the same `SKILL.md` convention Claude Code and Codex share, so a
skill needs no per-agent adaptation. See the
[Skill-Library README](Skill-Library/README.md) for details.

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

## License

[BSD 3-Clause](LICENSE).
