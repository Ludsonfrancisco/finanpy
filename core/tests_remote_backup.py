import stat
from contextlib import contextmanager
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
        storage.list_managed.return_value = [existing]

        outcome = execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(outcome.status, 'already_exists')
        self.assertEqual(outcome.key, self.key)
        self.assertEqual(outcome.size, 180224)
        self.assertEqual(outcome.sha256, 'a' * 64)
        self.assertEqual(outcome.deleted_keys, ())
        backup_mock.assert_not_called()
        storage.upload_and_verify.assert_not_called()
        storage.list_managed.assert_called_once_with()

    @patch('core.remote_backup.backup_sqlite')
    def test_retention_failure_retries_existing_object_without_reupload(
        self,
        backup_mock,
    ):
        existing = RemoteObject(
            key=self.key,
            backup_date=date(2026, 8, 12),
            size=180224,
            sha256='a' * 64,
            retention=frozenset({'daily'}),
        )
        expired = RemoteObject(
            key='production/backups/2026/08/lar-finance-2026-08-11.sqlite3',
            backup_date=date(2026, 8, 11),
            size=170000,
            sha256='b' * 64,
            retention=frozenset({'daily'}),
        )
        config = replace(
            self.config,
            daily_retention=0,
            weekly_retention=0,
            monthly_retention=0,
        )
        storage = Mock()
        storage.head_managed.side_effect = [None, existing]
        storage.upload_and_verify.return_value = existing
        storage.list_managed.return_value = [expired, existing]
        storage.delete.side_effect = [OSError('private retention failure'), None]
        backup_mock.side_effect = lambda source, destination: destination.write_bytes(
            b'verified sqlite backup bytes'
        )

        with self.assertRaises(BackupRetentionError):
            execute_remote_backup(config, storage, self.db, self.now)

        outcome = execute_remote_backup(config, storage, self.db, self.now)

        self.assertEqual(outcome.status, 'already_exists')
        self.assertEqual(outcome.deleted_keys, (expired.key,))
        self.assertEqual(storage.list_managed.call_count, 2)
        self.assertEqual(storage.delete.call_count, 2)
        backup_mock.assert_called_once()
        storage.upload_and_verify.assert_called_once()

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

    def test_storage_timeout_is_sanitized_as_preflight_failure(self):
        storage = Mock()
        storage.head_managed.side_effect = Timeout('private preflight path')

        with self.assertRaises(BackupVerificationError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'remote_invalid')
        self.assertEqual(raised.exception.stage, 'preflight')
        self.assertNotIn('private preflight path', str(raised.exception))

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
            self.assertEqual(
                destination.parent,
                self.db.parent / 'backups' / '.lar-finance-r2-staging',
            )
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
    def test_copy_timeout_is_sanitized_with_copy_code(self, backup_mock):
        backup_mock.side_effect = Timeout('private copy path')
        storage, _ = self.storage_for_created_backup()

        with self.assertRaises(BackupVerificationError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'copy_failed')
        self.assertEqual(raised.exception.stage, 'copy')
        self.assertNotIn('private copy path', str(raised.exception))

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
    def test_upload_timeout_is_sanitized_with_upload_code(self, backup_mock):
        backup_mock.side_effect = lambda source, destination: destination.write_bytes(
            self.backup_content
        )
        storage, _ = self.storage_for_created_backup()
        storage.upload_and_verify.side_effect = Timeout('private upload path')

        with self.assertRaises(BackupVerificationError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'upload_failed')
        self.assertEqual(raised.exception.stage, 'upload')
        self.assertNotIn('private upload path', str(raised.exception))

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
    def test_retention_timeout_is_sanitized_with_retention_code(self, backup_mock):
        backup_mock.side_effect = lambda source, destination: destination.write_bytes(
            self.backup_content
        )
        storage, _ = self.storage_for_created_backup()
        storage.list_managed.side_effect = Timeout('private retention path')

        with self.assertRaises(BackupRetentionError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'retention_failed')
        self.assertEqual(raised.exception.stage, 'retention')
        self.assertNotIn('private retention path', str(raised.exception))

    def test_reservation_failures_are_sanitized_as_copy_failure(self):
        scenarios = (
            ('mkdir', self._backup_mkdir_patch()),
            (
                'create',
                patch(
                    'core.remote_backup.tempfile.NamedTemporaryFile',
                    side_effect=OSError('private create path'),
                ),
            ),
            (
                'close',
                self._temporary_handle_patch(
                    close_error=OSError('private close path')
                ),
            ),
            (
                'initial_unlink',
                self._backup_unlink_patch(OSError('private unlink path')),
            ),
        )

        for label, failure_patch in scenarios:
            with self.subTest(operation=label), failure_patch:
                storage, _ = self.storage_for_created_backup()
                with self.assertRaises(BackupVerificationError) as raised:
                    execute_remote_backup(self.config, storage, self.db, self.now)

                self.assertEqual(raised.exception.error_code, 'copy_failed')
                self.assertEqual(raised.exception.stage, 'copy')
                self.assertNotIn('private', str(raised.exception))

    @patch('core.remote_backup.backup_sqlite')
    def test_cleanup_failure_after_success_is_sanitized(self, backup_mock):
        backup_mock.side_effect = lambda source, destination: destination.write_bytes(
            self.backup_content
        )
        storage, _ = self.storage_for_created_backup()

        with self._backup_unlink_patch(None, OSError('private cleanup path')):
            with self.assertRaises(BackupVerificationError) as raised:
                execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'cleanup_failed')
        self.assertEqual(raised.exception.stage, 'cleanup')
        self.assertNotIn('private cleanup path', str(raised.exception))

    @patch('core.remote_backup.backup_sqlite')
    def test_cleanup_failure_exposes_state_and_recovers_on_retry(self, backup_mock):
        captured = {}

        def fail_copy(source, destination):
            captured['residue'] = destination
            destination.write_bytes(b'partial private backup')
            raise OSError('private primary copy')

        backup_mock.side_effect = fail_copy
        storage, _ = self.storage_for_created_backup()

        with self._backup_unlink_patch(None, OSError('private cleanup path')):
            with self.assertRaises(BackupVerificationError) as raised:
                execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'cleanup_failed')
        self.assertEqual(raised.exception.stage, 'cleanup')
        self.assertIsInstance(raised.exception.__cause__, BackupVerificationError)
        self.assertEqual(raised.exception.__cause__.error_code, 'copy_failed')
        self.assertNotIn('private primary copy', str(raised.exception))
        self.assertNotIn('private cleanup path', str(raised.exception))
        self.assertTrue(captured['residue'].exists())

        backup_mock.side_effect = lambda source, destination: destination.write_bytes(
            self.backup_content
        )
        outcome = execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(outcome.status, 'created')
        self.assertFalse(captured['residue'].exists())

    @patch('core.remote_backup.backup_sqlite')
    def test_stale_cleanup_removes_only_valid_owned_regular_files(self, backup_mock):
        backup_directory = self.db.parent / 'backups'
        backup_directory.mkdir()
        owned = backup_directory / '.lar-finance-r2-owned.sqlite3'
        unknown = backup_directory / 'manual-backup.sqlite3'
        apparent_symlink = backup_directory / '.lar-finance-r2-link.sqlite3'
        owned.write_bytes(b'owned residue')
        unknown.write_bytes(b'unknown backup')
        apparent_symlink.write_bytes(b'symlink sentinel')
        existing = self.remote(date(2026, 8, 12))
        storage = Mock()
        storage.head_managed.return_value = existing
        storage.list_managed.return_value = [existing]
        with self._symlink_lstat_patch(apparent_symlink):
            outcome = execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(outcome.status, 'already_exists')
        self.assertFalse(owned.exists())
        self.assertTrue(unknown.exists())
        self.assertTrue(apparent_symlink.exists())
        self.assertEqual(self.db.read_bytes(), b'sqlite sentinel')
        backup_mock.assert_not_called()

    @patch('core.remote_backup.backup_sqlite')
    def test_retry_cleans_owned_staging_files_and_sqlite_sidecars(
        self,
        backup_mock,
    ):
        backup_directory = self.db.parent / 'backups'
        staging_directory = backup_directory / '.lar-finance-r2-staging'
        staging_directory.mkdir(parents=True)
        legacy_base = backup_directory / '.lar-finance-backup-legacy.tmp'
        staging_base = staging_directory / '.lar-finance-backup-restart.tmp'
        owned = (
            backup_directory / '.lar-finance-r2-legacy.sqlite3',
            backup_directory / '.lar-finance-r2-legacy.sqlite3-wal',
            legacy_base,
            backup_directory / f'{legacy_base.name}-journal',
            staging_directory / '.lar-finance-r2-restart.sqlite3',
            staging_base,
            staging_directory / f'{staging_base.name}-wal',
            staging_directory / f'{staging_base.name}-shm',
            staging_directory / f'{staging_base.name}-journal',
        )
        for path in owned:
            path.write_bytes(b'owned staging residue')
        unknown = staging_directory / 'manual-backup.tmp-wal'
        apparent_symlink = staging_directory / '.lar-finance-backup-link.tmp-shm'
        outside = self.db.parent / '.lar-finance-backup-outside.tmp'
        unknown.write_bytes(b'unknown sentinel')
        apparent_symlink.write_bytes(b'symlink sentinel')
        outside.write_bytes(b'outside sentinel')
        existing = self.remote(date(2026, 8, 12))
        storage = Mock()
        storage.head_managed.return_value = existing
        storage.list_managed.return_value = [existing]
        with self._symlink_lstat_patch(apparent_symlink):
            outcome = execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(outcome.status, 'already_exists')
        for path in owned:
            self.assertFalse(path.exists(), path.name)
        self.assertTrue(unknown.exists())
        self.assertTrue(apparent_symlink.exists())
        self.assertTrue(outside.exists())
        self.assertEqual(self.db.read_bytes(), b'sqlite sentinel')
        backup_mock.assert_not_called()

    def test_staging_cleanup_failure_aborts_before_remote_operations(self):
        backup_directory = self.db.parent / 'backups'
        staging_directory = backup_directory / '.lar-finance-r2-staging'
        staging_directory.mkdir(parents=True)
        residue = staging_directory / '.lar-finance-backup-owned.tmp'
        residue.write_bytes(b'partial private backup')
        storage = Mock()
        existing = self.remote(date(2026, 8, 12))
        storage.head_managed.return_value = existing
        storage.list_managed.return_value = [existing]
        original_unlink = Path.unlink

        def unlink(path, *args, **kwargs):
            if path == residue:
                raise OSError('private staging cleanup path')
            return original_unlink(path, *args, **kwargs)

        with patch.object(
            Path,
            'unlink',
            autospec=True,
            side_effect=unlink,
        ):
            with self.assertRaises(BackupVerificationError) as raised:
                execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'cleanup_failed')
        self.assertEqual(raised.exception.stage, 'cleanup')
        self.assertNotIn('private staging cleanup path', str(raised.exception))
        storage.head_managed.assert_not_called()
        storage.upload_and_verify.assert_not_called()
        storage.list_managed.assert_not_called()

    def test_staging_path_that_is_not_a_directory_aborts_before_remote(self):
        backup_directory = self.db.parent / 'backups'
        backup_directory.mkdir()
        staging_path = backup_directory / '.lar-finance-r2-staging'
        staging_path.write_bytes(b'not a directory')
        storage = Mock()

        with self.assertRaises(BackupVerificationError) as raised:
            execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'cleanup_failed')
        self.assertEqual(raised.exception.stage, 'cleanup')
        storage.head_managed.assert_not_called()

    def test_symbolic_staging_directory_aborts_before_remote(self):
        backup_directory = self.db.parent / 'backups'
        staging_directory = backup_directory / '.lar-finance-r2-staging'
        staging_directory.mkdir(parents=True)
        storage = Mock()
        with self._symlink_lstat_patch(staging_directory):
            with self.assertRaises(BackupVerificationError) as raised:
                execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'cleanup_failed')
        self.assertEqual(raised.exception.stage, 'cleanup')
        storage.head_managed.assert_not_called()

    @patch('core.remote_backup.backup_sqlite')
    def test_dangling_backup_directory_symlink_aborts_before_any_io(
        self,
        backup_mock,
    ):
        backup_directory = self.db.parent / 'backups'
        storage = Mock()
        existing = self.remote(date(2026, 8, 12))
        storage.head_managed.return_value = existing
        storage.list_managed.return_value = [existing]

        with self._dangling_symlink_patch(backup_directory):
            with self.assertRaises(BackupVerificationError) as raised:
                execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'cleanup_failed')
        self.assertEqual(raised.exception.stage, 'cleanup')
        backup_mock.assert_not_called()
        storage.head_managed.assert_not_called()
        storage.list_managed.assert_not_called()
        storage.upload_and_verify.assert_not_called()
        storage.delete.assert_not_called()

    @patch('core.remote_backup.backup_sqlite')
    def test_dangling_staging_directory_symlink_aborts_before_any_io(
        self,
        backup_mock,
    ):
        backup_directory = self.db.parent / 'backups'
        backup_directory.mkdir()
        staging_directory = backup_directory / '.lar-finance-r2-staging'
        storage = Mock()
        existing = self.remote(date(2026, 8, 12))
        storage.head_managed.return_value = existing
        storage.list_managed.return_value = [existing]

        with self._dangling_symlink_patch(staging_directory):
            with self.assertRaises(BackupVerificationError) as raised:
                execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'cleanup_failed')
        self.assertEqual(raised.exception.stage, 'cleanup')
        backup_mock.assert_not_called()
        storage.head_managed.assert_not_called()
        storage.list_managed.assert_not_called()
        storage.upload_and_verify.assert_not_called()
        storage.delete.assert_not_called()

    def test_stale_cleanup_failure_aborts_before_remote_operations(self):
        backup_directory = self.db.parent / 'backups'
        backup_directory.mkdir()
        residue = backup_directory / '.lar-finance-r2-owned.sqlite3'
        residue.write_bytes(b'partial private backup')
        storage = Mock()

        with patch.object(
            Path,
            'unlink',
            autospec=True,
            side_effect=OSError('private cleanup path'),
        ):
            with self.assertRaises(BackupVerificationError) as raised:
                execute_remote_backup(self.config, storage, self.db, self.now)

        self.assertEqual(raised.exception.error_code, 'cleanup_failed')
        self.assertEqual(raised.exception.stage, 'cleanup')
        self.assertNotIn('private cleanup path', str(raised.exception))
        storage.head_managed.assert_not_called()
        storage.upload_and_verify.assert_not_called()
        storage.list_managed.assert_not_called()

    @patch('core.remote_backup.backup_sqlite')
    def test_process_control_exceptions_are_preserved(self, backup_mock):
        for exception_type in (KeyboardInterrupt, SystemExit):
            with self.subTest(exception_type=exception_type.__name__):
                backup_mock.side_effect = exception_type()
                storage, _ = self.storage_for_created_backup()

                with self.assertRaises(exception_type):
                    execute_remote_backup(self.config, storage, self.db, self.now)

    def _temporary_handle_patch(self, *, close_error):
        handle = Mock()
        handle.name = str(self.db.parent / 'backups' / 'reserved.sqlite3')
        handle.close.side_effect = close_error
        return patch(
            'core.remote_backup.tempfile.NamedTemporaryFile',
            return_value=handle,
        )

    @contextmanager
    def _dangling_symlink_patch(self, dangling_path):
        original_exists = Path.exists
        original_is_symlink = Path.is_symlink
        original_lstat = Path.lstat

        def exists(path):
            if path == dangling_path:
                return False
            return original_exists(path)

        def is_symlink(path):
            if path == dangling_path:
                return True
            return original_is_symlink(path)

        def lstat(path):
            if path == dangling_path:
                return Mock(st_mode=stat.S_IFLNK, st_dev=1, st_ino=99)
            return original_lstat(path)

        with (
            patch.object(Path, 'exists', autospec=True, side_effect=exists),
            patch.object(
                Path,
                'is_symlink',
                autospec=True,
                side_effect=is_symlink,
            ),
            patch.object(Path, 'lstat', autospec=True, side_effect=lstat),
        ):
            yield

    def _symlink_lstat_patch(self, symlink_path):
        original_lstat = Path.lstat

        def lstat(path):
            if path == symlink_path:
                return Mock(st_mode=stat.S_IFLNK, st_dev=1, st_ino=98)
            return original_lstat(path)

        return patch.object(Path, 'lstat', autospec=True, side_effect=lstat)

    def _backup_mkdir_patch(self):
        original_mkdir = Path.mkdir
        backup_directory = self.db.parent / 'backups'

        def mkdir(path, *args, **kwargs):
            if path == backup_directory:
                raise OSError('private mkdir path')
            return original_mkdir(path, *args, **kwargs)

        return patch('core.remote_backup.Path.mkdir', autospec=True, side_effect=mkdir)

    def _backup_unlink_patch(self, *effects):
        original_unlink = Path.unlink
        remaining_effects = iter(effects)

        def unlink(path, *args, **kwargs):
            if path.suffix == '.sqlite3':
                try:
                    effect = next(remaining_effects)
                except StopIteration:
                    effect = None
                if isinstance(effect, BaseException):
                    raise effect
            return original_unlink(path, *args, **kwargs)

        return patch(
            'core.remote_backup.Path.unlink',
            autospec=True,
            side_effect=unlink,
        )

    @patch('core.remote_backup.backup_sqlite')
    def test_nonblocking_file_lock_rejects_concurrent_run(self, backup_mock):
        storage = Mock()
        lock_path = self.db.parent / '.lar-finance-r2-backup.lock'

        with FileLock(lock_path):
            with self.assertRaises(BackupAlreadyRunning):
                execute_remote_backup(self.config, storage, self.db, self.now)

        backup_mock.assert_not_called()
        storage.head_managed.assert_not_called()
