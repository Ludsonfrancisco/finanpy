from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.response import Response
from rest_framework.views import APIView

from sync.cursors import InvalidCursor, decode_cursor, encode_cursor
from sync.exceptions import IdempotencyConflict
from sync.models import SyncChange
from sync.services import apply_operation


class InvalidBatch(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'O corpo deve conter uma lista de operações.'
    default_code = 'invalid_batch'


class EmptyBatch(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Envie pelo menos uma operação.'
    default_code = 'min_1_operation'


class OversizedBatch(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Envie no máximo 100 operações.'
    default_code = 'max_100_operations'


class InvalidSyncCursor(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Cursor inválido.'
    default_code = 'invalid_cursor'


def _serialize_change(change):
    return {
        'entity_type': change.entity_type,
        'entity_uuid': str(change.entity_uuid),
        'entity_version': change.entity_version,
        'operation': change.operation,
        'payload': change.payload,
    }


class SyncPullView(APIView):
    def get(self, request):
        household = request.auth.household
        cursor = request.query_params.get('cursor')
        if cursor is None:
            cursor = encode_cursor(0, household.uuid)

        try:
            change_id = decode_cursor(cursor, household.uuid)
        except InvalidCursor as exc:
            raise InvalidSyncCursor from exc

        try:
            limit = int(request.query_params.get('limit', 100))
        except (TypeError, ValueError):
            limit = 100
        limit = max(0, min(limit, 100))
        changes = list(
            SyncChange.objects.filter(household=household, id__gt=change_id)
            .order_by('id')[:limit]
        )
        if changes:
            cursor = encode_cursor(changes[-1].id, household.uuid)
        return Response(
            {'changes': [_serialize_change(change) for change in changes], 'cursor': cursor}
        )


class SyncPushView(APIView):
    def post(self, request):
        if not isinstance(request.data, dict):
            raise InvalidBatch
        operations = request.data.get('operations')
        if not isinstance(operations, list):
            raise InvalidBatch
        if not operations:
            raise EmptyBatch
        if len(operations) > 100:
            raise OversizedBatch

        results = []
        for operation in operations:
            try:
                result = apply_operation(request.auth, operation)
            except IdempotencyConflict:
                result = {
                    'status': 'conflict',
                    'code': 'idempotency_conflict',
                }
            results.append(result)
        return Response({'results': results})
