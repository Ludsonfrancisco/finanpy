from rest_framework.views import exception_handler


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    request = context.get('request')
    request_id = getattr(request, 'request_id', None)
    if response is None:
        return response
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
