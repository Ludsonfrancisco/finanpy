import datetime
from decimal import Decimal

from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import Account
from bills.models import BillInstance, RecurringBill
from bills.services import (
    ensure_monthly_bill_instances,
    get_bills_dashboard_metrics,
    pay_bill_instance,
    reopen_bill_instance,
)
from categories.models import Category
from households.models import FinancialOwner
from households.services import get_financial_owner

from .bills_serializers import (
    serialize_bill_instance,
    serialize_bills_metrics,
    serialize_recurring_bill,
)


class BillsResourceView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        household = request.auth.household
        today = timezone.localdate()

        try:
            month = int(request.GET.get('month', today.month))
            year = int(request.GET.get('year', today.year))
        except (ValueError, TypeError):
            month = today.month
            year = today.year

        owner_filter = request.GET.get('owner', 'household')
        financial_owner = None
        if owner_filter in ('self', 'spouse', 'shared'):
            financial_owner = FinancialOwner.objects.filter(
                household=household,
                type=owner_filter,
            ).first()

        instances = ensure_monthly_bill_instances(household, month, year)
        if financial_owner:
            instances = instances.filter(financial_owner=financial_owner)

        recurring_bills = RecurringBill.objects.filter(
            household=household,
        ).select_related('category', 'default_account', 'financial_owner')
        if financial_owner:
            recurring_bills = recurring_bills.filter(financial_owner=financial_owner)

        metrics = get_bills_dashboard_metrics(household, month, year, financial_owner)

        return Response({
            'instances': [serialize_bill_instance(i) for i in instances],
            'recurring_bills': [serialize_recurring_bill(b) for b in recurring_bills],
            'metrics': serialize_bills_metrics(metrics),
        })

    def post(self, request):
        household = request.auth.household
        data = request.data

        name = data.get('name', '').strip()
        if not name:
            return Response({'error': 'Nome é obrigatório.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            amount = Decimal(str(data.get('amount', '0.00')).replace(',', '.'))
            due_day = int(data.get('due_day', 10))
            if not (1 <= due_day <= 31):
                raise ValueError()
        except Exception:
            return Response({'error': 'Valor ou dia de vencimento inválido.'}, status=status.HTTP_400_BAD_REQUEST)

        bill_type = data.get('type', RecurringBill.EXPENSE)
        category_id = data.get('category_id')
        category = None
        if category_id:
            category = Category.objects.filter(household=household, pk=category_id).first()
        if not category:
            category = Category.objects.filter(household=household).first()

        default_account_id = data.get('default_account_id')
        default_account = None
        if default_account_id:
            default_account = Account.objects.filter(household=household, pk=default_account_id).first()

        owner_type = data.get('financial_owner_type', FinancialOwner.SHARED)
        financial_owner = FinancialOwner.objects.filter(household=household, type=owner_type).first()
        if not financial_owner:
            financial_owner = get_financial_owner(household, FinancialOwner.SHARED)

        bill = RecurringBill.objects.create(
            household=household,
            user=request.user,
            financial_owner=financial_owner,
            name=name,
            amount=amount,
            due_day=due_day,
            type=bill_type,
            category=category,
            default_account=default_account,
            is_active=bool(data.get('is_active', True)),
            notes=data.get('notes', ''),
        )

        ensure_monthly_bill_instances(household)
        return Response(serialize_recurring_bill(bill), status=status.HTTP_201_CREATED)


class BillDetailResourceView(APIView):
    permission_classes = [IsAuthenticated]

    def put(self, request, pk):
        return self.patch(request, pk)

    def patch(self, request, pk):
        household = request.auth.household
        bill = get_object_or_404(RecurringBill, pk=pk, household=household)
        data = request.data

        if 'name' in data:
            bill.name = data['name'].strip()
        if 'amount' in data:
            bill.amount = Decimal(str(data['amount']).replace(',', '.'))
        if 'due_day' in data:
            bill.due_day = int(data['due_day'])
        if 'type' in data:
            bill.type = data['type']
        if 'category_id' in data:
            bill.category = Category.objects.filter(household=household, pk=data['category_id']).first() or bill.category
        if 'default_account_id' in data:
            bill.default_account = Account.objects.filter(household=household, pk=data['default_account_id']).first()
        if 'financial_owner_type' in data:
            bill.financial_owner = FinancialOwner.objects.filter(household=household, type=data['financial_owner_type']).first() or bill.financial_owner
        if 'is_active' in data:
            bill.is_active = bool(data['is_active'])
        if 'notes' in data:
            bill.notes = data['notes']

        bill.save()
        return Response(serialize_recurring_bill(bill))

    def delete(self, request, pk):
        household = request.auth.household
        bill = get_object_or_404(RecurringBill, pk=pk, household=household)
        bill.delete()
        return Response({'deleted': True}, status=status.HTTP_200_OK)


class PayBillResourceView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        household = request.auth.household
        instance = get_object_or_404(BillInstance, pk=pk, household=household)
        data = request.data

        account_id = data.get('account_id')
        account = get_object_or_404(Account, pk=account_id, household=household)

        paid_amount_str = data.get('paid_amount', str(instance.amount))
        paid_date_str = data.get('paid_date', timezone.localdate().isoformat())

        try:
            paid_amount = Decimal(str(paid_amount_str).replace(',', '.'))
            paid_date = datetime.date.fromisoformat(str(paid_date_str)[:10])
        except Exception:
            return Response({'error': 'Valor ou data de pagamento inválido.'}, status=status.HTTP_400_BAD_REQUEST)

        tx = pay_bill_instance(instance, request.user, account, paid_amount, paid_date)
        instance.refresh_from_db()
        return Response(serialize_bill_instance(instance))


class ReopenBillResourceView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        household = request.auth.household
        instance = get_object_or_404(BillInstance, pk=pk, household=household)
        reopen_bill_instance(instance)
        instance.refresh_from_db()
        return Response(serialize_bill_instance(instance))


class BillsMetricsResourceView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        household = request.auth.household
        today = timezone.localdate()

        try:
            month = int(request.GET.get('month', today.month))
            year = int(request.GET.get('year', today.year))
        except (ValueError, TypeError):
            month = today.month
            year = today.year

        owner_filter = request.GET.get('owner', 'household')
        financial_owner = None
        if owner_filter in ('self', 'spouse', 'shared'):
            financial_owner = FinancialOwner.objects.filter(household=household, type=owner_filter).first()

        metrics = get_bills_dashboard_metrics(household, month, year, financial_owner)
        return Response(serialize_bills_metrics(metrics))
