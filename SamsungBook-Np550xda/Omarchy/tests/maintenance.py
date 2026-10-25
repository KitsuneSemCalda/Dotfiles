#!/usr/bin/env python3
"""Maintenance policy and execution tests; never invoke a real updater."""
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'scripts/maintenance/maintenance.py'
spec = importlib.util.spec_from_file_location('maintenance', SOURCE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
root_spec = importlib.util.spec_from_file_location('maintenance_root', SOURCE.with_name('root.py'))
r = importlib.util.module_from_spec(root_spec)
root_spec.loader.exec_module(r)


class Clock(dt.datetime):
    current = dt.datetime(2026, 10, 25, 3, 30)

    @classmethod
    def now(cls, tz=None):
        return cls.current if tz is None else cls.current.astimezone(tz)


class MaintenanceTests(unittest.TestCase):
    def test_window_and_week(self):
        sunday = dt.datetime(2026, 10, 25, 3)
        self.assertTrue(m.eligible(sunday, True, 900))
        for ac, idle in ((False, 900), (None, 900), (True, None), (True, 899)):
            self.assertFalse(m.eligible(sunday, ac, idle))
        self.assertFalse(m.eligible(sunday.replace(hour=6), True, 900))
        self.assertEqual(m.week(sunday), m.week(sunday + dt.timedelta(days=6)))
        self.assertNotEqual(m.week(sunday), m.week(sunday + dt.timedelta(days=7)))
        self.assertTrue(m.eligible(sunday + dt.timedelta(days=1), True, 900))

    def test_cleanup_preserves_links_recent_files_and_other_trees(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            cache = base / 'cache'; cache.mkdir()
            other = base / 'documents'; other.mkdir()
            (other / 'keep').write_text('document')
            (cache / 'old').write_text('old')
            (cache / 'recent').write_text('new')
            (cache / 'nested').mkdir()
            (cache / 'nested/old').write_text('old')
            (cache / 'link').symlink_to(other, target_is_directory=True)
            (cache / 'file-link').symlink_to(other / 'keep')
            now = time.time()
            # ctime is deliberately included by cleanup; use a future clock for old files.
            os.utime(cache / 'recent', (now + 20 * 86400, now + 20 * 86400))
            removed = m.cleanup(cache, now + 10 * 86400)
            self.assertEqual(removed, 6)
            self.assertTrue((cache / 'recent').exists())
            self.assertTrue((other / 'keep').exists())
            self.assertTrue((cache / 'file-link').is_symlink())
            indirect = base / 'indirect'; indirect.symlink_to(cache, target_is_directory=True)
            self.assertEqual(m.cleanup(indirect, now + 100 * 86400), 0)

    def test_resume_failure_missing_window_and_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / 'state/dotfiles-maintenance'
            calls = []
            fail = {'system': True}

            def perform(name):
                calls.append(name)
                return (1, 'simulated updater failure') if fail.get(name) else (0, 'simulated success')

            fake_analysis = lambda: {'time': Clock.current.isoformat(), 'warnings': [], 'checks': {}}
            with patch.dict(os.environ, {'XDG_STATE_HOME': str(root / 'state'), 'XDG_RUNTIME_DIR': str(root)}), \
                    patch.object(m.Path, 'home', return_value=root), \
                    patch.object(m.dt, 'datetime', Clock), \
                    patch.object(m, 'analyze', side_effect=fake_analysis), \
                    patch.object(m, 'conditions', return_value=(True, 1800)) as conditions, \
                    patch.object(m, 'perform', side_effect=perform), \
                    patch.object(m, 'command', return_value=(0, '')), \
                    patch.object(m.shutil, 'disk_usage', return_value=type('Disk', (), {'free': 30*m.GIB})()), \
                    patch('sys.argv', ['maintenance', 'run', '--scheduled']):
                Clock.current = dt.datetime(2026, 10, 25, 3, 30)
                self.assertEqual(m.main(), 1)
                self.assertEqual(calls[-1], 'system')
                done = json.loads((state / 'progress.json').read_text())['done']
                self.assertNotIn('system', done)
                calls.clear()
                # Lost window: not even a pending updater is started at noon.
                Clock.current = dt.datetime(2026, 10, 26, 12)
                self.assertEqual(m.main(), 0)
                self.assertEqual(calls, [])
                Clock.current = dt.datetime(2026, 10, 27, 4)
                fail['system'] = False
                self.assertEqual(m.main(), 0)
                self.assertEqual(calls[0], 'system')
                self.assertFalse(set(done) & set(calls))
                calls.clear()
                self.assertEqual(m.main(), 0)
                self.assertEqual(calls, [])
                # A fresh week allows work again, but an active user stops new phases.
                Clock.current = dt.datetime(2026, 11, 1, 4)
                conditions.side_effect = [(True, 1800), (True, 1800), (True, 0)]
                self.assertEqual(m.main(), 0)
                self.assertEqual(calls, ['prune'])

    def test_unknown_power_or_idle_fails_closed(self):
        for replies in (((1, 'unavailable'), (1, 'unavailable'), (1, 'unavailable')),
                        ((0, 'b false'), (0, 'IdleHint=no\nIdleSinceHintMonotonic=0'), (1, 'unavailable'))):
            with patch.object(m, 'command', side_effect=replies):
                ac, idle = m.conditions()
                self.assertFalse(m.eligible(dt.datetime(2026, 10, 25, 4), ac, idle))

    def test_shell_fallback_requires_a_live_idle_cycle(self):
        now = dt.datetime(2026, 10, 25, 4, tzinfo=dt.timezone.utc)
        status = {'enabled': True, 'idle': True, 'stayAwake': False, 'screensaver': 300, 'lock': 600,
                  'lastEventAt': (now - dt.timedelta(seconds=600)).isoformat()}
        self.assertEqual(m.shell_idle_seconds(status, now), 900)
        self.assertEqual(m.shell_idle_seconds({**status, 'idle': False}, now), 0)
        for field, value in (('enabled', False), ('stayAwake', True), ('lastEventAt', 'invalid')):
            self.assertIsNone(m.shell_idle_seconds({**status, field: value}, now))

    def test_simulation_does_not_create_state(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / 'absent'
            with patch.dict(os.environ, {'XDG_STATE_HOME': str(state)}), \
                    patch.object(m, 'conditions', return_value=(True, 1800)), \
                    patch('sys.argv', ['maintenance', 'simulate']), patch('builtins.print'):
                self.assertEqual(m.main(), 0)
                self.assertFalse(state.exists())

    def test_low_disk_still_cleans_but_blocks_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); calls = []
            with patch.dict(os.environ, {'XDG_STATE_HOME': str(root), 'XDG_RUNTIME_DIR': str(root)}), \
                    patch.object(m.Path, 'home', return_value=root), patch.object(m.dt, 'datetime', Clock), \
                    patch.object(m, 'analyze', return_value={'time': 'test', 'warnings': [], 'checks': {}}), \
                    patch.object(m, 'conditions', return_value=(True, 1800)), \
                    patch.object(m, 'perform', side_effect=lambda name: (calls.append(name) or 0, 'ok')), \
                    patch.object(m, 'command', return_value=(0, '')), \
                    patch.object(m.shutil, 'disk_usage', return_value=type('Disk', (), {'free': m.GIB})()), \
                    patch('sys.argv', ['maintenance', 'run']):
                Clock.current = dt.datetime(2026, 10, 25, 4)
                m.main()
                self.assertEqual(calls, ['prune', 'temporary', 'trim'])
                report = json.loads((root / 'dotfiles-maintenance/latest.json').read_text())
                self.assertEqual(report['actions']['snapshot']['status'], 'pending')

    def test_power_partial_setup_restores_only_owned_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); state = root / 'maintenance'; state.mkdir()
            profiles = root / 'profiles'; profiles.mkdir()
            (profiles / 'ac').write_text('performance\n')
            (profiles / 'battery').write_text('balanced\n')
            fail = {'ac': True}

            def apply(args, **kwargs):
                if args[-1] == 'autodetect':
                    return 0, ''
                name, profile = args[-2:]
                if fail.get(name):
                    return 1, 'simulated failure'
                (profiles / name).write_text(profile + '\n')
                return 0, ''

            with patch.dict(os.environ, {'OMARCHY_POWERPROFILES_STATE_DIR': str(profiles)}), \
                    patch.object(m, 'conditions', return_value=(True, 0)), patch.object(m, 'command', side_effect=apply):
                with self.assertRaises(RuntimeError):
                    m.power(state)
                self.assertFalse((state / 'power-applied').exists())
                original = json.loads((state / 'power.json').read_text())
                fail['ac'] = False
                m.power(state)
                self.assertEqual(json.loads((state / 'power.json').read_text()), original)
                (profiles / 'ac').write_text('power-saver\n') # a later explicit user choice
                m.power(state, restore=True)
                self.assertEqual((profiles / 'ac').read_text().strip(), 'power-saver')
                self.assertEqual((profiles / 'battery').read_text().strip(), 'balanced')
                self.assertFalse((state / 'power.json').exists())

    def test_root_boundary_rejects_extra_arguments_and_ignores_environment(self):
        with patch.object(r.os, 'geteuid', return_value=0), \
                patch('sys.argv', ['helper', 'system', '/tmp/attacker']), \
                patch.object(r.subprocess, 'run') as run:
            with self.assertRaises(SystemExit):
                r.main()
            run.assert_not_called()
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(r.os, 'geteuid', return_value=0), \
                    patch('sys.argv', ['helper', 'system']), \
                    patch.dict(os.environ, {'PATH': '/tmp/attacker', 'HOME': '/tmp/attacker', 'OMARCHY_PATH': '/tmp/attacker'}), \
                    patch.object(r, 'open', side_effect=lambda *args: open(Path(directory) / 'lock', 'w'), create=True), \
                    patch.object(r.subprocess, 'run', return_value=type('Result', (), {'returncode': 0})()) as run:
                with self.assertRaises(SystemExit) as result:
                    r.main()
                self.assertEqual(result.exception.code, 0)
                args, kwargs = run.call_args
                self.assertIn('/usr/share/omarchy/bin/omarchy-update-system-pkgs', args[0])
                self.assertEqual(kwargs['env']['HOME'], '/root')
                self.assertEqual(kwargs['env']['OMARCHY_PATH'], '/usr/share/omarchy')
                self.assertNotIn('/tmp/attacker', kwargs['env']['PATH'])


if __name__ == '__main__':
    unittest.main()
