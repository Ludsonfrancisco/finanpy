from decimal import Decimal

from sync.registry import serialize_entity


def serialize_household(household):
    return {
        'uuid': str(household.uuid),
        'name': household.name,
        'created_at': household.created_at.isoformat(),
        'updated_at': household.updated_at.isoformat(),
    }


def serialize_owner(owner):
    return {
        'uuid': str(owner.uuid),
        'type': owner.type,
        'name': owner.name,
    }


def serialize_summary(*, total_balance, monthly_income, monthly_expenses):
    precision = Decimal('0.01')
    return {
        'total_balance': str(total_balance.quantize(precision)),
        'monthly_income': str(monthly_income.quantize(precision)),
        'monthly_expenses': str(monthly_expenses.quantize(precision)),
    }


__all__ = ['serialize_entity', 'serialize_household', 'serialize_owner', 'serialize_summary']
