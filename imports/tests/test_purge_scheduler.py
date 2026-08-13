from unittest.mock import patch

from django.core.management import call_command
from django.test import SimpleTestCase

from imports.services import ImportBusyError


class ImportPreviewPurgeSchedulerTest(SimpleTestCase):
    @patch(
        'imports.management.commands.run_import_preview_purge_scheduler.time.sleep'
    )
    @patch(
        'imports.management.commands.run_import_preview_purge_scheduler.'
        'purge_preview_records'
    )
    @patch(
        'imports.management.commands.run_import_preview_purge_scheduler.'
        'next_preview_purge_delay'
    )
    def test_purges_immediately_then_waits_for_nearest_expiry_with_hourly_cap(
        self, next_delay, purge, sleep
    ):
        purge.return_value = 2
        next_delay.return_value = 900
        sleep.side_effect = KeyboardInterrupt

        call_command('run_import_preview_purge_scheduler')

        purge.assert_called_once_with()
        next_delay.assert_called_once_with(max_delay_seconds=3600)
        sleep.assert_called_once_with(900)

    @patch(
        'imports.management.commands.run_import_preview_purge_scheduler.time.sleep'
    )
    @patch(
        'imports.management.commands.run_import_preview_purge_scheduler.'
        'purge_preview_records'
    )
    def test_transient_import_contention_does_not_stop_scheduler(self, purge, sleep):
        purge.side_effect = ImportBusyError('temporary contention')
        sleep.side_effect = KeyboardInterrupt

        with self.assertLogs('imports.preview_purge', level='WARNING') as captured:
            call_command('run_import_preview_purge_scheduler')

        sleep.assert_called_once_with(60)
        self.assertIn('import_preview_purge_busy', captured.output[0])
        self.assertNotIn('temporary contention', captured.output[0])
