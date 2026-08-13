from dataclasses import replace
from datetime import UTC, date, datetime, time
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch
from zoneinfo import ZoneInfo

from django.test import SimpleTestCase
from filelock import FileLock, Timeout

from core.backup_config import R2BackupConfig
from core.r2_storage import (
    RemoteObject,
    RemoteObjectInvalid,
    RemoteVerificationError,
)
from core.remote_backup import (
    BackupAlreadyRunning,
    BackupRetentionError,
    BackupVerificationError,
    execute_remote_backup,
)


class RemoteBackupTestMixin:
    def setUp(self):
        super().setUp()
        self.temporary_directory = TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.db = Path(self.temporary_directory.name) / 'db.sqlite3'
        self.db.write_bytes(b'sqlite sentinel')
        self.now = datetime(2026, 8, 12, 6, tzinfo=UTC)
        self.config = R2BackupConfig(
            endpoint_url='https://account.invalid',
            access_key_id='access-id',
            secret_access_key='secret-value',
            bucket='backup-bucket',
            prefix='production',
            schedule_time=time(3),
            time_zone=ZoneInfo('America/Sao_Paulo'),
        )
        self.key = 'production/backups/2026/08/lar-finance-2026-08-12.sqlite3'


class RemoteBackupPreflightTest(RemoteBackupTestMixin, SimpleTestCase):

    @patch('core.remote_backup.backup_sqlite')
    def test_existing_valid_day_is_idempotent_before_local_copy(self, backup_mock):
        existing = RemoteObject(
            key=self.key,
            backup_date=date(2026, 8, 12),
            size=180224,
            sha256='a' * 64,
            retention=frozenset({'daily'}),
        )
        storage = Mock()
        storage.head_managed.return_value = existing

        outcome = execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(outcome.status, 'already_exists')
        self.assertEqual(outcome.key, self.key)
        self.assertEqual(outcome.size, 180224)
        self.assertEqual(outcome.sha256, 'a' * 64)
        self.assertEqual(outcome.deleted_keys, ())
        backup_mock.assert_not_called()
        storage.upload_and_verify.assert_not_called()
        storage.list_managed.assert_not_called()

    @patch('core.remote_backup.backup_sqlite')
    def test_invalid_existing_day_aborts_before_copy_or_remote_changes(
        self,
        backup_mock,
    ):
        storage = Mock()
        storage.head_managed.side_effect = RemoteObjectInvalid(
            'sensitive remote response'
        )

        with self.assertRaises(BackupVerificationError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertNotIn('sensitive remote response', str(raised.exception))
        backup_mock.assert_not_called()
        storage.upload_and_verify.assert_not_called()
        storage.list_managed.assert_not_called()
        storage.delete.assert_not_called()
        self.assertFalse((self.db.parent / 'backups').exists())

    def test_storage_timeout_is_not_misclassified_as_lock_contention(self):
        storage = Mock()
        storage.head_managed.side_effect = Timeout('remote-operation')

        with self.assertRaises(Timeout):
            execute_remote_backup(self.config, storage, self.db, self.now)

    def test_programming_error_is_not_hidden_as_operational_failure(self):
        storage = Mock()
        storage.head_managed.side_effect = AttributeError('implementation defect')

        with self.assertRaisesRegex(AttributeError, 'implementation defect'):
            execute_remote_backup(self.config, storage, self.db, self.now)


class RemoteBackupExecutionTest(RemoteBackupTestMixin, SimpleTestCase):
    backup_content = b'verified sqlite backup bytes'
    backup_sha256 = '3cc788a9543c499357bec68c7cf64df35460131e21be52cecd41a5319b133052'

    def remote(self, backup_date, *, sha256=None, size=None):
        key = (
            f'production/backups/{backup_date:%Y/%m}/'
            f'lar-finance-{backup_date:%Y-%m-%d}.sqlite3'
        )
        return RemoteObject(
            key=key,
            backup_date=backup_date,
            size=len(self.backup_content) if size is None else size,
            sha256=sha256 or self.backup_sha256,
            retention=frozenset({'daily'}),
        )

    def storage_for_created_backup(self, *, objects=None):
        storage = Mock()
        storage.head_managed.return_value = None
        remote = self.remote(date(2026, 8, 12))
        storage.upload_and_verify.return_value = remote
        storage.list_managed.return_value = objects or [remote]
        return storage, remote

    @patch('core.remote_backup.backup_sqlite')
    def test_creates_unused_adjacent_copy_hashes_real_file_and_cleans_it(
        self,
        backup_mock,
    ):
        captured = {}
        events = []
        storage, remote = self.storage_for_created_backup()

        def create_backup(source, destination):
            captured['path'] = destination
            self.assertEqual(source, self.db.resolve())
            self.assertEqual(destination.parent, self.db.parent / 'backups')
            self.assertFalse(destination.exists())
            destination.write_bytes(self.backup_content)
            events.append('copy')

        def upload(path, key, backup_date, sha256):
            self.assertEqual(path.read_bytes(), self.backup_content)
            self.assertEqual(key, self.key)
            self.assertEqual(backup_date, date(2026, 8, 12))
            self.assertEqual(sha256, self.backup_sha256)
            events.append('upload')
            return remote

        def list_managed():
            events.append('list')
            return [remote]

        backup_mock.side_effect = create_backup
        storage.upload_and_verify.side_effect = upload
        storage.list_managed.side_effect = list_managed

        outcome = execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(outcome.status, 'created')
        self.assertEqual(outcome.key, self.key)
        self.assertEqual(outcome.size, len(self.backup_content))
        self.assertEqual(outcome.sha256, self.backup_sha256)
        self.assertEqual(outcome.deleted_keys, ())
        self.assertEqual(events, ['copy', 'upload', 'list'])
        self.assertFalse(captured['path'].exists())

    @patch('core.remote_backup.backup_sqlite')
    def test_deletes_only_expired_objects_in_oldest_first_order(self, backup_mock):
        backup_mock.side_effect = lambda source, destination: destination.write_bytes(
            self.backup_content
        )
        current = self.remote(date(2026, 8, 12))
        retained = self.remote(date(2026, 8, 11))
        newer_expired = self.remote(date(2026, 8, 10))
        oldest_expired = self.remote(date(2026, 8, 9))
        storage, _ = self.storage_for_created_backup(
            objects=[newer_expired, current, oldest_expired, retained]
        )
        config = replace(
            self.config,
            daily_retention=2,
            weekly_retention=0,
            monthly_retention=0,
        )

        outcome = execute_remote_backup(config, storage, self.db, self.now)

        expected_deleted = (oldest_expired.key, newer_expired.key)
        self.assertEqual(outcome.deleted_keys, expected_deleted)
        self.assertEqual(
            [call.args[0] for call in storage.delete.call_args_list],
            list(expected_deleted),
        )
        self.assertNotIn(current.key, expected_deleted)
        self.assertNotIn(retained.key, expected_deleted)

    @patch('core.remote_backup.backup_sqlite')
    def test_zero_retention_still_never_deletes_latest_backup(self, backup_mock):
        backup_mock.side_effect = lambda source, destination: destination.write_bytes(
            self.backup_content
        )
        current = self.remote(date(2026, 8, 12))
        older = self.remote(date(2026, 8, 11))
        storage, _ = self.storage_for_created_backup(objects=[older, current])
        config = replace(
            self.config,
            daily_retention=0,
            weekly_retention=0,
            monthly_retention=0,
        )

        outcome = execute_remote_backup(config, storage, self.db, self.now)

        self.assertEqual(outcome.deleted_keys, (older.key,))
        storage.delete.assert_called_once_with(older.key)

    @patch('core.remote_backup.backup_sqlite')
    def test_first_delete_failure_stops_remaining_deletes_and_cleans_temp(
        self,
        backup_mock,
    ):
        captured = {}

        def create_backup(source, destination):
            captured['path'] = destination
            destination.write_bytes(self.backup_content)

        backup_mock.side_effect = create_backup
        current = self.remote(date(2026, 8, 12))
        newer_expired = self.remote(date(2026, 8, 11))
        oldest_expired = self.remote(date(2026, 8, 10))
        storage, _ = self.storage_for_created_backup(
            objects=[newer_expired, current, oldest_expired]
        )
        storage.delete.side_effect = OSError('sensitive delete response')
        config = replace(
            self.config,
            daily_retention=0,
            weekly_retention=0,
            monthly_retention=0,
        )

        with self.assertRaises(BackupRetentionError) as raised:
            execute_remote_backup(config, storage, self.db, self.now)

        self.assertNotIn('sensitive delete response', str(raised.exception))
        storage.delete.assert_called_once_with(oldest_expired.key)
        self.assertFalse(captured['path'].exists())

    @patch('core.remote_backup.backup_sqlite')
    def test_sqlite_failure_is_sanitized_and_cleans_reserved_temp(self, backup_mock):
        captured = {}

        def fail_copy(source, destination):
            captured['path'] = destination
            raise OSError('sqlite contents and private transaction')

        backup_mock.side_effect = fail_copy
        storage, _ = self.storage_for_created_backup()

        with self.assertRaises(BackupVerificationError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertNotIn('private transaction', str(raised.exception))
        self.assertFalse(captured['path'].exists())
        storage.upload_and_verify.assert_not_called()

    @patch('core.remote_backup.backup_sqlite')
    def test_upload_failure_is_sanitized_and_cleans_temp(self, backup_mock):
        captured = {}

        def create_backup(source, destination):
            captured['path'] = destination
            destination.write_bytes(self.backup_content)

        backup_mock.side_effect = create_backup
        storage, _ = self.storage_for_created_backup()
        storage.upload_and_verify.side_effect = RemoteVerificationError(
            'secret endpoint response'
        )

        with self.assertRaises(BackupVerificationError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertNotIn('secret endpoint response', str(raised.exception))
        self.assertFalse(captured['path'].exists())
        storage.list_managed.assert_not_called()

    @patch('core.remote_backup.backup_sqlite')
    def test_list_failure_is_sanitized_and_cleans_temp(self, backup_mock):
        captured = {}

        def create_backup(source, destination):
            captured['path'] = destination
            destination.write_bytes(self.backup_content)

        backup_mock.side_effect = create_backup
        storage, _ = self.storage_for_created_backup()
        storage.list_managed.side_effect = OSError('secret catalog response')

        with self.assertRaises(BackupRetentionError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertNotIn('secret catalog response', str(raised.exception))
        self.assertFalse(captured['path'].exists())

    @patch('core.remote_backup.backup_sqlite')
    def test_nonblocking_file_lock_rejects_concurrent_run(self, backup_mock):
        storage = Mock()
        lock_path = self.db.parent / '.lar-finance-r2-backup.lock'

        with FileLock(lock_path):
            with self.assertRaises(BackupAlreadyRunning):
                execute_remote_backup(self.config, storage, self.db, self.now)

        backup_mock.assert_not_called()
        storage.head_managed.assert_not_called()
