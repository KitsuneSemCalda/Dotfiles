#!/usr/bin/env python3
"""Test flag preservation and scoped fstab edits without touching encryption."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'scripts/enable-root-trim.py'
spec = importlib.util.spec_from_file_location('trim', path)
trim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trim)


class RootTrim(unittest.TestCase):
    def test_boot_option_preserves_other_options_and_is_idempotent(self):
        original = 'KERNEL_CMDLINE[default]+="cryptdevice=UUID=abc:root:timeout=30 root=/dev/mapper/root"\n'
        updated = trim.boot_trim(original)
        self.assertIn(':root:timeout=30,allow-discards ', updated)
        self.assertEqual(trim.boot_trim(updated), updated)
        with self.assertRaises(RuntimeError):
            trim.boot_trim('root=/dev/mapper/root')

    def test_periodic_only_scoped_to_root_filesystem(self):
        original = '# comment\nUUID=root / btrfs rw,discard=async,subvol=@ 0 0\nUUID=root /home btrfs rw,subvol=@home 0 0\nUUID=other /mnt btrfs rw,discard 0 0\n'
        result = trim.periodic_fstab(original, 'root')
        self.assertIn('rw,subvol=@,nodiscard', result)
        self.assertIn('rw,subvol=@home,nodiscard', result)
        self.assertIn('UUID=other /mnt btrfs rw,discard 0 0', result)
        self.assertEqual(trim.periodic_fstab(result, 'root'), result)
        with self.assertRaises(RuntimeError):
            trim.periodic_fstab(original, 'missing')


if __name__ == '__main__':
    unittest.main()
