import uuid
from datetime import timedelta

from django.contrib import admin
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase
from django.utils import timezone

from accounts.models import Account
from api.models import DeviceSession
from categories.models import Category
from households.services import ensure_household_for_user, get_financial_owner
from sync.admin import SyncChangeAdmin
from sync.models import (
    IdempotentOperation,
    ImmutableSyncChangeError,
    SyncChange,
)
from transactions.models import Transaction


class SyncModelTest(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.user = user_model.objects.create_user(
            email='sync-models@example.test',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type='self')
        self.device = self._create_device('first')
        self.other_device = self._create_device('second')

    def _create_device(self, suffix):
        now = timezone.now()
        return DeviceSession.objects.create(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name=f'Device {suffix}',
            access_token_digest=(suffix + '-access').ljust(64, 'a'),
            access_expires_at=now + timedelta(minutes=15),
            refresh_token_digest=(suffix + '-refresh').ljust(64, 'r'),
            refresh_expires_at=now + timedelta(days=30),
        )

    def _create_account(self, name):
        return Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name=name,
            type=Account.CHECKING,
        )

    def _create_category(self, name):
        return Category.objects.create(
            user=self.user,
            household=self.household,
            name=name,
            type=Category.EXPENSE,
        )

    def _create_transaction(self, description, account, category):
        return Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            account=account,
            category=category,
            description=description,
            amount='10.00',
            date=timezone.localdate(),
            type=Transaction.EXPENSE,
        )

    def _create_change(self, entity_uuid=None, payload=None):
        return SyncChange.objects.create(
            household=self.household,
            device_session=self.device,
            operation_id=uuid.uuid4(),
            entity_type='account',
            entity_uuid=entity_uuid or uuid.uuid4(),
            entity_version=1,
            operation=SyncChange.CREATE,
            payload=payload or {'name': 'Wallet'},
        )

    def test_account_uuid(self):
        first = self._create_account('First account')
        second = self._create_account('Second account')

        self.assertIsNotNone(first.uuid)
        self.assertIsNotNone(second.uuid)
        self.assertNotEqual(first.uuid, second.uuid)
        self.assertFalse(Account._meta.get_field('uuid').editable)
        self.assertEqual(first.sync_version, 1)

    def test_category_uuid(self):
        first = self._create_category('First category')
        second = self._create_category('Second category')

        self.assertIsNotNone(first.uuid)
        self.assertIsNotNone(second.uuid)
        self.assertNotEqual(first.uuid, second.uuid)
        self.assertFalse(Category._meta.get_field('uuid').editable)
        self.assertEqual(first.sync_version, 1)

    def test_transaction_uuid(self):
        account = self._create_account('Transactions account')
        category = self._create_category('Transactions category')
        first = self._create_transaction('First transaction', account, category)
        second = self._create_transaction('Second transaction', account, category)

        self.assertIsNotNone(first.uuid)
        self.assertIsNotNone(second.uuid)
        self.assertNotEqual(first.uuid, second.uuid)
        self.assertFalse(Transaction._meta.get_field('uuid').editable)
        self.assertEqual(first.sync_version, 1)

    def test_change_order(self):
        first = self._create_change()
        second = self._create_change()

        self.assertLess(first.id, second.id)

    def test_operation_same_device(self):
        operation_id = uuid.uuid4()
        values = {
            'device_session': self.device,
            'operation_id': operation_id,
            'request_hash': 'a' * 64,
            'status_code': 200,
            'response_body': {'status': 'applied'},
        }
        IdempotentOperation.objects.create(**values)

        with self.assertRaises(IntegrityError), transaction.atomic():
            IdempotentOperation.objects.create(**values)

    def test_operation_different_device(self):
        operation_id = uuid.uuid4()
        common = {
            'operation_id': operation_id,
            'request_hash': 'a' * 64,
            'status_code': 200,
            'response_body': {'status': 'applied'},
        }
        IdempotentOperation.objects.create(device_session=self.device, **common)

        second = IdempotentOperation.objects.create(
            device_session=self.other_device,
            **common,
        )

        self.assertIsNotNone(second.pk)

    def test_sync_change_cannot_be_updated_or_deleted_through_model_api(self):
        change = self._create_change(payload={'name': 'Original'})
        change.payload = {'name': 'Changed'}

        with self.assertRaises(ImmutableSyncChangeError):
            change.save()
        with self.assertRaises(ImmutableSyncChangeError):
            change.delete()

        change.refresh_from_db()
        self.assertEqual(change.payload, {'name': 'Original'})

    def test_sync_change_contract_and_indexes(self):
        self.assertEqual(
            SyncChange.OPERATION_CHOICES,
            [('create', 'Create'), ('update', 'Update'), ('delete', 'Delete')],
        )
        self.assertEqual(SyncChange._meta.get_field('entity_type').max_length, 32)
        self.assertEqual(SyncChange._meta.get_field('operation').max_length, 8)
        self.assertEqual(
            [tuple(index.fields) for index in SyncChange._meta.indexes],
            [('household', 'id'), ('household', 'entity_type', 'entity_uuid')],
        )

    def test_idempotent_operation_contract(self):
        self.assertEqual(
            IdempotentOperation._meta.get_field('request_hash').max_length,
            64,
        )
        constraint_fields = [
            tuple(constraint.fields)
            for constraint in IdempotentOperation._meta.constraints
        ]
        self.assertIn(('device_session', 'operation_id'), constraint_fields)

    def test_sync_change_admin_is_read_only(self):
        model_admin = SyncChangeAdmin(SyncChange, admin.site)
        request = type('Request', (), {})()

        self.assertEqual(
            model_admin.get_readonly_fields(request),
            tuple(field.name for field in SyncChange._meta.fields),
        )
        self.assertFalse(model_admin.has_add_permission(request))
        self.assertFalse(model_admin.has_delete_permission(request))
