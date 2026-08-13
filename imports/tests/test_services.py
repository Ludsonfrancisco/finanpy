from datetime import date, datetime, timedelta
from datetime import timezone as datetime_timezone
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TestCase
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
    ImportStateError,
    bind_preview_account,
    cancel_preview,
    create_preview,
    get_batch_for_household,
)
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
        content = self.content.replace(b'<FITID>synthetic-fitid-001\n', b'')
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
    def test_preview_expires_in_24_hours_and_does_not_log_financial_data(self, now):
        frozen = datetime(2026, 3, 1, tzinfo=datetime_timezone.utc)
        now.return_value = frozen
        with self.assertNoLogs('imports.services'):
            batch = create_preview(
                household=self.household,
                device_session=self.device,
                content=self.content,
            )

        self.assertEqual(batch.expires_at, frozen + timedelta(hours=24))
        record = batch.records.get(line_number=1)
        self.assertEqual(record.external_id, 'synthetic-fitid-001')
        self.assertEqual(record.description, 'Synthetic market purchase')
        self.assertEqual(record.amount, Decimal('-42.50'))

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
