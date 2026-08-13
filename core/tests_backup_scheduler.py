from datetime import datetime, time
from unittest.mock import patch
from zoneinfo import ZoneInfo

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase

from core.backup_config import R2BackupConfig
from core.backup_scheduler import LastAttempt, decide_next_action

SAO_PAULO = ZoneInfo('America/Sao_Paulo')


class BackupSchedulerDecisionTest(SimpleTestCase):
    schedule_time = time(3)
    retry_seconds = 3600

    def decide(self, now, last_attempt=None):
        return decide_next_action(
            now,
            self.schedule_time,
            SAO_PAULO,
            self.retry_seconds,
            last_attempt,
        )

    def test_sleeps_until_today_schedule_before_window(self):
        decision = self.decide(datetime(2026, 8, 12, 2, tzinfo=SAO_PAULO))

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 3600)

    def test_runs_at_schedule_without_previous_attempt(self):
        decision = self.decide(datetime(2026, 8, 12, 3, tzinfo=SAO_PAULO))

        self.assertTrue(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 0)

    def test_runs_after_schedule_without_previous_attempt(self):
        decision = self.decide(datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO))

        self.assertTrue(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 0)

    def test_success_today_sleeps_until_tomorrow_schedule(self):
        now = datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO)
        last_attempt = LastAttempt(
            at=datetime(2026, 8, 12, 3, tzinfo=SAO_PAULO),
            succeeded=True,
        )

        decision = self.decide(now, last_attempt)

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 7 * 3600)

    def test_recent_failure_sleeps_only_until_retry(self):
        now = datetime(2026, 8, 12, 20, 30, tzinfo=SAO_PAULO)
        last_attempt = LastAttempt(
            at=datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO),
            succeeded=False,
        )

        decision = self.decide(now, last_attempt)

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 1800)

    def test_failure_retries_when_retry_instant_arrives(self):
        now = datetime(2026, 8, 12, 21, tzinfo=SAO_PAULO)
        last_attempt = LastAttempt(
            at=datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO),
            succeeded=False,
        )

        decision = self.decide(now, last_attempt)

        self.assertTrue(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 0)

    def test_restart_with_empty_memory_runs_after_schedule(self):
        decision = self.decide(datetime(2026, 8, 12, 21, tzinfo=SAO_PAULO))

        self.assertTrue(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 0)

    def test_previous_day_attempt_does_not_block_current_day(self):
        last_attempt = LastAttempt(
            at=datetime(2026, 8, 11, 3, tzinfo=SAO_PAULO),
            succeeded=True,
        )

        decision = self.decide(
            datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO),
            last_attempt,
        )

        self.assertTrue(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 0)

    def test_next_schedule_remains_local_three_across_dst(self):
        new_york = ZoneInfo('America/New_York')
        now = datetime(2026, 3, 7, 20, tzinfo=new_york)
        last_attempt = LastAttempt(
            at=datetime(2026, 3, 7, 3, tzinfo=new_york),
            succeeded=True,
        )

        decision = decide_next_action(
            now,
            self.schedule_time,
            new_york,
            self.retry_seconds,
            last_attempt,
        )

        wake_at = now.timestamp() + decision.sleep_seconds
        scheduled = datetime.fromtimestamp(wake_at, tz=new_york)
        self.assertTrue(scheduled.tzinfo is not None)
        self.assertEqual(scheduled, datetime(2026, 3, 8, 3, tzinfo=new_york))


class StopScheduler(Exception):
    pass


def stop_after_sleep(seconds):
    raise StopScheduler(seconds)


class BackupSchedulerCommandTest(SimpleTestCase):
    def setUp(self):
        self.config = R2BackupConfig(
            endpoint_url='https://account.invalid',
            access_key_id='private-access-id-sentinel',
            secret_access_key='private-secret-sentinel',
            bucket='backup-bucket',
            prefix='production',
            schedule_time=time(3),
            time_zone=SAO_PAULO,
        )

    @patch('core.management.commands.run_backup_scheduler.call_command')
    @patch('core.management.commands.run_backup_scheduler.time.sleep')
    @patch('core.management.commands.run_backup_scheduler.datetime')
    @patch('core.management.commands.run_backup_scheduler.R2BackupConfig.from_env')
    def test_runs_backup_after_schedule_then_sleeps_until_next_day(
        self,
        config_from_env,
        clock,
        sleeper,
        backup_command,
    ):
        config_from_env.return_value = self.config
        clock.now.return_value = datetime(2026, 8, 12, 3, tzinfo=SAO_PAULO)
        sleeper.side_effect = stop_after_sleep

        with self.assertRaises(StopScheduler) as stopped:
            call_command('run_backup_scheduler')

        backup_command.assert_called_once_with('backup_to_r2')
        self.assertEqual(stopped.exception.args, (86400.0,))

    @patch('core.management.commands.run_backup_scheduler.call_command')
    @patch('core.management.commands.run_backup_scheduler.time.sleep')
    @patch('core.management.commands.run_backup_scheduler.datetime')
    @patch('core.management.commands.run_backup_scheduler.R2BackupConfig.from_env')
    def test_command_error_records_failure_and_retries_without_exception_text(
        self,
        config_from_env,
        clock,
        sleeper,
        backup_command,
    ):
        config_from_env.return_value = self.config
        clock.now.return_value = datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO)
        sleeper.side_effect = stop_after_sleep
        backup_command.side_effect = CommandError('private backup failure')

        with (
            self.assertRaises(StopScheduler) as stopped,
            self.assertLogs('lar_finance.backup', level='INFO') as captured,
        ):
            call_command('run_backup_scheduler')

        backup_command.assert_called_once_with('backup_to_r2')
        self.assertEqual(stopped.exception.args, (3600.0,))
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_failed', output)
        self.assertNotIn('private backup failure', output)

    @patch('core.management.commands.run_backup_scheduler.call_command')
    @patch('core.management.commands.run_backup_scheduler.time.sleep')
    @patch('core.management.commands.run_backup_scheduler.datetime')
    @patch('core.management.commands.run_backup_scheduler.R2BackupConfig.from_env')
    def test_keyboard_interrupt_stops_cleanly(
        self,
        config_from_env,
        clock,
        sleeper,
        backup_command,
    ):
        config_from_env.return_value = self.config
        clock.now.return_value = datetime(2026, 8, 12, 2, tzinfo=SAO_PAULO)
        sleeper.side_effect = KeyboardInterrupt

        call_command('run_backup_scheduler')

        backup_command.assert_not_called()
