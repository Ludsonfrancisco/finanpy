from django.core.management.base import BaseCommand

from imports.services import purge_preview_records


class Command(BaseCommand):
    help = 'Purge normalized rows from expired or cancelled OFX previews.'

    def handle(self, *args, **options):
        deleted = purge_preview_records()
        self.stdout.write(f'purged_import_records={deleted}')
