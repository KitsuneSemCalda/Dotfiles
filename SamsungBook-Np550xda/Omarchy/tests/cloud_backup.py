#!/usr/bin/env python3
"""Use small synthetic files to exercise cloud quota and lossless evacuation."""
import os
from pathlib import Path
import random
import runpy
import tempfile
import unittest
from unittest.mock import patch
import zipfile

api = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'home/.local/bin/backup-zip'))


class CloudTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.source = self.root / 'state/current'
        (self.source / 'Documents').mkdir(parents=True)
        (self.source / 'Documents/keep').write_bytes(random.Random(42).randbytes(2048))
        (self.source / 'Downloads').mkdir()
        (self.source / 'Downloads/local-only').write_text('full backup only')
        self.dropbox = self.root / 'Dropbox'
        self.dropbox.mkdir()
        self.target = self.dropbox / 'Backups/SamsungBook-Np550xda/Omarchy/latest.zip'
        self.includes = self.root / 'cloud-includes'

    def publish(self):
        api['cloud'](self.source, self.dropbox, self.includes, '2026-10-24T00:00:00+00:00')

    def test_defaults_keep_one_current_zip_and_local_only_data(self):
        self.publish()
        with zipfile.ZipFile(self.target) as archive:
            self.assertIn('Documents/keep', archive.namelist())
            self.assertNotIn('Downloads/local-only', archive.namelist())
        old_size = self.target.stat().st_size
        previous = self.target.read_bytes()
        # The total must be strictly below the configured budget.
        with patch.dict(os.environ, HOME_BACKUP_DROPBOX_BUDGET_BYTES=str(old_size)):
            with self.assertRaises(ValueError):
                self.publish()
        self.assertEqual(self.target.read_bytes(), previous)
        # A replacement fits even when two simultaneous copies would exceed budget.
        with patch.dict(os.environ, HOME_BACKUP_DROPBOX_BUDGET_BYTES=str(old_size + 100)):
            self.publish()
        self.assertEqual(list(self.dropbox.rglob('*.zip')), [self.target])
        self.assertTrue((self.source / 'Downloads/local-only').exists())

    def test_quota_counts_other_files_and_preserves_previous_zip(self):
        self.publish()
        previous = self.target.read_bytes()
        other = self.dropbox / 'personal.dat'
        other.write_bytes(b'x' * 1000)
        with patch.dict(os.environ, HOME_BACKUP_DROPBOX_BUDGET_BYTES=str(len(previous) + 500)):
            with self.assertRaisesRegex(ValueError, 'budget exceeded'):
                self.publish()
        self.assertEqual(self.target.read_bytes(), previous)
        self.assertEqual(other.read_bytes(), b'x' * 1000)
        self.assertFalse(list(self.dropbox.rglob('.partial-*')))

    def test_oversized_first_backup_and_selection_escape_are_rejected(self):
        with patch.dict(os.environ, HOME_BACKUP_DROPBOX_BUDGET_BYTES='100'):
            with self.assertRaises(ValueError):
                self.publish()
        self.assertFalse(self.target.exists())
        self.includes.write_text('../outside\n')
        with self.assertRaises(ValueError):
            self.publish()

    def test_configurable_selection_avoids_nested_duplicate_entries(self):
        self.includes.write_text('Documents\nDocuments/keep\nDownloads\n')
        self.publish()
        with zipfile.ZipFile(self.target) as archive:
            self.assertEqual(archive.namelist().count('Documents/keep'), 1)
            self.assertIn('Downloads/local-only', archive.namelist())

    def test_old_cloud_backups_are_evacuated_and_retry_is_safe(self):
        legacy = self.dropbox / 'Backups/SamsungBook-Np550xda/Omarchy/home'
        path = legacy / '2025/2025-01-01.zip'
        path.parent.mkdir(parents=True)
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('keep', 'old version')
        original = path.read_bytes()
        local = self.root / 'state/archives/home'
        # Simulate interruption after copy but before removing the cloud file.
        (local / '2025').mkdir(parents=True)
        (local / '2025/2025-01-01.zip').write_bytes(original)
        api['relocate'](legacy, local)
        self.assertFalse(legacy.exists())
        self.assertEqual((local / '2025/2025-01-01.zip').read_bytes(), original)
        api['relocate'](legacy, local)

    def test_migration_failure_never_removes_cloud_original(self):
        legacy = self.dropbox / 'old'
        legacy.mkdir()
        path = legacy / 'old.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('keep', 'old version')
        with patch.dict(api['relocate'].__globals__, publish=lambda *args: (_ for _ in ()).throw(OSError('disk full'))):
            with self.assertRaises(OSError):
                api['relocate'](legacy, self.root / 'local')
        self.assertTrue(path.exists())


if __name__ == '__main__':
    unittest.main()
