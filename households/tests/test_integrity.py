from contextlib import redirect_stderr, redirect_stdout
from decimal import Decimal
from io import StringIO

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db.models.deletion import ProtectedError
from django.test import TestCase

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner, HouseholdMembership
from households.services import ensure_household_for_user, get_financial_owner
from transactions.models import Transaction

User = get_user_model()


class LegacyUserIntegrityTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='member@example.com',
            password='test-pass',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household)
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Mercado',
            type=Category.EXPENSE,
        )
        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Conta principal',
        )

    def _transaction(self, **overrides):
        values = {
            'user': self.user,
            'household': self.household,
            'financial_owner': self.owner,
            'account': self.account,
            'category': self.category,
            'description': 'Compra',
            'amount': Decimal('10.00'),
            'date': '2026-08-10',
            'type': Transaction.EXPENSE,
        }
        values.update(overrides)
        return Transaction(**values)

    def test_account_rejects_user_without_active_membership(self):
        outsider = User.objects.create_user(
            email='account-outsider@example.com',
            password='test-pass',
        )
        account = Account(
            user=outsider,
            household=self.household,
            financial_owner=self.owner,
            name='Conta inválida',
        )

        with self.assertRaises(ValidationError) as caught:
            account.full_clean()

        self.assertEqual(set(caught.exception.error_dict), {'user'})

    def test_category_rejects_user_without_active_membership(self):
        outsider = User.objects.create_user(
            email='category-outsider@example.com',
            password='test-pass',
        )
        category = Category(
            user=outsider,
            household=self.household,
            name='Categoria inválida',
            type=Category.EXPENSE,
        )

        with self.assertRaises(ValidationError) as caught:
            category.full_clean()

        self.assertEqual(set(caught.exception.error_dict), {'user'})

    def test_transaction_rejects_user_without_active_membership(self):
        outsider = User.objects.create_user(
            email='transaction-outsider@example.com',
            password='test-pass',
        )

        with self.assertRaises(ValidationError) as caught:
            self._transaction(user=outsider).full_clean()

        self.assertEqual(set(caught.exception.error_dict), {'user'})

    def test_inactive_membership_is_rejected(self):
        membership = HouseholdMembership.objects.get(
            household=self.household,
            user=self.user,
        )
        membership.is_active = False
        membership.save(update_fields=['is_active'])

        with self.assertRaises(ValidationError) as caught:
            self.account.full_clean()

        self.assertEqual(set(caught.exception.error_dict), {'user'})

    def test_different_members_of_same_household_are_valid(self):
        other_member = User.objects.create_user(
            email='other-member@example.com',
            password='test-pass',
        )
        HouseholdMembership.objects.create(
            household=self.household,
            user=other_member,
        )
        other_account = Account(
            user=other_member,
            household=self.household,
            financial_owner=self.owner,
            name='Conta do outro membro',
        )
        other_category = Category(
            user=other_member,
            household=self.household,
            name='Categoria do outro membro',
            type=Category.EXPENSE,
        )
        other_account.full_clean()
        other_category.full_clean()
        other_account.save()
        other_category.save()

        transaction = self._transaction(
            user=other_member,
            account=self.account,
            category=self.category,
        )

        transaction.full_clean()

    def test_deleting_ledger_user_is_protected(self):
        transaction = self._transaction()
        transaction.save()

        with self.assertRaises(ProtectedError):
            self.user.delete()

        self.assertTrue(User.objects.filter(pk=self.user.pk).exists())
        self.assertTrue(Account.objects.filter(pk=self.account.pk).exists())
        self.assertTrue(Category.objects.filter(pk=self.category.pk).exists())
        self.assertTrue(Transaction.objects.filter(pk=transaction.pk).exists())


class HouseholdIntegrityCommandTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='audit-member@example.com',
            password='test-pass',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household)
        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Conta auditada',
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Categoria auditada',
            type=Category.EXPENSE,
        )

    def _snapshot(self):
        return {
            'users': User.objects.count(),
            'memberships': HouseholdMembership.objects.count(),
            'owners': FinancialOwner.objects.count(),
            'accounts': Account.objects.count(),
            'categories': Category.objects.count(),
            'transactions': Transaction.objects.count(),
        }

    def test_clean_audit_succeeds_and_is_read_only(self):
        before = self._snapshot()
        stdout = StringIO()

        call_command('audit_household_integrity', stdout=stdout)

        output = stdout.getvalue()
        self.assertIn('duplicate_household_user_pairs=0', output)
        self.assertIn('multiple_active_memberships=0', output)
        self.assertIn('legacy_account_user_membership=0', output)
        self.assertIn('transaction_account_household=0', output)
        self.assertIn('integrity_status=ok', output)
        self.assertNotIn(self.user.email, output)
        self.assertNotIn(self.account.name, output)
        self.assertEqual(self._snapshot(), before)

    def test_audit_reports_each_required_owner_type(self):
        for owner_type in (
            FinancialOwner.SELF,
            FinancialOwner.SPOUSE,
            FinancialOwner.SHARED,
        ):
            with self.subTest(owner_type=owner_type):
                owner = FinancialOwner.objects.get(
                    household=self.household,
                    type=owner_type,
                )
                owner.is_active = False
                owner.save(update_fields=['is_active'])
                stdout = StringIO()
                stderr = StringIO()

                with self.assertRaises(CommandError):
                    call_command(
                        'audit_household_integrity',
                        stdout=stdout,
                        stderr=stderr,
                    )

                output = stdout.getvalue() + stderr.getvalue()
                self.assertIn(
                    f'inactive_or_missing_owner_{owner_type}=1',
                    output,
                )
                owner.is_active = True
                owner.save(update_fields=['is_active'])

    def test_audit_reports_each_missing_required_owner_type(self):
        for index, owner_type in enumerate((
            FinancialOwner.SELF,
            FinancialOwner.SPOUSE,
            FinancialOwner.SHARED,
        )):
            with self.subTest(owner_type=owner_type):
                user = User.objects.create_user(
                    email=f'missing-owner-{index}@example.com',
                    password='test-pass',
                )
                household = ensure_household_for_user(user)
                household.financial_owners.get(type=owner_type).delete()
                stdout = StringIO()
                stderr = StringIO()

                with self.assertRaises(CommandError):
                    call_command(
                        'audit_household_integrity',
                        stdout=stdout,
                        stderr=stderr,
                    )

                output = stdout.getvalue() + stderr.getvalue()
                self.assertIn(
                    f'inactive_or_missing_owner_{owner_type}=1',
                    output,
                )
                household.delete()

    def test_audit_reports_all_ledger_mismatch_families_without_pii(self):
        outsider = User.objects.create_user(
            email='audit-outsider@example.com',
            password='test-pass',
        )
        other_household = ensure_household_for_user(outsider)
        other_owner = get_financial_owner(other_household)
        other_account = Account.objects.create(
            user=outsider,
            household=other_household,
            financial_owner=other_owner,
            name='Conta externa sigilosa',
        )
        other_category = Category.objects.create(
            user=outsider,
            household=other_household,
            name='Categoria externa sigilosa',
            type=Category.EXPENSE,
        )
        invalid_account = Account.objects.create(
            user=outsider,
            household=self.household,
            financial_owner=other_owner,
            name='Conta inválida sigilosa',
        )
        invalid_category = Category.objects.create(
            user=outsider,
            household=self.household,
            name='Categoria inválida sigilosa',
            type=Category.EXPENSE,
        )
        Transaction.objects.create(
            user=outsider,
            household=self.household,
            financial_owner=other_owner,
            account=other_account,
            category=other_category,
            description='Movimentação sigilosa',
            amount=Decimal('99.00'),
            date='2026-08-10',
            type=Transaction.EXPENSE,
        )
        FinancialOwner.objects.filter(
            household=self.household,
            type=FinancialOwner.SELF,
        ).update(is_active=False)
        before = self._snapshot()
        stdout = StringIO()
        stderr = StringIO()

        with self.assertRaises(CommandError), redirect_stdout(stdout), redirect_stderr(stderr):
            call_command(
                'audit_household_integrity',
                stdout=stdout,
                stderr=stderr,
            )

        output = stdout.getvalue() + stderr.getvalue()
        expected_checks = {
            'inactive_or_missing_owner_self',
            'legacy_account_user_membership',
            'legacy_category_user_membership',
            'legacy_transaction_user_membership',
            'account_owner_household',
            'transaction_account_household',
            'transaction_category_household',
            'transaction_owner_household',
        }
        for check in expected_checks:
            self.assertRegex(output, rf'{check}=[1-9][0-9]*')
        for private_value in (
            outsider.email,
            invalid_account.name,
            invalid_category.name,
            'Movimentação sigilosa',
            '99.00',
        ):
            self.assertNotIn(private_value, output)
        self.assertEqual(self._snapshot(), before)
