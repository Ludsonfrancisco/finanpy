from uuid import uuid4

from django.test import TestCase

from api.models import DeviceSession
from api.tokens import issue_session
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from sync.cursors import decode_cursor, encode_cursor
from sync.models import SyncChange
from users.models import User

PULL_CASES = (
    ('ordered_after_cursor', 2, 3, ('ascending', 'next_cursor')),
    ('delete_tombstone', 1, 1, ('delete', 'deleted_true')),
    ('limit_100', 101, 100, ('next_cursor', 'remaining_one')),
    ('repeat_cursor', 3, 3, ('identical_body', 'identical_cursor')),
    ('empty', 0, 0, ('same_cursor', 'empty_results')),
)


class SyncPullApiTest(TestCase):
    endpoint = '/api/v1/sync/changes/'

    def setUp(self):
        self.user = User.objects.create_user(
            email='pull-api@example.test',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, FinancialOwner.SELF)
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issued.access_token}'}

    def create_changes(self, count, *, household=None, delete_at=None):
        household = household or self.household
        changes = []
        for position in range(count):
            is_delete = position == delete_at
            changes.append(
                SyncChange.objects.create(
                    household=household,
                    entity_type='account',
                    entity_uuid=uuid4(),
                    entity_version=position + 1,
                    operation=SyncChange.DELETE if is_delete else SyncChange.CREATE,
                    payload={
                        'uuid': str(uuid4()),
                        'deleted': True,
                    }
                    if is_delete
                    else {'uuid': str(uuid4()), 'name': f'Change {position}'},
                )
            )
        return changes

    def pull(self, cursor=None, **params):
        query = params.copy()
        if cursor is not None:
            query['cursor'] = cursor
        return self.client.get(self.endpoint, query, **self.auth)

    def test_ordered_after_cursor(self):
        first, *remaining = self.create_changes(3)

        response = self.pull(encode_cursor(first.id, self.household.uuid))

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(
            [item['entity_uuid'] for item in body['changes']],
            [str(change.entity_uuid) for change in remaining],
        )
        self.assertEqual(
            decode_cursor(body['cursor'], self.household.uuid), remaining[-1].id
        )
        self.assertNotIn('id', body['changes'][0])

    def test_delete_tombstone(self):
        change = self.create_changes(1, delete_at=0)[0]

        response = self.pull()

        self.assertEqual(response.status_code, 200)
        item = response.json()['changes'][0]
        self.assertEqual(item['operation'], SyncChange.DELETE)
        self.assertTrue(item['payload']['deleted'])
        self.assertEqual(item['entity_uuid'], str(change.entity_uuid))

    def test_limit_100(self):
        changes = self.create_changes(101)

        first_page = self.pull(limit=999)

        self.assertEqual(first_page.status_code, 200)
        first_body = first_page.json()
        self.assertEqual(len(first_body['changes']), 100)
        self.assertEqual(
            decode_cursor(first_body['cursor'], self.household.uuid), changes[99].id
        )
        second_page = self.pull(first_body['cursor'])
        self.assertEqual(len(second_page.json()['changes']), 1)
        self.assertEqual(
            second_page.json()['changes'][0]['entity_uuid'], str(changes[100].entity_uuid)
        )

    def test_repeat_cursor(self):
        self.create_changes(3)
        cursor = encode_cursor(0, self.household.uuid)

        first = self.pull(cursor)
        repeated = self.pull(cursor)

        self.assertEqual(first.status_code, 200)
        self.assertEqual(repeated.status_code, 200)
        self.assertEqual(first.json(), repeated.json())

    def test_empty(self):
        first = self.pull()

        self.assertEqual(first.status_code, 200)
        body = first.json()
        self.assertEqual(body['changes'], [])
        self.assertEqual(decode_cursor(body['cursor'], self.household.uuid), 0)
        repeated = self.pull(body['cursor'])
        self.assertEqual(repeated.json(), body)

    def assert_invalid_cursor_response(self, cursor):
        self.create_changes(1)

        response = self.pull(cursor)

        self.assertEqual(response.status_code, 400)
        body = response.json()
        self.assertEqual(body['error']['code'], 'invalid_cursor')
        self.assertNotIn('changes', body)
        self.assertNotIn('cursor', body)

    def test_tampered_cursor_is_rejected(self):
        cursor = encode_cursor(0, self.household.uuid)
        replacement = 'a' if cursor[-1] != 'a' else 'b'

        self.assert_invalid_cursor_response(cursor[:-1] + replacement)

    def test_foreign_household_cursor_is_rejected(self):
        cursor = encode_cursor(0, uuid4())

        self.assert_invalid_cursor_response(cursor)

    def test_negative_change_id_cursor_is_rejected(self):
        cursor = encode_cursor(-1, self.household.uuid)

        self.assert_invalid_cursor_response(cursor)

    def test_pull_cases_are_documented(self):
        self.assertEqual(len(PULL_CASES), 5)

    def test_pull_requires_device_authentication(self):
        response = self.client.get(self.endpoint)

        self.assertEqual(response.status_code, 401)
