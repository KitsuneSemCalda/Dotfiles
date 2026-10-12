#!/usr/bin/env python3
"""Sample host load during an OBS scenario; enter OBS Stats in the CSV later."""
import argparse
import csv
import datetime as dt
import pathlib
import subprocess
import time


def read(path):
    try:
        return pathlib.Path(path).read_text().strip()
    except OSError:
        return ''


def command(*args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return ''


def memory():
    info = {}
    for line in read('/proc/meminfo').splitlines():
        key, _, value = line.partition(':')
        if key in ('MemTotal', 'MemAvailable'):
            info[key] = int(value.strip().split()[0])
    return round((info.get('MemTotal', 0) - info.get('MemAvailable', 0)) / 1024)


parser = argparse.ArgumentParser()
parser.add_argument('scenario')
parser.add_argument('--seconds', type=int, default=600)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
args.output.parent.mkdir(parents=True, exist_ok=True)

fields = ['timestamp', 'scenario', 'cpu_load_1m', 'ram_used_mib',
          'cpu_temp_millic', 'cpu_freq_khz', 'obs_rss_kib',
          'render_lag_pct', 'encode_lag_pct', 'dropped_frames_pct', 'notes']
with args.output.open('w', newline='') as file:
    writer = csv.DictWriter(file, fieldnames=fields)
    writer.writeheader()
    for _ in range(args.seconds):
        obs = command('pgrep', '-n', 'obs')
        status = read(f'/proc/{obs}/status') if obs else ''
        rss = next((line.split()[1] for line in status.splitlines()
                    if line.startswith('VmRSS:')), '')
        load = read('/proc/loadavg').split()
        writer.writerow({
            'timestamp': dt.datetime.now(dt.timezone.utc).isoformat(),
            'scenario': args.scenario,
            'cpu_load_1m': load[0] if load else '',
            'ram_used_mib': memory(),
            'cpu_temp_millic': read('/sys/class/thermal/thermal_zone0/temp'),
            'cpu_freq_khz': read('/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq'),
            'obs_rss_kib': rss,
        })
        file.flush()
        time.sleep(1)
