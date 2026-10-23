#!/usr/bin/env python3
"""Exercise Btrfs export publication and retry in a disposable directory."""

from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess


source = Path(__file__).resolve().parents[1] / "scripts/btrfs-monthly-backup"
with TemporaryDirectory() as directory:
    root = Path(directory)
    home = root / "home"
    (home / "Dropbox").mkdir(parents=True)
    state = root / "state"
    script = root / "btrfs-monthly-backup"
    code = source.read_text()
    changes = {
        "[[ $EUID == 0 && $# == 1 ]]": "[[ $# == 1 ]]",
        "[[ $home == /home/* && $(findmnt -n -o FSTYPE -T /) == btrfs ]]": "[[ -d $home ]]",
        "month=$(date +%Y-%m)": "month=2026-10",
        "state=/var/lib/home-dropbox-backup": f"state={state}",
        'runuser -u "$owner" -- ': "",
        'btrfs subvolume snapshot -r / "$snapshot"': 'mkdir -p "$snapshot"',
        'btrfs send "${parent[@]}" "$snapshot"': "printf 'snapshot payload\\n'",
        'source_kib=$(du -skx --exclude=/.snapshots --exclude=/var/lib/home-dropbox-backup / | awk \'{ print $1 }\')': "source_kib=0",
        "(( available_kib >= source_kib + 10 * 1024 * 1024 ))": "(( available_kib >= source_kib ))",
        'btrfs subvolume delete -- "$old"': 'rmdir -- "$old"',
    }
    for old, new in changes.items():
        assert old in code, f"Fixture no longer matches production script: {old}"
        code = code.replace(old, new)
    script.write_text(code)

    def run():
        return subprocess.run(["bash", str(script), str(home)], capture_output=True, text=True, check=True)

    destination = home / "Dropbox/Backups/SamsungBook-Np550xda/Omarchy/home/monthly/btrfs"
    archive = destination / "2026-10.send.zst"
    checksum = destination / "2026-10.sha256"
    metadata = destination / "2026-10.meta"

    assert "Created full Btrfs send archive" in run().stdout
    assert archive.is_file() and checksum.is_file() and metadata.is_file()
    (state / "latest").unlink()
    assert "already verified" in run().stdout
    assert (state / "latest").read_text().strip() == "2026-10"

    # A crash before checksum publication must cause a retry, not a false success.
    checksum.unlink()
    retried = run()
    assert "retrying 2026-10" in retried.stderr
    assert archive.is_file() and checksum.is_file() and metadata.is_file()
    quarantines = list(destination.glob(".incomplete-2026-10.*"))
    assert len(quarantines) == 1
    assert (quarantines[0] / archive.name).is_file()

    # A damaged archive with a checksum is also preserved and regenerated.
    archive.write_bytes(b"damaged")
    assert "retrying 2026-10" in run().stderr
    assert len(list(destination.glob(".incomplete-2026-10.*"))) == 2
    subprocess.run(["sha256sum", "-c", checksum.name], cwd=destination, check=True, capture_output=True)

    metadata.write_text("format=btrfs-send\nkind=invalid\nparent=none\nsubvolume=/\n")
    assert "retrying 2026-10" in run().stderr
    assert len(list(destination.glob(".incomplete-2026-10.*"))) == 3

print("OK: Btrfs export validation, quarantine and retry")
