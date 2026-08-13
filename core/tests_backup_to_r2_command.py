import json
import os
from datetime import UTC, datetime, time
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch
from zoneinfo import ZoneInfo

from django.conf import settings
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase

from core.backup_config import R2BackupConfig
from core.backup_logging import serialize_backup_event
from core.remote_backup import BackupOutcome, BackupVerificationError


class BackupEventSerializationTest(SimpleTestCase):
    def test_serializes_compact_utc_event_with_abbreviated_hash(self):
        serialized = serialize_backup_event(
            timestamp=datetime(
                2026,
                8,
                12,
                3,
                4,
                5,
                tzinfo=ZoneInfo('America/Sao_Paulo'),
            ),
            event='backup_finished',
            status='created',
            stage='complete',
            key='production/backups/example.sqlite3',
            size=180224,
            sha256='abcdef123456' + ('0' * 52),
            duration_ms=125,
            deleted_count=2,
        )

        self.assertNotIn(' ', serialized)
        self.assertEqual(
            json.loads(serialized),
            {
                'timestamp': '2026-08-12T06:04:05+00:00',
                'service': 'lar-finance-backup',
                'event': 'backup_finished',
                'status': 'created',
                'stage': 'complete',
                'key': 'production/backups/example.sqlite3',
                'size': 180224,
                'sha256': 'abcdef123456',
                'duration_ms': 125,
                'deleted_count': 2,
                'error_code': None,
            },
        )


class BackupToR2CommandTest(SimpleTestCase):
    access_id = 'private-access-id-sentinel'
    secret = 'private-secret-sentinel'
    sqlite_content = 'private-sqlite-content-sentinel'
    financial_description = 'private-financial-description-sentinel'

    def setUp(self):
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.database_path = Path(self.temporary_directory.name) / 'db.sqlite3'
        self.config = R2BackupConfig(
            endpoint_url='https://account.invalid',
            access_key_id=self.access_id,
            secret_access_key=self.secret,
            bucket='backup-bucket',
            prefix='production',
            schedule_time=time(3),
            time_zone=ZoneInfo('America/Sao_Paulo'),
        )
        self.database_settings = {
            'default': {
                'ENGINE': 'django.db.backends.sqlite3',
                'NAME': self.database_path,
            }
        }

    @patch('core.management.commands.backup_to_r2.time.monotonic')
    @patch('core.management.commands.backup_to_r2.execute_remote_backup')
    @patch('core.management.commands.backup_to_r2.R2Storage.from_config')
    @patch('core.management.commands.backup_to_r2.R2BackupConfig.from_env')
    def test_success_logs_complete_sanitized_json_event(
        self,
        config_from_env,
        storage_from_config,
        execute_backup,
        monotonic,
    ):
        config_from_env.return_value = self.config
        storage = Mock()
        storage_from_config.return_value = storage
        execute_backup.return_value = BackupOutcome(
            status='created',
            key='production/backups/2026/08/lar-finance-2026-08-12.sqlite3',
            size=180224,
            sha256='abcdef123456' + ('0' * 52),
            deleted_keys=('older-1', 'older-2'),
        )
        monotonic.side_effect = (100.0, 100.125)
        stdout = StringIO()
        stderr = StringIO()

        with (
            patch.object(settings, 'DATABASES', self.database_settings),
            self.assertLogs('lar_finance.backup', level='INFO') as captured,
        ):
            call_command('backup_to_r2', stdout=stdout, stderr=stderr)

        config_from_env.assert_called_once_with(os.environ)
        storage_from_config.assert_called_once_with(self.config)
        execute_backup.assert_called_once()
        call = execute_backup.call_args
        self.assertEqual(call.args[:3], (self.config, storage, self.database_path))
        self.assertEqual(call.args[3].tzinfo, UTC)
        event = json.loads(captured.records[0].getMessage())
        self.assertEqual(event['service'], 'lar-finance-backup')
        self.assertEqual(event['event'], 'backup_finished')
        self.assertEqual(event['status'], 'created')
        self.assertEqual(event['stage'], 'complete')
        self.assertEqual(event['duration_ms'], 125)
        self.assertEqual(
            event['key'],
            'production/backups/2026/08/lar-finance-2026-08-12.sqlite3',
        )
        self.assertEqual(event['size'], 180224)
        self.assertEqual(event['sha256'], 'abcdef123456')
        self.assertEqual(event['deleted_count'], 2)
        self.assertEqual(event['timestamp'][-6:], '+00:00')
        self.assert_private_values_absent(stdout, stderr, captured)

    @patch('core.management.commands.backup_to_r2.time.monotonic')
    @patch('core.management.commands.backup_to_r2.execute_remote_backup')
    @patch('core.management.commands.backup_to_r2.R2Storage.from_config')
    @patch('core.management.commands.backup_to_r2.R2BackupConfig.from_env')
    def test_known_error_logs_code_and_raises_sanitized_command_error(
        self,
        config_from_env,
        storage_from_config,
        execute_backup,
        monotonic,
    ):
        config_from_env.return_value = self.config
        storage_from_config.return_value = Mock()
        execute_backup.side_effect = BackupVerificationError(
            ' '.join(
                (
                    self.access_id,
                    self.secret,
                    self.sqlite_content,
                    self.financial_description,
                )
            ),
            error_code='remote_invalid',
            stage='preflight',
        )
        monotonic.side_effect = (200.0, 200.025)
        stdout = StringIO()
        stderr = StringIO()

        with (
            patch.object(settings, 'DATABASES', self.database_settings),
            self.assertLogs('lar_finance.backup', level='ERROR') as captured,
            self.assertRaises(CommandError) as raised,
        ):
            call_command('backup_to_r2', stdout=stdout, stderr=stderr)

        self.assertEqual(str(raised.exception), 'Backup failed [remote_invalid].')
        event = json.loads(captured.records[0].getMessage())
        self.assertEqual(event['event'], 'backup_failed')
        self.assertEqual(event['status'], 'error')
        self.assertEqual(event['stage'], 'preflight')
        self.assertEqual(event['error_code'], 'remote_invalid')
        self.assertEqual(event['duration_ms'], 25)
        self.assert_private_values_absent(stdout, stderr, captured, raised.exception)

    def test_backup_logger_uses_json_stdout_without_propagation(self):
        logger_config = settings.LOGGING['loggers']['lar_finance.backup']

        self.assertEqual(logger_config['handlers'], ['api_stdout'])
        self.assertEqual(logger_config['level'], 'INFO')
        self.assertIs(logger_config['propagate'], False)

    def assert_private_values_absent(self, stdout, stderr, captured, error=None):
        output = '\n'.join(
            (
                stdout.getvalue(),
                stderr.getvalue(),
                *captured.output,
                '' if error is None else str(error),
            )
        )
        for private_value in (
            self.access_id,
            self.secret,
            self.sqlite_content,
            self.financial_description,
        ):
            self.assertNotIn(private_value, output)
