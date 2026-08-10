from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler

from .diagnostics import emit_exception_diagnostic


def internal_error_payload(request_id):
    return {
        'error': {
            'code': 'internal_error',
            'message': 'Erro interno do servidor.',
            'fields': None,
        },
        'request_id': request_id,
    }


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    request = context.get('request')
    request_id = getattr(request, 'request_id', None)
    if response is None:
        emit_exception_diagnostic(request, exc, 'caught_api_exception')
        return Response(
            internal_error_payload(request_id),
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )
    detail = response.data
    code = getattr(exc, 'default_code', 'api_error')
    if isinstance(detail, dict) and 'detail' in detail:
        message = str(detail['detail'])
        fields = None
    else:
        message = 'Verifique os campos enviados.'
        fields = detail
    response.data = {
        'error': {'code': str(code), 'message': message, 'fields': fields},
        'request_id': request_id,
    }
    return response
