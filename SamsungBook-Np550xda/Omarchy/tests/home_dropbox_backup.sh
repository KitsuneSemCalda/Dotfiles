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
backup="$test_home/Dropbox/Backups/SamsungBook-Np550xda/Omarchy/home"
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

printf 'from Dropbox\n' >"$backup/current/Documents/cloud.txt"
bash "$script" >/dev/null
[[ $(cat "$test_home/Documents/cloud.txt") == 'from Dropbox' ]]
printf 'local edit\n' >"$test_home/Documents/note.txt"
printf 'cloud edit\n' >"$backup/current/Documents/note.txt"
if bash "$script" >/dev/null 2>&1; then
  echo 'Conflicting edits were silently accepted' >&2
  exit 1
fi
[[ $(cat "$test_home/Documents/note.txt") == 'local edit' ]]
[[ $(cat "$backup/current/Documents/note.txt") == 'cloud edit' ]]
HOME_BACKUP_SEED_HOME=1 bash "$script" >/dev/null
[[ $(cat "$backup/current/Documents/note.txt") == 'local edit' ]]
rm "$backup/current/Documents/cloud.txt"
if bash "$script" >/dev/null 2>&1; then
  echo 'Cloud deletion unexpectedly removed a home file' >&2
  exit 1
fi
[[ -f "$test_home/Documents/cloud.txt" ]]
cp "$test_home/Documents/cloud.txt" "$backup/current/Documents/cloud.txt"
bash "$script" >/dev/null
[[ -f "$backup/current/Documents/cloud.txt" ]]

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

monthly="$repo/home/.local/bin/home-dropbox-monthly"
touch "$XDG_STATE_HOME/home-dropbox-backup/last-partial"
if HOME_BACKUP_MONTH=2026-10 bash "$monthly" >/dev/null 2>&1; then
  echo 'Monthly archive accepted a partial home synchronization' >&2
  exit 1
fi
[[ ! -e "$backup/monthly/home/2026-10.tar.zst" ]]
rm "$XDG_STATE_HOME/home-dropbox-backup/last-partial"
HOME_BACKUP_MONTH=2026-10 bash "$monthly" >/dev/null
[[ -f "$backup/monthly/home/2026-10.tar.zst" ]]
[[ $(cat "$backup/monthly/home/2026-10.meta") == *'kind=full'* ]]
printf 'next month\n' >"$backup/current/Documents/note.txt"
HOME_BACKUP_MONTH=2026-11 bash "$monthly" >/dev/null
[[ $(cat "$backup/monthly/home/2026-11.meta") == *'parent=2026-10'* ]]
monthly_restore="$fixture/monthly-restored"
mkdir "$monthly_restore"
for month in 2026-10 2026-11; do
  zstd -dc -- "$backup/monthly/home/$month.tar.zst" \
    | tar -xG -C "$monthly_restore" -f -
done
[[ $(cat "$monthly_restore/Documents/note.txt") == 'next month' ]]

mkdir "$fixture/bin"
printf '#!/bin/sh\nexit 2\n' >"$fixture/bin/unison"
chmod +x "$fixture/bin/unison"
PATH="$fixture/bin:$PATH" bash "$script" >/dev/null 2>&1
[[ -f "$XDG_STATE_HOME/home-dropbox-backup/last-partial" ]]
echo 'home Dropbox backup fixture passed'
