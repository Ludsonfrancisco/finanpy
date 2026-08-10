from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TestCase

from households.models import FinancialOwner, Household, HouseholdMembership
from households.services import (
    ensure_household_for_user,
    get_financial_owner,
    get_household_for_user,
)

User = get_user_model()


class HouseholdModelTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='household-owner@example.com',
            password='test-password-123',
        )

    def test_bootstrap_creates_household_membership_and_three_owners(self):
        household = ensure_household_for_user(self.user)

        self.assertEqual(household.name, 'Lar Finance')
        self.assertTrue(
            HouseholdMembership.objects.filter(
                household=household,
                user=self.user,
                role=HouseholdMembership.ADMIN,
            ).exists()
        )
        self.assertEqual(
            set(household.financial_owners.values_list('type', flat=True)),
            {FinancialOwner.SELF, FinancialOwner.SPOUSE, FinancialOwner.SHARED},
        )

    def test_bootstrap_is_idempotent(self):
        first = ensure_household_for_user(self.user)
        second = ensure_household_for_user(self.user)

        self.assertEqual(first, second)
        self.assertEqual(Household.objects.count(), 1)
        self.assertEqual(FinancialOwner.objects.count(), 3)

    def test_owner_type_is_unique_inside_household(self):
        household = ensure_household_for_user(self.user)

        with self.assertRaises(IntegrityError):
            FinancialOwner.objects.create(
                household=household,
                type=FinancialOwner.SHARED,
                name='Outro conjunto',
            )

    def test_get_household_for_user_returns_active_household(self):
        household = ensure_household_for_user(self.user)

        self.assertEqual(get_household_for_user(self.user), household)

    def test_get_financial_owner_returns_shared_owner_by_default(self):
        household = ensure_household_for_user(self.user)

        self.assertEqual(
            get_financial_owner(household).type,
            FinancialOwner.SHARED,
        )
