import uuid

from django.db import migrations


OWNER_NAMES = {
    'self': 'Eu',
    'spouse': 'Esposa',
    'shared': 'Conjunto',
}

BACKFILL_NAMESPACE = uuid.UUID('a2d5460b-0812-49c6-a6cf-e64bd5f7b42f')


def backfill_household_uuid(user_id):
    return uuid.uuid5(BACKFILL_NAMESPACE, f'legacy-user:{user_id}')


def forwards(apps, schema_editor):
    User = apps.get_model('users', 'User')
    Household = apps.get_model('households', 'Household')
    Membership = apps.get_model('households', 'HouseholdMembership')
    Owner = apps.get_model('households', 'FinancialOwner')
    Account = apps.get_model('accounts', 'Account')
    Category = apps.get_model('categories', 'Category')
    Transaction = apps.get_model('transactions', 'Transaction')

    for user in User.objects.order_by('pk').iterator():
        if Membership.objects.filter(user_id=user.pk).exists():
            continue

        household = Household.objects.create(
            uuid=backfill_household_uuid(user.pk),
            name='Lar Finance',
        )
        Membership.objects.create(
            household=household,
            user_id=user.pk,
            role='admin',
        )
        owners = {
            owner_type: Owner.objects.create(
                household=household,
                type=owner_type,
                name=name,
            )
            for owner_type, name in OWNER_NAMES.items()
        }
        shared = owners['shared']
        Account.objects.filter(user_id=user.pk, household__isnull=True).update(
            household=household,
            financial_owner=shared,
        )
        Category.objects.filter(user_id=user.pk, household__isnull=True).update(
            household=household,
        )
        Transaction.objects.filter(user_id=user.pk, household__isnull=True).update(
            household=household,
            financial_owner=shared,
        )


def backwards(apps, schema_editor):
    Household = apps.get_model('households', 'Household')
    Membership = apps.get_model('households', 'HouseholdMembership')
    Account = apps.get_model('accounts', 'Account')
    Category = apps.get_model('categories', 'Category')
    Transaction = apps.get_model('transactions', 'Transaction')

    for membership in Membership.objects.filter(role='admin').order_by('pk').iterator():
        household = Household.objects.filter(
            pk=membership.household_id,
            uuid=backfill_household_uuid(membership.user_id),
        ).first()
        if household is None:
            continue

        Account.objects.filter(
            user_id=membership.user_id,
            household_id=household.pk,
        ).update(household=None, financial_owner=None)
        Category.objects.filter(
            user_id=membership.user_id,
            household_id=household.pk,
        ).update(household=None)
        Transaction.objects.filter(
            user_id=membership.user_id,
            household_id=household.pk,
        ).update(household=None, financial_owner=None)
        household.delete()


class Migration(migrations.Migration):
    dependencies = [
        ('households', '0001_initial'),
        ('users', '0001_initial'),
        ('accounts', '0002_account_household_financial_owner'),
        ('categories', '0002_category_household'),
        ('transactions', '0002_transaction_household_financial_owner'),
    ]

    operations = [migrations.RunPython(forwards, backwards)]
