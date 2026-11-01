#!/usr/bin/env python3
"""check-keyring must fail on a locked keyring or a launcher without the flag."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

omarchy = Path(__file__).resolve().parents[1]
script = omarchy / 'home/.local/bin/check-keyring'
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    binaries, config = root / 'bin', root / 'config'
    binaries.mkdir()
    config.mkdir()
    busctl = binaries / 'busctl'
    busctl.write_text('#!/bin/sh\necho "$BUS_REPLY"\n')
    for name in ('chatgpt', 'electron43'):
        (binaries / name).write_text('#!/bin/sh\n')
    for name in ('chatgpt-flags.conf', 'electron-flags.conf'):
        (config / name).write_text((omarchy / 'home/.config' / name).read_text())
    launcher = binaries / 'claude-desktop'
    launcher.write_text('#!/bin/sh\nset -- --password-store=gnome-libsecret "$@"\n')
    for path in binaries.iterdir():
        path.chmod(0o755)
    env = {**os.environ, 'PATH': str(binaries), 'XDG_CONFIG_HOME': str(config)}

    def check(reply='b false'):
        result = subprocess.run([sys.executable, str(script)], env={**env, 'BUS_REPLY': reply},
                                capture_output=True, text=True)
        return result.returncode, result.stdout

    code, out = check()
    assert code == 0 and out.count('PASS') == 4, out
    code, out = check('b true')
    assert code == 1 and 'FAIL: Secret Service' in out, out

    # The official .deb ships a bare symlink, which leaves Electron on plaintext.
    launcher.unlink()
    launcher.symlink_to(binaries / 'chatgpt')
    code, out = check()
    assert code == 1 and 'FAIL: Claude Desktop' in out, out

    launcher.unlink()
    (config / 'chatgpt-flags.conf').write_text('--ozone-platform=wayland\n')
    code, out = check()
    assert code == 1 and 'SKIP: Claude Desktop' in out and 'FAIL: ChatGPT' in out, out
print('OK: check-keyring reports locked keyrings, bare launchers and missing flags')
