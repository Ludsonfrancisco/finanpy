import json
import sqlite3
import tempfile
from contextlib import ExitStack, closing
from datetime import UTC, datetime
from io import StringIO
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, call, patch

from django.conf import settings
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase, override_settings

from core.backup_config import BackupConfigurationError
from core.deploy import (
    DatabaseState,
    DeployPreparationError,
    classify_database,
    has_pending_migrations,
    prepare_deploy,
    sqlite_integrity_check,
    validated_database_path,
)
from core.management.commands.prepare_deploy import (
    ALLOWED_DEPLOY_EVENT_KEYS,
    serialize_deploy_event,
)
from core.r2_storage import R2StorageError
from core.remote_backup import (
    BackupAlreadyRunning,
    BackupRetentionError,
    BackupVerificationError,
)

FIXED_NOW = datetime(2026, 8, 21, 18, 30, tzinfo=UTC)
VERSION = 'a' * 40


def create_sqlite(path: Path, statements=()):
    with closing(sqlite3.connect(path)) as database:
        for statement in statements:
            database.execute(statement)
        database.commit()


class DatabasePreflightTest(SimpleTestCase):
    def test_missing_database_is_new(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, 'missing.sqlite3')

            self.assertEqual(classify_database(path), DatabaseState.NEW)
            self.assertFalse(path.exists())

    def test_empty_sqlite_database_is_new(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, 'empty.sqlite3')
            create_sqlite(path)

            self.assertEqual(classify_database(path), DatabaseState.NEW)

    def test_database_with_migration_table_is_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, 'ready.sqlite3')
            create_sqlite(path, ('CREATE TABLE django_migrations (id INTEGER)',))

            self.assertEqual(classify_database(path), DatabaseState.READY)

    def test_nonempty_database_without_migration_table_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, 'unknown.sqlite3')
            create_sqlite(path, ('CREATE TABLE household (id INTEGER)',))

            with self.assertRaises(DeployPreparationError) as raised:
                classify_database(path)

        self.assertEqual(raised.exception.error_code, 'database_unrecognized')
        self.assertEqual(raised.exception.stage, 'preflight')

    def test_corrupt_sqlite_fails_before_migration_detection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, 'corrupt.sqlite3')
            path.write_bytes(b'not sqlite')
            with (
                patch('core.deploy.has_pending_migrations') as detector,
                patch('core.deploy.execute_deploy_backup') as backup,
                patch('core.deploy.call_command') as command,
                patch.dict(settings.DATABASES['default'], {'NAME': path}),
                override_settings(DEBUG=True),
            ):
                with self.assertRaises(DeployPreparationError) as raised:
                    prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(raised.exception.error_code, 'sqlite_integrity_failed')
        self.assertEqual(raised.exception.stage, 'integrity')
        detector.assert_not_called()
        backup.assert_not_called()
        command.assert_not_called()

    def test_integrity_check_rejects_corruption_without_original_message(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, 'private-name.sqlite3')
            path.write_bytes(b'not sqlite')

            with self.assertRaises(DeployPreparationError) as raised:
                sqlite_integrity_check(path)

        self.assertEqual(str(raised.exception), 'Deploy preparation failed [sqlite_integrity_failed].')
        self.assertNotIn('private-name', str(raised.exception))

    def test_directory_and_symlink_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            regular = root / 'regular.sqlite3'
            create_sqlite(regular)
            candidates = [root / 'database-directory']
            candidates[0].mkdir()
            symlink = root / 'database-link.sqlite3'
            try:
                symlink.symlink_to(regular)
            except OSError:
                symlink = None
            if symlink is not None:
                candidates.append(symlink)

            for candidate in candidates:
                with self.subTest(candidate=candidate.name):
                    with self.assertRaises(DeployPreparationError) as raised:
                        classify_database(candidate)
                    self.assertEqual(raised.exception.error_code, 'database_path_invalid')

    @override_settings(DEBUG=False)
    def test_production_rejects_path_outside_data_volume(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory, 'app-data')
            outside_parent = Path(directory, 'outside', 'nested')
            with (
                patch('core.deploy.PRODUCTION_DATA_ROOT', root),
                self.assertRaises(DeployPreparationError) as raised,
            ):
                validated_database_path(outside_parent / 'db.sqlite3', debug=False)

            self.assertFalse(outside_parent.exists())

        self.assertEqual(raised.exception.error_code, 'database_path_invalid')

    def test_production_accepts_resolved_path_inside_data_volume(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory, 'app-data')
            path = root / 'nested' / 'db.sqlite3'
            with patch('core.deploy.PRODUCTION_DATA_ROOT', root):
                result = validated_database_path(path, debug=False)

            self.assertEqual(result, path)
            self.assertTrue(path.parent.is_dir())

    def test_production_rejects_relative_path_without_creating_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            relative = Path('private-relative', 'db.sqlite3')
            with (
                patch('core.deploy.PRODUCTION_DATA_ROOT', Path(directory)),
                self.assertRaises(DeployPreparationError) as raised,
            ):
                validated_database_path(relative, debug=False)

        self.assertEqual(raised.exception.error_code, 'database_path_invalid')

    def test_production_keeps_symlink_visible_to_database_classification(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory, 'app-data')
            root.mkdir()
            target = root / 'target.sqlite3'
            create_sqlite(target)
            alias = root / 'database.sqlite3'
            try:
                alias.symlink_to(target)
            except OSError:
                self.skipTest('The platform does not permit symlink creation.')

            with patch('core.deploy.PRODUCTION_DATA_ROOT', root):
                validated = validated_database_path(alias, debug=False)
                with self.assertRaises(DeployPreparationError) as raised:
                    classify_database(validated)

        self.assertEqual(validated, alias)
        self.assertEqual(raised.exception.error_code, 'database_path_invalid')


