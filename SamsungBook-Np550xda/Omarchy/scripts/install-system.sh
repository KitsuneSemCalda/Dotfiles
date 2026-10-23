#!/usr/bin/env bash
set -euo pipefail

[[ $EUID == 0 ]] || { echo 'This script must run as root' >&2; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
openrgb_dir=''
ek75_knob=false
home_backup=false

while (($#)); do
  case $1 in
    --openrgb)
      (($# >= 2)) || { echo 'Missing OpenRGB directory' >&2; exit 2; }
      openrgb_dir=$2
      shift 2
      ;;
    --ek75-knob) ek75_knob=true; shift ;;
    --home-backup) home_backup=true; shift ;;
    *) echo "Unknown system installation action: $1" >&2; exit 2 ;;
  esac
done

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
  install -D -m 0755 "$script_dir/btrfs-monthly-backup" /usr/local/libexec/btrfs-monthly-backup
  for unit in home-btrfs-monthly.service home-btrfs-monthly.timer; do
    install -D -m 0644 "$script_dir/systemd/$unit" "/etc/systemd/system/$unit"
  done
  systemctl daemon-reload
  systemctl enable --now home-btrfs-monthly.timer
fi
