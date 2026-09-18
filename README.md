# Dotfiles

Two independent modules, versioned in one repository:

- [`SamsungBook-Np550xda/`](SamsungBook-Np550xda/README.md) — personalizations
  for the Samsung NP550XDA-KF2BR: Omarchy/Hyprland and Windows 11 profiles,
  fonts, terminals, apps, and the optional Docker stack. Tied to this
  specific machine.
- [`Skill-Library/`](Skill-Library/README.md) — personal library of AI
  coding-agent skills (`SKILL.md` format), installed globally into every
  agent CLI detected on a machine. Machine-independent, with a native
  installer per platform (`install.pl` for Linux, `install.ps1` for Windows).

Each machine's installer (`omarchy.pl` / `win11.ps1`) runs the matching
Skill-Library installer as part of its own install, so skills stay in sync
with the rest of the dotfiles without an extra manual step.
