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


class TransactionViewTest(TestCase):
    """8.2.2 + 8.2.3 — list filtering and CRUD for transactions."""

    def setUp(self):
        self.user = User.objects.create_user(email='eve@example.com', password='pass123')
        self.other_user = User.objects.create_user(email='frank@example.com', password='pass123')
        self.client.login(username='eve@example.com', password='pass123')

        self.account = Account.objects.create(
            user=self.user, name='Nubank', type=Account.CHECKING, initial_balance=Decimal('0')
        )
        self.other_account = Account.objects.create(
            user=self.other_user, name='Bradesco', type=Account.SAVINGS, initial_balance=Decimal('0')
        )
        self.category = Category.objects.create(user=self.user, name='Salário', type=Category.INCOME)
        self.other_category = Category.objects.create(
            user=self.other_user, name='Aluguel', type=Category.EXPENSE
        )

        self.tx = Transaction.objects.create(
            user=self.user,
            account=self.account,
            category=self.category,
            description='Pagamento',
            amount=Decimal('1000'),
            date=datetime.date(2026, 1, 15),
            type=Transaction.INCOME,
        )
        self.other_tx = Transaction.objects.create(
            user=self.other_user,
            account=self.other_account,
            category=self.other_category,
            description='Aluguel janeiro',
            amount=Decimal('1500'),
            date=datetime.date(2026, 1, 10),
            type=Transaction.EXPENSE,
        )

    def _post_data(self, **overrides):
        data = {
            'account': self.account.pk,
            'category': self.category.pk,
            'description': 'Nova transação',
            'amount': '200.00',
            'date': '2026-02-01',
            'type': Transaction.INCOME,
        }
        data.update(overrides)
        return data

    def test_list_shows_only_own_transactions(self):
        response = self.client.get('/transacoes/')
        self.assertEqual(response.status_code, 200)
        transactions = list(response.context['transactions'])
        self.assertIn(self.tx, transactions)
        self.assertNotIn(self.other_tx, transactions)

    def test_create_transaction(self):
        response = self.client.post('/transacoes/nova/', self._post_data())
        self.assertRedirects(response, '/transacoes/')
        self.assertTrue(
            Transaction.objects.filter(user=self.user, description='Nova transação').exists()
        )

    def test_update_transaction(self):
        response = self.client.post(
            f'/transacoes/{self.tx.pk}/editar/',
            self._post_data(description='Atualizado'),
        )
        self.assertRedirects(response, '/transacoes/')
        self.tx.refresh_from_db()
        self.assertEqual(self.tx.description, 'Atualizado')

    def test_delete_transaction(self):
        response = self.client.post(f'/transacoes/{self.tx.pk}/excluir/')
        self.assertRedirects(response, '/transacoes/')
        self.assertFalse(Transaction.objects.filter(pk=self.tx.pk).exists())

    def test_cannot_update_other_user_transaction(self):
        response = self.client.post(
            f'/transacoes/{self.other_tx.pk}/editar/',
            self._post_data(description='Hackeada'),
        )
        self.assertEqual(response.status_code, 404)

    def test_cannot_delete_other_user_transaction(self):
        response = self.client.post(f'/transacoes/{self.other_tx.pk}/excluir/')
        self.assertEqual(response.status_code, 404)


class TransactionFilterViewTest(TestCase):
    """8.2.4 — transaction list view filters."""

    def setUp(self):
        self.user = User.objects.create_user(email='gina@example.com', password='pass123')
        self.client.login(username='gina@example.com', password='pass123')

        self.account = Account.objects.create(
            user=self.user, name='Conta', type=Account.CHECKING, initial_balance=Decimal('0')
        )
        self.account2 = Account.objects.create(
            user=self.user, name='Poupança', type=Account.SAVINGS, initial_balance=Decimal('0')
        )
        self.cat_income = Category.objects.create(user=self.user, name='Salário', type=Category.INCOME)
        self.cat_expense = Category.objects.create(user=self.user, name='Aluguel', type=Category.EXPENSE)

        self.tx_jan_income = Transaction.objects.create(
            user=self.user, account=self.account, category=self.cat_income,
            description='Salário jan', amount=Decimal('3000'), date=datetime.date(2026, 1, 5),
            type=Transaction.INCOME,
        )
        self.tx_jan_expense = Transaction.objects.create(
            user=self.user, account=self.account2, category=self.cat_expense,
            description='Aluguel jan', amount=Decimal('1200'), date=datetime.date(2026, 1, 10),
            type=Transaction.EXPENSE,
        )
        self.tx_feb_income = Transaction.objects.create(
            user=self.user, account=self.account, category=self.cat_income,
            description='Salário fev', amount=Decimal('3000'), date=datetime.date(2026, 2, 5),
            type=Transaction.INCOME,
        )

    def _get_transactions(self, params):
        response = self.client.get('/transacoes/', params)
        self.assertEqual(response.status_code, 200)
        return list(response.context['transactions'])

    def test_filter_date_from(self):
        txs = self._get_transactions({'date_from': '2026-01-08'})
        self.assertNotIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertIn(self.tx_feb_income, txs)

    def test_filter_date_to(self):
        txs = self._get_transactions({'date_to': '2026-01-31'})
        self.assertIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertNotIn(self.tx_feb_income, txs)

    def test_filter_date_range(self):
        txs = self._get_transactions({'date_from': '2026-01-01', 'date_to': '2026-01-31'})
        self.assertIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertNotIn(self.tx_feb_income, txs)

    def test_filter_by_account(self):
        txs = self._get_transactions({'account': self.account.pk})
        self.assertIn(self.tx_jan_income, txs)
        self.assertNotIn(self.tx_jan_expense, txs)
        self.assertIn(self.tx_feb_income, txs)

    def test_filter_by_category(self):
        txs = self._get_transactions({'category': self.cat_expense.pk})
        self.assertNotIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertNotIn(self.tx_feb_income, txs)

    def test_filter_by_type_income(self):
        txs = self._get_transactions({'type': Transaction.INCOME})
        self.assertIn(self.tx_jan_income, txs)
        self.assertNotIn(self.tx_jan_expense, txs)
        self.assertIn(self.tx_feb_income, txs)

    def test_filter_by_type_expense(self):
        txs = self._get_transactions({'type': Transaction.EXPENSE})
        self.assertNotIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertNotIn(self.tx_feb_income, txs)

    def test_no_filter_returns_all_own_transactions(self):
        txs = self._get_transactions({})
        self.assertIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertIn(self.tx_feb_income, txs)
