#!/usr/bin/env python3
"""Exercise installation with a disposable checkout and destination."""
import pathlib
import shutil
import subprocess
import tempfile

installer = pathlib.Path(__file__).resolve().parents[1] / 'Omarchy/omarchy.pl'
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    repo, target = root / 'repo', root / 'target'
    (repo / 'home').mkdir(parents=True)
    target.mkdir()
    shutil.copy2(installer, repo / 'omarchy.pl')
    source = repo / 'home/tool'
    source.write_text('original\n')
    source.chmod(0o755)
    dest = target / 'tool'

    def run(*args, success=True):
        result = subprocess.run(['perl', str(repo / 'omarchy.pl'), '--target', str(target), *args], capture_output=True, text=True)
        assert (result.returncode == 0) == success, result.stdout + result.stderr

    dest.symlink_to(source)
    run('--dry-run')
    assert dest.is_symlink()
    run()
    assert not dest.is_symlink() and dest.stat().st_mode & 0o111
    moved = root / 'moved'
    repo.rename(moved)
    assert dest.read_text() == 'original\n'
    moved.rename(repo)
    source.write_text('updated\n')
    run()
    assert dest.read_text() == 'updated\n'
    dest.write_text('user edit\n')
    run(success=False)
    assert dest.read_text() == 'user edit\n'
    run('--backup')
    dest.write_text('later edit\n')
    run('--restore', success=False)
    dest.write_text('updated\n')
    run('--restore')
    assert dest.read_text() == 'user edit\n'
    dest.unlink()
    run()
    assert dest.read_text() == 'updated\n'
print('OK: migration, independent copies, permissions, update, conflicts, backup and restore')
