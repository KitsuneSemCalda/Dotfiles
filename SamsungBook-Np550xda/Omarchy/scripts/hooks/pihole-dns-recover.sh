#!/bin/bash
set -uo pipefail

# Pi-hole's container can still be starting when systemd-resolved first tries
# 127.0.0.1, so resolved marks it as a bad server and keeps using the
# fallback (1.1.1.1) for the rest of the session even after Pi-hole becomes
# healthy — this is why DNS looks like it "reverts" on every reboot. Resetting
# the active interface's DNS list once Pi-hole is healthy makes resolved
# re-evaluate 127.0.0.1. This is an unprivileged resolve1 D-Bus call the
# active session is already allowed to make, so no root/pkexec is needed.

health=""
for _ in $(seq 1 60); do
    health=$(docker inspect --format '{{.State.Health.Status}}' omarchy-pihole 2>/dev/null)
    [[ $health == healthy ]] && break
    sleep 2
done

[[ $health == healthy ]] || exit 0

iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
[[ -n $iface ]] || exit 0

# A single-server list forces resolved to pick 127.0.0.1 as the current
# server unambiguously; handing it 127.0.0.1 alongside the 1.1.1.1 fallback
# again did not reliably win back "current" in testing, since resolved only
# re-picks when the previously-current server drops out of the list. The
# system-wide FallbackDNS in /etc/systemd/resolved.conf (set by `omarchy dns
# Custom`) still covers Pi-hole going down mid-session.
resolvectl dns "$iface" 127.0.0.1
