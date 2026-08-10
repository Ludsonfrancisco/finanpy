import json
import logging
import time
import uuid

from django.http import JsonResponse
from django.utils import timezone

from .diagnostics import emit_exception_diagnostic
from .exceptions import internal_error_payload
from .logging import serialize_access_event
from .models import DeviceSession

logger = logging.getLogger('lar_finance.api')


def _is_error_envelope_json(response):
    content_type = response.get('Content-Type', '').partition(';')[0]
    data = getattr(response, 'data', None)
    if data is None and content_type == 'application/json':
        try:
            data = json.loads(response.content)
        except (AttributeError, TypeError, ValueError):
            return False
    if content_type != 'application/json' or not isinstance(data, dict):
        return False
    error = data.get('error')
    return (
        set(data) == {'error', 'request_id'}
        and isinstance(error, dict)
        and set(error) == {'code', 'message', 'fields'}
    )


def _request_id(request):
    existing = getattr(request, 'request_id', None)
    if existing is not None:
        return existing
    supplied = request.headers.get('X-Request-ID')
    if supplied:
        try:
            uuid.UUID(supplied)
        except (AttributeError, TypeError, ValueError):
            pass
        else:
            return supplied
    return str(uuid.uuid4())


class RequestIdMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request.request_id = _request_id(request)
        response = self.get_response(request)
        if request.path.startswith('/api/v1/') and response.status_code >= 500:
            exc = getattr(request, '_api_unhandled_exception', None)
            if exc is not None:
                emit_exception_diagnostic(request, exc, 'unhandled_api_exception')
            if not _is_error_envelope_json(response):
                response = JsonResponse(
                    internal_error_payload(request.request_id),
                    status=500,
                )
        response['X-Request-ID'] = request.request_id
        return response


def _route_name(request):
    match = request.resolver_match
    if match is None:
        return 'unmatched'
    return match.view_name or match.route or 'unmatched'


def _error_code(response):
    data = getattr(response, 'data', None)
    if not isinstance(data, dict):
        return 'internal_error' if response.status_code >= 500 else None
    error = data.get('error')
    if not isinstance(error, dict):
        return 'internal_error' if response.status_code >= 500 else None
    code = error.get('code')
    if code is not None:
        return str(code)
    return 'internal_error' if response.status_code >= 500 else None


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
            device = getattr(request, 'auth', None)
            authenticated = isinstance(device, DeviceSession)
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
                'device_uuid': str(device.uuid) if authenticated else None,
                'error_code': _error_code(response),
            }
            logger.info(serialize_access_event(event))

        return response
