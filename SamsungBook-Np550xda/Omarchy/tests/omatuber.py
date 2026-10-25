#!/usr/bin/env python3
"""Check pinned installation and OBS integration without a GUI or a real build."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
configure = runpy.run_path(str(ROOT / 'scripts/configure-omatuber.py'))['configure']
generator = runpy.run_path(str(ROOT.parent / 'tools/generate-obs-dotfiles.py'))
REVISION = '7a51920e8a6148ddf628f7ca1f35cab6be4682da'


class IntegrationTests(unittest.TestCase):
    def test_scene_reuses_microphone_and_leaves_existing_scenes_intact(self):
        collection = generator['collection']('linux')
        sources = {source['name']: source for source in collection['sources']}
        self.assertEqual(len(sources), len(collection['sources']))
        avatar = sources['OmaTuber']
        self.assertEqual(avatar['id'], 'browser_source')
        self.assertEqual(avatar['settings']['url'], 'http://127.0.0.1:39017/')
        self.assertFalse(avatar['settings']['shutdown'])
        live = sources['OmaTuber Live']['settings']['items']
        self.assertEqual([item['name'] for item in live], ['Capture Monitor', 'OmaTuber', 'Audio Buses'])
        self.assertEqual(sources['Microphone']['settings']['device_id'], 'capture_microphone')
        self.assertEqual(collection['current_scene'], 'Desktop')
        for name in generator['SCENES']:
            self.assertIn(name, sources)
        windows = generator['collection']('windows')
        self.assertNotIn('OmaTuber', [source['name'] for source in windows['sources']])

    def test_config_has_private_password_matching_audio_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            configure(config)
            path = config / 'obs-studio/plugin_config/obs-websocket/config.json'
            first = json.loads(path.read_text())
            self.assertTrue(first['server_enabled'] and first['auth_required'])
            self.assertGreaterEqual(len(first['server_password']), 32)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            prefs = json.loads((config / 'omatuber/prefs.json').read_text())
            self.assertNotIn('server_password', prefs)
            self.assertEqual(prefs['audio_input'], generator['uid']('Microphone'))
            self.assertEqual(prefs['scene'], 'OmaTuber Live')
            configure(config)
            self.assertEqual(first, json.loads(path.read_text()))

    def test_existing_secrets_avatar_and_selection_survive(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            path = config / 'obs-studio/plugin_config/obs-websocket/config.json'
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps({'server_port': 4460, 'server_password': 'keep-secret', 'alerts_enabled': False}))
            prefs = config / 'omatuber/prefs.json'
            prefs.parent.mkdir()
            selected = str(uuid.uuid4())
            prefs.write_text(json.dumps({'audio_input': selected, 'closed_png': '/avatar.png', 'scene': 'Custom', 'obs_port': 4455}))
            configure(config)
            updated = json.loads(prefs.read_text())
            self.assertEqual(updated['audio_input'], selected)
            self.assertEqual(updated['closed_png'], '/avatar.png')
            self.assertEqual(updated['scene'], 'Custom')
            self.assertEqual(updated['obs_port'], 4460)
            self.assertEqual(json.loads(path.read_text())['server_password'], 'keep-secret')

    def test_invalid_preferences_do_not_modify_obs(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            prefs = config / 'omatuber/prefs.json'
            prefs.parent.mkdir(parents=True)
            prefs.write_text('invalid JSON')
            with self.assertRaises(ValueError):
                configure(config)
            self.assertFalse((config / 'obs-studio').exists())

    def test_pinned_install_and_dirty_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            fake = home / 'fake'
            fake.mkdir()
            log = home / 'commands.jsonl'
            tool = fake / 'tool'
            tool.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['COMMAND_LOG'], 'a') as log: log.write(json.dumps([name, *args]) + '\\n')
if name == 'git':
    if args[0] == 'clone':
        dest = pathlib.Path(args[-1]); (dest / '.git').mkdir(parents=True)
        (dest / 'packaging').mkdir()
        for file in ('omatuber.desktop','omatuber.svg'): (dest / 'packaging' / file).write_text('fixture')
    else:
        args = args[2:]
        if args[:2] == ['remote','get-url']: print('https://github.com/KitsuneForgering/OmaTuber.git')
        elif args[0] == 'status' and os.environ.get('DIRTY'): print(' M src/main.rs')
        elif args[0] == 'rev-parse': print('7a51920e8a6148ddf628f7ca1f35cab6be4682da')
elif name == 'cargo':
    root = pathlib.Path(args[args.index('--root') + 1]); (root / 'bin').mkdir(parents=True)
    binary = root / 'bin/omatuber'; binary.write_text('#!/bin/sh\\n'); binary.chmod(0o755)
''')
            tool.chmod(0o755)
            for name in ('git', 'cargo'):
                (fake / name).symlink_to(tool)
            env = {**os.environ, 'HOME': str(home), 'PATH': str(fake) + ':' + os.environ['PATH'],
                   'XDG_CACHE_HOME': str(home / '.cache'), 'XDG_STATE_HOME': str(home / '.local/state'),
                   'XDG_DATA_HOME': str(home / '.local/share'), 'COMMAND_LOG': str(log)}
            command = ['bash', str(ROOT / 'scripts/install-omatuber.sh')]
            subprocess.run(command, env=env, check=True)
            subprocess.run(command, env=env, check=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            builds = [call for call in calls if call[0] == 'cargo']
            self.assertEqual(len(builds), 1)
            self.assertIn('--locked', builds[0])
            self.assertIn(REVISION, [arg for call in calls for arg in call])
            self.assertTrue((home / '.local/share/applications/omatuber.desktop').exists())
            failed = subprocess.run(command, env={**env, 'DIRTY': '1'}, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn(b'local edits', failed.stderr)


if __name__ == '__main__':
    unittest.main()
