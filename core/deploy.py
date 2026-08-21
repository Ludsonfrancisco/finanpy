import os
import sqlite3
import stat
from contextlib import closing
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from pathlib import Path
from typing import Mapping

from django.conf import settings
from django.core.management import call_command
from django.db import connection
from django.db.migrations.executor import MigrationExecutor

from core.backup_config import BackupConfigurationError, R2BackupConfig
from core.r2_storage import R2Storage, R2StorageError
from core.release import ReleaseVersionError, read_app_version, validate_app_version
from core.remote_backup import (
    BackupAlreadyRunning,
    BackupRetentionError,
    BackupVerificationError,
    execute_deploy_backup,
)


class DeployPreparationError(RuntimeError):
    def __init__(self, *, error_code: str, stage: str):
        super().__init__(f'Deploy preparation failed [{error_code}].')
        self.error_code = error_code
        self.stage = stage


class DatabaseState(StrEnum):
    NEW = 'new'
    READY = 'ready'


@dataclass(frozen=True)
class DeployOutcome:
    version: str
    database_state: DatabaseState
    migrations_applied: bool
    backup_key: str | None


PRODUCTION_DATA_ROOT = Path('/app/data')


def _readonly_sqlite_uri(path: Path) -> str:
    return f'{path.absolute().as_uri()}?mode=ro'


def sqlite_integrity_check(path: Path) -> None:
    try:
        with closing(sqlite3.connect(_readonly_sqlite_uri(path), uri=True)) as database:
            rows = database.execute('PRAGMA integrity_check').fetchall()
    except sqlite3.Error:
        raise DeployPreparationError(
            error_code='sqlite_integrity_failed',
            stage='integrity',
        ) from None
    if rows != [('ok',)]:
        raise DeployPreparationError(
            error_code='sqlite_integrity_failed',
            stage='integrity',
        )


def validated_database_path(value, *, debug: bool) -> Path:
    try:
        path = Path(value)
    except (TypeError, ValueError):
        raise DeployPreparationError(
            error_code='database_path_invalid',
            stage='configuration',
        ) from None

    if not debug:
        if not path.is_absolute():
            raise DeployPreparationError(
                error_code='database_path_invalid',
                stage='configuration',
            )
        try:
            root = PRODUCTION_DATA_ROOT.resolve(strict=False)
            resolved = path.resolve(strict=False)
            resolved.relative_to(root)
        except (OSError, RuntimeError, ValueError):
            raise DeployPreparationError(
                error_code='database_path_invalid',
                stage='configuration',
            ) from None

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        raise DeployPreparationError(
            error_code='database_path_invalid',
            stage='configuration',
        ) from None
    return path


def classify_database(path: Path) -> DatabaseState:
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        return DatabaseState.NEW
    except OSError:
        raise DeployPreparationError(
            error_code='database_path_invalid',
            stage='configuration',
        ) from None
    if stat.S_ISLNK(path_stat.st_mode) or not stat.S_ISREG(path_stat.st_mode):
        raise DeployPreparationError(
            error_code='database_path_invalid',
            stage='configuration',
        )

    sqlite_integrity_check(path)
    try:
        with closing(sqlite3.connect(_readonly_sqlite_uri(path), uri=True)) as database:
            tables = {
                row[0]
                for row in database.execute(
                    "SELECT name FROM sqlite_master "
                    "WHERE type='table' AND name NOT LIKE 'sqlite_%'"
                )
            }
    except sqlite3.Error:
        raise DeployPreparationError(
            error_code='sqlite_integrity_failed',
            stage='integrity',
        ) from None
    if not tables:
        return DatabaseState.NEW
    if 'django_migrations' not in tables:
        raise DeployPreparationError(
            error_code='database_unrecognized',
            stage='preflight',
        )
    return DatabaseState.READY


def has_pending_migrations() -> bool:
    executor = MigrationExecutor(connection)
    targets = executor.loader.graph.leaf_nodes()
    return bool(executor.migration_plan(targets))


def run_deploy_backup(
    source: Mapping[str, str],
    database_path: Path,
    instant: datetime,
    version: str,
) -> str:
    try:
        config = R2BackupConfig.from_env(source)
        storage = R2Storage.from_config(config)
        outcome = execute_deploy_backup(
            config,
            storage,
            database_path,
            instant,
            version,
        )
    except BackupConfigurationError:
        raise DeployPreparationError(
            error_code='configuration_invalid',
            stage='backup',
        ) from None
    except BackupAlreadyRunning:
        raise DeployPreparationError(
            error_code='lock_busy',
            stage='backup',
        ) from None
    except (
        BackupVerificationError,
        BackupRetentionError,
        R2StorageError,
        OSError,
    ):
        raise DeployPreparationError(
            error_code='backup_failed',
            stage='backup',
        ) from None
    return outcome.key


def run_command(name: str, *, stage: str, **options) -> None:
    try:
        call_command(name, **options)
    except Exception:
        raise DeployPreparationError(
            error_code=f'{stage}_failed',
            stage=stage,
        ) from None


def prepare_deploy(
    environ: Mapping[str, str] | None = None,
    now: datetime | None = None,
) -> DeployOutcome:
    source = os.environ if environ is None else environ
    instant = datetime.now(UTC) if now is None else now.astimezone(UTC)
    try:
        version = validate_app_version(
            read_app_version(source),
            debug=settings.DEBUG,
        )
    except ReleaseVersionError:
        raise DeployPreparationError(
            error_code='version_invalid',
            stage='configuration',
        ) from None

    database_path = validated_database_path(
        settings.DATABASES['default']['NAME'],
        debug=settings.DEBUG,
    )
    state = classify_database(database_path)
    try:
        pending = has_pending_migrations()
    except Exception:
        raise DeployPreparationError(
            error_code='preflight_failed',
            stage='preflight',
        ) from None
    backup_key = None

    if state is DatabaseState.READY and pending:
        backup_key = run_deploy_backup(source, database_path, instant, version)
    if pending:
        run_command('migrate', stage='migration', interactive=False)
    run_command('audit_household_integrity', stage='audit')
    run_command('collectstatic', stage='collectstatic', interactive=False)
    return DeployOutcome(version, state, pending, backup_key)
