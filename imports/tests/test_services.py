import json
import multiprocessing
import sqlite3
import tempfile
from contextlib import closing
from datetime import date, datetime, timedelta
from datetime import timezone as datetime_timezone
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.db import IntegrityError, OperationalError
from django.test import SimpleTestCase, TestCase
from django.utils import timezone

from accounts.models import Account
from api.models import DeviceSession
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from imports import services
from imports.models import ImportAccountLink, ImportBatch, ImportRecord, SourceReference
from imports.services import (
    ExpiredPreviewError,
    ImportAccessError,
    ImportBusyError,
    ImportConflictError,
    ImportStateError,
    bind_preview_account,
    cancel_preview,
    confirm_preview,
    create_preview,
    get_batch_for_household,
    next_preview_purge_delay,
)
from imports.tests.process_workers import (
    confirm_process,
    purge_process,
    seed_process_database,
    wait_until_process_finishes,
)
from sync.models import SyncChange
from transactions.models import Transaction

FIXTURES = Path(__file__).parent / 'fixtures'


class ImportPreviewServiceTest(TestCase):
    def setUp(self):
        self.content = (FIXTURES / 'nubank-account.ofx').read_bytes()
        self.card_content = (FIXTURES / 'nubank-card.ofx').read_bytes()
        self.user, self.household, self.owner, self.account, self.device = (
            self._setup_household('preview@example.com')
        )
        (
            self.other_user,
            self.other_household,
            self.other_owner,
            self.other_account,
            self.other_device,
        ) = self._setup_household('other-preview@example.com')

    def test_recognized_account_creates_preview_records_without_transactions(self):
        ImportAccountLink.objects.create(
            household=self.household,
            account=self.account,
            provider='nubank',
            product_type='bank_account',
            external_account_id='synthetic-account-001',
        )

        batch = create_preview(
            household=self.household, device_session=self.device, content=self.content
        )

        self.assertEqual(batch.status, ImportBatch.PREVIEW_READY)
        self.assertEqual(batch.account, self.account)
        self.assertEqual(batch.financial_owner, self.owner)
        self.assertEqual(batch.created_count, 2)
        self.assertEqual(Transaction.objects.count(), 0)
        self.assertEqual(
            list(batch.records.values_list('line_number', flat=True)), [1, 2]
        )
        self.assertFalse(hasattr(batch, 'raw_content'))

    def test_unknown_account_requires_link_then_recalculates_outcomes(self):
        batch = create_preview(
            household=self.household, device_session=self.device, content=self.content
        )

        self.assertEqual(batch.status, ImportBatch.NEEDS_ACCOUNT_LINK)
        self.assertIsNone(batch.account)
        self.assertEqual(batch.records.count(), 2)
        self.assertEqual(batch.created_count, 0)

        batch = bind_preview_account(batch=batch, account=self.account)

        self.assertEqual(batch.status, ImportBatch.PREVIEW_READY)
        self.assertEqual(batch.financial_owner, self.owner)
        self.assertEqual(batch.created_count, 2)
        self.assertTrue(
            ImportAccountLink.objects.filter(
                household=self.household,
                account=self.account,
                external_account_id='synthetic-account-001',
            ).exists()
        )

    def test_credit_card_preview_requires_credit_account(self):
        batch = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.card_content,
        )

        with self.assertRaises(ImportStateError):
            bind_preview_account(batch=batch, account=self.account)

        card = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Synthetic card',
            type=Account.CREDIT,
        )
        batch = bind_preview_account(batch=batch, account=card)
        self.assertEqual(batch.account, card)

    def test_recognized_credit_card_rejects_a_non_credit_account_link(self):
        ImportAccountLink.objects.create(
            household=self.household,
            account=self.account,
            provider='nubank',
            product_type='credit_card',
            external_account_id='synthetic-card-002',
        )

        with self.assertRaises(ImportStateError):
            create_preview(
                household=self.household,
                device_session=self.device,
                content=self.card_content,
            )

    def test_foreign_batch_account_and_device_are_rejected_without_metadata_disclosure(
        self,
    ):
        batch = create_preview(
            household=self.household, device_session=self.device, content=self.content
        )

        with self.assertRaises(ImportAccessError):
            get_batch_for_household(
                household=self.other_household, batch_uuid=batch.uuid
            )
        with self.assertRaises(ImportAccessError):
            bind_preview_account(batch=batch, account=self.other_account)
        with self.assertRaises(ImportAccessError):
            create_preview(
                household=self.household,
                device_session=self.other_device,
                content=self.content,
            )

    def test_expired_or_cancelled_preview_cannot_be_bound(self):
        batch = create_preview(
            household=self.household, device_session=self.device, content=self.content
        )
        batch.expires_at = timezone.now() - timedelta(seconds=1)
        batch.full_clean()
        batch.save(update_fields=['expires_at'])
        with self.assertRaises(ExpiredPreviewError):
            bind_preview_account(batch=batch, account=self.account)

        fresh = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content + b'\n',
        )
        before = Transaction.objects.count()
        cancelled = cancel_preview(batch=fresh)
        self.assertEqual(cancelled.status, ImportBatch.CANCELLED)
        self.assertEqual(Transaction.objects.count(), before)
        with self.assertRaises(ImportStateError):
            bind_preview_account(batch=cancelled, account=self.account)

    def test_stale_preview_reference_cannot_overwrite_cancel_or_completion(self):
        for status in (ImportBatch.CANCELLED, ImportBatch.COMPLETED):
            with self.subTest(status=status):
                batch = create_preview(
                    household=self.household,
                    device_session=self.device,
                    content=self.content,
                )
                ImportBatch.objects.filter(pk=batch.pk).update(status=status)

                with self.assertRaises(ImportStateError):
                    bind_preview_account(batch=batch, account=self.account)

                self.assertEqual(
                    ImportBatch.objects.get(pk=batch.pk).status,
                    status,
                )

    def test_cancel_reloads_batch_accepts_linked_preview_and_rejects_completed(self):
        stale_unlinked = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content,
        )
        linked = bind_preview_account(batch=stale_unlinked, account=self.account)

        cancelled = cancel_preview(batch=stale_unlinked)
        self.assertEqual(
            ImportBatch.objects.get(pk=linked.pk).status,
            ImportBatch.CANCELLED,
        )
        self.assertEqual(cancelled.status, ImportBatch.CANCELLED)
        self.assertFalse(cancelled.records.exists())

        same_receipt = cancel_preview(batch=stale_unlinked)
        self.assertEqual(same_receipt.pk, cancelled.pk)
        self.assertEqual(same_receipt.status, ImportBatch.CANCELLED)

        stale_linked = self._bound_preview(content=self.content + b'\n')
        confirm_preview(batch=stale_linked, device_session=self.device)
        with self.assertRaises(ImportStateError):
            cancel_preview(batch=stale_linked)
        self.assertEqual(
            ImportBatch.objects.get(pk=stale_linked.pk).status,
            ImportBatch.COMPLETED,
        )

    def test_account_link_unique_race_returns_domain_error_not_integrity_error(self):
        batch = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content,
        )
        original_save = services._save

        def race_save(instance):
            if isinstance(instance, ImportAccountLink):
                raise IntegrityError('simulated unique collision')
            return original_save(instance)

        with patch('imports.services._save', side_effect=race_save):
            with self.assertRaises(ImportStateError):
                bind_preview_account(batch=batch, account=self.account)

    def test_fitid_duplicate_is_limited_to_the_linked_account(self):
        ImportAccountLink.objects.create(
            household=self.household,
            account=self.account,
            provider='nubank',
            product_type='bank_account',
            external_account_id='synthetic-account-001',
        )
        transaction = self._transaction(
            self.user, self.household, self.owner, self.account
        )
        SourceReference.objects.create(
            account=self.account,
            provider='nubank',
            external_id='synthetic-fitid-001',
            transaction=transaction,
        )

        batch = create_preview(
            household=self.household, device_session=self.device, content=self.content
        )
        self.assertEqual(batch.duplicate_count, 1)
        self.assertEqual(
            batch.records.get(line_number=1).outcome, ImportRecord.DUPLICATE
        )

        ImportAccountLink.objects.create(
            household=self.other_household,
            account=self.other_account,
            provider='nubank',
            product_type='bank_account',
            external_account_id='synthetic-account-001',
        )
        other = create_preview(
            household=self.other_household,
            device_session=self.other_device,
            content=self.content,
        )
        self.assertEqual(other.duplicate_count, 0)

    def test_missing_fitid_matching_completed_record_is_warning(self):
        content = self.content.replace(b'<FITID>synthetic-fitid-001', b'')
        ImportAccountLink.objects.create(
            household=self.household,
            account=self.account,
            provider='nubank',
            product_type='bank_account',
            external_account_id='synthetic-account-001',
        )
        completed = self._completed_batch()
        ImportRecord.objects.create(
            batch=completed,
            line_number=1,
            posted_on=date(2026, 1, 2),
            amount=Decimal('-42.50'),
            description='Synthetic market purchase',
            transaction_type='expense',
            fingerprint=self._fingerprint(self.account),
            outcome=ImportRecord.CREATED,
        )

        batch = create_preview(
            household=self.household, device_session=self.device, content=content
        )
        self.assertEqual(batch.warning_count, 1)
        self.assertEqual(batch.records.get(line_number=1).outcome, ImportRecord.WARNING)

    def test_completed_file_is_a_receipt_and_same_hash_other_household_is_independent(
        self,
    ):
        completed = self._completed_batch()
        completed.file_sha256 = self._sha256(self.content)
        completed.full_clean()
        completed.save(update_fields=['file_sha256'])

        receipt = create_preview(
            household=self.household, device_session=self.device, content=self.content
        )
        self.assertEqual(receipt.status, ImportBatch.PREVIEW_READY)
        self.assertEqual(receipt.created_count, 0)
        self.assertEqual(receipt.duplicate_count, 2)
        self.assertEqual(receipt.records.count(), 0)
        self.assertTrue(receipt.is_repeated_file)

        other = create_preview(
            household=self.other_household,
            device_session=self.other_device,
            content=self.content,
        )
        self.assertEqual(other.status, ImportBatch.NEEDS_ACCOUNT_LINK)

    @patch('imports.services.timezone.now')
    def test_preview_expires_in_23_hours_and_does_not_log_financial_data(self, now):
        frozen = datetime(2026, 3, 1, tzinfo=datetime_timezone.utc)
        now.return_value = frozen
        with self.assertNoLogs('imports.services'):
            batch = create_preview(
                household=self.household,
                device_session=self.device,
                content=self.content,
            )

        self.assertEqual(batch.expires_at, frozen + timedelta(hours=23))
        record = batch.records.get(line_number=1)
        self.assertEqual(record.external_id, 'synthetic-fitid-001')
        self.assertEqual(record.description, 'Synthetic market purchase')
        self.assertEqual(record.amount, Decimal('-42.50'))

    @patch('imports.services.timezone.now')
    def test_preview_created_while_scheduler_sleeps_is_purged_within_24_hours(
        self, now
    ):
        created_at = datetime(2026, 3, 1, tzinfo=datetime_timezone.utc)
        now.return_value = created_at
        batch = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content,
        )
        latest_hourly_poll = batch.expires_at + timedelta(hours=1)

        deleted = services.purge_preview_records(now=latest_hourly_poll)

        self.assertLessEqual(latest_hourly_poll, created_at + timedelta(hours=24))
        self.assertGreater(deleted, 0)
        self.assertFalse(batch.records.exists())

    def test_confirm_preview_creates_transactions_references_and_sync_receipt(self):
        batch = self._bound_preview()
        sync_before = SyncChange.objects.filter(
            household=self.household,
            entity_type='transaction',
        ).count()

        confirmed = confirm_preview(batch=batch, device_session=self.device)

        self.assertEqual(confirmed.status, ImportBatch.COMPLETED)
        self.assertEqual(
            Transaction.objects.filter(household=self.household).count(), 2
        )
        self.assertEqual(
            SourceReference.objects.filter(account=self.account).count(), 2
        )
        self.assertEqual(
            SyncChange.objects.filter(
                household=self.household,
                entity_type='transaction',
            ).count(),
            sync_before + 2,
        )
        self.assertTrue(
            Category.objects.filter(
                household=self.household,
                name='Não categorizado',
                type=Category.EXPENSE,
            ).exists()
        )
        self.assertEqual(
            list(confirmed.records.values_list('outcome', flat=True)),
            [ImportRecord.CREATED, ImportRecord.CREATED],
        )

    def test_conflicting_second_fitid_rolls_back_preview_confirmation(self):
        batch = self._bound_preview()
        second = batch.records.get(line_number=2)
        second.external_id = 'synthetic-conflict'
        second.full_clean()
        second.save(update_fields=['external_id'])
        existing = self._transaction(
            self.user, self.household, self.owner, self.account
        )
        SourceReference.objects.create(
            account=self.account,
            provider='nubank',
            external_id='synthetic-conflict',
            transaction=existing,
        )
        baseline = Transaction.objects.count()

        with self.assertRaises(ImportConflictError):
            confirm_preview(batch=batch, device_session=self.device)

        self.assertEqual(Transaction.objects.count(), baseline)
        self.assertEqual(
            ImportBatch.objects.get(pk=batch.pk).status,
            ImportBatch.PREVIEW_READY,
        )
        self.assertFalse(
            Category.objects.filter(
                household=self.household,
                name='Não categorizado',
            ).exists()
        )

    def test_repeated_fitid_inside_batch_rolls_back_before_any_write(self):
        batch = self._bound_preview()
        second = batch.records.get(line_number=2)
        second.external_id = batch.records.get(line_number=1).external_id
        second.full_clean()
        second.save(update_fields=['external_id'])

        with self.assertRaises(ImportConflictError):
            confirm_preview(batch=batch, device_session=self.device)

        self.assertEqual(
            Transaction.objects.filter(household=self.household).count(), 0
        )
        self.assertEqual(
            SourceReference.objects.filter(account=self.account).count(), 0
        )
        self.assertEqual(
            ImportBatch.objects.get(pk=batch.pk).status,
            ImportBatch.PREVIEW_READY,
        )

    def test_reconfirming_completed_preview_is_idempotent(self):
        batch = self._bound_preview()
        confirm_preview(batch=batch, device_session=self.device)
        before = Transaction.objects.count()

        same_receipt = confirm_preview(batch=batch, device_session=self.device)

        self.assertEqual(same_receipt.status, ImportBatch.COMPLETED)
        self.assertEqual(Transaction.objects.count(), before)

    def test_confirmation_rejects_expired_unlinked_invalid_and_foreign_device(self):
        batch = self._bound_preview()
        batch.expires_at = timezone.now() - timedelta(seconds=1)
        batch.save(update_fields=['expires_at'])
        with self.assertRaises(ExpiredPreviewError):
            confirm_preview(batch=batch, device_session=self.device)

        unlinked = self._bound_preview(content=self.content + b'\n')
        ImportBatch.objects.filter(pk=unlinked.pk).update(
            account=None,
            financial_owner=None,
            status=ImportBatch.NEEDS_ACCOUNT_LINK,
        )
        with self.assertRaises(ImportStateError):
            confirm_preview(batch=unlinked, device_session=self.device)

        fresh = self._bound_preview(content=self.content + b'\n\n')
        with self.assertRaises(ImportAccessError):
            confirm_preview(batch=fresh, device_session=self.other_device)

        fresh = self._bound_preview(content=self.content + b'\n\n\n')
        self.device.revoked_at = timezone.now()
        self.device.save(update_fields=['revoked_at'])
        with self.assertRaises(ImportAccessError):
            confirm_preview(batch=fresh, device_session=self.device)

    def test_confirmation_rejects_expired_device_session(self):
        batch = self._bound_preview()
        self.device.access_expires_at = timezone.now() - timedelta(seconds=1)
        self.device.save(update_fields=['access_expires_at'])

        with self.assertRaises(ImportAccessError):
            confirm_preview(batch=batch, device_session=self.device)

    def test_confirmation_creates_independent_income_uncategorized_category(self):
        batch = self._bound_preview()
        for record in batch.records.all():
            record.transaction_type = 'income'
            record.full_clean()
            record.save(update_fields=['transaction_type'])

        confirm_preview(batch=batch, device_session=self.device)

        self.assertTrue(
            Category.objects.filter(
                household=self.household,
                name='Não categorizado',
                type=Category.INCOME,
            ).exists()
        )

    def test_category_creation_collision_reuses_the_concurrent_category(self):
        batch = self._bound_preview()
        existing = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Não categorizado',
            type=Category.EXPENSE,
        )

        confirmed = confirm_preview(batch=batch, device_session=self.device)

        self.assertEqual(confirmed.status, ImportBatch.COMPLETED)
        self.assertEqual(
            Transaction.objects.filter(category=existing).count(),
            1,
        )

    def test_category_lookup_insert_race_reloads_the_concurrent_category(self):
        batch = self._bound_preview()
        existing = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Não categorizado',
            type=Category.EXPENSE,
        )
        original_filter = Category.objects.filter

        class EmptyLookup:
            @staticmethod
            def first():
                return None

        calls = 0

        def raced_filter(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 1:
                return EmptyLookup()
            return original_filter(*args, **kwargs)

        with patch(
            'imports.services.Category.objects.filter',
            side_effect=raced_filter,
        ):
            confirmed = confirm_preview(batch=batch, device_session=self.device)

        self.assertEqual(confirmed.status, ImportBatch.COMPLETED)
        self.assertEqual(Transaction.objects.filter(category=existing).count(), 1)

    def test_late_source_reference_collision_rolls_back_every_confirmation_write(self):
        batch = self._bound_preview()
        original_save = services._save
        writes = 0

        def collision_on_second_reference(instance):
            nonlocal writes
            if isinstance(instance, SourceReference):
                writes += 1
                if writes == 2:
                    raise IntegrityError('simulated late source reference collision')
            return original_save(instance)

        with patch('imports.services._save', side_effect=collision_on_second_reference):
            with self.assertRaises(ImportConflictError):
                confirm_preview(batch=batch, device_session=self.device)

        self.assertEqual(
            Transaction.objects.filter(household=self.household).count(), 0
        )
        self.assertEqual(
            SourceReference.objects.filter(account=self.account).count(), 0
        )
        self.assertFalse(
            Category.objects.filter(
                household=self.household,
                name='Não categorizado',
            ).exists()
        )
        restored = ImportBatch.objects.get(pk=batch.pk)
        self.assertEqual(restored.status, ImportBatch.PREVIEW_READY)
        self.assertEqual(
            list(restored.records.values_list('outcome', flat=True)),
            [ImportRecord.PENDING, ImportRecord.PENDING],
        )

    def test_confirmation_skips_duplicates_and_creates_warnings(self):
        batch = self._bound_preview()
        duplicate = batch.records.get(line_number=1)
        duplicate.outcome = ImportRecord.DUPLICATE
        duplicate.full_clean()
        duplicate.save(update_fields=['outcome'])
        warning = batch.records.get(line_number=2)
        warning.outcome = ImportRecord.WARNING
        warning.full_clean()
        warning.save(update_fields=['outcome'])

        confirmed = confirm_preview(batch=batch, device_session=self.device)

        self.assertEqual(
            Transaction.objects.filter(household=self.household).count(), 1
        )
        self.assertEqual(
            ImportRecord.objects.get(pk=duplicate.pk).outcome,
            ImportRecord.DUPLICATE,
        )
        self.assertEqual(
            ImportRecord.objects.get(pk=warning.pk).outcome,
            ImportRecord.CREATED,
        )
        self.assertEqual(confirmed.created_count, 1)
        self.assertEqual(confirmed.duplicate_count, 1)
        self.assertEqual(confirmed.warning_count, 0)

    def test_bank_preview_rejects_credit_account_for_auto_link_and_manual_bind(self):
        credit_account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Synthetic credit card',
            type=Account.CREDIT,
        )
        ImportAccountLink.objects.create(
            household=self.household,
            account=credit_account,
            provider='nubank',
            product_type='bank_account',
            external_account_id='synthetic-account-001',
        )
        with self.assertRaises(ImportStateError):
            create_preview(
                household=self.household,
                device_session=self.device,
                content=self.content,
            )

        ImportAccountLink.objects.all().delete()
        batch = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content,
        )
        with self.assertRaises(ImportStateError):
            bind_preview_account(batch=batch, account=credit_account)

    def test_purge_removes_only_normalized_preview_records_and_keeps_receipts(self):
        now = timezone.now()
        expired = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content,
        )
        cancelled = create_preview(
            household=self.other_household,
            device_session=self.other_device,
            content=self.content,
        )
        ImportBatch.objects.filter(pk=expired.pk).update(
            expires_at=now - timedelta(seconds=1)
        )
        ImportBatch.objects.filter(pk=cancelled.pk).update(
            status=ImportBatch.CANCELLED
        )
        cancelled.refresh_from_db()
        completed = self._completed_batch()
        ImportRecord.objects.create(
            batch=completed,
            line_number=1,
            posted_on=date(2026, 1, 1),
            amount=Decimal('1.00'),
            description='Synthetic completed receipt',
            transaction_type='income',
            fingerprint='a' * 64,
            outcome=ImportRecord.CREATED,
        )
        preview_record_count = expired.records.count() + cancelled.records.count()

        deleted = services.purge_preview_records(now=now)

        self.assertEqual(deleted, preview_record_count)
        self.assertFalse(ImportRecord.objects.filter(batch=expired).exists())
        self.assertFalse(ImportRecord.objects.filter(batch=cancelled).exists())
        self.assertTrue(ImportRecord.objects.filter(batch=completed).exists())
        self.assertEqual(
            ImportBatch.objects.get(pk=expired.pk).status,
            ImportBatch.FAILED,
        )
        self.assertEqual(
            ImportBatch.objects.get(pk=cancelled.pk).status,
            ImportBatch.CANCELLED,
        )
        self.assertTrue(ImportBatch.objects.filter(pk=completed.pk).exists())

    def test_cancel_immediately_removes_normalized_records_but_keeps_batch_counts(self):
        batch = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content,
        )
        counts = (batch.created_count, batch.duplicate_count, batch.warning_count)

        cancelled = cancel_preview(batch=batch)

        self.assertEqual(cancelled.status, ImportBatch.CANCELLED)
        self.assertEqual(
            (
                cancelled.created_count,
                cancelled.duplicate_count,
                cancelled.warning_count,
            ),
            counts,
        )
        self.assertFalse(cancelled.records.exists())

    def test_unlinked_repeated_file_receipt_can_be_cancelled(self):
        completed = self._completed_batch()
        completed.file_sha256 = self._sha256(self.content)
        completed.save(update_fields=['file_sha256'])
        repeated = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content,
        )
        self.assertEqual(repeated.status, ImportBatch.PREVIEW_READY)
        self.assertIsNone(repeated.account_id)

        cancelled = cancel_preview(batch=repeated)

        self.assertEqual(cancelled.status, ImportBatch.CANCELLED)

    @patch('imports.management.commands.purge_import_previews.purge_preview_records')
    def test_purge_management_command_is_idempotent_entry_point(self, purge):
        purge.return_value = 3

        call_command('purge_import_previews')

        purge.assert_called_once_with()

    def test_next_purge_delay_uses_nearest_expiry_with_hourly_cap(self):
        now = timezone.now()
        self.assertEqual(
            next_preview_purge_delay(max_delay_seconds=3600, now=now),
            3600.0,
        )
        batch = create_preview(
            household=self.household,
            device_session=self.device,
            content=self.content,
        )
        ImportBatch.objects.filter(pk=batch.pk).update(
            expires_at=now + timedelta(minutes=15)
        )

        self.assertEqual(
            next_preview_purge_delay(max_delay_seconds=3600, now=now),
            900.0,
        )

    def _setup_household(self, email):
        user = get_user_model().objects.create_user(email=email, password='password')
        household = ensure_household_for_user(user)
        owner = get_financial_owner(household, FinancialOwner.SELF)
        account = Account.objects.create(
            user=user,
            household=household,
            financial_owner=owner,
            name=f'Account {email}',
        )
        device = DeviceSession.objects.create(
            user=user,
            household=household,
            default_owner=owner,
            platform=DeviceSession.WINDOWS,
            name=f'Device {email}',
            access_token_digest=(f'access-{email}'.ljust(64, 'x'))[:64],
            access_expires_at='2027-01-01T00:00:00Z',
            refresh_token_digest=(f'refresh-{email}'.ljust(64, 'y'))[:64],
            refresh_expires_at='2027-01-01T00:00:00Z',
        )
        return user, household, owner, account, device

    def _completed_batch(self):
        return ImportBatch.objects.create(
            household=self.household,
            device_session=self.device,
            account=self.account,
            financial_owner=self.owner,
            provider='nubank',
            product_type='bank_account',
            external_account_id='synthetic-account-001',
            file_sha256='0' * 64,
            statement_start=date(2026, 1, 1),
            statement_end=date(2026, 1, 31),
            expires_at='2027-01-01T00:00:00Z',
            status=ImportBatch.COMPLETED,
        )

    def _bound_preview(self, content=None):
        batch = create_preview(
            household=self.household,
            device_session=self.device,
            content=content or self.content,
        )
        return bind_preview_account(batch=batch, account=self.account)

    def _transaction(self, user, household, owner, account):
        category = Category.objects.create(
            user=user,
            household=household,
            name=f'Category {user.pk}',
            type=Category.EXPENSE,
        )
        return Transaction.objects.create(
            user=user,
            household=household,
            financial_owner=owner,
            account=account,
            category=category,
            description='Synthetic existing',
            amount=Decimal('1.00'),
            date=date(2026, 1, 1),
            type=Transaction.EXPENSE,
        )

    def _fingerprint(self, account):
        value = f'{account.uuid}|2026-01-02|-42.5|expense|Synthetic market purchase'
        return self._sha256(value.encode())

    def _sha256(self, content):
        import hashlib

        return hashlib.sha256(content).hexdigest()


