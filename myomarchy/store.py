"""Durable records and append-only events; imported claims remain attributed."""
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
from datetime import datetime, timezone
import uuid


def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def state_dir():
    return Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'myomarchy'


def clean(text):
    # A best-effort guard, not a guarantee: never ingest transcripts or command output.
    text = re.sub(r'(?i)(password|token|secret|api[_-]?key)(\s*[=:]\s*)[^\s,;]+', r'\1\2[redacted]', str(text))
    return re.sub(r'(?i)(https?://)[^\s/@]+:[^\s/@]+@', r'\1[redacted]@', text)[:100000]


def sanitized(value):
    if isinstance(value, dict):
        return {k: sanitized(v) for k,v in value.items()}
    if isinstance(value, list):
        return [sanitized(v) for v in value]
    return clean(value) if isinstance(value, str) else value


class Store:
    def __init__(self, directory=None):
        directory = Path(directory or state_dir())
        if directory.is_symlink():
            raise ValueError('State directory must not be a symlink')
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.directory = directory
        path = directory/'history.sqlite3'
        if path.is_symlink():
            raise ValueError('History database must not be a symlink')
        self.db = sqlite3.connect(path, timeout=15)
        os.chmod(path, 0o600)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
          PRAGMA journal_mode=WAL;
          PRAGMA synchronous=FULL;
          CREATE TABLE IF NOT EXISTS records (
            id TEXT PRIMARY KEY, category TEXT NOT NULL, title TEXT NOT NULL,
            date TEXT, date_kind TEXT NOT NULL, status TEXT NOT NULL,
            origin TEXT NOT NULL, details TEXT NOT NULL, identity TEXT UNIQUE,
            observed_at TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS events (
            seq INTEGER PRIMARY KEY, record_id TEXT NOT NULL,
            at TEXT NOT NULL, kind TEXT NOT NULL, details TEXT NOT NULL);
          CREATE INDEX IF NOT EXISTS event_record ON events(record_id);
        ''')

    def add(self, title, category='fixes', *, date=None, date_kind='recorded',
            status='unfinished', origin='managed', details='', identity=None):
        if category not in {'plugins', 'fixes', 'customizations', 'activity'}:
            raise ValueError('Unknown category')
        if identity:
            row = self.db.execute('SELECT id FROM records WHERE identity=?', (identity,)).fetchone()
            if row:
                return row['id']
        rid = str(uuid.uuid4())
        with self.db:
            self.db.execute('INSERT INTO records VALUES (?,?,?,?,?,?,?,?,?,?)',
                (rid, category, clean(title)[:240], date, date_kind, status, origin,
                 clean(details), identity, now()))
            self.db.execute('INSERT INTO events(record_id,at,kind,details) VALUES (?,?,?,?)',
                (rid, now(), 'created', json.dumps({'origin': origin})))
        return rid

    def event(self, rid, kind, details, status=None):
        self.get(rid)
        with self.db:
            self.db.execute('INSERT INTO events(record_id,at,kind,details) VALUES (?,?,?,?)',
                (rid, now(), kind, json.dumps(sanitized(details), ensure_ascii=False)))
            if status:
                self.db.execute('UPDATE records SET status=? WHERE id=?', (status, rid))

    def get(self, rid):
        row = self.db.execute('SELECT * FROM records WHERE id=?', (rid,)).fetchone()
        if not row:
            raise ValueError('Unknown record')
        value = dict(row)
        value['events'] = [dict(r) for r in self.db.execute(
            'SELECT at,kind,details FROM events WHERE record_id=? ORDER BY seq', (rid,))]
        return value

    def list(self, query='', limit=500):
        return [dict(r) for r in self.db.execute('''SELECT id,category,title,date,date_kind,
            status,origin,observed_at FROM records
            WHERE instr(lower(title || ' ' || details), lower(?)) > 0
            ORDER BY coalesce(date,observed_at) DESC, id LIMIT ?''', (query, limit))]

    def import_journal(self, path):
        path = Path(path)
        if path.stat().st_size > 8*1024*1024:
            raise ValueError('Journal exceeds 8 MiB import limit')
        text = path.read_text()
        sections = re.split(r'^##\s+', text, flags=re.M)[1:]
        ids = []
        for section in sections:
            heading, _, body = section.partition('\n')
            match = re.match(r'(\d{4}-\d{2}-\d{2})\s*[-—:]\s*(.*)', heading)
            date, title = (match.group(1), match.group(2)) if match else (None, heading)
            category = 'fixes' if re.search(r'fix|repair|recover|crash|fail', title, re.I) else 'customizations'
            if re.search(r'firmware|driver|package update|system update', title, re.I):
                category = 'activity'
            identity = 'journal:' + hashlib.sha256((str(path.resolve())+'\n'+heading+'\n'+body).encode()).hexdigest()
            ids.append(self.add(title, category, date=date, date_kind='recorded',
                status='reconstructed', origin='journal',
                details=f'Source: {path}\nHistorical claim; current state and rollback unverified.\n\n{body.strip()}',
                identity=identity))
        return ids

    def inventory(self, plugins_dir):
        directory = Path(plugins_dir)
        if not directory.is_dir():
            raise ValueError('Plugin directory unavailable; presence is unknown')
        seen = set()
        for path in sorted(directory.glob('*/manifest.json')):
            try:
                if path.stat().st_size > 65536:
                    continue
                value = json.loads(path.read_text())
                pid = value['id']
                if not isinstance(pid, str) or not pid:
                    continue
                identity = 'plugin:' + pid
                seen.add(identity)
                details = json.dumps(dict(plugin_id=pid, path=str(path.parent),
                    version=value.get('version'), author=value.get('author')), ensure_ascii=False)
                rid = self.add(value.get('name', pid), 'plugins', date_kind='unknown',
                    status='present', origin='discovered', details=details, identity=identity)
                old = self.get(rid)
                if old['status'] != 'present' or old['details'] != details:
                    self.event(rid, 'inventory', {'previous': old['details'], 'observed': details}, 'present')
                with self.db:
                    self.db.execute('UPDATE records SET details=?,observed_at=? WHERE id=?', (details, now(), rid))
            except (ValueError, KeyError, OSError):
                # Do not infer removal from a malformed manifest.
                seen.add('invalid:' + str(path.parent))
        for row in self.db.execute("SELECT id,identity,details FROM records WHERE origin='discovered' AND category='plugins'").fetchall():
            data = json.loads(row['details'])
            if row['identity'] not in seen and not Path(data['path']).exists():
                if self.get(row['id'])['status'] != 'removed':
                    self.event(row['id'], 'inventory', {'observation': 'directory no longer present'}, 'removed')

    def import_packages(self, path):
        path = Path(path)
        # The last 4 MiB is enough for a pilot activity window, with deterministic deduplication.
        with path.open('rb') as stream:
            size = stream.seek(0, 2)
            stream.seek(max(0, size-4*1024*1024))
            if size > 4*1024*1024:
                stream.readline()
            lines = stream.read().decode(errors='replace').splitlines()
        for line in lines:
            m = re.match(r'^\[([^]]+)\] \[ALPM\] (installed|upgraded|removed|downgraded) (.+)$', line)
            if m:
                self.add(m[2]+' '+m[3], 'activity', date=m[1], date_kind='logged',
                    status='logged', origin='pacman', details='Source: pacman ALPM log',
                    identity='pacman:'+hashlib.sha256(line.encode()).hexdigest())
