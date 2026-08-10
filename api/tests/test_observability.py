import json
import logging
from contextlib import contextmanager
from io import StringIO
from uuid import UUID, uuid4

from django.conf import settings
from django.test import RequestFactory, TestCase
from django.test.utils import override_settings

from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from users.models import User

from ..models import DeviceSession
from ..tokens import issue_session

OBSERVABILITY_CASES = (
    ('generated_request_id', None, 'uuid_response_header'),
    (
        'valid_request_id',
        'e8b27e90-7b70-4c1e-bef1-6c8791e5fa31',
        'same_response_header',
    ),
    ('invalid_request_id', 'not-a-uuid', 'replacement_uuid'),
    ('login_privacy', 'lar@example.test Strong-pass-123', 'neither_value_in_log'),
    ('sync_privacy', '999.99 private description', 'neither_value_in_log'),
)


@contextmanager
def capture_configured_log_stream():
    stream = StringIO()
    handlers = {}
    for logger_name in (
        'lar_finance.api',
        'django',
        'django.request',
        'django.server',
        'django.security',
    ):
        for handler in logging.getLogger(logger_name).handlers:
            if isinstance(handler, logging.StreamHandler):
                handlers[id(handler)] = handler
    original_streams = {handler_id: handler.stream for handler_id, handler in handlers.items()}
    try:
        for handler in handlers.values():
            handler.setStream(stream)
        yield stream
    finally:
        for handler_id, handler in handlers.items():
            handler.setStream(original_streams[handler_id])


def parse_json_log_lines(stream):
    return [json.loads(line) for line in stream.getvalue().splitlines() if line]


