#!/usr/bin/env python3
"""Manage cron-backed, single-iteration agent loops. No prompt is run as shell."""

import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import random
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time


HERE = Path(__file__).resolve()
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "skills/loop"
CRONTAB = os.environ.get("LOOP_CRONTAB", "crontab")
INTERVAL = re.compile(r"^(\d+)([smhd])$")
TAIL = re.compile(
    r"\s+(?:every\s+(\d+)\s*(seconds?|minutes?|hours?|days?|[smhd])|"
    r"a\s+cada\s+(\d+)\s*(segundos?|minutos?|horas?|dias?|[smhd]))\s*$",
    re.I,
)
RESULTS = {"changed", "no_change", "completed", "failed", "timeout", "skipped", "blocked"}
DEFAULT = """Continue useful unfinished work already authorized for this project.
Inspect the current state before acting. Finish authorized work, check relevant failures, builds,
CI, issues or PRs, and resolve clear regressions within the original authorization. If nothing
requires action, do one bounded maintenance pass. Do not invent work. Return no_change and exit."""


def now():
    return dt.datetime.now(dt.timezone.utc)


def stamp(value):
    return value.astimezone(dt.timezone.utc).isoformat(timespec="seconds")


def parse_time(value):
    return dt.datetime.fromisoformat(value)


def seconds(value):
    match = INTERVAL.fullmatch(value.strip().lower())
    if not match or int(match[1]) == 0:
        raise ValueError(f"invalid interval: {value}")
    return int(match[1]) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[match[2]]


def label(value):
    if value % 86400 == 0:
        return f"{value // 86400}d"
    if value % 3600 == 0:
        return f"{value // 3600}h"
    if value % 60 == 0:
        return f"{value // 60}m"
    return f"{value}s"


def parse_request(raw, cwd):
    value = raw.strip()
    value = re.sub(r"^(?:/loop|\$loop)(?:\s+|$)", "", value, count=1).strip()
    interval = None
    note = None
    first, _, rest = value.partition(" ")
    if INTERVAL.fullmatch(first):
        interval, value = seconds(first), rest.strip()
    else:
        match = TAIL.search(value)
        if match:
            count = match[1] or match[3]
            unit = (match[2] or match[4]).lower()
            unit = {"segundos": "s", "segundo": "s", "seconds": "s", "second": "s",
                    "minutos": "m", "minuto": "m", "minutes": "m", "minute": "m",
                    "horas": "h", "hora": "h", "hours": "h", "hour": "h",
                    "dias": "d", "dia": "d", "days": "d", "day": "d"}.get(unit, unit)
            interval = seconds(count + unit)
            value = value[:match.start()].strip()
    if interval is not None and interval < 60:
        note = f"Requested {label(interval)}; scheduled 1m (cron has minute resolution)"
        interval = 60
    source = "explicit"
    if not value:
        project = cwd / ".loop.md"
        user = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "skills/loop.md"
        for candidate in (project, user):
            if candidate.is_file():
                value = candidate.read_text(encoding="utf-8").strip()
                source = str(candidate)
                break
        if not value:
            value, source = DEFAULT, "built-in"
    return value, interval, source, note


def check_skill(prompt, agent):
    if not prompt.startswith("/"):
        return
    name = prompt.split(maxsplit=1)[0][1:]
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
        raise ValueError("invalid Skill name in prompt")
    home = Path.home()
    roots = [home / ".codex/skills"] if agent == "codex" else [home / ".claude/skills"]
    for root in roots:
        skill = root / name / "SKILL.md"
        if not skill.is_file():
            continue
        content = skill.read_text(encoding="utf-8")
        if not re.search(r"(?m)^name:\s*" + re.escape(name) + r"\s*$", content):
            raise ValueError(f"installed Skill {name} has an invalid name")
        policy = root / name / "agents/openai.yaml"
        if policy.is_file() and re.search(r"allow_implicit_invocation:\s*false", policy.read_text()):
            raise ValueError(f"Skill {name} does not permit automatic invocation")
        return
    raise ValueError(f"Skill {name} is not installed for {agent}")


