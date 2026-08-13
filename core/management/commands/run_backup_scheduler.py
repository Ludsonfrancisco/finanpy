import logging
import os
import signal
import time
from datetime import datetime

from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError

from core.backup_config import R2BackupConfig
from core.backup_scheduler import LastAttempt, decide_next_action

logger = logging.getLogger('lar_finance.backup')


def _handle_sigterm(signum, frame):
    raise KeyboardInterrupt


class Command(BaseCommand):
    help = 'Run the recoverable daily R2 backup scheduler.'

    def handle(self, *args, **options):
        previous_sigterm_handler = signal.getsignal(signal.SIGTERM)
        signal.signal(signal.SIGTERM, _handle_sigterm)

        try:
            config = R2BackupConfig.from_env(os.environ)
            last_attempt = None
            while True:
                now = datetime.now(config.time_zone)
                decision = decide_next_action(
                    now,
                    config.schedule_time,
                    config.time_zone,
                    config.retry_seconds,
                    last_attempt,
                )
                if decision.run_now:
                    backup_date = now.astimezone(config.time_zone).date()
                    try:
                        call_command('backup_to_r2')
                    except CommandError:
                        last_attempt = LastAttempt(
                            backup_date=backup_date,
                            completed_at=datetime.now(config.time_zone),
                            succeeded=False,
                        )
                        logger.error('backup_scheduler_failed')
                    else:
                        last_attempt = LastAttempt(
                            backup_date=backup_date,
                            completed_at=datetime.now(config.time_zone),
                            succeeded=True,
                        )
                        logger.info('backup_scheduler_succeeded')
                    continue

                logger.info('backup_scheduler_wait')
                time.sleep(decision.sleep_seconds)
        except KeyboardInterrupt:
            logger.info('backup_scheduler_stopped')
        finally:
            signal.signal(signal.SIGTERM, previous_sigterm_handler)