class MigrationDetectionTest(SimpleTestCase):
    @patch('core.deploy.MigrationExecutor')
    def test_reports_pending_migrations_from_leaf_plan(self, executor_type):
        executor = executor_type.return_value
        executor.loader.graph.leaf_nodes.return_value = [('app', '0002')]
        executor.migration_plan.return_value = [('migration', False)]

        self.assertTrue(has_pending_migrations())
        executor.migration_plan.assert_called_once_with([('app', '0002')])

    @patch('core.deploy.MigrationExecutor')
    def test_reports_no_pending_migrations(self, executor_type):
        executor = executor_type.return_value
        executor.loader.graph.leaf_nodes.return_value = [('app', '0001')]
        executor.migration_plan.return_value = []

        self.assertFalse(has_pending_migrations())


class DeployOrchestrationTest(SimpleTestCase):
    def orchestrator_patches(self, *, state=DatabaseState.READY, pending=True):
        stack = ExitStack()
        mocks = SimpleNamespace(
            database_path=stack.enter_context(
                patch('core.deploy.validated_database_path', return_value=Path('test.sqlite3'))
            ),
            classify=stack.enter_context(
                patch('core.deploy.classify_database', return_value=state)
            ),
            pending=stack.enter_context(
                patch('core.deploy.has_pending_migrations', return_value=pending)
            ),
            config=stack.enter_context(
                patch('core.deploy.R2BackupConfig.from_env', return_value=Mock())
            ),
            storage=stack.enter_context(
                patch('core.deploy.R2Storage.from_config', return_value=Mock())
            ),
            command=stack.enter_context(patch('core.deploy.call_command')),
            backup=stack.enter_context(patch('core.deploy.execute_deploy_backup')),
        )
        return stack, mocks

    @override_settings(DEBUG=True)
    def test_existing_database_backs_up_before_migrate(self):
        stack, mocks = self.orchestrator_patches()
        with stack:
            events = []
            mocks.backup.side_effect = (
                lambda *args, **kwargs: events.append('backup')
                or SimpleNamespace(key='production/deploy/verified.sqlite3')
            )
            mocks.command.side_effect = lambda name, **kwargs: events.append(name)

            result = prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(
            events,
            ['backup', 'migrate', 'audit_household_integrity', 'collectstatic'],
        )
        self.assertTrue(result.migrations_applied)
        self.assertEqual(result.backup_key, 'production/deploy/verified.sqlite3')

    @override_settings(DEBUG=True)
    def test_new_database_migrates_without_backup(self):
        stack, mocks = self.orchestrator_patches(state=DatabaseState.NEW, pending=True)
        with stack:
            result = prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(
            mocks.command.call_args_list,
            [
                call('migrate', interactive=False),
                call('audit_household_integrity'),
                call('collectstatic', interactive=False),
            ],
        )
        mocks.backup.assert_not_called()
        self.assertTrue(result.migrations_applied)
        self.assertIsNone(result.backup_key)

    @override_settings(DEBUG=True)
    def test_ready_database_without_pending_migration_skips_backup_and_migrate(self):
        stack, mocks = self.orchestrator_patches(state=DatabaseState.READY, pending=False)
        with stack:
            result = prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(
            mocks.command.call_args_list,
            [call('audit_household_integrity'), call('collectstatic', interactive=False)],
        )
        mocks.backup.assert_not_called()
        self.assertFalse(result.migrations_applied)

    @override_settings(DEBUG=True)
    def test_development_version_is_allowed(self):
        stack, _ = self.orchestrator_patches(state=DatabaseState.NEW, pending=False)
        with stack:
            outcome = prepare_deploy(environ={'APP_VERSION': 'development'}, now=FIXED_NOW)

        self.assertEqual(outcome.version, 'development')

    @override_settings(DEBUG=False)
    def test_production_rejects_invalid_version_before_database_path(self):
        with patch('core.deploy.validated_database_path') as database_path:
            with self.assertRaises(DeployPreparationError) as raised:
                prepare_deploy(environ={'APP_VERSION': 'development'}, now=FIXED_NOW)

        self.assertEqual(raised.exception.error_code, 'version_invalid')
        self.assertEqual(raised.exception.stage, 'configuration')
        database_path.assert_not_called()

    @override_settings(DEBUG=True)
    def test_backup_receives_config_storage_database_time_and_version(self):
        stack, mocks = self.orchestrator_patches()
        with stack:
            mocks.backup.return_value = SimpleNamespace(key='verified-key')
            prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        mocks.backup.assert_called_once_with(
            mocks.config.return_value,
            mocks.storage.return_value,
            Path('test.sqlite3'),
            FIXED_NOW,
            VERSION,
        )

    @override_settings(DEBUG=True)
    def test_backup_failure_prevents_migrate(self):
        stack, mocks = self.orchestrator_patches()
        with stack:
            mocks.backup.side_effect = BackupVerificationError('secret remote details')
            with self.assertRaises(DeployPreparationError) as raised:
                prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(raised.exception.error_code, 'backup_failed')
        self.assertNotIn('secret remote details', str(raised.exception))
        mocks.command.assert_not_called()

    @override_settings(DEBUG=True)
    def test_migration_detection_failure_prevents_backup_and_commands(self):
        stack, mocks = self.orchestrator_patches()
        with stack:
            mocks.pending.side_effect = sqlite3.OperationalError(
                'private database path and values'
            )
            with self.assertRaises(DeployPreparationError) as raised:
                prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(raised.exception.error_code, 'preflight_failed')
        self.assertEqual(raised.exception.stage, 'preflight')
        self.assertNotIn('private database path', str(raised.exception))
        mocks.backup.assert_not_called()
        mocks.command.assert_not_called()

    @override_settings(DEBUG=True)
    def test_known_backup_failures_are_safely_translated(self):
        cases = (
            (BackupConfigurationError('secret'), 'configuration_invalid'),
            (BackupAlreadyRunning('private lock'), 'lock_busy'),
            (BackupRetentionError('secret'), 'backup_failed'),
            (R2StorageError('secret'), 'backup_failed'),
            (OSError('private path'), 'backup_failed'),
        )
        for error, expected_code in cases:
            with self.subTest(error=type(error).__name__):
                stack, mocks = self.orchestrator_patches()
                with stack:
                    if isinstance(error, BackupConfigurationError):
                        mocks.config.side_effect = error
                    elif isinstance(error, BackupAlreadyRunning):
                        mocks.backup.side_effect = error
                    elif isinstance(error, R2StorageError):
                        mocks.storage.side_effect = error
                    else:
                        mocks.backup.side_effect = error
                    with self.assertRaises(DeployPreparationError) as raised:
                        prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

                self.assertEqual(raised.exception.error_code, expected_code)
                self.assertEqual(raised.exception.stage, 'backup')
                self.assertNotIn('secret', str(raised.exception))
                mocks.command.assert_not_called()

    @override_settings(DEBUG=True)
    def test_migration_failure_prevents_later_stages(self):
        stack, mocks = self.orchestrator_patches(state=DatabaseState.NEW)
        with stack:
            mocks.command.side_effect = CommandError('private migration details')
            with self.assertRaises(DeployPreparationError) as raised:
                prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(mocks.command.call_args_list, [call('migrate', interactive=False)])
        self.assertEqual(raised.exception.error_code, 'migration_failed')
        self.assertNotIn('private migration details', str(raised.exception))

    @override_settings(DEBUG=True)
    def test_audit_failure_prevents_collectstatic(self):
        stack, mocks = self.orchestrator_patches(state=DatabaseState.NEW)
        with stack:
            mocks.command.side_effect = [None, CommandError('private audit details')]
            with self.assertRaises(DeployPreparationError) as raised:
                prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(
            mocks.command.call_args_list,
            [call('migrate', interactive=False), call('audit_household_integrity')],
        )
        self.assertEqual(raised.exception.error_code, 'audit_failed')

    @override_settings(DEBUG=True)
    def test_collectstatic_failure_is_terminal(self):
        stack, mocks = self.orchestrator_patches(state=DatabaseState.NEW)
        with stack:
            mocks.command.side_effect = [None, None, CommandError('private static path')]
            with self.assertRaises(DeployPreparationError) as raised:
                prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(
            mocks.command.call_args_list,
            [
                call('migrate', interactive=False),
                call('audit_household_integrity'),
                call('collectstatic', interactive=False),
            ],
        )
        self.assertEqual(raised.exception.error_code, 'collectstatic_failed')

    @override_settings(DEBUG=True)
    def test_keyboard_interrupt_is_not_translated(self):
        stack, mocks = self.orchestrator_patches(state=DatabaseState.NEW)
        with stack:
            mocks.command.side_effect = KeyboardInterrupt
            with self.assertRaises(KeyboardInterrupt):
                prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

    @override_settings(DEBUG=True)
    def test_system_exit_is_not_translated(self):
        stack, mocks = self.orchestrator_patches(state=DatabaseState.NEW)
        with stack:
            mocks.command.side_effect = SystemExit(2)
            with self.assertRaises(SystemExit) as raised:
                prepare_deploy(environ={'APP_VERSION': VERSION}, now=FIXED_NOW)

        self.assertEqual(raised.exception.code, 2)


