import datetime
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from accounts.models import Account
from categories.models import Category
from transactions.forms import TransactionForm
from transactions.models import Transaction

User = get_user_model()


class TransactionFormTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='irene@example.com', password='pass123')
        self.other_user = User.objects.create_user(email='jack@example.com', password='pass123')

        self.account = Account.objects.create(
            user=self.user,
            name='Nubank',
            type=Account.CHECKING,
            initial_balance=Decimal('0.00'),
        )
        self.other_account = Account.objects.create(
            user=self.other_user,
            name='Bradesco',
            type=Account.SAVINGS,
            initial_balance=Decimal('0.00'),
        )

        self.category = Category.objects.create(
            user=self.user,
            name='Salário',
            type=Category.INCOME,
        )
        self.other_category = Category.objects.create(
            user=self.other_user,
            name='Aluguel',
            type=Category.EXPENSE,
        )

    def _valid_data(self):
        return {
            'account': self.account.pk,
            'category': self.category.pk,
            'description': 'Pagamento mensal',
            'amount': '3500.00',
            'date': datetime.date.today().isoformat(),
            'type': Transaction.INCOME,
        }

    def test_valid_data_passes(self):
        form = TransactionForm(data=self._valid_data(), user=self.user)
        self.assertTrue(form.is_valid(), form.errors)

    def test_missing_description_fails(self):
        data = self._valid_data()
        data['description'] = ''
        form = TransactionForm(data=data, user=self.user)
        self.assertFalse(form.is_valid())
        self.assertIn('description', form.errors)

    def test_missing_amount_fails(self):
        data = self._valid_data()
        data['amount'] = ''
        form = TransactionForm(data=data, user=self.user)
        self.assertFalse(form.is_valid())
        self.assertIn('amount', form.errors)

    def test_missing_date_fails(self):
        data = self._valid_data()
        data['date'] = ''
        form = TransactionForm(data=data, user=self.user)
        self.assertFalse(form.is_valid())
        self.assertIn('date', form.errors)

    def test_account_queryset_scoped_to_user(self):
        form = TransactionForm(user=self.user)
        account_qs = form.fields['account'].queryset
        self.assertIn(self.account, account_qs)
        self.assertNotIn(self.other_account, account_qs)

    def test_category_queryset_scoped_to_user(self):
        form = TransactionForm(user=self.user)
        category_qs = form.fields['category'].queryset
        self.assertIn(self.category, category_qs)
        self.assertNotIn(self.other_category, category_qs)

    def test_other_user_account_rejected_in_form(self):
        data = self._valid_data()
        data['account'] = self.other_account.pk
        form = TransactionForm(data=data, user=self.user)
        self.assertFalse(form.is_valid())
        self.assertIn('account', form.errors)

    def test_other_user_category_rejected_in_form(self):
        data = self._valid_data()
        data['category'] = self.other_category.pk
        form = TransactionForm(data=data, user=self.user)
        self.assertFalse(form.is_valid())
        self.assertIn('category', form.errors)

    def test_form_without_user_shows_all_accounts(self):
        # When no user is passed the queryset falls back to the model default
        form = TransactionForm()
        account_qs = form.fields['account'].queryset
        self.assertIn(self.account, account_qs)
        self.assertIn(self.other_account, account_qs)
