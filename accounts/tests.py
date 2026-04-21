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
