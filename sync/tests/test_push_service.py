from copy import deepcopy
from decimal import Decimal
from unittest.mock import patch
from uuid import uuid4

from django.test import TestCase
from django.utils import timezone

from accounts.models import Account
from api.models import DeviceSession
from api.tokens import issue_session
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from sync.exceptions import IdempotencyConflict
from sync.hashes import request_hash
from sync.models import IdempotentOperation, SyncChange
from sync.services import apply_operation
from transactions.models import Transaction
from users.models import User


class PushServiceTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='push-service@example.test',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(
            self.household,
            owner_type=FinancialOwner.SELF,
        )
        self.other_owner = get_financial_owner(
            self.household,
            owner_type=FinancialOwner.SPOUSE,
        )
        self.device_session = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        ).session
        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Conta local',
            type=Account.CHECKING,
            initial_balance=Decimal('100.00'),
            currency='BRL',
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Mercado',
            type=Category.EXPENSE,
            color='#abcdef',
        )
        self.transaction = Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            account=self.account,
            category=self.category,
            description='Compra local',
            amount=Decimal('20.00'),
            date=timezone.localdate(),
            type=Transaction.EXPENSE,
        )

        self.foreign_user = User.objects.create_user(
            email='foreign-push@example.test',
            password='Strong-pass-123',
        )
        self.foreign_household = ensure_household_for_user(self.foreign_user)
        self.foreign_owner = get_financial_owner(
            self.foreign_household,
            owner_type=FinancialOwner.SELF,
        )
        self.foreign_account = Account.objects.create(
            user=self.foreign_user,
            household=self.foreign_household,
            financial_owner=self.foreign_owner,
            name='Conta estrangeira confidencial',
            type=Account.CASH,
        )
        self.foreign_category = Category.objects.create(
            user=self.foreign_user,
            household=self.foreign_household,
            name='Categoria estrangeira confidencial',
            type=Category.EXPENSE,
        )

    def account_create_operation(self, **overrides):
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

    def test_request_hash_is_canonical_and_unicode_safe(self):
        first = {'entity': 'account', 'data': {'name': 'Poupança', 'type': 'cash'}}
        second = {'data': {'type': 'cash', 'name': 'Poupança'}, 'entity': 'account'}

        self.assertEqual(request_hash(first), request_hash(second))
        self.assertEqual(len(request_hash(first)), 64)

    def test_retry_create_is_single_effect_and_returns_stored_duplicate(self):
        operation = self.account_create_operation()

        first = apply_operation(self.device_session, operation)
        second = apply_operation(self.device_session, deepcopy(operation))

        self.assertEqual(first['status'], 'applied')
        self.assertEqual(second['status'], 'duplicate')
        self.assertEqual(first['entity'], second['entity'])
        self.assertEqual(first['entity']['version'], 1)
        self.assertEqual(
            Account.objects.filter(uuid=operation['entity_uuid']).count(),
            1,
        )
        stored = IdempotentOperation.objects.get(
            device_session=self.device_session,
            operation_id=operation['operation_id'],
        )
        self.assertEqual(stored.response_body, second)
        change = SyncChange.objects.get(
            device_session=self.device_session,
            operation_id=operation['operation_id'],
        )
        self.assertEqual(change.entity_version, 1)

    def test_changed_body_with_same_operation_id_raises_without_effect(self):
        operation = self.account_create_operation()
        apply_operation(self.device_session, operation)
        changed = deepcopy(operation)
        changed['data']['name'] = 'Outro nome'

        with self.assertRaises(IdempotencyConflict):
            apply_operation(self.device_session, changed)

        account = Account.objects.get(uuid=operation['entity_uuid'])
        self.assertEqual(account.name, 'Carteira')
        self.assertEqual(
            SyncChange.objects.filter(
                device_session=self.device_session,
                operation_id=operation['operation_id'],
            ).count(),
            1,
        )

    def test_current_update_advances_version_and_attributes_capture(self):
        operation = self.transaction_operation()

        result = apply_operation(self.device_session, operation)

        self.transaction.refresh_from_db()
        self.assertEqual(result['status'], 'applied')
        self.assertEqual(result['entity']['version'], 2)
        self.assertEqual(self.transaction.sync_version, 2)
        self.assertEqual(self.transaction.amount, Decimal('25.00'))
        change = SyncChange.objects.get(
            device_session=self.device_session,
            operation_id=operation['operation_id'],
        )
        self.assertEqual(change.entity_version, 2)

    def test_stale_amount_update_returns_submitted_and_current_without_overwrite(self):
        self.transaction.amount = Decimal('30.00')
        self.transaction.save()
        operation = self.transaction_operation(data={'amount': '999.00'})

        result = apply_operation(self.device_session, operation)

        self.transaction.refresh_from_db()
        self.assertEqual(result['status'], 'conflict')
        self.assertEqual(result['code'], 'version_conflict')
        self.assertEqual(result['submitted']['data']['amount'], '999.00')
        self.assertEqual(result['current']['amount'], '30.00')
        self.assertEqual(result['current']['version'], 2)
        self.assertEqual(self.transaction.amount, Decimal('30.00'))
        stored = IdempotentOperation.objects.get(operation_id=operation['operation_id'])
        self.assertEqual(stored.response_body, result)

    def test_stale_owner_update_does_not_overwrite_current_owner(self):
        self.transaction.description = 'Atualização concorrente'
        self.transaction.save()
        operation = self.transaction_operation(
            data={'financial_owner_uuid': str(self.other_owner.uuid)}
        )

        result = apply_operation(self.device_session, operation)

        self.transaction.refresh_from_db()
        self.assertEqual(result['status'], 'conflict')
        self.assertEqual(result['current']['financial_owner_uuid'], str(self.owner.uuid))
        self.assertEqual(
            result['submitted']['data']['financial_owner_uuid'],
            str(self.other_owner.uuid),
        )
        self.assertEqual(self.transaction.financial_owner, self.owner)

    def test_stale_account_and_category_updates_do_not_overwrite_relations(self):
        other_account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Conta alternativa',
            type=Account.CASH,
        )
        other_category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Categoria alternativa',
            type=Category.EXPENSE,
        )
        cases = (
            ('account_uuid', other_account.uuid, 'account_id', self.account.pk),
            ('category_uuid', other_category.uuid, 'category_id', self.category.pk),
        )
        for submitted_name, submitted_uuid, stored_name, stored_id in cases:
            with self.subTest(relation=submitted_name):
                target = Transaction.objects.create(
                    user=self.user,
                    household=self.household,
                    financial_owner=self.owner,
                    account=self.account,
                    category=self.category,
                    description=f'Alvo {submitted_name}',
                    amount=Decimal('10.00'),
                    date=timezone.localdate(),
                    type=Transaction.EXPENSE,
                )
                target.description = 'Atualização concorrente'
                target.save()
                operation = self.transaction_operation(
                    entity_uuid=str(target.uuid),
                    data={submitted_name: str(submitted_uuid)},
                )

                result = apply_operation(self.device_session, operation)

                target.refresh_from_db()
                self.assertEqual(result['status'], 'conflict')
                self.assertEqual(result['submitted']['data'][submitted_name], str(submitted_uuid))
                self.assertEqual(getattr(target, stored_name), stored_id)

    def test_stale_delete_does_not_delete_current_row(self):
        self.transaction.description = 'Atualização concorrente'
        self.transaction.save()
        operation = self.transaction_operation(action='delete', data={})

        result = apply_operation(self.device_session, operation)

        self.assertEqual(result['status'], 'conflict')
        self.assertEqual(result['current']['version'], 2)
        self.assertTrue(Transaction.objects.filter(pk=self.transaction.pk).exists())

    def test_current_delete_returns_tombstone_and_attributes_capture(self):
        operation = self.transaction_operation(action='delete', data={})

        first = apply_operation(self.device_session, operation)
        second = apply_operation(self.device_session, deepcopy(operation))

        self.assertEqual(first['status'], 'applied')
        self.assertEqual(first['entity']['version'], 2)
        self.assertTrue(first['entity']['deleted'])
        self.assertEqual(second['status'], 'duplicate')
        self.assertFalse(Transaction.objects.filter(pk=self.transaction.pk).exists())
        change = SyncChange.objects.get(
            device_session=self.device_session,
            operation_id=operation['operation_id'],
        )
        self.assertEqual(change.operation, SyncChange.DELETE)
        self.assertEqual(change.entity_version, 2)

    def test_foreign_relation_is_invalid_and_result_is_retryable_without_leak(self):
        operation = {
            'operation_id': str(uuid4()),
            'entity': 'transaction',
            'action': 'create',
            'entity_uuid': str(uuid4()),
            'expected_version': None,
            'data': {
                'financial_owner_uuid': str(self.owner.uuid),
                'account_uuid': str(self.foreign_account.uuid),
                'category_uuid': str(self.category.uuid),
                'description': 'Não deve persistir',
                'amount': '777.00',
                'date': timezone.localdate().isoformat(),
                'type': Transaction.EXPENSE,
            },
        }

        first = apply_operation(self.device_session, operation)
        second = apply_operation(self.device_session, deepcopy(operation))

        self.assertEqual(first, second)
        self.assertEqual(first['status'], 'invalid')
        self.assertEqual(first['code'], 'validation_error')
        self.assertEqual(set(first['fields']), {'account_uuid'})
        self.assertNotIn(self.foreign_account.name, repr(first))
        self.assertFalse(Transaction.objects.filter(uuid=operation['entity_uuid']).exists())
        self.assertTrue(
            IdempotentOperation.objects.filter(
                device_session=self.device_session,
                operation_id=operation['operation_id'],
            ).exists()
        )

    def test_existing_entity_with_foreign_relations_is_outside_push_boundary(self):
        invalid_local = Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.foreign_owner,
            account=self.foreign_account,
            category=self.foreign_category,
            description='Registro local inconsistente',
            amount=Decimal('50.00'),
            date=timezone.localdate(),
            type=Transaction.EXPENSE,
        )
        Transaction.objects.filter(pk=invalid_local.pk).update(sync_version=2)
        operation = self.transaction_operation(
            entity_uuid=str(invalid_local.uuid),
            data={'amount': '999.00'},
        )

        result = apply_operation(self.device_session, operation)

        invalid_local.refresh_from_db()
        self.assertEqual(result['status'], 'invalid')
        self.assertEqual(result['code'], 'validation_error')
        self.assertEqual(set(result['fields']), {'entity_uuid'})
        self.assertNotIn(str(self.foreign_owner.uuid), repr(result))
        self.assertNotIn(str(self.foreign_account.uuid), repr(result))
        self.assertNotIn(str(self.foreign_category.uuid), repr(result))
        self.assertEqual(invalid_local.amount, Decimal('50.00'))

    def test_local_and_foreign_uuid_collisions_have_the_same_opaque_outcome(self):
        local_operation = self.account_create_operation(
            entity_uuid=str(self.account.uuid),
        )
        foreign_operation = self.account_create_operation(
            entity_uuid=str(self.foreign_account.uuid),
        )
        expected = {
            'status': 'invalid',
            'code': 'validation_error',
            'fields': {'entity_uuid': ['Invalid value.']},
        }
        account_count = Account.objects.count()
        change_count = SyncChange.objects.count()

        local_result = apply_operation(self.device_session, local_operation)
        foreign_result = apply_operation(self.device_session, foreign_operation)

        self.assertEqual(local_result, expected)
        self.assertEqual(foreign_result, expected)
        self.assertEqual(local_result, foreign_result)
        self.assertEqual(Account.objects.count(), account_count)
        self.assertEqual(SyncChange.objects.count(), change_count)
        for operation, result in (
            (local_operation, local_result),
            (foreign_operation, foreign_result),
        ):
            stored = IdempotentOperation.objects.get(
                device_session=self.device_session,
                operation_id=operation['operation_id'],
            )
            self.assertEqual(stored.response_body, result)

    def test_create_integrity_fallback_matches_opaque_uuid_collision_outcome(self):
        operation = self.account_create_operation(
            entity_uuid=str(self.foreign_account.uuid),
        )
        expected = {
            'status': 'invalid',
            'code': 'validation_error',
            'fields': {'entity_uuid': ['Invalid value.']},
        }
        account_count = Account.objects.count()
        change_count = SyncChange.objects.count()

        with patch.object(Account, 'full_clean', return_value=None):
            result = apply_operation(self.device_session, operation)

        self.assertEqual(result, expected)
        self.assertEqual(Account.objects.count(), account_count)
        self.assertEqual(SyncChange.objects.count(), change_count)
        stored = IdempotentOperation.objects.get(
            device_session=self.device_session,
            operation_id=operation['operation_id'],
        )
        self.assertEqual(stored.response_body, result)

    def test_uuid_collision_preserves_other_validation_errors(self):
        local_operation = self.account_create_operation(
            entity_uuid=str(self.account.uuid),
        )
        foreign_operation = self.account_create_operation(
            entity_uuid=str(self.foreign_account.uuid),
        )
        local_operation['data']['name'] = ''
        foreign_operation['data']['name'] = ''
        expected = {
            'status': 'invalid',
            'code': 'validation_error',
            'fields': {
                'entity_uuid': ['Invalid value.'],
                'name': ['Invalid value.'],
            },
        }
        account_count = Account.objects.count()
        change_count = SyncChange.objects.count()

        local_result = apply_operation(self.device_session, local_operation)
        foreign_result = apply_operation(self.device_session, foreign_operation)

        self.assertEqual(local_result, expected)
        self.assertEqual(foreign_result, expected)
        self.assertEqual(local_result, foreign_result)
        self.assertEqual(Account.objects.count(), account_count)
        self.assertEqual(SyncChange.objects.count(), change_count)
        for operation in (local_operation, foreign_operation):
            stored = IdempotentOperation.objects.get(
                device_session=self.device_session,
                operation_id=operation['operation_id'],
            )
            self.assertEqual(stored.response_body, expected)

    def test_validation_failure_is_stored_without_partial_mutation(self):
        operation = self.account_create_operation()
        operation['data']['name'] = ''

        first = apply_operation(self.device_session, operation)
        second = apply_operation(self.device_session, deepcopy(operation))

        self.assertEqual(first, second)
        self.assertEqual(first['status'], 'invalid')
        self.assertEqual(first['code'], 'validation_error')
        self.assertIn('name', first['fields'])
        self.assertFalse(Account.objects.filter(uuid=operation['entity_uuid']).exists())

    def test_operation_ids_are_scoped_per_device_session(self):
        second_session = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.ANDROID,
            name='Celular',
        ).session
        first_operation = self.account_create_operation()
        second_operation = deepcopy(first_operation)
        second_operation['entity_uuid'] = str(uuid4())
        second_operation['data']['name'] = 'Carteira do celular'

        first = apply_operation(self.device_session, first_operation)
        second = apply_operation(second_session, second_operation)

        self.assertEqual(first['status'], 'applied')
        self.assertEqual(second['status'], 'applied')
        self.assertEqual(
            IdempotentOperation.objects.filter(
                operation_id=first_operation['operation_id']
            ).count(),
            2,
        )

    def test_account_and_category_in_use_are_not_deleted(self):
        for entity, instance in (('account', self.account), ('category', self.category)):
            with self.subTest(entity=entity):
                operation = {
                    'operation_id': str(uuid4()),
                    'entity': entity,
                    'action': 'delete',
                    'entity_uuid': str(instance.uuid),
                    'expected_version': 1,
                    'data': {},
                }

                result = apply_operation(self.device_session, operation)

                self.assertEqual(result['status'], 'conflict')
                self.assertEqual(result['code'], 'resource_in_use')
                self.assertEqual(result['current']['version'], 1)
                self.assertTrue(type(instance).objects.filter(pk=instance.pk).exists())
