import signal
from datetime import date, datetime, time
from unittest.mock import call, patch
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
            backup_date=date(2026, 8, 12),
            completed_at=datetime(2026, 8, 12, 3, tzinfo=SAO_PAULO),
            succeeded=True,
        )

        decision = self.decide(now, last_attempt)

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 7 * 3600)

    def test_recent_failure_sleeps_only_until_retry(self):
        now = datetime(2026, 8, 12, 20, 30, tzinfo=SAO_PAULO)
        last_attempt = LastAttempt(
            backup_date=date(2026, 8, 12),
            completed_at=datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO),
            succeeded=False,
        )

        decision = self.decide(now, last_attempt)

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 1800)

    def test_failure_retries_when_retry_instant_arrives(self):
        now = datetime(2026, 8, 12, 21, tzinfo=SAO_PAULO)
        last_attempt = LastAttempt(
            backup_date=date(2026, 8, 12),
            completed_at=datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO),
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
            backup_date=date(2026, 8, 11),
            completed_at=datetime(2026, 8, 11, 3, tzinfo=SAO_PAULO),
            succeeded=True,
        )

        decision = self.decide(
            datetime(2026, 8, 12, 20, tzinfo=SAO_PAULO),
            last_attempt,
        )

        self.assertTrue(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 0)

    def test_success_completed_after_midnight_does_not_cover_new_date(self):
        last_attempt = LastAttempt(
            backup_date=date(2026, 8, 12),
            completed_at=datetime(2026, 8, 13, 0, 1, tzinfo=SAO_PAULO),
            succeeded=True,
        )

        decision = self.decide(
            datetime(2026, 8, 13, 0, 1, tzinfo=SAO_PAULO),
            last_attempt,
        )

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 2 * 3600 + 59 * 60)

    def test_failure_completed_after_midnight_retries_from_completion(self):
        last_attempt = LastAttempt(
            backup_date=date(2026, 8, 12),
            completed_at=datetime(2026, 8, 13, 0, 1, tzinfo=SAO_PAULO),
            succeeded=False,
        )

        decision = self.decide(
            datetime(2026, 8, 13, 0, 31, tzinfo=SAO_PAULO),
            last_attempt,
        )

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 30 * 60)

    def test_next_schedule_remains_local_three_across_dst(self):
        new_york = ZoneInfo('America/New_York')
        now = datetime(2026, 3, 7, 20, tzinfo=new_york)
        last_attempt = LastAttempt(
            backup_date=date(2026, 3, 7),
            completed_at=datetime(2026, 3, 7, 3, tzinfo=new_york),
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

    def test_failure_retry_uses_elapsed_seconds_during_fall_fold(self):
        new_york = ZoneInfo('America/New_York')
        last_attempt = LastAttempt(
            backup_date=date(2026, 11, 1),
            completed_at=datetime(2026, 11, 1, 1, 30, tzinfo=new_york, fold=0),
            succeeded=False,
        )
        now = datetime(2026, 11, 1, 1, 45, tzinfo=new_york, fold=0)

        decision = decide_next_action(
            now,
            self.schedule_time,
            new_york,
            self.retry_seconds,
            last_attempt,
        )

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 2700)

    def test_success_during_fall_fold_sleeps_until_tomorrow_without_busy_loop(self):
        new_york = ZoneInfo('America/New_York')
        last_attempt = LastAttempt(
            backup_date=date(2026, 11, 1),
            completed_at=datetime(2026, 11, 1, 1, 30, tzinfo=new_york, fold=0),
            succeeded=True,
        )
        now = datetime(2026, 11, 1, 1, 45, tzinfo=new_york, fold=1)

        decision = decide_next_action(
            now,
            time(1, 30),
            new_york,
            self.retry_seconds,
            last_attempt,
        )

        self.assertFalse(decision.run_now)
        self.assertGreater(decision.sleep_seconds, 0)
        wake_at = datetime.fromtimestamp(
            now.timestamp() + decision.sleep_seconds,
            new_york,
        )
        self.assertEqual(wake_at, datetime(2026, 11, 2, 1, 30, tzinfo=new_york))
        self.assertEqual(wake_at.fold, 0)

    def test_ambiguous_schedule_uses_first_occurrence(self):
        new_york = ZoneInfo('America/New_York')
        now = datetime(2026, 11, 1, 0, 30, tzinfo=new_york)

        decision = decide_next_action(
            now,
            time(1, 30),
            new_york,
            self.retry_seconds,
            None,
        )

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 3600)
        wake_at = datetime.fromtimestamp(
            now.timestamp() + decision.sleep_seconds,
            new_york,
        )
        self.assertEqual(wake_at, datetime(2026, 11, 1, 1, 30, tzinfo=new_york))
        self.assertEqual(wake_at.fold, 0)

    def test_nonexistent_schedule_normalizes_forward_through_spring_gap(self):
        new_york = ZoneInfo('America/New_York')
        now = datetime(2026, 3, 8, 1, tzinfo=new_york)

        decision = decide_next_action(
            now,
            time(2, 30),
            new_york,
            self.retry_seconds,
            None,
        )

        self.assertFalse(decision.run_now)
        self.assertEqual(decision.sleep_seconds, 5400)
        wake_at = datetime.fromtimestamp(
            now.timestamp() + decision.sleep_seconds,
            new_york,
        )
        self.assertEqual(wake_at, datetime(2026, 3, 8, 3, 30, tzinfo=new_york))


