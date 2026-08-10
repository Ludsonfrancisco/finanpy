import logging
import time
import uuid

from django.utils import timezone

from .logging import serialize_access_event

logger = logging.getLogger('lar_finance.api')


def _request_id(request):
    supplied = request.headers.get('X-Request-ID')
    if supplied:
        try:
            uuid.UUID(supplied)
        except (AttributeError, TypeError, ValueError):
            pass
        else:
            return supplied
    return str(uuid.uuid4())


def _route_name(request):
    match = request.resolver_match
    if match is None:
        return 'unmatched'
    return match.view_name or match.route or 'unmatched'


def _error_code(response):
    data = getattr(response, 'data', None)
    if not isinstance(data, dict):
        return None
    error = data.get('error')
    if not isinstance(error, dict):
        return None
    code = error.get('code')
    return str(code) if code is not None else None


class ApiObservabilityMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request.request_id = _request_id(request)
        started_at = time.perf_counter()
        response = self.get_response(request)
        duration_ms = round((time.perf_counter() - started_at) * 1000, 3)
        response['X-Request-ID'] = request.request_id

        if request.path.startswith('/api/v1/'):
            user = getattr(request, 'user', None)
            authenticated = bool(user and user.is_authenticated)
            device = getattr(request, 'auth', None) if authenticated else None
            event = {
                'timestamp': timezone.now().isoformat(),
                'level': 'INFO',
                'service': 'lar-finance-api',
                'request_id': request.request_id,
                'method': request.method,
                'route': _route_name(request),
                'status': response.status_code,
                'duration_ms': duration_ms,
                'authenticated': authenticated,
                'device_uuid': str(device.uuid) if device is not None else None,
                'error_code': _error_code(response),
            }
            logger.info(serialize_access_event(event))

        return response
