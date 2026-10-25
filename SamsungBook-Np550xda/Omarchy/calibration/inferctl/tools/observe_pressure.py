#!/usr/bin/env python3
"""Bounded, read-only observation of ambient host memory/swap pressure.

Does not send inference requests or attribute host counters to any model.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import time


def counters(path):
    result = {}
    for line in Path(path).read_text().splitlines():
        fields = line.replace(":", " ").split()
        if len(fields) >= 2:
            try:
                result[fields[0]] = int(fields[1])
            except ValueError:
                continue
    return result


def swap_devices():
    devices = []
    for line in Path("/proc/swaps").read_text().splitlines()[1:]:
        fields = line.split()
        if len(fields) != 5:
            continue
        name = Path(fields[0]).name
        zram = name.startswith("zram") and name[4:].isdigit()
        device = {"path": fields[0], "type": fields[1],
                  "size_bytes": int(fields[2])*1024, "used_bytes": int(fields[3])*1024,
                  "priority": int(fields[4]), "compressed_ram": zram}
        if zram:
            try:
                mm = list(map(int, Path(f"/sys/block/{name}/mm_stat").read_text().split()))
                device.update(logical_data_bytes=mm[0], compressed_data_bytes=mm[1],
                              physical_memory_bytes=mm[2])
            except (OSError, ValueError, IndexError):
                pass
        devices.append(device)
    return devices


def snapshot():
    vm = counters("/proc/vmstat")
    mem = counters("/proc/meminfo")
    pressure = {}
    for resource in ("memory", "io", "cpu"):
        try:
            for line in Path(f"/proc/pressure/{resource}").read_text().splitlines():
                fields = line.split()
                pressure[resource+"."+fields[0]] = {
                    k: int(v) if k == "total" else float(v)
                    for k, v in (field.split("=", 1) for field in fields[1:])}
        except OSError:
            pass
    return {"at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "monotonic": time.monotonic(), "swap_in_pages": vm["pswpin"],
            "swap_out_pages": vm["pswpout"], "ram_available_bytes": mem["MemAvailable"]*1024,
            "swap_used_bytes": (mem["SwapTotal"]-mem["SwapFree"])*1024,
            "psi": pressure, "swap_devices": swap_devices()}


def summarize(samples, page_size):
    first, last = samples[0], samples[-1]
    seconds = last["monotonic"]-first["monotonic"]
    deltas = []
    for a, b in zip(samples, samples[1:]):
        incoming = b["swap_in_pages"]-a["swap_in_pages"]
        outgoing = b["swap_out_pages"]-a["swap_out_pages"]
        if incoming < 0 or outgoing < 0:
            raise ValueError("swap counters regressed")
        dt = b["monotonic"]-a["monotonic"]
        if dt <= 0:
            raise ValueError("nonpositive sampling interval")
        deltas.append((incoming*page_size/dt, outgoing*page_size/dt))
    result = {"seconds": seconds, "swap_in_bytes": (last["swap_in_pages"]-first["swap_in_pages"])*page_size,
              "swap_out_bytes": (last["swap_out_pages"]-first["swap_out_pages"])*page_size,
              "swap_growth_peak_bytes": max(0, max(s["swap_used_bytes"] for s in samples)-first["swap_used_bytes"]),
              "minimum_available_ram_bytes": min(s["ram_available_bytes"] for s in samples),
              "swap_in_peak_bytes_per_second": max((x[0] for x in deltas), default=0),
              "swap_out_peak_bytes_per_second": max((x[1] for x in deltas), default=0)}
    result["swap_io_bytes"] = result["swap_in_bytes"]+result["swap_out_bytes"]
    if "memory.full" in first["psi"] and "memory.full" in last["psi"] and seconds > 0:
        stalled = last["psi"]["memory.full"]["total"]-first["psi"]["memory.full"]["total"]
        if stalled < 0:
            raise ValueError("PSI counter regressed")
        result["memory_full_stall_percent"] = stalled/(seconds*1e6)*100
    return result


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix+".tmp")
    with temp.open("w") as handle:
        os.chmod(temp, 0o600)
        json.dump(value, handle, indent=2, allow_nan=False)
        handle.write("\n")
    temp.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration", type=float, default=120)
    parser.add_argument("--interval", type=float, default=1)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.duration <= 600 or not .1 <= args.interval <= args.duration:
        parser.error("duration must be 1..600s; interval must be .1s..duration")
    samples = [snapshot()]
    result = {"version": 1, "status": "running", "kind": "ambient_observation",
              "scope": "host counters visible to this process; no workload attribution",
              "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
              "page_size": os.sysconf("SC_PAGE_SIZE"), "samples": samples}
    write(args.output, result)
    print(f"Observing ambient pressure for {args.duration:g}s; output: {args.output}", flush=True)
    deadline = time.monotonic()+args.duration
    try:
        while time.monotonic() < deadline:
            time.sleep(min(args.interval, max(0, deadline-time.monotonic())))
            samples.append(snapshot())
        result["summary"] = summarize(samples, result["page_size"])
        result["status"] = "completed"
    except BaseException as exc:
        result["status"] = "failed"
        result["error"] = str(exc) or type(exc).__name__
        write(args.output, result)
        raise
    write(args.output, result)
    print(json.dumps(result["summary"], indent=2), flush=True)


if __name__ == "__main__":
    main()
