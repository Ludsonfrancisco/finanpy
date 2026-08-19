from decimal import Decimal

from cards.models import CreditCard, CreditCardExpense, CreditCardInvoice


def serialize_credit_card(card: CreditCard, metrics: dict | None = None) -> dict:
    available_limit = metrics['available_limit'] if metrics else card.limit
    unpaid_total = metrics['unpaid_expenses_total'] if metrics else Decimal('0.00')
    current_invoice_total = (
        metrics['current_invoice_total'] if metrics else Decimal('0.00')
    )
    limit_usage_percent = metrics['limit_usage_percent'] if metrics else 0.0

    return {
        'id': card.pk,
        'name': card.name,
        'limit': f'{card.limit:.2f}',
        'available_limit': f'{available_limit:.2f}',
        'unpaid_expenses_total': f'{unpaid_total:.2f}',
        'current_invoice_total': f'{current_invoice_total:.2f}',
        'limit_usage_percent': limit_usage_percent,
        'closing_day': card.closing_day,
        'due_day': card.due_day,
        'color': card.color,
        'brand': card.brand,
        'brand_display': card.get_brand_display(),
        'last_digits': card.last_digits,
        'is_active': card.is_active,
        'financial_owner_id': card.financial_owner_id,
        'financial_owner_type': card.financial_owner.type,
        'financial_owner_name': card.financial_owner.name,
    }


def serialize_card_expense(expense: CreditCardExpense) -> dict:
    return {
        'id': expense.pk,
        'card_id': expense.credit_card_id,
        'card_name': expense.credit_card.name,
        'invoice_id': expense.invoice_id,
        'description': expense.description,
        'amount': f'{expense.amount:.2f}',
        'date': expense.date.isoformat(),
        'category_id': expense.category_id,
        'category_name': expense.category.name if expense.category else 'Geral',
        'financial_owner_id': expense.financial_owner_id,
        'financial_owner_type': expense.financial_owner.type,
        'financial_owner_name': expense.financial_owner.name,
        'installments_count': expense.installments_count,
        'installment_number': expense.installment_number,
        'installment_group_id': str(expense.installment_group_id),
    }


def serialize_card_invoice(
    invoice: CreditCardInvoice, include_expenses: bool = True
) -> dict:
    data = {
        'id': invoice.pk,
        'card_id': invoice.credit_card_id,
        'card_name': invoice.credit_card.name,
        'month': invoice.month,
        'year': invoice.year,
        'closing_date': invoice.closing_date.isoformat(),
        'due_date': invoice.due_date.isoformat(),
        'status': invoice.status,
        'status_display': invoice.get_status_display(),
        'total_amount': f'{invoice.total_amount:.2f}',
        'paid_amount': f'{invoice.paid_amount:.2f}',
        'paid_at': invoice.paid_at.isoformat() if invoice.paid_at else None,
        'payment_account_id': invoice.payment_account_id,
        'payment_account_name': invoice.payment_account.name
        if invoice.payment_account
        else None,
        'expenses_count': invoice.expenses.count(),
    }
    if include_expenses:
        data['expenses'] = [
            serialize_card_expense(exp)
            for exp in invoice.expenses.select_related(
                'category', 'financial_owner', 'credit_card'
            ).order_by('-date', '-created_at')
        ]
    return data
