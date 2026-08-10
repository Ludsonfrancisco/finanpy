from copy import deepcopy
from decimal import Decimal
from uuid import uuid4

from django.test import TestCase
from django.utils import timezone

from accounts.models import Account
from api.models import DeviceSession
from api.tokens import issue_session
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from sync.models import IdempotentOperation
from transactions.models import Transaction
from users.models import User

PUSH_CASES = (
    ('retry_create', 'account', 'create', None, 200, 'duplicate', 1),
    ('changed_body_same_operation', 'account', 'create', None, 200, 'idempotency_conflict', 0),
    ('current_update', 'transaction', 'update', 1, 200, 'applied', 2),
    ('stale_amount', 'transaction', 'update', 1, 200, 'conflict', 2),
    ('stale_owner', 'transaction', 'update', 1, 200, 'conflict', 2),
    ('stale_delete', 'transaction', 'delete', 1, 200, 'conflict', 2),
    ('foreign_relation', 'transaction', 'create', None, 200, 'invalid', 0),
    ('mixed_batch', 'account', 'create', None, 200, 'per_operation_results', 1),
    ('oversized_batch', 'account', 'create', None, 400, 'max_100_operations', 0),
    ('account_in_use', 'account', 'delete', 1, 200, 'resource_in_use', 1),
    ('category_in_use', 'category', 'delete', 1, 200, 'resource_in_use', 1),
)


