#!/usr/bin/env python3
"""Report when Anthropic's apt repository has a newer Claude Desktop than the recipe."""
import argparse
from pathlib import Path
import re
import sys
import urllib.request

INDEX = 'https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages'
RECIPE = Path(__file__).resolve().parents[1] / 'packages/claude-desktop/PKGBUILD'


def version_key(version):
    return tuple(int(part) for part in re.findall(r'\d+', version))


def newest(index):
    entries = []
    for stanza in index.split('\n\n'):
        fields = dict(re.findall(r'^([\w-]+): (.*)$', stanza, re.M))
        if fields.get('Package') == 'claude-desktop':
            entries.append(fields)
    if not entries:
        raise SystemExit('No claude-desktop entries in the apt index')
    return max(entries, key=lambda fields: version_key(fields['Version']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', help='read a local Packages file instead of downloading it')
    args = parser.parse_args()
    if args.index:
        index = Path(args.index).read_text()
    else:
        with urllib.request.urlopen(INDEX, timeout=30) as response:
            index = response.read().decode()
    pinned = re.search(r'^pkgver=(\S+)$', RECIPE.read_text(), re.M)[1]
    latest = newest(index)
    if version_key(latest['Version']) <= version_key(pinned):
        print(f'OK: the recipe pins claude-desktop {pinned}, the newest published version')
        return
    print(f'UPDATE: claude-desktop {latest["Version"]} is published; the recipe pins {pinned}.')
    print(f'Set pkgver={latest["Version"]}, pkgrel=1 and sha256sums=(\'{latest["SHA256"]}\')')
    print(f'in {RECIPE.relative_to(RECIPE.parents[4])}, then rebuild with makepkg.')
    sys.exit(1)


if __name__ == '__main__':
    main()
