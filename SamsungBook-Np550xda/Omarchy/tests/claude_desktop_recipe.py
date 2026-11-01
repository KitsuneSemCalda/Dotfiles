#!/usr/bin/env python3
"""The Claude recipe must install a launcher that selects GNOME Keyring."""
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

recipe = Path(__file__).resolve().parents[1] / 'packages/claude-desktop/PKGBUILD'
subprocess.run(['bash', '-n', str(recipe)], check=True)


def ar_member(name, data):
    header = f'{name:<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode()
    return header + data + (b'\n' if len(data) % 2 else b'')


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    srcdir, pkgdir = root / 'src', root / 'pkg'
    srcdir.mkdir()
    pkgdir.mkdir()

    # A minimal .deb whose /usr/bin entry is a symlink, as in the official one.
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:xz') as archive:
        link = tarfile.TarInfo('./usr/bin/claude-desktop')
        link.type, link.linkname = tarfile.SYMTYPE, '../lib/claude-desktop/claude-desktop'
        archive.addfile(link)
    (srcdir / 'claude-desktop_amd64.deb').write_bytes(
        b'!<arch>\n' + ar_member('debian-binary', b'2.0\n') + ar_member('data.tar.xz', data.getvalue()))

    subprocess.run(['bash', '-euc', 'source "$1"; package', 'recipe', str(recipe)], check=True,
                   env={**os.environ, 'srcdir': str(srcdir), 'pkgdir': str(pkgdir)})
    launcher = pkgdir / 'usr/bin/claude-desktop'
    assert launcher.is_file() and not launcher.is_symlink()
    assert os.access(launcher, os.X_OK)

    # Point the launcher at a stub that prints the arguments it receives.
    stub = root / 'claude-desktop'
    stub.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
    stub.chmod(0o755)
    test_launcher = root / 'launcher'
    test_launcher.write_text(launcher.read_text().replace('/usr/lib/claude-desktop/claude-desktop', str(stub)))

    def run(*args):
        result = subprocess.run(['sh', str(test_launcher), *args], check=True, capture_output=True, text=True)
        return result.stdout.splitlines()

    assert run() == ['--password-store=gnome-libsecret']
    url = 'claude://code/new?a=1&b=2'
    assert run(url) == ['--password-store=gnome-libsecret', url]
    assert run('--password-store=basic', url) == ['--password-store=basic', url]
print('OK: Claude recipe replaces the launcher symlink and selects GNOME Keyring')
