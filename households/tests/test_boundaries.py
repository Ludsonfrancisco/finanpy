from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.db import IntegrityError
from django.test import TestCase

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from transactions.models import Transaction

User = get_user_model()


class HouseholdBoundaryTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='one@example.com', password='test-pass')
        self.other_user = User.objects.create_user(email='two@example.com', password='test-pass')
        self.household = ensure_household_for_user(self.user)
        self.other_household = ensure_household_for_user(self.other_user)
        self.owner = get_financial_owner(self.household, FinancialOwner.SHARED)
        self.other_owner = get_financial_owner(self.other_household, FinancialOwner.SHARED)
        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Conta do Lar',
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Mercado',
            type=Category.EXPENSE,
        )
        self.other_account = Account.objects.create(
            user=self.other_user,
            household=self.other_household,
            financial_owner=self.other_owner,
            name='Conta de outro Lar',
        )
        self.other_category = Category.objects.create(
            user=self.other_user,
            household=self.other_household,
            name='Outra categoria',
            type=Category.EXPENSE,
        )

    def test_account_rejects_owner_from_another_household(self):
        account = Account(
            user=self.user,
            household=self.household,
            financial_owner=self.other_owner,
            name='Conta inválida',
            initial_balance=Decimal('0.00'),
        )

        with self.assertRaises(ValidationError):
            account.full_clean()

    def test_account_requires_household_and_owner(self):
        account = Account(user=self.user, name='Sem Lar')

        with self.assertRaises(ValidationError):
            account.full_clean()

    def test_category_requires_household(self):
        category = Category(
            user=self.user,
            name='Sem Lar',
            type=Category.EXPENSE,
        )

        with self.assertRaises(ValidationError):
            category.full_clean()

    def test_categories_are_unique_inside_household(self):
        with self.assertRaises(IntegrityError):
            Category.objects.create(
                user=self.other_user,
                household=self.household,
                name='Mercado',
                type=Category.EXPENSE,
            )

    def test_category_name_and_type_can_repeat_in_another_household(self):
        category = Category.objects.create(
            user=self.user,
            household=self.other_household,
            name='Mercado',
            type=Category.EXPENSE,
        )

        self.assertEqual(category.household, self.other_household)

    def _transaction(self, **overrides):
        values = {
            'user': self.user,
            'household': self.household,
            'financial_owner': self.owner,
            'account': self.account,
            'category': self.category,
            'description': 'Compra',
            'amount': Decimal('10.00'),
            'date': '2026-08-10',
            'type': Transaction.EXPENSE,
        }
        values.update(overrides)
        return Transaction(**values)

    def test_transaction_rejects_account_from_another_household(self):
        with self.assertRaises(ValidationError):
            self._transaction(account=self.other_account).full_clean()

    def test_transaction_rejects_category_from_another_household(self):
        with self.assertRaises(ValidationError):
            self._transaction(category=self.other_category).full_clean()

    def test_transaction_rejects_owner_from_another_household(self):
        with self.assertRaises(ValidationError):
            self._transaction(financial_owner=self.other_owner).full_clean()

    def test_transaction_requires_household_and_owner(self):
        transaction = self._transaction(household=None, financial_owner=None)

        with self.assertRaises(ValidationError):
            transaction.full_clean()
