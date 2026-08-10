import datetime
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from transactions.models import Transaction

User = get_user_model()


class ProtectedRouteRedirectTest(TestCase):
    """8.2.1 — unauthenticated requests redirect to login."""

    def setUp(self):
        self.user = User.objects.create_user(email='anon@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.shared_owner = get_financial_owner(self.household)
        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Conta',
            type=Account.CHECKING,
            initial_balance=Decimal('0'),
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Cat',
            type=Category.EXPENSE,
        )
        self.transaction = Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
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


class PrivateEntryPointTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='private-entry@example.com',
            password='test-password-123',
        )
        self.household = ensure_household_for_user(self.user)

    def test_public_signup_is_not_exposed(self):
        response = self.client.get('/signup/')

        self.assertEqual(response.status_code, 404)

    def test_root_redirects_anonymous_user_to_login(self):
        response = self.client.get('/')

        self.assertRedirects(response, '/login/')

    def test_root_redirects_authenticated_user_to_dashboard(self):
        self.client.force_login(self.user)

        response = self.client.get('/')

        self.assertRedirects(response, '/dashboard/')


class DashboardHouseholdScopeTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='dashboard@example.com',
            password='pass123',
        )
        self.other_user = User.objects.create_user(
            email='other-dashboard@example.com',
            password='pass123',
        )
        self.household = ensure_household_for_user(self.user)
        self.other_household = ensure_household_for_user(self.other_user)
        self.self_owner = get_financial_owner(self.household, FinancialOwner.SELF)
        self.spouse_owner = get_financial_owner(self.household, FinancialOwner.SPOUSE)
        self.shared_owner = get_financial_owner(self.household)
        self.other_shared_owner = get_financial_owner(self.other_household)
        self.client.force_login(self.user)

        self.self_account = self._create_account(
            user=self.user,
            household=self.household,
            financial_owner=self.self_owner,
            name='Conta Eu',
            balance='500.00',
        )
        self.spouse_account = self._create_account(
            user=self.other_user,
            household=self.household,
            financial_owner=self.spouse_owner,
            name='Conta Esposa',
            balance='400.00',
        )
        self.shared_account = self._create_account(
            user=self.other_user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Conta Conjunto',
            balance='600.00',
        )
        self.foreign_account = self._create_account(
            user=self.user,
            household=self.other_household,
            financial_owner=self.other_shared_owner,
            name='Conta Outro Lar',
            balance='9000.00',
        )

    def _create_account(self, *, user, household, financial_owner, name, balance):
        return Account.objects.create(
            user=user,
            household=household,
            financial_owner=financial_owner,
            name=name,
            type=Account.CHECKING,
            initial_balance=Decimal(balance),
        )

    def test_dashboard_consolidates_all_three_owners(self):
        response = self.client.get('/dashboard/')

        self.assertEqual(response.context['total_balance'], Decimal('1500.00'))

    def test_dashboard_transactions_are_scoped_by_household(self):
        household_category = Category.objects.create(
            user=self.other_user,
            household=self.household,
            name='Despesa do Lar',
            type=Category.EXPENSE,
        )
        foreign_category = Category.objects.create(
            user=self.user,
            household=self.other_household,
            name='Despesa de Outro Lar',
            type=Category.EXPENSE,
        )
        today = timezone.localdate()
        household_income = Transaction.objects.create(
            user=self.other_user,
            household=self.household,
            financial_owner=self.spouse_owner,
            account=self.spouse_account,
            category=household_category,
            description='Receita do Lar',
            amount=Decimal('200.00'),
            date=today,
            type=Transaction.INCOME,
        )
        household_expense = Transaction.objects.create(
            user=self.other_user,
            household=self.household,
            financial_owner=self.shared_owner,
            account=self.shared_account,
            category=household_category,
            description='Despesa do Lar',
            amount=Decimal('50.00'),
            date=today,
            type=Transaction.EXPENSE,
        )
        foreign_transaction = Transaction.objects.create(
            user=self.user,
            household=self.other_household,
            financial_owner=self.other_shared_owner,
            account=self.foreign_account,
            category=foreign_category,
            description='Despesa de Outro Lar',
            amount=Decimal('8000.00'),
            date=today,
            type=Transaction.EXPENSE,
        )

        response = self.client.get('/dashboard/')

        self.assertEqual(response.context['monthly_income'], Decimal('200.00'))
        self.assertEqual(response.context['monthly_expenses'], Decimal('50.00'))
        expenses = list(response.context['expenses_by_category'])
        self.assertEqual(expenses[0]['category__name'], household_category.name)
        recent_transactions = list(response.context['recent_transactions'])
        self.assertIn(household_income, recent_transactions)
        self.assertIn(household_expense, recent_transactions)
        self.assertNotIn(foreign_transaction, recent_transactions)
