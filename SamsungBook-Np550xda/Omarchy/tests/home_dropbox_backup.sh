#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
test_home="$fixture/home"
mkdir -p "$test_home/.config/home-dropbox-backup" "$test_home/.config/chromium/Default/Sessions" \
  "$test_home/Dropbox" "$test_home/Documents"
cp "$repo/home/.config/home-dropbox-backup/excludes" "$test_home/.config/home-dropbox-backup/excludes"
script="$repo/home/.local/bin/home-dropbox-backup"
cloud="$test_home/.local/state/home-dropbox-backup/archives/home"
cloud_zip="$test_home/Dropbox/Backups/SamsungBook-Np550xda/Omarchy/latest.zip"
backup="$test_home/.local/state/home-dropbox-backup"
export HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
  XDG_STATE_HOME="$test_home/.local/state" HOME_BACKUP_MIN_FREE_GIB=0

printf 'first\n' >"$test_home/Documents/note.txt"
printf 'old\n' >"$test_home/Documents/deleted.txt"
printf 'inside Dropbox\n' >"$test_home/Dropbox/original.txt"
printf 'saved bookmark\n' >"$test_home/.config/chromium/Default/Bookmarks"
printf 'live history\n' >"$test_home/.config/chromium/Default/History"
printf 'live preferences\n' >"$test_home/.config/chromium/Default/Preferences"
printf 'live session\n' >"$test_home/.config/chromium/Default/Sessions/Session_1"
bash "$script" --dry-run >/dev/null
[[ ! -e "$backup/current/Documents/note.txt" ]]
bash "$script" >/dev/null
[[ $(cat "$backup/current/Documents/note.txt") == first ]]
[[ ! -e "$backup/current/Dropbox" ]]
[[ -f "$backup/current/.config/chromium/Default/Bookmarks" ]]
[[ ! -e "$backup/current/.config/chromium/Default/History" ]]
[[ ! -e "$backup/current/.config/chromium/Default/Preferences" ]]
[[ ! -e "$backup/current/.config/chromium/Default/Sessions" ]]

# Files from an older backup remain on disk but must stay excluded on restore.
printf 'stale history\n' >"$backup/current/.config/chromium/Default/History"

printf 'second\n' >"$test_home/Documents/note.txt"
rm "$test_home/Documents/deleted.txt"
bash "$script" >/dev/null
[[ $(cat "$backup/current/Documents/note.txt") == second ]]
[[ ! -e "$backup/current/Documents/deleted.txt" ]]
[[ $(find "$backup/history" -name '*note.txt*' | wc -l) -ge 1 ]]
[[ $(find "$backup/history" -name '*deleted.txt*' | wc -l) -ge 1 ]]

# Local staging edits must never flow back into HOME.
printf 'staging only\n' >"$backup/current/Documents/cloud.txt"
bash "$script" >/dev/null
[[ ! -e "$test_home/Documents/cloud.txt" ]]
printf 'local edit\n' >"$test_home/Documents/note.txt"
printf 'staging edit\n' >"$backup/current/Documents/note.txt"
bash "$script" >/dev/null
[[ $(cat "$test_home/Documents/note.txt") == 'local edit' ]]
[[ $(cat "$backup/current/Documents/note.txt") == 'local edit' ]]

restore_target="$fixture/restored"
mkdir "$restore_target"
bash "$script" --restore --target "$restore_target" >/dev/null
[[ ! -e "$restore_target/Documents/note.txt" ]]
bash "$script" --restore --apply --target "$restore_target" >/dev/null
[[ $(cat "$restore_target/Documents/note.txt") == 'local edit' ]]
[[ ! -e "$restore_target/.config/chromium/Default/History" ]]

# A restore into an existing home must not replace a newer local edit.
printf 'newer local edit\n' >"$restore_target/Documents/note.txt"
touch -d '2030-01-01 UTC' "$restore_target/Documents/note.txt"
bash "$script" --restore --apply --target "$restore_target" >/dev/null
[[ $(cat "$restore_target/Documents/note.txt") == 'newer local edit' ]]

# An older local copy can still be brought up to date from the backup.
touch -d '2000-01-01 UTC' "$restore_target/Documents/note.txt"
bash "$script" --restore --apply --target "$restore_target" >/dev/null
[[ $(cat "$restore_target/Documents/note.txt") == 'local edit' ]]

# Commit stays in WAL while the writer is open; the staged database must include it.
python3 - "$script" "$backup/current" <<'PYTEST'
import os, pathlib, sqlite3, subprocess, sys
home = pathlib.Path(os.environ['HOME'])
for name in ('build', 'dist', 'target'):
    (home / 'Documents' / name).mkdir()
    (home / 'Documents' / name / 'keep.txt').write_text('personal data')
with sqlite3.connect(home / 'Documents/live.db') as live:
    live.execute('PRAGMA journal_mode=WAL')
    live.execute('PRAGMA wal_autocheckpoint=0')
    live.execute('CREATE TABLE items(value)')
    live.commit()
    live.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    live.execute("INSERT INTO items VALUES ('committed')")
    live.commit()
    subprocess.run(['bash', sys.argv[1]], check=True, stdout=subprocess.DEVNULL)
    staged = pathlib.Path(sys.argv[2]) / 'Documents/live.db'
    with sqlite3.connect(staged) as saved:
        assert saved.execute('SELECT value FROM items').fetchall() == [('committed',)]
    assert not pathlib.Path(str(staged) + '-wal').exists()
