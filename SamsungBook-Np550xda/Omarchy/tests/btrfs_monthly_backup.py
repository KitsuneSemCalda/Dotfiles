#!/usr/bin/env python3
"""Exercise verified Btrfs ZIP publication, retry and failed send handling."""
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import struct
import zipfile

repo = Path(__file__).resolve().parents[1]
source = repo / 'scripts/btrfs-monthly-backup'
with TemporaryDirectory() as directory:
    root = Path(directory)
    home = root / 'home'
    (home / 'Dropbox').mkdir(parents=True)
    # Minimal valid protocol stream (END only), not a restorable filesystem.
    command = struct.pack('<IHI', 0, 21, 0)
    crc = 0
    for byte in command:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82F63B78 if crc & 1 else 0)
    payload = b'btrfs-stream\0' + struct.pack('<I', 1) + struct.pack('<IHI', 0, 21, crc)
    stream = root / 'valid.send'
    stream.write_bytes(payload)
    state = root / 'state'
    script = root / 'btrfs-monthly-backup'
    changes = {
        '[[ $EUID == 0 && $# == 1 ]]': '[[ $# == 1 ]]',
        '[[ $home == /home/* && $(findmnt -n -o FSTYPE -T /) == btrfs ]]': '[[ -d $home ]]',
        'date=$(date +%F)': 'date=2026-10-24',
        'state=/var/lib/home-dropbox-backup': f'state={state}',
        'helper=/usr/local/libexec/dotfiles-backup-zip': f'helper={repo}/home/.local/bin/backup-zip',
        'runuser -u "$owner" -- ': '',
        'btrfs subvolume snapshot -r / "$snapshot"': 'mkdir -p "$snapshot"',
        'btrfs send "$snapshot"': f'(if [[ ${{FAIL_SEND:-0}} == 1 ]]; then printf partial; exit 1; else cat "{stream}"; fi)',
        "source_kib=$(du -skx --exclude=/.snapshots --exclude=/var/lib/home-dropbox-backup / | awk '{ print $1 }')": 'source_kib=0',
        '(( available_kib >= source_kib * 2 + 10 * 1024 * 1024 ))': '(( available_kib >= source_kib ))',
        'btrfs subvolume delete -- "$old"': 'rmdir -- "$old"',
    }
    code = source.read_text()
    for old, new in changes.items():
        assert old in code, old
        code = code.replace(old, new)
    script.write_text(code)

    def run(**extra):
        return subprocess.run(['bash', str(script), str(home)], capture_output=True, text=True,
                              env={**os.environ, **extra})

    destination = home / '.local/state/home-dropbox-backup/archives/btrfs'
    archive = destination / '2026/2026-10-24.zip'
    failed = run(FAIL_SEND='1')
    assert failed.returncode != 0 and not archive.exists(), failed.stdout + failed.stderr
    result = run()
    assert result.returncode == 0, result.stdout + result.stderr
    with zipfile.ZipFile(archive) as saved:
        assert saved.read('root.send') == payload
        assert json.loads(saved.read('manifest.json'))['kind'] == 'full'
    assert 'already verified' in run().stdout
    archive.write_bytes(b'damaged')
    retried = run()
    assert retried.returncode == 0, retried.stdout + retried.stderr
    assert 'retrying 2026-10' in retried.stderr
    assert list((home / '.local/state/home-dropbox-backup/btrfs').glob('incomplete.*/*.zip'))
    assert all(p.suffix == '.zip' for p in destination.rglob('*') if p.is_file())
print('OK: full Btrfs ZIP, failed producer isolation, validation and quarantine')
