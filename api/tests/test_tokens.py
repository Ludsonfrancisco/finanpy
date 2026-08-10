from datetime import timedelta

from django.core.exceptions import ValidationError
from django.test import TestCase
from django.utils import timezone

from api.models import DeviceSession, UsedRefreshToken
from api.tokens import (
    ACCESS_LIFETIME,
    REFRESH_LIFETIME,
    InvalidRefreshTokenError,
    RefreshReuseError,
    digest_token,
    issue_session,
    revoke_session,
    rotate_refresh_token,
)
from households.services import ensure_household_for_user, get_financial_owner
from users.models import User


class DeviceTokenServiceTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='lar@example.test', password='Strong-pass-123')
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type='self')

    def test_raw_tokens_are_returned_once_but_only_digests_are_stored(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        session = issued.session
        self.assertNotEqual(session.access_token_digest, issued.access_token)
        self.assertEqual(session.access_token_digest, digest_token(issued.access_token))
        self.assertEqual(session.refresh_token_digest, digest_token(issued.refresh_token))
        self.assertNotIn(issued.access_token, repr(session.__dict__))
        self.assertNotIn(issued.refresh_token, repr(session.__dict__))
        self.assertEqual(session.access_expires_at - session.last_seen_at, ACCESS_LIFETIME)
        self.assertEqual(session.refresh_expires_at - session.last_seen_at, REFRESH_LIFETIME)

    def test_refresh_rotates_both_tokens_and_reuse_revokes_session(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        rotated = rotate_refresh_token(issued.refresh_token)
        self.assertNotEqual(rotated.refresh_token, issued.refresh_token)
        self.assertTrue(UsedRefreshToken.objects.filter(
            token_digest=digest_token(issued.refresh_token),
        ).exists())
        with self.assertRaises(RefreshReuseError):
            rotate_refresh_token(issued.refresh_token)
        issued.session.refresh_from_db()
        self.assertIsNotNone(issued.session.revoked_at)

    def test_refresh_rotates_access_token_and_slides_both_expiries(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )

        rotated = rotate_refresh_token(issued.refresh_token)

        self.assertNotEqual(rotated.access_token, issued.access_token)
        self.assertEqual(
            rotated.session.access_expires_at - rotated.session.last_seen_at,
            timedelta(minutes=15),
        )
        self.assertEqual(
            rotated.session.refresh_expires_at - rotated.session.last_seen_at,
            timedelta(days=30),
        )

    def test_expired_or_revoked_refresh_token_is_rejected(self):
        expired = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.IOS,
            name='iPhone',
        )
        expired.session.refresh_expires_at = timezone.now() - timedelta(seconds=1)
        expired.session.save(update_fields=['refresh_expires_at'])

        with self.assertRaises(InvalidRefreshTokenError):
            rotate_refresh_token(expired.refresh_token)

        revoked = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.ANDROID,
            name='Android',
        )
        revoke_session(revoked.session)
        with self.assertRaises(InvalidRefreshTokenError):
            rotate_refresh_token(revoked.refresh_token)

    def test_revoke_session_preserves_the_first_revocation_timestamp(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        revoke_session(issued.session)
        first_revoked_at = issued.session.revoked_at

        revoke_session(issued.session)
        issued.session.refresh_from_db()

        self.assertEqual(issued.session.revoked_at, first_revoked_at)

    def test_session_rejects_foreign_household_and_default_owner(self):
        other_user = User.objects.create_user(
            email='outro@example.test',
            password='Strong-pass-123',
        )
        other_household = ensure_household_for_user(other_user)
        other_owner = get_financial_owner(other_household, owner_type='self')

        with self.assertRaises(ValidationError) as foreign_household_error:
            issue_session(
                user=self.user,
                household=other_household,
                default_owner=other_owner,
                platform=DeviceSession.WINDOWS,
                name='Notebook',
            )
        self.assertIn('household', foreign_household_error.exception.message_dict)

        with self.assertRaises(ValidationError) as foreign_owner_error:
            issue_session(
                user=self.user,
                household=self.household,
                default_owner=other_owner,
                platform=DeviceSession.WINDOWS,
                name='Notebook',
            )
        self.assertIn('default_owner', foreign_owner_error.exception.message_dict)

    def test_session_rejects_shared_owner_as_device_default(self):
        shared_owner = get_financial_owner(self.household, owner_type='shared')

        with self.assertRaises(ValidationError) as error:
            issue_session(
                user=self.user,
                household=self.household,
                default_owner=shared_owner,
                platform=DeviceSession.WINDOWS,
                name='Notebook',
            )

        self.assertIn('default_owner', error.exception.message_dict)
