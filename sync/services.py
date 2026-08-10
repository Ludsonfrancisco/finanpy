from copy import deepcopy
from dataclasses import dataclass
from typing import TypeAlias
from uuid import UUID

from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner
from sync.context import capture_sync_context
from sync.exceptions import IdempotencyConflict
from sync.hashes import request_hash
from sync.models import IdempotentOperation
from sync.registry import serialize_entity
from transactions.models import Transaction

OperationResult: TypeAlias = dict[str, object]


@dataclass(frozen=True)
class EntitySpec:
    model: type
    scalar_fields: frozenset[str]
    relation_fields: dict[str, tuple[str, type]]


ENTITY_SPECS = {
    'account': EntitySpec(
        model=Account,
        scalar_fields=frozenset({'name', 'type', 'initial_balance', 'currency'}),
        relation_fields={
            'financial_owner_uuid': ('financial_owner', FinancialOwner),
        },
    ),
    'category': EntitySpec(
        model=Category,
        scalar_fields=frozenset({'name', 'type', 'color', 'icon'}),
        relation_fields={},
    ),
    'transaction': EntitySpec(
        model=Transaction,
        scalar_fields=frozenset({'description', 'amount', 'date', 'type'}),
        relation_fields={
            'financial_owner_uuid': ('financial_owner', FinancialOwner),
            'account_uuid': ('account', Account),
            'category_uuid': ('category', Category),
        },
    ),
}

REQUIRED_OPERATION_FIELDS = frozenset(
    {
        'operation_id',
        'entity',
        'action',
        'entity_uuid',
        'expected_version',
        'data',
    }
)
VALID_ACTIONS = frozenset({'create', 'update', 'delete'})


def _field_error(message='Invalid value.'):
    return [message]


def _invalid(fields) -> OperationResult:
    return {
        'status': 'invalid',
        'code': 'validation_error',
        'fields': fields,
    }


def _uuid_collision() -> OperationResult:
    return _invalid({'entity_uuid': _field_error()})


def _uuid(value):
    if isinstance(value, UUID):
        return value
    if not isinstance(value, str):
        raise ValueError
    return UUID(value)


def _validate_operation(operation):
    if not isinstance(operation, dict):
        return None, _invalid({'operation': _field_error('Expected an object.')})

    missing = REQUIRED_OPERATION_FIELDS.difference(operation)
    unknown = set(operation).difference(REQUIRED_OPERATION_FIELDS)
    fields = {name: _field_error('This field is required.') for name in sorted(missing)}
    fields.update({name: _field_error('Unknown field.') for name in sorted(unknown)})

    entity = operation.get('entity')
    spec = ENTITY_SPECS.get(entity) if isinstance(entity, str) else None
    if spec is None and 'entity' not in missing:
        fields['entity'] = _field_error()

    action = operation.get('action')
    if (
        (not isinstance(action, str) or action not in VALID_ACTIONS)
        and 'action' not in missing
    ):
        fields['action'] = _field_error()

    try:
        entity_uuid = _uuid(operation.get('entity_uuid'))
    except (TypeError, ValueError, AttributeError):
        entity_uuid = None
        if 'entity_uuid' not in missing:
            fields['entity_uuid'] = _field_error()

    data = operation.get('data')
    if not isinstance(data, dict) and 'data' not in missing:
        fields['data'] = _field_error('Expected an object.')
    elif isinstance(data, dict) and spec is not None:
        allowed_fields = spec.scalar_fields | frozenset(spec.relation_fields)
        for name in sorted(set(data).difference(allowed_fields)):
            fields[name] = _field_error('Unknown field.')
        if action == 'delete' and data:
            fields['data'] = _field_error('Delete data must be empty.')

    expected_version = operation.get('expected_version')
    if action == 'create':
        if expected_version is not None:
            fields['expected_version'] = _field_error('Must be null for create.')
    elif isinstance(action, str) and action in {'update', 'delete'}:
        if (
            isinstance(expected_version, bool)
            or not isinstance(expected_version, int)
            or expected_version < 1
        ):
            fields['expected_version'] = _field_error('Must be a positive integer.')

    if fields:
        return None, _invalid(fields)
    return {
        'spec': spec,
        'action': action,
        'entity_uuid': entity_uuid,
        'expected_version': expected_version,
        'data': data,
    }, None


def _validation_fields(exc):
    if not hasattr(exc, 'error_dict'):
        return {'data': _field_error()}
    relation_names = {
        'uuid': 'entity_uuid',
        'financial_owner': 'financial_owner_uuid',
        'account': 'account_uuid',
        'category': 'category_uuid',
        '__all__': 'data',
    }
    return {
        relation_names.get(name, name): _field_error()
        for name in sorted(exc.error_dict)
    }


def _submitted(operation):
    return {
        'entity_uuid': str(operation['entity_uuid']),
        'expected_version': operation['expected_version'],
        'data': deepcopy(operation['data']),
    }


def _conflict(operation, current, code='version_conflict') -> OperationResult:
    return {
        'status': 'conflict',
        'code': code,
        'submitted': _submitted(operation),
        'current': current,
    }


