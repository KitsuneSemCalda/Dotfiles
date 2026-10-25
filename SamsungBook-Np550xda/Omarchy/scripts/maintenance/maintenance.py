#!/usr/bin/env python3
"""Local, bounded maintenance. No shell evaluation or network service required."""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time

GIB = 1024 ** 3
ROOT_HELPER = '/usr/local/libexec/dotfiles-maintenance-root'
PHASES = ('prune', 'temporary', 'trim', 'snapshot', 'keyring', 'system', 'migrations', 'hooks', 'aur', 'mise', 'flatpak-system', 'flatpak-user')


def command(args, timeout=30):
    try:
        # Builds can emit large logs. Keep memory bounded and retain the tail.
        with tempfile.TemporaryFile() as log:
            result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=timeout)
            size = log.seek(0, os.SEEK_END)
            log.seek(max(0, size - 24000))
            return result.returncode, log.read().decode('utf-8', errors='replace')
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, str(exc)


def week(now):
    return (now.date() - dt.timedelta(days=(now.weekday() + 1) % 7)).isoformat()


def eligible(now, ac, idle):
    return 3 <= now.hour < 6 and ac is True and idle is not None and idle >= 900


def shell_idle_seconds(status, now):
    """Conservative lower bound from the shell's current idle cycle and last event."""
    if status.get('enabled') is not True or status.get('stayAwake') is not False:
        return None
    if status.get('idle') is False:
        return 0
    if status.get('idle') is not True:
        return None
    try:
        timeouts = [float(status[name]) for name in ('screensaver', 'lock') if float(status[name]) > 0]
        event = dt.datetime.fromisoformat(status['lastEventAt'].replace('Z', '+00:00'))
        if not timeouts or event.tzinfo is None or event > now:
            return None
        # All shell events during the current idle cycle happen after the first
        # idle timeout. Later lock/process events only under-estimate idle time.
        return min(timeouts) + max(0, (now - event).total_seconds())
    except (KeyError, ValueError, TypeError):
        return None


def conditions():
    code, text = command(['busctl', 'get-property', 'org.freedesktop.UPower',
                          '/org/freedesktop/UPower', 'org.freedesktop.UPower', 'OnBattery'])
    ac = None if code or text.strip() not in ('b true', 'b false') else text.strip() == 'b false'
    code, session = command(['loginctl', 'show-session', os.environ.get('XDG_SESSION_ID', 'self'),
                             '-p', 'IdleHint', '-p', 'IdleSinceHintMonotonic'])
    fields = dict(line.split('=', 1) for line in session.splitlines() if '=' in line)
    idle = None
    if not code and fields.get('IdleHint') == 'yes':
        try:
            since = int(fields.get('IdleSinceHintMonotonic', '0')) / 1e6
            if since > 0:
                idle = max(0, time.clock_gettime(time.CLOCK_MONOTONIC) - since)
        except ValueError:
            pass
    if idle is None:
        # systemd --user managers are not members of a login session. The
        # Omarchy shell exposes the compositor's idle monitor over its own IPC.
        code, output = command(['omarchy', 'shell', 'idle', 'status'])
        if not code:
            try:
                idle = shell_idle_seconds(json.loads(output), dt.datetime.now(dt.timezone.utc))
            except (ValueError, TypeError):
                pass
    return ac, idle


def cleanup(root, now=None):
    """Only old regular files, on this device, reached through real directories."""
    now = time.time() if now is None else now
    if not root.is_dir() or root.resolve() != root.absolute():
        return 0
    device = root.stat().st_dev
    removed = 0
    for directory, dirs, files, directory_fd in os.fwalk(root, follow_symlinks=False):
        if os.fstat(directory_fd).st_dev != device:
            dirs[:] = []
            continue
        for name in files:
            try:
                info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                if (stat.S_ISREG(info.st_mode) and info.st_dev == device
                        and max(info.st_mtime, info.st_atime, info.st_ctime) < now - 7 * 86400):
                    os.unlink(name, dir_fd=directory_fd)
                    removed += info.st_size
            except OSError:
                continue
    return removed


