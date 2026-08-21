import re
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Sequence


@dataclass(frozen=True)
class CatalogObject:
    key: str
    backup_date: date


def build_object_key(prefix: str, backup_date: date) -> str:
    return (
        f'{prefix}/backups/{backup_date:%Y/%m}/'
        f'lar-finance-{backup_date:%Y-%m-%d}.sqlite3'
    )


def build_deploy_object_key(prefix: str, version: str, now: datetime) -> str:
    instant = now.astimezone(UTC)
    stamp = instant.strftime('%Y%m%dT%H%M%S%fZ')
    return (
        f'{prefix}/deploy/{version}/{stamp}/'
        f'{instant:%Y/%m/%d}.sqlite3'
    )


def parse_deploy_object_key(
    prefix: str,
    key: str,
) -> tuple[str, datetime, date] | None:
    pattern = re.compile(
        rf'^{re.escape(prefix)}/deploy/'
        r'(?P<version>[0-9a-f]{40})/'
        r'(?P<stamp>\d{8}T\d{12}Z)/'
        r'(?P<year>\d{4})/(?P<month>\d{2})/(?P<day>\d{2})\.sqlite3$'
    )
    match = pattern.fullmatch(key)
    if match is None:
        return None
    try:
        instant = datetime.strptime(
            match['stamp'],
            '%Y%m%dT%H%M%S%fZ',
        ).replace(tzinfo=UTC)
        backup_date = date(
            int(match['year']),
            int(match['month']),
            int(match['day']),
        )
    except ValueError:
        return None
    if instant.date() != backup_date:
        return None
    return match['version'], instant, backup_date


def parse_managed_key(prefix: str, key: str) -> date | None:
    pattern = re.compile(
        rf'^{re.escape(prefix)}/backups/'
        r'(?P<directory_year>\d{4})/(?P<directory_month>\d{2})/'
        r'lar-finance-(?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2})\.sqlite3$'
    )
    match = pattern.fullmatch(key)
    if match is None:
        return None

    try:
        backup_date = date(
            int(match['year']),
            int(match['month']),
            int(match['day']),
        )
    except ValueError:
        return None

    if (
        backup_date.year != int(match['directory_year'])
        or backup_date.month != int(match['directory_month'])
    ):
        return None
    return backup_date


def retention_labels(backup_date: date) -> frozenset[str]:
    labels = {'daily'}
    if backup_date.weekday() == 6:
        labels.add('weekly')
    if backup_date.day == 1:
        labels.add('monthly')
    return frozenset(labels)


def select_retained_keys(
    objects: Sequence[CatalogObject],
    daily: int = 14,
    weekly: int = 8,
    monthly: int = 12,
) -> set[str]:
    if not objects:
        return set()

    ordered_objects = sorted(
        objects,
        key=lambda catalog_object: (catalog_object.backup_date, catalog_object.key),
        reverse=True,
    )
    retained = set()
    for label, limit in (
        ('daily', daily),
        ('weekly', weekly),
        ('monthly', monthly),
    ):
        labeled_objects = [
            catalog_object
            for catalog_object in ordered_objects
            if label in retention_labels(catalog_object.backup_date)
        ]
        retained.update(
            catalog_object.key for catalog_object in labeled_objects[: max(0, limit)]
        )

    retained.add(ordered_objects[0].key)
    return retained
