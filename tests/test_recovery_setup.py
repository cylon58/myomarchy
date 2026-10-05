import unittest
from unittest.mock import patch

from myomarchy.recovery import Recovery


class RecoverySetupTests(unittest.TestCase):
    def setup_commands(self, existing, **options):
        commands = []
        def run(argv, **kwargs):
            commands.append(argv)
            return ''
        with patch('myomarchy.recovery.configs', return_value=existing):
            Recovery(run).setup(**options)
        return commands

    def test_default_preserves_existing_policy_and_configures_missing_home(self):
        commands = self.setup_commands({'root': {
            'SUBVOLUME': '/', 'FSTYPE': 'btrfs', 'NUMBER_LIMIT': '5'}})
        self.assertFalse(any('root' in command for command in commands))
        self.assertIn(['/usr/bin/snapper', '-c', 'myomarchy-home',
                       'create-config', '/home'], commands)
        home_policy = next(c for c in commands if 'set-config' in c)
        self.assertIn('NUMBER_LIMIT=5', home_policy)
        self.assertIn('TIMELINE_CREATE=no', home_policy)
        self.assertIn(['/usr/bin/chmod', '644',
                       '/etc/snapper/configs/myomarchy-home'], commands)

    def test_existing_complete_setup_is_unchanged_by_default(self):
        self.assertEqual(self.setup_commands({
            'root': {'SUBVOLUME': '/', 'FSTYPE': 'btrfs'},
            'home': {'SUBVOLUME': '/home', 'FSTYPE': 'btrfs'}}), [])

    def test_explicit_retention_changes_existing_configurations(self):
        commands = self.setup_commands({
            'root': {'SUBVOLUME': '/', 'FSTYPE': 'btrfs'},
            'home': {'SUBVOLUME': '/home', 'FSTYPE': 'btrfs'}}, count=12)
        self.assertEqual(len(commands), 2)
        self.assertTrue(all('NUMBER_LIMIT=12' in c for c in commands))

    def test_rejects_non_btrfs_configuration(self):
        with self.assertRaisesRegex(ValueError, 'Btrfs'):
            self.setup_commands({'root': {'SUBVOLUME': '/', 'FSTYPE': 'ext4'}})
