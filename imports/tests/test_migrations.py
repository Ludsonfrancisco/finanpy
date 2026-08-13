import uuid
from datetime import date
from decimal import Decimal

from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase


class ImportsSchemaMigrationTest(TransactionTestCase):
    base_migrations = [
        ('accounts', '0005_account_sync_metadata'),
        ('api', '0001_initial'),
        ('categories', '0005_category_sync_metadata'),
        ('households', '0003_reconcile_membership_uniqueness'),
        ('transactions', '0005_transaction_sync_metadata'),
    ]
    migrate_from = [*base_migrations, ('imports', '0002_enforce_household_boundaries')]
    migrate_to = [*base_migrations, ('imports', '0003_import_batch_preview_metadata')]

    def setUp(self):
        super().setUp()
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_from)
        apps = executor.loader.project_state(self.migrate_from).apps

        User = apps.get_model('users', 'User')
        Household = apps.get_model('households', 'Household')
        Owner = apps.get_model('households', 'FinancialOwner')
        Account = apps.get_model('accounts', 'Account')
        Category = apps.get_model('categories', 'Category')
        Transaction = apps.get_model('transactions', 'Transaction')

        user = User.objects.create(email='migration-imports@example.com')
        household = Household.objects.create(name='Lar de migration')
        owner = Owner.objects.create(household=household, type='shared', name='Conjunto')
        account = Account.objects.create(
            user=user,
            household=household,
            financial_owner=owner,
            name='Conta preservada',
            initial_balance=Decimal('10.00'),
        )
        category = Category.objects.create(
            uuid=uuid.uuid4(),
            user=user,
            household=household,
            name='Categoria preservada',
            type='expense',
            color='#123456',
        )
        self.transaction_id = Transaction.objects.create(
            uuid=uuid.uuid4(),
            user=user,
            household=household,
            financial_owner=owner,
            account=account,
            category=category,
            description='Lançamento preservado',
            amount=Decimal('5.00'),
            date=date(2026, 8, 13),
            type='expense',
        ).pk
        self.account_id = account.pk

    def tearDown(self):
        executor = MigrationExecutor(connection)
        executor.migrate(executor.loader.graph.leaf_nodes())
        super().tearDown()

    def test_import_schema_installs_and_rolls_back_without_touching_ledger(self):
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_to)

        with connection.cursor() as cursor:
            tables = set(connection.introspection.table_names(cursor))
            batch_columns = {
                column.name
                for column in connection.introspection.get_table_description(
                    cursor, 'imports_importbatch'
                )
            }
            constraints = connection.introspection.get_constraints(
                cursor, 'imports_sourcereference'
            )
            cursor.execute(
                "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'imports_%'"
            )
            triggers = {row[0] for row in cursor.fetchall()}

        self.assertTrue(
            {
                'imports_importaccountlink',
                'imports_importbatch',
                'imports_importrecord',
                'imports_sourcereference',
            }.issubset(tables)
        )
        self.assertTrue(
            {'uuid', 'external_account_id', 'is_repeated_file'}.issubset(batch_columns)
        )
        self.assertIn('unique_source_reference_external_id', constraints)
        self.assertIn('imports_source_reference_household_insert', triggers)

        executor = MigrationExecutor(connection)
        rollback_target = [*self.base_migrations, ('imports', None)]
        executor.migrate(rollback_target)

        with connection.cursor() as cursor:
            tables = set(connection.introspection.table_names(cursor))
        self.assertFalse(any(table.startswith('imports_') for table in tables))
        self.assertIn('accounts_account', tables)
        self.assertIn('transactions_transaction', tables)

        apps = executor.loader.project_state(self.base_migrations).apps
        Account = apps.get_model('accounts', 'Account')
        Transaction = apps.get_model('transactions', 'Transaction')
        self.assertTrue(Account.objects.filter(pk=self.account_id).exists())
        self.assertTrue(Transaction.objects.filter(pk=self.transaction_id).exists())
