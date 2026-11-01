#!/usr/bin/env python3
"""Prepare every selected installer input before publishing files or packages.

Only caches/source checkouts and Docker's image cache are written here. Never
install packages, enable services, or publish user configuration in this phase.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
from urllib.parse import urlparse, urlencode, urljoin
from html.parser import HTMLParser

OMATUBER_REVISION = '7a51920e8a6148ddf628f7ca1f35cab6be4682da'
WRAPPER_SHA256 = '2906cdae7e405d7b64c3023cb0812311590b63223bd60b7f216cd898c89c9509'


def run(*args, cwd=None, capture=False, env=None):
    print('PREPARE ' + shlex.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fetch(url, path, max_time=1800):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Reuse completed files; callers recheck signatures/checksums on every run.
    if not path.is_file() or path.stat().st_size == 0:
        partial = path.with_name(path.name + '.partial')
        try:
            run('curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3',
                '--connect-timeout', '20', '--max-time', str(max_time), '--proto', '=https',
                '--proto-redir', '=https', url, '-o', partial)
            if not partial.stat().st_size:
                raise RuntimeError(f'Empty download: {url}')
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
    return path


class IconLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == 'link' and 'apple-touch-icon' in attributes.get('rel', ''):
            if attributes.get('href'):
                self.links.append(attributes['href'])


def prepare_icon(app, cache):
    url = app['url']
    name = hashlib.sha256(url.encode()).hexdigest() + '.png'
    path = cache / 'icons' / name
    candidates = []
    if not path.exists():
        try:
            page = run('curl', '-fsSL', '--max-time', '10', '--max-filesize', '2000000', url, capture=True)
            parser = IconLinks(); parser.feed(page)
            candidates.extend(urljoin(url, link) for link in parser.links)
        except subprocess.CalledProcessError:
            pass  # The same well-known-path and favicon fallbacks as Omarchy.
    candidates += [urljoin(url, '/apple-touch-icon.png'),
                   'https://www.google.com/s2/favicons?' + urlencode({'domain': url, 'sz': 256})]
    for candidate in candidates:
        if not candidate.startswith('https://'):
            continue
        try:
            fetch(candidate, path, max_time=30)
            media = run('file', '-b', '--mime-type', path, capture=True).strip()
            if media.startswith('image/'):
                return str(path)
        except subprocess.CalledProcessError:
            pass
        path.unlink(missing_ok=True)
    raise RuntimeError(f'Cannot download a valid icon for {app["name"]}')


def verify_checksum(path, checksum):
    if digest(path) != checksum:
        Path(path).unlink(missing_ok=True)
        raise RuntimeError(f'Checksum mismatch: {path}; discarded, rerun to download again')


def checkout(url, path, revision=None, build_tree=False):
    path = Path(path)
    if not path.exists():
        run('git', 'clone', '--depth', '1', '--', url, path)
    else:
        origin = run('git', '-C', path, 'remote', 'get-url', 'origin', capture=True).strip()
        if origin != url:
            raise RuntimeError(f'Unexpected checkout origin: {path}: {origin}')
        # Build trees acquire untracked sources/output. Preserve them; pull
        # still refuses to overwrite any untracked file that conflicts upstream.
        status_args = ['--untracked-files=no'] if build_tree else []
        if run('git', '-C', path, 'status', '--porcelain', *status_args, capture=True).strip():
            raise RuntimeError(f'Local source edits preserved: {path}')
    if revision:
        run('git', '-C', path, 'fetch', '--depth', '1', 'origin', revision)
        run('git', '-C', path, 'checkout', '--detach', revision)
    else:
        run('git', '-C', path, 'pull', '--ff-only')
    return str(path)


def satisfied(dependency):
    return subprocess.run(['pacman', '-T', dependency], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def source_info(path):
    result = {}
    for line in run('makepkg', '--dir', path, '--printsrcinfo', capture=True).splitlines():
        key, sep, value = line.strip().partition(' = ')
        if sep:
            result.setdefault(key, []).append(value)
    return result


class Packages:
    def __init__(self, cache):
        self.cache = cache
        self.official = set()
        self.aur = []
        self.visiting = set()
        self.resolved = set()

    def dependency(self, dependency):
        if satisfied(dependency) or dependency in self.resolved:
            return
        name = re.split(r'[<>=]', dependency)[0]
        if subprocess.run(['pacman', '-Si', name], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0:
            self.official.add(dependency)
            return
        if name in self.visiting:
            raise RuntimeError(f'AUR dependency cycle at {name}')
        self.visiting.add(name)
        # Query pkgbase to support split packages. Fail before install if a
        # virtual dependency cannot be resolved unambiguously.
        info_file = self.cache / 'aur-info' / (name + '.json')
        info_file.unlink(missing_ok=True)
        info = json.loads(fetch('https://aur.archlinux.org/rpc/v5/info?' +
                                urlencode({'arg[]': name}), info_file).read_text())
        if len(info.get('results', [])) != 1:
            raise RuntimeError(f'Cannot resolve AUR dependency {dependency}')
        base = info['results'][0]['PackageBase']
        directory = self.cache / 'aur' / base
        if not any(entry['base'] == base for entry in self.aur):
            checkout(f'https://aur.archlinux.org/{base}.git', directory, build_tree=True)
            self.recipe(directory, base)
        self.visiting.remove(name)
        self.resolved.add(dependency)

    def recipe(self, directory, base):
        info = source_info(directory)
        for key in ('depends', 'makedepends', 'checkdepends', 'depends_x86_64',
                    'makedepends_x86_64', 'checkdepends_x86_64'):
            for dependency in info.get(key, []):
                # A split package can depend on another output of itself.
                if re.split(r'[<>=]', dependency)[0] not in info.get('pkgname', []):
                    self.dependency(dependency)
        run('makepkg', '--dir', directory, '--verifysource', '--nodeps', '--noconfirm')
        self.aur.append({'base': base, 'dir': str(directory)})

    def download(self):
        if not self.official:
            return []
        listing = run('pacman', '-Sp', '--needed', '--print-format', '%l', '--',
                      *sorted(self.official), capture=True)
        files = []
        for url in listing.splitlines():
            if not url.startswith('https://'):
                raise RuntimeError(f'Expected HTTPS package URL, got {url}')
            file = fetch(url, self.cache / 'packages' / Path(urlparse(url).path).name)
            signature = fetch(url + '.sig', str(file) + '.sig')
            try:
                run('pacman-key', '--verify', signature, file)
            except subprocess.CalledProcessError:
                file.unlink(missing_ok=True)
                signature.unlink(missing_ok=True)
                raise
            files.append(str(file))
        return files


def build_environment(packages, cache, commands):
    """Run downloaded tool packages from a cache, without installing them."""
    env = dict(os.environ)
    missing = [command for command in commands if not shutil.which(command)]
    if not missing:
        return env
    root = cache / 'tools'
    root.mkdir(parents=True, exist_ok=True)
    # Include runtime libraries of the tools, also downloaded by pacman -Sp.
    for package in packages:
        run('bsdtar', '-xf', package, '-C', root, 'usr')
    env['PATH'] = str(root / 'usr/bin') + ':' + env['PATH']
    env['LD_LIBRARY_PATH'] = str(root / 'usr/lib')
    if 'go' in missing:
        env['GOROOT'] = str(root / 'usr/lib/go')
    for command in missing:
        if not (root / 'usr/bin' / command).exists():
            raise RuntimeError(f'{command} is required to prepare build dependencies')
    return env


def build_cache_environment(cache):
    return {'CARGO_HOME': str(cache / 'cargo'),
            'GOPATH': str(cache / 'go'), 'GOMODCACHE': str(cache / 'go/pkg/mod'),
            'GOCACHE': str(cache / 'go/build')}


def prepare(plan, cache, repo):
    cache.mkdir(parents=True, exist_ok=True)
    state = {'sources': {}, 'assets': {}, 'packages': [], 'aur': []}
    selected = set(plan['options'])
    packages = Packages(cache)
    docker_ready = ('ai-memory' in selected and shutil.which('docker') and
                    subprocess.run(['docker', 'info'], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL).returncode == 0)
    if 'ai-memory' in selected and not docker_ready and not satisfied('skopeo'):
        packages.official.add('skopeo')
    for package in plan['repo_packages']:
        if not satisfied(package):
            packages.official.add(package)
    for package in plan['aur_packages']:
        packages.dependency(package)
    if 'apps' in selected and not satisfied('claude-desktop'):
        directory = cache / 'aur/claude-desktop'
        directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(repo / 'packages/claude-desktop/PKGBUILD', directory / 'PKGBUILD')
        packages.recipe(directory, 'claude-desktop')
    state['packages'] = packages.download()
    state['aur'] = packages.aur

    def source(name, url, revision=None):
        path = checkout(url, cache / 'sources' / name, revision)
        state['sources'][name] = path
        return Path(path)

    commands = (['go'] if 'plugin' in selected else []) + (['cargo'] if 'omatuber' in selected else [])
    if 'ai-memory' in selected and not docker_ready:
        commands.append('skopeo')
    env = build_environment(state['packages'], cache, commands)
    env.update(build_cache_environment(cache))
    if 'plugin' in selected:
        feader = source('Feader-RSS', 'https://github.com/KitsuneForgering/Feader-RSS.git')
        source('Spaces', 'https://github.com/tornikegomareli/omarchy-spaces.git')
        source('omarchy-glass', 'https://github.com/KitsuneForgering/omarchy-glass.git')
        run('go', 'mod', 'download', 'all', cwd=feader, env=env)
    if 'openrgb' in selected:
        rgb = source('dareu-ek75-openrgb', 'https://github.com/KitsuneSemCalda/Dareu-EK75-OpenRGB-Compat.git')
        script = (rgb / 'tools/build.sh').read_text()
        match = re.search(r'^OPENRGB_PINNED_COMMIT=([0-9a-f]{40})$', script, re.M)
        if not match:
            raise RuntimeError('OpenRGB installer no longer declares a pinned source revision')
        checkout('https://gitlab.com/CalcProgrammer1/OpenRGB.git', rgb / 'build/OpenRGB', match[1], build_tree=True)
    if 'omatuber' in selected:
        src = source('OmaTuber', 'https://github.com/KitsuneForgering/OmaTuber.git', OMATUBER_REVISION)
        run('cargo', 'fetch', '--locked', '--manifest-path', src / 'Cargo.toml', env=env)
    if 'theme' in selected:
        source('Sword-Art-Omarchy', 'https://github.com/KitsuneSemCalda/Sword-Art-Omarchy')
    if 'omastore' in selected:
        source('OmaStore', 'https://github.com/KitsuneForgering/OmaStore.git')
        latest = run('curl', '-fsSLI', '--connect-timeout', '20', '--max-time', '60',
                     '-o', '/dev/null', '-w', '%{url_effective}',
                     'https://github.com/KitsuneForgering/OmaStore/releases/latest', capture=True)
        tag = latest.rstrip('/').rsplit('/', 1)[-1]
        if not re.fullmatch(r'v\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?', tag):
            raise RuntimeError('Cannot resolve OmaStore release')
        name = f'omastore-{tag[1:]}-x86_64-linux.tar.gz'
        url = f'https://github.com/KitsuneForgering/OmaStore/releases/download/{tag}/{name}'
        archive = fetch(url, cache / 'assets' / name)
        sums = fetch(url + '.sha256', str(archive) + '.sha256')
        match = re.search(r'^([0-9a-fA-F]{64})\s+\*?' + re.escape(name) + r'$', sums.read_text(), re.M)
        if not match:
            raise RuntimeError('Invalid OmaStore checksum manifest')
        verify_checksum(archive, match[1].lower())
        state['assets']['omastore'] = str(archive)
    if 'fonts' in selected:
        # Download TTFs in preparation, publish them only after the barrier.
        css = run('curl', '-fsSL', '--connect-timeout', '20', '--max-time', '60', '-A', 'Mozilla/5.0',
                  'https://fonts.googleapis.com/css2?family=Lexend:wght@400;700', capture=True)
        urls = dict(re.findall(r'font-weight:\s*(\d+);\s*src:\s*url\(([^)]+)\)', css))
        for weight, name in [('400', 'Lexend-Regular.ttf'), ('700', 'Lexend-Bold.ttf')]:
            if weight not in urls:
                raise RuntimeError(f'Missing Lexend weight {weight}')
            font = fetch(urls[weight], cache / 'assets' / name)
            if font.read_bytes()[:4] not in (b'\x00\x01\x00\x00', b'OTTO'):
                font.unlink()
                raise RuntimeError(f'Invalid font download: {name}')
            state['assets'][name] = str(font)
    if 'apps' in selected:
        for app in plan['webapps']:
            state['assets']['icon:' + app['name']] = prepare_icon(app, cache)
    if 'ai-memory' in selected:
        wrapper = fetch('https://github.com/akitaonrails/ai-memory/releases/download/v2.3.0/ai-memory-wrapper',
                        cache / 'assets/ai-memory-wrapper')
        verify_checksum(wrapper, WRAPPER_SHA256)
        state['assets']['ai-memory-wrapper'] = str(wrapper)
        # Stage the native client under the unified cache. Its help command
        # downloads/verifies it without installing packages or agent hooks.
        content = wrapper.read_text().replace('/releases/latest/download/', '/releases/download/v2.3.0/')
        content = content.replace('ai-memory:latest', 'ai-memory:2.3.0')
        staged = cache / 'assets/ai-memory-prepared'
        staged.write_text(content); staged.chmod(0o755)
        native_env = {**os.environ, 'AI_MEMORY_NO_VERSION_CHECK': '1',
                      'XDG_CACHE_HOME': str(cache / 'native')}
        native_env.pop('AI_MEMORY_NATIVE_BIN', None)
        run(staged, 'run', '--help', env=native_env)
        state['native_runner'] = str(cache / 'native/ai-memory/native-runner')
        # Starting/enabling Docker belongs to installation. Skopeo can download
        # the image first when Docker has not yet been installed or started.
        image = 'docker.io/akitaonrails/ai-memory:2.3.0'
        if docker_ready:
            run('docker', 'pull', image)
        else:
            archive = cache / 'assets/ai-memory-image.tar'
            partial = archive.with_suffix('.partial')
            partial.unlink(missing_ok=True)
            run('skopeo', '--insecure-policy', 'copy', 'docker://' + image,
                'docker-archive:' + str(partial) + ':' + image, env=env)
            partial.replace(archive)
            state['assets']['ai-memory-image'] = str(archive)
    # Verify selected inputs, rather than reading unrelated old downloads or
    # compiler caches on every installation. Cargo/Go verify their own lockfiles.
    inputs = {Path(p) for p in state['assets'].values()} | {Path(p) for p in state['packages']}
    for directory in [*state['sources'].values(), *(a['dir'] for a in state['aur'])]:
        root = Path(directory)
        if (root / '.git').is_dir():
            tracked = run('git', '-C', root, 'ls-files', '-z', capture=True).split('\0')
            inputs.update(root / name for name in tracked if name and (root / name).is_file())
        else:
            inputs.add(root / 'PKGBUILD')
    if state.get('native_runner'):
        inputs.update(p for p in Path(state['native_runner']).iterdir() if p.is_file())
    state['hashes'] = {str(p): digest(p) for p in sorted(inputs)}
    return state


def verify(state):
    for path, expected in state['hashes'].items():
        if not Path(path).is_file() or digest(path) != expected:
            raise RuntimeError(f'Prepared input changed or disappeared: {path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    args = parser.parse_args()
    ready = args.cache / 'ready.json'
    ready.unlink(missing_ok=True)
    state = prepare(json.loads(args.plan.read_text()), args.cache, Path(__file__).resolve().parents[1])
    verify(state)
    temporary = ready.with_suffix('.tmp')
    temporary.write_text(json.dumps(state, indent=2) + '\n')
    temporary.replace(ready)
    print('Downloads verified. Installation may now begin.', flush=True)


if __name__ == '__main__':
    main()
