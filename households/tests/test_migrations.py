import uuid
from datetime import date
from decimal import Decimal

from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.db.migrations.recorder import MigrationRecorder
from django.test import TransactionTestCase

BACKFILL_NAMESPACE = uuid.UUID('a2d5460b-0812-49c6-a6cf-e64bd5f7b42f')


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
        self.old_apps = executor.loader.project_state(self.migrate_from).apps

        User = self.old_apps.get_model('users', 'User')
        Account = self.old_apps.get_model('accounts', 'Account')
        Category = self.old_apps.get_model('categories', 'Category')
        Transaction = self.old_apps.get_model('transactions', 'Transaction')

        self.ledger_user_id = User.objects.create(
            email='ledger-legacy@example.com',
            password='legacy-password-hash',
            first_name='Pessoa',
            last_name='Legada',
        ).pk
        self.empty_user_id = User.objects.create(
            email='empty-legacy@example.com',
            password='empty-password-hash',
        ).pk
        self.account_id = Account.objects.create(
            user_id=self.ledger_user_id,
            name='Conta Legada',
            type='checking',
            initial_balance=Decimal('875.25'),
            currency='BRL',
            household=None,
            financial_owner=None,
        ).pk
        self.category_id = Category.objects.create(
            user_id=self.ledger_user_id,
            name='Mercado',
            type='expense',
            color='#123456',
            icon='cart',
            household=None,
        ).pk
        self.transaction_id = Transaction.objects.create(
            user_id=self.ledger_user_id,
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
        if not self._migration_is_applied():
            self._clear_preflight_inconsistencies()
        executor = MigrationExecutor(connection)
        executor.migrate(executor.loader.graph.leaf_nodes())
        super().tearDown()

    def _migration_is_applied(self):
        return MigrationRecorder(connection).migration_qs.filter(
            app='households',
            name='0002_backfill_existing_financial_data',
        ).exists()

    def _clear_preflight_inconsistencies(self):
        Account = self.old_apps.get_model('accounts', 'Account')
        Category = self.old_apps.get_model('categories', 'Category')
        Transaction = self.old_apps.get_model('transactions', 'Transaction')
        Household = self.old_apps.get_model('households', 'Household')

        Account.objects.update(household=None, financial_owner=None)
        Category.objects.update(household=None)
        Transaction.objects.update(household=None, financial_owner=None)
        Household.objects.all().delete()

    def _migrate_to_backfill(self):
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_to)
        return executor.loader.project_state(self.migrate_to).apps

    def _roll_back(self):
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_from)
        return executor.loader.project_state(self.migrate_from).apps

    def _database_snapshot(self):
        model_names = {
            'users': ('users', 'User'),
            'households': ('households', 'Household'),
            'memberships': ('households', 'HouseholdMembership'),
            'owners': ('households', 'FinancialOwner'),
            'accounts': ('accounts', 'Account'),
            'categories': ('categories', 'Category'),
            'transactions': ('transactions', 'Transaction'),
        }
        return {
            label: list(
                self.old_apps.get_model(app_label, model_name)
                .objects.order_by('pk')
                .values()
            )
            for label, (app_label, model_name) in model_names.items()
        }

    def _assert_preflight_aborts_without_changes(self, expected_counts):
        before = self._database_snapshot()

        with self.assertRaises(RuntimeError) as caught:
            self._migrate_to_backfill()

        message = str(caught.exception)
        self.assertIn('household backfill preflight failed', message)
        for inconsistency, count in expected_counts.items():
            self.assertIn(f'{inconsistency}={count}', message)
        self.assertNotIn('ledger-legacy@example.com', message)
        self.assertNotIn('Conta Legada', message)
        self.assertNotIn('875.25', message)
        self.assertEqual(self._database_snapshot(), before)
        self.assertFalse(self._migration_is_applied())

    def test_backfills_every_user_and_reverses_without_data_loss(self):
        migrated_apps = self._migrate_to_backfill()

        User = migrated_apps.get_model('users', 'User')
        Household = migrated_apps.get_model('households', 'Household')
        Membership = migrated_apps.get_model('households', 'HouseholdMembership')
        Owner = migrated_apps.get_model('households', 'FinancialOwner')
        Account = migrated_apps.get_model('accounts', 'Account')
        Category = migrated_apps.get_model('categories', 'Category')
        Transaction = migrated_apps.get_model('transactions', 'Transaction')

        self.assertEqual(User.objects.count(), 2)
        self.assertEqual(Household.objects.count(), 2)
        self.assertEqual(Membership.objects.count(), 2)
        self.assertEqual(Owner.objects.count(), 6)

        first_household_uuids = {}
        for user_id in (self.ledger_user_id, self.empty_user_id):
            membership = Membership.objects.get(user_id=user_id)
            household = Household.objects.get(pk=membership.household_id)
            expected_uuid = uuid.uuid5(BACKFILL_NAMESPACE, f'legacy-user:{user_id}')
            self.assertEqual(household.uuid, expected_uuid)
            self.assertEqual(household.uuid.version, 5)
            self.assertEqual(membership.role, 'admin')
            self.assertEqual(
                set(Owner.objects.filter(household=household).values_list('type', 'name')),
                {('self', 'Eu'), ('spouse', 'Esposa'), ('shared', 'Conjunto')},
            )
            first_household_uuids[user_id] = household.uuid

        ledger_household = Household.objects.get(memberships__user_id=self.ledger_user_id)
        empty_household = Household.objects.get(memberships__user_id=self.empty_user_id)
        shared_owner = Owner.objects.get(household=ledger_household, type='shared')
        self.assertEqual(Account.objects.filter(household=ledger_household).count(), 1)
        self.assertEqual(Category.objects.filter(household=ledger_household).count(), 1)
        self.assertEqual(Transaction.objects.filter(household=ledger_household).count(), 1)
        self.assertEqual(Account.objects.filter(household=empty_household).count(), 0)
        self.assertEqual(Category.objects.filter(household=empty_household).count(), 0)
        self.assertEqual(Transaction.objects.filter(household=empty_household).count(), 0)

        account = Account.objects.get(pk=self.account_id)
        category = Category.objects.get(pk=self.category_id)
        transaction = Transaction.objects.get(pk=self.transaction_id)
        self.assertEqual(account.financial_owner_id, shared_owner.pk)
        self.assertEqual(transaction.financial_owner_id, shared_owner.pk)
        self.assertEqual(account.household_id, ledger_household.pk)
        self.assertEqual(category.household_id, ledger_household.pk)
        self.assertEqual(transaction.household_id, ledger_household.pk)
        self.assertEqual(account.initial_balance, Decimal('875.25'))
        self.assertEqual(transaction.amount, Decimal('125.50'))
        self.assertEqual(transaction.account_id, self.account_id)
        self.assertEqual(transaction.category_id, self.category_id)

        unmarked_household = Household.objects.create(name='Unmarked post-migration household')
        unmarked_household_id = unmarked_household.pk
        rolled_back_apps = self._roll_back()

        Household = rolled_back_apps.get_model('households', 'Household')
        Membership = rolled_back_apps.get_model('households', 'HouseholdMembership')
        Owner = rolled_back_apps.get_model('households', 'FinancialOwner')
        User = rolled_back_apps.get_model('users', 'User')
        Account = rolled_back_apps.get_model('accounts', 'Account')
        Category = rolled_back_apps.get_model('categories', 'Category')
        Transaction = rolled_back_apps.get_model('transactions', 'Transaction')

        self.assertEqual(Household.objects.count(), 1)
        self.assertTrue(Household.objects.filter(pk=unmarked_household_id).exists())
        self.assertEqual(Membership.objects.count(), 0)
        self.assertEqual(Owner.objects.count(), 0)
        self.assertEqual(User.objects.count(), 2)
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
        self.assertEqual(transaction.user_id, self.ledger_user_id)

        Household.objects.filter(pk=unmarked_household_id).delete()
        migrated_again_apps = self._migrate_to_backfill()
        Membership = migrated_again_apps.get_model('households', 'HouseholdMembership')
        Household = migrated_again_apps.get_model('households', 'Household')
        second_household_uuids = {
            user_id: Household.objects.get(
                pk=Membership.objects.get(user_id=user_id).household_id
            ).uuid
            for user_id in (self.ledger_user_id, self.empty_user_id)
        }
        self.assertEqual(second_household_uuids, first_household_uuids)

    def test_preflight_aborts_for_preexisting_household_membership(self):
        Household = self.old_apps.get_model('households', 'Household')
        Membership = self.old_apps.get_model('households', 'HouseholdMembership')

        existing_household = Household.objects.create(name='Lar preexistente')
        Membership.objects.create(
            household=existing_household,
            user_id=self.ledger_user_id,
            role='admin',
        )

        self._assert_preflight_aborts_without_changes(
            {'households': 1, 'memberships': 1}
        )

    def test_preflight_aborts_for_partially_populated_ledger_links(self):
        Household = self.old_apps.get_model('households', 'Household')
        Owner = self.old_apps.get_model('households', 'FinancialOwner')
        Account = self.old_apps.get_model('accounts', 'Account')
        Category = self.old_apps.get_model('categories', 'Category')
        Transaction = self.old_apps.get_model('transactions', 'Transaction')

        existing_household = Household.objects.create(name='Lar parcial')
        existing_owner = Owner.objects.create(
            household=existing_household,
            type='shared',
            name='Conjunto parcial',
        )
        Account.objects.filter(pk=self.account_id).update(household=existing_household)
        Category.objects.filter(pk=self.category_id).update(household=existing_household)
        Transaction.objects.filter(pk=self.transaction_id).update(
            financial_owner=existing_owner
        )

        self._assert_preflight_aborts_without_changes(
            {
                'households': 1,
                'financial_owners': 1,
                'accounts.household': 1,
                'categories.household': 1,
                'transactions.financial_owner': 1,
            }
        )
