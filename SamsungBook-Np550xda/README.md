# Dotfiles — Samsung Book NP550XDA

Personalizations for the Samsung NP550XDA-KF2BR on Omarchy and Windows 11: desktop,
fonts, terminals, applications, and automation. The installers assume an
operating system is already installed; they do not provision partitions, a bootloader, or drivers.

- [Analysis and diagrams of the modifications](docs/architecture.md): layers, differences
  from the base system, installation, power, services, and restore limits.
- [Omarchy profile](Omarchy/README.md): installation and optional Docker stack.
- [Windows 11 profile](Windows-11/README.md): installation, shortcuts, and debloat.
- [Maintenance](docs/maintenance.md): scheduling, reports, updates and recovery on both systems.
- [Capture setup](docs/capture.md): OBS profiles, PipeWire audio and OmaTuber integration.
- [Intel acceleration and model storage](Omarchy/docs/ai-acceleration.md): GPU API checks and shared model paths.
- [inferctl](Omarchy/calibration/inferctl/README.md): Linux AI benchmarks and resource control, built separately.

The Omarchy profile keeps full backups locally and publishes selected essentials
as one Dropbox ZIP under a total local storage budget. inferctl has its own
profiles and validation record; applying the dotfiles does not calibrate models
or start ComfyUI.

The diagrams are Mermaid, editable directly in Markdown and rendered by
GitHub. The analysis documents the repository's code; it does not certify that all
personalizations are applied on the machine.
