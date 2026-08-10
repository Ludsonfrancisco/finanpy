from django.core.management.base import BaseCommand, CommandError
from django.db.models import Count, Exists, F, OuterRef

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner, Household, HouseholdMembership
from transactions.models import Transaction


class Command(BaseCommand):
    help = (
        'Audita relações do Lar sem alterar dados. Execute antes e depois das '
        'migrations em uma cópia e novamente no EasyPanel.'
    )

    def handle(self, *args, **options):
        active_membership = HouseholdMembership.objects.filter(
            household_id=OuterRef('household_id'),
            user_id=OuterRef('user_id'),
            is_active=True,
        )
        checks = {
            'duplicate_household_user_pairs': (
                HouseholdMembership.objects.values('household_id', 'user_id')
                .annotate(row_count=Count('pk'))
                .filter(row_count__gt=1)
                .count()
            ),
            'multiple_active_memberships': (
                HouseholdMembership.objects.filter(is_active=True)
                .values('user_id')
                .annotate(row_count=Count('pk'))
                .filter(row_count__gt=1)
                .count()
            ),
        }
        for owner_type in (
            FinancialOwner.SELF,
            FinancialOwner.SPOUSE,
            FinancialOwner.SHARED,
        ):
            active_owner = FinancialOwner.objects.filter(
                household_id=OuterRef('pk'),
                type=owner_type,
                is_active=True,
            )
            checks[f'inactive_or_missing_owner_{owner_type}'] = (
                Household.objects.filter(is_active=True)
                .annotate(has_active_owner=Exists(active_owner))
                .filter(has_active_owner=False)
                .count()
            )

        checks.update(
            {
                'legacy_account_user_membership': (
                    Account.objects.annotate(
                        has_active_membership=Exists(active_membership),
                    )
                    .filter(has_active_membership=False)
                    .count()
                ),
                'legacy_category_user_membership': (
                    Category.objects.annotate(
                        has_active_membership=Exists(active_membership),
                    )
                    .filter(has_active_membership=False)
                    .count()
                ),
                'legacy_transaction_user_membership': (
                    Transaction.objects.annotate(
                        has_active_membership=Exists(active_membership),
                    )
                    .filter(has_active_membership=False)
                    .count()
                ),
                'account_owner_household': Account.objects.exclude(
                    financial_owner__household_id=F('household_id'),
                ).count(),
                'transaction_account_household': Transaction.objects.exclude(
                    account__household_id=F('household_id'),
                ).count(),
                'transaction_category_household': Transaction.objects.exclude(
                    category__household_id=F('household_id'),
                ).count(),
                'transaction_owner_household': Transaction.objects.exclude(
                    financial_owner__household_id=F('household_id'),
                ).count(),
            }
        )

        for check_name, count in checks.items():
            self.stdout.write(f'{check_name}={count}')

        failed_checks = sum(count > 0 for count in checks.values())
        if failed_checks:
            raise CommandError(
                f'integrity_status=failed; inconsistent_checks={failed_checks}'
            )
        self.stdout.write(self.style.SUCCESS('integrity_status=ok'))
