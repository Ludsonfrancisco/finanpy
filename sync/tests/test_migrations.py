from django.core.exceptions import FieldDoesNotExist
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase


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

    def _migrate(self, targets):
        executor = MigrationExecutor(connection)
        executor.migrate(targets)
        return executor.loader.project_state(targets).apps

    def test_forward_backfills_unique_uuids_and_version_one_then_reverses(self):
        new_apps = self._migrate(self.migrate_to)

        for app_label, model_name, key in (
            ('accounts', 'Account', 'accounts'),
            ('categories', 'Category', 'categories'),
            ('transactions', 'Transaction', 'transactions'),
        ):
            Model = new_apps.get_model(app_label, model_name)
            rows = list(
                Model.objects.filter(pk__in=self.legacy_ids[key])
                .order_by('pk')
                .values_list('uuid', 'sync_version')
            )
            self.assertEqual(len(rows), 2)
            self.assertTrue(all(row_uuid is not None for row_uuid, _ in rows))
            self.assertEqual(len({row_uuid for row_uuid, _ in rows}), 2)
            self.assertEqual([version for _, version in rows], [1, 1])

        reversed_apps = self._migrate(self.migrate_from)
        for app_label, model_name, key in (
            ('accounts', 'Account', 'accounts'),
            ('categories', 'Category', 'categories'),
            ('transactions', 'Transaction', 'transactions'),
        ):
            Model = reversed_apps.get_model(app_label, model_name)
            self.assertEqual(
                list(
                    Model.objects.filter(pk__in=self.legacy_ids[key])
                    .order_by('pk')
                    .values_list('pk', flat=True)
                ),
                self.legacy_ids[key],
            )
            with self.assertRaises(FieldDoesNotExist):
                Model._meta.get_field('uuid')
            with self.assertRaises(FieldDoesNotExist):
                Model._meta.get_field('sync_version')
