#!/usr/bin/env python3
"""Check hardware settings persistence and rollback without a compositor."""
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

namespace = runpy.run_path(str(Path(__file__).resolve().parents[1] /
                               'home/.local/bin/calibrate-devices'))
apply = namespace['apply_settings']
globals_ = apply.__globals__


class HardwareSettings(unittest.TestCase):
    def test_confirmation_and_rollback(self):
        settings = {'monitors': {'eDP-1': {'mode': 'preferred', 'scale': 1}},
                    'pointers': {'mouse"name': {'sensitivity': 0.2, 'natural_scroll': True}}}
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch.dict(globals_, ROOT=root), patch.dict(globals_, run=lambda *args: None), \
                 patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, '', '')), \
                 patch('select.select', return_value=([0], [], [])), patch('builtins.input', return_value='s'):
                apply(settings)
            original = (root / 'devices.lua').read_bytes()
            self.assertEqual(json.loads((root / 'settings.json').read_text()), settings)
            self.assertIn('mouse\\"name', original.decode())
            settings['monitors']['eDP-1']['scale'] = 2
            with patch.dict(globals_, ROOT=root), patch.dict(globals_, run=lambda *args: None), \
                 patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, '', '')), \
                 patch('select.select', return_value=([], [], [])):
                apply(settings)
            self.assertEqual((root / 'devices.lua').read_bytes(), original)
            self.assertEqual(json.loads((root / 'settings.json').read_text())['monitors']['eDP-1']['scale'], 1)
            with patch.dict(globals_, ROOT=root), patch.dict(globals_, run=lambda *args: None), \
                 patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, 'invalid scale', '')):
                with self.assertRaises(ValueError):
                    apply(settings)
            self.assertEqual((root / 'devices.lua').read_bytes(), original)

    def test_bad_names(self):
        with self.assertRaises(ValueError):
            namespace['lua_string']('device\nname')

    def test_first_use_rollback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch.dict(globals_, ROOT=root), patch.dict(globals_, run=lambda *args: None), \
                 patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, '', '')), \
                 patch('select.select', return_value=([], [], [])):
                apply({'monitors': {}, 'pointers': {}})
            self.assertFalse((root / 'devices.lua').exists())
            self.assertFalse((root / 'settings.json').exists())


if __name__ == '__main__':
    unittest.main()
