from datetime import timedelta
from uuid import UUID, uuid4

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone

from api.models import DeviceSession
from api.tokens import digest_token, issue_session
from households.models import HouseholdMembership
from households.services import ensure_household_for_user, get_financial_owner
from users.models import User

AUTH_CASES = (
    ('login_success', '/api/v1/auth/login/', 200, ('access_token', 'refresh_token', 'device')),
    ('shared_owner_default', '/api/v1/auth/login/', 400, ('default_owner_uuid',)),
    ('unknown_email', '/api/v1/auth/login/', 401, ('invalid_credentials',)),
    ('wrong_password', '/api/v1/auth/login/', 401, ('invalid_credentials',)),
    ('sixth_login_attempt', '/api/v1/auth/login/', 429, ('throttled',)),
    ('refresh_rotation', '/api/v1/auth/refresh/', 200, ('new_access', 'new_refresh')),
    ('logout_current', '/api/v1/auth/logout/', 204, ('current_revoked', 'other_active')),
    ('device_list', '/api/v1/devices/', 200, ('same_user_only', 'no_token_fields')),
    (
        'revoke_other',
        '/api/v1/devices/{device_uuid}/revoke/',
        204,
        ('target_revoked', 'current_active'),
    ),
    ('patch_current_owner', '/api/v1/devices/current/', 200, ('self_or_spouse_only',)),
    ('inactive_membership', '/api/v1/devices/', 401, ('revoked_device',)),
)