def _resolve_data(device_session, spec, data):
    resolved = {name: value for name, value in data.items() if name in spec.scalar_fields}
    errors = {}
    for submitted_name, (model_name, model) in spec.relation_fields.items():
        if submitted_name not in data:
            continue
        try:
            relation_uuid = _uuid(data[submitted_name])
        except (TypeError, ValueError, AttributeError):
            errors[submitted_name] = _field_error()
            continue
        related = model.objects.filter(
            household=device_session.household,
            uuid=relation_uuid,
        ).first()
        if related is None:
            errors[submitted_name] = _field_error()
        else:
            resolved[model_name] = related
    return resolved, errors


def _query_current(spec, device_session, entity_uuid):
    queryset = spec.model.objects.select_for_update().filter(
        household=device_session.household,
        uuid=entity_uuid,
    )
    if spec.model is Account:
        queryset = queryset.filter(
            financial_owner__household=device_session.household,
        ).select_related('household', 'financial_owner')
    elif spec.model is Category:
        queryset = queryset.select_related('household')
    else:
        queryset = queryset.filter(
            financial_owner__household=device_session.household,
            account__household=device_session.household,
            category__household=device_session.household,
        ).select_related('household', 'financial_owner', 'account', 'category')
    return queryset.first()


def _create(device_session, operation, validated) -> OperationResult:
    spec = validated['spec']
    if spec.model.objects.filter(
        household=device_session.household,
        uuid=validated['entity_uuid'],
    ).exists():
        return _uuid_collision()

    values, errors = _resolve_data(device_session, spec, validated['data'])
    if errors:
        return _invalid(errors)
    instance = spec.model(
        uuid=validated['entity_uuid'],
        user=device_session.user,
        household=device_session.household,
        sync_version=1,
        **values,
    )
    instance.full_clean()
    with capture_sync_context(
        device_session=device_session,
        operation_id=_uuid(operation['operation_id']),
    ):
        instance.save(force_insert=True)
    return {'status': 'applied', 'entity': serialize_entity(instance)}


def _resource_is_in_use(instance):
    if isinstance(instance, (Account, Category)):
        return instance.transactions.exists()
    return False


def _update_or_delete(device_session, operation, validated) -> OperationResult:
    spec = validated['spec']
    instance = _query_current(spec, device_session, validated['entity_uuid'])
    if instance is None:
        return _invalid({'entity_uuid': _field_error()})

    current = serialize_entity(instance)
    if instance.sync_version != validated['expected_version']:
        return _conflict(operation, current)

    if validated['action'] == 'delete':
        if _resource_is_in_use(instance):
            return _conflict(operation, current, code='resource_in_use')
        deleted = {
            'uuid': str(instance.uuid),
            'version': instance.sync_version + 1,
            'deleted': True,
        }
        with capture_sync_context(
            device_session=device_session,
            operation_id=_uuid(operation['operation_id']),
        ):
            instance.delete()
        return {'status': 'applied', 'entity': deleted}

    values, errors = _resolve_data(device_session, spec, validated['data'])
    if errors:
        return _invalid(errors)
    for name, value in values.items():
        setattr(instance, name, value)
    instance.full_clean()
    with capture_sync_context(
        device_session=device_session,
        operation_id=_uuid(operation['operation_id']),
    ):
        instance.save()
    return {'status': 'applied', 'entity': serialize_entity(instance)}


def _apply_new(device_session, operation) -> OperationResult:
    validated, error = _validate_operation(operation)
    if error is not None:
        return error
    try:
        with transaction.atomic():
            if validated['action'] == 'create':
                return _create(device_session, operation, validated)
            return _update_or_delete(device_session, operation, validated)
    except ValidationError as exc:
        if validated['action'] == 'create' and 'uuid' in getattr(exc, 'error_dict', {}):
            return _uuid_collision()
        return _invalid(_validation_fields(exc))
    except IntegrityError:
        if validated['action'] == 'create':
            return _uuid_collision()
        return _invalid({'data': _field_error()})


def _stored_result(result):
    stored = deepcopy(result)
    if stored.get('status') == 'applied':
        stored['status'] = 'duplicate'
    return stored


def _existing_result(stored, digest):
    if stored.request_hash != digest:
        raise IdempotencyConflict
    return deepcopy(stored.response_body)


def apply_operation(device_session, operation) -> OperationResult:
    if not isinstance(operation, dict):
        return _invalid({'operation': _field_error('Expected an object.')})
    try:
        operation_id = _uuid(operation.get('operation_id'))
    except (TypeError, ValueError, AttributeError):
        return _invalid({'operation_id': _field_error()})

    digest = request_hash(operation)
    with transaction.atomic():
        stored = (
            IdempotentOperation.objects.select_for_update()
            .filter(
                device_session=device_session,
                operation_id=operation_id,
            )
            .first()
        )
        if stored is not None:
            return _existing_result(stored, digest)

        try:
            with transaction.atomic():
                stored = IdempotentOperation.objects.create(
                    device_session=device_session,
                    operation_id=operation_id,
                    request_hash=digest,
                    status_code=200,
                    response_body={},
                )
        except IntegrityError:
            stored = IdempotentOperation.objects.select_for_update().get(
                device_session=device_session,
                operation_id=operation_id,
            )
            return _existing_result(stored, digest)

        result = _apply_new(device_session, operation)
        stored.response_body = _stored_result(result)
        stored.save(update_fields=['response_body', 'updated_at'])
        return result
