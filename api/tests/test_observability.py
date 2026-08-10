import json
from uuid import UUID, uuid4

from django.test import TestCase

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

    def test_observability_cases_are_documented(self):
        self.assertEqual(len(OBSERVABILITY_CASES), 5)
