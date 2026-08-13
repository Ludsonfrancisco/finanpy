import logging
import signal
import time

from django.core.management.base import BaseCommand

from imports.services import (
    ImportBusyError,
    next_preview_purge_delay,
    purge_preview_records,
)

PURGE_INTERVAL_SECONDS = 60 * 60
PURGE_BUSY_RETRY_SECONDS = 60
logger = logging.getLogger('imports.preview_purge')


def _handle_sigterm(signum, frame):
    raise KeyboardInterrupt


class Command(BaseCommand):
    help = 'Continuously purge expired normalized OFX preview records.'

    def handle(self, *args, **options):
        previous_sigterm_handler = signal.getsignal(signal.SIGTERM)
        signal.signal(signal.SIGTERM, _handle_sigterm)
        try:
            while True:
                try:
                    deleted = purge_preview_records()
                except ImportBusyError:
                    logger.warning('import_preview_purge_busy')
                    delay = PURGE_BUSY_RETRY_SECONDS
                else:
                    self.stdout.write(f'purged_import_records={deleted}')
                    delay = next_preview_purge_delay(
                        max_delay_seconds=PURGE_INTERVAL_SECONDS
                    )
                time.sleep(delay)
        except KeyboardInterrupt:
            self.stdout.write('import_preview_purge_scheduler_stopped')
        finally:
            signal.signal(signal.SIGTERM, previous_sigterm_handler)
