#!/usr/bin/env python3
"""Disposable cron and agent fixtures; never touches the user's crontab."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/loop.py"


class LoopTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.project = self.root / "project"
        self.project.mkdir()
        self.cron = self.root / "crontab.txt"
        self.cron.write_text("MAILTO=owner@example.org\n17 8 * * * /existing/job\n")
        fake_cron = self.bin / "crontab"
        fake_cron.write_text("""#!/usr/bin/env python3
import os, pathlib, sys
p = pathlib.Path(os.environ['FAKE_CRON_FILE'])
if sys.argv[1] == '-l':
    if not p.exists():
        print('no crontab for user', file=sys.stderr)
        sys.exit(1)
    print(p.read_text(), end='')
elif sys.argv[1] == '-':
    p.write_text(sys.stdin.read())
else:
    sys.exit(2)
""")
        fake_cron.chmod(0o755)
        fake_codex = self.bin / "codex"
        fake_codex.write_text("""#!/usr/bin/env python3
import os, pathlib, sys
if '--help' in sys.argv:
    print('--output-last-message --cd')
    sys.exit(0)
prompt = sys.stdin.read()
pathlib.Path(os.environ['FAKE_AGENT_CALLS']).open('a').write(prompt + '\\n')
out = pathlib.Path(sys.argv[sys.argv.index('--output-last-message') + 1])
out.write_text(os.environ['FAKE_AGENT_RESULT'])
""")
        fake_codex.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root), XDG_STATE_HOME=str(self.root / "state"),
                        XDG_CONFIG_HOME=str(self.root / "config"), LOOP_CRONTAB=str(fake_cron),
                        LOOP_AGENT="codex", FAKE_CRON_FILE=str(self.cron),
                        FAKE_AGENT_CALLS=str(self.root / "calls.txt"),
                        FAKE_AGENT_RESULT=json.dumps({"result": "no_change", "summary": "checked",
                                                      "memory": "only useful state"}),
                        PATH=str(self.bin) + os.pathsep + os.environ.get("PATH", ""))

    def call(self, *args, okay=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *args], cwd=self.project,
                                env=self.env, capture_output=True, text=True)
        if okay:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def task_id(self, output):
        return next(line.split(": ", 1)[1] for line in output.splitlines() if line.startswith("ID:"))

    def state(self, task_id):
        return json.loads((self.root / "state/skills/loop" / task_id / "state.json").read_text())

    def test_fixed_nonrepresentable_and_crontab_ownership(self):
        first = self.task_id(self.call("create", "--", "/loop 5m check CI").stdout)
        second = self.task_id(self.call("create", "--", "/loop 7m check build").stdout)
        cron = self.cron.read_text()
        self.assertIn("*/5 * * * *", cron)
        self.assertIn("* * * * * /usr/bin/env HOME=", cron)
        self.assertIn(f"{sys.executable} {SCRIPT} tick {second}", cron)
        self.assertIn("17 8 * * * /existing/job", cron)
        self.assertTrue(self.state(second)["tick"])
        self.call("pause", first)
        self.assertNotIn(f"skill-loop:{first}", self.cron.read_text())
        self.call("resume", first)
        self.call("edit", second, "--interval", "1h")
        self.assertIn("0 */1 * * *", self.cron.read_text())
        self.call("cancel", second)
        self.assertNotIn(f"skill-loop:{second}", self.cron.read_text())
        self.assertIn(f"skill-loop:{first}", self.cron.read_text())
        self.assertTrue(self.cron.read_text().startswith("MAILTO=owner@example.org\n17 8 * * * /existing/job\n"))

    def test_dynamic_iteration_and_completion(self):
        task_id = self.task_id(self.call("create", "--now", "--", "/loop watch CI").stdout)
        task = self.state(task_id)
        self.assertEqual(task["last_result"], "no_change")
        self.assertGreaterEqual(task["chosen_interval_seconds"], 300)
        self.assertEqual(task["run_count"], 1)
        self.assertIn("original_request", (self.root / "calls.txt").read_text())
        self.env["FAKE_AGENT_RESULT"] = json.dumps({"result": "completed", "summary": "build done", "memory": ""})
        until = self.task_id(self.call("create", "--now", "--", "/loop 5m watch build until it finishes").stdout)
        self.assertEqual(self.state(until)["status"], "completed")
        self.assertNotIn(f"skill-loop:{until}", self.cron.read_text())

    def test_default_prompt_and_invalid_skill(self):
        (self.project / ".loop.md").write_text("Inspect failing tests; do nothing when healthy.\n")
        task_id = self.task_id(self.call("create", "--", "/loop").stdout)
        self.assertIn("Inspect failing tests", self.state(task_id)["prompt"])
        bad = self.call("create", "--", "/loop 30m /missing-skill", okay=False)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn("not installed", bad.stderr)

    def test_natural_interval_rounding_and_invalid_agent_result(self):
        natural = self.task_id(self.call("create", "--", "/loop confira o deploy a cada 20 minutos").stdout)
        self.assertEqual(self.state(natural)["interval_seconds"], 1200)
        rounded_output = self.call("create", "--", "/loop 30s check the build").stdout
        rounded = self.task_id(rounded_output)
        self.assertIn("Requested 30s; scheduled 1m", rounded_output)
        self.assertEqual(self.state(rounded)["interval_seconds"], 60)
        self.env["FAKE_AGENT_RESULT"] = "not JSON"
        self.assertEqual(self.call("run", rounded).stdout.strip(), "failed")
        self.assertEqual(self.state(rounded)["last_result"], "failed")
        self.assertTrue(self.state(rounded)["enabled"])
        duplicate = self.call("create", "--", "/loop 30s check the build", okay=False)
        self.assertIn("already exists", duplicate.stderr)

    def test_cron_line_runs_with_minimal_environment(self):
        task_id = self.task_id(self.call("create", "--", "/loop 5m check CI").stdout)
        line = next(line for line in self.cron.read_text().splitlines() if line.endswith(f"tick {task_id}"))
        command = " ".join(line.split(" ")[5:])
        minimal = {key: self.env[key] for key in ("FAKE_AGENT_RESULT", "FAKE_AGENT_CALLS", "FAKE_CRON_FILE")}
        result = subprocess.run(["/bin/sh", "-c", command], env=minimal, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state(task_id)["run_count"], 1)


if __name__ == "__main__":
    unittest.main()
