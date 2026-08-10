import shutil
import sqlite3
import tempfile
from contextlib import closing
from pathlib import Path

from django.core.management import get_commands
from django.test import SimpleTestCase

from core.backup import backup_sqlite, verify_sqlite


class SqliteBackupTest(SimpleTestCase):
    def setUp(self):
        self.temp_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp_directory.name)
        self.source = self.directory / 'source.sqlite3'
        self.backup = self.directory / 'backup.sqlite3'

        with closing(sqlite3.connect(self.source)) as connection:
            connection.execute('CREATE TABLE entries (value TEXT NOT NULL)')
            connection.execute('INSERT INTO entries (value) VALUES (?)', ('preserved',))
            connection.commit()

    def tearDown(self):
        self.temp_directory.cleanup()

    def test_backup_is_valid_and_can_be_restored(self):
        backup_sqlite(self.source, self.backup)

        self.assertTrue(verify_sqlite(self.backup))

        restored = self.directory / 'restored.sqlite3'
        shutil.copy2(self.backup, restored)
        with closing(sqlite3.connect(restored)) as connection:
            row = connection.execute('SELECT value FROM entries').fetchone()

        self.assertEqual(row, ('preserved',))

    def test_backup_refuses_to_overwrite_an_existing_file(self):
        self.backup.write_text('existing', encoding='utf-8')

        with self.assertRaises(FileExistsError):
            backup_sqlite(self.source, self.backup)

    def test_backup_rejects_missing_source(self):
        missing = self.directory / 'missing.sqlite3'

        with self.assertRaises(FileNotFoundError):
            backup_sqlite(missing, self.backup)

    def test_backup_management_command_is_registered(self):
        self.assertEqual(get_commands().get('backup_sqlite'), 'core')
