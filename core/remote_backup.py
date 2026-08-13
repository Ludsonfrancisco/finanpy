import hashlib
import re
import sqlite3
import sys
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from botocore.exceptions import BotoCoreError, ClientError
from filelock import FileLock, Timeout

from core.backup import backup_sqlite
from core.backup_catalog import build_object_key, select_retained_keys
from core.r2_storage import R2StorageError, RemoteObject

LOCAL_BACKUP_ERRORS = (OSError, ValueError, sqlite3.Error)
REMOTE_OPERATION_ERRORS = (OSError, BotoCoreError, ClientError, R2StorageError)
TEMPORARY_BACKUP_PATTERN = re.compile(
    r'\.lar-finance-r2-[A-Za-z0-9_-]+\.sqlite3'
)


class BackupAlreadyRunning(RuntimeError):
    error_code = 'lock_busy'
    stage = 'lock'


class BackupVerificationError(RuntimeError):
    def __init__(self, message, *, error_code='upload_failed', stage='upload'):
        super().__init__(message)
        self.error_code = error_code
        self.stage = stage


class BackupRetentionError(RuntimeError):
    error_code = 'retention_failed'
    stage = 'retention'


@dataclass(frozen=True)
class BackupOutcome:
    status: str
    key: str
    size: int
    sha256: str
    deleted_keys: tuple[str, ...]

    @classmethod
    def already_exists(
        cls,
        remote: RemoteObject,
        deleted_keys: tuple[str, ...] = (),
    ) -> 'BackupOutcome':
        return cls(
            status='already_exists',
            key=remote.key,
            size=remote.size,
            sha256=remote.sha256,
            deleted_keys=deleted_keys,
        )

    @classmethod
    def created(
        cls,
        remote: RemoteObject,
        deleted_keys: tuple[str, ...],
    ) -> 'BackupOutcome':
        return cls(
            status='created',
            key=remote.key,
            size=remote.size,
            sha256=remote.sha256,
            deleted_keys=deleted_keys,
        )


def create_unused_temporary_path(directory: Path) -> Path:
    handle = None
    path = None
    try:
        directory.mkdir(parents=True, exist_ok=True)
        handle = tempfile.NamedTemporaryFile(
            dir=directory,
            prefix='.lar-finance-r2-',
            suffix='.sqlite3',
            delete=False,
        )
        path = Path(handle.name)
        handle.close()
        handle = None
        path.unlink()
        return path
    except OSError:
        if handle is not None:
            try:
                handle.close()
            except OSError:
                pass
        if path is not None:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        raise BackupVerificationError(
            'Temporary backup path could not be reserved.',
            error_code='copy_failed',
            stage='copy',
        ) from None


@contextmanager
def temporary_backup_path(directory: Path):
    path = create_unused_temporary_path(directory)
    try:
        yield path
    finally:
        primary_error = sys.exc_info()[1]
        try:
            path.unlink(missing_ok=True)
        except OSError:
            cleanup_error = BackupVerificationError(
                'Temporary backup could not be cleaned up.',
                error_code='cleanup_failed',
                stage='cleanup',
            )
            if primary_error is None:
                raise cleanup_error from None
            if isinstance(primary_error, Exception):
                raise cleanup_error from primary_error


def cleanup_stale_temporary_backups(directory: Path) -> None:
    try:
        if not directory.exists():
            return
        if directory.is_symlink() or not directory.is_dir():
            raise OSError
        resolved_directory = directory.resolve(strict=True)
        for candidate in directory.iterdir():
            if (
                TEMPORARY_BACKUP_PATTERN.fullmatch(candidate.name) is None
                or candidate.is_symlink()
            ):
                continue
            resolved_candidate = candidate.resolve(strict=True)
            if (
                resolved_candidate.parent != resolved_directory
                or not resolved_candidate.is_file()
            ):
                continue
            resolved_candidate.unlink()
    except OSError:
        raise BackupVerificationError(
            'Temporary backup residue could not be cleaned up.',
            error_code='cleanup_failed',
            stage='cleanup',
        ) from None


def file_identity(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    with path.open('rb') as backup_file:
        for chunk in iter(lambda: backup_file.read(1024 * 1024), b''):
            size += len(chunk)
            digest.update(chunk)
    return size, digest.hexdigest()


def delete_expired_oldest_first(storage, objects, retained) -> tuple[str, ...]:
    expired = sorted(
        (item for item in objects if item.key not in retained),
        key=lambda item: (item.backup_date, item.key),
    )
    deleted = []
    for item in expired:
        storage.delete(item.key)
        deleted.append(item.key)
    return tuple(deleted)


def enforce_retention(config, storage) -> tuple[str, ...]:
    try:
        objects = storage.list_managed()
        retained = select_retained_keys(
            objects,
            config.daily_retention,
            config.weekly_retention,
            config.monthly_retention,
        )
        return delete_expired_oldest_first(storage, objects, retained)
    except REMOTE_OPERATION_ERRORS:
        raise BackupRetentionError(
            'Remote backup retention could not be completed.'
        ) from None


@contextmanager
def _backup_lock(lock):
    try:
        lock.acquire()
    except Timeout:
        raise BackupAlreadyRunning(
            'Another backup execution is already running.'
        ) from None
    try:
        yield
    finally:
        lock.release()


def execute_remote_backup(config, storage, database_path, now) -> BackupOutcome:
    source = Path(database_path).resolve()
    backup_date = now.astimezone(config.time_zone).date()
    key = build_object_key(config.prefix, backup_date)
    lock = FileLock(str(source.parent / '.lar-finance-r2-backup.lock'), timeout=0)

    with _backup_lock(lock):
        backup_directory = source.parent / 'backups'
        cleanup_stale_temporary_backups(backup_directory)
        try:
            existing = storage.head_managed(key)
        except REMOTE_OPERATION_ERRORS:
            raise BackupVerificationError(
                'Existing remote backup could not be verified.',
                error_code='remote_invalid',
                stage='preflight',
            ) from None
        if existing is not None:
            deleted = enforce_retention(config, storage)
            return BackupOutcome.already_exists(existing, deleted)

        with temporary_backup_path(backup_directory) as temporary_path:
            try:
                backup_sqlite(source, temporary_path)
                _, sha256 = file_identity(temporary_path)
            except LOCAL_BACKUP_ERRORS:
                raise BackupVerificationError(
                    'Local SQLite backup could not be verified.',
                    error_code='copy_failed',
                    stage='copy',
                ) from None

            try:
                remote = storage.upload_and_verify(
                    temporary_path,
                    key,
                    backup_date,
                    sha256,
                )
            except REMOTE_OPERATION_ERRORS:
                raise BackupVerificationError(
                    'Remote backup upload could not be verified.'
                ) from None

            deleted = enforce_retention(config, storage)
            return BackupOutcome.created(remote, deleted)
