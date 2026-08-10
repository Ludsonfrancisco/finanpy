import threading

from django.contrib.auth import get_user_model
from django.db import IntegrityError, close_old_connections, models
from django.test import TestCase, TransactionTestCase

from households.models import FinancialOwner, Household, HouseholdMembership
from households.services import (
    _SQLITE_USER_LOCKS,
    _SQLITE_USER_LOCKS_GUARD,
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

    def test_user_cannot_have_two_active_household_memberships(self):
        ensure_household_for_user(self.user)
        another_household = Household.objects.create(name='Outro Lar')

        with self.assertRaises(IntegrityError):
            HouseholdMembership.objects.create(
                household=another_household,
                user=self.user,
                role=HouseholdMembership.ADMIN,
            )

    def test_user_can_keep_inactive_membership_history_with_one_active(self):
        historical_household = ensure_household_for_user(self.user)
        historical_membership = HouseholdMembership.objects.get(user=self.user)
        historical_membership.is_active = False
        historical_membership.save(update_fields=['is_active'])
        active_household = Household.objects.create(name='Lar Atual')

        active_membership = HouseholdMembership.objects.create(
            household=active_household,
            user=self.user,
            role=HouseholdMembership.ADMIN,
        )

        self.assertEqual(active_membership.household, active_household)
        self.assertEqual(
            HouseholdMembership.objects.filter(user=self.user).count(),
            2,
        )
        self.assertTrue(
            HouseholdMembership.objects.filter(
                user=self.user,
                household=historical_household,
                is_active=False,
            ).exists()
        )

    def test_membership_model_declares_pair_and_partial_active_constraints(self):
        constraints = {
            constraint.name: constraint
            for constraint in HouseholdMembership._meta.constraints
        }

        self.assertEqual(
            constraints['unique_household_membership'].fields,
            ('household', 'user'),
        )
        active_constraint = constraints[
            'unique_active_household_membership_user'
        ]
        self.assertEqual(active_constraint.fields, ('user',))
        self.assertEqual(
            active_constraint.condition,
            models.Q(is_active=True),
        )

    def test_bootstrap_reactivates_existing_inactive_household(self):
        household = ensure_household_for_user(self.user)
        membership = HouseholdMembership.objects.get(user=self.user)
        household.is_active = False
        household.save(update_fields=['is_active'])
        membership.is_active = False
        membership.save(update_fields=['is_active'])

        restored_household = ensure_household_for_user(self.user)

        membership.refresh_from_db()
        restored_household.refresh_from_db()
        self.assertEqual(restored_household, household)
        self.assertTrue(restored_household.is_active)
        self.assertTrue(membership.is_active)
        self.assertEqual(HouseholdMembership.objects.filter(user=self.user).count(), 1)
        self.assertEqual(FinancialOwner.objects.filter(household=household).count(), 3)

    def test_bootstrap_prefers_active_membership_over_older_inactive_history(self):
        historical_household = Household.objects.create(name='Lar HistÃ³rico')
        historical_membership = HouseholdMembership.objects.create(
            household=historical_household,
            user=self.user,
            role=HouseholdMembership.ADMIN,
            is_active=False,
        )
        active_household = Household.objects.create(name='Lar Atual')
        active_membership = HouseholdMembership.objects.create(
            household=active_household,
            user=self.user,
            role=HouseholdMembership.ADMIN,
            is_active=True,
        )

        restored_household = ensure_household_for_user(self.user)

        historical_membership.refresh_from_db()
        active_membership.refresh_from_db()
        self.assertEqual(restored_household, active_household)
        self.assertFalse(historical_membership.is_active)
        self.assertTrue(active_membership.is_active)
        self.assertEqual(
            FinancialOwner.objects.filter(household=active_household).count(),
            3,
        )
        self.assertFalse(
            FinancialOwner.objects.filter(household=historical_household).exists()
        )

    def test_bootstrap_rejects_ambiguous_inactive_membership_history(self):
        for name in ('Lar HistÃ³rico Um', 'Lar HistÃ³rico Dois'):
            HouseholdMembership.objects.create(
                household=Household.objects.create(name=name),
                user=self.user,
                role=HouseholdMembership.ADMIN,
                is_active=False,
            )
        before_memberships = list(
            HouseholdMembership.objects.filter(user=self.user)
            .order_by('pk')
            .values('pk', 'household_id', 'is_active')
        )

        with self.assertRaisesRegex(
            RuntimeError,
            'multiple inactive household memberships',
        ) as caught:
            ensure_household_for_user(self.user)

        self.assertNotIn(self.user.email, str(caught.exception))
        self.assertEqual(
            list(
                HouseholdMembership.objects.filter(user=self.user)
                .order_by('pk')
                .values('pk', 'household_id', 'is_active')
            ),
            before_memberships,
        )
        self.assertFalse(FinancialOwner.objects.exists())

    def test_bootstrap_restores_missing_and_inactive_owners_with_canonical_names(self):
        household = ensure_household_for_user(self.user)
        owners = {owner.type: owner for owner in household.financial_owners.all()}
        FinancialOwner.objects.filter(pk=owners[FinancialOwner.SELF].pk).update(
            name='Nome alterado',
            is_active=False,
        )
        FinancialOwner.objects.filter(pk=owners[FinancialOwner.SPOUSE].pk).update(
            name='Outro nome',
            is_active=False,
        )
        owners[FinancialOwner.SHARED].delete()

        restored_household = ensure_household_for_user(self.user)

        self.assertEqual(restored_household, household)
        self.assertEqual(
            {
                owner.type: (owner.name, owner.is_active)
                for owner in restored_household.financial_owners.all()
            },
            {
                FinancialOwner.SELF: ('Eu', True),
                FinancialOwner.SPOUSE: ('Esposa', True),
                FinancialOwner.SHARED: ('Conjunto', True),
            },
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


class HouseholdConcurrencyTest(TransactionTestCase):
    def setUp(self):
        with _SQLITE_USER_LOCKS_GUARD:
            _SQLITE_USER_LOCKS.clear()
        self.user = User.objects.create_user(
            email='concurrent-household-owner@example.com',
            password='test-password-123',
        )

    def test_concurrent_bootstrap_returns_one_household_without_errors(self):
        barrier = threading.Barrier(2)
        result_household_ids = []
        failures = []
        result_lock = threading.Lock()

        def bootstrap_household():
            close_old_connections()
            try:
                worker_user = User.objects.get(pk=self.user.pk)
                barrier.wait()
                household = ensure_household_for_user(worker_user)
                with result_lock:
                    result_household_ids.append(household.pk)
            except Exception as exc:
                with result_lock:
                    failures.append(exc)
            finally:
                close_old_connections()

        threads = [threading.Thread(target=bootstrap_household) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertFalse(failures, [repr(failure) for failure in failures])
        self.assertEqual(len(result_household_ids), 2)
        self.assertEqual(len(set(result_household_ids)), 1)
        self.assertEqual(HouseholdMembership.objects.filter(user=self.user).count(), 1)
        self.assertEqual(FinancialOwner.objects.count(), 3)
        self.assertEqual(_SQLITE_USER_LOCKS, {})
