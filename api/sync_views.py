from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.response import Response
from rest_framework.views import APIView

from sync.exceptions import IdempotencyConflict
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
