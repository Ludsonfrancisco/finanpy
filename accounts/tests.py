import datetime
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from accounts.models import Account
from categories.models import Category
from transactions.models import Transaction

User = get_user_model()


class AccountCurrentBalanceTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='grace@example.com', password='pass123')
        self.account = Account.objects.create(
            user=self.user,
            name='Conta Principal',
            type=Account.CHECKING,
            initial_balance=Decimal('1000.00'),
        )
        self.category = Category.objects.create(
            user=self.user,
            name='Outros',
            type=Category.EXPENSE,
        )

    def _make_transaction(self, amount, tx_type):
        return Transaction.objects.create(
            user=self.user,
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
        self.client.login(username='alice@example.com', password='pass123')

        self.account = Account.objects.create(
            user=self.user, name='Minha Conta', type=Account.CHECKING, initial_balance=Decimal('500')
        )
        self.other_account = Account.objects.create(
            user=self.other_user, name='Conta Alheia', type=Account.SAVINGS, initial_balance=Decimal('100')
        )

    def test_list_shows_only_own_accounts(self):
        response = self.client.get('/accounts/')
        self.assertEqual(response.status_code, 200)
        accounts = list(response.context['accounts'])
        self.assertIn(self.account, accounts)
        self.assertNotIn(self.other_account, accounts)

    def test_create_account(self):
        response = self.client.post('/accounts/new/', {
            'name': 'Nova Conta',
            'type': Account.SAVINGS,
            'initial_balance': '1000.00',
            'currency': 'BRL',
        })
        self.assertRedirects(response, '/accounts/')
        self.assertTrue(Account.objects.filter(user=self.user, name='Nova Conta').exists())

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

    def test_delete_account(self):
        response = self.client.post(f'/accounts/{self.account.pk}/delete/')
        self.assertRedirects(response, '/accounts/')
        self.assertFalse(Account.objects.filter(pk=self.account.pk).exists())

    def test_cannot_update_other_user_account(self):
        response = self.client.post(f'/accounts/{self.other_account.pk}/edit/', {
            'name': 'Hackeada',
            'type': Account.CHECKING,
            'initial_balance': '0',
            'currency': 'BRL',
        })
        self.assertEqual(response.status_code, 404)

    def test_cannot_delete_other_user_account(self):
        response = self.client.post(f'/accounts/{self.other_account.pk}/delete/')
        self.assertEqual(response.status_code, 404)
