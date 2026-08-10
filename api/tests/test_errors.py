import json
from unittest.mock import patch

from django.conf import settings
from django.test import TestCase, override_settings

from api.views import HealthView

from .test_observability import capture_configured_log_stream, parse_json_log_lines


class ApiInternalErrorTest(TestCase):
    def test_unhandled_api_exception_returns_private_error_envelope_and_safe_logs(self):
        exception_secret = 'private exception detail and token'
        self.client.raise_request_exception = False

        def raise_private_exception(view, request):
            raise RuntimeError(exception_secret)

        with patch.object(HealthView, 'get', raise_private_exception):
            with capture_configured_log_stream() as stream:
                response = self.client.get(
                    '/api/v1/health/?token=private-error-query',
                    HTTP_X_PRIVATE_HEADER='private-error-header',
                )

        self.assertEqual(response.status_code, 500)
        request_id = response.headers['X-Request-ID']
        self.assertEqual(
            response.json(),
            {
                'error': {
                    'code': 'internal_error',
                    'message': 'Erro interno do servidor.',
                    'fields': None,
                },
                'request_id': request_id,
            },
        )
        events = parse_json_log_lines(stream)
        access_events = [event for event in events if event['service'] == 'lar-finance-api']
        diagnostic_events = [
            event for event in events if event['service'] == 'lar-finance-api-diagnostic'
        ]
        self.assertEqual(len(access_events), 1)
        self.assertEqual(len(diagnostic_events), 1)
        self.assertEqual(access_events[0]['error_code'], 'internal_error')
        self.assertEqual(diagnostic_events[0]['error_type'], 'internal_error')
        self.assertEqual(
            diagnostic_events[0]['exception_type'],
            'builtins.RuntimeError',
        )
        self.assertEqual(len(diagnostic_events[0]['fingerprint']), 64)
        serialized = json.dumps(events)
        for forbidden in (
            exception_secret,
            'private-error-query',
            'private-error-header',
        ):
            self.assertNotIn(forbidden, serialized)

    def test_diagnostic_fingerprint_is_stable_for_same_exception_location(self):
        self.client.raise_request_exception = False

        def raise_private_exception(view, request):
            raise RuntimeError('a different secret on every request')

        fingerprints = []
        with patch.object(HealthView, 'get', raise_private_exception):
            for _ in range(2):
                with capture_configured_log_stream() as stream:
                    self.client.get('/api/v1/health/')
                diagnostics = [
                    event
                    for event in parse_json_log_lines(stream)
                    if event['service'] == 'lar-finance-api-diagnostic'
                ]
                self.assertEqual(len(diagnostics), 1)
                fingerprints.append(diagnostics[0]['fingerprint'])

        self.assertEqual(fingerprints[0], fingerprints[1])

    def test_downstream_middleware_failure_gets_safe_fallback_and_diagnostic(self):
        secret = 'middleware-secret-token-and-financial-value-998.76'

        class_path = 'api.tests.test_errors.ExplodingMiddleware'
        middleware = list(settings.MIDDLEWARE)
        middleware.insert(middleware.index('api.middleware.ApiObservabilityMiddleware') + 1, class_path)

        self.client.raise_request_exception = False
        with override_settings(MIDDLEWARE=middleware):
            with capture_configured_log_stream() as stream:
                response = self.client.get(
                    '/api/v1/health/?token=downstream-private-query',
                    HTTP_X_PRIVATE_HEADER='downstream-private-header',
                )

        self.assertEqual(response.status_code, 500)
        request_id = response.headers['X-Request-ID']
        self.assertEqual(
            response.json(),
            {
                'error': {
                    'code': 'internal_error',
                    'message': 'Erro interno do servidor.',
                    'fields': None,
                },
                'request_id': request_id,
            },
        )
        events = parse_json_log_lines(stream)
        access_events = [
            event for event in events if event['service'] == 'lar-finance-api'
        ]
        diagnostics = [
            event for event in events if event['service'] == 'lar-finance-api-diagnostic'
        ]
        self.assertEqual(len(access_events), 1)
        self.assertEqual(access_events[0]['error_code'], 'internal_error')
        self.assertEqual(len(diagnostics), 1)
        self.assertEqual(diagnostics[0]['exception_type'], 'builtins.RuntimeError')
        self.assertEqual(len(diagnostics[0]['fingerprint']), 64)
        serialized = json.dumps(events)
        for forbidden in (
            secret,
            'downstream-private-query',
            'downstream-private-header',
        ):
            self.assertNotIn(forbidden, serialized)


class ExplodingMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        raise RuntimeError('middleware-secret-token-and-financial-value-998.76')
