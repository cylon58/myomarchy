from datetime import datetime, timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from myomarchy.store import Store
from myomarchy.install_dates import evidence


class InstallationDatesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'plugins/trial'
        (self.path/'.git/logs').mkdir(parents=True)
        (self.path/'manifest.json').write_text(json.dumps({'id': 'trial', 'name': 'Trial'}))
        self.epoch = 1700000000
        self.date = datetime.fromtimestamp(self.epoch, timezone.utc).isoformat(timespec='seconds')
        self.observed = '2026-10-05T00:00:00+00:00'

    def clone(self, epoch=None):
        epoch = self.epoch if epoch is None else epoch
        (self.path/'.git/logs/HEAD').write_text('0'*40+' '+'a'*40+' Person <private@example.invalid> '+str(epoch)+' +0000\tclone: from https://example.invalid/private\n')

    def test_clone_corroborated_by_location_creation_is_install_estimate(self):
        self.clone()
        with patch('myomarchy.install_dates.birth_time', return_value=self.epoch-1):
            result = evidence(self.path, self.observed)
        self.assertEqual(result['date'], self.date)
        self.assertEqual(result['date_kind'], 'inferred-install')
        self.assertNotIn('private@example', json.dumps(result))

    def test_copied_old_clone_uses_location_creation_instead(self):
        self.clone()
        with patch('myomarchy.install_dates.birth_time', return_value=self.epoch+86400):
            self.assertEqual(evidence(self.path, self.observed)['date_kind'], 'location-created')

    def test_reclone_after_first_observation_does_not_invent_original_install(self):
        self.clone()
        first = '2020-01-01T00:00:00+00:00'
        with patch('myomarchy.install_dates.birth_time', return_value=self.epoch):
            result = evidence(self.path, first)
        self.assertEqual(result, {'date': first, 'date_kind': 'first-seen', 'source': 'First local inventory observation'})

    def test_missing_or_malformed_logs_use_first_seen(self):
        for content in ['', 'malformed', '0'*40+' '+'a'*40+' Person <x@y.invalid> 1700000000 +0000\tcommit (initial): hello\n']:
            (self.path/'.git/logs/HEAD').write_text(content)
            with patch('myomarchy.install_dates.birth_time', return_value=None):
                self.assertEqual(evidence(self.path, self.observed)['date_kind'], 'first-seen')

    def test_store_backfills_once_and_preserves_verified_install(self):
        self.clone()
        store = Store(Path(self.tmp.name)/'state'); self.addCleanup(store.db.close)
        with patch('myomarchy.install_dates.birth_time', return_value=self.epoch):
            store.inventory(self.path.parent); store.inventory(self.path.parent)
        row = store.get(store.list()[0]['id'])
        self.assertEqual(row['date_kind'], 'inferred-install')
        self.assertEqual(len([e for e in row['events'] if e['kind']=='installation-evidence']), 1)
        with store.db:
            store.db.execute("UPDATE records SET date='2023-01-01',date_kind='installed' WHERE id=?", (row['id'],))
        with patch('myomarchy.install_dates.birth_time', return_value=self.epoch):
            store.inventory(self.path.parent)
        self.assertEqual(store.get(row['id'])['date'], '2023-01-01')

    def test_recorded_location_date_survives_missing_or_replaced_location_evidence(self):
        store = Store(Path(self.tmp.name)/'state'); self.addCleanup(store.db.close)
        with patch('myomarchy.install_dates.birth_time', return_value=self.epoch):
            store.inventory(self.path.parent)
        row = store.get(store.list()[0]['id'])
        self.assertEqual(row['date_kind'], 'location-created')
        for birth in [None, 2000000000]:
            with patch('myomarchy.install_dates.birth_time', return_value=birth):
                store.inventory(self.path.parent)
            self.assertEqual(store.get(row['id'])['date'], row['date'])
            self.assertEqual(store.get(row['id'])['date_kind'], 'location-created')
