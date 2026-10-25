#!/usr/bin/env python3
"""Exercise recovery without touching real displays."""
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'home/.local/bin/clamshell-recover'


class Recovery(unittest.TestCase):
    def test_initial_configuration_applies_after_all_overrides(self):
        lua = shutil.which('lua') or shutil.which('lua5.4')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        config = HELPER.parents[2] / '.config/hypr'
        self.assertTrue((config / 'hyprland.lua').read_text().rstrip().endswith("require('hypr.clamshell')"))
        # Combined lid/DRM result, including Lua 5.1 and 5.4 return conventions.
        for result, count in (('true', 1), ('0', 1), ('false', 0), ('nil', 0)):
            code = f'''
local calls = 0
os.execute = function(command)
  assert(command == 'omarchy-hw-clamshell >/dev/null 2>&1')
  return {result}
end
hl = {{monitor = function(rule)
  assert(rule.output == 'eDP-1' and rule.disabled == true)
  calls = calls + 1
end}}
dofile(arg[1])
assert(calls == {count})
'''
            with tempfile.TemporaryDirectory() as directory:
                test = Path(directory) / 'startup.lua'
                test.write_text(code)
                subprocess.run([lua, str(test), str(config / 'clamshell.lua')], check=True)

    def test_recovery_and_reload_limits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            log = root / 'log'
            commands = {
                'omarchy-hyprland-monitor-clamshell': 'exit "${RECONCILE_STATUS:-0}"',
                'omarchy-hyprland-monitor-modeless': 'exit "$MODELESS_STATUS"',
                'omarchy-hyprland-reload-guard': 'exit "$GUARD_STATUS"',
                'omarchy-hw-laptop-closed': 'exit "${LID_STATUS:-1}"',
                'hyprctl': 'if [ "$1" = monitors ]; then printf "%s\\n" "${MONITORS:-[]}"; else echo "$*" >> "$TEST_LOG"; fi',
            }
            for name, body in commands.items():
                path = root / name
                path.write_text('#!/bin/sh\n' + body + '\n')
                path.chmod(0o755)
            env = dict(os.environ, PATH=f'{root}:/usr/bin', XDG_RUNTIME_DIR=tmp,
                       TEST_LOG=str(log), MODELESS_STATUS='1', GUARD_STATUS='1')

            def run(**changes):
                return subprocess.run(['bash', str(HELPER)], env=env | changes,
                                      capture_output=True, text=True)

            self.assertEqual(run().returncode, 0)
            self.assertFalse(log.exists())  # Healthy/idle display: no reload.
            self.assertEqual(run(MODELESS_STATUS='0', GUARD_STATUS='0').returncode, 0)
            self.assertFalse(log.exists())  # Package update guard is respected.
            self.assertEqual(run(MODELESS_STATUS='0').returncode, 0)
            self.assertEqual(log.read_text(), 'reload\n')
            run(MODELESS_STATUS='0')
            self.assertEqual(log.read_text(), 'reload\n')  # Rate limited.
            (root / 'dotfiles-clamshell-last-reload').write_text('0\n')
            run(MODELESS_STATUS='0')
            self.assertEqual(log.read_text(), 'reload\nreload\n')
            self.assertNotEqual(run(RECONCILE_STATUS='1').returncode, 0)
            monitor = '[{"name":"HDMI-A-2","model":"SMB2030N","width":1600,"height":900,"disabled":false}]'
            log.write_text('')
            result = run(MONITORS=monitor, LID_STATUS='0')
            self.assertEqual(result.returncode, 0, result.stderr)
            actions = log.read_text()
            self.assertIn('dpms', actions)
            self.assertIn('focus', actions)
            run(MONITORS=monitor, LID_STATUS='0')
            self.assertEqual(log.read_text(), actions)  # Never steal focus per poll.
            run(MONITORS='[]', LID_STATUS='0')
            run(MONITORS=monitor, LID_STATUS='0')
            self.assertEqual(log.read_text(), actions + actions)

            # A successful stock helper with a stale toggle must not hide drift.
            drift = monitor[:-1] + ',{"name":"eDP-1","disabled":false}]'
            log.write_text('')
            result = run(MONITORS=drift, LID_STATUS='0')
            self.assertNotEqual(result.returncode, 0)  # Fake output never changes.
            self.assertIn('eval hl.monitor({ output = "eDP-1", disabled = true })',
                          log.read_text())
            self.assertIn('remains enabled', result.stderr)
            log.write_text('')
            self.assertEqual(run(MONITORS=drift, LID_STATUS='1').returncode, 0)
            self.assertNotIn('eval', log.read_text())  # Open lid permits two screens.
            log.write_text('')
            internal_only = '[{"name":"eDP-1","disabled":false}]'
            self.assertEqual(run(MONITORS=internal_only, LID_STATUS='0').returncode, 0)
            self.assertNotIn('eval', log.read_text())  # Never remove the only output.


if __name__ == '__main__':
    unittest.main()
