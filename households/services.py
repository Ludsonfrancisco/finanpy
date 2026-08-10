from django.core.exceptions import ObjectDoesNotExist
from django.db import transaction

from .models import FinancialOwner, Household, HouseholdMembership

OWNER_NAMES = {
    FinancialOwner.SELF: 'Eu',
    FinancialOwner.SPOUSE: 'Esposa',
    FinancialOwner.SHARED: 'Conjunto',
}


@transaction.atomic
def ensure_household_for_user(user):
    locked_user = user.__class__.objects.select_for_update().get(pk=user.pk)
    membership = (
        HouseholdMembership.objects.select_related('household')
        .filter(user=locked_user, is_active=True, household__is_active=True)
        .order_by('pk')
        .first()
    )
    if membership:
        household = membership.household
    else:
        household = Household.objects.create(name='Lar Finance')
        HouseholdMembership.objects.create(
            household=household,
            user=locked_user,
            role=HouseholdMembership.ADMIN,
        )

    for owner_type, name in OWNER_NAMES.items():
        FinancialOwner.objects.get_or_create(
            household=household,
            type=owner_type,
            defaults={'name': name},
        )
    return household


def get_household_for_user(user):
    try:
        return Household.objects.get(
            memberships__user=user,
            memberships__is_active=True,
            is_active=True,
        )
    except ObjectDoesNotExist as exc:
        raise Household.DoesNotExist('Usuário sem Lar ativo.') from exc


def get_financial_owner(household, owner_type=FinancialOwner.SHARED):
    return FinancialOwner.objects.get(
        household=household,
        type=owner_type,
        is_active=True,
    )
