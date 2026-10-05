import contextlib
import io
import os
import sys
import time
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch, Mock

from myomarchy import plugins
from myomarchy.cli import agent_prompt, main
from myomarchy.store import Store


class PluginUpdatesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.store = Store(self.home/'state')
        self.addCleanup(self.store.db.close)
        self.patch = patch('pathlib.Path.home', return_value=self.home)
        self.patch.start(); self.addCleanup(self.patch.stop)

    def checkout(self, pid='trial', remote='https://github.com/example/trial.git'):
        path = self.home/'.config/omarchy/plugins'/pid
        path.mkdir(parents=True)
        subprocess.run(['git', 'init', '-q', str(path)], check=True)
        for key, value in [('user.name', 'Test'), ('user.email', 'test@example.invalid')]:
            subprocess.run(['git', '-C', str(path), 'config', key, value], check=True)
        (path/'manifest.json').write_text(json.dumps({'id': pid, 'name': pid}))
        subprocess.run(['git', '-C', str(path), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(path), 'commit', '-qm', 'fixture'], check=True)
        subprocess.run(['git', '-C', str(path), 'remote', 'add', 'origin', remote], check=True)
        self.store.inventory(path.parent)
        rid = next(r['id'] for r in self.store.list() if r['title'] == pid)
        return path, rid

    def test_repository_links_reject_credentials_and_other_hosts(self):
        self.assertEqual(plugins.repository('git@github.com:example/trial.git'), 'https://github.com/example/trial')
        for remote in ['https://token@github.com/example/trial', 'ext::sh evil', '/tmp/repo', 'https://github.com.evil/example/trial', 'https://github.com/a/../b']:
            self.assertIsNone(plugins.repository(remote))

    def test_clean_target_is_exact_installed_checkout(self):
        path, rid = self.checkout()
        self.assertEqual(plugins.target(self.store, rid)['path'], str(path))
        (path/'untracked').write_text('personal edits')
        with self.assertRaisesRegex(ValueError, 'Local changes'):
            plugins.target(self.store, rid)

    def test_symlink_and_alternate_paths_are_blocked(self):
        path, rid = self.checkout()
        outside = self.home/'outside'; path.rename(outside); path.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'unsymlinked'):
            plugins.target(self.store, rid)
        path.unlink(); outside.rename(path)
        detail = json.loads(self.store.get(rid)['details']); detail['path'] = str(outside)
        with self.store.db:
            self.store.db.execute('UPDATE records SET details=? WHERE id=?', (json.dumps(detail), rid))
        with self.assertRaisesRegex(ValueError, 'standard'):
            plugins.target(self.store, rid)

    def test_missing_or_unsafe_origins_cannot_update(self):
        path, rid = self.checkout(remote='ext::sh evil')
        with self.assertRaisesRegex(ValueError, 'GitHub origin'):
            plugins.target(self.store, rid)
        subprocess.run(['git', '-C', str(path), 'remote', 'remove', 'origin'], check=True)
        self.assertFalse(plugins.metadata(self.store, self.store.get(rid))['can_update'])

    def test_remote_check_different_same_failed_and_invalidated(self):
        path, rid = self.checkout()
        actual_git = plugins.git
        revision = actual_git(path, 'rev-parse', 'HEAD')
        def checked(remote):
            def fake_git(directory, *args):
                return remote if args[0] == 'ls-remote' else actual_git(directory, *args)
            with patch('myomarchy.plugins.git', side_effect=fake_git):
                plugins.check_updates(self.store, rid)
            return plugins.metadata(self.store, self.store.get(rid))
        self.assertEqual(checked('a'*40+'\tHEAD')['update_status'], 'Remote changes available')
        self.assertEqual(checked(revision+'\tHEAD')['update_status'], 'Up to date')
        def timeout(directory, *args):
            if args[0] == 'ls-remote':
                raise subprocess.TimeoutExpired('git', 20)
            return actual_git(directory, *args)
        with patch('myomarchy.plugins.git', side_effect=timeout):
            plugins.check_updates(self.store, rid)
        self.assertEqual(plugins.metadata(self.store, self.store.get(rid))['update_status'], 'Update check failed')
        subprocess.run(['git', '-C', str(path), 'remote', 'set-url', 'origin', 'https://github.com/example/other.git'], check=True)
        row = plugins.metadata(self.store, self.store.get(rid))
        self.assertEqual(row['update_status'], 'Not checked'); self.assertIsNone(row['checked_at'])

    def run_worker(self, ids, recovery, run):
        rid = self.store.add('Update plugins', 'activity', status='queued')
        @contextlib.contextmanager
        def lock(store): yield
        # Worker owns its connection; keep this test's connection open for assertions.
        with patch.object(self.store, 'db', wraps=self.store.db) as db, patch('myomarchy.plugins.subprocess.run', side_effect=run), patch('myomarchy.plugins.run_updater', side_effect=lambda pid: run(['omarchy', 'plugin', 'update', pid, '--yes']).returncode):
            db.close.return_value = None
            plugins.update_worker(self.store, rid, ids, recovery, lock)
        return self.store.get(rid)

    def test_snapshot_failure_never_runs_updater(self):
        path, plugin = self.checkout()
        class Failed:
            def prepare(self, *args): raise RuntimeError('recovery unavailable')
        original = subprocess.run
        def run(command, **kwargs):
            self.assertNotEqual(command[0], 'omarchy')
            return original(command, **kwargs)
        row = self.run_worker([plugin], Failed(), run)
        self.assertEqual(row['status'], 'failed')

    def test_partial_failure_records_outcomes_and_self_updates_last(self):
        _, one = self.checkout('one')
        _, own = self.checkout(plugins.SELF)
        _, two = self.checkout('two')
        order = []; recovered = []
        class Ready:
            def prepare(self, rid, paths, emit): recovered.extend(paths)
        original = subprocess.run
        def run(command, **kwargs):
            if command[0] == 'omarchy':
                self.assertTrue(recovered)
                order.append(command[3])
                return subprocess.CompletedProcess(command, 1 if command[3] == 'two' else 0)
            return original(command, **kwargs)
        row = self.run_worker([own, one, two], Ready(), run)
        self.assertEqual(order[-1], plugins.SELF)
        self.assertEqual(row['status'], 'failed')
        self.assertEqual(len([e for e in row['events'] if e['kind'] == 'plugin-update']), 3)

    def test_advice_is_read_only(self):
        _, rid = self.checkout()
        prompt = agent_prompt(self.store, rid, 'update-advice')
        self.assertIn('Read-only inspection only', prompt)
        self.assertIn('do not install updates', prompt)

    def test_updater_timeout_kills_descendant_group(self):
        binary = self.home/'omarchy'
        marker = self.home/'descendant-survived'
        child = 'import time; from pathlib import Path; time.sleep(1); Path(' + repr(str(marker)) + ').write_text("bad")'
        binary.write_text('#!' + sys.executable + '\nimport subprocess,time,sys\nsubprocess.Popen([sys.executable,"-c",' + repr(child) + '])\ntime.sleep(30)\n')
        binary.chmod(0o700)
        with patch.dict(os.environ, {'PATH': str(self.home) + os.pathsep + os.environ['PATH']}):
            with self.assertRaises(subprocess.TimeoutExpired):
                plugins.run_updater('trial', timeout=0.2)
        time.sleep(1.1)
        self.assertFalse(marker.exists())

    def test_stopped_worker_is_reconciled(self):
        rid = self.store.add('Update plugins', 'activity', status='queued')
        self.store.event(rid, 'worker-launched', {'pid': 99999999, 'start_time': '0'})
        self.assertFalse(plugins.active_updates(self.store, self.store.list()))
        self.assertEqual(self.store.get(rid)['status'], 'unfinished')

    def test_empty_update_all_does_not_launch_worker(self):
        (self.home/'.config/omarchy/plugins').mkdir(parents=True)
        with patch('myomarchy.cli.subprocess.Popen') as launch, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(main(['--state-dir', str(self.store.directory), 'update-plugins', '--all']), 1)
        launch.assert_not_called()

    def test_update_launch_is_detached_and_has_record_ids(self):
        _, rid = self.checkout()
        original = subprocess.Popen
        launch = Mock(return_value=Mock(pid=99999999))
        def selective(command, **kwargs):
            return launch(command, **kwargs) if 'update-worker' in command else original(command, **kwargs)
        with patch('myomarchy.cli.subprocess.Popen', side_effect=selective), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(main(['--state-dir', str(self.store.directory), 'update-plugins', '--id', rid]), 0)
        self.assertTrue(launch.call_args.kwargs['start_new_session'])
        self.assertEqual(launch.call_args.args[0][-1], rid)
        self.assertTrue(json.loads(output.getvalue())['updating'])

    def test_liveness_reconciliation_preserves_completed_result(self):
        rid = self.store.add('Update plugins', 'activity', status='queued')
        rows = self.store.list()
        self.store.event(rid, 'finished', {'summary': 'Done'}, 'completed')
        self.assertFalse(plugins.active_updates(self.store, rows))
        self.assertEqual(self.store.get(rid)['status'], 'completed')