def agent_command(agent, executable=None):
    path = executable or shutil.which(agent)
    if not path:
        raise ValueError(f"supported agent CLI not found: {agent}")
    if agent == "codex":
        return [path, "exec", "--sandbox", "workspace-write", "--output-last-message"]
    if agent == "claude":
        return [path, "-p", "--output-format", "text"]
    raise ValueError(f"unsupported noninteractive agent CLI: {agent}")


def select_agent():
    requested = os.environ.get("LOOP_AGENT")
    if requested:
        preflight_agent(requested)
        return requested
    for candidate in ("codex", "claude"):
        if shutil.which(candidate):
            preflight_agent(candidate)
            return candidate
    raise ValueError("no supported noninteractive agent CLI found (codex or claude)")


def preflight_agent(agent):
    command = agent_command(agent)
    probe = [command[0], "exec", "--help"] if agent == "codex" else [command[0], "--help"]
    result = subprocess.run(probe, text=True, capture_output=True, timeout=10)
    help_text = result.stdout + result.stderr
    required = ("--output-last-message", "--cd") if agent == "codex" else ("--print", "--output-format")
    if result.returncode or not all(flag in help_text for flag in required):
        raise ValueError(f"{agent} CLI does not expose the required noninteractive interface")


def task_path(task_id):
    if not re.fullmatch(r"[0-9a-f]{8}", task_id):
        raise ValueError("invalid task ID")
    return STATE / task_id


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temp = tempfile.mkstemp(prefix=".state-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(data, file, indent=2, ensure_ascii=False)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def load(task_id):
    path = task_path(task_id) / "state.json"
    if not path.is_file():
        raise ValueError(f"loop not found: {task_id}")
    return json.loads(path.read_text(encoding="utf-8"))


def save(task):
    write_json(task_path(task["id"]) / "state.json", task)


def all_tasks():
    if not STATE.exists():
        return []
    tasks = []
    for path in sorted(STATE.glob("[0-9a-f]" * 8 + "/state.json")):
        try:
            tasks.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            continue
    return tasks


def resolve(value):
    matches = [task for task in all_tasks() if task["id"] == value or task.get("name") == value]
    if len(matches) != 1:
        raise ValueError("task ID or name is missing or ambiguous")
    return matches[0]


@contextlib.contextmanager
def lock(path, blocking=True):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("a+") as file:
        flags = fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB)
        try:
            fcntl.flock(file, flags)
        except BlockingIOError:
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(file, fcntl.LOCK_UN)


def cron_plan(task):
    if task["mode"] == "dynamic":
        return "* * * * *", True
    period = task["interval_seconds"]
    if period % 60 == 0:
        minutes = period // 60
        if minutes < 60 and 60 % minutes == 0:
            return f"*/{minutes} * * * *", False
        if period % 3600 == 0:
            hours = period // 3600
            if hours <= 24 and 24 % hours == 0:
                return ("0 0 * * *" if hours == 24 else f"0 */{hours} * * *"), False
    return "* * * * *", True


