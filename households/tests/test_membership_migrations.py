import importlib
from datetime import datetime, timezone

import django
from django.db import IntegrityError, connection, models
from django.db.migrations.executor import MigrationExecutor
from django.db.migrations.recorder import MigrationRecorder
from django.test import SimpleTestCase, TransactionTestCase
from django.test.utils import CaptureQueriesContext

MEMBERSHIP_TABLE = 'households_householdmembership'
PAIR_CONSTRAINT = 'unique_household_membership'
ACTIVE_CONSTRAINT = 'unique_active_household_membership_user'
LEGACY_GLOBAL_CONSTRAINT = 'unique_household_membership_user'


def membership_constraints():
    with connection.cursor() as cursor:
        return connection.introspection.get_constraints(cursor, MEMBERSHIP_TABLE)


def partial_constraint_sql():
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = %s",
            [ACTIVE_CONSTRAINT],
        )
        row = cursor.fetchone()
    return None if row is None else row[0]


def sqlite_integrity():
    with connection.cursor() as cursor:
        cursor.execute('PRAGMA integrity_check')
        integrity_rows = cursor.fetchall()
        cursor.execute('PRAGMA foreign_key_check')
        foreign_key_rows = cursor.fetchall()
    return integrity_rows, foreign_key_rows


def replace_physical_membership_constraints(Membership, constraints):
    # Django's SQLite schema editor has no public table-rebuild primitive.
    # Task 8 supports and pins Django 5.2.13, whose implementation is exercised
    # here against physical disposable test databases before migration use.
    if django.get_version() != '5.2.13':
        raise AssertionError('membership schema fixtures require Django 5.2.13')
    original_constraints = Membership._meta.constraints
    Membership._meta.constraints = constraints
    try:
        with connection.schema_editor() as schema_editor:
            schema_editor._remake_table(Membership)
    finally:
        Membership._meta.constraints = original_constraints


def canonical_pair_constraint():
    return models.UniqueConstraint(
        fields=('household', 'user'),
        name=PAIR_CONSTRAINT,
    )


class ReconcileMembershipSqlCollectionTest(SimpleTestCase):
    class CollectingSchemaEditor:
        collect_sql = True

        def __init__(self):
            self.statements = []

        def execute(self, statement):
            self.statements.append(statement)

    def test_sql_collection_does_not_require_a_physical_table(self):
        migration = importlib.import_module(
            'households.migrations.0003_reconcile_membership_uniqueness'
        )
        schema_editor = self.CollectingSchemaEditor()

        migration.forwards(None, schema_editor)

        self.assertIn(ACTIVE_CONSTRAINT, ' '.join(schema_editor.statements))
        self.assertIn('CREATE UNIQUE INDEX', ' '.join(schema_editor.statements))

    def test_reverse_sql_collection_removes_only_the_partial_index(self):
        migration = importlib.import_module(
            'households.migrations.0003_reconcile_membership_uniqueness'
        )
        schema_editor = self.CollectingSchemaEditor()

        migration.backwards(None, schema_editor)

        sql = ' '.join(schema_editor.statements)
        self.assertIn(f'DROP INDEX "{ACTIVE_CONSTRAINT}"', sql)
        self.assertNotIn(PAIR_CONSTRAINT, sql)


class CanonicalInitialMembershipMigrationTest(TransactionTestCase):
    migrate_to = [('households', '0001_initial')]

    def setUp(self):
        super().setUp()
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_to)
        self.apps = executor.loader.project_state(self.migrate_to).apps

    def tearDown(self):
        Household = self.apps.get_model('households', 'Household')
        Household.objects.all().delete()
        executor = MigrationExecutor(connection)
        executor.migrate(executor.loader.graph.leaf_nodes())
        super().tearDown()

    def test_initial_migration_uses_canonical_household_user_uniqueness(self):
        User = self.apps.get_model('users', 'User')
        Household = self.apps.get_model('households', 'Household')
        Membership = self.apps.get_model('households', 'HouseholdMembership')

        user = User.objects.create(
            email='canonical-membership@example.com',
            password='legacy-password-hash',
        )
        first_household = Household.objects.create(name='Primeiro Lar')
        second_household = Household.objects.create(name='Segundo Lar')
        Membership.objects.create(household=first_household, user=user)

        historical_membership = Membership.objects.create(
            household=second_household,
            user=user,
            is_active=False,
        )

        self.assertIsNotNone(historical_membership.pk)
        with self.assertRaises(IntegrityError):
            Membership.objects.create(
                household=first_household,
                user=user,
                is_active=False,
            )

        with connection.cursor() as cursor:
            constraints = connection.introspection.get_constraints(
                cursor,
                MEMBERSHIP_TABLE,
            )
        self.assertIn(PAIR_CONSTRAINT, constraints)
        self.assertEqual(
            constraints[PAIR_CONSTRAINT]['columns'],
            ['household_id', 'user_id'],
        )
        self.assertNotIn(LEGACY_GLOBAL_CONSTRAINT, constraints)