class DeviceAuthenticationApiTest(TestCase):
    password = 'Strong-pass-123'

    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(email='lar@example.test', password=self.password)
        self.household = ensure_household_for_user(self.user)
        self.self_owner = get_financial_owner(self.household, owner_type='self')
        self.spouse_owner = get_financial_owner(self.household, owner_type='spouse')
        self.shared_owner = get_financial_owner(self.household, owner_type='shared')

    def login_payload(self, **overrides):
        payload = {
            'email': self.user.email,
            'password': self.password,
            'platform': DeviceSession.WINDOWS,
            'name': 'Notebook',
            'default_owner_uuid': str(self.self_owner.uuid),
        }
        payload.update(overrides)
        return payload

    def issue_device(self, *, user=None, household=None, owner=None, name='Notebook'):
        user = user or self.user
        household = household or self.household
        owner = owner or self.self_owner
        return issue_session(
            user=user,
            household=household,
            default_owner=owner,
            platform=DeviceSession.WINDOWS,
            name=name,
        )

    def bearer(self, token):
        return {'HTTP_AUTHORIZATION': f'Bearer {token}'}

    def error_code(self, response):
        return response.json()['error']['code']

    def test_login_success(self):
        response = self.client.post(
            '/api/v1/auth/login/',
            data=self.login_payload(),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(
            set(body),
            {
                'access_token',
                'access_expires_at',
                'refresh_token',
                'refresh_expires_at',
                'device',
            },
        )
        self.assertEqual(
            body['device'],
            {
                'uuid': str(DeviceSession.objects.get().uuid),
                'name': 'Notebook',
                'platform': DeviceSession.WINDOWS,
                'default_owner_uuid': str(self.self_owner.uuid),
            },
        )
        session = DeviceSession.objects.get()
        self.assertEqual(session.access_token_digest, digest_token(body['access_token']))
        self.assertEqual(session.refresh_token_digest, digest_token(body['refresh_token']))
        self.assertNotEqual(body['access_token'], session.access_token_digest)
        self.assertNotEqual(body['refresh_token'], session.refresh_token_digest)

    def test_login_without_default_owner_uses_active_self_owner(self):
        payload = {
            'email': self.user.email,
            'password': self.password,
            'platform': DeviceSession.WINDOWS,
            'name': 'Notebook novo',
        }

        response = self.client.post(
            '/api/v1/auth/login/', payload, content_type='application/json'
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()['device']['default_owner_uuid'],
            str(self.self_owner.uuid),
        )

    def test_login_without_default_owner_rejects_household_without_active_self(self):
        self.self_owner.is_active = False
        self.self_owner.save(update_fields=['is_active'])

        payload = {
            'email': self.user.email,
            'password': self.password,
            'platform': DeviceSession.ANDROID,
            'name': 'Telefone novo',
        }
        response = self.client.post(
            '/api/v1/auth/login/',
            payload,
            content_type='application/json',
        )
        invalid_response = self.client.post(
            '/api/v1/auth/login/',
            {**payload, 'password': 'Wrong-pass-123'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()['error']['code'], 'invalid_credentials')
        self.assertEqual(response.json()['error'], invalid_response.json()['error'])
        self.assertFalse(DeviceSession.objects.exists())

    def test_login_with_explicit_spouse_owner_succeeds(self):
        response = self.client.post(
            '/api/v1/auth/login/',
            data=self.login_payload(default_owner_uuid=str(self.spouse_owner.uuid)),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()['device']['default_owner_uuid'],
            str(self.spouse_owner.uuid),
        )

    def test_login_with_explicit_inactive_owner_is_rejected(self):
        self.spouse_owner.is_active = False
        self.spouse_owner.save(update_fields=['is_active'])

        response = self.client.post(
            '/api/v1/auth/login/',
            data=self.login_payload(default_owner_uuid=str(self.spouse_owner.uuid)),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('default_owner_uuid', response.json()['error']['fields'])
        self.assertFalse(DeviceSession.objects.exists())

    def test_login_with_explicit_foreign_owner_is_rejected(self):
        other_user = User.objects.create_user(
            email='other@example.test', password=self.password
        )
        other_household = ensure_household_for_user(other_user)
        foreign_owner = get_financial_owner(other_household, owner_type='self')

        response = self.client.post(
            '/api/v1/auth/login/',
            data=self.login_payload(default_owner_uuid=str(foreign_owner.uuid)),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('default_owner_uuid', response.json()['error']['fields'])
        self.assertFalse(DeviceSession.objects.exists())

    def test_invalid_explicit_owner_errors_do_not_reveal_owner_existence(self):
        other_user = User.objects.create_user(
            email='other@example.test', password=self.password
        )
        other_household = ensure_household_for_user(other_user)
        foreign_owner = get_financial_owner(other_household, owner_type='self')
        self.spouse_owner.is_active = False
        self.spouse_owner.save(update_fields=['is_active'])
        invalid_owner_uuids = (
            uuid4(),
            self.shared_owner.uuid,
            self.spouse_owner.uuid,
            foreign_owner.uuid,
        )

        responses = [
            self.client.post(
                '/api/v1/auth/login/',
                data=self.login_payload(default_owner_uuid=str(owner_uuid)),
                content_type='application/json',
            )
            for owner_uuid in invalid_owner_uuids
        ]

        baseline_error = responses[0].json()['error']
        for response in responses:
            self.assertEqual(response.status_code, 400)
            self.assertEqual(response.json()['error'], baseline_error)
        self.assertFalse(DeviceSession.objects.exists())

    def test_shared_owner_default(self):
        response = self.client.post(
            '/api/v1/auth/login/',
            data=self.login_payload(default_owner_uuid=str(self.shared_owner.uuid)),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('default_owner_uuid', response.json()['error']['fields'])
        self.assertFalse(DeviceSession.objects.exists())

    def test_unknown_email(self):
        response = self.client.post(
            '/api/v1/auth/login/',
            data=self.login_payload(email='unknown@example.test'),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(self.error_code(response), 'invalid_credentials')

    def test_wrong_password(self):
        unknown_response = self.client.post(
            '/api/v1/auth/login/',
            data=self.login_payload(email='unknown@example.test'),
            content_type='application/json',
        )
        wrong_password_response = self.client.post(
            '/api/v1/auth/login/',
            data=self.login_payload(password='Wrong-pass-123'),
            content_type='application/json',
        )

        self.assertEqual(wrong_password_response.status_code, 401)
        self.assertEqual(self.error_code(wrong_password_response), 'invalid_credentials')
        self.assertEqual(
            wrong_password_response.json()['error'],
            unknown_response.json()['error'],
        )
        for response in (wrong_password_response, unknown_response):
            request_id = response.json()['request_id']
            self.assertEqual(str(UUID(request_id)), request_id)

    def test_sixth_login_attempt(self):
        responses = [
            self.client.post(
                '/api/v1/auth/login/',
                data=self.login_payload(password='Wrong-pass-123'),
                content_type='application/json',
            )
            for _ in range(6)
        ]

        self.assertEqual([response.status_code for response in responses[:5]], [401] * 5)
        self.assertEqual(responses[5].status_code, 429)
        self.assertEqual(self.error_code(responses[5]), 'throttled')

    def test_refresh_rotation(self):
        issued = self.issue_device()

        response = self.client.post(
            '/api/v1/auth/refresh/',
            data={'refresh_token': issued.refresh_token},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertNotEqual(body['access_token'], issued.access_token)
        self.assertNotEqual(body['refresh_token'], issued.refresh_token)
        issued.session.refresh_from_db()
        self.assertEqual(issued.session.access_token_digest, digest_token(body['access_token']))
        self.assertEqual(issued.session.refresh_token_digest, digest_token(body['refresh_token']))

    def test_logout_current(self):
        current = self.issue_device(name='Notebook')
        other = self.issue_device(name='Celular')

        response = self.client.post(
            '/api/v1/auth/logout/',
            data={},
            content_type='application/json',
            **self.bearer(current.access_token),
        )

        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.content, b'')
        current.session.refresh_from_db()
        other.session.refresh_from_db()
        self.assertIsNotNone(current.session.revoked_at)
        self.assertIsNone(other.session.revoked_at)

    def test_device_list(self):
        current = self.issue_device(name='Notebook')
        same_user = self.issue_device(name='Celular')
        other_user = User.objects.create_user(
            email='other@example.test',
            password=self.password,
        )
        other_household = ensure_household_for_user(other_user)
        other_owner = get_financial_owner(other_household, owner_type='self')
        outsider = self.issue_device(
            user=other_user,
            household=other_household,
            owner=other_owner,
            name='Outsider',
        )

        response = self.client.get('/api/v1/devices/', **self.bearer(current.access_token))

        self.assertEqual(response.status_code, 200)
        body = response.json()
        listed_uuids = {device['uuid'] for device in body}
        self.assertEqual(listed_uuids, {str(current.session.uuid), str(same_user.session.uuid)})
        self.assertNotIn(str(outsider.session.uuid), listed_uuids)
        serialized = repr(body)
        for forbidden in (
            'access_token',
            'refresh_token',
            'access_token_digest',
            'refresh_token_digest',
            current.access_token,
            current.refresh_token,
        ):
            self.assertNotIn(forbidden, serialized)

    def test_revoke_other(self):
        current = self.issue_device(name='Notebook')
        target = self.issue_device(name='Celular')

        response = self.client.post(
            f'/api/v1/devices/{target.session.uuid}/revoke/',
            data={},
            content_type='application/json',
            **self.bearer(current.access_token),
        )

        self.assertEqual(response.status_code, 204)
        current.session.refresh_from_db()
        target.session.refresh_from_db()
        self.assertIsNone(current.session.revoked_at)
        self.assertIsNotNone(target.session.revoked_at)

    def test_patch_current_owner(self):
        current = self.issue_device()

        spouse_response = self.client.patch(
            '/api/v1/devices/current/',
            data={'default_owner_uuid': str(self.spouse_owner.uuid), 'name': 'Meu notebook'},
            content_type='application/json',
            **self.bearer(current.access_token),
        )
        shared_response = self.client.patch(
            '/api/v1/devices/current/',
            data={'default_owner_uuid': str(self.shared_owner.uuid)},
            content_type='application/json',
            **self.bearer(current.access_token),
        )

        self.assertEqual(spouse_response.status_code, 200)
        self.assertEqual(
            spouse_response.json()['default_owner_uuid'],
            str(self.spouse_owner.uuid),
        )
        self.assertEqual(spouse_response.json()['name'], 'Meu notebook')
        self.assertEqual(shared_response.status_code, 400)
        self.assertIn('default_owner_uuid', shared_response.json()['error']['fields'])
        current.session.refresh_from_db()
        self.assertEqual(current.session.default_owner, self.spouse_owner)

    def test_inactive_membership(self):
        current = self.issue_device()
        HouseholdMembership.objects.filter(
            user=self.user,
            household=self.household,
        ).update(is_active=False)

        response = self.client.get('/api/v1/devices/', **self.bearer(current.access_token))

        self.assertEqual(response.status_code, 401)
        self.assertEqual(self.error_code(response), 'revoked_device')
        current.session.refresh_from_db()
        self.assertIsNotNone(current.session.revoked_at)

    def test_access_authentication_uses_stable_token_error_codes(self):
        expired = self.issue_device(name='Expirado')
        DeviceSession.objects.filter(pk=expired.session.pk).update(
            access_expires_at=timezone.now() - timedelta(seconds=1),
        )
        expired_response = self.client.get(
            '/api/v1/devices/',
            **self.bearer(expired.access_token),
        )
        revoked = self.issue_device(name='Revogado')
        DeviceSession.objects.filter(pk=revoked.session.pk).update(revoked_at=timezone.now())
        revoked_response = self.client.get(
            '/api/v1/devices/',
            **self.bearer(revoked.access_token),
        )
        invalid_response = self.client.get(
            '/api/v1/devices/',
            **self.bearer('unknown-token'),
        )

        self.assertEqual(expired_response.status_code, 401)
        self.assertEqual(self.error_code(expired_response), 'expired_token')
        self.assertEqual(revoked_response.status_code, 401)
        self.assertEqual(self.error_code(revoked_response), 'revoked_device')
        self.assertEqual(invalid_response.status_code, 401)
        self.assertEqual(self.error_code(invalid_response), 'invalid_token')

    def test_authorization_requires_exact_bearer_shape(self):
        current = self.issue_device()

        valid_response = self.client.get(
            '/api/v1/devices/',
            **self.bearer(current.access_token),
        )
        lowercase_response = self.client.get(
            '/api/v1/devices/',
            HTTP_AUTHORIZATION=f'bearer {current.access_token}',
        )
        extra_part_response = self.client.get(
            '/api/v1/devices/',
            HTTP_AUTHORIZATION=f'Bearer {current.access_token} extra',
        )
        whitespace_response = self.client.get(
            '/api/v1/devices/',
            HTTP_AUTHORIZATION='   ',
        )
        repeated_space_response = self.client.get(
            '/api/v1/devices/',
            HTTP_AUTHORIZATION=f'Bearer  {current.access_token}',
        )
        tab_response = self.client.get(
            '/api/v1/devices/',
            HTTP_AUTHORIZATION=f'Bearer\t{current.access_token}',
        )

        self.assertEqual(valid_response.status_code, 200)
        self.assertEqual(lowercase_response.status_code, 401)
        self.assertEqual(self.error_code(lowercase_response), 'not_authenticated')
        self.assertEqual(extra_part_response.status_code, 401)
        self.assertEqual(self.error_code(extra_part_response), 'invalid_token')
        self.assertEqual(whitespace_response.status_code, 401)
        self.assertEqual(self.error_code(whitespace_response), 'not_authenticated')
        self.assertEqual(repeated_space_response.status_code, 401)
        self.assertEqual(self.error_code(repeated_space_response), 'invalid_token')
        self.assertEqual(tab_response.status_code, 401)
        self.assertEqual(self.error_code(tab_response), 'invalid_token')

    def test_last_seen_is_written_at_most_once_per_five_minutes(self):
        current = self.issue_device()
        recent = timezone.now() - timedelta(minutes=4)
        DeviceSession.objects.filter(pk=current.session.pk).update(last_seen_at=recent)

        first_response = self.client.get(
            '/api/v1/devices/',
            **self.bearer(current.access_token),
        )
        current.session.refresh_from_db()
        self.assertEqual(first_response.status_code, 200)
        self.assertEqual(current.session.last_seen_at, recent)

        stale = timezone.now() - timedelta(minutes=6)
        DeviceSession.objects.filter(pk=current.session.pk).update(last_seen_at=stale)
        second_response = self.client.get(
            '/api/v1/devices/',
            **self.bearer(current.access_token),
        )
        current.session.refresh_from_db()
        self.assertEqual(second_response.status_code, 200)
        self.assertGreater(current.session.last_seen_at, stale)

    def test_inactive_user_and_household_revoke_authenticated_device(self):
        inactive_user_device = self.issue_device(name='Usuário inativo')
        self.user.is_active = False
        self.user.save(update_fields=['is_active'])

        user_response = self.client.get(
            '/api/v1/devices/',
            **self.bearer(inactive_user_device.access_token),
        )
        self.assertEqual(user_response.status_code, 401)
        self.assertEqual(self.error_code(user_response), 'revoked_device')
        inactive_user_device.session.refresh_from_db()
        self.assertIsNotNone(inactive_user_device.session.revoked_at)

        self.user.is_active = True
        self.user.save(update_fields=['is_active'])
        inactive_household_device = self.issue_device(name='Lar inativo')
        self.household.is_active = False
        self.household.save(update_fields=['is_active'])

        household_response = self.client.get(
            '/api/v1/devices/',
            **self.bearer(inactive_household_device.access_token),
        )
        self.assertEqual(household_response.status_code, 401)
        self.assertEqual(self.error_code(household_response), 'revoked_device')
        inactive_household_device.session.refresh_from_db()
        self.assertIsNotNone(inactive_household_device.session.revoked_at)

    def test_refresh_is_throttled_after_thirty_attempts(self):
        responses = [
            self.client.post(
                '/api/v1/auth/refresh/',
                data={'refresh_token': 'unknown-token'},
                content_type='application/json',
            )
            for _ in range(31)
        ]

        self.assertEqual([response.status_code for response in responses[:30]], [401] * 30)
        self.assertEqual(responses[30].status_code, 429)
        self.assertEqual(self.error_code(responses[30]), 'throttled')

    def test_cannot_revoke_a_session_outside_authenticated_user_and_household(self):
        current = self.issue_device()
        other_user = User.objects.create_user(
            email='other@example.test',
            password=self.password,
        )
        other_household = ensure_household_for_user(other_user)
        other_owner = get_financial_owner(other_household, owner_type='self')
        outsider = self.issue_device(
            user=other_user,
            household=other_household,
            owner=other_owner,
        )

        response = self.client.post(
            f'/api/v1/devices/{outsider.session.uuid}/revoke/',
            data={},
            content_type='application/json',
            **self.bearer(current.access_token),
        )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.error_code(response), 'not_found')
        outsider.session.refresh_from_db()
        self.assertIsNone(outsider.session.revoked_at)
