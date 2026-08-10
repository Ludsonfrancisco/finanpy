import django
from django.db import migrations, models


MEMBERSHIP_TABLE = 'households_householdmembership'
PAIR_CONSTRAINT = 'unique_household_membership'
ACTIVE_CONSTRAINT = 'unique_active_household_membership_user'
LEGACY_GLOBAL_CONSTRAINT = 'unique_household_membership_user'
SUPPORTED_DJANGO_VERSION = '5.2.13'


def _physical_constraints(schema_editor):
    with schema_editor.connection.cursor() as cursor:
        return schema_editor.connection.introspection.get_constraints(
            cursor,
            MEMBERSHIP_TABLE,
        )


def _has_unique_columns(constraints, columns):
    expected = tuple(columns)
    return any(
        details.get('unique') and tuple(details.get('columns') or ()) == expected
        for details in constraints.values()
    )


def _assert_canonical_pair(constraints):
    pair = constraints.get(PAIR_CONSTRAINT)
    if not pair or not pair.get('unique') or pair.get('columns') != [
        'household_id',
        'user_id',
    ]:
        raise RuntimeError(
            'membership schema reconciliation failed: canonical pair constraint '
            'was not created'
        )


def forwards(apps, schema_editor):
    if schema_editor.collect_sql:
        schema_editor.execute(
            '-- Runtime SQLite introspection reconciles the historical '
            'membership table before this partial index is created'
        )
        schema_editor.execute(
            f'CREATE UNIQUE INDEX "{ACTIVE_CONSTRAINT}" '
            f'ON "{MEMBERSHIP_TABLE}" ("user_id") WHERE "is_active"'
        )
        return

    Membership = apps.get_model('households', 'HouseholdMembership')
    database_alias = schema_editor.connection.alias
    duplicate_pair_groups = (
        Membership.objects.using(database_alias)
        .values('household_id', 'user_id')
        .annotate(membership_count=models.Count('pk'))
        .filter(membership_count__gt=1)
        .count()
    )
    active_membership_users = (
        Membership.objects.using(database_alias)
        .filter(is_active=True)
        .values('user_id')
        .annotate(membership_count=models.Count('pk'))
        .filter(membership_count__gt=1)
        .count()
    )
    if duplicate_pair_groups or active_membership_users:
        raise RuntimeError(
            'membership uniqueness preflight failed: '
            f'duplicate_household_user_pairs={duplicate_pair_groups}, '
            f'active_membership_users={active_membership_users}'
        )

    constraints_before = _physical_constraints(schema_editor)
    canonical_pair = constraints_before.get(PAIR_CONSTRAINT)
    pair_is_canonical = bool(
        canonical_pair
        and canonical_pair.get('unique')
        and canonical_pair.get('columns') == ['household_id', 'user_id']
    )
    has_global_user_unique = _has_unique_columns(
        constraints_before,
        ['user_id'],
    )

    if not pair_is_canonical or has_global_user_unique:
        if schema_editor.connection.vendor != 'sqlite':
            raise RuntimeError(
                'membership schema reconciliation supports SQLite only'
            )
        if django.get_version() != SUPPORTED_DJANGO_VERSION:
            raise RuntimeError(
                'membership schema reconciliation requires Django '
                f'{SUPPORTED_DJANGO_VERSION}'
            )
        # SQLite cannot alter table constraints directly. Django 5.2.13's
        # schema editor rebuilds the table from the historical model state,
        # whose sole membership constraint is the canonical household/user pair.
        schema_editor._remake_table(Membership)

    constraints_after_pair = _physical_constraints(schema_editor)
    _assert_canonical_pair(constraints_after_pair)
    if _has_unique_columns(constraints_after_pair, ['user_id']):
        raise RuntimeError(
            'membership schema reconciliation failed: legacy global user '
            'constraint remains'
        )

    active_constraint = models.UniqueConstraint(
        fields=('user',),
        condition=models.Q(is_active=True),
        name=ACTIVE_CONSTRAINT,
    )
    schema_editor.add_constraint(Membership, active_constraint)

    constraints_after = _physical_constraints(schema_editor)
    _assert_canonical_pair(constraints_after)
    active = constraints_after.get(ACTIVE_CONSTRAINT)
    if not active or not active.get('unique') or active.get('columns') != ['user_id']:
        raise RuntimeError(
            'membership schema reconciliation failed: active user constraint '
            'was not created'
        )
    if LEGACY_GLOBAL_CONSTRAINT in constraints_after:
        raise RuntimeError(
            'membership schema reconciliation failed: legacy global constraint '
            'remains'
        )


def backwards(apps, schema_editor):
    if schema_editor.collect_sql:
        schema_editor.execute(f'DROP INDEX "{ACTIVE_CONSTRAINT}"')
        return

    Membership = apps.get_model('households', 'HouseholdMembership')
    active_constraint = models.UniqueConstraint(
        fields=('user',),
        condition=models.Q(is_active=True),
        name=ACTIVE_CONSTRAINT,
    )
    schema_editor.remove_constraint(Membership, active_constraint)

    constraints_after = _physical_constraints(schema_editor)
    _assert_canonical_pair(constraints_after)
    if ACTIVE_CONSTRAINT in constraints_after:
        raise RuntimeError(
            'membership schema reverse failed: active user constraint remains'
        )


class Migration(migrations.Migration):
    atomic = True

    dependencies = [
        ('households', '0002_backfill_existing_financial_data'),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(forwards, backwards),
            ],
            state_operations=[
                migrations.AddConstraint(
                    model_name='householdmembership',
                    constraint=models.UniqueConstraint(
                        fields=('user',),
                        condition=models.Q(is_active=True),
                        name=ACTIVE_CONSTRAINT,
                    ),
                ),
            ],
        ),
    ]