class ImportMutationSerializationTest(SimpleTestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.lock_path = str(Path(self.temp_dir.name) / 'imports.lock')

    def test_purge_and_confirmation_cannot_enter_write_sections_together(self):
        context = multiprocessing.get_context('spawn')
        db_path = str(Path(self.temp_dir.name) / 'process.sqlite3')
        metadata_path = str(Path(self.temp_dir.name) / 'metadata.json')
        marker_path = str(Path(self.temp_dir.name) / 'purge-active')
        overlap_path = str(Path(self.temp_dir.name) / 'overlap')
        seed = context.Process(
            target=seed_process_database,
            args=(
                db_path,
                self.lock_path,
                str(FIXTURES / 'nubank-account.ofx'),
                metadata_path,
            ),
        )
        seed.start()
        wait_until_process_finishes(seed)
        self.assertEqual(seed.exitcode, 0)
        metadata = json.loads(Path(metadata_path).read_text(encoding='utf-8'))

        purge_entered = context.Event()
        release_purge = context.Event()
        confirm_ready = context.Event()
        confirm_entered = context.Event()
        purge = context.Process(
            target=purge_process,
            args=(
                db_path,
                self.lock_path,
                purge_entered,
                release_purge,
                marker_path,
            ),
        )
        confirm = context.Process(
            target=confirm_process,
            args=(
                db_path,
                self.lock_path,
                metadata['confirm_batch_id'],
                metadata['device_id'],
                marker_path,
                overlap_path,
                confirm_ready,
                confirm_entered,
            ),
        )
        purge.start()
        try:
            self.assertTrue(purge_entered.wait(timeout=5))
            confirm.start()
            self.assertTrue(confirm_ready.wait(timeout=5))
            self.assertFalse(confirm_entered.wait(timeout=0.25))
            self.assertFalse(Path(overlap_path).exists())
            release_purge.set()
            self.assertTrue(confirm_entered.wait(timeout=5))
            wait_until_process_finishes(purge)
            wait_until_process_finishes(confirm)
        finally:
            release_purge.set()
            for process in (purge, confirm):
                if process.pid is not None and process.is_alive():
                    process.terminate()
                if process.pid is not None:
                    process.join(timeout=5)

        self.assertEqual(purge.exitcode, 0)
        self.assertEqual(confirm.exitcode, 0)
        self.assertFalse(Path(overlap_path).exists())
        with closing(sqlite3.connect(db_path)) as database:
            expired_status = database.execute(
                'SELECT status FROM imports_importbatch WHERE id = ?',
                (metadata['expired_batch_id'].replace('-', ''),),
            ).fetchone()[0]
            expired_records = database.execute(
                'SELECT COUNT(*) FROM imports_importrecord WHERE batch_id = ?',
                (metadata['expired_batch_id'].replace('-', ''),),
            ).fetchone()[0]
            confirm_status = database.execute(
                'SELECT status FROM imports_importbatch WHERE id = ?',
                (metadata['confirm_batch_id'].replace('-', ''),),
            ).fetchone()[0]
        self.assertEqual(expired_status, ImportBatch.FAILED)
        self.assertEqual(expired_records, 0)
        self.assertEqual(confirm_status, ImportBatch.COMPLETED)

    def test_transient_sqlite_lock_is_retried_with_a_finite_limit(self):
        attempts = 0

        def locked_then_succeeds():
            nonlocal attempts
            attempts += 1
            if attempts < 3:
                raise OperationalError('database is locked')
            return 'receipt'

        with (
            self.settings(
                IMPORT_MUTATION_LOCK_PATH=self.lock_path,
                IMPORT_MUTATION_LOCK_RETRIES=3,
                IMPORT_MUTATION_LOCK_RETRY_DELAY_SECONDS=0,
            ),
            patch('imports.services.connection.vendor', 'sqlite'),
        ):
            result = services._run_serialized_import_mutation(
                locked_then_succeeds
            )

        self.assertEqual(result, 'receipt')
        self.assertEqual(attempts, 3)

    def test_exhausted_sqlite_lock_retries_raise_safe_domain_error(self):
        with (
            self.settings(
                IMPORT_MUTATION_LOCK_PATH=self.lock_path,
                IMPORT_MUTATION_LOCK_RETRIES=2,
                IMPORT_MUTATION_LOCK_RETRY_DELAY_SECONDS=0,
            ),
            patch('imports.services.connection.vendor', 'sqlite'),
            self.assertRaises(ImportBusyError),
        ):
            services._run_serialized_import_mutation(
                lambda: (_ for _ in ()).throw(
                    OperationalError('database is locked')
                )
            )
