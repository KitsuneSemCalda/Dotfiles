#!/usr/bin/env python3
"""The version check must compare numerically and print the values to pin."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

omarchy = Path(__file__).resolve().parents[1]
script = omarchy / 'scripts/check-claude-desktop-version.py'
pinned = re.search(r'^pkgver=(\S+)$', (omarchy / 'packages/claude-desktop/PKGBUILD').read_text(), re.M)[1]
major, minor, patch = (int(part) for part in pinned.split('.'))


def stanza(version, digest='0' * 64, package='claude-desktop'):
    return f'Package: {package}\nVersion: {version}\nSHA256: {digest}\n'


def check(*stanzas):
    with tempfile.NamedTemporaryFile('w', suffix='Packages') as index:
        index.write('\n'.join(stanzas))
        index.flush()
        result = subprocess.run([sys.executable, str(script), '--index', index.name],
                                capture_output=True, text=True)
    return result.returncode, result.stdout


code, out = check(stanza(pinned), stanza(f'{major}.{minor - 1}.{patch}'))
assert code == 0 and out.startswith('OK'), out

# 3.10000.0 sorts after 3.9999.0 numerically but not as text.
newer = f'{major}.{minor * 10}.{patch}'
code, out = check(stanza(f'{major}.{minor + 1}.{patch}'), stanza(newer, 'a' * 64),
                  stanza('99.0.0', package='claude-desktop-dbg'))
assert code == 1 and f'pkgver={newer}' in out and 'a' * 64 in out, out
print('OK: Claude Desktop version check compares numerically and ignores other packages')
