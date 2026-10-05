"""Compare configuration hashes without storing file contents or inventing history."""
import hashlib
import json
from pathlib import Path
from .store import now


def hashes(directory):
    directory = Path(directory)
    found = {}
    for path in sorted(directory.rglob('*')):
        if path.is_file() and not path.is_symlink() and path.stat().st_size <= 1024*1024:
            found[str(path.relative_to(directory))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return found


def compare(store, config, stock=Path('/usr/share/omarchy/config')):
    # Only paths supplied by installed Omarchy templates, not all personal files.
    official = hashes(stock)
    current = {}
    for relative in official:
        path = Path(config)/relative
        if path.is_file() and path.stat().st_size <= 1024*1024:
            current[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        else:
            current[relative] = None
    baseline_path = store.directory/'baseline.json'
    first = not baseline_path.exists()
    if first:
        baseline_path.write_text(json.dumps({'captured_at': now(), 'hashes': current}))
    baseline = json.loads(baseline_path.read_text())
    return dict(captured_at=baseline['captured_at'], original_installation='unknown',
        scope='Installed Omarchy config templates only. A template difference is not necessarily a problem.',
        differs_from_templates=[p for p,h in current.items() if h != official[p]],
        changed_since_observation=[p for p,h in current.items() if p in baseline['hashes'] and h != baseline['hashes'][p]],
        newly_observed_template_paths=[p for p in current if p not in baseline['hashes']],
        missing=[p for p,h in current.items() if h is None])
