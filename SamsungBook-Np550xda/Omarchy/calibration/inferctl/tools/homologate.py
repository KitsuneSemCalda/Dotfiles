#!/usr/bin/env python3
"""Bounded local acceptance run. Never promote missing/skipped prerequisites to a pass.

Uses only the standard library and inferctl itself. No downloads, privileged calls,
persistent service installation, model deletion, or configuration of the host.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import signal
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
NAMES = ["hardware", "lmstudio", "profiles", "governor", "comfyui", "docker",
         "pareto", "scheduler", "thermal", "speculative"]


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def save(path, data):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("w") as handle:
        os.chmod(temp, 0o600)
        json.dump(data, handle, indent=2, ensure_ascii=False, allow_nan=False)
        handle.write("\n")
    temp.replace(path)


class Run:
    def __init__(self, directory):
        self.directory = directory
        self.records = []
        self.phases = {}
        self.env = os.environ.copy()
        self.env["INFERCTL_STATE"] = str(directory / "state")

    def command(self, name, argv, timeout=120, env=None):
        started = time.monotonic()
        record = {"name": name, "argv": list(map(str, argv)), "started": now()}
        process = None
        try:
            process = subprocess.Popen(record["argv"], cwd=ROOT, env=env or self.env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       start_new_session=True)
            out, err = process.communicate(timeout=timeout)
            record["exit_code"] = process.returncode
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGINT)
            try:
                out, err = process.communicate(timeout=55)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                out, err = process.communicate()
            record["exit_code"] = 124
            err += b"\nqualification command timed out; owned workload cleanup required\n"
        except OSError as exc:
            record["exit_code"] = 127
            out, err = b"", str(exc).encode()
        for suffix, content in [("stdout", out), ("stderr", err)]:
            path = self.directory / f"{name}.{suffix}"
            path.write_bytes(content)
            os.chmod(path, 0o600)
            record[suffix] = path.name
        record["seconds"] = time.monotonic() - started
        self.records.append(record)
        save(self.directory / "commands.json", self.records)
        return record

    def output_json(self, record):
        return json.loads((self.directory / record["stdout"]).read_text())

    def phase(self, number, status, reason, evidence=(), scope=None):
        item = {"phase": number, "name": NAMES[number-1], "status": status,
                "reason": reason, "evidence": list(evidence)}
        if scope:
            item["scope"] = scope
        self.phases[number] = item
        save(self.directory / "qualification.json", self.summary())
        print(f"{number:2}. {item['name']:12} {status:8} {reason}", flush=True)

    def summary(self):
        return {"version": 1, "updated": now(), "environment": platform.platform(),
                "all_passed": len(self.phases) == 10 and all(
                    p["status"] == "passed" for p in self.phases.values()),
                "phases": [self.phases[k] for k in sorted(self.phases)],
                "commands": "commands.json"}


def inventory(directory):
    """List metadata, bounded to avoid unbounded scans; do not read GGUF contents."""
    result = {"directory": str(directory), "exists": directory.is_dir(), "models": [], "truncated": False}
    if result["exists"]:
        seen = 0
        for parent, dirs, files in os.walk(directory, followlinks=False):
            dirs.sort()
            for name in sorted(files):
                seen += 1
                if seen > 10000:
                    result["truncated"] = True
                    return result
                if name.lower().endswith(".gguf"):
                    path = Path(parent) / name
                    try:
                        result["models"].append({"path": str(path), "bytes": path.stat().st_size})
                    except OSError as exc:
                        result["models"].append({"path": str(path), "error": str(exc)})
    return result


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def endpoint(url):
    try:
        req = urllib.request.Request(url)
        token = os.environ.get("INFERCTL_API_TOKEN")
        if token:
            req.add_header("Authorization", "Bearer " + token)
        with urllib.request.build_opener(NoRedirect).open(req, timeout=3) as response:
            data = response.read(4 * 1024 * 1024 + 1)
            if len(data) > 4 * 1024 * 1024:
                return {"reachable": False, "error": "inventory response exceeds 4 MiB"}
            return {"reachable": True, "data": json.loads(data)}
    except (OSError, ValueError, urllib.error.HTTPError) as exc:
        return {"reachable": False, "error": str(exc)}


def profile(path, backend=None, native=False):
    if not path:
        return None, "profile not supplied"
    try:
        config = json.loads(path.read_text())
        if backend and config.get("backend") != backend:
            return None, f"expected {backend} profile"
        if native and not config.get("command"):
            return None, "profile requires a managed native command"
        if config.get("policy", {}).get("required_ram_bytes", 0) <= 0:
            return None, "profile requires an explicit measured/budgeted RAM requirement"
        if config.get("min_seconds", 0) < 120:
            return None, "acceptance requires >=120 measured seconds per candidate"
        return config, None
    except (OSError, ValueError) as exc:
        return None, str(exc)


def assess(report, speculative=False, thermal=False):
    """Validate raw observations as well as process exit status and display labels."""
    reasons = []
    if report.get("error"):
        reasons.append("execution reported an error")
    config = report.get("config", {})
    minimum = 300 if thermal else 120
    if config.get("min_seconds", 0) < minimum:
        reasons.append("sustained-duration protocol too short")
    if report.get("validation") != "controlled protocol completed; real workload measurements":
        reasons.append("benchmark protocol was not completed")
    results = report.get("results", [])
    if len(results) < 2 or not report.get("baseline_recheck"):
        reasons.append("comparison and final baseline recheck required")
    observed = [r for r in results if not r.get("error")]
    if len(observed)<2 or not results or results[0].get("error"):
        reasons.append("successful baseline and comparison candidate required")
    for r in observed + ([report["baseline_recheck"]] if report.get("baseline_recheck") else []):
        runs = r.get("runs", [])
        resources = r.get("resources", {})
        if len(runs) < 3 or sum(m.get("seconds", 0) for m in runs) < minimum:
            reasons.append(f"{r.get('candidate', {}).get('name')}: insufficient raw measurements")
        if resources.get("temperature_peak_c") is None:
            reasons.append("missing thermal evidence")
        if resources.get("samples", 0) < 2:
            reasons.append("missing resource sampling")
        quality=config.get("quality",{})
        if quality.get("swap_accounting")=="additional":
            limit=quality.get("max_host_swap_bytes")
            if resources.get("host_swap_baseline_bytes") is None or limit is None:
                reasons.append("missing additional swap evidence")
            elif resources.get("host_swap_growth_peak_bytes",limit+1)>limit or resources.get("host_swap_io_bytes",limit+1)>limit:
                reasons.append("additional swap budget exceeded")
    if speculative:
        base_runs=results[0].get("runs",[]) if results else []
        for r in observed:
            if not r.get("candidate",{}).get("speculative"):continue
            for index,m in enumerate(r.get("runs",[])):
                extra=m.get("extra",{})
                if "draft_acceptance_ratio" not in extra or not 0<=extra["draft_acceptance_ratio"]<=1:
                    reasons.append("missing or invalid draft acceptance ratio")
                if index<len(base_runs) and m.get("output_hash")!=base_runs[index].get("output_hash"):
                    reasons.append("speculation changed deterministic output")
    if speculative and not any(r.get("candidate", {}).get("speculative") for r in observed):
        reasons.append("no successfully measured draft candidate")
    if thermal and not any(r.get("candidate", {}).get("limits", {}).get("cpu_quota_percent", 0) > 0 for r in observed):
        reasons.append("no successfully measured CPU quota candidate")
    if not report.get("recommended"):
        reasons.append("no candidate passed selection constraints")
    return sorted(set(reasons))


def calibrate(run, label, path, config, extra=()):
    candidates = max(1, len(config.get("candidates", [])))
    # Includes adaptive candidates, readiness and cleanup; each backend still has its own timeout.
    budget = min(86400, int(config.get("timeout_seconds", 1800) * max(8, candidates + 2) + 180))
    record = run.command(label, [ROOT / "bin/inferctl", "calibrate", config["backend"],
                                 "--profile", path, *extra], timeout=budget)
    if record["exit_code"]:
        return None, [f"calibration failed; see {record['stderr']}"], record
    try:
        report = run.output_json(record)
    except (ValueError, OSError) as exc:
        return None, [str(exc)], record
    return report, assess(report, speculative="--draft-model" in extra, thermal="--thermal" in extra), record


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true", help="run bounded real integrations and explicitly supplied workloads")
    parser.add_argument("--output", type=Path, help="new private artifact directory; must not already exist")
    parser.add_argument("--models-dir", type=Path, default=Path.home() / ".lmstudio/models")
    for name in ("lmstudio", "native", "comfyui"):
        parser.add_argument(f"--{name}-profile", type=Path)
    parser.add_argument("--draft-model", type=Path)
    parser.add_argument("--lmstudio-url", default="http://127.0.0.1:1234")
    parser.add_argument("--comfyui-url", default="http://127.0.0.1:8188")
    args = parser.parse_args(argv)
    directory = args.output or Path(os.environ.get("XDG_STATE_HOME", str(Path.home()/".local/state"))) / "inferctl/qualification" / dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    directory = directory.expanduser().absolute()
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    run = Run(directory)
    print(f"Artifacts: {directory}", flush=True)
    tests = run.command("unit-tests", ["go", "test", "-race", "-count=1", "./..."], timeout=300)
    vet = run.command("vet", ["go", "vet", "./..."], timeout=120)
    build = run.command("build", ["go", "build", "-trimpath", "-o", "bin/inferctl", "./cmd/inferctl"], timeout=120)
    if any(r["exit_code"] for r in (tests, vet, build)):
        for phase in range(1, 11):
            run.phase(phase, "failed" if phase == 1 else "blocked", "build/static/unit acceptance failed", ["commands.json"])
        return 1
    sources=[]
    for path in sorted(ROOT.rglob("*")):
        if path.is_file() and (path.suffix in {".go",".py"} or path.name in {"go.mod","Makefile"}) and "__pycache__" not in path.parts:
            sources.append({"path":str(path.relative_to(ROOT)),"sha256":hashlib.sha256(path.read_bytes()).hexdigest()})
    save(directory / "source-manifest.json", sources)
    save(directory / "binary.json", {"sha256":hashlib.sha256((ROOT/"bin/inferctl").read_bytes()).hexdigest()})
    models = inventory(args.models_dir.expanduser())
    save(directory / "models.json", models)
    systemd = run.command("systemd-status", ["systemctl", "--user", "show", "--property=SystemState", "--value"], timeout=5)
    docker = run.command("docker-info", ["docker", "info", "--format", "{{json .}}"], timeout=10)
    lm_profile_config,lm_profile_error=profile(args.lmstudio_profile,"lmstudio")
    comfy_profile_config,comfy_profile_error=profile(args.comfyui_profile,"comfyui")
    if lm_profile_config:args.lmstudio_url=lm_profile_config.get("url",args.lmstudio_url)
    if comfy_profile_config:args.comfyui_url=comfy_profile_config.get("url",args.comfyui_url)
    lm = endpoint(args.lmstudio_url.rstrip("/") + "/api/v1/models")
    comfy = endpoint(args.comfyui_url.rstrip("/") + "/system_stats")
    save(directory / "prerequisites.json", {"systemd_user": systemd["exit_code"] == 0,
         "docker_daemon": docker["exit_code"] == 0, "lmstudio": lm, "comfyui": comfy,
         "gpu_device_access": Path("/dev/dri").exists() or Path("/dev/nvidia0").exists(),
         "models_visible": models["exists"], "model_count": len(models["models"])})
    hardware = run.command("hardware", [ROOT / "bin/inferctl", "hardware", "--interval", "1s"], timeout=15)
    try:
        observation = run.output_json(hardware)
        snapshot = observation["snapshot"]
        cpu, memory = snapshot["cpu"], snapshot["memory"]
        if hardware["exit_code"] or cpu["threads"] < 1 or not 0 <= observation["cpu_utilization_percent"] <= 100 or not 0 < memory["Available"] <= memory["Total"]:
            raise ValueError("invalid topology, CPU delta or RAM counters")
        mem_total = next(int(line.split()[1])*1024 for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemTotal:"))
        if mem_total != memory["Total"]:
            raise ValueError("profiler RAM differs from kernel")
        if cpu["threads"] != (os.cpu_count() or 0):
            raise ValueError("profiler logical CPU count differs from Python/OS")
        run.phase(1, "passed", "real kernel counters cross-checked", [hardware["stdout"]],
                  "visible Linux CPU/RAM/PSI/storage; GPU acceleration requires device access and workload")
    except (KeyError, ValueError, TypeError, OSError, StopIteration) as exc:
        run.phase(1, "failed", str(exc), [hardware["stdout"]])
    lm_config,lm_error=lm_profile_config,lm_profile_error
    lm_report = None
    if args.execute and lm_config and lm["reachable"] and run.phases[1]["status"] == "passed":
        lm_report, problems, record = calibrate(run, "lmstudio-calibration", args.lmstudio_profile.absolute(), lm_config)
        run.phase(2, "failed" if problems else "passed", "; ".join(problems) or "real LLM baseline/candidates/recheck", [record["stdout"], record["stderr"]])
    else:
        run.phase(2, "blocked", lm_error or ("LM Studio endpoint unreachable" if not lm["reachable"] else "real execution requires --execute"), ["prerequisites.json", "models.json"])
    if lm_report and run.phases[2]["status"] == "passed":
        compare = run.command("compare-real", [ROOT / "bin/inferctl", "compare", directory / "lmstudio-calibration.stdout"], timeout=15)
        try:
            compared = run.output_json(compare)
            if compare["exit_code"] or compared["recommended"] != lm_report["recommended"] or compared["pareto"] != lm_report["pareto"]:
                raise ValueError("selection changed on persisted report")
            run.phase(3, "passed", "persisted real report replays identical selection", [compare["stdout"]])
        except (KeyError, ValueError, OSError) as exc:
            run.phase(3, "failed", str(exc), [compare["stderr"]])
    else:
        run.phase(3, "blocked", "needs accepted real baseline; persistence unit tests passed", [tests["stdout"]])
    if args.execute and systemd["exit_code"] == 0:
        env = run.env.copy()
        env["INFERCTL_REAL_SYSTEMD"] = "1"
        native = run.command("systemd-integration", ["go", "test", "-count=1", "-v", "./internal/governor", "-run", "^TestSystemdIntegration$"], timeout=60, env=env)
        text = (directory / native["stdout"]).read_text()
        ok = native["exit_code"] == 0 and "--- PASS: TestSystemdIntegration" in text and "--- SKIP:" not in text
        run.phase(4, "passed" if ok else "failed", "real transient unit, kernel controls, weight update and reset" if ok else "real governor integration failed", [native["stdout"], native["stderr"]])
    else:
        run.phase(4, "blocked", "systemd user bus unavailable" if systemd["exit_code"] else "real execution requires --execute", [systemd["stderr"]])
    comfy_config,comfy_error=comfy_profile_config,comfy_profile_error
    comfy_report = None
    if args.execute and comfy_config and (comfy_config.get("container") and docker["exit_code"] == 0 or comfy_config.get("command") and run.phases[4]["status"] == "passed" or not comfy_config.get("container") and not comfy_config.get("command") and comfy["reachable"]):
        comfy_report, problems, record = calibrate(run, "comfyui-calibration", args.comfyui_profile.absolute(), comfy_config)
        # Workflow outputs alone do not prove equivalent image/video quality or node instrumentation.
        run.phase(5, "failed" if problems else "blocked", "; ".join(problems) or "generation measured; node/offload instrumentation and output-quality evidence still required", [record["stdout"], record["stderr"]])
    else:
        run.phase(5, "blocked", comfy_error or "ComfyUI endpoint or managed runtime unavailable", ["prerequisites.json"])
    if args.execute and docker["exit_code"]==0 and comfy_config and comfy_config.get("container"):
        env=run.env.copy();env["INFERCTL_REAL_DOCKER_PROFILE"]=str(args.comfyui_profile.absolute())
        container=run.command("docker-integration",["go","test","-count=1","-v","./internal/docker","-run","^TestDockerIntegration$"],timeout=120,env=env)
        text=(directory/container["stdout"]).read_text()
        ok=container["exit_code"]==0 and "--- PASS: TestDockerIntegration" in text and "--- SKIP:" not in text
        run.phase(6,"passed" if ok else "failed","real pinned image, limits, mounts, persistence and torch accelerator" if ok else "real Docker integration failed",[container["stdout"],container["stderr"]],"only supplied image and configured GPU runtime")
    else:
        run.phase(6,"blocked",("Docker access denied" if "permission denied" in (directory/docker["stderr"]).read_text().lower() else "Docker daemon/socket unavailable") if docker["exit_code"] else "pinned ComfyUI container profile and --execute required",[docker["stderr"]])
    if lm_report and run.phases[3]["status"] == "passed":
        run.phase(7, "passed", "real data replay plus adversarial Pareto/floor regression tests", ["compare-real.stdout", tests["stdout"]], "current objective metrics; no claim of global optimum or measured offload knee")
    else:
        run.phase(7, "blocked", "real comparison unavailable; algorithmic regression tests passed", [tests["stdout"]])
    run.phase(8, "blocked", "requires actual sustained pressure/recovery and desktop-responsiveness evidence; unit hysteresis alone is insufficient", [tests["stdout"]])
    native_config, native_error = profile(args.native_profile, native=True)
    for number, label, extra in [(9, "thermal-calibration", ["--thermal"]), (10, "speculative-calibration", ["--draft-model", str(args.draft_model.absolute())] if args.draft_model else [])]:
        missing = native_error
        if number == 10 and not args.draft_model:
            missing = "local compatible draft model path required"
        if number == 10 and native_config and native_config.get("backend") != "llamacpp":
            missing = "speculative acceptance requires managed llamacpp profile"
        if args.execute and not missing and native_config and run.phases[4]["status"] == "passed":
            report, problems, record = calibrate(run, label, args.native_profile.absolute(), native_config, extra)
            # These remaining gates require evidence not yet emitted by the implementation.
            pending = "thermal plateau and independent desktop responsiveness not yet verified" if number == 9 else "draft acceptance-rate telemetry not yet verified"
            run.phase(number, "failed" if problems else "passed" if number==10 else "blocked", "; ".join(problems) or ("real main/draft comparison with acceptance telemetry and output equivalence" if number==10 else pending), [record["stdout"], record["stderr"]])
        else:
            run.phase(number, "blocked", missing or "managed native runtime unavailable", ["prerequisites.json"])
    code = 0 if run.summary()["all_passed"] else 1 if any(p["status"] == "failed" for p in run.phases.values()) else 2
    # This state directory belongs exclusively to this suite, never to another inferctl session.
    cleanup=run.command("owned-reset",[ROOT/"bin/inferctl","reset"],timeout=60)
    if cleanup["exit_code"]:
        run.phase(4,"failed","owned-resource cleanup failed",[cleanup["stderr"]])
        code=1
    print(f"Result: {'all accepted' if code == 0 else 'failed checks' if code == 1 else 'blocked; not all phases accepted'}", flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
