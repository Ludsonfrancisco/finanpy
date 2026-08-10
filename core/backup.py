import os
import sqlite3
import tempfile
from contextlib import closing
from pathlib import Path


def verify_sqlite(database_path):
    path = Path(database_path)
    if not path.is_file():
        return False

    try:
        with closing(
            sqlite3.connect(f'file:{path.as_posix()}?mode=ro', uri=True)
        ) as connection:
            result = connection.execute('PRAGMA integrity_check').fetchone()
    except sqlite3.Error:
        return False

    return result == ('ok',)


def backup_sqlite(source_path, destination_path):
    source = Path(source_path).resolve()
    destination = Path(destination_path).resolve()

    if not source.is_file():
        raise FileNotFoundError(f'SQLite source does not exist: {source}')
    if source == destination:
        raise ValueError('Backup destination must differ from the source database.')
    if destination.exists():
        raise FileExistsError(f'Backup destination already exists: {destination}')

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_handle = tempfile.NamedTemporaryFile(
        dir=destination.parent,
        prefix='.lar-finance-backup-',
        suffix='.tmp',
        delete=False,
    )
    temporary_path = Path(temporary_handle.name)
    temporary_handle.close()

    try:
        with closing(sqlite3.connect(source)) as source_connection:
            with closing(sqlite3.connect(temporary_path)) as destination_connection:
                source_connection.backup(destination_connection)

        if not verify_sqlite(temporary_path):
            raise sqlite3.DatabaseError('The generated SQLite backup failed integrity check.')

        os.link(temporary_path, destination)
    finally:
        temporary_path.unlink(missing_ok=True)

    return destination
