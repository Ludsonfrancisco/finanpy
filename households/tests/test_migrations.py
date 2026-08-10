from datetime import date
from decimal import Decimal

from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase


class BackfillExistingFinancialDataMigrationTest(TransactionTestCase):
    migrate_from = [
        ('households', '0001_initial'),
        ('accounts', '0002_account_household_financial_owner'),
        ('categories', '0002_category_household'),
        ('transactions', '0002_transaction_household_financial_owner'),
    ]
    migrate_to = [('households', '0002_backfill_existing_financial_data')]

    def setUp(self):
        super().setUp()
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_from)
        old_apps = executor.loader.project_state(self.migrate_from).apps
        self.old_apps = old_apps

        User = old_apps.get_model('users', 'User')
        Account = old_apps.get_model('accounts', 'Account')
        Category = old_apps.get_model('categories', 'Category')
        Transaction = old_apps.get_model('transactions', 'Transaction')

        self.user_id = User.objects.create(
            email='legacy@example.com',
            password='legacy-password-hash',
            first_name='Pessoa',
            last_name='Legada',
        ).pk
        self.account_id = Account.objects.create(
            user_id=self.user_id,
            name='Conta Legada',
            type='checking',
            initial_balance=Decimal('875.25'),
            currency='BRL',
            household=None,
            financial_owner=None,
        ).pk
        self.category_id = Category.objects.create(
            user_id=self.user_id,
            name='Mercado',
            type='expense',
            color='#123456',
            icon='cart',
            household=None,
        ).pk
        self.transaction_id = Transaction.objects.create(
            user_id=self.user_id,
            account_id=self.account_id,
            category_id=self.category_id,
            description='Compra preservada',
            amount=Decimal('125.50'),
            date=date(2026, 8, 9),
            type='expense',
            household=None,
            financial_owner=None,
        ).pk

    def tearDown(self):
        executor = MigrationExecutor(connection)
        executor.migrate(executor.loader.graph.leaf_nodes())
        super().tearDown()

    def test_backfills_legacy_ledger_and_reverses_without_data_loss(self):
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_to)
        migrated_apps = executor.loader.project_state(self.migrate_to).apps

        Household = migrated_apps.get_model('households', 'Household')
        Membership = migrated_apps.get_model('households', 'HouseholdMembership')
        Owner = migrated_apps.get_model('households', 'FinancialOwner')
        Account = migrated_apps.get_model('accounts', 'Account')
        Category = migrated_apps.get_model('categories', 'Category')
        Transaction = migrated_apps.get_model('transactions', 'Transaction')

        self.assertEqual(Household.objects.count(), 1)
        self.assertEqual(Membership.objects.count(), 1)
        self.assertEqual(Owner.objects.count(), 3)
        self.assertEqual(
            set(Owner.objects.values_list('type', 'name')),
            {('self', 'Eu'), ('spouse', 'Esposa'), ('shared', 'Conjunto')},
        )
        self.assertEqual(Account.objects.filter(household__isnull=True).count(), 0)
        self.assertEqual(Category.objects.filter(household__isnull=True).count(), 0)
        self.assertEqual(Transaction.objects.filter(household__isnull=True).count(), 0)

        account = Account.objects.get(pk=self.account_id)
        category = Category.objects.get(pk=self.category_id)
        transaction = Transaction.objects.get(pk=self.transaction_id)
        self.assertEqual(account.financial_owner.type, 'shared')
        self.assertEqual(transaction.financial_owner.type, 'shared')
        self.assertEqual(account.household_id, category.household_id)
        self.assertEqual(account.household_id, transaction.household_id)
        self.assertEqual(account.initial_balance, Decimal('875.25'))
        self.assertEqual(transaction.amount, Decimal('125.50'))
        self.assertEqual(transaction.account_id, self.account_id)
        self.assertEqual(transaction.category_id, self.category_id)

        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_from)
        rolled_back_apps = executor.loader.project_state(self.migrate_from).apps

        Household = rolled_back_apps.get_model('households', 'Household')
        Membership = rolled_back_apps.get_model('households', 'HouseholdMembership')
        Owner = rolled_back_apps.get_model('households', 'FinancialOwner')
        User = rolled_back_apps.get_model('users', 'User')
        Account = rolled_back_apps.get_model('accounts', 'Account')
        Category = rolled_back_apps.get_model('categories', 'Category')
        Transaction = rolled_back_apps.get_model('transactions', 'Transaction')

        self.assertEqual(Household.objects.count(), 0)
        self.assertEqual(Membership.objects.count(), 0)
        self.assertEqual(Owner.objects.count(), 0)
        self.assertTrue(User.objects.filter(pk=self.user_id).exists())
        self.assertEqual(Account.objects.count(), 1)
        self.assertEqual(Category.objects.count(), 1)
        self.assertEqual(Transaction.objects.count(), 1)

        account = Account.objects.get(pk=self.account_id)
        category = Category.objects.get(pk=self.category_id)
        transaction = Transaction.objects.get(pk=self.transaction_id)
        self.assertIsNone(account.household_id)
        self.assertIsNone(account.financial_owner_id)
        self.assertIsNone(category.household_id)
        self.assertIsNone(transaction.household_id)
        self.assertIsNone(transaction.financial_owner_id)
        self.assertEqual(account.name, 'Conta Legada')
        self.assertEqual(account.initial_balance, Decimal('875.25'))
        self.assertEqual(category.name, 'Mercado')
        self.assertEqual(category.color, '#123456')
        self.assertEqual(category.icon, 'cart')
        self.assertEqual(transaction.description, 'Compra preservada')
        self.assertEqual(transaction.amount, Decimal('125.50'))
        self.assertEqual(transaction.date, date(2026, 8, 9))
        self.assertEqual(transaction.account_id, self.account_id)
        self.assertEqual(transaction.category_id, self.category_id)
        self.assertEqual(transaction.user_id, self.user_id)

    def test_preserves_household_structures_that_predate_the_backfill(self):
        User = self.old_apps.get_model('users', 'User')
        Household = self.old_apps.get_model('households', 'Household')
        Membership = self.old_apps.get_model('households', 'HouseholdMembership')
        Owner = self.old_apps.get_model('households', 'FinancialOwner')

        existing_user = User.objects.create(
            email='existing-household@example.com',
            password='existing-password-hash',
        )
        existing_household = Household.objects.create(name='Lar preexistente')
        existing_membership = Membership.objects.create(
            household=existing_household,
            user=existing_user,
            role='admin',
        )
        existing_owner = Owner.objects.create(
            household=existing_household,
            type='shared',
            name='Responsável preexistente',
        )

        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_to)
        migrated_apps = executor.loader.project_state(self.migrate_to).apps

        Household = migrated_apps.get_model('households', 'Household')
        Membership = migrated_apps.get_model('households', 'HouseholdMembership')
        Owner = migrated_apps.get_model('households', 'FinancialOwner')
        self.assertEqual(Household.objects.count(), 2)
        self.assertEqual(Membership.objects.count(), 2)
        self.assertEqual(Owner.objects.count(), 4)

        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_from)
        rolled_back_apps = executor.loader.project_state(self.migrate_from).apps

        Household = rolled_back_apps.get_model('households', 'Household')
        Membership = rolled_back_apps.get_model('households', 'HouseholdMembership')
        Owner = rolled_back_apps.get_model('households', 'FinancialOwner')
        self.assertEqual(Household.objects.count(), 1)
        self.assertTrue(Household.objects.filter(pk=existing_household.pk).exists())
        self.assertTrue(Membership.objects.filter(pk=existing_membership.pk).exists())
        self.assertTrue(Owner.objects.filter(pk=existing_owner.pk).exists())