class StopScheduler(Exception):
    pass


def stop_after_sleep(seconds):
    raise StopScheduler(seconds)


class BackupSchedulerCommandTest(SimpleTestCase):
    def setUp(self):
        self.config = R2BackupConfig(
            endpoint_url='https://private-endpoint.invalid',
            access_key_id='private-access-id-sentinel',
            secret_access_key='private-secret-sentinel',
            bucket='private-bucket-sentinel',
            prefix='private-prefix-sentinel',
            schedule_time=time(3),
            time_zone=SAO_PAULO,
        )
        self.sensitive_values = (
            self.config.access_key_id,
            self.config.secret_access_key,
            self.config.endpoint_url,
            self.config.bucket,
            self.config.prefix,
            'private sqlite content',
            'private financial description',
            'private financial amount',
            'private financial balance',
            'private email',
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

        with (
            self.assertRaises(StopScheduler) as stopped,
            self.assertLogs('lar_finance.backup', level='INFO') as captured,
        ):
            call_command('run_backup_scheduler')

        backup_command.assert_called_once_with('backup_to_r2')
        self.assertEqual(stopped.exception.args, (86400.0,))
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_succeeded', output)
        self.assertIn('backup_scheduler_wait', output)
        self.assertNotIn('backup_scheduler_failed', output)

    @patch('core.management.commands.run_backup_scheduler.call_command')
    @patch('core.management.commands.run_backup_scheduler.time.sleep')
    @patch('core.management.commands.run_backup_scheduler.datetime')
    @patch('core.management.commands.run_backup_scheduler.R2BackupConfig.from_env')
    def test_success_started_before_midnight_does_not_cover_completion_date(
        self,
        config_from_env,
        clock,
        sleeper,
        backup_command,
    ):
        config_from_env.return_value = self.config
        timeline = []
        timestamps = iter((
            datetime(2026, 8, 12, 23, 59, tzinfo=SAO_PAULO),
            datetime(2026, 8, 13, 0, 1, tzinfo=SAO_PAULO),
            datetime(2026, 8, 13, 0, 1, tzinfo=SAO_PAULO),
        ))

        def now_after_backup(*args):
            timeline.append('clock')
            return next(timestamps)

        def successful_backup(*args):
            timeline.append('backup')

        clock.now.side_effect = now_after_backup
        sleeper.side_effect = stop_after_sleep
        backup_command.side_effect = successful_backup

        with (
            self.assertRaises(StopScheduler) as stopped,
            self.assertLogs('lar_finance.backup', level='INFO') as captured,
        ):
            call_command('run_backup_scheduler')

        backup_command.assert_called_once_with('backup_to_r2')
        self.assertEqual(stopped.exception.args, (2 * 3600.0 + 59 * 60.0,))
        self.assertEqual(timeline, ['clock', 'backup', 'clock', 'clock'])
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_succeeded', output)
        self.assertIn('backup_scheduler_wait', output)
        self.assertNotIn('backup_scheduler_failed', output)

    @patch('core.management.commands.run_backup_scheduler.call_command')
    @patch('core.management.commands.run_backup_scheduler.time.sleep')
    @patch('core.management.commands.run_backup_scheduler.datetime')
    @patch('core.management.commands.run_backup_scheduler.R2BackupConfig.from_env')
    def test_failure_started_before_midnight_retries_from_completion_time(
        self,
        config_from_env,
        clock,
        sleeper,
        backup_command,
    ):
        config_from_env.return_value = self.config
        timestamps = iter((
            datetime(2026, 8, 12, 23, 59, tzinfo=SAO_PAULO),
            datetime(2026, 8, 13, 0, 1, tzinfo=SAO_PAULO),
            datetime(2026, 8, 13, 0, 31, tzinfo=SAO_PAULO),
        ))
        clock.now.side_effect = lambda *args: next(timestamps)
        sleeper.side_effect = stop_after_sleep
        backup_command.side_effect = CommandError('private backup failure')

        with (
            self.assertRaises(StopScheduler) as stopped,
            self.assertLogs('lar_finance.backup', level='INFO') as captured,
        ):
            call_command('run_backup_scheduler')

        backup_command.assert_called_once_with('backup_to_r2')
        self.assertEqual(stopped.exception.args, (30 * 60.0,))
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_failed', output)
        self.assertIn('backup_scheduler_wait', output)

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
        backup_command.side_effect = CommandError(' '.join(self.sensitive_values))

        with (
            self.assertRaises(StopScheduler) as stopped,
            self.assertLogs('lar_finance.backup', level='INFO') as captured,
        ):
            call_command('run_backup_scheduler')

        backup_command.assert_called_once_with('backup_to_r2')
        self.assertEqual(stopped.exception.args, (3600.0,))
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_failed', output)
        for sensitive_value in self.sensitive_values:
            self.assertNotIn(sensitive_value, output)

    @patch('core.management.commands.run_backup_scheduler.call_command')
    @patch('core.management.commands.run_backup_scheduler.time.sleep')
    @patch('core.management.commands.run_backup_scheduler.datetime')
    @patch('core.management.commands.run_backup_scheduler.R2BackupConfig.from_env')
    def test_command_error_retries_from_failure_completion_time(
        self,
        config_from_env,
        clock,
        sleeper,
        backup_command,
    ):
        config_from_env.return_value = self.config
        timeline = []
        timestamps = iter((
            datetime(2026, 8, 12, 3, tzinfo=SAO_PAULO),
            datetime(2026, 8, 12, 4, tzinfo=SAO_PAULO),
            datetime(2026, 8, 12, 4, tzinfo=SAO_PAULO),
        ))

        def now_after_backup(*args):
            timeline.append('clock')
            return next(timestamps)

        def failed_backup(*args):
            timeline.append('backup')
            raise CommandError('private backup failure')

        clock.now.side_effect = now_after_backup
        sleeper.side_effect = stop_after_sleep
        backup_command.side_effect = failed_backup

        with (
            self.assertRaises(StopScheduler) as stopped,
            self.assertLogs('lar_finance.backup', level='INFO') as captured,
        ):
            call_command('run_backup_scheduler')

        backup_command.assert_called_once_with('backup_to_r2')
        self.assertEqual(stopped.exception.args, (3600.0,))
        self.assertEqual(timeline, ['clock', 'backup', 'clock', 'clock'])
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_failed', output)
        self.assertIn('backup_scheduler_wait', output)

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

        with self.assertLogs('lar_finance.backup', level='INFO') as captured:
            call_command('run_backup_scheduler')

        backup_command.assert_not_called()
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_wait', output)
        self.assertIn('backup_scheduler_stopped', output)
        self.assertNotIn('backup_scheduler_failed', output)

    @patch('core.management.commands.run_backup_scheduler.call_command')
    @patch('core.management.commands.run_backup_scheduler.time.sleep')
    @patch('core.management.commands.run_backup_scheduler.datetime')
    @patch('core.management.commands.run_backup_scheduler.R2BackupConfig.from_env')
    def test_keyboard_interrupt_from_backup_stops_without_failure_log(
        self,
        config_from_env,
        clock,
        sleeper,
        backup_command,
    ):
        config_from_env.return_value = self.config
        clock.now.return_value = datetime(2026, 8, 12, 3, tzinfo=SAO_PAULO)
        backup_command.side_effect = KeyboardInterrupt

        with self.assertLogs('lar_finance.backup', level='INFO') as captured:
            call_command('run_backup_scheduler')

        backup_command.assert_called_once_with('backup_to_r2')
        sleeper.assert_not_called()
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_stopped', output)
        self.assertNotIn('backup_scheduler_failed', output)

    @patch('signal.signal')
    @patch('signal.getsignal')
    @patch('core.management.commands.run_backup_scheduler.call_command')
    @patch('core.management.commands.run_backup_scheduler.datetime')
    @patch('core.management.commands.run_backup_scheduler.R2BackupConfig.from_env')
    def test_sigterm_handler_uses_keyboard_interrupt_unwind_and_is_restored(
        self,
        config_from_env,
        clock,
        backup_command,
        get_signal,
        set_signal,
    ):
        previous_handler = object()
        installed = {}
        get_signal.return_value = previous_handler
        config_from_env.return_value = self.config
        clock.now.return_value = datetime(2026, 8, 12, 3, tzinfo=SAO_PAULO)

        def remember_handler(signum, handler):
            if signum == signal.SIGTERM and 'handler' not in installed:
                installed['handler'] = handler

        def terminate_during_backup(*args):
            installed['handler'](signal.SIGTERM, None)

        set_signal.side_effect = remember_handler
        backup_command.side_effect = terminate_during_backup

        with self.assertLogs('lar_finance.backup', level='INFO') as captured:
            call_command('run_backup_scheduler')

        self.assertEqual(set_signal.call_count, 2)
        installed_handler = installed['handler']
        self.assertEqual(
            set_signal.call_args_list,
            [
                call(signal.SIGTERM, installed_handler),
                call(signal.SIGTERM, previous_handler),
            ],
        )
        output = '\n'.join(captured.output)
        self.assertIn('backup_scheduler_stopped', output)
        self.assertNotIn('backup_scheduler_failed', output)
