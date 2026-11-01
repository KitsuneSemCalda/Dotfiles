#!/usr/bin/env python3
"""Verify download failures, cache integrity and offline build preparation."""
import contextlib
import io
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('downloads', ROOT / 'scripts/prepare-downloads.py')
downloads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(downloads)


class Downloads(unittest.TestCase):
    def test_failed_download_never_publishes_partial_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            asset = Path(tmp) / 'release.tar.gz'
            def failed(*args):
                Path(args[-1]).write_bytes(b'incomplete')
                raise subprocess.CalledProcessError(22, args)
            with patch.object(downloads, 'run', side_effect=failed), self.assertRaises(subprocess.CalledProcessError):
                downloads.fetch('https://example.org/release.tar.gz', asset)
            self.assertFalse(asset.exists())
            self.assertFalse(asset.with_name(asset.name + '.partial').exists())

    def test_checksum_failure_discards_bad_cache_and_retry_can_succeed(self):
        with tempfile.TemporaryDirectory() as tmp:
            asset = Path(tmp) / 'asset'
            asset.write_bytes(b'incomplete')
            expected = downloads.hashlib.sha256(b'complete').hexdigest()
            with self.assertRaisesRegex(RuntimeError, 'Checksum mismatch'):
                downloads.verify_checksum(asset, expected)
            self.assertFalse(asset.exists())
            def fetch(*args): Path(args[-1]).write_bytes(b'complete')
            with patch.object(downloads, 'run', side_effect=fetch):
                downloads.fetch('https://example.org/asset', asset)
            downloads.verify_checksum(asset, expected)

    def test_failed_preparation_invalidates_old_success_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); plan = root / 'plan.json'; plan.write_text('{}')
            ready = root / 'ready.json'; ready.write_text('{"old": true}')
            with patch('sys.argv', ['prepare', '--plan', str(plan), '--cache', str(root)]), \
                    patch.object(downloads, 'prepare', side_effect=RuntimeError('source unavailable')), \
                    self.assertRaisesRegex(RuntimeError, 'source unavailable'):
                downloads.main()
            self.assertFalse(ready.exists())

    def test_official_dependencies_and_signatures_are_downloaded_without_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); packages = downloads.Packages(root)
            packages.official.add('application')
            urls = ['https://mirror.example/library-1-x86_64.pkg.tar.zst',
                    'https://mirror.example/application-1-x86_64.pkg.tar.zst']
            def run(*args, **kwargs):
                return '\n'.join(urls) if args[0] == 'pacman' else ''
            def fetch(url, path):
                path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'verified'); return path
            with patch.object(downloads, 'run', side_effect=run) as commands, \
                    patch.object(downloads, 'fetch', side_effect=fetch) as transfers:
                files = packages.download()
            self.assertEqual(len(files), 2)
            self.assertEqual(transfers.call_count, 4)
            self.assertEqual([c.args[0] for c in commands.call_args_list],
                             ['pacman', 'pacman-key', 'pacman-key'])
            self.assertIn('-Sp', commands.call_args_list[0].args)
            self.assertNotIn('-S', commands.call_args_list[0].args)

    def test_bad_package_signature_discards_cached_pair_for_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); packages = downloads.Packages(root); packages.official.add('application')
            url = 'https://mirror.example/application.pkg.tar.zst'
            def command(*args, **kwargs):
                if args[0] == 'pacman': return url
                raise subprocess.CalledProcessError(1, args)
            def fetch(url, path):
                path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'corrupted'); return path
            with patch.object(downloads, 'run', side_effect=command), \
                    patch.object(downloads, 'fetch', side_effect=fetch), \
                    self.assertRaises(subprocess.CalledProcessError):
                packages.download()
            self.assertEqual(list((root / 'packages').iterdir()), [])

    def test_aur_preparation_fetches_sources_and_resolves_dependencies_without_syncdeps(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); packages = downloads.Packages(root)
            info = {'pkgname': ['example'], 'depends': ['runtime>=2'],
                    'makedepends': ['compiler'], 'checkdepends_x86_64': ['test-tool']}
            with patch.object(downloads, 'source_info', return_value=info), \
                    patch.object(packages, 'dependency') as dependency, \
                    patch.object(downloads, 'run') as command:
                packages.recipe(root, 'example')
            self.assertEqual([c.args[0] for c in dependency.call_args_list],
                             ['runtime>=2', 'compiler', 'test-tool'])
            command.assert_called_once_with('makepkg', '--dir', root, '--verifysource', '--nodeps', '--noconfirm')
            self.assertNotIn('--syncdeps', command.call_args.args)

    def test_modified_input_is_rejected_before_installation(self):
        with tempfile.TemporaryDirectory() as tmp:
            asset = Path(tmp) / 'asset'; asset.write_bytes(b'release')
            state = {'hashes': {str(asset): downloads.digest(asset)}}
            downloads.verify(state)
            asset.write_bytes(b'changed')
            with self.assertRaisesRegex(RuntimeError, 'changed or disappeared'):
                downloads.verify(state)

    def test_installed_packages_do_not_trigger_network_or_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = {'options': [], 'repo_packages': ['python'], 'aur_packages': ['app'], 'webapps': []}
            with patch.object(downloads, 'satisfied', return_value=True), \
                    patch.object(downloads, 'fetch') as fetch, \
                    patch.object(downloads, 'run') as command:
                state = downloads.prepare(plan, Path(tmp), ROOT)
            self.assertEqual(state['packages'], [])
            self.assertEqual(state['aur'], [])
            fetch.assert_not_called(); command.assert_not_called()

    def test_go_and_cargo_caches_share_the_download_root(self):
        cache = Path('/temporary/downloads')
        env = downloads.build_cache_environment(cache)
        for path in env.values():
            self.assertTrue(Path(path).is_relative_to(cache))

    def test_dirty_source_is_preserved_instead_of_updated(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch.object(downloads, 'run', side_effect=['https://example.org/repo.git', ' M file']) as command, \
                    self.assertRaisesRegex(RuntimeError, 'Local source edits preserved'):
                downloads.checkout('https://example.org/repo.git', root)
            self.assertFalse(any('pull' in c.args for c in command.call_args_list))

    def test_repeated_build_checkout_keeps_generated_files_and_rejects_source_edits(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            root = Path(tmp); origin = root / 'origin'; origin.mkdir()
            def git(*args, cwd=origin):
                return subprocess.run(['git', *args], cwd=cwd, check=True,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            git('init', '-b', 'main')
            git('config', 'user.name', 'Installer test')
            git('config', 'user.email', 'test@example.invalid')
            (origin / 'PKGBUILD').write_text('original recipe')
            git('add', 'PKGBUILD'); git('commit', '-m', 'fixture')
            source = root / 'checkout'
            downloads.checkout(str(origin), source)
            (source / 'archive.tar').write_bytes(b'cached source')
            downloads.checkout(str(origin), source, build_tree=True)
            self.assertEqual((source / 'archive.tar').read_bytes(), b'cached source')
            (source / 'PKGBUILD').write_text('local edit')
            with self.assertRaisesRegex(RuntimeError, 'Local source edits preserved'):
                downloads.checkout(str(origin), source, build_tree=True)
            self.assertEqual((source / 'PKGBUILD').read_text(), 'local edit')

    def test_image_is_staged_without_starting_docker_during_preparation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); wrapper_content = b'#!/bin/sh\n# fixture wrapper\n'
            def fetch(url, path):
                path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(wrapper_content); return path
            def run(*args, **kwargs):
                if args[0] == 'skopeo':
                    archive = Path(str(args[-1]).split(':')[1]); archive.write_bytes(b'container image')
                elif len(args) > 2 and args[1:3] == ('run', '--help'):
                    runner = root / 'native/ai-memory/native-runner'; runner.mkdir(parents=True)
                    for name in ('ai-memory', 'ai-memory-linux-x86_64.tar.gz', 'last-check'):
                        (runner / name).write_text('prepared')
                return ''
            plan = {'options': ['ai-memory'], 'repo_packages': [], 'aur_packages': [], 'webapps': []}
            with patch.object(downloads.shutil, 'which', return_value='/usr/bin/tool'), \
                    patch.object(downloads.subprocess, 'run', return_value=Mock(returncode=1)), \
                    patch.object(downloads, 'satisfied', return_value=True), \
                    patch.object(downloads, 'fetch', side_effect=fetch), \
                    patch.object(downloads, 'run', side_effect=run) as command, \
                    patch.object(downloads, 'WRAPPER_SHA256', downloads.hashlib.sha256(wrapper_content).hexdigest()):
                state = downloads.prepare(plan, root, ROOT)
            self.assertTrue(Path(state['assets']['ai-memory-image']).is_file())
            self.assertTrue(Path(state['native_runner']).is_dir())
            downloads.verify(state)
            self.assertFalse(any(c.args[0] in ('docker', 'systemctl', 'pkexec', 'pacman')
                                 for c in command.call_args_list))

    def test_standalone_and_prepared_desktop_migration_keep_webapps_on_missing_packages(self):
        # A prepared install must never fall back to a network package installer.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); bin_dir = root / 'bin'; bin_dir.mkdir()
            tool = bin_dir / 'pacman'; tool.write_text('#!/bin/sh\nexit 1\n'); tool.chmod(0o755)
            log = root / 'unexpected-install'
            omarchy = bin_dir / 'omarchy'; omarchy.write_text(f'#!/bin/sh\ntouch "{log}"\n'); omarchy.chmod(0o755)
            import os
            result = subprocess.run(['bash', str(ROOT / 'scripts/install-ai-desktops.sh')],
                                    env={**os.environ, 'PATH': f'{bin_dir}:/usr/bin:/bin',
                                         'DOTFILES_DOWNLOAD_MANIFEST': str(root / 'ready.json')},
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(log.exists())


if __name__ == '__main__':
    unittest.main()
