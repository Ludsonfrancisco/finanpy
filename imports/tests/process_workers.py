"""Spawn-safe helpers for real cross-process SQLite import tests."""

import json
import os
import time
from datetime import timedelta
from pathlib import Path


def _setup(db_path, lock_path):
    os.environ['DJANGO_SETTINGS_MODULE'] = 'core.settings'
    os.environ['SQLITE_PATH'] = db_path

    import django

    django.setup()

    from django.conf import settings

    settings.IMPORT_MUTATION_LOCK_PATH = lock_path


def seed_process_database(db_path, lock_path, fixture_path, metadata_path):
    _setup(db_path, lock_path)

    from django.contrib.auth import get_user_model
    from django.core.management import call_command
    from django.utils import timezone

    from api.models import DeviceSession
    from households.models import FinancialOwner
    from households.services import ensure_household_for_user, get_financial_owner
    from imports.services import create_preview

    call_command('migrate', verbosity=0, interactive=False)
    user = get_user_model().objects.create_user(
        email='process-import@example.test', password='Strong-pass-123'
    )
    household = ensure_household_for_user(user)
    owner = get_financial_owner(household, FinancialOwner.SELF)
    device = DeviceSession.objects.create(
        user=user,
        household=household,
        default_owner=owner,
        platform=DeviceSession.WINDOWS,
        name='Process test device',
        access_token_digest='a' * 64,
        access_expires_at=timezone.now() + timedelta(hours=2),
        refresh_token_digest='b' * 64,
        refresh_expires_at=timezone.now() + timedelta(days=1),
    )
    content = Path(fixture_path).read_bytes()
    confirm_batch = create_preview(
        household=household,
        device_session=device,
        content=content,
    )
    expired_batch = create_preview(
        household=household,
        device_session=device,
        content=content + b'\n',
    )
    expired_batch.expires_at = timezone.now() - timedelta(seconds=1)
    expired_batch.save(update_fields=['expires_at'])
    Path(metadata_path).write_text(
        json.dumps(
            {
                'confirm_batch_id': str(confirm_batch.pk),
                'expired_batch_id': str(expired_batch.pk),
                'device_id': str(device.pk),
            }
        ),
        encoding='utf-8',
    )


def seed_auto_link_race_database(db_path, lock_path, metadata_path):
    _setup(db_path, lock_path)

    from django.contrib.auth import get_user_model
    from django.core.management import call_command
    from django.utils import timezone

    from api.models import DeviceSession
    from households.models import FinancialOwner
    from households.services import ensure_household_for_user, get_financial_owner

    call_command('migrate', verbosity=0, interactive=False)
    user = get_user_model().objects.create_user(
        email='auto-link-race@example.test',
        password='Strong-pass-123',
    )
    household = ensure_household_for_user(user)
    owner = get_financial_owner(household, FinancialOwner.SELF)
    device = DeviceSession.objects.create(
        user=user,
        household=household,
        default_owner=owner,
        platform=DeviceSession.WINDOWS,
        name='Auto-link race device',
        access_token_digest='c' * 64,
        access_expires_at=timezone.now() + timedelta(hours=2),
        refresh_token_digest='d' * 64,
        refresh_expires_at=timezone.now() + timedelta(days=1),
    )
    Path(metadata_path).write_text(
        json.dumps(
            {
                'household_id': household.pk,
                'device_id': str(device.pk),
            }
        ),
        encoding='utf-8',
    )


def create_preview_process(
    db_path,
    lock_path,
    fixture_path,
    household_id,
    device_id,
    ready_event,
    start_event,
    result_path,
):
    _setup(db_path, lock_path)

    from api.models import DeviceSession
    from households.models import Household
    from imports.services import create_preview

    household = Household.objects.get(pk=household_id)
    device = DeviceSession.objects.get(pk=device_id)
    content = Path(fixture_path).read_bytes()
    ready_event.set()
    if not start_event.wait(timeout=10):
        raise RuntimeError('auto-link race process was not released')
    batch = create_preview(
        household=household,
        device_session=device,
        content=content,
    )
    Path(result_path).write_text(
        json.dumps(
            {
                'account_id': batch.account_id,
                'batch_id': batch.pk,
                'status': batch.status,
            }
        ),
        encoding='utf-8',
    )


def purge_process(
    db_path,
    lock_path,
    entered_event,
    release_event,
    marker_path,
):
    _setup(db_path, lock_path)

    from imports import services

    original_purge = services._purge_preview_records

    def coordinated_purge(*, now=None):
        Path(marker_path).touch()
        entered_event.set()
        if not release_event.wait(timeout=10):
            raise RuntimeError('purge process was not released')
        try:
            return original_purge(now=now)
        finally:
            Path(marker_path).unlink(missing_ok=True)

    services._purge_preview_records = coordinated_purge
    services.purge_preview_records()


def confirm_process(
    db_path,
    lock_path,
    batch_id,
    device_id,
    marker_path,
    overlap_path,
    ready_event,
    entered_event,
):
    _setup(db_path, lock_path)

    from api.models import DeviceSession
    from imports import services
    from imports.models import ImportBatch

    original_confirm = services._confirm_preview
    batch = ImportBatch.objects.get(pk=batch_id)
    device_session = DeviceSession.objects.get(pk=device_id)

    def observed_confirm(*, batch, device_session):
        entered_event.set()
        if Path(marker_path).exists():
            Path(overlap_path).touch()
        return original_confirm(batch=batch, device_session=device_session)

    services._confirm_preview = observed_confirm
    ready_event.set()
    services.confirm_preview(
        batch=batch,
        device_session=device_session,
    )


def wait_until_process_finishes(process, *, timeout=15):
    deadline = time.monotonic() + timeout
    while process.is_alive() and time.monotonic() < deadline:
        process.join(timeout=0.05)
