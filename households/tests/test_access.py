from django.contrib.auth import get_user_model
from django.test import TestCase

from households.models import FinancialOwner, Household, HouseholdMembership
from households.services import ensure_household_for_user

User = get_user_model()


class HouseholdAccessRevocationTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='revoked-access@example.com',
            password='test-password-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.membership = HouseholdMembership.objects.get(user=self.user)
        self.owners = list(
            FinancialOwner.objects.filter(household=self.household).order_by('pk')
        )
        self.client.force_login(self.user)

    def _deactivate_owners(self):
        FinancialOwner.objects.filter(household=self.household).update(is_active=False)

    def _assert_owners_stay_inactive(self):
        self.assertFalse(
            FinancialOwner.objects.filter(
                household=self.household,
                is_active=True,
            ).exists()
        )

    def test_inactive_membership_returns_403_without_reactivating_access(self):
        self.membership.is_active = False
        self.membership.save(update_fields=['is_active'])
        self._deactivate_owners()

        with self.assertLogs('households.mixins', level='WARNING') as captured:
            response = self.client.get('/dashboard/')

        self.assertEqual(response.status_code, 403)
        self.household.refresh_from_db()
        self.membership.refresh_from_db()
        self.assertTrue(self.household.is_active)
        self.assertFalse(self.membership.is_active)
        self._assert_owners_stay_inactive()
        warning = ' '.join(captured.output)
        self.assertNotIn(self.user.email, warning)
        self.assertNotIn(self.household.name, warning)

    def test_inactive_household_returns_403_without_reactivating_access(self):
        self.household.is_active = False
        self.household.save(update_fields=['is_active'])
        self._deactivate_owners()

        with self.assertLogs('households.mixins', level='WARNING') as captured:
            response = self.client.get('/dashboard/')

        self.assertEqual(response.status_code, 403)
        self.household.refresh_from_db()
        self.membership.refresh_from_db()
        self.assertFalse(self.household.is_active)
        self.assertTrue(self.membership.is_active)
        self._assert_owners_stay_inactive()
        warning = ' '.join(captured.output)
        self.assertNotIn(self.user.email, warning)
        self.assertNotIn(self.household.name, warning)


class AnonymousHouseholdAccessTest(TestCase):
    def test_anonymous_request_redirects_to_login_without_bootstrap(self):
        response = self.client.get('/dashboard/')

        self.assertRedirects(response, '/login/?next=/dashboard/')
        self.assertFalse(Household.objects.exists())
        self.assertFalse(HouseholdMembership.objects.exists())
        self.assertFalse(FinancialOwner.objects.exists())
