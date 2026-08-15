from hashlib import sha256
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
BATCH_KEYS = {
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
    'record_count',
    'pending_count',
    'income_total',
    'expense_total',
    'is_repeated_file',
    'records',
    'next_cursor',
}
RECORD_KEYS = {
    'uuid',
    'posted_on',
    'description',
    'amount',
    'transaction_type',
    'outcome',
}


class ImportApiTest(TestCase):
    def setUp(self):
        self.content = (FIXTURES / 'nubank-account.ofx').read_bytes()
        self.multi_content = (FIXTURES / 'nubank-account-multi.ofx').read_bytes()
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
        self.assertEqual(set(body), BATCH_KEYS)
        self.assertEqual(body['status'], ImportBatch.PREVIEW_READY)
        self.assertTrue(body['expires_at'].endswith('Z'))
        self.assertIsNotNone(body['account_uuid'])
        self.assertEqual(body['financial_owner_uuid'], str(self.owner.uuid))
        self.assertEqual(body['record_count'], 2)
        self.assertEqual(body['pending_count'], 2)
        self.assertEqual(body['income_total'], '125.75')
        self.assertEqual(body['expense_total'], '42.50')
        self.assertIsNone(body['next_cursor'])
        self.assertEqual(len(body['records']), 2)
        self.assertEqual(
            body['records'][0],
            {
                'uuid': body['records'][0]['uuid'],
                'posted_on': '2026-01-02',
                'description': 'Synthetic market purchase',
                'amount': '42.50',
                'transaction_type': 'expense',
                'outcome': 'pending',
            },
        )
        serialized = repr(body)
        for forbidden in (
            'synthetic-account-001',
            'synthetic-fitid-001',
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

        batch = ImportBatch.objects.get(uuid=batch_uuid)
        batch.account.import_account_links.filter(
            household=self.household,
            provider='nubank',
            product_type='bank_account',
        ).delete()
        ImportBatch.objects.filter(pk=batch.pk).update(
            account=None,
            financial_owner=None,
            status=ImportBatch.NEEDS_ACCOUNT_LINK,
        )
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

    def test_detail_returns_private_records_in_stable_pages(self):
        url = self._detail_url(self._multi_batch_uuid())

        first = self.client.get(f'{url}?limit=2', **self.auth).json()

        self.assertEqual(set(first), BATCH_KEYS)
        self.assertEqual(len(first['records']), 2)
        self.assertEqual(first['next_cursor'], '2')
        self.assertEqual(set(first['records'][0]), RECORD_KEYS)
        self.assertEqual(first['record_count'], 5)
        self.assertEqual(first['pending_count'], 5)
        self.assertEqual(first['income_total'], '60.00')
        self.assertEqual(first['expense_total'], '90.00')

        second = self.client.get(f'{url}?after=2&limit=2', **self.auth).json()
        self.assertEqual(second['next_cursor'], '4')

        last = self.client.get(f'{url}?after=4&limit=2', **self.auth).json()
        self.assertEqual(len(last['records']), 1)
        self.assertIsNone(last['next_cursor'])

        pages = (first, second, last)
        self.assertEqual(
            [record['description'] for page in pages for record in page['records']],
            [
                'Synthetic paged expense one',
                'Synthetic paged income one',
                'Synthetic paged expense two',
                'Synthetic paged income two',
                'Synthetic paged expense three',
            ],
        )
        self.assertEqual(
            [record['amount'] for page in pages for record in page['records']],
            ['10.00', '20.00', '30.00', '40.00', '50.00'],
        )
        uuids = [record['uuid'] for page in pages for record in page['records']]
        self.assertEqual(len(set(uuids)), 5)

        exhausted = self.client.get(f'{url}?after=5', **self.auth).json()
        self.assertEqual(exhausted['records'], [])
        self.assertIsNone(exhausted['next_cursor'])
        self.assertEqual(exhausted['record_count'], 5)

    def test_detail_without_paging_parameters_uses_the_default_page(self):
        url = self._detail_url(self._multi_batch_uuid())

        body = self.client.get(url, **self.auth).json()

        self.assertEqual(len(body['records']), 5)
        self.assertIsNone(body['next_cursor'])

    def test_detail_rejects_invalid_after_and_limit(self):
        url = self._detail_url(self._multi_batch_uuid())

        for limit in (1, 50, 100):
            with self.subTest(limit=limit):
                accepted = self.client.get(f'{url}?limit={limit}', **self.auth)
                self.assertEqual(accepted.status_code, 200)

        for query in (
            'limit=0',
            'limit=101',
            'limit=-1',
            'limit=abc',
            'limit=1.5',
            'after=-1',
            'after=abc',
            'after=1.5',
        ):
            with self.subTest(query=query):
                rejected = self.client.get(f'{url}?{query}', **self.auth)
                self.assertEqual(rejected.status_code, 400)
                self.assertEqual(
                    rejected.json()['error']['code'], 'invalid_import_page'
                )

    def test_detail_never_exposes_fitid_account_id_hash_or_file_name(self):
        url = self._detail_url(self._multi_batch_uuid())

        serialized = repr(self.client.get(url, **self.auth).json())

        for forbidden in (
            'synthetic-fitid-101',
            'synthetic-fitid-105',
            'synthetic-account-multi',
            sha256(self.multi_content).hexdigest(),
            'nubank-account-multi.ofx',
            'fingerprint',
            'line_number',
            'external_id',
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, serialized)

    def test_foreign_household_cannot_page_records(self):
        foreign_batch_uuid = self._preview(
            content=self.multi_content, auth=self.foreign_auth
        ).json()['uuid']

        response = self.client.get(
            f'{self._detail_url(foreign_batch_uuid)}?after=1&limit=2', **self.auth
        )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()['error']['code'], 'not_found')

    def test_confirmed_and_cancelled_receipts_keep_the_same_page_shape(self):
        batch_uuid = self._multi_batch_uuid()
        confirmed = self.client.post(
            self._confirm_url(batch_uuid), {}, content_type='application/json', **self.auth
        ).json()

        self.assertEqual(set(confirmed), BATCH_KEYS)
        self.assertEqual(confirmed['pending_count'], 0)
        self.assertEqual(
            {record['outcome'] for record in confirmed['records']}, {'created'}
        )

        cancelled_uuid = self._preview(
            content=self.multi_content.replace(
                b'synthetic-account-multi', b'synthetic-account-cancelled'
            )
        ).json()['uuid']
        cancelled = self.client.post(
            self._cancel_url(cancelled_uuid),
            {},
            content_type='application/json',
            **self.auth,
        ).json()

        self.assertEqual(set(cancelled), BATCH_KEYS)
        self.assertEqual(cancelled['records'], [])
        self.assertEqual(cancelled['record_count'], 0)
        self.assertEqual(cancelled['income_total'], '0.00')
        self.assertEqual(cancelled['expense_total'], '0.00')
        self.assertIsNone(cancelled['next_cursor'])

    def test_sqlite_contention_returns_stable_domain_error_instead_of_500(self):
        batch_uuid = self._preview().json()['uuid']

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

    def _multi_batch_uuid(self):
        return self._preview(content=self.multi_content).json()['uuid']

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
