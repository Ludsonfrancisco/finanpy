import datetime
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase

from accounts.models import Account
from categories.models import Category
from households.services import ensure_household_for_user, get_financial_owner
from transactions.models import Transaction

User = get_user_model()


class AccountCurrentBalanceTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='grace@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.shared_owner = get_financial_owner(self.household)
        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Conta Principal',
            type=Account.CHECKING,
            initial_balance=Decimal('1000.00'),
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Outros',
            type=Category.EXPENSE,
        )

    def _make_transaction(self, amount, tx_type):
        return Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            account=self.account,
            category=self.category,
            description='Teste',
            amount=Decimal(str(amount)),
            date=datetime.date.today(),
            type=tx_type,
        )

    def test_current_balance_equals_initial_balance_when_no_transactions(self):
        self.assertEqual(self.account.current_balance, Decimal('1000.00'))

    def test_income_transaction_increases_balance(self):
        self._make_transaction('500.00', Transaction.INCOME)
        self.assertEqual(self.account.current_balance, Decimal('1500.00'))

    def test_expense_transaction_decreases_balance(self):
        self._make_transaction('300.00', Transaction.EXPENSE)
        self.assertEqual(self.account.current_balance, Decimal('700.00'))

    def test_combined_income_and_expense_transactions(self):
        self._make_transaction('200.00', Transaction.INCOME)
        self._make_transaction('50.00', Transaction.INCOME)
        self._make_transaction('400.00', Transaction.EXPENSE)
        # 1000 + 200 + 50 - 400 = 850
        self.assertEqual(self.account.current_balance, Decimal('850.00'))

    def test_current_balance_zero_initial_balance(self):
        account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Conta Zerada',
            type=Account.CASH,
            initial_balance=Decimal('0.00'),
        )
        self.assertEqual(account.current_balance, Decimal('0.00'))


class AccountViewTest(TestCase):
    """8.2.2 + 8.2.3 — list filtering and CRUD for accounts."""

    def setUp(self):
        self.user = User.objects.create_user(email='alice@example.com', password='pass123')
        self.other_user = User.objects.create_user(email='bob@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.other_household = ensure_household_for_user(self.other_user)
        self.shared_owner = get_financial_owner(self.household)
        self.other_shared_owner = get_financial_owner(self.other_household)
        self.client.login(username='alice@example.com', password='pass123')

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Minha Conta',
            type=Account.CHECKING,
            initial_balance=Decimal('500'),
        )
        self.other_account = Account.objects.create(
            user=self.user,
            household=self.other_household,
            financial_owner=self.other_shared_owner,
            name='Conta Alheia',
            type=Account.SAVINGS,
            initial_balance=Decimal('100'),
        )

    def test_account_list_is_scoped_by_household(self):
        response = self.client.get('/accounts/')

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, self.account.name)
        self.assertNotContains(response, self.other_account.name)

    def test_create_account(self):
        response = self.client.post('/accounts/new/', {
            'name': 'Nova Conta',
            'type': Account.SAVINGS,
            'initial_balance': '1000.00',
            'currency': 'BRL',
        })
        self.assertRedirects(response, '/accounts/')
        account = Account.objects.get(user=self.user, name='Nova Conta')
        self.assertEqual(account.household, self.household)
        self.assertEqual(account.financial_owner, self.shared_owner)

    def test_update_account(self):
        response = self.client.post(f'/accounts/{self.account.pk}/edit/', {
            'name': 'Conta Atualizada',
            'type': Account.CHECKING,
            'initial_balance': '500.00',
            'currency': 'BRL',
        })
        self.assertRedirects(response, '/accounts/')
        self.account.refresh_from_db()
        self.assertEqual(self.account.name, 'Conta Atualizada')

    def test_create_account_with_revoked_membership_shows_form_error(self):
        with patch(
            'households.validators.has_active_household_membership',
            return_value=False,
        ):
            response = self.client.post('/accounts/new/', {
                'name': 'Conta bloqueada',
                'type': Account.SAVINGS,
                'initial_balance': '1000.00',
                'currency': 'BRL',
            })

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.context['form'].non_field_errors())
        self.assertFalse(Account.objects.filter(name='Conta bloqueada').exists())

    def test_update_account_with_revoked_membership_preserves_data(self):
        with patch(
            'households.validators.has_active_household_membership',
            return_value=False,
        ):
            response = self.client.post(f'/accounts/{self.account.pk}/edit/', {
                'name': 'Conta bloqueada',
                'type': Account.CHECKING,
                'initial_balance': '500.00',
                'currency': 'BRL',
            })

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.context['form'].non_field_errors())
        self.account.refresh_from_db()
        self.assertEqual(self.account.name, 'Minha Conta')

    def test_delete_account(self):
        response = self.client.post(f'/accounts/{self.account.pk}/delete/')
        self.assertRedirects(response, '/accounts/')
        self.assertFalse(Account.objects.filter(pk=self.account.pk).exists())

    def test_cannot_update_account_from_other_household(self):
        response = self.client.post(f'/accounts/{self.other_account.pk}/edit/', {
            'name': 'Hackeada',
            'type': Account.CHECKING,
            'initial_balance': '0',
            'currency': 'BRL',
        })
        self.assertEqual(response.status_code, 404)

    def test_cannot_delete_account_from_other_household(self):
        response = self.client.post(f'/accounts/{self.other_account.pk}/delete/')
        self.assertEqual(response.status_code, 404)
