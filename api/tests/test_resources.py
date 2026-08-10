from decimal import Decimal

from django.db.models import Max
from django.test import TestCase
from django.utils import timezone

from accounts.models import Account
from api.models import DeviceSession
from api.tokens import issue_session
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from sync.cursors import decode_cursor
from sync.models import SyncChange
from transactions.models import Transaction
from users.models import User

RESOURCE_EXPECTATIONS = (
    (
        'bootstrap',
        '/api/v1/bootstrap/',
        ('household', 'owners', 'accounts', 'categories', 'transactions', 'summary', 'cursor'),
    ),
    ('accounts', '/api/v1/accounts/', ('current_household_only', 'no_database_id')),
    ('categories', '/api/v1/categories/', ('current_household_only', 'no_database_id')),
    ('transactions', '/api/v1/transactions/', ('current_household_only', 'no_database_id')),
    ('owners', '/api/v1/owners/', ('uuid', 'type', 'name')),
)


class HouseholdResourceTest(TestCase):
    password = 'Strong-pass-123'

    def setUp(self):
        self.user = User.objects.create_user(
            email='resources@example.test',
            password=self.password,
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type=FinancialOwner.SELF)
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issued.access_token}'}

        self.account = self.create_account(
            user=self.user,
            household=self.household,
            owner=self.owner,
            name='Conta da casa',
        )
        self.category = self.create_category(
            user=self.user,
            household=self.household,
            name='Categoria da casa',
        )
        self.transaction = self.create_transaction(
            user=self.user,
            household=self.household,
            owner=self.owner,
            account=self.account,
            category=self.category,
            description='Transacao da casa',
        )

        self.foreign_user = User.objects.create_user(
            email='foreign@example.test',
            password=self.password,
        )
        self.foreign_household = ensure_household_for_user(self.foreign_user)
        self.foreign_household.name = 'Lar estrangeiro confidencial'
        self.foreign_household.save(update_fields=['name'])
        self.foreign_owner = get_financial_owner(
            self.foreign_household,
            owner_type=FinancialOwner.SELF,
        )
        self.foreign_owner.name = 'Responsavel estrangeiro confidencial'
        self.foreign_owner.save(update_fields=['name'])
        self.foreign_account = self.create_account(
            user=self.foreign_user,
            household=self.foreign_household,
            owner=self.foreign_owner,
            name='Conta estrangeira confidencial',
        )
        self.foreign_category = self.create_category(
            user=self.foreign_user,
            household=self.foreign_household,
            name='Categoria estrangeira confidencial',
        )
        self.foreign_transaction = self.create_transaction(
            user=self.foreign_user,
            household=self.foreign_household,
            owner=self.foreign_owner,
            account=self.foreign_account,
            category=self.foreign_category,
            description='Transacao estrangeira confidencial',
        )
        self.cross_household_transaction = self.create_transaction(
            user=self.foreign_user,
            household=self.foreign_household,
            owner=self.foreign_owner,
            account=self.account,
            category=self.foreign_category,
            description='Lancamento estrangeiro em conta local',
            amount=Decimal('777.00'),
        )
        self.invalid_local_account = self.create_account(
            user=self.user,
            household=self.household,
            owner=self.foreign_owner,
            name='Conta local com responsavel estrangeiro',
            initial_balance=Decimal('888.00'),
        )
        self.invalid_local_transaction = self.create_transaction(
            user=self.user,
            household=self.household,
            owner=self.foreign_owner,
            account=self.foreign_account,
            category=self.foreign_category,
            description='Transacao local com relacoes estrangeiras',
            amount=Decimal('555.00'),
        )

    @staticmethod
    def create_account(
        *,
        user,
        household,
        owner,
        name,
        initial_balance=Decimal('100.00'),
    ):
        return Account.objects.create(
            user=user,
            household=household,
            financial_owner=owner,
            name=name,
            type=Account.CHECKING,
            initial_balance=initial_balance,
            currency='BRL',
        )

    @staticmethod
    def create_category(*, user, household, name):
        return Category.objects.create(
            user=user,
            household=household,
            name=name,
            type=Category.EXPENSE,
            color='#abcdef',
        )

    @staticmethod
    def create_transaction(
        *,
        user,
        household,
        owner,
        account,
        category,
        description,
        amount=Decimal('20.00'),
    ):
        return Transaction.objects.create(
            user=user,
            household=household,
            financial_owner=owner,
            account=account,
            category=category,
            description=description,
            amount=amount,
            date=timezone.localdate(),
            type=Transaction.EXPENSE,
        )

    def assert_foreign_data_absent(self, body):
        serialized = repr(body)
        for value in (
            self.foreign_household.uuid,
            self.foreign_household.name,
            self.foreign_owner.uuid,
            self.foreign_owner.name,
            self.foreign_account.uuid,
            self.foreign_account.name,
            self.foreign_category.uuid,
            self.foreign_category.name,
            self.foreign_transaction.uuid,
            self.foreign_transaction.description,
            self.cross_household_transaction.uuid,
            self.cross_household_transaction.description,
            self.invalid_local_account.uuid,
            self.invalid_local_account.name,
            self.invalid_local_transaction.uuid,
            self.invalid_local_transaction.description,
        ):
            self.assertNotIn(str(value), serialized)

    def get_json(self, path):
        response = self.client.get(path, **self.auth)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assert_foreign_data_absent(body)
        return body

    def test_bootstrap(self):
        body = self.get_json(RESOURCE_EXPECTATIONS[0][1])

        self.assertEqual(set(body), set(RESOURCE_EXPECTATIONS[0][2]))
        self.assertEqual(body['household']['uuid'], str(self.household.uuid))
        self.assertEqual(body['accounts'][0]['uuid'], str(self.account.uuid))
        self.assertEqual(body['categories'][0]['uuid'], str(self.category.uuid))
        self.assertEqual(body['transactions'][0]['uuid'], str(self.transaction.uuid))
        self.assertEqual(len(body['accounts']), 1)
        self.assertEqual(len(body['transactions']), 1)
        self.assertEqual(body['summary']['total_balance'], '80.00')
        self.assertEqual(body['summary']['monthly_expenses'], '20.00')
        self.assertNotIn('888.00', repr(body))
        self.assertNotIn('555.00', repr(body))
        expected_change_id = SyncChange.objects.filter(
            household=self.household
        ).aggregate(max_id=Max('id'))['max_id']
        self.assertEqual(
            decode_cursor(body['cursor'], self.household.uuid),
            expected_change_id,
        )

    def test_accounts(self):
        body = self.get_json(RESOURCE_EXPECTATIONS[1][1])

        self.assertEqual([row['uuid'] for row in body], [str(self.account.uuid)])
        self.assertNotIn('id', body[0])
        self.assertEqual(body[0]['initial_balance'], '100.00')
        self.assertNotIn('888.00', repr(body))

    def test_categories(self):
        body = self.get_json(RESOURCE_EXPECTATIONS[2][1])

        self.assertEqual([row['uuid'] for row in body], [str(self.category.uuid)])
        self.assertNotIn('id', body[0])

    def test_transactions(self):
        body = self.get_json(RESOURCE_EXPECTATIONS[3][1])

        self.assertEqual([row['uuid'] for row in body], [str(self.transaction.uuid)])
        self.assertNotIn('id', body[0])
        self.assertEqual(body[0]['amount'], '20.00')
        self.assertEqual(body[0]['date'], self.transaction.date.isoformat())
        self.assertEqual(body[0]['account_uuid'], str(self.account.uuid))
        self.assertNotIn('account_id', body[0])
        self.assertNotIn('555.00', repr(body))

    def test_owners(self):
        body = self.get_json(RESOURCE_EXPECTATIONS[4][1])

        self.assertEqual(len(body), 3)
        for owner in body:
            self.assertEqual(set(owner), {'uuid', 'type', 'name'})

    def test_household_and_summary_routes_are_scoped(self):
        household = self.get_json('/api/v1/household/')
        summary = self.get_json('/api/v1/summary/')

        self.assertEqual(household['uuid'], str(self.household.uuid))
        self.assertEqual(
            set(summary),
            {'total_balance', 'monthly_income', 'monthly_expenses'},
        )
        self.assertEqual(summary['total_balance'], '80.00')
        self.assertEqual(summary['monthly_income'], '0.00')
        self.assertEqual(summary['monthly_expenses'], '20.00')
        self.assertNotIn('555.00', repr(summary))
        self.assertNotIn('888.00', repr(summary))

    def test_resources_require_device_authentication(self):
        for _, path, _ in RESOURCE_EXPECTATIONS:
            response = self.client.get(path)
            self.assertEqual(response.status_code, 401)

    def test_household_and_summary_require_device_authentication(self):
        for path in ('/api/v1/household/', '/api/v1/summary/'):
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 401)
