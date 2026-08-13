from rest_framework import serializers


class OfxPreviewSerializer(serializers.Serializer):
    file = serializers.FileField(write_only=True)


class BindImportAccountSerializer(serializers.Serializer):
    account_uuid = serializers.UUIDField()


class EmptySerializer(serializers.Serializer):
    pass


def serialize_import_batch(batch):
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
        'is_repeated_file': batch.is_repeated_file,
    }
