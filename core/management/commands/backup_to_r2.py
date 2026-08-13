import logging
import os
import time
from datetime import UTC, datetime
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from core.backup_config import BackupConfigurationError, R2BackupConfig
from core.backup_logging import serialize_backup_event
from core.r2_storage import R2Storage
from core.remote_backup import (
    BackupAlreadyRunning,
    BackupRetentionError,
    BackupVerificationError,
    execute_remote_backup,
)

logger = logging.getLogger('lar_finance.backup')
KNOWN_BACKUP_ERRORS = (
    BackupConfigurationError,
    BackupAlreadyRunning,
    BackupVerificationError,
    BackupRetentionError,
)


class Command(BaseCommand):
    help = 'Create, verify, upload, and retain the daily R2 SQLite backup.'

    def handle(self, *args, **options):
        started = time.monotonic()
        try:
            config = R2BackupConfig.from_env(os.environ)
            storage = R2Storage.from_config(config)
            database_path = Path(settings.DATABASES['default']['NAME'])
            now = datetime.now(UTC)
            outcome = execute_remote_backup(
                config,
                storage,
                database_path,
                now,
            )
        except KNOWN_BACKUP_ERRORS as error:
            duration_ms = _duration_ms(started)
            error_code, stage = _error_details(error)
            logger.error(
                serialize_backup_event(
                    timestamp=datetime.now(UTC),
                    event='backup_failed',
                    status='error',
                    stage=stage,
                    duration_ms=duration_ms,
                    error_code=error_code,
                )
            )
            raise CommandError(f'Backup failed [{error_code}].') from None

        logger.info(
            serialize_backup_event(
                timestamp=datetime.now(UTC),
                event='backup_finished',
                status=outcome.status,
                stage='complete',
                key=outcome.key,
                size=outcome.size,
                sha256=outcome.sha256,
                duration_ms=_duration_ms(started),
                deleted_count=len(outcome.deleted_keys),
            )
        )


def _duration_ms(started: float) -> int:
    return max(0, round((time.monotonic() - started) * 1000))


def _error_details(error) -> tuple[str, str]:
    if isinstance(error, BackupConfigurationError):
        return 'configuration_invalid', 'configuration'
    return error.error_code, error.stage
