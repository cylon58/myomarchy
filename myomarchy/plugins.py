"""Inspect trusted GitHub origins and guard the installed Omarchy updater."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import signal
import subprocess

from .store import now

SELF = 'io.github.cylon58.myomarchy'


def git(path, *args):
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GIT_OPTIONAL_LOCKS='0')
    result = subprocess.run(['git', '-C', str(path), *args], capture_output=True,
                            text=True, timeout=20, env=env, check=True)
    return result.stdout.strip()


def repository(remote):
    match = re.fullmatch(r'(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?', remote)
    if not match or any(part in {'.', '..'} for part in match.groups()):
        return None
    return 'https://github.com/' + '/'.join(match.groups())


def inspect(path):
    path = Path(path)
    try:
        # Do not mistake a parent repository for a plugin checkout.
        if not (path/'.git').exists() or Path(git(path, 'rev-parse', '--show-toplevel')).resolve() != path.resolve():
            return {}
        origin = git(path, 'remote', 'get-url', 'origin')
        return dict(repository=repository(origin), origin=origin,
                    commit=git(path, 'rev-parse', 'HEAD'),
                    dirty=bool(git(path, 'status', '--porcelain', '--untracked-files=all')))
    except (OSError, subprocess.SubprocessError):
        return {}


def checks(store):
    path = store.directory/'plugin-checks.json'
    if path.is_symlink():
        raise ValueError('Invalid update cache')
    return json.loads(path.read_text()) if path.exists() else {}


def save_checks(store, value):
    path = store.directory/'plugin-checks.json'
    if path.is_symlink():
        raise ValueError('Invalid update cache')
    # Store directory is private; replace instead of following an existing link.
    temporary = store.directory/'plugin-checks.tmp'
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def metadata(store, row, cache=None):
    if row['category'] != 'plugins' or row['origin'] != 'discovered':
        return row
    detail = json.loads(store.get(row['id'])['details'])
    info = inspect(detail['path']) if row['status'] == 'present' else {}
    cached = (checks(store) if cache is None else cache).get(detail['plugin_id'], {})
    valid_cache = cached.get('origin') == info.get('origin') and cached.get('commit') == info.get('commit')
    status = 'Not checked'
    if not info.get('repository'):
        status = 'No supported GitHub origin'
    elif info.get('dirty'):
        status = 'Local changes — update blocked'
    elif valid_cache:
        status = cached.get('status', status)
    try:
        target(store, row['id'])
        eligible = True
        reason = ''
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        eligible = False
        reason = str(exc)
    return dict(row, repository=info.get('repository'), plugin_id=detail['plugin_id'],
                update_status=status, checked_at=cached.get('checked_at') if valid_cache else None,
                can_update=eligible, update_blocked_reason=reason)


def check_updates(store, rid=None):
    cache = checks(store)
    rows = [store.get(rid)] if rid else store.list(limit=5000)
    for row in rows:
        if row['category'] != 'plugins' or row['origin'] != 'discovered' or row['status'] != 'present':
            continue
        detail = json.loads(store.get(row['id'])['details'])
        info = inspect(detail['path'])
        if not info.get('repository'):
            continue
        entry = dict(origin=info['origin'], commit=info['commit'], checked_at=now())
        try:
            output = git(detail['path'], 'ls-remote', '--exit-code', info['repository'] + '.git', 'HEAD')
            remote = output.split()[0]
            if not re.fullmatch(r'[0-9a-f]{40,64}', remote):
                raise ValueError('Invalid remote revision')
            entry.update(remote_commit=remote, status='Up to date' if remote == info['commit'] else 'Remote changes available')
        except (OSError, ValueError, subprocess.SubprocessError):
            entry['status'] = 'Update check failed'
        cache[detail['plugin_id']] = entry
    save_checks(store, cache)


def target(store, rid):
    row = store.get(rid)
    if row['category'] != 'plugins' or row['origin'] != 'discovered' or row['status'] != 'present':
        raise ValueError('Select an installed plugin')
    detail = json.loads(row['details'])
    pid = detail['plugin_id']
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', pid) or '..' in pid:
        raise ValueError('Invalid plugin ID')
    path = Path.home()/'.config/omarchy/plugins'/pid
    if str(path) != detail['path'] or path.resolve() != path or not (path/'.git').is_dir():
        raise ValueError('Updater requires a standard, unsymlinked installed Git checkout')
    manifest = json.loads((path/'manifest.json').read_text())
    info = inspect(path)
    if manifest.get('id') != pid or not info.get('repository'):
        raise ValueError('Plugin must have a matching manifest and a GitHub origin')
    if info['dirty']:
        raise ValueError('Local changes must be reviewed before updating')
    # Use a safe HTTPS origin; other Git remote helpers must not run in the updater.
    if info['origin'] != info['repository'] and info['origin'] != info['repository'] + '.git':
        raise ValueError('Updater requires an HTTPS GitHub origin')
    return dict(id=pid, path=str(path), before=info['commit'], record=rid)


def run_updater(pid, timeout=180):
    command = ['omarchy', 'plugin', 'update', pid, '--yes']
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except BaseException:
        # Kill the group, including any Git/validator descendants, before releasing the lock.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        raise


def update_worker(store, rid, record_ids, recovery, lock):
    try:
        with lock(store):
            targets = []
            skipped = []
            for record in record_ids:
                try:
                    targets.append(target(store, record))
                except (ValueError, OSError, subprocess.SubprocessError) as exc:
                    skipped.append(dict(record=record, plugin_id=json.loads(store.get(record)['details']).get('plugin_id', record), reason=str(exc)))
            if not targets:
                raise ValueError('No eligible clean GitHub plugins to update')
            targets.sort(key=lambda t: t['id'] == SELF)
            recovery.prepare(rid, [t['path'] for t in targets], lambda snap: store.event(rid, 'snapshot', snap))
            store.event(rid, 'started', {}, 'running')
            failed = bool(skipped)
            for item in targets:
                # Recheck after snapshots in case a user edited the checkout.
                try:
                    current = target(store, item['record'])
                    if current['before'] != item['before']:
                        raise ValueError('Plugin changed while preparing recovery')
                    code = run_updater(item['id'])
                    after = inspect(item['path']).get('commit')
                    success = code == 0 and after is not None
                    failed |= not success
                    store.event(rid, 'plugin-update', dict(plugin_id=item['id'], before=item['before'], after=after, success=success))
                except subprocess.TimeoutExpired:
                    failed = True
                    store.event(rid, 'plugin-update-failed', dict(plugin_id=item['id'], reason='Updater timed out; its process group was terminated. Remaining updates stopped.'))
                    break
                except (ValueError, OSError, subprocess.SubprocessError) as exc:
                    failed = True
                    store.event(rid, 'plugin-update-failed', dict(plugin_id=item['id'], reason=str(exc)))
            store.inventory(Path.home()/'.config/omarchy/plugins')
            store.event(rid, 'finished', dict(summary='Updates finished; inspect per-plugin outcomes.', skipped=skipped), 'failed' if failed else 'completed')
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as exc:
        store.event(rid, 'finished', dict(summary=str(exc)), 'failed')
    finally:
        store.db.close()


def active_updates(store, rows):
    active = False
    for row in rows:
        if row['origin'] != 'managed' or row['status'] not in {'queued', 'running'}:
            continue
        record = store.get(row['id'])
        if record['status'] not in {'queued', 'running'}:
            continue
        launched = [json.loads(e['details']) for e in record['events'] if e['kind'] == 'worker-launched']
        alive = False
        if launched:
            worker = launched[-1]
            try:
                stat = Path('/proc')/str(worker['pid'])/'stat'
                fields = stat.read_text().rsplit(')', 1)[1].split()
                alive = fields[0] != 'Z' and fields[19] == worker['start_time']
            except (OSError, KeyError, IndexError):
                pass
        elif (datetime.now(timezone.utc) - datetime.fromisoformat(row['observed_at'])).total_seconds() < 60:
            alive = True  # Allow the launcher to write its receipt.
        if alive:
            active = True
        else:
            with store.db:
                changed = store.db.execute("UPDATE records SET status='unfinished' WHERE id=? AND status IN ('queued','running')", (row['id'],)).rowcount
                if changed:
                    store.db.execute('INSERT INTO events(record_id,at,kind,details) VALUES (?,?,?,?)',
                                     (row['id'], now(), 'finished', json.dumps(dict(summary='Update helper stopped before completion; inspect current plugins before retrying.'))))
    return active
