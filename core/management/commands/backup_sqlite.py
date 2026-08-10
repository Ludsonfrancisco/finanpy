from datetime import UTC, datetime
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from core.backup import backup_sqlite


class Command(BaseCommand):
    help = 'Create and integrity-check a non-overwriting SQLite backup.'

    def add_arguments(self, parser):
        parser.add_argument('--output', type=Path)

    def handle(self, *args, **options):
        database = settings.DATABASES['default']
        if database['ENGINE'] != 'django.db.backends.sqlite3':
            raise CommandError('backup_sqlite only supports the SQLite backend.')

        source = Path(database['NAME'])
        timestamp = datetime.now(UTC).strftime('%Y%m%dT%H%M%SZ')
        destination = options['output'] or (
            settings.BASE_DIR / 'backups' / f'lar-finance-{timestamp}.sqlite3'
        )

        try:
            backup_path = backup_sqlite(source, destination)
        except (FileNotFoundError, FileExistsError, ValueError, OSError) as error:
            raise CommandError(str(error)) from error

        self.stdout.write(self.style.SUCCESS(f'Backup verified: {backup_path}'))