def next_boundary(task, current):
    _, tick = cron_plan(task)
    if tick:
        return current + dt.timedelta(seconds=task.get("interval_seconds") or 60)
    period = task["interval_seconds"]
    candidate = current.replace(second=0, microsecond=0) + dt.timedelta(minutes=1)
    for _ in range(1441):
        local = candidate.astimezone()
        if period < 3600 and local.minute % (period // 60) == 0:
            return candidate
        if 3600 <= period < 86400 and local.minute == 0 and local.hour % (period // 3600) == 0:
            return candidate
        if period == 86400 and local.hour == 0 and local.minute == 0:
            return candidate
        candidate += dt.timedelta(minutes=1)
    raise ValueError("cannot determine next cron boundary")


def crontab_read():
    command = shutil.which(CRONTAB) if "/" not in CRONTAB else CRONTAB
    if not command:
        raise ValueError("crontab is unavailable; no loop was scheduled")
    result = subprocess.run([command, "-l"], text=True, capture_output=True, check=False)
    if result.returncode == 0:
        return result.stdout, command
    if "no crontab" in result.stderr.lower():
        return "", command
    raise RuntimeError(f"cannot read crontab: {result.stderr.strip()}")


def crontab_update(task, enabled):
    with lock(STATE / ".cron.lock"):
        old, command = crontab_read()
        task_id = task["id"]
        begin, end = f"# BEGIN skill-loop:{task_id}", f"# END skill-loop:{task_id}"
        pattern = re.compile(r"(?m)^" + re.escape(begin) + r"\n.*?^" + re.escape(end) + r"\n?", re.S)
        new = pattern.sub("", old)
        if enabled:
            schedule, _ = cron_plan(task)
            values = {"HOME": task["home"], "XDG_STATE_HOME": task["xdg_state_home"],
                      "XDG_CONFIG_HOME": task["xdg_config_home"], "PATH": task["path"]}
            environment = " ".join(f"{key}={shlex.quote(value)}" for key, value in values.items())
            invocation = f"/usr/bin/env {environment} {shlex.quote(sys.executable)} {shlex.quote(str(HERE))} tick {task_id}"
            invocation = invocation.replace("%", r"\%")
            block = f"{begin}\n{schedule} {invocation}\n{end}\n"
            if new and not new.endswith("\n"):
                new += "\n"
            new += block
        if new != old:
            result = subprocess.run([command, "-"], input=new, text=True, capture_output=True, check=False)
            if result.returncode:
                raise RuntimeError(f"cannot update crontab: {result.stderr.strip()}")


def git_facts(cwd):
    def git(*args):
        try:
            result = subprocess.run(["git", "-C", cwd, *args], text=True, capture_output=True, timeout=5)
            return result.stdout.strip() if result.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired):
            return None
    return {"repository": git("rev-parse", "--show-toplevel"), "branch": git("branch", "--show-current"),
            "head": git("rev-parse", "HEAD"), "status": (git("status", "--short") or "")[:1000]}


def event(task_id, result, reason):
    path = task_path(task_id) / "runs.log"
    with path.open("a", encoding="utf-8") as file:
        file.write(json.dumps({"at": stamp(now()), "result": result, "reason": reason[:500]}, ensure_ascii=False) + "\n")


def agent_run(task):
    facts = git_facts(task["working_directory"])
    task["repository"] = facts["repository"]
    task["branch"] = facts["branch"]
    task["last_seen_commit"] = facts["head"]
    instruction = {
        "original_request": task["original_prompt"],
        "task_prompt": task["prompt"],
        "project": facts,
        "previous_result": task.get("last_result"),
        "previous_summary": task.get("last_summary", ""),
        "persistent_memory": task.get("memory", ""),
        "stop_when_condition_met": task["wait_until"],
    }
    prompt = ("Perform exactly one bounded iteration of this recurring task. Inspect current state first. "
              "Your authority is limited to the original request and normal agent policies. "
              "Do not repeat old findings or invent work. For a /skill payload, invoke that installed "
              "Skill with its arguments, never as shell. Return only a JSON object with keys result "
              "(changed, no_change, completed, failed, or blocked), summary (brief), memory "
              "(only useful facts for the next run, max 4000 characters), next_interval "
              "(optional interval such as 5m for dynamic tasks), and reason (brief). "
              "Use completed only when an explicit wait-until condition is satisfied.\n\n"
              + json.dumps(instruction, ensure_ascii=False))
    command = agent_command(task["agent"], task["agent_executable"])
    output = task_path(task["id"]) / ".agent-result"
    output.unlink(missing_ok=True)
    if task["agent"] == "codex":
        command += [str(output), "-C", task["working_directory"], "-"]
        stdin = prompt
    else:
        command += [prompt]
        stdin = None
    try:
        process = subprocess.Popen(command, cwd=task["working_directory"], stdin=subprocess.PIPE if stdin else None,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        stdout, stderr = process.communicate(stdin, timeout=task["timeout_seconds"])
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        return {"result": "timeout", "summary": "iteration timed out", "memory": task.get("memory", "")}
    if process.returncode:
        return {"result": "failed", "summary": f"agent exited {process.returncode}: {stderr[-500:]}",
                "memory": task.get("memory", "")}
    raw = output.read_text(encoding="utf-8") if task["agent"] == "codex" and output.exists() else stdout
    try:
        value = json.loads(raw.strip())
        if not isinstance(value, dict) or value.get("result") not in RESULTS:
            raise ValueError("invalid result")
        return value
    except (ValueError, json.JSONDecodeError):
        return {"result": "failed", "summary": "agent returned invalid JSON", "memory": task.get("memory", "")}
    finally:
        output.unlink(missing_ok=True)


def run_task(task_id, scheduled):
    folder = task_path(task_id)
    with lock(folder / "lock", blocking=False) as acquired:
        if not acquired:
            event(task_id, "skipped", "previous_iteration_active")
            return "skipped"
        task = load(task_id)
        if not task["enabled"]:
            return "skipped"
        if scheduled and task["tick"] and now() < parse_time(task["next_run_at"]):
            return "skipped"
        if scheduled and task.get("jitter_seconds"):
            time.sleep(random.uniform(0, task["jitter_seconds"]))
        started = now()
        task["status"] = "running"
        save(task)
        try:
            result = agent_run(task)
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            result = {"result": "failed", "summary": f"runner error: {error}", "memory": task.get("memory", "")}
        outcome = result["result"]
        if outcome == "completed" and not task["wait_until"]:
            outcome = "changed"
        task["last_run_at"] = stamp(started)
        task["run_count"] += 1
        task["last_result"] = outcome
        task["last_summary"] = str(result.get("summary", ""))[:2000]
        task["memory"] = str(result.get("memory", task.get("memory", "")))[:4000]
        task["last_reason"] = str(result.get("reason", ""))[:500]
        if outcome in ("failed", "timeout", "blocked"):
            task["consecutive_failures"] += 1
        else:
            task["consecutive_failures"] = 0
            task["last_success_at"] = stamp(now())
            task["last_processed_commit"] = task.get("last_seen_commit")
        if outcome == "completed":
            task["enabled"] = False
            task["status"] = "completed"
            task["next_run_at"] = None
            save(task)
            crontab_update(task, False)
        else:
            task["status"] = "waiting" if outcome not in ("failed", "blocked", "timeout") else outcome
            if task["mode"] == "dynamic":
                minimum, maximum = task["min_seconds"], task["max_seconds"]
                try:
                    requested = seconds(str(result["next_interval"])) if result.get("next_interval") else 300
                except ValueError:
                    requested = 300
                chosen = min(max(requested, minimum), maximum)
                if outcome == "no_change":
                    chosen = min(maximum, max(chosen, int(task.get("chosen_interval_seconds") or minimum) * 2))
                if outcome in ("failed", "timeout", "blocked"):
                    chosen = min(maximum, max(chosen, minimum * 2 ** min(task["consecutive_failures"], 6)))
                task["chosen_interval_seconds"] = chosen
                task["last_reason"] = task["last_reason"] or ("bounded failure backoff" if outcome in ("failed", "timeout", "blocked") else "adaptive cadence")
                task["next_run_at"] = stamp(now() + dt.timedelta(seconds=chosen))
            else:
                task["next_run_at"] = stamp(next_boundary(task, now()))
        save(task)
        event(task_id, outcome, task["last_summary"])
        return outcome


def create(args):
    cwd = Path.cwd().resolve()
    raw = " ".join(args.text)
    prompt, period, source, note = parse_request(raw, cwd)
    agent = select_agent()
    check_skill(prompt, agent)
    minimum = seconds(os.environ.get("LOOP_MIN_INTERVAL", "1m"))
    maximum = seconds(os.environ.get("LOOP_MAX_INTERVAL", "1h"))
    if minimum < 60 or maximum < minimum:
        raise ValueError("dynamic interval bounds must be at least 1m and ordered")
    for old in all_tasks():
        if old["enabled"] and old["working_directory"] == str(cwd) and old["original_prompt"] == raw:
            raise ValueError(f"matching loop already exists: {old['id']}; edit it instead")
    task_id = secrets.token_hex(4)
    while task_path(task_id).exists():
        task_id = secrets.token_hex(4)
    mode = "fixed" if period else "dynamic"
    task = {"id": task_id, "name": args.name, "mode": mode, "interval_seconds": period,
            "original_prompt": raw, "prompt": prompt, "prompt_source": source, "agent": agent,
            "agent_executable": str(Path(shutil.which(agent)).resolve()),
            "home": str(Path.home()), "xdg_state_home": str(STATE.parents[1]),
            "xdg_config_home": os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")),
            "path": os.environ.get("PATH", "/usr/bin:/bin"),
            "enabled": True, "status": "waiting", "created_at": stamp(now()),
            "last_run_at": None, "last_success_at": None, "next_run_at": None,
            "run_count": 0, "consecutive_failures": 0, "last_result": None,
            "last_summary": "", "memory": "", "working_directory": str(cwd),
            "wait_until": bool(re.search(r"\b(until|até|ate)\b", prompt, re.I)),
            "min_seconds": minimum, "max_seconds": maximum,
            "timeout_seconds": seconds(args.timeout), "jitter_seconds": seconds(args.jitter) if args.jitter else 0}
    if task["jitter_seconds"] > 59:
        raise ValueError("jitter must be shorter than 1m")
    _, task["tick"] = cron_plan(task)
    task["next_run_at"] = stamp(now() if mode == "dynamic" else next_boundary(task, now()))
    task_path(task_id).mkdir(parents=True, mode=0o700)
    crontab_update(task, True)
    save(task)
    print(f"Loop created\nID: {task_id}\nSchedule: {mode} {label(period) if period else f'{label(minimum)}–{label(maximum)}'}"
          f"\nPrompt: {prompt[:160]}\nFirst run: {'now' if args.now else 'next scheduled tick'}"
          f"\nNext scheduled run: {task['next_run_at']}")
    if note:
        print(note)
    if args.now:
        print(f"First result: {run_task(task_id, False)}")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    make = sub.add_parser("create")
    make.add_argument("--now", action="store_true")
    make.add_argument("--name")
    make.add_argument("--timeout", default="30m")
    make.add_argument("--jitter", help="optional 1–59s start delay for scheduled runs")
    make.add_argument("text", nargs="*")
    sub.add_parser("list")
    for action in ("status", "run", "tick", "pause", "resume", "cancel", "edit"):
        command = sub.add_parser(action)
        command.add_argument("id")
        if action == "edit":
            command.add_argument("--interval")
            command.add_argument("--prompt")
            command.add_argument("--name")
    args = parser.parse_args()
    try:
        if args.action == "create":
            create(args)
        elif args.action == "list":
            for task in all_tasks():
                schedule = label(task["interval_seconds"]) if task["mode"] == "fixed" else "dynamic"
                print(f"{task['id']}  {schedule:8}  {task['status']:10}  {task['prompt'][:80]}")
        elif args.action == "status":
            print(json.dumps(resolve(args.id), indent=2, ensure_ascii=False))
        elif args.action in ("run", "tick"):
            task = resolve(args.id) if args.action == "run" else load(args.id)
            print(run_task(task["id"], args.action == "tick"))
        else:
            task = resolve(args.id)
            with lock(task_path(task["id"]) / "lock", blocking=False) as acquired:
                if not acquired:
                    raise ValueError("task is currently running; retry after this iteration")
                if args.action == "edit":
                    if args.interval:
                        task["interval_seconds"] = max(60, seconds(args.interval))
                        task["mode"] = "fixed"
                    if args.prompt is not None:
                        check_skill(args.prompt, task["agent"])
                        task["prompt"] = args.prompt
                        task["original_prompt"] = args.prompt
                        task["wait_until"] = bool(re.search(r"\b(until|até|ate)\b", args.prompt, re.I))
                    if args.name is not None:
                        task["name"] = args.name
                    if not any((args.interval, args.prompt is not None, args.name is not None)):
                        raise ValueError("edit requires --interval, --prompt, or --name")
                    task["tick"] = cron_plan(task)[1]
                    task["next_run_at"] = stamp(next_boundary(task, now()))
                elif args.action == "pause":
                    task["enabled"], task["status"] = False, "paused"
                elif args.action == "resume":
                    task["enabled"], task["status"] = True, "waiting"
                    task["next_run_at"] = stamp(now() if task["mode"] == "dynamic" else next_boundary(task, now()))
                elif args.action == "cancel":
                    task["enabled"], task["status"] = False, "cancelled"
                crontab_update(task, task["enabled"])
                save(task)
                print(f"{task['id']}: {task['status']} (next: {task['next_run_at']})")
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"loop: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