class FreshMembershipSchemaMigrationTest(TransactionTestCase):
    def test_fresh_database_has_pair_and_partial_active_constraints(self):
        constraints = membership_constraints()

        self.assertEqual(
            constraints[PAIR_CONSTRAINT]['columns'],
            ['household_id', 'user_id'],
        )
        self.assertEqual(
            constraints[ACTIVE_CONSTRAINT]['columns'],
            ['user_id'],
        )
        self.assertIn('WHERE "is_active"', partial_constraint_sql())
        self.assertEqual(sqlite_integrity(), ([('ok',)], []))


class ReconcileMembershipUniquenessMigrationTest(TransactionTestCase):
    migrate_from = [('households', '0002_backfill_existing_financial_data')]
    migrate_to = [('households', '0003_reconcile_membership_uniqueness')]

    def setUp(self):
        super().setUp()
        executor = MigrationExecutor(connection)
        executor.migrate(self.migrate_from)
        self.old_apps = executor.loader.project_state(self.migrate_from).apps

    def tearDown(self):
        executor = MigrationExecutor(connection)
        if not self._migration_is_applied():
            Membership = self.old_apps.get_model(
                'households',
                'HouseholdMembership',
            )
            Household = self.old_apps.get_model('households', 'Household')
            Household.objects.all().delete()
            constraints = membership_constraints()
            if (
                PAIR_CONSTRAINT not in constraints
                or constraints[PAIR_CONSTRAINT]['columns']
                != ['household_id', 'user_id']
            ):
                replace_physical_membership_constraints(
                    Membership,
                    [canonical_pair_constraint()],
                )
        executor = MigrationExecutor(connection)
        executor.migrate(executor.loader.graph.leaf_nodes())
        super().tearDown()

    def _migration_is_applied(self):
        return MigrationRecorder(connection).migration_qs.filter(
            app='households',
            name='0003_reconcile_membership_uniqueness',
        ).exists()

    def _create_user(self, email):
        User = self.old_apps.get_model('users', 'User')
        return User.objects.create(email=email, password='legacy-password-hash')

    def _migrate(self, target=None):
        target = target or self.migrate_to
        executor = MigrationExecutor(connection)
        executor.migrate(target)
        return executor.loader.project_state(target).apps

    def _rows(self, apps):
        Membership = apps.get_model('households', 'HouseholdMembership')
        return list(
            Membership.objects.order_by('pk').values(
                'pk',
                'household_id',
                'user_id',
                'role',
                'is_active',
                'created_at',
            )
        )

    def _assert_abort_without_ddl(self, expected_detail):
        before_rows = self._rows(self.old_apps)
        before_constraints = membership_constraints()
        before_integrity = sqlite_integrity()

        with CaptureQueriesContext(connection) as queries:
            with self.assertRaisesRegex(RuntimeError, expected_detail) as caught:
                self._migrate()

        message = str(caught.exception)
        self.assertIn('membership uniqueness preflight failed', message)
        self.assertNotIn('@example.com', message)
        ddl = [
            query['sql']
            for query in queries.captured_queries
            if any(
                marker in query['sql'].upper()
                for marker in (
                    'ALTER TABLE',
                    'CREATE TABLE',
                    'DROP TABLE',
                    'CREATE INDEX',
                    'DROP INDEX',
                )
            )
        ]
        self.assertEqual(ddl, [])
        self.assertEqual(self._rows(self.old_apps), before_rows)
        self.assertEqual(membership_constraints(), before_constraints)
        self.assertEqual(sqlite_integrity(), before_integrity)
        self.assertFalse(self._migration_is_applied())

    def test_original_pair_schema_accepts_history_and_adds_active_constraint(self):
        Household = self.old_apps.get_model('households', 'Household')
        Membership = self.old_apps.get_model('households', 'HouseholdMembership')
        user = self._create_user('pair-schema@example.com')
        historical_household = Household.objects.create(name='Lar HistÃ³rico')
        active_household = Household.objects.create(name='Lar Atual')
        Membership.objects.create(
            household=historical_household,
            user=user,
            role='admin',
            is_active=False,
        )
        Membership.objects.create(
            household=active_household,
            user=user,
            role='admin',
            is_active=True,
        )
        before_rows = self._rows(self.old_apps)

        migrated_apps = self._migrate()

        self.assertEqual(self._rows(migrated_apps), before_rows)
        constraints = membership_constraints()
        self.assertEqual(
            constraints[PAIR_CONSTRAINT]['columns'],
            ['household_id', 'user_id'],
        )
        self.assertEqual(
            constraints[ACTIVE_CONSTRAINT]['columns'],
            ['user_id'],
        )
        self.assertNotIn(LEGACY_GLOBAL_CONSTRAINT, constraints)
        self.assertEqual(sqlite_integrity(), ([('ok',)], []))

        Membership = migrated_apps.get_model('households', 'HouseholdMembership')
        third_household = Household.objects.create(name='Terceiro Lar')
        with self.assertRaises(IntegrityError):
            Membership.objects.create(
                household_id=third_household.pk,
                user_id=user.pk,
                is_active=True,
            )

    def test_rewritten_global_schema_is_rebuilt_without_data_loss(self):
        Household = self.old_apps.get_model('households', 'Household')
        Membership = self.old_apps.get_model('households', 'HouseholdMembership')
        first_user = self._create_user('global-one@example.com')
        second_user = self._create_user('global-two@example.com')
        first_household = Household.objects.create(name='Lar Global Um')
        second_household = Household.objects.create(name='Lar Global Dois')
        first_membership = Membership.objects.create(
            household=first_household,
            user=first_user,
            role='admin',
            is_active=False,
        )
        second_membership = Membership.objects.create(
            household=second_household,
            user=second_user,
            role='admin',
            is_active=True,
        )
        first_created_at = datetime(2024, 1, 2, 3, 4, 5, tzinfo=timezone.utc)
        second_created_at = datetime(2025, 6, 7, 8, 9, 10, tzinfo=timezone.utc)
        Membership.objects.filter(pk=first_membership.pk).update(
            created_at=first_created_at,
        )
        Membership.objects.filter(pk=second_membership.pk).update(
            created_at=second_created_at,
        )
        replace_physical_membership_constraints(
            Membership,
            [
                models.UniqueConstraint(
                    fields=('user',),
                    name=LEGACY_GLOBAL_CONSTRAINT,
                )
            ],
        )
        before_rows = self._rows(self.old_apps)
        before_integrity = sqlite_integrity()
        before_constraints = membership_constraints()
        self.assertNotIn(PAIR_CONSTRAINT, before_constraints)
        self.assertEqual(
            before_constraints[LEGACY_GLOBAL_CONSTRAINT]['columns'],
            ['user_id'],
        )

        migrated_apps = self._migrate()

        self.assertEqual(self._rows(migrated_apps), before_rows)
        self.assertEqual(sqlite_integrity(), before_integrity)
        constraints = membership_constraints()
        self.assertEqual(
            constraints[PAIR_CONSTRAINT]['columns'],
            ['household_id', 'user_id'],
        )
        self.assertEqual(
            constraints[ACTIVE_CONSTRAINT]['columns'],
            ['user_id'],
        )
        self.assertNotIn(LEGACY_GLOBAL_CONSTRAINT, constraints)

        Membership = migrated_apps.get_model('households', 'HouseholdMembership')
        historical_household = Household.objects.create(name='Outro HistÃ³rico')
        historical = Membership.objects.create(
            household_id=historical_household.pk,
            user_id=second_user.pk,
            role='admin',
            is_active=False,
        )
        self.assertIsNotNone(historical.pk)

    def test_two_active_memberships_abort_before_ddl(self):
        Household = self.old_apps.get_model('households', 'Household')
        Membership = self.old_apps.get_model('households', 'HouseholdMembership')
        user = self._create_user('duplicate-active@example.com')
        for name in ('Lar Ativo Um', 'Lar Ativo Dois'):
            Membership.objects.create(
                household=Household.objects.create(name=name),
                user=user,
                is_active=True,
            )

        self._assert_abort_without_ddl('active_membership_users=1')

    def test_duplicate_household_user_pair_aborts_before_ddl(self):
        Household = self.old_apps.get_model('households', 'Household')
        Membership = self.old_apps.get_model('households', 'HouseholdMembership')
        user = self._create_user('duplicate-pair@example.com')
        household = Household.objects.create(name='Lar Duplicado')
        replace_physical_membership_constraints(Membership, [])
        Membership.objects.create(household=household, user=user, is_active=False)
        Membership.objects.create(household=household, user=user, is_active=False)

        self._assert_abort_without_ddl('duplicate_household_user_pairs=1')

    def test_round_trip_removes_only_partial_constraint_and_preserves_rows(self):
        Household = self.old_apps.get_model('households', 'Household')
        Membership = self.old_apps.get_model('households', 'HouseholdMembership')
        user = self._create_user('round-trip@example.com')
        Membership.objects.create(
            household=Household.objects.create(name='Lar Antigo'),
            user=user,
            is_active=False,
        )
        Membership.objects.create(
            household=Household.objects.create(name='Lar Novo'),
            user=user,
            is_active=True,
        )
        before_rows = self._rows(self.old_apps)

        migrated_apps = self._migrate()
        first_forward_rows = self._rows(migrated_apps)
        self.assertIn(PAIR_CONSTRAINT, membership_constraints())
        self.assertIn(ACTIVE_CONSTRAINT, membership_constraints())

        rolled_back_apps = self._migrate(self.migrate_from)
        rolled_back_constraints = membership_constraints()
        self.assertEqual(self._rows(rolled_back_apps), before_rows)
        self.assertIn(PAIR_CONSTRAINT, rolled_back_constraints)
        self.assertNotIn(ACTIVE_CONSTRAINT, rolled_back_constraints)

        migrated_again_apps = self._migrate()
        self.assertEqual(self._rows(migrated_again_apps), first_forward_rows)
        self.assertIn(PAIR_CONSTRAINT, membership_constraints())
        self.assertIn(ACTIVE_CONSTRAINT, membership_constraints())
        self.assertEqual(sqlite_integrity(), ([('ok',)], []))
