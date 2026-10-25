#!/usr/bin/env bash
# Apply the bounded runtime-PM pilot recorded in docs/samsung-linux-research.md.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with pkexec or sudo.' >&2; exit 1; }
[[ $(</sys/class/dmi/id/board_name) == NP550XDA-KF2BR ]] || exit 1
device=/sys/bus/pci/devices/0000:02:00.0
[[ $(<"$device/vendor") == 0x10ec && $(<"$device/device") == 0x8168 \
  && $(<"$device/subsystem_vendor") == 0x144d \
  && $(<"$device/subsystem_device") == 0xc195 \
  && $(basename "$(readlink -f "$device/driver")") == r8169 ]] || exit 1

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_rule="$source_dir/udev/90-samsung-ethernet-runtime-pm.rules"
rule=/etc/udev/rules.d/90-samsung-ethernet-runtime-pm.rules
action=${1:---apply}
[[ $# -le 1 && ( $action == --apply || $action == --restore ) ]] || exit 2
if [[ -e $rule ]] && ! cmp -s "$source_rule" "$rule"; then
  echo "Refusing to replace or remove modified $rule" >&2; exit 1
fi
if [[ $action == --restore ]]; then
  [[ -f $rule ]] || { echo 'Managed rule absent; nothing changed.'; exit 1; }
  rm -- "$rule"
  udevadm control --reload-rules
  printf 'on\n' > "$device/power/control"
else
  udevadm verify "$source_rule"
  install -m 0644 "$source_rule" "$rule"
  udevadm control --reload-rules
  printf 'auto\n' > "$device/power/control"
fi
printf 'Runtime policy: '
cat "$device/power/control"
echo 'Driver decides when to suspend; no link or ASPM setting was forced.'
