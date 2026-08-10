import json
from unittest.mock import patch

from django.test import TestCase

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
        self.assertEqual(len(events), 1)
        access_events = [event for event in events if event['service'] == 'lar-finance-api']
        self.assertEqual(len(access_events), 1)
        self.assertEqual(access_events[0]['error_code'], 'internal_error')
        serialized = json.dumps(events)
        for forbidden in (
            exception_secret,
            'private-error-query',
            'private-error-header',
        ):
            self.assertNotIn(forbidden, serialized)
