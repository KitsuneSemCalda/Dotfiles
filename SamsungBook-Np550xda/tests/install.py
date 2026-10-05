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

    # Exercise the whole desktop reinstall without a real desktop/network.
    import json
    fixtures = root / 'fixtures'
    fixtures.mkdir()
    log = root / 'commands.jsonl'
    fake_bin = root / 'fakebin'
    fake_bin.mkdir()
    ids = {
        'Spaces': 'tornikegomareli.spaces',
        'Widget-on-glass': 'kitsuneforgering.widget-on-glass',
    }
    for name in ['OmaStore', 'Feader-RSS', *ids]:
        directory = fixtures / name
        directory.mkdir()
        plugin = directory
        if name in ids:
            (plugin / 'manifest.json').write_text(json.dumps({'id': ids[name]}))
            (plugin / 'widget.qml').write_text('new plugin content')
    (fixtures / 'OmaStore/packaging').mkdir()
    (fixtures / 'OmaStore/packaging/install.sh').write_text(
        '#!/bin/sh\nmkdir -p "$HOME/.local/bin"\ncp "$FAKE_BIN/omastore" "$HOME/.local/bin/omastore"\n')
    (fixtures / 'Feader-RSS/scripts').mkdir()
    (fixtures / 'Feader-RSS/scripts/install.sh').write_text(
        '#!/bin/sh\nset -eu\n[ -z "${FAIL_BACKEND:-}" ] || exit 1\n'
        'p="$HOME/.config/omarchy/plugins/io.github.kitsunesemcalda.feader-rss"\n'
        'mkdir -p "$p"\necho rebuilt-backend > "$p/feader-rss-fetch"\nchmod +x "$p/feader-rss-fetch"\n')
    fake_tool = fake_bin / 'tool'
    fake_tool.write_text(r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['COMMAND_LOG'], 'a') as f:
    f.write(json.dumps([name, *args]) + '\n')
if name == 'git' and args[0] == 'clone':
    dest = pathlib.Path(args[-1])
    shutil.copytree(pathlib.Path(os.environ['FIXTURES']) / dest.name, dest)
    (dest / '.git').mkdir()
elif name == 'hyprctl' and args[0] == 'configerrors':
    print(os.environ.get('CONFIG_ERRORS', ''), end='')
elif name == 'omarchy' and args[:2] == ['plugin', 'list']:
    ids = ['tornikegomareli.spaces', 'io.github.kitsunesemcalda.feader-rss', 'kitsuneforgering.widget-on-glass']
    print(json.dumps([{'id': x, 'enabled': True} for x in ids]))
elif name == 'omarchy' and args[:2] == ['plugin', 'validate']:
    assert (pathlib.Path(args[2]) / 'manifest.json').is_file()
''')
    fake_tool.chmod(0o755)
    for name in ['git', 'omarchy', 'omarchy-shell', 'hyprctl', 'systemctl']:
        (fake_bin / name).symlink_to(fake_tool)
    env = {**os.environ, 'HOME': str(target), 'PATH': f"{fake_bin}:{os.environ['PATH']}",
           'FIXTURES': str(fixtures), 'COMMAND_LOG': str(log), 'FAKE_BIN': str(fake_bin)}

    def run_plugin(*args, success=True, extra_env=None):
        result = subprocess.run(['perl', str(repo / 'omarchy.pl'), *args],
                                capture_output=True, text=True, env={**env, **(extra_env or {})})
        assert (result.returncode == 0) == success, result.stdout + result.stderr
        return result

    run_plugin('--plugin', '--reboot')
    backend = target / '.config/omarchy/plugins/io.github.kitsunesemcalda.feader-rss/feader-rss-fetch'
    assert backend.stat().st_mode & 0o111
    commands = [json.loads(line) for line in log.read_text().splitlines()]
    assert commands[-1] == ['systemctl', 'reboot']
    assert not any(cmd[0] == 'omastore' for cmd in commands)
    all_ids = [*ids.values()]
    for plugin_id in all_ids:
        directory = target / '.config/omarchy/plugins' / plugin_id
        (directory / 'obsolete.qml').write_text('old')
    backend.write_text('outdated backend')
    log.write_text('')
    run_plugin('--plugins')
    assert backend.read_text() == 'rebuilt-backend\n'
    for plugin_id in all_ids:
        assert not (target / '.config/omarchy/plugins' / plugin_id / 'obsolete.qml').exists()
        assert list((target / '.local/state/dotfiles/plugin-backups').glob(f'*/{plugin_id}/obsolete.qml'))
    assert ['systemctl', 'reboot'] not in [json.loads(line) for line in log.read_text().splitlines()]
    before = log.read_bytes()
    preview = run_plugin('--all', '--reboot', '--dry-run')
    assert log.read_bytes() == before
    assert "'systemctl' 'reboot'" in preview.stdout
    log.write_text('')
    run_plugin('--plugin', '--reboot', success=False, extra_env={'FAIL_BACKEND': '1'})
    assert ['systemctl', 'reboot'] not in [json.loads(line) for line in log.read_text().splitlines()]
    log.write_text('')
    run_plugin('--reboot', success=False, extra_env={'CONFIG_ERRORS': 'invalid config'})
    assert ['systemctl', 'reboot'] not in [json.loads(line) for line in log.read_text().splitlines()]
    run('--plugin', success=False)  # A test --target cannot request desktop actions.
    run_plugin('--restore', '--reboot', success=False)
print('OK: copies, backup/restore, current plugin replacement, backend and reboot guards')
