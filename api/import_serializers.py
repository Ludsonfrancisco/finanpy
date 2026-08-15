from rest_framework import serializers

from imports.services import MAX_RECORD_PAGE_LIMIT


class OfxPreviewSerializer(serializers.Serializer):
    file = serializers.FileField(write_only=True)


class ImportPageSerializer(serializers.Serializer):
    after = serializers.IntegerField(required=False, min_value=0)
    limit = serializers.IntegerField(
        required=False, min_value=1, max_value=MAX_RECORD_PAGE_LIMIT
    )


class BindImportAccountSerializer(serializers.Serializer):
    account_uuid = serializers.UUIDField()


class EmptySerializer(serializers.Serializer):
    pass


def serialize_import_record(record):
    return {
        'uuid': str(record.uuid),
        'posted_on': record.posted_on.isoformat(),
        'description': record.description,
        'amount': _magnitude(record.amount),
        'transaction_type': record.transaction_type,
        'outcome': record.outcome,
    }


def _magnitude(amount):
    return f'{abs(amount):.2f}'


def serialize_import_batch(batch, page):
    return {
        'uuid': str(batch.uuid),
        'status': batch.status,
        'provider': batch.provider,
        'product_type': batch.product_type,
        'statement_start': batch.statement_start.isoformat(),
        'statement_end': batch.statement_end.isoformat(),
        'expires_at': batch.expires_at.isoformat().replace('+00:00', 'Z'),
        'account_uuid': str(batch.account.uuid) if batch.account_id else None,
        'financial_owner_uuid': (
            str(batch.financial_owner.uuid) if batch.financial_owner_id else None
        ),
        'created_count': batch.created_count,
        'duplicate_count': batch.duplicate_count,
        'warning_count': batch.warning_count,
        'record_count': page['record_count'],
        'pending_count': page['pending_count'],
        'income_total': _magnitude(page['income_total']),
        'expense_total': _magnitude(page['expense_total']),
        'is_repeated_file': batch.is_repeated_file,
        'records': [serialize_import_record(record) for record in page['records']],
        'next_cursor': page['next_cursor'],
    }
