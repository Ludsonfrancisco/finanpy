from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TransactionTestCase

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from imports.models import ImportAccountLink, ImportBatch, ImportRecord, SourceReference
from transactions.models import Transaction


class ImportModelTest(TransactionTestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(
            email='import-owner@example.com',
            password='password',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, FinancialOwner.SELF)
        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Primary account',
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='General',
            type=Category.EXPENSE,
        )
        self.transaction = Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            account=self.account,
            category=self.category,
            description='Existing transaction',
            amount=Decimal('10.00'),
            date=date(2026, 1, 1),
            type=Transaction.EXPENSE,
        )

    def test_account_link_is_unique_for_household_provider_product_and_external_id(
        self,
    ):
        ImportAccountLink.objects.create(
            household=self.household,
            account=self.account,
            provider='nubank',
            product_type='bank_account',
            external_account_id='account-1',
        )

        with self.assertRaises(IntegrityError):
            ImportAccountLink.objects.create(
                household=self.household,
                account=self.account,
                provider='nubank',
                product_type='bank_account',
                external_account_id='account-1',
            )

    def test_source_reference_fitid_is_unique_for_account_provider_and_external_id(
        self,
    ):
        SourceReference.objects.create(
            account=self.account,
            provider='nubank',
            external_id='fitid-1',
            transaction=self.transaction,
        )

        with self.assertRaises(IntegrityError):
            SourceReference.objects.create(
                account=self.account,
                provider='nubank',
                external_id='fitid-1',
                transaction=self.transaction,
            )

    def test_account_link_rejects_account_from_another_household_on_create(self):
        other_account, _, _ = self._other_household_financial_data()

        with self.assertRaises(IntegrityError):
            ImportAccountLink.objects.create(
                household=self.household,
                account=other_account,
                provider='nubank',
                product_type='bank_account',
                external_account_id='account-2',
            )

    def test_batch_rejects_foreign_device_session_on_create(self):
        _, other_owner, other_household = self._other_household_financial_data()

        with self.assertRaises(IntegrityError):
            self._create_batch(
                device_session_id=self._device_session_id(
                    other_household,
                    other_owner,
                ),
            )

    def test_batch_rejects_foreign_account_on_create(self):
        other_account, _, _ = self._other_household_financial_data()

        with self.assertRaises(IntegrityError):
            self._create_batch(account=other_account)

    def test_batch_rejects_foreign_financial_owner_on_create(self):
        _, other_owner, _ = self._other_household_financial_data()

        with self.assertRaises(IntegrityError):
            self._create_batch(financial_owner=other_owner)

    def test_record_rejects_transaction_from_another_household_on_create(self):
        batch = self._batch()
        other_transaction = self._other_household_transaction()

        with self.assertRaises(IntegrityError):
            ImportRecord.objects.create(
                batch=batch,
                line_number=1,
                posted_on=date(2026, 1, 1),
                amount=Decimal('10.00'),
                description='Imported transaction',
                transaction_type=Transaction.EXPENSE,
                fingerprint='fingerprint-1',
                outcome='pending',
                transaction=other_transaction,
            )

    def test_source_reference_rejects_transaction_from_another_household_on_create(
        self,
    ):
        other_transaction = self._other_household_transaction()

        with self.assertRaises(IntegrityError):
            SourceReference.objects.create(
                account=self.account,
                provider='nubank',
                external_id='fitid-2',
                transaction=other_transaction,
            )

    def _batch(self):
        return self._create_batch()

    def _create_batch(self, **overrides):
        values = {
            'household': self.household,
            'device_session_id': self._device_session_id(),
            'account': self.account,
            'financial_owner': self.owner,
            'provider': 'nubank',
            'product_type': 'bank_account',
            'file_sha256': '1' * 64,
            'statement_start': date(2026, 1, 1),
            'statement_end': date(2026, 1, 31),
            'expires_at': '2026-02-01T00:00:00Z',
        }
        values.update(overrides)
        return ImportBatch.objects.create(**values)

    def _device_session_id(self, household=None, owner=None):
        household = household or self.household
        owner = owner or self.owner
        user = owner.household.memberships.get(is_active=True).user
        from api.models import DeviceSession

        return DeviceSession.objects.create(
            user=user,
            household=household,
            default_owner=owner,
            platform=DeviceSession.WINDOWS,
            name='Import device',
            access_token_digest=f'access-{user.pk}'.ljust(64, '0'),
            access_expires_at='2026-02-01T00:00:00Z',
            refresh_token_digest=f'refresh-{user.pk}'.ljust(64, '0'),
            refresh_expires_at='2026-02-01T00:00:00Z',
        ).pk

    def _other_household_financial_data(self):
        user = get_user_model().objects.create_user(
            email='other-import-owner@example.com',
            password='password',
        )
        household = ensure_household_for_user(user)
        owner = get_financial_owner(household, FinancialOwner.SELF)
        account = Account.objects.create(
            user=user,
            household=household,
            financial_owner=owner,
            name='Other account',
        )
        return account, owner, household

    def _other_household_transaction(self):
        account, owner, household = self._other_household_financial_data()
        category = Category.objects.create(
            user=account.user,
            household=household,
            name='Other general',
            type=Category.EXPENSE,
        )
        return Transaction.objects.create(
            user=account.user,
            household=household,
            financial_owner=owner,
            account=account,
            category=category,
            description='Other transaction',
            amount=Decimal('10.00'),
            date=date(2026, 1, 1),
            type=Transaction.EXPENSE,
        )
