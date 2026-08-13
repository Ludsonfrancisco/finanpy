from datetime import date

from django.test import SimpleTestCase

from core.backup_catalog import (
    CatalogObject,
    build_object_key,
    parse_managed_key,
    retention_labels,
    select_retained_keys,
)


class BackupCatalogTest(SimpleTestCase):
    def test_key_round_trip_and_unknown_key(self):
        key = build_object_key('production', date(2026, 8, 12))
        self.assertEqual(
            key,
            'production/backups/2026/08/lar-finance-2026-08-12.sqlite3',
        )
        self.assertEqual(parse_managed_key('production', key), date(2026, 8, 12))
        self.assertIsNone(parse_managed_key('production', 'production/manual.sqlite3'))

    def test_parse_rejects_invalid_date_or_incoherent_directories(self):
        self.assertIsNone(
            parse_managed_key(
                'production',
                'production/backups/2026/08/lar-finance-2026-08-32.sqlite3',
            )
        )
        self.assertIsNone(
            parse_managed_key(
                'production',
                'production/backups/2026/07/lar-finance-2026-08-12.sqlite3',
            )
        )
        self.assertIsNone(
            parse_managed_key(
                'staging',
                'production/backups/2026/08/lar-finance-2026-08-12.sqlite3',
            )
        )

    def test_labels_share_one_physical_object(self):
        self.assertEqual(
            retention_labels(date(2026, 3, 1)),
            frozenset({'daily', 'weekly', 'monthly'}),
        )

    def test_regular_day_has_only_daily_label(self):
        self.assertEqual(retention_labels(date(2026, 8, 12)), frozenset({'daily'}))

    def test_retention_preserves_union_and_latest(self):
        objects = [
            CatalogObject(key=f'key-{day}', backup_date=date(2026, 1, day))
            for day in range(1, 32)
        ]

        retained = select_retained_keys(objects, daily=2, weekly=1, monthly=1)

        self.assertEqual(retained, {'key-31', 'key-30', 'key-25', 'key-1'})

    def test_retention_protects_latest_when_all_limits_are_zero(self):
        objects = [
            CatalogObject(key='older', backup_date=date(2026, 8, 11)),
            CatalogObject(key='latest', backup_date=date(2026, 8, 12)),
        ]

        self.assertEqual(
            select_retained_keys(objects, daily=0, weekly=0, monthly=0),
            {'latest'},
        )

    def test_empty_catalog_retains_nothing(self):
        self.assertEqual(select_retained_keys([]), set())
