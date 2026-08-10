import uuid
from datetime import date
from decimal import Decimal

from django.test import TestCase

from accounts.models import Account
from api.models import DeviceSession
from api.tokens import issue_session
from categories.models import Category
from households.services import ensure_household_for_user, get_financial_owner
from sync.context import capture_sync_context
from sync.models import SyncChange
from transactions.models import Transaction
from users.models import User

CAPTURE_EXPECTATIONS = (
    ('account_create', 'create', 1, ('uuid', 'version', 'household_uuid')),
    ('account_update', 'update', 2, ('uuid', 'version', 'name')),
    ('transaction_delete', 'delete', 2, ('uuid', 'deleted')),
    (
        'transaction_relations',
        'create',
        1,
        ('account_uuid', 'category_uuid', 'financial_owner_uuid'),
    ),
)


class SyncCaptureTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='capture@example.test',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type='self')

    def create_account(self, **overrides):
        values = {
            'user': self.user,
            'household': self.household,
            'financial_owner': self.owner,
            'name': 'Conta principal',
            'type': Account.CHECKING,
            'initial_balance': Decimal('125.50'),
            'currency': 'BRL',
        }
        values.update(overrides)
        return Account.objects.create(**values)

    def create_category(self, **overrides):
        values = {
            'user': self.user,
            'household': self.household,
            'name': 'Mercado',
            'type': Category.EXPENSE,
            'color': '#123456',
            'icon': 'cart',
        }
        values.update(overrides)
        return Category.objects.create(**values)

    def create_transaction(self, **overrides):
        account = overrides.pop('account', None) or self.create_account()
        category = overrides.pop('category', None) or self.create_category()
        values = {
            'user': self.user,
            'household': self.household,
            'financial_owner': self.owner,
            'account': account,
            'category': category,
            'description': 'Compras do mes',
            'amount': Decimal('19.90'),
            'date': date(2026, 8, 10),
            'type': Transaction.EXPENSE,
        }
        values.update(overrides)
        return Transaction.objects.create(**values)

    def assert_one_new_change(self, mutate):
        before = SyncChange.objects.count()
        result = mutate()
        self.assertEqual(SyncChange.objects.count(), before + 1)
        return result, SyncChange.objects.latest('id')

    def test_account_create(self):
        account, change = self.assert_one_new_change(self.create_account)

        self.assertEqual(change.operation, 'create')
        self.assertEqual(change.entity_version, 1)
        self.assertEqual(change.entity_type, 'account')
        self.assertEqual(change.entity_uuid, account.uuid)
        for key in CAPTURE_EXPECTATIONS[0][3]:
            self.assertIn(key, change.payload)
        self.assertEqual(change.payload['household_uuid'], str(self.household.uuid))
        self.assertEqual(change.payload['initial_balance'], '125.50')
        self.assertIsInstance(change.payload['created_at'], str)
        self.assertIsInstance(change.payload['updated_at'], str)

    def test_account_update(self):
        account = self.create_account()

        def update_account():
            account.name = 'Conta atualizada'
            account.save()
            return account

        _, change = self.assert_one_new_change(update_account)

        account.refresh_from_db()
        self.assertEqual(change.operation, 'update')
        self.assertEqual(change.entity_version, 2)
        self.assertEqual(account.sync_version, 2)
        for key in CAPTURE_EXPECTATIONS[1][3]:
            self.assertIn(key, change.payload)
        self.assertEqual(change.payload['name'], 'Conta atualizada')

    def test_transaction_delete(self):
        transaction = self.create_transaction()
        transaction_uuid = transaction.uuid

        _, change = self.assert_one_new_change(transaction.delete)

        self.assertEqual(change.operation, 'delete')
        self.assertEqual(change.entity_version, 2)
        for key in CAPTURE_EXPECTATIONS[2][3]:
            self.assertIn(key, change.payload)
        self.assertEqual(
            change.payload,
            {'uuid': str(transaction_uuid), 'deleted': True},
        )

    def test_transaction_relations(self):
        account = self.create_account()
        category = self.create_category()

        transaction, change = self.assert_one_new_change(
            lambda: self.create_transaction(account=account, category=category)
        )

        self.assertEqual(change.operation, 'create')
        self.assertEqual(change.entity_version, 1)
        for key in CAPTURE_EXPECTATIONS[3][3]:
            self.assertIn(key, change.payload)
        self.assertEqual(change.payload['account_uuid'], str(account.uuid))
        self.assertEqual(change.payload['category_uuid'], str(category.uuid))
        self.assertEqual(change.payload['financial_owner_uuid'], str(self.owner.uuid))
        self.assertEqual(change.payload['amount'], '19.90')
        self.assertEqual(change.payload['date'], '2026-08-10')
        self.assertNotIn('account_id', change.payload)
        self.assertNotIn('category_id', change.payload)
        self.assertEqual(change.entity_uuid, transaction.uuid)

    def test_capture_context_attributes_device_and_operation(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        operation_id = uuid.uuid4()

        with capture_sync_context(
            device_session=issued.session,
            operation_id=operation_id,
        ):
            _, change = self.assert_one_new_change(self.create_account)

        self.assertEqual(change.device_session, issued.session)
        self.assertEqual(change.operation_id, operation_id)

    def test_locked_mutation_version_is_not_incremented_twice(self):
        account = self.create_account()
        account.sync_version = 2

        _, change = self.assert_one_new_change(account.save)

        account.refresh_from_db()
        self.assertEqual(account.sync_version, 2)
        self.assertEqual(change.entity_version, 2)

    def test_update_fields_persists_the_advanced_version(self):
        account = self.create_account()
        account.name = 'Atualizada seletivamente'

        _, change = self.assert_one_new_change(
            lambda: account.save(update_fields=['name'])
        )

        account.refresh_from_db()
        self.assertEqual(account.sync_version, 2)
        self.assertEqual(change.entity_version, 2)

    def test_web_crud_is_captured_by_the_same_signals(self):
        self.client.force_login(self.user)

        def create_through_web():
            return self.client.post(
                '/accounts/new/',
                {
                    'name': 'Conta criada na web',
                    'type': Account.SAVINGS,
                    'initial_balance': '75.00',
                    'currency': 'BRL',
                },
            )

        response, change = self.assert_one_new_change(create_through_web)

        self.assertEqual(response.status_code, 302)
        self.assertEqual(change.operation, SyncChange.CREATE)
        self.assertEqual(change.payload['name'], 'Conta criada na web')

    def test_stale_instance_delete_uses_the_last_stored_version(self):
        account = self.create_account()
        stale_account = Account.objects.get(pk=account.pk)
        account.name = 'Versao mais recente'
        account.save()

        _, change = self.assert_one_new_change(stale_account.delete)

        self.assertEqual(change.operation, SyncChange.DELETE)
        self.assertEqual(change.entity_version, 3)
