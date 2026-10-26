#!/usr/bin/python3 -I
"""Opt-in periodic TRIM for this Samsung's LUKS2 root; leave LUKS metadata unchanged."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

STATE = Path('/var/lib/dotfiles-root-trim')
def boot_trim(text):
    pattern = r"cryptdevice=([^\s:\"']+):root(?::([^\s\"']+))?"
    matches = list(re.finditer(pattern, text))
    if len(matches) != 1:
        raise RuntimeError('Expected exactly one root cryptdevice boot argument')
    def replace(match):
        flags = (match[2] or '').split(',')
        flags = [flag for flag in flags if flag]
        if 'allow-discards' not in flags:
            flags.append('allow-discards')
        return f"cryptdevice={match[1]}:root:" + ','.join(flags)
    return re.sub(pattern, replace, text)


def run(*args):
    return subprocess.check_output(args, text=True, timeout=300, stdin=subprocess.DEVNULL).strip()


def periodic_fstab(text, uuid):
    count = 0
    lines = []
    for line in text.splitlines(keepends=True):
        fields = list(re.finditer(r'\S+', line))
        if not line.lstrip().startswith('#') and len(fields) >= 4:
            if fields[0].group() in (f'UUID={uuid}', '/dev/mapper/root') and fields[2].group() == 'btrfs':
                field = fields[3]
                opts = [o for o in field.group().split(',') if o != 'discard' and not o.startswith('discard=') and o != 'nodiscard']
                line = line[:field.start()] + ','.join(opts + ['nodiscard']) + line[field.end():]
                count += 1
        lines.append(line)
    if not count:
        raise RuntimeError('No matching Btrfs root entries in fstab')
    return ''.join(lines)


def main():
    if os.geteuid() != 0 or sys.argv[1:] not in (['--apply'], ['--restore']):
        raise SystemExit('Expected root and --apply or --restore')
    if Path('/sys/class/dmi/id/board_name').read_text().strip() != 'NP550XDA-KF2BR':
        raise SystemExit('Unsupported board')
    device = '/dev/nvme0n1p2'
    status = run('/usr/bin/cryptsetup', 'status', 'root')
    if not re.search(r'type:\s+LUKS2', status) or not re.search(r'device:\s+' + device + r'\s', status + '\n'):
        raise SystemExit('Unexpected root mapping')
    # Boot option avoids changing the LUKS header or handling its passphrase.
    uuid = run('/usr/bin/findmnt', '-no', 'UUID', '/')
    fstab = Path('/etc/fstab')
    boot = Path('/etc/default/limine')
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    saved = STATE / 'original.json'
    if sys.argv[1] == '--apply':
        data = json.loads(saved.read_text()) if saved.exists() else {'fstab': fstab.read_text(), 'uuid': uuid}
        if data['uuid'] != uuid:
            raise SystemExit('Root filesystem changed; refusing installation')
        if 'boot' not in data:
            data['boot'] = boot.read_text()
        updated = periodic_fstab(data['fstab'], uuid)
        updated_boot = boot_trim(data['boot'])
        if fstab.read_text() not in (data['fstab'], updated) or boot.read_text() not in (data['boot'], updated_boot):
            raise SystemExit('Configuration changed since backup; refusing overwrite')
        saved.write_text(json.dumps(data)); saved.chmod(0o600)
        fstab.write_text(updated)
        boot.write_text(updated_boot)
    else:
        data = json.loads(saved.read_text())
        if data['uuid'] != uuid or fstab.read_text() != periodic_fstab(data['fstab'], uuid) or boot.read_text() != boot_trim(data['boot']):
            raise SystemExit('Configuration changed since installation; refusing rollback')
        fstab.write_text(data['fstab'])
        boot.write_text(data['boot'])
    run('/usr/bin/systemctl', 'daemon-reload')
    # Same UKI regeneration mechanism as the existing HuC installer.
    print(run('/usr/bin/limine-mkinitcpio'))
    print('Boot images rebuilt. Reboot required; existing dotfiles maintenance schedules periodic TRIM.')



if __name__ == '__main__':
    main()
