import uuid
from datetime import date, timedelta
from decimal import Decimal

from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase
from django.utils import timezone


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


class ImportRecordUuidMigrationTest(TransactionTestCase):
    base_migrations = ImportsSchemaMigrationTest.base_migrations
    migrate_from = [*base_migrations, ('imports', '0003_import_batch_preview_metadata')]
    migrate_to = [*base_migrations, ('imports', '0004_import_record_uuid')]

    def setUp(self):
        super().setUp()
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_from)
        apps = executor.loader.project_state(self.migrate_from).apps

        User = apps.get_model('users', 'User')
        Household = apps.get_model('households', 'Household')
        Owner = apps.get_model('households', 'FinancialOwner')
        Account = apps.get_model('accounts', 'Account')
        DeviceSession = apps.get_model('api', 'DeviceSession')
        ImportBatch = apps.get_model('imports', 'ImportBatch')
        ImportRecord = apps.get_model('imports', 'ImportRecord')

        user = User.objects.create(email='migration-records@example.com')
        household = Household.objects.create(name='Lar de migration de registros')
        owner = Owner.objects.create(household=household, type='self', name='Eu')
        account = Account.objects.create(
            user=user,
            household=household,
            financial_owner=owner,
            name='Conta de migration',
            initial_balance=Decimal('0.00'),
        )
        now = timezone.now()
        device = DeviceSession.objects.create(
            user=user,
            household=household,
            default_owner=owner,
            platform='windows',
            name='Dispositivo de migration',
            access_token_digest='e' * 64,
            access_expires_at=now + timedelta(hours=2),
            refresh_token_digest='f' * 64,
            refresh_expires_at=now + timedelta(days=1),
        )
        batch = ImportBatch.objects.create(
            uuid=uuid.uuid4(),
            household=household,
            device_session=device,
            account=account,
            financial_owner=owner,
            provider='nubank',
            product_type='bank_account',
            external_account_id='synthetic-migration-account',
            file_sha256='0' * 64,
            statement_start=date(2026, 8, 1),
            statement_end=date(2026, 8, 12),
            expires_at=now + timedelta(hours=23),
        )
        self.record_ids = [
            ImportRecord.objects.create(
                batch=batch,
                line_number=line_number,
                external_id=None,
                posted_on=date(2026, 8, 10),
                amount=Decimal('-10.00'),
                description=f'Registro preservado {line_number}',
                transaction_type='expense',
                fingerprint=f'{line_number}' * 8,
                outcome='pending',
            ).pk
            for line_number in (1, 2)
        ]

    def tearDown(self):
        executor = MigrationExecutor(connection)
        executor.migrate(executor.loader.graph.leaf_nodes())
        super().tearDown()

    def _record_uuids(self, apps):
        ImportRecord = apps.get_model('imports', 'ImportRecord')
        return [
            ImportRecord.objects.get(pk=record_id).uuid
            for record_id in self.record_ids
        ]

    def _uuid_column(self):
        with connection.cursor() as cursor:
            columns = {
                column.name: column
                for column in connection.introspection.get_table_description(
                    cursor, 'imports_importrecord'
                )
            }
            constraints = connection.introspection.get_constraints(
                cursor, 'imports_importrecord'
            )
        unique = any(
            constraint['columns'] == ['uuid'] and constraint['unique']
            for constraint in constraints.values()
        )
        return columns['uuid'], unique

    def test_existing_records_receive_distinct_unique_uuids(self):
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_to)

        uuids = self._record_uuids(executor.loader.project_state(self.migrate_to).apps)
        column, unique = self._uuid_column()

        self.assertEqual(len(set(uuids)), len(self.record_ids))
        self.assertNotIn(None, uuids)
        self.assertFalse(column.null_ok)
        self.assertTrue(unique)

    def test_rollback_drops_the_column_and_reapplication_backfills_again(self):
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_to)
        first_uuids = self._record_uuids(
            executor.loader.project_state(self.migrate_to).apps
        )

        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_from)

        with connection.cursor() as cursor:
            columns = {
                column.name
                for column in connection.introspection.get_table_description(
                    cursor, 'imports_importrecord'
                )
            }
        self.assertNotIn('uuid', columns)

        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_to)
        second_uuids = self._record_uuids(
            executor.loader.project_state(self.migrate_to).apps
        )
        _, unique = self._uuid_column()

        self.assertEqual(len(set(second_uuids)), len(self.record_ids))
        self.assertTrue(unique)
        self.assertFalse(set(first_uuids) & set(second_uuids))
