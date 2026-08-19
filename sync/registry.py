from accounts.models import Account
from categories.models import Category
from transactions.models import Transaction


def _string_value(value):
    if hasattr(value, 'isoformat'):
        return value.isoformat()
    return str(value)


def _base_payload(instance):
    return {
        'uuid': str(instance.uuid),
        'version': instance.sync_version,
        'created_at': _string_value(instance.created_at),
        'updated_at': _string_value(instance.updated_at),
        'household_uuid': str(instance.household.uuid),
    }


def _serialize_account(account):
    return {
        **_base_payload(account),
        'financial_owner_uuid': str(account.financial_owner.uuid),
        'name': account.name,
        'type': account.type,
        'initial_balance': _string_value(account.initial_balance),
        'currency': account.currency,
    }


def _serialize_category(category):
    return {
        **_base_payload(category),
        'name': category.name,
        'type': category.type,
        'color': category.color,
        'icon': category.icon,
        'budget': _string_value(category.budget),
    }


def _serialize_transaction(transaction):
    return {
        **_base_payload(transaction),
        'financial_owner_uuid': str(transaction.financial_owner.uuid),
        'account_uuid': str(transaction.account.uuid),
        'category_uuid': str(transaction.category.uuid),
        'description': transaction.description,
        'amount': _string_value(transaction.amount),
        'date': _string_value(transaction.date),
        'type': transaction.type,
    }


ENTITY_REGISTRY = {
    Account: ('account', _serialize_account),
    Category: ('category', _serialize_category),
    Transaction: ('transaction', _serialize_transaction),
}


def get_entity_type(instance):
    try:
        return ENTITY_REGISTRY[type(instance)][0]
    except KeyError as exc:
        raise ValueError(f'Unregistered sync entity: {type(instance).__name__}') from exc


def serialize_entity(instance):
    try:
        serializer = ENTITY_REGISTRY[type(instance)][1]
    except KeyError as exc:
        raise ValueError(f'Unregistered sync entity: {type(instance).__name__}') from exc
    return serializer(instance)
