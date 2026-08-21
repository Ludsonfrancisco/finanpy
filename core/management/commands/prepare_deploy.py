import json
import logging
import time
from datetime import UTC, datetime

from django.core.management.base import BaseCommand, CommandError

from core.deploy import DeployPreparationError, prepare_deploy

logger = logging.getLogger('lar_finance.deploy')

ALLOWED_DEPLOY_EVENT_KEYS = {
    'timestamp',
    'event',
    'version',
    'stage',
    'status',
    'error_code',
    'duration_ms',
}


def serialize_deploy_event(**fields) -> str:
    event = {key: fields.get(key) for key in ALLOWED_DEPLOY_EVENT_KEYS}
    event['timestamp'] = datetime.now(UTC).isoformat()
    return json.dumps(event, separators=(',', ':'), sort_keys=True)


def duration_ms(started: float) -> int:
    return max(0, round((time.monotonic() - started) * 1000))


class Command(BaseCommand):
    help = 'Prepare the SQLite release and fail before Supervisor on error.'

    def handle(self, *args, **options):
        started = time.monotonic()
        try:
            outcome = prepare_deploy()
        except DeployPreparationError as error:
            logger.error(
                serialize_deploy_event(
                    event='deploy_prepare_failed',
                    version='invalid',
                    stage=error.stage,
                    error_code=error.error_code,
                    duration_ms=duration_ms(started),
                    status='error',
                )
            )
            raise CommandError(
                f'Deploy preparation failed [{error.error_code}].'
            ) from None
        logger.info(
            serialize_deploy_event(
                event='deploy_prepare_finished',
                version=outcome.version,
                stage='complete',
                error_code=None,
                duration_ms=duration_ms(started),
                status='ok',
            )
        )
