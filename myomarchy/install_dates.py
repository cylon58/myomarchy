"""Recover dated local evidence without treating discovery or mtime as installation."""
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess


def birth_time(path):
    try:
        # Linux Python does not expose statx birth time; GNU stat does. Do not follow links.
        value = int(subprocess.check_output(['stat', '-c', '%W', '--', str(path)], text=True, stderr=subprocess.DEVNULL, timeout=3).strip())
        return value if value > 0 else None
    except (ValueError, OSError, subprocess.SubprocessError):
        return None


def clone_time(path):
    directory = Path(path)/'.git'
    if not directory.is_dir() or directory.is_symlink():
        return None
    log = directory/'logs/HEAD'
    if log.is_symlink():
        return None
    try:
        with log.open() as stream:
            first = stream.readline(8192)
        # Never retain the identity, email or origin in a reflog line.
        match = re.fullmatch(r'0{40,64} [0-9a-f]{40,64} .* ([0-9]{9,12}) [+-][0-9]{4}\tclone: from [^\n]+\n?', first)
        return int(match[1]) if match else None
    except (OSError, ValueError):
        return None


def evidence(path, first_observed):
    observed = datetime.fromisoformat(first_observed).timestamp()
    created = birth_time(path)
    cloned = clone_time(path)
    # A later re-clone/update is not evidence of the original installation.
    if created and cloned and 0 < cloned <= observed and abs(cloned-created) <= 600:
        timestamp, kind, source = cloned, 'inferred-install', 'Git clone log corroborated by plugin-location creation (installation estimate)'
    elif created and 0 < created <= observed:
        timestamp, kind, source = created, 'location-created', 'Filesystem birth time of the current plugin location (not a confirmed installation)'
    else:
        return dict(date=first_observed, date_kind='first-seen', source='First local inventory observation')
    try:
        date = datetime.fromtimestamp(timestamp, timezone.utc).isoformat(timespec='seconds')
        return dict(date=date, date_kind=kind, source=source)
    except (ValueError, OverflowError, OSError):
        return dict(date=first_observed, date_kind='first-seen', source='First local inventory observation')
