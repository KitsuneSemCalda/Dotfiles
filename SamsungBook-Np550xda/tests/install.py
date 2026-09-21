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
    # Freeze the disposable installer's clock so backup collisions are deterministic.
    script = repo / 'omarchy.pl'
    clock = "strftime('%Y%m%d-%H%M%S', localtime)"
    assert clock in script.read_text()
    script.write_text(script.read_text().replace(clock, "'20260920-120000'"))
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
    dest.chmod(0o700)
    # A later conflict must prevent even earlier, conflict-free files from being copied.
    (repo / 'home/aaa').write_text('new file\n')
    run(success=False)
    assert dest.read_text() == 'user edit\n'
    assert not (target / 'aaa').exists()
    assert not (target / '.local/state/dotfiles/backups').exists()
    run('--backup')
    dest.write_text('later edit\n')
    run('--restore', success=False)
    dest.write_text('updated\n')
    backups = target / '.local/state/dotfiles/backups'
    first_backup = next(backups.glob('*/tool'))
    state = target / '.local/state/dotfiles/installed.json'
    previous_state = state.read_bytes()
    run('--restore', '--dry-run')
    assert dest.read_text() == 'updated\n'
    assert state.read_bytes() == previous_state
    # An unreadable backup must leave the installed file and its state intact.
    first_backup.chmod(0)
    run('--restore', success=False)
    assert dest.read_text() == 'updated\n'
    assert state.read_bytes() == previous_state
    first_backup.chmod(0o700)
    run('--restore')
    assert dest.read_text() == 'user edit\n'
    assert dest.stat().st_mode & 0o7777 == 0o700
    dest.write_text('second user edit\n')
    run('--backup', '--dry-run')
    assert len(list(backups.iterdir())) == 1
    run('--backup')
    assert sorted(p.read_text() for p in backups.glob('*/tool')) == [
        'second user edit\n', 'user edit\n',
    ]
    run('--restore')
    assert dest.read_text() == 'second user edit\n'
    assert dest.stat().st_mode & 0o7777 == 0o700
    dest.unlink()
    dest.symlink_to('missing-local-tool')
    run('--backup')
    run('--restore')
    assert dest.is_symlink() and dest.readlink() == pathlib.Path('missing-local-tool')
    dest.unlink()
    run()
    assert dest.read_text() == 'updated\n'
print('OK: migration, copies, permissions, conflicts, backup collisions, restore failure and symlinks')
