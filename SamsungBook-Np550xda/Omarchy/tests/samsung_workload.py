import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest

path = Path(__file__).resolve().parents[1] / 'home/.local/bin/samsung-workload'
loader = importlib.machinery.SourceFileLoader('workload', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
workload = importlib.util.module_from_spec(spec)
loader.exec_module(workload)


class Workload(unittest.TestCase):
    def test_ac_hold_and_battery_passthrough(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            adapter = root / 'ADP1'
            adapter.mkdir()
            (adapter / 'type').write_text('Mains\n')
            (adapter / 'online').write_text('1\n')
            args = ['content', '--', 'ffmpeg', 'file with spaces;literal']
            command = workload.command_for(args, root)
            self.assertEqual(command[0:4], ['powerprofilesctl', 'launch', '--profile', 'performance'])
            self.assertEqual(command[-2:], args[-2:])
            (adapter / 'online').write_text('0\n')
            self.assertEqual(workload.command_for(args, root), args[-2:])

    def test_invalid_commands(self):
        for args in ([], ['gaming'], ['content', '--'], ['unknown', 'true']):
            with self.assertRaises(ValueError):
                workload.command_for(args)


if __name__ == '__main__':
    unittest.main()
