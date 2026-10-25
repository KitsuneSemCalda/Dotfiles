import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from inspect_memory import by_name, process_memory


class MemoryCensusTests(unittest.TestCase):
    def fixture(self, root, rollup=True):
        directory=Path(root)/"42"
        directory.mkdir()
        (directory/"stat").write_text("42 (name with spaces) "+" ".join(["S"]+["0"]*18+["1234"]))
        (directory/"status").write_text("Uid:\t1000 1000 1000 1000\nPPid:\t7\nVmRSS:\t100 kB\nVmSwap:\t50 kB\n")
        (directory/"comm").write_text("app\n")
        if rollup:
            (directory/"smaps_rollup").write_text("Pss:\t60 kB\nSwapPss:\t20 kB\nPss_Anon:\t40 kB\n")
        return directory

    def test_shared_rss_not_summed_as_pss(self):
        with tempfile.TemporaryDirectory() as root:
            record=process_memory(self.fixture(root),1000)
            self.assertEqual(record["pss_bytes"],60*1024)
            self.assertEqual(record["rss_bytes"],100*1024)
            group=by_name([record,record])[0]
            self.assertEqual(group["known_pss_bytes"],120*1024)
            self.assertEqual(group["known_swap_pss_logical_bytes"],40*1024)

    def test_missing_pss_is_unknown_and_uid_is_checked(self):
        with tempfile.TemporaryDirectory() as root:
            directory=self.fixture(root,False)
            record=process_memory(directory,1000)
            self.assertNotIn("pss_bytes",record)
            self.assertIn("pss_error",record)
            self.assertEqual(by_name([record])[0]["pss_available_processes"],0)
            self.assertIsNone(process_memory(directory,9999))

    def test_recycled_pid_is_discarded(self):
        with tempfile.TemporaryDirectory() as root:
            directory=self.fixture(root)
            with patch("inspect_memory.start_time",side_effect=[1234,9999]):
                self.assertIsNone(process_memory(directory,1000))
