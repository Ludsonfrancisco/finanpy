from datetime import date
from decimal import Decimal

from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import Account
from api.resources import _household
from cards.models import CreditCard, CreditCardExpense, CreditCardInvoice
from cards.services import (
    calculate_card_metrics,
    create_card_expense,
    pay_card_invoice,
    reopen_card_invoice,
    resolve_or_create_invoice,
)
from categories.models import Category
from households.models import FinancialOwner

from .cards_serializers import (
    serialize_card_expense,
    serialize_card_invoice,
    serialize_credit_card,
)


class CardsResourceView(APIView):
    def get(self, request):
        household = _household(request)
        now = timezone.localdate()

        try:
            month = int(request.query_params.get('month', now.month))
            year = int(request.query_params.get('year', now.year))
        except (ValueError, TypeError):
            month = now.month
            year = now.year

        owner_type = request.query_params.get('owner')

        cards_qs = (
            CreditCard.objects.filter(household=household, is_active=True)
            .select_related('financial_owner')
            .order_by('name')
        )
        if owner_type in ['self', 'spouse', 'shared']:
            cards_qs = cards_qs.filter(financial_owner__type=owner_type)

        cards = list(cards_qs)
        cards_serialized = []
        total_limit = Decimal('0.00')
        total_used = Decimal('0.00')
        total_current_invoices = Decimal('0.00')

        for card in cards:
            metrics = calculate_card_metrics(card, month, year)
            cards_serialized.append(serialize_credit_card(card, metrics))
            total_limit += card.limit
            total_used += metrics['unpaid_expenses_total']
            total_current_invoices += metrics['current_invoice_total']

        total_available = max(Decimal('0.00'), total_limit - total_used)

        return Response(
            {
                'cards': cards_serialized,
                'summary': {
                    'month': month,
                    'year': year,
                    'total_limit': f'{total_limit:.2f}',
                    'total_used': f'{total_used:.2f}',
                    'total_available': f'{total_available:.2f}',
                    'total_current_invoices': f'{total_current_invoices:.2f}',
                    'limit_usage_percent': min(
                        100.0, float((total_used / total_limit) * 100)
                    )
                    if total_limit > 0
                    else 0.0,
                },
            }
        )

    def post(self, request):
        household = _household(request)
        data = request.data

        name = data.get('name', '').strip()
        if not name:
            return Response(
                {
                    'error': {
                        'code': 'missing_name',
                        'message': 'Nome do cartão é obrigatório.',
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            limit = Decimal(str(data.get('limit', '0')))
            if limit <= 0:
                raise ValueError
        except Exception:
            return Response(
                {
                    'error': {
                        'code': 'invalid_limit',
                        'message': 'Limite deve ser um valor positivo.',
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        closing_day = int(data.get('closing_day', 10))
        due_day = int(data.get('due_day', 17))
        color = data.get('color', '#2F756A')
        brand = data.get('brand', 'visa')
        last_digits = data.get('last_digits', '')[:4]
        owner_type = data.get('financial_owner_type', 'shared')

        owner = FinancialOwner.objects.filter(
            household=household, type=owner_type
        ).first()
        if not owner:
            owner = FinancialOwner.objects.filter(
                household=household, type='shared'
            ).first()

        card = CreditCard.objects.create(
            household=household,
            user=request.user,
            financial_owner=owner,
            name=name,
            limit=limit,
            closing_day=closing_day,
            due_day=due_day,
            color=color,
            brand=brand,
            last_digits=last_digits,
            is_active=True,
        )

        metrics = calculate_card_metrics(card)
        return Response(
            serialize_credit_card(card, metrics), status=status.HTTP_201_CREATED
        )


class CardDetailResourceView(APIView):
    def get(self, request, pk):
        household = _household(request)
        card = get_object_or_404(CreditCard, pk=pk, household=household)
        now = timezone.localdate()

        try:
            month = int(request.query_params.get('month', now.month))
            year = int(request.query_params.get('year', now.year))
        except (ValueError, TypeError):
            month = now.month
            year = now.year

        selected_invoice = resolve_or_create_invoice(card, month, year)
        metrics = calculate_card_metrics(card, month, year)

        # Faturas futuras
        future_invoices = []
        for i in range(1, 7):
            f_month = ((month - 1 + i) % 12) + 1
            f_year = year + ((month - 1 + i) // 12)
            f_inv = resolve_or_create_invoice(card, f_month, f_year)
            if f_inv.expenses.exists():
                future_invoices.append(
                    serialize_card_invoice(f_inv, include_expenses=False)
                )

        return Response(
            {
                'card': serialize_credit_card(card, metrics),
                'selected_invoice': serialize_card_invoice(
                    selected_invoice, include_expenses=True
                ),
                'future_invoices': future_invoices,
                'metrics': {
                    'available_limit': f'{metrics["available_limit"]:.2f}',
                    'unpaid_expenses_total': f'{metrics["unpaid_expenses_total"]:.2f}',
                    'current_invoice_total': f'{metrics["current_invoice_total"]:.2f}',
                    'future_invoices_total': f'{metrics["future_invoices_total"]:.2f}',
                    'limit_usage_percent': metrics['limit_usage_percent'],
                },
            }
        )

    def put(self, request, pk):
        return self.patch(request, pk)

    def patch(self, request, pk):
        household = _household(request)
        card = get_object_or_404(CreditCard, pk=pk, household=household)
        data = request.data

        if 'name' in data:
            card.name = data['name'].strip()
        if 'limit' in data:
            card.limit = Decimal(str(data['limit']))
        if 'closing_day' in data:
            card.closing_day = int(data['closing_day'])
        if 'due_day' in data:
            card.due_day = int(data['due_day'])
        if 'color' in data:
            card.color = data['color']
        if 'brand' in data:
            card.brand = data['brand']
        if 'last_digits' in data:
            card.last_digits = data['last_digits'][:4]
        if 'is_active' in data:
            card.is_active = bool(data['is_active'])

        if 'financial_owner_type' in data:
            owner = FinancialOwner.objects.filter(
                household=household, type=data['financial_owner_type']
            ).first()
            if owner:
                card.financial_owner = owner

        card.save()
        metrics = calculate_card_metrics(card)
        return Response(serialize_credit_card(card, metrics))

    def delete(self, request, pk):
        household = _household(request)
        card = get_object_or_404(CreditCard, pk=pk, household=household)
        card.is_active = False
        card.save(update_fields=['is_active'])
        return Response({'status': 'archived', 'id': card.pk})


class CardExpenseResourceView(APIView):
    def post(self, request):
        household = _household(request)
        data = request.data

        card_id = data.get('card_id')
        card = get_object_or_404(CreditCard, pk=card_id, household=household)

        description = data.get('description', '').strip()
        if not description:
            return Response(
                {
                    'error': {
                        'code': 'missing_description',
                        'message': 'Descrição é obrigatória.',
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            amount = Decimal(str(data.get('amount', '0')))
            if amount <= 0:
                raise ValueError
        except Exception:
            return Response(
                {'error': {'code': 'invalid_amount', 'message': 'Valor inválido.'}},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            purchase_date = date.fromisoformat(
                data.get('date', timezone.localdate().isoformat())
            )
        except Exception:
            purchase_date = timezone.localdate()

        category_id = data.get('category_id')
        category = Category.objects.filter(household=household, pk=category_id).first()
        if not category:
            category, _ = Category.objects.get_or_create(
                household=household,
                user=request.user,
                name='Outros',
                type='expense',
            )

        installments_count = int(data.get('installments_count', 1))
        owner_type = data.get('financial_owner_type', card.financial_owner.type)
        owner = (
            FinancialOwner.objects.filter(household=household, type=owner_type).first()
            or card.financial_owner
        )

        expenses = create_card_expense(
            credit_card=card,
            description=description,
            total_amount=amount,
            purchase_date=purchase_date,
            category=category,
            installments_count=installments_count,
            financial_owner=owner,
            user=request.user,
        )

        return Response(
            {
                'created_count': len(expenses),
                'expenses': [serialize_card_expense(e) for e in expenses],
            },
            status=status.HTTP_201_CREATED,
        )


class CardExpenseDetailResourceView(APIView):
    def delete(self, request, pk):
        household = _household(request)
        expense = get_object_or_404(CreditCardExpense, pk=pk, household=household)
        delete_all = request.query_params.get('delete_all') == 'true'

        if delete_all and expense.installments_count > 1:
            count, _ = CreditCardExpense.objects.filter(
                installment_group_id=expense.installment_group_id,
                household=household,
            ).delete()
            return Response({'deleted_count': count})
        else:
            expense.delete()
            return Response({'deleted_count': 1})


class PayCardInvoiceResourceView(APIView):
    def post(self, request, pk):
        household = _household(request)
        invoice = get_object_or_404(CreditCardInvoice, pk=pk, household=household)
        data = request.data

        account_id = data.get('account_id')
        account = get_object_or_404(Account, pk=account_id, household=household)

        try:
            paid_amount = Decimal(str(data.get('paid_amount', invoice.total_amount)))
        except Exception:
            paid_amount = invoice.total_amount

        try:
            payment_date = date.fromisoformat(
                data.get('payment_date', timezone.localdate().isoformat())
            )
        except Exception:
            payment_date = timezone.localdate()

        invoice = pay_card_invoice(
            invoice=invoice,
            payment_account=account,
            paid_amount=paid_amount,
            payment_date=payment_date,
        )

        return Response(serialize_card_invoice(invoice, include_expenses=True))


class ReopenCardInvoiceResourceView(APIView):
    def post(self, request, pk):
        household = _household(request)
        invoice = get_object_or_404(CreditCardInvoice, pk=pk, household=household)
        invoice = reopen_card_invoice(invoice)
        return Response(serialize_card_invoice(invoice, include_expenses=True))
