#!/usr/bin/env python3
"""Exercise installation with a disposable checkout and destination."""
import os
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

    # --plugin must not just enable Feader-RSS: `omarchy plugin add`/`enable`
    # alone only copies the repository, it never builds feader-rss-fetch (see
    # the plugin's own README). A fake `omarchy` stands in for the real one so
    # this runs without Omarchy or network access.
    plugin_id = 'io.github.kitsunesemcalda.feader-rss'
    plugin_dir = target / '.config/omarchy/plugins' / plugin_id
    install_sh = plugin_dir / 'scripts/install.sh'
    backend = plugin_dir / 'feader-rss-fetch'
    fake_bin = root / 'fakebin'
    fake_bin.mkdir()
    fake_omarchy = fake_bin / 'omarchy'
    fake_omarchy.write_text(f'''#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "plugin" && "$2" == "add" ]]; then
  mkdir -p "{plugin_dir}/scripts"
  cat > "{install_sh}" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo fake-binary > "{backend}"
chmod +x "{backend}"
EOS
  chmod +x "{install_sh}"
fi
''')
    fake_omarchy.chmod(0o755)
    # --plugin refuses to run against a --target that isn't the real HOME (so
    # tests can't accidentally touch it); point HOME at the disposable target
    # instead of passing --target, to exercise the real guarded code path.
    env = {**os.environ, 'PATH': f"{fake_bin}:{os.environ['PATH']}", 'HOME': str(target)}

    def run_plugin(*args, success=True):
        result = subprocess.run(
            ['perl', str(repo / 'omarchy.pl'), *args],
            capture_output=True, text=True, env=env,
        )
        assert (result.returncode == 0) == success, result.stdout + result.stderr
        return result

    run_plugin('--plugin')
    assert backend.is_file() and backend.stat().st_mode & 0o111, 'install.sh did not run after plugin add'

    # Already installed with a backend in place: re-enabling must not rebuild it.
    backend.write_text('sentinel\n')
    run_plugin('--plugin')
    assert backend.read_text() == 'sentinel\n', 'ensure_plugin rebuilt an already-present backend'

    # install.sh failing to produce a binary must fail the run instead of
    # silently leaving the plugin enabled with no backend to talk to.
    backend.unlink()
    install_sh.write_text('#!/usr/bin/env bash\nexit 0\n')
    install_sh.chmod(0o755)
    run_plugin('--plugin', success=False)
    assert not backend.exists()
print('OK: migration, copies, permissions, conflicts, backup collisions, restore failure, symlinks and plugin backend')
