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
        'Liquid-Glass': 'io.github.fasi96.liquid-glass',
        'OmaVM': 'dev.omavm.bar',
    }
    for name in ['OmaStore', 'Feader-RSS', *ids]:
        directory = fixtures / name
        directory.mkdir()
        plugin = directory / 'contrib/dev.omavm.bar' if name == 'OmaVM' else directory
        plugin.mkdir(parents=True, exist_ok=True)
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
    (fixtures / 'Liquid-Glass/install.sh').write_text(
        '#!/bin/sh\nset -eu\ntest -f "$HOME/.config/omarchy-liquid-glass/state.json"\n'
        'test -f "$HOME/.config/omarchy-liquid-glass/looks.json"\n')
    ai = root / 'ai-release'
    (ai / 'bin').mkdir(parents=True)
    (ai / 'bin/omarchy-ai').write_text('#!/bin/sh\n')
    (ai / 'bin/omarchy-ai').chmod(0o755)
    (ai / 'install.sh').write_text('#!/bin/sh\nexit 0\n')
    for suffix in ['settings', 'watchdog', 'assistant-huds', 'chat-hud', 'window-labels', 'myapi', 'tv-discovery', 'quota-alert']:
        plugin = ai / 'quickshell/plugins' / ('omarchy-ai.' + suffix)
        plugin.mkdir(parents=True)
        (plugin / 'manifest.json').write_text(json.dumps({'id': 'omarchy-ai.' + suffix}))
    vm = root / 'vm-release/bin'
    vm.mkdir(parents=True)
    for name in ['omavm', 'omavm-gui']:
        (vm / name).write_text('#!/bin/sh\n')
        (vm / name).chmod(0o755)
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
elif name == 'omastore' and args[0] == 'show':
    print(json.dumps({'Install': {'ExecPath': os.environ['VM_EXEC' if args[-1].endswith('/OmaVM') else 'AI_EXEC']}}))
elif name == 'hyprctl' and args[0] == 'configerrors':
    print(os.environ.get('CONFIG_ERRORS', ''), end='')
elif name == 'omarchy' and args[:2] == ['plugin', 'list']:
    ids = ['tornikegomareli.spaces', 'io.github.fasi96.liquid-glass', 'io.github.kitsunesemcalda.feader-rss', 'dev.omavm.bar']
    ids += ['omarchy-ai.' + x for x in ['settings', 'watchdog', 'assistant-huds', 'chat-hud', 'window-labels', 'myapi', 'tv-discovery', 'quota-alert']]
    print(json.dumps([{'id': x, 'enabled': True} for x in ids]))
elif name == 'omarchy' and args[:2] == ['plugin', 'validate']:
    assert (pathlib.Path(args[2]) / 'manifest.json').is_file()
''')
    fake_tool.chmod(0o755)
    for name in ['git', 'omarchy', 'omarchy-shell', 'omastore', 'hyprctl', 'systemctl']:
        (fake_bin / name).symlink_to(fake_tool)
    glass_config = target / '.config/omarchy-liquid-glass'
    glass_config.mkdir(parents=True)
    (glass_config / 'state.json').write_text('{"glass_on": false, "blur_strength": 0.5}')
    (glass_config / 'looks.json').write_text('{"active": null}')
    saved_glass = [p.read_bytes() for p in sorted(glass_config.iterdir())]
    env = {**os.environ, 'HOME': str(target), 'PATH': f"{fake_bin}:{os.environ['PATH']}",
           'FIXTURES': str(fixtures), 'COMMAND_LOG': str(log), 'FAKE_BIN': str(fake_bin),
           'VM_EXEC': str(vm / 'omavm-gui'), 'AI_EXEC': str(ai / 'bin/omarchy-ai')}

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
    assert ['systemctl', '--user', 'restart', 'omarchy-ai.service'] in commands
    assert (target / '.local/bin/omavm').stat().st_mode & 0o111
    all_ids = [*ids.values(), *['omarchy-ai.' + x for x in ['settings', 'watchdog', 'assistant-huds', 'chat-hud', 'window-labels', 'myapi', 'tv-discovery', 'quota-alert']]]
    for plugin_id in all_ids:
        directory = target / '.config/omarchy/plugins' / plugin_id
        (directory / 'obsolete.qml').write_text('old')
    cli_launcher = target / '.local/bin/omavm'
    cli_launcher.unlink()
    cli_launcher.symlink_to(vm / 'omavm')
    backend.write_text('outdated backend')
    log.write_text('')
    run_plugin('--plugins')
    assert backend.read_text() == 'rebuilt-backend\n'
    assert (vm / 'omavm').read_text() == '#!/bin/sh\n', 'replacement followed the old CLI symlink'
    for plugin_id in all_ids:
        assert not (target / '.config/omarchy/plugins' / plugin_id / 'obsolete.qml').exists()
        assert list((target / '.local/state/dotfiles/plugin-backups').glob(f'*/{plugin_id}/obsolete.qml'))
    assert saved_glass == [p.read_bytes() for p in sorted(glass_config.iterdir())]
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
print('OK: copies, backup/restore, plugin replacement, backends, Liquid Glass preservation and reboot guards')
