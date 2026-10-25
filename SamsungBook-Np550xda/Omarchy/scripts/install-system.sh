#!/usr/bin/env bash
set -euo pipefail

[[ $EUID == 0 ]] || { echo 'This script must run as root' >&2; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
openrgb_dir=''
ek75_knob=false
home_backup=false
clamshell=false
hardware=false
maintenance_user=''

while (($#)); do
  case $1 in
    --openrgb)
      (($# >= 2)) || { echo 'Missing OpenRGB directory' >&2; exit 2; }
      openrgb_dir=$2
      shift 2
      ;;
    --clamshell) clamshell=true; shift ;;
    --hardware) hardware=true; shift ;;
    --maintenance)
      (($# >= 2)) || { echo 'Missing maintenance user' >&2; exit 2; }
      maintenance_user=$2; shift 2 ;;
    --ek75-knob) ek75_knob=true; shift ;;
    --home-backup) home_backup=true; shift ;;
    *) echo "Unknown system installation action: $1" >&2; exit 2 ;;
  esac
done

if [[ $hardware == true ]]; then
  [[ $(</sys/class/dmi/id/board_name) == NP550XDA-KF2BR ]] || {
    echo 'Hardware enforcement requires NP550XDA-KF2BR' >&2; exit 1;
  }
  bash "$script_dir/enable-intel-huc.sh"
  bash "$script_dir/enable-samsung-ethernet-pm.sh"
  install -D -o root -g root -m 0755 "$script_dir/samsung-hardware-state.py" /usr/local/libexec/dotfiles-samsung-hardware
  install -D -o root -g root -m 0644 "$script_dir/systemd/dotfiles-samsung-hardware.service" /etc/systemd/system/dotfiles-samsung-hardware.service
  systemctl daemon-reload
  systemctl enable --now thermald.service power-profiles-daemon.service
  systemctl enable dotfiles-samsung-hardware.service
  systemctl restart dotfiles-samsung-hardware.service
  systemctl is-active --quiet dotfiles-samsung-hardware.service
fi

if [[ -n $maintenance_user ]]; then
  [[ $maintenance_user =~ ^[a-z_][a-z0-9_-]*$ ]] && id "$maintenance_user" >/dev/null || exit 2
  install -D -o root -g root -m 0755 "$script_dir/maintenance/root.py" /usr/local/libexec/dotfiles-maintenance-root
  install -D -o root -g root -m 0755 "$script_dir/maintenance/maintenance.py" /usr/local/bin/dotfiles-maintenance
  install -D -o root -g root -m 0755 "$script_dir/maintenance/sudo" /usr/local/libexec/dotfiles-maintenance-bin/sudo
  for unit in dotfiles-maintenance.service dotfiles-maintenance.timer; do
    install -D -o root -g root -m 0644 "$script_dir/maintenance/$unit" "/etc/systemd/user/$unit"
  done
  policy=$(mktemp)
  trap 'rm -f -- "$policy"' EXIT
  printf 'e /tmp - - - 7d\ne /var/tmp - - - 7d\n' > "$policy"
  install -o root -g root -m 0644 "$policy" /etc/dotfiles-maintenance-tmpfiles.conf
  printf '%s ALL=(root) NOPASSWD: /usr/local/libexec/dotfiles-maintenance-root *\n' "$maintenance_user" > "$policy"
  visudo -cf "$policy"
  install -o root -g root -m 0440 "$policy" "/etc/sudoers.d/dotfiles-maintenance-$maintenance_user"
fi

if [[ -n $openrgb_dir ]]; then
  [[ -f $openrgb_dir/tools/install-udev.sh && -f $openrgb_dir/udev/70-dareu-ek75.rules ]] || {
    echo "Missing OpenRGB udev installer in $openrgb_dir" >&2; exit 1;
  }
  bash "$openrgb_dir/tools/install-udev.sh"
fi

if [[ $ek75_knob == true ]]; then
  install -m 0644 "$script_dir/udev/61-ek75-knob.hwdb" /etc/udev/hwdb.d/61-ek75-knob.hwdb
  systemd-hwdb --strict update
fi

if [[ $home_backup == true ]]; then
  install -D -m 0755 "$script_dir/../home/.local/bin/backup-zip" /usr/local/libexec/dotfiles-backup-zip
  install -D -m 0755 "$script_dir/btrfs-monthly-backup" /usr/local/libexec/btrfs-monthly-backup
  for unit in home-btrfs-monthly.service home-btrfs-monthly.timer; do
    install -D -m 0644 "$script_dir/systemd/$unit" "/etc/systemd/system/$unit"
  done
  systemctl daemon-reload
  systemctl enable --now home-btrfs-monthly.timer
fi

if [[ $clamshell == true ]]; then
  install -D -m 0644 "$script_dir/logind/60-dotfiles-clamshell.conf" \
    /etc/systemd/logind.conf.d/60-dotfiles-clamshell.conf
  systemctl reload systemd-logind
  echo 'Clamshell policy installed and logind reloaded.'
fi
