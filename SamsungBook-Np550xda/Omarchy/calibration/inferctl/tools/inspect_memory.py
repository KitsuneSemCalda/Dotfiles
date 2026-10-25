#!/usr/bin/env python3
"""Read-only census of the current user's process memory and LM Studio inventory.

No process arguments/environments, model loads, process termination or config edits.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import time

from homologate import endpoint
from observe_pressure import counters, snapshot, write


def start_time(directory):
    tail = (directory / "stat").read_text().rsplit(")", 1)[1].split()
    return int(tail[19])


def process_memory(directory, uid):
    before = start_time(directory)
    status = counters(directory / "status")
    if status.get("Uid") != uid:
        return None
    record = {"pid": int(directory.name), "ppid": status["PPid"],
              "name": (directory / "comm").read_text(errors="replace").strip(),
              "start_time_ticks": before,
              "rss_bytes": status.get("VmRSS", 0)*1024,
              "vm_swap_logical_bytes": status.get("VmSwap", 0)*1024}
    try:
        rollup = counters(directory / "smaps_rollup")
        for source, target in [("Pss", "pss_bytes"), ("SwapPss", "swap_pss_logical_bytes"),
                               ("Pss_Anon", "pss_anon_bytes"), ("Pss_File", "pss_file_bytes"),
                               ("Pss_Shmem", "pss_shmem_bytes")]:
            if source in rollup:
                record[target] = rollup[source]*1024
        if "Pss" not in rollup:
            record["pss_error"] = "Pss counter unavailable"
    except (OSError, ValueError) as exc:
        record["pss_error"] = type(exc).__name__
    if start_time(directory) != before:
        return None  # PID recycled during collection; do not mix two processes.
    return record


def by_name(processes):
    groups = {}
    for process in processes:
        name = process["name"]
        group = groups.setdefault(name, {"name": name, "processes": 0, "pss_available_processes": 0,
                                         "known_pss_bytes": 0, "known_swap_pss_logical_bytes": 0})
        group["processes"] += 1
        if "pss_bytes" in process:
            group["pss_available_processes"] += 1
            group["known_pss_bytes"] += process["pss_bytes"]
        group["known_swap_pss_logical_bytes"] += process.get("swap_pss_logical_bytes", 0)
    return sorted(groups.values(), key=lambda x: x["known_pss_bytes"], reverse=True)


def model_inventory(url):
    result = endpoint(url.rstrip("/")+"/api/v1/models")
    if not result["reachable"]:
        return result
    models = []
    for model in result["data"].get("models", []):
        row = {key: model[key] for key in ("key", "type", "publisher", "quantization", "size_bytes") if key in model}
        row["loaded_instances"] = []
        for instance in model.get("loaded_instances", []):
            config = instance.get("config", {})
            row["loaded_instances"].append({"id": instance.get("id"), "config": {
                key: config[key] for key in ("context_length", "parallel", "eval_batch_size", "physical_batch_size") if key in config}})
        models.append(row)
    return {"reachable": True, "models": models}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--url", default="http://127.0.0.1:1234")
    parser.add_argument("--max-seconds", type=float, default=15)
    args = parser.parse_args()
    if not 1 <= args.max_seconds <= 60:
        parser.error("max-seconds must be 1..60")
    started = time.monotonic()
    initial = snapshot()
    processes, skipped = [], 0
    truncated = False
    directories = sorted((p for p in Path("/proc").iterdir() if p.name.isdigit()), key=lambda p: int(p.name))
    for count, directory in enumerate(directories):
        if count >= 4096 or time.monotonic()-started > args.max_seconds:
            truncated = True
            break
        try:
            record = process_memory(directory, os.getuid())
            if record is not None:
                processes.append(record)
        except (OSError, ValueError, IndexError, KeyError):
            skipped += 1
    report = {"version": 1, "at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "scope": "visible processes of current UID; non-atomic census, not model peak memory",
              "uid": os.getuid(), "hostname": os.uname().nodename,
              "truncated": truncated, "skipped_or_exited_processes": skipped,
              "pss_unavailable_processes": sum("pss_bytes" not in p for p in processes),
              "known_user_pss_bytes": sum(p.get("pss_bytes", 0) for p in processes),
              "by_process_name": by_name(processes),
              "processes": sorted(processes, key=lambda p: p.get("pss_bytes", -1), reverse=True),
              "host_before": initial, "host_after": snapshot(),
              "lmstudio": model_inventory(args.url),
              "notes": ["Groups are exact process names, not application ownership trees.",
                        "Missing PSS is unknown, not zero usage.",
                        "Do not add logical SwapPss to physical ZRAM memory as if both were RAM.",
                        "No process was killed and no model was loaded or unloaded."]}
    report["collection_seconds"] = time.monotonic()-started
    write(args.output, report)
    print(f"Saved: {args.output}; processes={len(processes)}; PSS unavailable={report['pss_unavailable_processes']}; truncated={truncated}")
    for group in report["by_process_name"][:12]:
        coverage = f"{group['pss_available_processes']}/{group['processes']}"
        print(f"{group['name']}: known PSS {group['known_pss_bytes']/2**20:.1f} MiB; coverage {coverage}")


if __name__ == "__main__":
    main()
