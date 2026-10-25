import copy
import tempfile
import unittest
from pathlib import Path

import homologate


def measured_report():
    run = {"seconds": 40, "output_hash": "same", "extra": {}}
    result = {"candidate": {"name": "baseline"}, "runs": [copy.deepcopy(run) for _ in range(3)],
              "resources": {"temperature_peak_c": 70, "samples": 120}}
    other = copy.deepcopy(result)
    other["candidate"]["name"] = "candidate"
    return {"config": {"min_seconds": 120}, "results": [result, other],
            "baseline_recheck": copy.deepcopy(result), "recommended": "baseline",
            "validation": "controlled protocol completed; real workload measurements"}


class AcceptanceChecks(unittest.TestCase):
    def test_reported_execution_error_cannot_be_accepted(self):
        report=measured_report()
        report["error"]="admission failed"
        self.assertTrue(homologate.assess(report))

    def test_short_raw_run_cannot_pass_by_claiming_long_protocol(self):
        report = measured_report()
        self.assertEqual(homologate.assess(report), [])
        report["results"][1]["runs"][0]["seconds"] = 1
        self.assertTrue(homologate.assess(report))

    def test_recheck_requires_actual_measurements(self):
        report = measured_report()
        report["baseline_recheck"]["runs"] = []
        self.assertTrue(homologate.assess(report))

    def test_speculative_requires_measured_acceptance_and_equal_outputs(self):
        report = measured_report()
        report["results"][1]["candidate"]["speculative"] = True
        self.assertTrue(homologate.assess(report, speculative=True))
        for row in report["results"][1]["runs"]:
            row["extra"]["draft_acceptance_ratio"] = .75
        self.assertEqual(homologate.assess(report, speculative=True), [])
        report["results"][1]["runs"][0]["output_hash"] = "different"
        self.assertTrue(homologate.assess(report, speculative=True))

    def test_additional_swap_requires_counters_and_enforces_limit(self):
        report=measured_report()
        report["config"]["quality"]={"swap_accounting":"additional","max_host_swap_bytes":256}
        self.assertTrue(homologate.assess(report))
        for result in report["results"]+[report["baseline_recheck"]]:
            result["resources"].update(host_swap_baseline_bytes=9000,host_swap_growth_peak_bytes=0,host_swap_io_bytes=0)
        self.assertEqual(homologate.assess(report),[])
        report["results"][1]["resources"]["host_swap_io_bytes"]=257
        self.assertTrue(homologate.assess(report))

    def test_missing_inventory_is_explicit_and_does_not_scan_elsewhere(self):
        with tempfile.TemporaryDirectory() as directory:
            result = homologate.inventory(Path(directory) / "missing")
            self.assertFalse(result["exists"])
            self.assertEqual(result["models"], [])

    def test_exit_zero_or_nine_phases_cannot_mean_all_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            run = homologate.Run(Path(directory))
            for number in range(1, 10):
                run.phases[number] = {"status": "passed"}
            self.assertFalse(run.summary()["all_passed"])
            run.phases[10] = {"status": "blocked"}
            self.assertFalse(run.summary()["all_passed"])
            run.phases[10]["status"] = "passed"
            self.assertTrue(run.summary()["all_passed"])


if __name__ == "__main__":
    unittest.main()
