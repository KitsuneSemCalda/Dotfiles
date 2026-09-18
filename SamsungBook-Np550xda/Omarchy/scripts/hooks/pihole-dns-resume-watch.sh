#!/bin/bash
set -uo pipefail

# Mirrors Omarchy's own pre-suspend lock monitor
# (/usr/share/omarchy/bin/omarchy-system-sleep-monitor), but reacts to the
# opposite edge: PrepareForSleep(false) fires once the machine has resumed.
# The post-boot hook alone only re-runs pihole-dns-recover.sh once per full
# boot; on a laptop that suspends far more often than it reboots, resolved
# never re-evaluates 127.0.0.1 on its own after a resume, so DNS stays stuck
# on the 1.1.1.1 fallback for the rest of the day after the first resume.
# Running as a long-lived systemd --user service and reading this signal
# directly needs no elevated privileges, same as the recovery script itself.

recover_script="$HOME/.config/omarchy/hooks/post-boot.d/pihole-dns-recover.sh"

dbus-monitor --system \
    "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" |
while IFS= read -r line; do
    [[ $line == *"boolean false"* ]] || continue
    [[ -x $recover_script ]] && "$recover_script"
done
