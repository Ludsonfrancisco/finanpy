from io import BytesIO
from pathlib import Path
from unittest.mock import patch

from django.test import TestCase

from accounts.models import Account
from api.import_views import _read_ofx_upload
from api.models import DeviceSession
from api.tokens import issue_session
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from imports.models import ImportBatch
from imports.services import ImportBusyError
from users.models import User

FIXTURES = Path(__file__).parents[2] / 'imports' / 'tests' / 'fixtures'
IMPORT_ROUTES = (
    '/api/v1/imports/ofx/preview/',
    '/api/v1/imports/{batch_uuid}/',
    '/api/v1/imports/{batch_uuid}/bind-account/',
    '/api/v1/imports/{batch_uuid}/confirm/',
    '/api/v1/imports/{batch_uuid}/cancel/',
)


class ImportApiTest(TestCase):
    def setUp(self):
        self.content = (FIXTURES / 'nubank-account.ofx').read_bytes()
        self.user, self.household, self.owner, self.account, self.auth = self._setup(
            'imports@example.test'
        )
        self.device = DeviceSession.objects.get(household=self.household)
        (
            self.foreign_user,
            self.foreign_household,
            self.foreign_owner,
            self.foreign_account,
            self.foreign_auth,
        ) = self._setup('foreign-imports@example.test')

    def test_preview_requires_device_token_and_returns_private_stable_payload(self):
        anonymous = self.client.post(
            IMPORT_ROUTES[0], {'file': BytesIO(self.content)}, format='multipart'
        )
        self.assertEqual(anonymous.status_code, 401)

        response = self._preview()

        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertEqual(
            set(body),
            {
                'uuid',
                'status',
                'provider',
                'product_type',
                'statement_start',
                'statement_end',
                'expires_at',
                'account_uuid',
                'financial_owner_uuid',
                'created_count',
                'duplicate_count',
                'warning_count',
                'is_repeated_file',
            },
        )
        self.assertEqual(body['status'], ImportBatch.NEEDS_ACCOUNT_LINK)
        self.assertTrue(body['expires_at'].endswith('Z'))
        self.assertIsNone(body['account_uuid'])
        serialized = repr(body)
        for forbidden in (
            'synthetic-account-001',
            'Synthetic market purchase',
            '-42.50',
            'file_sha256',
            'external_account_id',
        ):
            self.assertNotIn(forbidden, serialized)

    def test_preview_bind_confirm_and_cancel_routes(self):
        batch_uuid = self._preview().json()['uuid']
        detail = self.client.get(self._detail_url(batch_uuid), **self.auth)
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()['uuid'], batch_uuid)

        bound = self.client.post(
            self._bind_url(batch_uuid),
            {'account_uuid': str(self.account.uuid)},
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(bound.status_code, 200)
        self.assertEqual(bound.json()['status'], ImportBatch.PREVIEW_READY)

        confirmed = self.client.post(
            self._confirm_url(batch_uuid), {}, content_type='application/json', **self.auth
        )
        self.assertEqual(confirmed.status_code, 200)
        self.assertEqual(confirmed.json()['status'], ImportBatch.COMPLETED)

        unknown_content = self.content.replace(
            b'synthetic-account-001', b'synthetic-account-cancel'
        )
        cancelled_batch_uuid = self._preview(content=unknown_content).json()['uuid']
        cancelled = self.client.post(
            self._cancel_url(cancelled_batch_uuid),
            {},
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(cancelled.status_code, 200)
        self.assertEqual(cancelled.json()['status'], ImportBatch.CANCELLED)

    def test_sqlite_contention_returns_stable_domain_error_instead_of_500(self):
        batch_uuid = self._preview().json()['uuid']
        bound = self.client.post(
            self._bind_url(batch_uuid),
            {'account_uuid': str(self.account.uuid)},
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(bound.status_code, 200)

        with patch(
            'api.import_views.confirm_preview',
            side_effect=ImportBusyError('Import operation is temporarily busy.'),
        ):
            response = self.client.post(
                self._confirm_url(batch_uuid),
                {},
                content_type='application/json',
                **self.auth,
            )

        self.assertEqual(response.status_code, 503)
        self.assertEqual(
            response.json()['error']['code'], 'import_temporarily_unavailable'
        )
        self.assertEqual(
            response.json()['error']['message'],
            'A importação está temporariamente ocupada. Tente novamente.',
        )

    def test_detail_purge_contention_returns_same_safe_503(self):
        batch_uuid = self._preview().json()['uuid']

        with patch(
            'api.import_views.get_batch_for_household',
            side_effect=ImportBusyError('private lock detail'),
        ):
            response = self.client.get(self._detail_url(batch_uuid), **self.auth)

        self.assertEqual(response.status_code, 503)
        self.assertEqual(
            response.json()['error']['code'], 'import_temporarily_unavailable'
        )
        self.assertNotIn('private lock detail', repr(response.json()))

    def test_other_household_batch_and_account_return_not_found(self):
        foreign_batch_uuid = self._preview(auth=self.foreign_auth).json()['uuid']

        for path, data in (
            (self._detail_url(foreign_batch_uuid), None),
            (self._bind_url(foreign_batch_uuid), {'account_uuid': str(self.account.uuid)}),
            (self._confirm_url(foreign_batch_uuid), {}),
            (self._cancel_url(foreign_batch_uuid), {}),
        ):
            with self.subTest(path=path):
                response = (
                    self.client.get(path, **self.auth)
                    if data is None
                    else self.client.post(
                        path, data, content_type='application/json', **self.auth
                    )
                )
                self.assertEqual(response.status_code, 404)
                self.assertEqual(response.json()['error']['code'], 'not_found')

        batch_uuid = self._preview(content=self.content + b'\n').json()['uuid']
        foreign_account = self.client.post(
            self._bind_url(batch_uuid),
            {'account_uuid': str(self.foreign_account.uuid)},
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(foreign_account.status_code, 404)
        self.assertEqual(foreign_account.json()['error']['code'], 'not_found')

    def test_invalid_ofx_uses_safe_error_envelope_without_content_in_logs(self):
        private_content = (
            b'OFXHEADER:100\nDATA:OFXSGML\nCHARSET:1252\n'
            b'<OFX><MEMO>private-value-987.65'
        )
        with self.assertLogs('lar_finance.api', level='INFO') as captured:
            response = self.client.post(
                IMPORT_ROUTES[0],
                {'file': BytesIO(private_content)},
                format='multipart',
                **self.auth,
            )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()['error']['code'], 'invalid_ofx')
        output = '\n'.join(record.getMessage() for record in captured.records)
        self.assertNotIn('private-value-987.65', output)
        self.assertNotIn(str(self.device.uuid), output)

    def test_unsupported_ofx_uses_its_stable_error_code(self):
        response = self.client.post(
            IMPORT_ROUTES[0],
            {'file': BytesIO(b'not an OFX')},
            format='multipart',
            **self.auth,
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()['error']['code'], 'unsupported_ofx')

    def test_unpersistable_normalized_field_returns_safe_invalid_ofx(self):
        content = self.content.replace(
            b'<MEMO>Synthetic market purchase',
            b'<MEMO>' + b'x' * 256,
        )

        response = self._preview(content=content)

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()['error']['code'], 'invalid_ofx')

    def test_oversized_upload_is_rejected_before_reading_its_content(self):
        class OversizedUpload:
            size = 10 * 1024 * 1024 + 1

            def chunks(self):
                raise AssertionError('oversized file must not be read')

        with self.assertRaisesRegex(ValueError, 'maximum'):
            _read_ofx_upload(OversizedUpload())

    def test_upload_without_reliable_size_is_read_only_up_to_the_limit(self):
        class UnknownSizeUpload:
            size = None

            def chunks(self):
                yield b'x' * (10 * 1024 * 1024)
                yield b'y'

        with self.assertRaisesRegex(ValueError, 'maximum'):
            _read_ofx_upload(UnknownSizeUpload())

    def _preview(self, content=None, auth=None):
        return self.client.post(
            IMPORT_ROUTES[0],
            {'file': BytesIO(content or self.content)},
            format='multipart',
            **(auth or self.auth),
        )

    @staticmethod
    def _detail_url(batch_uuid):
        return f'/api/v1/imports/{batch_uuid}/'

    @staticmethod
    def _bind_url(batch_uuid):
        return f'/api/v1/imports/{batch_uuid}/bind-account/'

    @staticmethod
    def _confirm_url(batch_uuid):
        return f'/api/v1/imports/{batch_uuid}/confirm/'

    @staticmethod
    def _cancel_url(batch_uuid):
        return f'/api/v1/imports/{batch_uuid}/cancel/'

    @staticmethod
    def _setup(email):
        user = User.objects.create_user(email=email, password='Strong-pass-123')
        household = ensure_household_for_user(user)
        owner = get_financial_owner(household, FinancialOwner.SELF)
        account = Account.objects.create(
            user=user,
            household=household,
            financial_owner=owner,
            name='Synthetic checking account',
            type=Account.CHECKING,
        )
        issued = issue_session(
            user=user,
            household=household,
            default_owner=owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        return user, household, owner, account, {
            'HTTP_AUTHORIZATION': f'Bearer {issued.access_token}'
        }
