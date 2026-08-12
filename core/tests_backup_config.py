from django.test import SimpleTestCase

from core.backup_config import BackupConfigurationError, R2BackupConfig


class R2BackupConfigTest(SimpleTestCase):
    def valid_env(self):
        return {
            'R2_BACKUP_ENDPOINT_URL': 'https://account.r2.cloudflarestorage.com',
            'R2_BACKUP_ACCESS_KEY_ID': 'access-id',
            'R2_BACKUP_SECRET_ACCESS_KEY': 'secret-value',
            'R2_BACKUP_BUCKET': 'lar-finance-backups',
        }

    def test_defaults_are_operational_and_credentials_are_not_represented(self):
        config = R2BackupConfig.from_env(self.valid_env())

        self.assertEqual(config.prefix, 'production')
        self.assertEqual(config.schedule_time.isoformat(), '03:00:00')
        self.assertEqual(config.time_zone.key, 'America/Sao_Paulo')
        self.assertEqual(config.retry_seconds, 3600)
        self.assertEqual(config.daily_retention, 14)
        self.assertEqual(config.weekly_retention, 8)
        self.assertEqual(config.monthly_retention, 12)
        self.assertNotIn('access-id', repr(config))
        self.assertNotIn('secret-value', repr(config))

    def test_normalizes_prefix(self):
        config = R2BackupConfig.from_env(
            self.valid_env() | {'R2_BACKUP_PREFIX': ' /production/eu/ '}
        )

        self.assertEqual(config.prefix, 'production/eu')

    def test_rejects_missing_required_values_without_echoing_credentials(self):
        for variable_name in (
            'R2_BACKUP_ENDPOINT_URL',
            'R2_BACKUP_ACCESS_KEY_ID',
            'R2_BACKUP_SECRET_ACCESS_KEY',
            'R2_BACKUP_BUCKET',
        ):
            with self.subTest(variable_name=variable_name):
                environ = self.valid_env() | {variable_name: '   '}

                with self.assertRaises(BackupConfigurationError) as raised:
                    R2BackupConfig.from_env(environ)

                message = str(raised.exception)
                self.assertIn(variable_name, message)
                self.assertNotIn('access-id', message)
                self.assertNotIn('secret-value', message)

    def test_rejects_non_https_endpoint_without_echoing_secret(self):
        environ = self.valid_env() | {
            'R2_BACKUP_ENDPOINT_URL': 'http://account.invalid',
        }

        with self.assertRaises(BackupConfigurationError) as raised:
            R2BackupConfig.from_env(environ)

        self.assertIn('R2_BACKUP_ENDPOINT_URL', str(raised.exception))
        self.assertNotIn('secret-value', str(raised.exception))

    def test_rejects_https_endpoint_without_hostname(self):
        environ = self.valid_env() | {'R2_BACKUP_ENDPOINT_URL': 'https:///path'}

        with self.assertRaisesRegex(
            BackupConfigurationError, 'R2_BACKUP_ENDPOINT_URL'
        ):
            R2BackupConfig.from_env(environ)

    def test_rejects_non_strict_or_out_of_range_schedule_time(self):
        for schedule_time in ('3:00', '24:00', '12:60'):
            with self.subTest(schedule_time=schedule_time):
                environ = self.valid_env() | {'R2_BACKUP_TIME': schedule_time}

                with self.assertRaisesRegex(BackupConfigurationError, 'R2_BACKUP_TIME'):
                    R2BackupConfig.from_env(environ)

    def test_rejects_empty_prefix(self):
        environ = self.valid_env() | {'R2_BACKUP_PREFIX': ' /// '}

        with self.assertRaisesRegex(BackupConfigurationError, 'R2_BACKUP_PREFIX'):
            R2BackupConfig.from_env(environ)

    def test_rejects_invalid_time_zone(self):
        environ = self.valid_env() | {'R2_BACKUP_TIME_ZONE': 'Not/A_Time_Zone'}

        with self.assertRaisesRegex(BackupConfigurationError, 'R2_BACKUP_TIME_ZONE'):
            R2BackupConfig.from_env(environ)
