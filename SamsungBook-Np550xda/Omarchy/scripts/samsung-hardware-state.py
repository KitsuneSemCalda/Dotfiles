#!/usr/bin/python3 -I
"""Reconcile the tested Samsung policy at boot and explicit installation."""
import json
import os
from pathlib import Path
import subprocess
import time

SYS = Path('/sys')
REPORT = Path('/var/lib/dotfiles-samsung/hardware.json')
BOOT_ID = Path('/proc/sys/kernel/random/boot_id')


def command(*args):
    return subprocess.check_output(args, text=True, timeout=15).strip()


def enforce(path, value):
    if path.read_text().strip() != value:
        path.write_text(value + '\n')
    if path.read_text().strip() != value:
        raise RuntimeError(f'{path} did not retain {value}')


def reconcile():
    if (SYS / 'class/dmi/id/board_name').read_text().strip() != 'NP550XDA-KF2BR':
        raise RuntimeError('Unsupported board')
    threshold = SYS / 'class/power_supply/BAT1/charge_control_end_threshold'
    for _ in range(20):
        if threshold.exists():
            break
        time.sleep(1)
    enforce(threshold, '80')
    devices = []
    for device in (SYS / 'bus/pci/devices').glob('*'):
        wanted = {'vendor': '0x10ec', 'device': '0x8168',
                  'subsystem_vendor': '0x144d', 'subsystem_device': '0xc195'}
        if all((device / key).exists() and (device / key).read_text().strip() == value
               for key, value in wanted.items()):
            devices.append(device)
    if len(devices) != 1 or (devices[0] / 'driver').resolve().name != 'r8169':
        raise RuntimeError('Expected one Samsung r8169 adapter')
    enforce(devices[0] / 'power/control', 'auto')
    for service in ('thermald.service', 'power-profiles-daemon.service'):
        command('/usr/bin/systemctl', 'is-enabled', '--quiet', service)
        command('/usr/bin/systemctl', 'is-active', '--quiet', service)
    guc = (SYS / 'module/i915/parameters/enable_guc').read_text().strip()
    result = {'boot_id': BOOT_ID.read_text().strip(), 'battery_end_threshold': 80,
              'ethernet_runtime_control': 'auto', 'system_services': 'enabled and active',
              'huc_pending_reboot': guc != '2', 'i915_enable_guc': guc}
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    staged = REPORT.with_suffix('.tmp')
    staged.write_text(json.dumps(result, indent=2) + '\n')
    staged.replace(REPORT)
    print(json.dumps(result))
    if result['huc_pending_reboot']:
        print('PENDING: reboot to load the configured HuC policy; encoding is not yet verified.')
    return result


if __name__ == '__main__':
    if os.geteuid() != 0:
        raise SystemExit('Expected root')
    reconcile()
