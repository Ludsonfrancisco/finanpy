import queue
import threading
from datetime import timedelta
from unittest.mock import patch

from django.core.exceptions import ValidationError
from django.db import close_old_connections
from django.db.models.query import QuerySet
from django.test import TestCase, TransactionTestCase
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
from households.models import HouseholdMembership
from households.services import ensure_household_for_user, get_financial_owner
from users.models import User


class DeviceTokenServiceTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='lar@example.test', password='Strong-pass-123')
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type='self')

    def issue_device_session(self):
        return issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )

    def assert_invalid_scope_revokes_without_rotation(self, issued):
        original_access_digest = issued.session.access_token_digest
        original_refresh_digest = issued.session.refresh_token_digest
        original_access_expiry = issued.session.access_expires_at
        original_refresh_expiry = issued.session.refresh_expires_at

        with self.assertRaises(InvalidRefreshTokenError):
            rotate_refresh_token(issued.refresh_token)

        issued.session.refresh_from_db()
        self.assertIsNotNone(issued.session.revoked_at)
        self.assertEqual(issued.session.access_token_digest, original_access_digest)
        self.assertEqual(issued.session.refresh_token_digest, original_refresh_digest)
        self.assertEqual(issued.session.access_expires_at, original_access_expiry)
        self.assertEqual(issued.session.refresh_expires_at, original_refresh_expiry)
        self.assertFalse(UsedRefreshToken.objects.filter(
            token_digest=digest_token(issued.refresh_token),
        ).exists())

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

    def test_session_rejects_inactive_user(self):
        self.user.is_active = False
        self.user.save(update_fields=['is_active'])

        with self.assertRaises(ValidationError) as error:
            self.issue_device_session()

        self.assertIn('user', error.exception.message_dict)
        self.assertFalse(DeviceSession.objects.exists())

    def test_refresh_revokes_session_after_user_is_deactivated(self):
        issued = self.issue_device_session()
        self.user.is_active = False
        self.user.save(update_fields=['is_active'])

        self.assert_invalid_scope_revokes_without_rotation(issued)

    def test_refresh_revokes_session_after_household_is_deactivated(self):
        issued = self.issue_device_session()
        self.household.is_active = False
        self.household.save(update_fields=['is_active'])

        self.assert_invalid_scope_revokes_without_rotation(issued)

    def test_refresh_revokes_session_after_membership_is_deactivated(self):
        issued = self.issue_device_session()
        HouseholdMembership.objects.filter(
            user=self.user,
            household=self.household,
        ).update(is_active=False)

        self.assert_invalid_scope_revokes_without_rotation(issued)

    def test_refresh_revokes_session_after_default_owner_is_deactivated(self):
        issued = self.issue_device_session()
        self.owner.is_active = False
        self.owner.save(update_fields=['is_active'])

        self.assert_invalid_scope_revokes_without_rotation(issued)

    def test_refresh_revokes_session_after_default_owner_becomes_shared(self):
        issued = self.issue_device_session()
        shared_owner = get_financial_owner(self.household, owner_type='shared')
        shared_owner.delete()
        self.owner.type = 'shared'
        self.owner.save(update_fields=['type'])

        self.assert_invalid_scope_revokes_without_rotation(issued)

    def test_refresh_revokes_session_after_default_owner_moves_to_another_household(self):
        issued = self.issue_device_session()
        other_user = User.objects.create_user(
            email='owner-externo@example.test',
            password='Strong-pass-123',
        )
        other_household = ensure_household_for_user(other_user)
        other_owner = get_financial_owner(other_household, owner_type='self')
        DeviceSession.objects.filter(pk=issued.session.pk).update(
            default_owner=other_owner,
        )

        self.assert_invalid_scope_revokes_without_rotation(issued)


class DeviceTokenConcurrencyTest(TransactionTestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='concorrencia@example.test',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type='self')

    def test_concurrent_refresh_has_one_winner_and_replay_revokes_session(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        both_loaded_session = threading.Barrier(2)
        outcomes = queue.Queue()
        original_first = QuerySet.first

        def synchronize_device_session_read(queryset):
            result = original_first(queryset)
            if queryset.model is DeviceSession:
                both_loaded_session.wait(timeout=10)
            return result

        def rotate_in_separate_connection():
            close_old_connections()
            try:
                rotate_refresh_token(issued.refresh_token)
            except RefreshReuseError:
                outcomes.put('replay')
            except Exception as exc:
                outcomes.put(type(exc).__name__)
            else:
                outcomes.put('issued')
            finally:
                close_old_connections()

        with patch.object(QuerySet, 'first', synchronize_device_session_read):
            threads = [
                threading.Thread(target=rotate_in_separate_connection)
                for _ in range(2)
            ]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(timeout=15)

        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertEqual(outcomes.qsize(), 2)
        self.assertEqual(
            sorted(outcomes.get_nowait() for _ in range(2)),
            ['issued', 'replay'],
        )
        issued.session.refresh_from_db()
        self.assertIsNotNone(issued.session.revoked_at)
        self.assertEqual(
            UsedRefreshToken.objects.filter(
                token_digest=digest_token(issued.refresh_token),
            ).count(),
            1,
        )
