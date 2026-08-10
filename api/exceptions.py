from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    request = context.get('request')
    request_id = getattr(request, 'request_id', None)
    if response is None:
        return Response(
            {
                'error': {
                    'code': 'internal_error',
                    'message': 'Erro interno do servidor.',
                    'fields': None,
                },
                'request_id': request_id,
            },
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
