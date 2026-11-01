#!/usr/bin/env python3
"""Desktop migration must preserve web launchers if package setup fails."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

script = Path(__file__).resolve().parents[1] / 'scripts/install-ai-desktops.sh'
recipe = (script.parents[1] / 'packages/claude-desktop/PKGBUILD').read_text()
wanted = '-'.join(re.search(rf'^{key}=(\S+)$', recipe, re.M)[1] for key in ('pkgver', 'pkgrel'))
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    home, binaries = root / 'home', root / 'bin'
    launchers = home / '.local/share/applications'
    launchers.mkdir(parents=True)
    binaries.mkdir()
    state, log = root / 'packages.json', root / 'commands.jsonl'
    tool = binaries / 'tool'
    tool.write_text('''#!/usr/bin/env python3
import json, os, pathlib, re, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
state = pathlib.Path(os.environ['PACKAGE_STATE'])
installed = json.loads(state.read_text())
with open(os.environ['COMMAND_LOG'], 'a') as f:
    f.write(json.dumps([name, *args]) + '\\n')
if name == 'pacman' and args[0] == '-Q':
    if args[1] not in installed: sys.exit(1)
    print(args[1], installed[args[1]])
elif name == 'vercmp':
    a, b = (tuple(map(int, re.findall(r'\\d+', v))) for v in args)
    print((a > b) - (a < b))
elif name == 'omarchy' and args[:3] == ['pkg', 'aur', 'add']:
    if os.environ.get('FAIL_INSTALL'): sys.exit(1)
    installed['chatgpt-desktop'] = '1.0-1'
    state.write_text(json.dumps(installed))
elif name == 'pkexec':
    if os.environ.get('FAIL_CLAUDE'): sys.exit(1)
    installed['claude-desktop'] = os.environ['CLAUDE_RECIPE']
    state.write_text(json.dumps(installed))
elif name == 'makepkg':
    package = pathlib.Path(args[args.index('--dir') + 1]) / 'claude-desktop.pkg.tar.zst'
    if '--packagelist' in args: print(package)
    else: package.touch()
elif name == 'uname': print('x86_64')
elif name == 'omarchy' and args[:2] == ['webapp', 'remove']:
    (pathlib.Path(os.environ['HOME']) / '.local/share/applications' / (args[2] + '.desktop')).unlink()
''')
    tool.chmod(0o755)
    for name in ('pacman', 'vercmp', 'omarchy', 'pkexec', 'makepkg', 'chatgpt', 'claude-desktop', 'uname'):
        (binaries / name).symlink_to(tool)
    env = {**os.environ, 'HOME': str(home), 'XDG_CACHE_HOME': str(root / 'cache'),
           'PATH': f'{binaries}:/usr/bin:/bin', 'PACKAGE_STATE': str(state), 'COMMAND_LOG': str(log),
           'CLAUDE_RECIPE': wanted}

    def reset():
        state.write_text('{}')
        log.write_text('')
        for name in ('ChatGPT', 'Claude'):
            (launchers / f'{name}.desktop').write_text('Exec=omarchy-launch-webapp https://example.com\n')

    for failure in ('FAIL_INSTALL', 'FAIL_CLAUDE'):
        reset()
        result = subprocess.run(['bash', str(script)], env={**env, failure: '1'}, capture_output=True)
        assert result.returncode != 0
        assert all((launchers / f'{name}.desktop').exists() for name in ('ChatGPT', 'Claude'))

    reset()
    subprocess.run(['bash', str(script)], env=env, check=True)
    assert not list(launchers.glob('*.desktop'))
    assert set(json.loads(state.read_text())) == {'chatgpt-desktop', 'claude-desktop'}
    log.write_text('')
    subprocess.run(['bash', str(script)], env=env, check=True)
    commands = [json.loads(line) for line in log.read_text().splitlines()]
    assert not any(c[0] in ('omarchy', 'makepkg', 'pkexec') for c in commands)

    # An older Claude build must be replaced by the current recipe.
    state.write_text(json.dumps({'chatgpt-desktop': '1.0-1', 'claude-desktop': '0.1-1'}))
    log.write_text('')
    subprocess.run(['bash', str(script)], env=env, check=True)
    commands = [json.loads(line) for line in log.read_text().splitlines()]
    assert any(c[0] == 'pkexec' for c in commands)
    assert json.loads(state.read_text())['claude-desktop'] == wanted
print('OK: desktop migration preserves webapps on failure, skips current packages and upgrades old ones')
