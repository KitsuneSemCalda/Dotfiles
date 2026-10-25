#!/usr/bin/python3 -I
"""Privileged entrypoint: fixed operations, no caller paths or environment."""
import os
import subprocess
import sys
import json
import shutil

ENV = {'PATH': '/usr/share/omarchy/bin:/usr/bin', 'HOME': '/root', 'USER': 'root',
       'OMARCHY_PATH': '/usr/share/omarchy', 'OMARCHY_UPDATE_UNATTENDED': '1',
       'LC_ALL': 'C', 'OMARCHY_UPDATE_PACMAN': '1'}
ACTIONS = {
    'prune': ['/usr/bin/paccache', '-rk2'],
    'snapshot': ['/usr/share/omarchy/bin/omarchy-snapshot', 'create'],
    'keyring': ['/usr/bin/bash', '-e', '/usr/share/omarchy/bin/omarchy-update-keyring'],
    'system': ['/usr/share/omarchy/bin/omarchy-update-system-pkgs'],
    'trim': ['/usr/bin/fstrim', '--all', '--verbose'],
    'temporary': ['/usr/bin/systemd-tmpfiles', '--clean', '/etc/dotfiles-maintenance-tmpfiles.conf'],
    'flatpak-system': ['/usr/bin/flatpak', 'update', '--system', '--noninteractive', '-y'],
    'health': ['/usr/bin/journalctl', '-k', '-p', 'err', '--since', '7 days ago', '-n', '30', '--no-pager'],
}

def main():
    if os.geteuid() != 0 or len(sys.argv) != 2 or sys.argv[1] not in ACTIONS:
        raise SystemExit('Expected root and one fixed maintenance action')
    # Package transactions cannot overlap even across different user schedulers.
    import fcntl
    with open('/run/dotfiles-maintenance-root.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        action = sys.argv[1]
        if action == 'health':
            if not shutil.which('smartctl', path=ENV['PATH']):
                raise SystemExit('SMART collector unavailable: install smartmontools')
            listing = subprocess.run(['/usr/bin/lsblk', '-dnpo', 'NAME,TYPE'], env=ENV, capture_output=True, text=True, check=True)
            results = []; failed = False
            for line in listing.stdout.splitlines():
                device, kind = line.split()
                if kind != 'disk':
                    continue
                result = subprocess.run(['/usr/bin/smartctl', '-H', '-j', device], env=ENV, capture_output=True, text=True)
                # smartctl returns a bitmask, including commands unsupported by USB bridges.
                results.append({'device': device, 'code': result.returncode, 'output': result.stdout or result.stderr})
                failed = failed or bool(result.returncode)
            print(json.dumps(results))
            raise SystemExit(int(failed or not results))
        if action == 'prune' and subprocess.run(['/usr/bin/systemctl', 'is-enabled', '--quiet', 'paccache.timer'], env=ENV).returncode == 0:
            print('Native paccache.timer already enabled; its retention policy is preserved')
            raise SystemExit(0)
        # A pre-existing native trim timer owns this work when enabled.
        if action == 'trim' and subprocess.run(['/usr/bin/systemctl', 'is-enabled', '--quiet', 'fstrim.timer'], env=ENV).returncode == 0:
            print('Native fstrim.timer already enabled')
            raise SystemExit(0)
        args = ACTIONS[action]
        if action in ('keyring', 'system', 'flatpak-system'):
            args = ['/usr/bin/systemd-inhibit', '--what=sleep', '--mode=block',
                    '--who=DotfilesMaintenance', '--why=Package transaction', *args]
        raise SystemExit(subprocess.run(args, env=ENV, stdin=subprocess.DEVNULL).returncode)


if __name__ == '__main__':
    main()