for name in ('build', 'dist', 'target'):
    assert (pathlib.Path(sys.argv[2]) / 'Documents' / name / 'keep.txt').exists()
PYTEST

monthly="$repo/home/.local/bin/home-dropbox-monthly"
# Previously uploaded full archives must be saved locally before cloud publication.
python3 - "$test_home/Dropbox/Backups/SamsungBook-Np550xda/Omarchy" <<'PYTEST'
import pathlib, sys, zipfile
for kind in ('home', 'btrfs'):
    old = pathlib.Path(sys.argv[1]) / kind / '2024/2024-01-01.zip'
    old.parent.mkdir(parents=True)
    with zipfile.ZipFile(old, 'w') as archive:
        archive.writestr('old-version', kind)
PYTEST
touch "$XDG_STATE_HOME/home-dropbox-backup/last-partial"
if HOME_BACKUP_MONTH=2026-10 bash "$monthly" >/dev/null 2>&1; then
  echo 'Monthly archive accepted a partial home synchronization' >&2
  exit 1
fi
[[ ! -e "$cloud/2026/2026-10-01.zip" ]]
rm "$XDG_STATE_HOME/home-dropbox-backup/last-partial"
cp "$backup/last-success" "$fixture/success.json"
printf '{"format":2,"synced_at":"2000-01-01T00:00:00+00:00"}\n' >"$backup/last-success"
if HOME_BACKUP_MONTH=2026-10 bash "$monthly" >/dev/null 2>&1; then
  echo 'Monthly archive accepted a stale synchronization' >&2; exit 1
fi
cp "$fixture/success.json" "$backup/last-success"
HOME_BACKUP_MONTH=2026-10 bash "$monthly" >/dev/null
python3 - "$cloud/2026/2026-10-01.zip" "$backup/last-success" <<'PYTEST'
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert json.loads(archive.comment)['synced_at'] == json.load(open(sys.argv[2]))['synced_at']
PYTEST
[[ -f "$cloud/2026/2026-10-01.zip" && -f "$cloud_zip" ]]
[[ $(find "$test_home/Dropbox/Backups" -type f | wc -l) == 1 ]]
[[ -f "$backup/archives/btrfs/2024/2024-01-01.zip" ]]
cp "$cloud_zip" "$fixture/previous-cloud.zip"
if HOME_BACKUP_DROPBOX_BUDGET_BYTES=1 HOME_BACKUP_MONTH=2026-10 bash "$monthly" >/dev/null 2>&1; then
  echo 'Cloud publication ignored the total budget' >&2; exit 1
fi
cmp "$cloud_zip" "$fixture/previous-cloud.zip"
# Re-running in the same month must refresh the cloud copy, not make more ZIPs.
printf 'same month update\n' >"$backup/current/Documents/note.txt"
HOME_BACKUP_MONTH=2026-10 bash "$monthly" >/dev/null
[[ $(unzip -p "$cloud_zip" Documents/note.txt) == 'same month update' ]]
printf 'next month\n' >"$backup/current/Documents/note.txt"
HOME_BACKUP_MONTH=2026-11 bash "$monthly" >/dev/null
monthly_restore="$fixture/monthly-restored"
mkdir "$monthly_restore"
unzip -q "$cloud/2026/2026-11-01.zip" -d "$monthly_restore"
[[ $(cat "$monthly_restore/Documents/note.txt") == 'next month' ]]
HOME_BACKUP_MONTH=2027-01 bash "$monthly" >/dev/null
[[ -f "$cloud/history.zip" && ! -e "$cloud/2026" ]]
[[ -f "$cloud/2027/2027-01-01.zip" ]]
unzip -tq "$cloud/history.zip" >/dev/null
[[ $(find "$cloud" -type f ! -name '*.zip' | wc -l) == 0 ]]

mkdir "$fixture/bin"
# A database normalization failure must leave publication blocked and preserve
# the previous success record, even if Unison itself completed successfully.
cp "$backup/last-success" "$fixture/previous-success"
python3 - "$test_home/Documents/broken.db" <<'PYTEST'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(b'SQLite format 3\0' + b'invalid' * 100)
PYTEST
bash "$script" >/dev/null 2>&1 || true
[[ -f "$backup/last-partial" ]]
cmp "$backup/last-success" "$fixture/previous-success"
if HOME_BACKUP_MONTH=2027-02 bash "$monthly" >/dev/null 2>&1; then
  echo 'Monthly archive accepted a failed SQLite copy' >&2; exit 1
fi
printf '#!/bin/sh\nexit 2\n' >"$fixture/bin/unison"
chmod +x "$fixture/bin/unison"
PATH="$fixture/bin:$PATH" bash "$script" >/dev/null 2>&1
[[ -f "$XDG_STATE_HOME/home-dropbox-backup/last-partial" ]]
echo 'home Dropbox backup fixture passed'