def atomic(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def analyze():
    report = {'time': dt.datetime.now().astimezone().isoformat(), 'volumes': {}, 'checks': {}, 'warnings': []}
    for mount in ('/', str(Path.home())):
        total, used, free = shutil.disk_usage(mount)
        report['volumes'][mount] = {'total': total, 'free': free}
        if free < 10 * GIB or free / total < .15:
            report['warnings'].append('Low disk space: ' + mount)
    memory = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    available = int(memory['MemAvailable'].split()[0])
    total = int(memory['MemTotal'].split()[0])
    report['memory_available_percent'] = round(available * 100 / total, 1)
    if available / total < .1:
        report['warnings'].append('Memory pressure: less than 10% available')
    checks = {
        'failed_system_units': ['systemctl', '--failed', '--no-legend', '--no-pager'],
        'failed_user_units': ['systemctl', '--user', '--failed', '--no-legend', '--no-pager'],
        'recent_errors': ['journalctl', '-p', 'err', '--since', '24 hours ago', '-n', '30', '--no-pager'],
        'top_processes': ['ps', '-eo', 'comm,pcpu,pmem', '--sort=-pcpu'],
        'battery': ['upower', '-d'],
        'updates': ['checkupdates'],
        'orphan_packages': ['pacman', '-Qtdq'],
        'backups': ['systemctl', '--user', 'show', 'home-dropbox-backup.service',
                    'home-dropbox-monthly.service', '-p', 'Id', '-p', 'Result', '-p', 'ExecMainExitTimestamp'],
        'root_backup': ['systemctl', 'show', 'home-btrfs-monthly.service', '-p', 'Result', '-p', 'ExecMainExitTimestamp'],
        'storage_health': ['lsblk', '-o', 'NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS'],
        'smart_health': ['sudo', '-n', ROOT_HELPER, 'health'],
    }
    for name, args in checks.items():
        code, output = command(args, 90 if name == 'updates' else 30)
        if name == 'top_processes':
            output = '\n'.join(output.splitlines()[:11])
        report['checks'][name] = {'code': code, 'output': output}
        if name.startswith('failed_') and not code and output.strip():
            report['warnings'].append(name)
        if name in ('backups', 'root_backup') and any(
                line.startswith('Result=') and line != 'Result=success' for line in output.splitlines()):
            report['warnings'].append(name + ' failed')
        if name == 'smart_health' and code:
            report['warnings'].append('Storage health check failed or unavailable; review report')
    report['storage_note'] = 'SMART health is best effort; an unavailable check is not proof of healthy storage.'
    return report


def save_report(state, report):
    if 'actions' in report:
        atomic(state / 'last-maintenance.json', report)
    elif (state / 'last-maintenance.json').exists():
        previous = json.loads((state / 'last-maintenance.json').read_text())
        report['previous_maintenance'] = previous['time']
        report['actions'] = previous.get('actions', {})
    reports = state / 'reports'
    reports.mkdir(exist_ok=True)
    path = reports / (dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.json')
    atomic(path, report)
    atomic(state / 'latest.json', report)
    lines = [report['time'], *report.get('warnings', [])]
    metrics = report.get('after', report)
    if 'memory_available_percent' in metrics:
        lines.append(f"Memory available: {metrics['memory_available_percent']}%")
    for name, volume in metrics.get('volumes', {}).items():
        lines.append(f"Volume {name}: {volume['free']/GIB:.1f} GiB free of {volume['total']/GIB:.1f} GiB")
    for name, result in report.get('actions', {}).items():
        lines.append(f"{name}: {result['status']} {result.get('detail', '')}")
    if 'checks' in report:
        lines.extend(f"{name}: {check['output']}" for name, check in report['checks'].items())
    path.with_suffix('.txt').write_text('\n'.join(lines) + '\n')
    (state / 'latest.txt').write_text('\n'.join(lines) + '\n')
    for old in reports.iterdir():
        if old.is_file() and old.stat().st_mtime < time.time() - 90 * 86400:
            old.unlink()
    issues = sorted(report.get('warnings', []) + [name + ':' + item['status'] for name, item in report.get('actions', {}).items()
                                                if item['status'] in ('failed', 'pending')])
    marker = state / 'last-notification.json'
    previous = json.loads(marker.read_text()) if marker.exists() else []
    if issues != previous:
        command(['notify-send', 'Dotfiles maintenance', '\n'.join(issues) if issues else 'Previous maintenance issues resolved'])
        atomic(marker, issues)


def power(state, restore=False):
    previous_path = state / 'power.json'
    base = Path(os.environ.get('OMARCHY_POWERPROFILES_STATE_DIR', str(
        Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'omarchy/powerprofiles')))
    if restore:
        if not previous_path.exists():
            return
        for name, info in json.loads(previous_path.read_text()).items():
            path = base / name
            if path.exists() and path.read_text().strip() == info['installed']:
                if info['previous'] is None:
                    path.unlink()
                else:
                    path.write_text(info['previous'])
        command(['omarchy', 'powerprofiles', 'set', 'autodetect'])
        previous_path.unlink()
        (state / 'power-applied').unlink(missing_ok=True)
        return
    if previous_path.exists():
        previous = json.loads(previous_path.read_text())
        if (state / 'power-applied').exists():
            return
    else:
        previous = {}
        for name, profile in (('battery', 'power-saver'), ('ac', 'balanced')):
            path = base / name
            previous[name] = {'previous': path.read_text() if path.exists() else None, 'installed': profile}
        # Save before applying, including on a partially failed setup.
        atomic(previous_path, previous)
    ac, _ = conditions()
    if ac is None:
        raise RuntimeError('Cannot determine AC power; power setup deferred')
    # The Omarchy command applies immediately: configure inactive supply first.
    order = ('battery', 'ac') if ac is True else ('ac', 'battery')
    for name in order:
        code, output = command(['omarchy', 'powerprofiles', 'set', name, previous[name]['installed']])
        if code:
            raise RuntimeError(output)
    (state / 'power-applied').touch()


def perform(name):
    if name in ('prune', 'snapshot', 'keyring', 'system', 'trim', 'temporary', 'flatpak-system'):
        if name == 'flatpak-system' and not shutil.which('flatpak'):
            return 0, 'Flatpak not installed; not applicable'
        code, output = command(['sudo', '-n', ROOT_HELPER, name], timeout=None)
        if name == 'temporary' and code == 0:
            output += f"\nThumbnail cache: removed {cleanup(Path.home() / '.cache/thumbnails')} bytes"
        return code, output
    args = {
        'migrations': ['omarchy', 'migrate'], 'hooks': ['omarchy', 'hook', 'post-update'],
        'aur': ['/usr/bin/bash', '-e', '/usr/share/omarchy/bin/omarchy-update-aur-pkgs'],
        'mise': ['/usr/bin/bash', '-e', '/usr/share/omarchy/bin/omarchy-update-mise'],
        'flatpak-user': ['flatpak', 'update', '--user', '--noninteractive', '-y'],
    }
    if name in ('flatpak-user', 'aur', 'mise'):
        tool = {'flatpak-user': 'flatpak', 'aur': 'yay', 'mise': 'mise'}[name]
        if not shutil.which(tool):
            return 0, 'Not installed; not applicable'
        if name == 'aur':
            code, output = command(['pacman', '-Qem'])
            if code == 1 and not output.strip():
                return 0, 'No AUR packages installed'
            if code:
                return code, output
            code, output = command(['omarchy', 'pkg', 'aur', 'accessible'])
            if code:
                return code, 'AUR unavailable; retry next maintenance window\n' + output
    return command(['systemd-inhibit', '--what=sleep', '--mode=block', '--who=DotfilesMaintenance',
                    '--why=Package transaction', *args[name]], timeout=None)


def main():
    os.environ['OMARCHY_PATH'] = '/usr/share/omarchy'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['analyze', 'run', 'simulate', 'status', 'enable', 'disable'])
    parser.add_argument('--scheduled', action='store_true')
    args = parser.parse_args()
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'dotfiles-maintenance'
    if args.mode == 'status':
        path = state / 'latest.txt'
        print(path.read_text() if path.exists() else 'No reports yet')
        return 0
    if args.mode == 'simulate':
        ac, idle = conditions()
        print(json.dumps({'ac': ac, 'idle_seconds': idle, 'eligible': eligible(dt.datetime.now(), ac, idle),
                          'phases': PHASES, 'updates': 'system, AUR, mise, Flatpak; never reboot'}, indent=2))
        return 0
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.mode == 'disable':
        (state / 'disabled').touch()
        code, output = command(['systemctl', '--user', 'disable', '--now', 'dotfiles-maintenance.timer'])
        power(state, restore=True)
        print(output)
        return code
    with (state / 'lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        if args.mode == 'enable':
            power(state)
            (state / 'disabled').unlink(missing_ok=True)
            code, output = command(['systemctl', '--user', 'enable', '--now', 'dotfiles-maintenance.timer'])
            print(output)
            return code
        progress_path = state / 'progress.json'
        if args.mode == 'run' and (state / 'disabled').exists():
            return 0
        progress = json.loads(progress_path.read_text()) if progress_path.exists() else {}
        now = dt.datetime.now()
        if args.mode == 'analyze':
            save_report(state, analyze())
            return 0
        if progress.get('diagnosed') != now.date().isoformat():
            save_report(state, analyze())
            progress['diagnosed'] = now.date().isoformat()
            atomic(progress_path, progress)
        if progress.get('week') != week(now):
            progress.update(week=week(now), done=[])
        if set(PHASES).issubset(progress.get('done', [])):
            return 0
        ac, idle = conditions()
        if not eligible(now, ac, idle):
            if not args.scheduled:
                print('Deferred: requires 03:00–06:00, AC power and 15 minutes idle')
            return 0
        # Share Omarchy's lock with manual updates. Children inherit its descriptor.
        runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp'))
        with (runtime / 'omarchy-update.lock').open('a') as update_lock:
            try:
                fcntl.flock(update_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return 0
            os.environ['OMARCHY_UPDATE_UNATTENDED'] = '1'
            os.environ['OMARCHY_PATH'] = '/usr/share/omarchy'
            os.environ['SUDO_ASKPASS'] = '/usr/bin/false'
            os.environ['PATH'] = '/usr/local/libexec/dotfiles-maintenance-bin:' + os.environ.get('PATH', '/usr/bin')
            report = {'time': now.astimezone().isoformat(), 'before': analyze(), 'actions': {}, 'warnings': []}
            for name in PHASES:
                if name in progress.get('done', []):
                    continue
                ac, idle = conditions()
                if (state / 'disabled').exists() or not eligible(dt.datetime.now(), ac, idle):
                    report['actions'][name] = {'status': 'pending', 'detail': 'Outside maintenance conditions'}
                    break
                if name in ('snapshot', 'keyring', 'system', 'aur', 'mise', 'flatpak-system', 'flatpak-user') and shutil.disk_usage('/').free < 10 * GIB:
                    report['actions'][name] = {'status': 'pending', 'detail': 'Less than 10 GiB free'}
                    break
                code, output = perform(name)
                report['actions'][name] = {'status': 'ok' if code == 0 else 'failed', 'code': code, 'detail': output}
                if code:
                    if name in ('prune', 'temporary', 'trim'):
                        continue
                    break
                progress.setdefault('done', []).append(name)
                atomic(progress_path, progress)
            report['after'] = analyze()
            report['warnings'] += report['after']['warnings']
            if list(Path('/usr/lib/modules').glob('*/vmlinuz')) and not (Path('/usr/lib/modules') / os.uname().release / 'vmlinuz').exists():
                report['warnings'].append('Kernel update: reboot pending')
            if list((Path.home() / '.local/state/omarchy').glob('*required')):
                report['warnings'].append('Omarchy component restart pending')
            save_report(state, report)
            return int(any(item['status'] == 'failed' for item in report['actions'].values()))


if __name__ == '__main__':
    raise SystemExit(main())
