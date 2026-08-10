from io import StringIO

from django.core.exceptions import FieldDoesNotExist
from django.core.management import call_command
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase

SPRINT_2_TABLES = {
    'api_devicesession',
    'api_usedrefreshtoken',
    'sync_idempotentoperation',
    'sync_syncchange',
}


class SyncMetadataMigrationTest(TransactionTestCase):
    migrate_from = [
        ('accounts', '0004_protect_legacy_user'),
        ('categories', '0004_protect_legacy_user'),
        ('transactions', '0004_protect_legacy_user'),
    ]
    migrate_to = [
        ('accounts', '0005_account_sync_metadata'),
        ('categories', '0005_category_sync_metadata'),
        ('transactions', '0005_transaction_sync_metadata'),
        ('sync', '0001_initial'),
    ]

    def setUp(self):
        super().setUp()
        executor = MigrationExecutor(connection)
        executor.migrate([*self.migrate_from, ('sync', None)])
        self.old_apps = executor.loader.project_state(self.migrate_from).apps
        self.legacy_ids = self._create_legacy_fixture(self.old_apps)
        self.legacy_snapshot = self._legacy_snapshot(self.old_apps)

    def tearDown(self):
        executor = MigrationExecutor(connection)
        executor.migrate(executor.loader.graph.leaf_nodes())
        super().tearDown()

    def _create_legacy_fixture(self, apps):
        User = apps.get_model('users', 'User')
        Household = apps.get_model('households', 'Household')
        Membership = apps.get_model('households', 'HouseholdMembership')
        FinancialOwner = apps.get_model('households', 'FinancialOwner')
        Account = apps.get_model('accounts', 'Account')
        Category = apps.get_model('categories', 'Category')
        Transaction = apps.get_model('transactions', 'Transaction')

        user = User.objects.create(
            email='legacy-sync@example.test',
            password='legacy-password-hash',
        )
        household = Household.objects.create(name='Legacy Lar')
        Membership.objects.create(user=user, household=household)
        owner = FinancialOwner.objects.create(
            household=household,
            type='self',
            name='Legacy Owner',
        )
        FinancialOwner.objects.create(
            household=household,
            type='spouse',
            name='Legacy Spouse',
        )
        FinancialOwner.objects.create(
            household=household,
            type='shared',
            name='Legacy Shared',
        )
        accounts = [
            Account.objects.create(
                user=user,
                household=household,
                financial_owner=owner,
                name=f'Legacy account {number}',
                type='checking',
            )
            for number in (1, 2)
        ]
        categories = [
            Category.objects.create(
                user=user,
                household=household,
                name=f'Legacy category {number}',
                type='expense',
            )
            for number in (1, 2)
        ]
        transactions = [
            Transaction.objects.create(
                user=user,
                household=household,
                financial_owner=owner,
                account=accounts[number - 1],
                category=categories[number - 1],
                description=f'Legacy transaction {number}',
                amount='10.00',
                date='2026-08-10',
                type='expense',
            )
            for number in (1, 2)
        ]
        return {
            'accounts': [row.pk for row in accounts],
            'categories': [row.pk for row in categories],
            'transactions': [row.pk for row in transactions],
        }

    def _legacy_snapshot(self, apps):
        cases = {
            'accounts': (
                apps.get_model('accounts', 'Account'),
                (
                    'pk',
                    'user_id',
                    'household_id',
                    'financial_owner_id',
                    'name',
                    'type',
                    'initial_balance',
                    'currency',
                    'created_at',
                    'updated_at',
                ),
            ),
            'categories': (
                apps.get_model('categories', 'Category'),
                (
                    'pk',
                    'user_id',
                    'household_id',
                    'name',
                    'type',
                    'color',
                    'icon',
                    'created_at',
                    'updated_at',
                ),
            ),
            'transactions': (
                apps.get_model('transactions', 'Transaction'),
                (
                    'pk',
                    'user_id',
                    'household_id',
                    'financial_owner_id',
                    'account_id',
                    'category_id',
                    'description',
                    'amount',
                    'date',
                    'type',
                    'created_at',
                    'updated_at',
                ),
            ),
        }
        return {
            key: list(
                Model.objects.filter(pk__in=self.legacy_ids[key])
                .order_by('pk')
                .values(*fields)
            )
            for key, (Model, fields) in cases.items()
        }

    def _migrate(self, targets, state_targets=None):
        executor = MigrationExecutor(connection)
        executor.migrate(targets)
        return executor.loader.project_state(state_targets or targets).apps

    def _assert_forward_state(self, apps):
        for app_label, model_name, key in (
            ('accounts', 'Account', 'accounts'),
            ('categories', 'Category', 'categories'),
            ('transactions', 'Transaction', 'transactions'),
        ):
            Model = apps.get_model(app_label, model_name)
            rows = list(
                Model.objects.filter(pk__in=self.legacy_ids[key])
                .order_by('pk')
                .values_list('uuid', 'sync_version')
            )
            self.assertEqual(len(rows), 2)
            self.assertTrue(all(row_uuid is not None for row_uuid, _ in rows))
            self.assertEqual(len({row_uuid for row_uuid, _ in rows}), 2)
            self.assertEqual([version for _, version in rows], [1, 1])

        DeviceSession = apps.get_model('api', 'DeviceSession')
        UsedRefreshToken = apps.get_model('api', 'UsedRefreshToken')
        IdempotentOperation = apps.get_model('sync', 'IdempotentOperation')
        SyncChange = apps.get_model('sync', 'SyncChange')
        self.assertEqual(DeviceSession.objects.count(), 0)
        self.assertEqual(UsedRefreshToken.objects.count(), 0)
        self.assertEqual(IdempotentOperation.objects.count(), 0)
        self.assertEqual(SyncChange.objects.count(), 0)

    def test_legacy_forward_rollback_forward_and_audit(self):
        new_apps = self._migrate(self.migrate_to)
        self._assert_forward_state(new_apps)

        reverse_targets = [*self.migrate_from, ('sync', None), ('api', None)]
        reversed_apps = self._migrate(reverse_targets, self.migrate_from)
        reversed_snapshot = self._legacy_snapshot(reversed_apps)
        for app_label, model_name, key in (
            ('accounts', 'Account', 'accounts'),
            ('categories', 'Category', 'categories'),
            ('transactions', 'Transaction', 'transactions'),
        ):
            Model = reversed_apps.get_model(app_label, model_name)
            self.assertEqual(
                reversed_snapshot[key],
                self.legacy_snapshot[key],
            )
            with self.assertRaises(FieldDoesNotExist):
                Model._meta.get_field('uuid')
            with self.assertRaises(FieldDoesNotExist):
                Model._meta.get_field('sync_version')

        self.assertTrue(
            SPRINT_2_TABLES.isdisjoint(connection.introspection.table_names())
        )

        replayed_apps = self._migrate(self.migrate_to)
        self._assert_forward_state(replayed_apps)

        audit_output = StringIO()
        call_command('audit_household_integrity', stdout=audit_output)
        audit_lines = audit_output.getvalue().splitlines()
        self.assertEqual(
            len([line for line in audit_lines if line.endswith('=0')]),
            12,
        )
        self.assertEqual(audit_lines[-1], 'integrity_status=ok')