class SyncPushApiTest(TestCase):
    endpoint = '/api/v1/sync/push/'

    def setUp(self):
        self.user = User.objects.create_user(
            email='push-api@example.test',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, FinancialOwner.SELF)
        self.other_owner = get_financial_owner(self.household, FinancialOwner.SPOUSE)
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        self.device_session = issued.session
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issued.access_token}'}
        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Conta atual',
            type=Account.CHECKING,
            initial_balance=Decimal('100.00'),
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Mercado',
            type=Category.EXPENSE,
        )
        self.transaction = Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            account=self.account,
            category=self.category,
            description='Original',
            amount=Decimal('20.00'),
            date=timezone.localdate(),
            type=Transaction.EXPENSE,
        )
        self.foreign_user = User.objects.create_user(
            email='foreign-push-api@example.test',
            password='Strong-pass-123',
        )
        self.foreign_household = ensure_household_for_user(self.foreign_user)
        self.foreign_owner = get_financial_owner(
            self.foreign_household,
            FinancialOwner.SELF,
        )
        self.foreign_account = Account.objects.create(
            user=self.foreign_user,
            household=self.foreign_household,
            financial_owner=self.foreign_owner,
            name='Conta estrangeira confidencial',
            type=Account.CASH,
        )

    def post_operations(self, operations):
        return self.client.post(
            self.endpoint,
            {'operations': operations},
            content_type='application/json',
            **self.auth,
        )

    def account_create(self, **overrides):
        operation = {
            'operation_id': str(uuid4()),
            'entity': 'account',
            'action': 'create',
            'entity_uuid': str(uuid4()),
            'expected_version': None,
            'data': {
                'name': 'Carteira',
                'type': Account.CASH,
                'initial_balance': '0.00',
                'currency': 'BRL',
                'financial_owner_uuid': str(self.owner.uuid),
            },
        }
        operation.update(overrides)
        return operation

    def transaction_operation(self, action='update', **overrides):
        operation = {
            'operation_id': str(uuid4()),
            'entity': 'transaction',
            'action': action,
            'entity_uuid': str(self.transaction.uuid),
            'expected_version': 1,
            'data': {'amount': '25.00'},
        }
        operation.update(overrides)
        return operation

    def test_push_cases(self):
        self.assertEqual(len(PUSH_CASES), 11)
        for case, entity, action, expected_version, http_status, expected, version in PUSH_CASES:
            with self.subTest(case=case):
                self._assert_case(
                    case,
                    entity,
                    action,
                    expected_version,
                    http_status,
                    expected,
                    version,
                )

    def _assert_case(
        self,
        case,
        entity,
        action,
        expected_version,
        http_status,
        expected,
        version,
    ):
        if entity == 'transaction' and case != 'foreign_relation':
            self.transaction = Transaction.objects.create(
                user=self.user,
                household=self.household,
                financial_owner=self.owner,
                account=self.account,
                category=self.category,
                description=f'Alvo {case}',
                amount=Decimal('20.00'),
                date=timezone.localdate(),
                type=Transaction.EXPENSE,
            )
        operation = self._operation_for(entity, action, expected_version)
        if case == 'retry_create':
            first = self.post_operations([operation])
            self.assertEqual(first.json()['results'][0]['status'], 'applied')
            response = self.post_operations([deepcopy(operation)])
            result = response.json()['results'][0]
        elif case == 'changed_body_same_operation':
            self.post_operations([operation])
            original_uuid = operation['entity_uuid']
            operation['data']['name'] = 'Corpo alterado'
            response = self.post_operations([operation])
            result = response.json()['results'][0]
            self.assertEqual(Account.objects.get(uuid=original_uuid).name, 'Carteira')
            self.assertEqual(Account.objects.filter(name='Corpo alterado').count(), 0)
            self.assertEqual(result['code'], expected)
        elif case in {'stale_amount', 'stale_owner', 'stale_delete'}:
            self.transaction.description = f'Concorrente {case}'
            self.transaction.save()
            operation = self.transaction_operation(
                action='delete' if case == 'stale_delete' else 'update',
                data={} if case == 'stale_delete' else self._stale_data(case),
            )
            response = self.post_operations([operation])
            result = response.json()['results'][0]
            self.transaction.refresh_from_db()
            self.assertEqual(result['code'], 'version_conflict')
            self.assertEqual(result['current']['version'], version)
            self.assertEqual(self.transaction.description, f'Concorrente {case}')
            if case == 'stale_amount':
                self.assertEqual(self.transaction.amount, Decimal('20.00'))
            if case == 'stale_owner':
                self.assertEqual(self.transaction.financial_owner, self.owner)
        elif case == 'foreign_relation':
            operation = self._foreign_transaction_create()
            response = self.post_operations([operation])
            result = response.json()['results'][0]
            self.assertEqual(result['code'], 'validation_error')
            self.assertNotIn(self.foreign_account.name, repr(result))
        elif case == 'mixed_batch':
            invalid = self.account_create()
            invalid['data']['name'] = ''
            response = self.post_operations([operation, invalid])
            results = response.json()['results']
            self.assertEqual([row['status'] for row in results], ['applied', 'invalid'])
            result = {'status': expected, 'entity': results[0]['entity']}
        elif case == 'oversized_batch':
            operations = [self.account_create() for _ in range(101)]
            response = self.post_operations(operations)
            result = response.json()['error']
            self.assertEqual(result['code'], expected)
        elif case in {'account_in_use', 'category_in_use'}:
            target = self.account if case == 'account_in_use' else self.category
            operation['entity_uuid'] = str(target.uuid)
            response = self.post_operations([operation])
            result = response.json()['results'][0]
            self.assertEqual(result['code'], expected)
            self.assertTrue(type(target).objects.filter(pk=target.pk).exists())
        else:
            response = self.post_operations([operation])
            result = response.json()['results'][0]

        self.assertEqual(response.status_code, http_status)
        if expected == 'per_operation_results':
            self.assertEqual(result['status'], expected)
        elif expected in {'idempotency_conflict', 'resource_in_use', 'max_100_operations'}:
            self.assertEqual(result['code'], expected)
        else:
            self.assertEqual(result['status'], expected)
        if version:
            self.assertEqual(result['entity']['version'] if 'entity' in result else result['current']['version'], version)

    def _operation_for(self, entity, action, expected_version):
        if entity == 'account' and action == 'create':
            return self.account_create(expected_version=expected_version)
        if entity == 'account':
            return {
                'operation_id': str(uuid4()),
                'entity': entity,
                'action': action,
                'entity_uuid': str(self.account.uuid),
                'expected_version': expected_version,
                'data': {},
            }
        if entity == 'category':
            return {
                'operation_id': str(uuid4()),
                'entity': entity,
                'action': action,
                'entity_uuid': str(self.category.uuid),
                'expected_version': expected_version,
                'data': {},
            }
        return self.transaction_operation(action=action, expected_version=expected_version)

    def _stale_data(self, case):
        if case == 'stale_owner':
            return {'financial_owner_uuid': str(self.other_owner.uuid)}
        return {'amount': '999.00'}

    def _foreign_transaction_create(self):
        return {
            'operation_id': str(uuid4()),
            'entity': 'transaction',
            'action': 'create',
            'entity_uuid': str(uuid4()),
            'expected_version': None,
            'data': {
                'financial_owner_uuid': str(self.owner.uuid),
                'account_uuid': str(self.foreign_account.uuid),
                'category_uuid': str(self.category.uuid),
                'description': 'Não persistir',
                'amount': '500.00',
                'date': timezone.localdate().isoformat(),
                'type': Transaction.EXPENSE,
            },
        }

    def test_each_operation_is_atomic_and_batch_order_is_preserved(self):
        valid_first = self.account_create()
        invalid = self.account_create()
        invalid['data']['name'] = ''
        valid_last = self.account_create()
        valid_last['data']['name'] = 'Reserva'

        response = self.post_operations([valid_first, invalid, valid_last])

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [result['status'] for result in response.json()['results']],
            ['applied', 'invalid', 'applied'],
        )
        self.assertTrue(Account.objects.filter(uuid=valid_first['entity_uuid']).exists())
        self.assertFalse(Account.objects.filter(uuid=invalid['entity_uuid']).exists())
        self.assertTrue(Account.objects.filter(uuid=valid_last['entity_uuid']).exists())
        self.assertEqual(IdempotentOperation.objects.count(), 3)

    def test_push_requires_device_authentication(self):
        response = self.client.post(
            self.endpoint,
            {'operations': [self.account_create()]},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 401)

    def test_push_rejects_invalid_json_and_empty_batch(self):
        invalid_json = self.client.post(
            self.endpoint,
            data='{',
            content_type='application/json',
            **self.auth,
        )
        empty = self.post_operations([])

        self.assertEqual(invalid_json.status_code, 400)
        self.assertEqual(empty.status_code, 400)
        self.assertEqual(empty.json()['error']['code'], 'min_1_operation')

    def test_schema_type_errors_are_per_operation_results(self):
        invalid_entity = self.account_create(entity=[])
        invalid_entity_object = self.account_create(entity={})
        invalid_action = self.account_create(action=[])
        invalid_action_object = self.account_create(action={})

        response = self.post_operations(
            [
                invalid_entity,
                invalid_entity_object,
                invalid_action,
                invalid_action_object,
            ]
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [result['status'] for result in response.json()['results']],
            ['invalid', 'invalid', 'invalid', 'invalid'],
        )
        self.assertEqual(IdempotentOperation.objects.count(), 4)
