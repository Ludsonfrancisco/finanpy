import hashlib
import logging
import sys

from django.core.signals import got_request_exception

diagnostic_logger = logging.getLogger('lar_finance.api.diagnostic')

ALLOWED_EVENT_TYPES = {'caught_api_exception', 'unhandled_api_exception'}


def _exception_type(exc):
    exception_class = type(exc)
    return f'{exception_class.__module__}.{exception_class.__qualname__}'


def _structural_location(exc):
    traceback = exc.__traceback__
    if traceback is None:
        return 'unknown'
    while traceback.tb_next is not None:
        traceback = traceback.tb_next
    code = traceback.tb_frame.f_code
    module = traceback.tb_frame.f_globals.get('__name__', 'unknown')
    return f'{module}:{code.co_qualname}'


def emit_exception_diagnostic(request, exc, event_type):
    if (
        request is None
        or not request.path.startswith('/api/v1/')
        or getattr(request, '_api_diagnostic_emitted', False)
    ):
        return
    if event_type not in ALLOWED_EVENT_TYPES:
        raise ValueError('Unsupported API diagnostic event type.')

    exception_type = _exception_type(exc)
    location = _structural_location(exc)
    fingerprint = hashlib.sha256(
        f'{exception_type}|{location}'.encode('utf-8')
    ).hexdigest()
    request._api_diagnostic_emitted = True
    diagnostic_logger.error(
        '',
        extra={
            'diagnostic_event': {
                'request_id': getattr(request, 'request_id', None),
                'event': event_type,
                'error_type': 'internal_error',
                'exception_type': exception_type,
                'fingerprint': fingerprint,
            }
        },
    )


def capture_unhandled_request_exception(sender, request, **kwargs):
    del sender, kwargs
    exc = sys.exception()
    if exc is not None and request.path.startswith('/api/v1/'):
        request._api_unhandled_exception = exc


def connect_exception_capture_signal():
    got_request_exception.connect(
        capture_unhandled_request_exception,
        dispatch_uid='api.capture_unhandled_request_exception',
        weak=False,
    )
