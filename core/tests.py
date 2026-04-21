import datetime
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse

from accounts.models import Account
from categories.models import Category
from transactions.models import Transaction

User = get_user_model()


class ProtectedRouteRedirectTest(TestCase):
    """8.2.1 — unauthenticated requests redirect to login."""

    def setUp(self):
        self.user = User.objects.create_user(email='anon@example.com', password='pass123')
        self.account = Account.objects.create(
            user=self.user, name='Conta', type=Account.CHECKING, initial_balance=Decimal('0')
        )
        self.category = Category.objects.create(
            user=self.user, name='Cat', type=Category.EXPENSE
        )
        self.transaction = Transaction.objects.create(
            user=self.user,
            account=self.account,
            category=self.category,
            description='Tx',
            amount=Decimal('10'),
            date=datetime.date.today(),
            type=Transaction.EXPENSE,
        )

    def _assert_redirects_to_login(self, url):
        response = self.client.get(url)
        self.assertEqual(response.status_code, 302, f'{url} should redirect')
        self.assertIn('/login/', response['Location'])

    def test_dashboard_redirects(self):
        self._assert_redirects_to_login('/dashboard/')

    def test_accounts_list_redirects(self):
        self._assert_redirects_to_login('/accounts/')

    def test_accounts_create_redirects(self):
        self._assert_redirects_to_login('/accounts/new/')

    def test_accounts_update_redirects(self):
        self._assert_redirects_to_login(f'/accounts/{self.account.pk}/edit/')

    def test_accounts_delete_redirects(self):
        self._assert_redirects_to_login(f'/accounts/{self.account.pk}/delete/')

    def test_categories_list_redirects(self):
        self._assert_redirects_to_login('/categories/')

    def test_categories_create_redirects(self):
        self._assert_redirects_to_login('/categories/novo/')

    def test_categories_update_redirects(self):
        self._assert_redirects_to_login(f'/categories/{self.category.pk}/editar/')

    def test_categories_delete_redirects(self):
        self._assert_redirects_to_login(f'/categories/{self.category.pk}/excluir/')

    def test_transactions_list_redirects(self):
        self._assert_redirects_to_login('/transacoes/')

    def test_transactions_create_redirects(self):
        self._assert_redirects_to_login('/transacoes/nova/')

    def test_transactions_update_redirects(self):
        self._assert_redirects_to_login(f'/transacoes/{self.transaction.pk}/editar/')

    def test_transactions_delete_redirects(self):
        self._assert_redirects_to_login(f'/transacoes/{self.transaction.pk}/excluir/')

    def test_profile_edit_redirects(self):
        self._assert_redirects_to_login('/profile/edit/')