class SafeDeployEventTest(SimpleTestCase):
    def test_event_has_exact_allowlisted_keys_and_no_private_values(self):
        payload = serialize_deploy_event(
            event='deploy_prepare_failed',
            version='invalid',
            stage='backup',
            status='error',
            error_code='backup_failed',
            duration_ms=12,
            database_path='/app/data/db.sqlite3',
            secret='secret-access-value',
            email='user@example.com',
            amount='R$ 1.234,56',
            merchant='Mercado do bairro',
        )

        self.assertEqual(set(json.loads(payload)), ALLOWED_DEPLOY_EVENT_KEYS)
        for forbidden in (
            'secret-access-value',
            'user@example.com',
            '/app/data/db.sqlite3',
            'R$ 1.234,56',
            'Mercado do bairro',
        ):
            self.assertNotIn(forbidden, payload)

    def test_duration_is_nonnegative(self):
        with patch('core.management.commands.prepare_deploy.time.monotonic', side_effect=[3, 2]):
            from core.management.commands.prepare_deploy import duration_ms

            self.assertEqual(duration_ms(3), 0)


class PrepareDeployCommandTest(SimpleTestCase):
    @patch(
        'core.management.commands.prepare_deploy.prepare_deploy',
        side_effect=DeployPreparationError(
            error_code='configuration_invalid',
            stage='backup',
        ),
    )
    def test_command_returns_safe_nonzero_error(self, prepare):
        stderr = StringIO()
        with self.assertLogs('lar_finance.deploy', level='ERROR') as captured:
            with self.assertRaisesRegex(
                CommandError,
                r'^Deploy preparation failed \[configuration_invalid\]\.$',
            ):
                call_command('prepare_deploy', stderr=stderr)
        event = json.loads(captured.output[0].split(':', 2)[-1])
        self.assertEqual(event['error_code'], 'configuration_invalid')
        self.assertEqual(set(event), ALLOWED_DEPLOY_EVENT_KEYS)
        prepare.assert_called_once_with()

    @patch('core.management.commands.prepare_deploy.prepare_deploy')
    def test_command_logs_safe_success_event(self, prepare):
        prepare.return_value = SimpleNamespace(version=VERSION)

        with self.assertLogs('lar_finance.deploy', level='INFO') as captured:
            call_command('prepare_deploy')

        event = json.loads(captured.output[0].split(':', 2)[-1])
        self.assertEqual(event['event'], 'deploy_prepare_finished')
        self.assertEqual(event['version'], VERSION)
        self.assertEqual(event['stage'], 'complete')
        self.assertEqual(event['status'], 'ok')
        self.assertEqual(set(event), ALLOWED_DEPLOY_EVENT_KEYS)

    @patch('core.management.commands.prepare_deploy.prepare_deploy', side_effect=KeyboardInterrupt)
    def test_command_preserves_keyboard_interrupt(self, prepare):
        with self.assertRaises(KeyboardInterrupt):
            call_command('prepare_deploy')

    @patch('core.management.commands.prepare_deploy.prepare_deploy', side_effect=SystemExit(2))
    def test_command_preserves_system_exit(self, prepare):
        with self.assertRaises(SystemExit) as raised:
            call_command('prepare_deploy')

        self.assertEqual(raised.exception.code, 2)
