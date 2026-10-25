#!/usr/bin/env python3
"""Exercise installation with a disposable checkout and destination."""
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
from hashlib import md5

installer = pathlib.Path(__file__).resolve().parents[1] / 'Omarchy/omarchy.pl'
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    repo, target = root / 'repo', root / 'target'
    (repo / 'home').mkdir(parents=True)
    target.mkdir()
    shutil.copy2(installer, repo / 'omarchy.pl')
    system_installer = repo / 'scripts/install-system.sh'
    system_installer.parent.mkdir(parents=True)
    shutil.copy2(installer.parent / 'scripts/install-system.sh', system_installer)
    knob_rule = repo / 'scripts/udev/61-ek75-knob.hwdb'
    knob_rule.parent.mkdir(parents=True)
    shutil.copy2(installer.parent / 'scripts/udev/61-ek75-knob.hwdb', knob_rule)
    # Freeze the disposable installer's clock so backup collisions are deterministic.
    script = repo / 'omarchy.pl'
    clock = "strftime('%Y%m%d-%H%M%S', localtime)"
    assert clock in script.read_text()
    script.write_text(script.read_text().replace(clock, "'20260920-120000'"))
    source = repo / 'home/tool'
    source.write_text('original\n')
    source.chmod(0o755)
    audio_source = installer.parent / 'home/.config/omarchy/plugins/kitsuneforgering.audio'
    shutil.copytree(audio_source, repo / 'home/.config/omarchy/plugins/kitsuneforgering.audio')
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
        'omarchy-glass': 'kitsuneforgering.glass',
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
    openrgb_tools = fixtures / 'dareu-ek75-openrgb/tools'
    openrgb_tools.mkdir(parents=True)
    for step in ('build.sh', 'install-launcher.sh', 'install-hook.sh'):
        (openrgb_tools / step).write_text(f'#!/bin/sh\necho {step} >> "$HOME/openrgb-steps"\n')
    fake_tool = fake_bin / 'tool'
    fake_tool.write_text(r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'omarchy' and 'ai-jail-bin' in args and os.environ.get('FAIL_AI_PACKAGE'):
    sys.exit(1)
if name != 'pacman':
    with open(os.environ['COMMAND_LOG'], 'a') as f:
        f.write(json.dumps([name, *args]) + '\n')
if name == 'pacman':
    sys.exit(1)  # A fresh machine starts without optional packages.
elif name == 'git' and args[0] == 'clone':
    dest = pathlib.Path(args[-1])
    shutil.copytree(pathlib.Path(os.environ['FIXTURES']) / dest.name, dest)
    (dest / '.git').mkdir()
elif name == 'hyprctl' and args[0] == 'configerrors':
    print(os.environ.get('CONFIG_ERRORS', ''), end='')
elif name == 'omarchy' and args[:2] == ['plugin', 'list']:
    ids = ['tornikegomareli.spaces', 'io.github.kitsunesemcalda.feader-rss', 'kitsuneforgering.glass', 'kitsuneforgering.audio']
    print(json.dumps([{'id': x, 'enabled': True} for x in ids]))
elif name == 'omarchy' and args[:2] == ['plugin', 'validate']:
    assert (pathlib.Path(args[2]) / 'manifest.json').is_file()
elif name == 'pgrep':
    if args[-1] == 'obs':
        if os.environ.get('OBS_RUNNING'):
            print('12345')
        else:
            sys.exit(1)
    elif os.environ.get('CHROMIUM_PID'):
        print(os.environ['CHROMIUM_PID'])
    else:
        sys.exit(1)
''')
    fake_tool.chmod(0o755)
    for name in ['git', 'omarchy', 'omarchy-shell', 'hyprctl', 'systemctl', 'pgrep', 'pkexec', 'omarchy-hyprland-monitor-clamshell',
                 'omarchy-hyprland-monitor-watch', 'omarchy-system-lid-close', 'pacman']:
        (fake_bin / name).symlink_to(fake_tool)
    env = {**os.environ, 'HOME': str(target), 'PATH': f"{fake_bin}:{os.environ['PATH']}",
           'FIXTURES': str(fixtures), 'COMMAND_LOG': str(log), 'FAKE_BIN': str(fake_bin)}

    # The main install delegates to the existing MCP/hooks installer. Exercise
    # that path with a disposable Compose directory and fake Docker/agents.
    stack_script = repo / 'scripts/docker-stack.pl'
    shutil.copy2(installer.parent / 'scripts/docker-stack.pl', stack_script)
    (repo / 'docker').mkdir()
    stack_env = repo / 'docker/.env'
    stack_env.write_text('LAN_IP=192.0.2.12\nPOSTGRES_PASSWORD=keep-existing\n')
    original_env = stack_env.read_bytes()
    for name in ('docker', 'codex', 'claude'):
        (fake_bin / name).symlink_to(fake_tool)
    wrapper = target / '.local/bin/ai-memory'
    wrapper.parent.mkdir(parents=True, exist_ok=True)
    wrapper.symlink_to(fake_tool)
    stack_result = subprocess.run(
        ['perl', str(stack_script), '--memory', '--agents'],
        capture_output=True, text=True, env=env,
    )
    assert stack_result.returncode == 0, stack_result.stdout + stack_result.stderr
    stack_commands = [json.loads(line) for line in log.read_text().splitlines()]
    compose_commands = [cmd for cmd in stack_commands if cmd[:2] == ['docker', 'compose']]
    assert len(compose_commands) == 1
    assert compose_commands[0][-3:] == ['up', '-d', 'ai-memory']
    for client in ('codex', 'claude-code'):
        assert ['ai-memory', 'install-mcp', '--client', client, '--apply'] in stack_commands
        assert ['ai-memory', 'install-hooks', '--agent', client, '--apply'] in stack_commands
    assert not any(cmd[:3] == ['omarchy', 'dns', 'Custom'] for cmd in stack_commands)
    assert stack_env.read_bytes() == original_env
    log.write_text('')

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
    all_preview = run_plugin('--all', '--dry-run')
    explicit_preview = run_plugin(
        '--apps', '--bookmarks', '--fonts', '--plugin', '--omastore',
        '--theme', '--openrgb', '--ek75-knob', '--home-backup', '--clamshell', '--calibrate',
        '--maintenance', '--ai-memory', '--ai-jail', '--omatuber', '--dry-run',
    )
    normalize_pid = lambda output: re.sub(r'\.dotfiles-tmp-\d+', '.dotfiles-tmp-PID', output)
    assert normalize_pid(all_preview.stdout) == normalize_pid(explicit_preview.stdout)
    assert "'systemctl' 'reboot'" not in all_preview.stdout
    assert "'omarchy' 'pkg' 'aur' 'add' 'ai-jail-bin'" in all_preview.stdout
    assert "'omarchy' 'pkg' 'add' 'bubblewrap'" in all_preview.stdout
    assert "'--memory' '--agents'" in all_preview.stdout
    assert '/scripts/install-ai-desktops.sh' in all_preview.stdout
    assert "'webapp' 'install' 'ChatGPT'" not in all_preview.stdout
    assert "'webapp' 'install' 'Claude'" not in all_preview.stdout
    assert log.read_bytes() == before
    before_obs_check = dest.read_bytes()
    running_obs = run_plugin('--omatuber', success=False, extra_env={'OBS_RUNNING': '1'})
    assert 'Close OBS Studio' in running_obs.stderr
    assert dest.read_bytes() == before_obs_check
    before = log.read_bytes()
    preview = run_plugin('--all', '--reboot', '--dry-run')
    assert log.read_bytes() == before
    assert 'SKIP    Chromium bookmarks' in preview.stdout
    assert "'systemctl' 'reboot'" in preview.stdout
    assert preview.stdout.count("'pkexec' '/usr/bin/bash'") == 1
    assert "'--openrgb'" in preview.stdout
    assert "'--maintenance'" in preview.stdout
    assert "'/usr/local/bin/dotfiles-maintenance' 'enable'" in preview.stdout
    assert "'--ek75-knob' '--clamshell' '--home-backup'" in preview.stdout
    assert "'systemctl' '--user' 'enable' '--now' 'home-dropbox-backup.timer'" in preview.stdout
    assert "'systemctl' '--user' 'enable' '--now' 'dotfiles-clamshell-recover.timer'" in preview.stdout
    log.write_text('')
    run_plugin('--ek75-knob')
    knob_commands = [json.loads(line) for line in log.read_text().splitlines()]
    assert knob_commands == [
        ['pkexec', '/usr/bin/bash', str(system_installer), '--ek75-knob'],
    ]
    log.write_text('')
    run_plugin('--openrgb', '--ek75-knob', '--home-backup')
    combined_commands = [json.loads(line) for line in log.read_text().splitlines()]
    assert [command for command in combined_commands if command[0] == 'pkexec'] == [
        ['pkexec', '/usr/bin/bash', str(system_installer), '--openrgb',
         str(target / '.local/share/dareu-ek75-openrgb'), '--ek75-knob', '--home-backup'],
    ]
    commands = [json.loads(line) for line in log.read_text().splitlines()]
    dependency_install = next(i for i, cmd in enumerate(commands)
                              if cmd[:3] == ['omarchy', 'pkg', 'add'] and 'openrgb' in cmd)
    first_rgb_step = next(i for i, cmd in enumerate(commands)
                         if cmd[:2] == ['git', 'clone'] and cmd[-1].endswith('/dareu-ek75-openrgb'))
    assert dependency_install < first_rgb_step
    assert 'mbedtls3' in commands[dependency_install]
    assert (target / 'openrgb-steps').read_text().splitlines() == [
        'build.sh', 'install-launcher.sh', 'install-hook.sh',
    ]

    # The bookmarks step merges into an existing Chromium profile and is idempotent.
    def checksum(bookmarks):
        digest = md5()
        def add_node(node):
            digest.update(node['id'].encode())
            digest.update(node['name'].encode('utf-16-le'))
            digest.update(node['type'].encode())
            if node['type'] == 'url':
                digest.update(node['url'].encode())
            else:
                for child in node['children']:
                    add_node(child)
        for key in ('bookmark_bar', 'other', 'synced'):
            add_node(bookmarks['roots'][key])
        return digest.hexdigest()

    bookmark_file = target / '.config/chromium/Default/Bookmarks'
    bookmark_file.parent.mkdir(parents=True)
    bookmarks = {'version': 1, 'roots': {
        'bookmark_bar': {'id': '1', 'name': 'Bookmarks bar', 'type': 'folder',
                         'children': [{'id': '4', 'name': 'Existing', 'type': 'url',
                                       'url': 'https://example.org/'}]},
        'other': {'id': '2', 'name': 'Other bookmarks', 'type': 'folder', 'children': []},
        'synced': {'id': '3', 'name': 'Mobile bookmarks', 'type': 'folder', 'children': []},
    }}
    bookmarks['checksum'] = checksum(bookmarks)
    bookmark_file.write_text(json.dumps(bookmarks))
    original_bookmarks = bookmark_file.read_bytes()
    run_plugin('--bookmarks', success=False, extra_env={'CHROMIUM_PID': '123'})
    assert bookmark_file.read_bytes() == original_bookmarks
    run_plugin('--bookmarks')
    updated = json.loads(bookmark_file.read_text())
    assert [(item['name'], item['url']) for item in updated['roots']['bookmark_bar']['children']] == [
        ('Existing', 'https://example.org/'),
        ('FrankMD', 'http://127.0.0.1:7591/'),
        ('Pi-hole', 'http://127.0.0.1:8080/admin/'),
        ('ai-memory', 'http://127.0.0.1:49374/web'),
    ]
    assert updated['checksum'] == checksum(updated)
    assert next((target / '.local/state/dotfiles/bookmark-backups').glob('*/Bookmarks')).read_bytes() == original_bookmarks
    after_first_run = bookmark_file.read_bytes()
    run_plugin('--bookmarks')
    assert bookmark_file.read_bytes() == after_first_run

    log.write_text('')
    run_plugin('--plugin', '--reboot', success=False, extra_env={'FAIL_BACKEND': '1'})
    assert ['systemctl', 'reboot'] not in [json.loads(line) for line in log.read_text().splitlines()]
    log.write_text('')
    run_plugin('--reboot', success=False, extra_env={'CONFIG_ERRORS': 'invalid config'})
    assert ['systemctl', 'reboot'] not in [json.loads(line) for line in log.read_text().splitlines()]
    run('--plugin', success=False)  # A test --target cannot request desktop actions.
    run_plugin('--restore', '--reboot', success=False)
    backup_source = repo / 'home/.local/bin/home-dropbox-backup'
    backup_source.parent.mkdir(parents=True, exist_ok=True)
    backup_source.write_text('#!/bin/sh\n')
    dest.write_text('local edit outside backup\n')
    log.write_text('')
    preview = run_plugin('--home-backup', '--dry-run')
    assert 'COPY?   tool ' not in preview.stdout
    assert 'SKIP    skill installation' not in preview.stdout
    run_plugin('--home-backup')
    assert dest.read_text() == 'local edit outside backup\n'
    assert (target / '.local/bin/home-dropbox-backup').read_text() == '#!/bin/sh\n'
    backup_commands = [json.loads(line) for line in log.read_text().splitlines()]
    assert not any(command[:3] in (["omarchy", "webapp", "remove"],
                                   ["omarchy", "remove", "service"])
                   for command in backup_commands)
    installed_backup = target / '.local/bin/home-dropbox-backup'
    installed_backup.write_text('local backup edit\n')
    log.write_text('')
    run_plugin('--home-backup', success=False)
    assert installed_backup.read_text() == 'local backup edit\n'
    assert not log.read_text()
    run_plugin('--home-backup', '--backup')
    assert installed_backup.read_text() == '#!/bin/sh\n'
    assert any(path.read_text() == 'local backup edit\n'
               for path in backups.glob('*/.local/bin/home-dropbox-backup'))
    # Failed prerequisite installation must not publish any dotfiles.
    original_tool = dest.read_bytes()
    source.write_text('must not be copied before dependencies\n')
    failed = run_plugin('--ai-jail', '--backup', success=False,
                        extra_env={'FAIL_AI_PACKAGE': '1'})
    assert dest.read_bytes() == original_tool
    assert 'COPY    ' not in failed.stdout
print('OK: copies, backup/restore, isolated home backup, --all parity, plugins, Chromium bookmarks and reboot guards')
