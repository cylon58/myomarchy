"""Use Snapper for snapshots and retention. Never implement filesystem rollback."""
import csv
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def command(argv, *, privileged=False):
    if privileged and os.geteuid() != 0:
        argv = (['sudo'] if sys.stdin.isatty() else ['pkexec']) + argv
    result = subprocess.run(argv, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout or 'Command failed')[:2000])
    return result.stdout.strip()


def configs(directory=Path('/etc/snapper/configs')):
    found = {}
    for path in sorted(directory.glob('*')):
        if not re.fullmatch(r'[A-Za-z0-9_-]+', path.name) or not path.is_file():
            continue
        data = {}
        for line in path.read_text().splitlines():
            m = re.match(r'([A-Z_]+)="([^"]*)"', line)
            if m:
                data[m[1]] = m[2]
        found[path.name] = data
    return found


def coverage():
    available = configs()
    covered = {v.get('SUBVOLUME') for v in available.values() if v.get('FSTYPE') == 'btrfs'}
    missing = [p for p in ['/', '/home'] if p not in covered]
    return dict(ready=not missing, missing=missing, configs=available,
        explanation='Root and home snapshots exclude nested subvolumes, other mounts, firmware and external services. Readiness is configuration only; creation must succeed before a change.')


class Recovery:
    def __init__(self, run=command):
        self.run = run

    def snap(self, *args):
        return self.run(['/usr/bin/snapper', *args], privileged=True)

    def prepare(self, record_id, paths, on_snapshot):
        available = configs()
        selected = {}
        for target in ['/', '/home']:
            names = [k for k,v in available.items() if v.get('SUBVOLUME') == target and v.get('FSTYPE') == 'btrfs']
            if len(names) != 1:
                raise RuntimeError(f'Exactly one Btrfs Snapper configuration for {target} is required. Run myomarchy recovery setup.')
            selected[target] = names[0]
        def filesystem_id(path):
            return (self.run(['/usr/bin/findmnt', '-n', '-o', 'UUID', '-T', str(path)]),
                    self.run(['/usr/bin/btrfs', 'inspect-internal', 'rootid', str(path)]))
        source_ids = {filesystem_id(p) for p in selected}
        if not paths:
            raise ValueError('Declare affected paths with --path before creating recovery points')
        for path in paths:
            current = Path(path).expanduser().resolve()
            while not current.exists() and current != current.parent:
                current = current.parent
            if filesystem_id(current) not in source_ids:
                raise RuntimeError(f'{path} is outside root/home snapshot coverage. Change was not started.')
        for target, name in selected.items():
            free = shutil.disk_usage(target).free
            if free < 2*1024**3:
                self.snap('-c', name, 'cleanup', 'number')
                if shutil.disk_usage(target).free < 2*1024**3:
                    raise RuntimeError('Less than 2 GiB free after Snapper cleanup. Change was not started.')
            number = self.snap('-c', name, 'create', '--read-only', '--print-number',
                '--cleanup-algorithm', 'number', '--description', 'My Omarchy '+record_id,
                '--userdata', 'myomarchy='+record_id)
            if not number.isdigit() or int(number) == 0:
                raise RuntimeError('Snapper did not return a valid snapshot number')
            # Persist each immediately so partial creation or a crash stays visible.
            on_snapshot(dict(config=name, number=int(number), subvolume=target))
            self.snap('-c', name, 'cleanup', 'number')

    def setup(self, count=None, space=None):
        if count is not None and not 2 <= count <= 1000:
            raise ValueError('Keep between 2 and 1000 snapshots per configuration')
        if space is not None and not .01 <= space <= .5:
            raise ValueError('Space allowance must be between 0.01 and 0.5 of the filesystem')
        available = configs()
        for target, default in [('/', 'root'), ('/home', 'myomarchy-home')]:
            names = [k for k,v in available.items() if v.get('SUBVOLUME') == target]
            if len(names) > 1:
                raise ValueError('Multiple configurations cover '+target)
            name = names[0] if names else default
            if names and available[name].get('FSTYPE') != 'btrfs':
                raise ValueError('Btrfs configuration required for '+target)
            if not names:
                if name in available:
                    raise ValueError('Configuration name already used: '+name)
                self.snap('-c', name, 'create-config', target)
                # Snapper defaults to 0640; readiness reads these non-secret
                # policy files as the desktop user. Never change existing modes.
                self.run(['/usr/bin/chmod', '644',
                          '/etc/snapper/configs/'+name], privileged=True)
            options = []
            if not names or count is not None:
                keep = count if count is not None else 5
                options = ['NUMBER_CLEANUP=yes', 'NUMBER_MIN_AGE=0',
                           f'NUMBER_LIMIT={keep}', f'NUMBER_LIMIT_IMPORTANT={keep}']
                if not names:
                    options += ['TIMELINE_CREATE=no']
            if space is not None:
                self.snap('-c', name, 'setup-quota')
                options += [f'SPACE_LIMIT={space}', 'FREE_LIMIT=0.05']
            if options:
                self.snap('-c', name, 'set-config', *options)
        return coverage()

    def list(self):
        result = []
        for name, conf in configs().items():
            raw = self.snap('--csvout', '-c', name, 'list', '--columns', 'number,date,description')
            for row in csv.DictReader(io.StringIO(raw)):
                result.append(dict(config=name, subvolume=conf.get('SUBVOLUME'), **row))
        return result
