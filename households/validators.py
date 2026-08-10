from .models import HouseholdMembership


def has_active_household_membership(*, user_id, household_id):
    if not user_id or not household_id:
        return False
    return HouseholdMembership.objects.filter(
        user_id=user_id,
        household_id=household_id,
        is_active=True,
    ).exists()
