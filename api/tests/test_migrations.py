import os
import secrets
import sqlite3
import subprocess
import sys
from contextlib import closing
from pathlib import Path
from tempfile import TemporaryDirectory

from django.test import SimpleTestCase

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PROJECT_APPS = (
    'accounts',
    'api',
    'categories',
    'households',
    'profiles',
    'sync',
    'transactions',
    'users',
)
SPRINT_2_TABLES = {
    'api_devicesession',
    'api_usedrefreshtoken',
    'sync_idempotentoperation',
    'sync_syncchange',
}


class FreshDatabaseMigrationTest(SimpleTestCase):
    def test_fresh_temporary_sqlite_migrates_to_every_project_head(self):
        environment = os.environ.copy()
        environment.update(
            {
                'SECRET_KEY': secrets.token_urlsafe(48),
                'DEBUG': 'False',
                'ALLOWED_HOSTS': 'localhost,127.0.0.1',
                'SECURE_SSL_REDIRECT': 'False',
            }
        )

        with TemporaryDirectory(prefix='finanpy-task9-fresh-') as temp_dir:
            database_path = Path(temp_dir) / 'fresh.sqlite3'
            environment['SQLITE_PATH'] = str(database_path)

            migrate = subprocess.run(
                [sys.executable, 'manage.py', 'migrate', '--noinput'],
                cwd=PROJECT_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
            self.assertEqual(
                migrate.returncode,
                0,
                f'migrate stdout:\n{migrate.stdout}\nmigrate stderr:\n{migrate.stderr}',
            )

            migrate_check = subprocess.run(
                [sys.executable, 'manage.py', 'migrate', '--check'],
                cwd=PROJECT_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
            self.assertEqual(
                migrate_check.returncode,
                0,
                'fresh database did not reach every migration head:\n'
                f'{migrate_check.stdout}\n{migrate_check.stderr}',
            )

            with closing(sqlite3.connect(database_path)) as database:
                applied = set(
                    database.execute(
                        'SELECT app, name FROM django_migrations'
                    ).fetchall()
                )
                tables = {
                    row[0]
                    for row in database.execute(
                        "SELECT name FROM sqlite_master WHERE type = 'table'"
                    ).fetchall()
                }
                account_columns = {
                    row[1]
                    for row in database.execute(
                        "PRAGMA table_info('accounts_account')"
                    ).fetchall()
                }

        expected = {
            (app_label, migration.stem)
            for app_label in PROJECT_APPS
            for migration in (PROJECT_ROOT / app_label / 'migrations').glob('*.py')
            if migration.name != '__init__.py'
        }
        self.assertTrue(expected)
        self.assertTrue(expected.issubset(applied))
        self.assertTrue(SPRINT_2_TABLES.issubset(tables))
        self.assertTrue({'uuid', 'sync_version'}.issubset(account_columns))
