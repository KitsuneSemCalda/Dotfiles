#!/usr/bin/env python3
"""Exercise policy drift, absent peripherals and pending reboot without host writes."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


system = load('samsung_system', ROOT / 'scripts/samsung-hardware-state.py')
session = load('samsung_session', ROOT / 'home/.local/bin/enforce-samsung-session')


class HardwarePolicy(unittest.TestCase):
    def test_rtkit_reset_on_fork_flag_is_realtime_but_timesharing_is_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = Path(tmp); task = proc / '123/task/456'; task.mkdir(parents=True)
            (task / 'comm').write_text('data-loop.0')
            with patch.object(session, 'PROC', proc), patch.object(session, 'command', return_value='123'), \
                    patch.object(session.os, 'sched_getparam', return_value=Mock(sched_priority=20)), \
                    patch.object(session.os, 'sched_getscheduler', return_value=session.os.SCHED_RR | session.os.SCHED_RESET_ON_FORK) as policy:
                self.assertTrue(session.realtime_ready())
                policy.return_value = session.os.SCHED_OTHER
                self.assertFalse(session.realtime_ready())

    def test_repeat_install_repairs_battery_and_ethernet_drift_and_marks_reboot(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            files = {'class/dmi/id/board_name': 'NP550XDA-KF2BR',
                     'class/power_supply/BAT1/charge_control_end_threshold': '100',
                     'module/i915/parameters/enable_guc': '-1',
                     'bus/pci/devices/test/vendor': '0x10ec',
                     'bus/pci/devices/test/device': '0x8168',
                     'bus/pci/devices/test/subsystem_vendor': '0x144d',
                     'bus/pci/devices/test/subsystem_device': '0xc195',
                     'bus/pci/devices/test/power/control': 'on', 'boot-id': 'boot-1'}
            for name, value in files.items():
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(value)
            driver = root / 'drivers/r8169'; driver.mkdir(parents=True)
            (root / 'bus/pci/devices/test/driver').symlink_to(driver)
            report = root / 'report/hardware.json'
            with patch.object(system, 'SYS', root), patch.object(system, 'REPORT', report), \
                    patch.object(system, 'BOOT_ID', root / 'boot-id'), \
                    patch.object(system, 'command', return_value=''), contextlib.redirect_stdout(io.StringIO()):
                self.assertTrue(system.reconcile()['huc_pending_reboot'])
                battery = root / 'class/power_supply/BAT1/charge_control_end_threshold'
                ethernet = root / 'bus/pci/devices/test/power/control'
                self.assertEqual(battery.read_text().strip(), '80')
                self.assertEqual(ethernet.read_text().strip(), 'auto')
                battery.write_text('100'); ethernet.write_text('on')
                (root / 'module/i915/parameters/enable_guc').write_text('2')
                self.assertFalse(system.reconcile()['huc_pending_reboot'])
                self.assertEqual(battery.read_text().strip(), '80')
                self.assertEqual(ethernet.read_text().strip(), 'auto')
                self.assertEqual(json.loads(report.read_text())['boot_id'], 'boot-1')

    def test_rejected_sysfs_write_fails_instead_of_reporting_success(self):
        path = Mock(); path.read_text.side_effect = ['100', '100']
        with self.assertRaises(RuntimeError):
            system.enforce(path, '80')

    def test_supply_order_and_profiles_are_reapplied_every_time(self):
        for battery in (False, True):
            expected = 'power-saver' if battery else 'balanced'
            def command(*args):
                if args[0] == 'busctl': return 'b true' if battery else 'b false'
                if args[0] == 'powerprofilesctl': return expected
                return ''
            with patch.object(session, 'command', side_effect=command) as call, \
                    contextlib.redirect_stdout(io.StringIO()):
                session.apply_profiles(); session.apply_profiles()
                settings = [c.args[-2:] for c in call.call_args_list if c.args[0] == 'omarchy']
                pair = [('ac', 'balanced'), ('battery', 'power-saver')] if battery else \
                       [('battery', 'power-saver'), ('ac', 'balanced')]
                self.assertEqual(settings, pair * 2)

    def test_profile_failure_is_not_hidden(self):
        def command(*args):
            return 'b false' if args[0] == 'busctl' else 'performance'
        with patch.object(session, 'command', side_effect=command), self.assertRaises(RuntimeError):
            session.apply_profiles()

    def test_absent_mic_stores_preference_without_starting_recording(self):
        metadata = {'metadata': [{'key': 'default.configured.audio.source',
                                 'value': {'name': session.FIFINE}}]}
        with patch.object(session, 'audio_nodes', side_effect=[[], [metadata]]), \
                patch.object(session, 'command', return_value='') as command, \
                contextlib.redirect_stdout(io.StringIO()):
            session.select_microphone()
            self.assertEqual(command.call_args.args[0], 'pw-metadata')
            self.assertIn(session.FIFINE, command.call_args.args[5])

    def test_multiple_fifines_fail_without_overwriting_selection(self):
        node = {'type': 'PipeWire:Interface:Node', 'info': {'props': {
            'media.class': 'Audio/Source', 'node.name': session.FIFINE}}}
        with patch.object(session, 'audio_nodes', return_value=[node, node]), \
                patch.object(session, 'command') as command, self.assertRaises(RuntimeError):
            session.select_microphone()
        command.assert_not_called()

    def test_stale_boot_report_fails_and_pending_reboot_does_not_claim_encoder_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            report = root / 'report'; boot = root / 'boot'; battery = root / 'battery'
            boot.write_text('new'); battery.write_text('80')
            report.write_text(json.dumps({'boot_id': 'old', 'huc_pending_reboot': False}))
            with patch.object(session, 'REPORT', report), patch.object(session, 'BOOT_ID', boot), \
                    patch.object(session, 'BATTERY', battery), patch.object(session, 'command') as command:
                with self.assertRaises(RuntimeError): session.verify_hardware()
                report.write_text(json.dumps({'boot_id': 'new', 'huc_pending_reboot': True}))
                with contextlib.redirect_stdout(io.StringIO()) as output: session.verify_hardware()
                self.assertIn('PENDING', output.getvalue())
                command.assert_not_called()
                report.write_text(json.dumps({'boot_id': 'new', 'huc_pending_reboot': False}))
                session.verify_hardware()
                self.assertEqual(command.call_args.args[0], 'ffmpeg')


if __name__ == '__main__':
    unittest.main()
