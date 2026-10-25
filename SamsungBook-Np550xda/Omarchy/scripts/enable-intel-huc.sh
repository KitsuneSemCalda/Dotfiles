#!/usr/bin/env bash
# Intel's documented Tiger Lake workaround for low-power bitrate control.
# No module reload: the running desktop keeps its current driver until reboot.
set -euo pipefail

[[ $EUID == 0 ]] || { echo 'Run with pkexec or sudo.' >&2; exit 1; }
[[ $(</sys/class/dmi/id/board_name) == NP550XDA-KF2BR ]] || {
  echo 'This adjustment was checked only for NP550XDA-KF2BR.' >&2; exit 1;
}
config=/etc/modprobe.d/60-dotfiles-intel-huc.conf
contents=$'# Enable HuC firmware for Tiger Lake low-power encoder bitrate control.\noptions i915 enable_guc=2'
action=${1:---apply}
[[ $# -le 1 && ( $action == --apply || $action == --restore ) ]] || exit 2

if [[ $action == --restore ]]; then
  [[ -f $config && $(<"$config") == "$contents" ]] || {
    echo 'Managed config absent or modified; refusing removal.' >&2; exit 1;
  }
  rm -- "$config"
else
  [[ -r /sys/module/i915/parameters/enable_guc ]] || exit 1
  # Recheck even on a repeat install: another file or the kernel command line
  # may have gained a conflicting policy since this managed file was created.
  while IFS= read -r policy; do
    if [[ $policy =~ ^options[[:space:]]+i915[[:space:]].*enable_guc=([^[:space:]]+) \
      && ${BASH_REMATCH[1]} != 2 ]]; then
      echo 'Conflicting enable_guc policy; refusing to claim HuC is enforced.' >&2; exit 1
    fi
  done < <(/usr/bin/modprobe -c)
  cmdline=$(</proc/cmdline)
  if [[ $cmdline =~ (^|[[:space:]])i915.enable_guc=([^[:space:]]+) \
    && ${BASH_REMATCH[2]} != 2 ]]; then
    echo 'Conflicting i915.enable_guc kernel argument; review boot configuration.' >&2; exit 1
  fi
  [[ -f /usr/lib/firmware/i915/tgl_huc.bin.zst ]] || {
    echo 'Tiger Lake HuC firmware missing; nothing changed.' >&2; exit 1;
  }
  if [[ -e $config ]]; then
    [[ $(<"$config") == "$contents" ]] || { echo "Refusing to overwrite $config" >&2; exit 1; }
  else
    printf '%s\n' "$contents" > "$config"
    chmod 0644 "$config"
  fi
fi

# Omarchy uses Limine UKIs; modconf must be included in the regenerated image.
if ! /usr/bin/limine-mkinitcpio; then
  echo "Boot image rebuild failed. Review $config and rerun limine-mkinitcpio before reboot." >&2
  exit 1
fi
echo 'Boot images rebuilt. Reboot when convenient, then repeat the encoder test.'
