from decimal import Decimal

from django.db import transaction
from django.db.models import Max, Sum
from django.utils import timezone
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import Account
from api.resource_serializers import (
    serialize_entity,
    serialize_household,
    serialize_owner,
    serialize_summary,
)
from categories.models import Category
from households.models import FinancialOwner
from sync.cursors import encode_cursor
from sync.models import SyncChange
from transactions.models import Transaction


def _household(request):
    return request.auth.household


def _owners(household):
    return FinancialOwner.objects.filter(household=household).order_by('type', 'uuid')


def _accounts(household):
    return Account.objects.filter(household=household).select_related(
        'household', 'financial_owner'
    )


def _categories(household):
    return Category.objects.filter(household=household).select_related('household')


def _transactions(household):
    return Transaction.objects.filter(household=household).select_related(
        'household', 'financial_owner', 'account', 'category'
    )


def _summary(household):
    initial_balance = (
        Account.objects.filter(household=household).aggregate(
            total=Sum('initial_balance')
        )['total']
        or Decimal('0.00')
    )
    household_transactions = Transaction.objects.filter(household=household)
    total_income = (
        household_transactions.filter(type=Transaction.INCOME).aggregate(
            total=Sum('amount')
        )['total']
        or Decimal('0.00')
    )
    total_expenses = (
        household_transactions.filter(type=Transaction.EXPENSE).aggregate(
            total=Sum('amount')
        )['total']
        or Decimal('0.00')
    )
    total_balance = initial_balance + total_income - total_expenses
    today = timezone.localdate()
    monthly = household_transactions.filter(
        date__year=today.year,
        date__month=today.month,
    )
    monthly_income = (
        monthly.filter(type=Transaction.INCOME).aggregate(total=Sum('amount'))['total']
        or Decimal('0.00')
    )
    monthly_expenses = (
        monthly.filter(type=Transaction.EXPENSE).aggregate(total=Sum('amount'))['total']
        or Decimal('0.00')
    )
    return serialize_summary(
        total_balance=total_balance,
        monthly_income=monthly_income,
        monthly_expenses=monthly_expenses,
    )


class HouseholdView(APIView):
    def get(self, request):
        return Response(serialize_household(_household(request)))


class OwnerListView(APIView):
    def get(self, request):
        return Response([serialize_owner(owner) for owner in _owners(_household(request))])


class AccountListView(APIView):
    def get(self, request):
        return Response([serialize_entity(account) for account in _accounts(_household(request))])


class CategoryListView(APIView):
    def get(self, request):
        return Response(
            [serialize_entity(category) for category in _categories(_household(request))]
        )


class TransactionListView(APIView):
    def get(self, request):
        return Response(
            [
                serialize_entity(transaction)
                for transaction in _transactions(_household(request))
            ]
        )


class SummaryView(APIView):
    def get(self, request):
        return Response(_summary(_household(request)))


class BootstrapView(APIView):
    @transaction.atomic
    def get(self, request):
        household = _household(request)
        body = {
            'household': serialize_household(household),
            'owners': [serialize_owner(owner) for owner in _owners(household)],
            'accounts': [serialize_entity(account) for account in _accounts(household)],
            'categories': [
                serialize_entity(category) for category in _categories(household)
            ],
            'transactions': [
                serialize_entity(item) for item in _transactions(household)
            ],
            'summary': _summary(household),
        }
        change_id = (
            SyncChange.objects.filter(household=household).aggregate(max_id=Max('id'))[
                'max_id'
            ]
            or 0
        )
        body['cursor'] = encode_cursor(change_id, household.uuid)
        return Response(body)
