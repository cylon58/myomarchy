import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from myomarchy.cli import main
from myomarchy.store import Store


class ManualPluginTests(unittest.TestCase):
    def test_dashboard_discovers_manual_install_update_removal_and_return(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            plugins = base/'config/omarchy/plugins'
            plugins.mkdir(parents=True)
            state = base/'state'
            stores = []
            def tracked_store(directory):
                store = Store(directory)
                stores.append(store)
                self.addCleanup(store.db.close)
                return store
            def dashboard():
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    self.assertEqual(main(['--state-dir', str(state), 'dashboard']), 0)
                return json.loads(output.getvalue())['records']
            with patch.dict(os.environ, {'XDG_CONFIG_HOME': str(base/'config')}), patch('myomarchy.cli.coverage', return_value={}), patch('myomarchy.cli.Store', side_effect=tracked_store):
                self.assertEqual(dashboard(), [])
                plugin = plugins/'manual'; plugin.mkdir()
                manifest = plugin/'manifest.json'
                manifest.write_text(json.dumps({'id': 'manual', 'name': 'Manual', 'version': '1'}))
                row = dashboard()[0]
                self.assertEqual(row['status'], 'present')
                self.assertIsNone(row['date'])
                manifest.write_text(json.dumps({'id': 'manual', 'name': 'Manual', 'version': '2'}))
                self.assertEqual(dashboard()[0]['id'], row['id'])
                manifest.unlink(); plugin.rmdir()
                self.assertEqual(dashboard()[0]['status'], 'removed')
                plugin.mkdir(); manifest.write_text(json.dumps({'id': 'manual', 'name': 'Manual'}))
                returned = dashboard()
                self.assertEqual(len(returned), 1)
                self.assertEqual(returned[0]['status'], 'present')
                self.assertEqual(returned[0]['id'], row['id'])
