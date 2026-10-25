#!/usr/bin/env python3
"""Verify archive content, migration and lossless annual consolidation."""
from pathlib import Path
import runpy
import json
import subprocess
import sqlite3
import stat
import tempfile
from unittest.mock import patch
import zipfile

helper = Path(__file__).resolve().parents[1] / 'home/.local/bin/backup-zip'
api = runpy.run_path(str(helper))
pack, consolidate, migrate = (api[name] for name in ('pack', 'consolidate', 'migrate'))
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    invalid = root / 'invalid-btrfs.zip'
    with zipfile.ZipFile(invalid, 'w') as archive:
        archive.writestr('manifest.json', json.dumps({'format': 'btrfs-send', 'kind': 'full', 'parent': None}))
        archive.writestr('root.send', b'not a Btrfs stream')
    try:
        api['verify'](invalid, True)
    except subprocess.CalledProcessError:
        pass
    else:
        raise AssertionError('Invalid Btrfs stream was accepted')
    source, backups = root / 'source', root / 'backups'
    source.mkdir()
    corrupt = source / 'corrupt.db'
    corrupt.write_bytes(b'SQLite format 3\0' + b'invalid' * 100)
    staged = root / 'staged'
    staged.mkdir()
    (staged / corrupt.name).write_bytes(corrupt.read_bytes())
    try:
        api['sqlite_copies'](source, staged)
    except sqlite3.DatabaseError:
        pass
    else:
        raise AssertionError('Corrupt SQLite database was accepted')
    corrupt.unlink()
    (source / 'empty').mkdir()
    (source / 'ação.txt').write_text('Portuguese filename')
    (source / '.private').write_bytes(b'first\x00content')
    (source / '.private').chmod(0o600)
    (source / 'link').symlink_to('.private')
    first = backups / '2026/2026-01-01.zip'
    pack(source, first)
    with zipfile.ZipFile(first) as archive:
        assert archive.read('.private') == b'first\x00content'
        assert stat.S_IMODE(archive.getinfo('.private').external_attr >> 16) == 0o600
        assert stat.S_ISLNK(archive.getinfo('link').external_attr >> 16)
    first_bytes = first.read_bytes()
    (source / '.private').write_text('second version')
    second = backups / '2026/2026-02-01.zip'
    pack(source, second)
    second_bytes = second.read_bytes()
    consolidate(backups, 2026)
    assert first.exists() and not (backups / 'history.zip').exists()
    with patch.dict(consolidate.__globals__, publish=lambda *args: (_ for _ in ()).throw(OSError('disk failure'))):
        try:
            consolidate(backups, 2027)
        except OSError:
            pass
        else:
            raise AssertionError('publication failure was ignored')
    assert first.exists() and second.exists()
    consolidate(backups, 2027)
    assert not first.parent.exists()
    with zipfile.ZipFile(backups / 'history.zip') as annual:
        assert annual.read('2026/2026-01-01.zip') == first_bytes
        assert annual.read('2026/2026-02-01.zip') == second_bytes
    # Recover an interrupted cleanup after publishing an annual ZIP.
    first.parent.mkdir()
    first.write_bytes(first_bytes)
    consolidate(backups, 2027)
    assert not first.parent.exists()
    first.parent.mkdir()
    first.write_bytes(b'corrupt')
    previous = (backups / 'history.zip').read_bytes()
    try:
        consolidate(backups, 2027)
    except zipfile.BadZipFile:
        pass
    else:
        raise AssertionError('corrupt source was discarded')
    assert first.read_bytes() == b'corrupt' and (backups / 'history.zip').read_bytes() == previous
    first.unlink()
    first.parent.rmdir()
    # Existing annual ZIPs stay nested; another completed year joins the same
    # history file, without discarding versions from earlier consolidations.
    legacy_annual = backups / '2025.zip'
    legacy_annual.write_bytes(first_bytes)
    another = backups / '2027/2027-01-01.zip'
    another.parent.mkdir()
    another.write_bytes(second_bytes)
    consolidate(backups, 2028)
    with zipfile.ZipFile(backups / 'history.zip') as history:
        assert history.read('2025.zip') == first_bytes
        assert history.read('2026/2026-01-01.zip') == first_bytes
        assert history.read('2027/2027-01-01.zip') == second_bytes
        assert all(info.compress_type == zipfile.ZIP_DEFLATED for info in history.infolist())
    assert not legacy_annual.exists() and not another.parent.exists()

    legacy, state = root / 'legacy', root / 'state'
    (legacy / 'current').mkdir(parents=True)
    (legacy / 'current/note').write_text('legacy file')
    (legacy / 'history').mkdir()
    (legacy / 'history/old').write_text('older version')
    (legacy / 'monthly').mkdir()
    (legacy / 'monthly/2025.tar.zst').write_bytes(b'original chain')
    migrate(legacy, state, '2026-10-24')
    assert (state / 'current/note').read_text() == 'legacy file'
    assert (state / 'history/old').read_text() == 'older version'
    assert not (legacy / 'monthly').exists()
    with zipfile.ZipFile(state / 'archives/home/2026/2026-10-24-legacy.zip') as archive:
        assert archive.read('monthly/2025.tar.zst') == b'original chain'
    assert all(p.suffix == '.zip' for p in legacy.rglob('*') if p.is_file())
print('OK: ZIP permissions/symlinks, nested local history, failed publication and legacy migration')