class ApiObservabilityTest(TestCase):
    log_fields = {
        'timestamp',
        'level',
        'service',
        'request_id',
        'method',
        'route',
        'status',
        'duration_ms',
        'authenticated',
        'device_uuid',
        'error_code',
    }

    def setUp(self):
        self.user = User.objects.create_user(
            email='lar@example.test',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, FinancialOwner.SELF)

    def capture_request(self, method, path, data=None, **headers):
        with self.assertLogs('lar_finance.api', level='INFO') as captured:
            response = getattr(self.client, method)(
                path,
                data=data,
                content_type='application/json' if data is not None else None,
                **headers,
            )
        lines = [record.getMessage() for record in captured.records]
        events = [json.loads(line) for line in lines]
        self.assertEqual(len(events), 1)
        self.assertEqual(set(events[0]), self.log_fields)
        return response, events[0], lines

    def test_generated_request_id(self):
        response, event, _ = self.capture_request('get', '/api/v1/health/')

        request_id = response.headers['X-Request-ID']
        self.assertEqual(str(UUID(request_id)), request_id)
        self.assertEqual(event['request_id'], request_id)

    def test_valid_request_id(self):
        request_id = 'e8b27e90-7b70-4c1e-bef1-6c8791e5fa31'

        response, event, _ = self.capture_request(
            'get',
            '/api/v1/health/',
            HTTP_X_REQUEST_ID=request_id,
        )

        self.assertEqual(response.headers['X-Request-ID'], request_id)
        self.assertEqual(event['request_id'], request_id)

    def test_invalid_request_id(self):
        response, event, _ = self.capture_request(
            'get',
            '/api/v1/health/',
            HTTP_X_REQUEST_ID='not-a-uuid',
        )

        replacement = response.headers['X-Request-ID']
        self.assertNotEqual(replacement, 'not-a-uuid')
        self.assertEqual(str(UUID(replacement)), replacement)
        self.assertEqual(event['request_id'], replacement)

    @override_settings(SECURE_SSL_REDIRECT=True)
    def test_ssl_redirect_receives_request_id_without_access_log(self):
        with self.assertNoLogs('lar_finance.api', level='INFO'):
            response = self.client.get('/api/v1/health/', secure=False)

        self.assertEqual(response.status_code, 301)
        request_id = response.headers['X-Request-ID']
        self.assertEqual(str(UUID(request_id)), request_id)

    def test_request_id_and_observability_middleware_order(self):
        request_id_position = settings.MIDDLEWARE.index('api.middleware.RequestIdMiddleware')
        security_position = settings.MIDDLEWARE.index(
            'django.middleware.security.SecurityMiddleware'
        )
        observability_position = settings.MIDDLEWARE.index(
            'api.middleware.ApiObservabilityMiddleware'
        )

        self.assertLess(request_id_position, security_position)
        self.assertEqual(observability_position, security_position + 1)

    def test_login_privacy(self):
        response, event, output = self.capture_request(
            'post',
            '/api/v1/auth/login/',
            {
                'email': 'lar@example.test',
                'password': 'Strong-pass-123',
                'platform': DeviceSession.WINDOWS,
                'name': 'Notebook',
                'default_owner_uuid': str(self.owner.uuid),
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertFalse(event['authenticated'])
        self.assertIsNone(event['device_uuid'])
        joined = '\n'.join(output)
        self.assertNotIn('lar@example.test', joined)
        self.assertNotIn('Strong-pass-123', joined)

    def test_real_login_log_stream_is_json_and_private(self):
        with capture_configured_log_stream() as stream:
            response = self.client.post(
                '/api/v1/auth/login/?invite=private-query',
                {
                    'email': 'stream-private@example.test',
                    'password': 'Stream-secret-123',
                    'platform': DeviceSession.WINDOWS,
                    'name': 'Private notebook header',
                    'default_owner_uuid': str(self.owner.uuid),
                },
                content_type='application/json',
                HTTP_X_PRIVATE_HEADER='private-header-value',
            )

        self.assertEqual(response.status_code, 401)
        events = parse_json_log_lines(stream)
        access_events = [event for event in events if event['service'] == 'lar-finance-api']
        self.assertEqual(len(access_events), 1)
        serialized = json.dumps(events)
        for forbidden in (
            'private-query',
            'stream-private@example.test',
            'Stream-secret-123',
            'Private notebook header',
            'private-header-value',
        ):
            self.assertNotIn(forbidden, serialized)

    def test_sync_privacy(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        response, event, output = self.capture_request(
            'post',
            '/api/v1/sync/push/',
            {
                'operations': [
                    {
                        'operation_id': str(uuid4()),
                        'entity': 'account',
                        'action': 'create',
                        'entity_uuid': str(uuid4()),
                        'expected_version': None,
                        'data': {
                            'name': 'private description',
                            'type': 'cash',
                            'initial_balance': '999.99',
                            'currency': 'BRL',
                            'financial_owner_uuid': str(self.owner.uuid),
                        },
                    }
                ]
            },
            HTTP_AUTHORIZATION=f'Bearer {issued.access_token}',
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(event['authenticated'])
        self.assertEqual(event['device_uuid'], str(issued.session.uuid))
        joined = '\n'.join(output)
        self.assertNotIn('999.99', joined)
        self.assertNotIn('private description', joined)

    def test_real_sync_log_stream_is_json_and_private(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        with capture_configured_log_stream() as stream:
            response = self.client.post(
                '/api/v1/sync/push/?cursor=private-sync-query',
                {
                    'operations': [
                        {
                            'operation_id': str(uuid4()),
                            'entity': 'account',
                            'action': 'create',
                            'entity_uuid': str(uuid4()),
                            'expected_version': None,
                            'data': {
                                'name': 'stream private description',
                                'type': 'cash',
                                'initial_balance': '876.54',
                                'currency': 'BRL',
                                'financial_owner_uuid': str(self.owner.uuid),
                            },
                        }
                    ]
                },
                content_type='application/json',
                HTTP_AUTHORIZATION=f'Bearer {issued.access_token}',
                HTTP_X_PRIVATE_HEADER='sync-private-header',
            )

        self.assertEqual(response.status_code, 200)
        events = parse_json_log_lines(stream)
        access_events = [event for event in events if event['service'] == 'lar-finance-api']
        self.assertEqual(len(access_events), 1)
        serialized = json.dumps(events)
        for forbidden in (
            'private-sync-query',
            'stream private description',
            '876.54',
            issued.access_token,
            'sync-private-header',
        ):
            self.assertNotIn(forbidden, serialized)

    def test_django_loggers_use_safe_json_handlers(self):
        request = RequestFactory().get(
            '/web/private/?token=private-django-query',
            HTTP_AUTHORIZATION='Bearer private-django-token',
            HTTP_X_PRIVATE_HEADER='private-django-header',
        )
        request.request_id = str(uuid4())

        with capture_configured_log_stream() as stream:
            try:
                raise RuntimeError('private django exception')
            except RuntimeError:
                for logger_name in (
                    'django.request',
                    'django.server',
                    'django.security',
                ):
                    logging.getLogger(logger_name).error(
                        'unsafe message %s',
                        'private-django-message',
                        extra={'request': request, 'status_code': 500},
                        exc_info=True,
                    )

        events = parse_json_log_lines(stream)
        self.assertEqual(len(events), 3)
        self.assertEqual(
            {event['logger'] for event in events},
            {'django.request', 'django.server', 'django.security'},
        )
        serialized = json.dumps(events)
        for forbidden in (
            'private-django-query',
            'private-django-token',
            'private-django-header',
            'private django exception',
            'private-django-message',
        ):
            self.assertNotIn(forbidden, serialized)

    def test_web_session_does_not_mark_unmatched_api_route_as_device_authenticated(self):
        self.client.force_login(self.user)

        response, event, _ = self.capture_request('get', '/api/v1/not-a-real-route/')

        self.assertEqual(response.status_code, 404)
        self.assertFalse(event['authenticated'])
        self.assertIsNone(event['device_uuid'])

    def test_observability_cases_are_documented(self):
        self.assertEqual(len(OBSERVABILITY_CASES), 5)
