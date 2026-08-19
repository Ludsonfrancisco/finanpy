from decimal import Decimal


def _fmt(val):
    try:
        return f'{Decimal(str(val)):.2f}'
    except Exception:
        return '0.00'


def serialize_bill_instance(instance):
    return {
        'id': instance.id,
        'bill_id': instance.bill_id,
        'name': instance.bill.name,
        'month': instance.month,
        'year': instance.year,
        'due_date': instance.due_date.isoformat(),
        'due_day': instance.bill.due_day,
        'amount': _fmt(instance.amount),
        'status': instance.status,
        'paid_at': instance.paid_at.isoformat() if instance.paid_at else None,
        'type': instance.bill.type,
        'category_name': instance.bill.category.name if instance.bill.category else 'Geral',
        'category_id': instance.bill.category_id,
        'account_name': instance.account.name if instance.account else None,
        'account_id': instance.account_id,
        'default_account_id': instance.bill.default_account_id,
        'financial_owner_type': instance.financial_owner.type if instance.financial_owner else 'shared',
        'financial_owner_name': instance.financial_owner.name if instance.financial_owner else 'Conjunto',
    }


def serialize_recurring_bill(bill):
    return {
        'id': bill.id,
        'name': bill.name,
        'amount': _fmt(bill.amount),
        'due_day': bill.due_day,
        'type': bill.type,
        'category_id': bill.category_id,
        'category_name': bill.category.name if bill.category else 'Geral',
        'default_account_id': bill.default_account_id,
        'default_account_name': bill.default_account.name if bill.default_account else None,
        'financial_owner_type': bill.financial_owner.type if bill.financial_owner else 'shared',
        'financial_owner_name': bill.financial_owner.name if bill.financial_owner else 'Conjunto',
        'is_active': bill.is_active,
        'notes': bill.notes or '',
    }


def serialize_bills_metrics(metrics):
    return {
        'month': metrics['month'],
        'year': metrics['year'],
        'pending_expenses_total': _fmt(metrics['pending_expenses_total']),
        'paid_expenses_total': _fmt(metrics['paid_expenses_total']),
        'total_committed': _fmt(metrics['total_committed']),
        'overdue_count': metrics['overdue_count'],
        'due_today_count': metrics['due_today_count'],
        'total_account_balance': _fmt(metrics['total_account_balance']),
        'free_cash_balance': _fmt(metrics['free_cash_balance']),
    }
