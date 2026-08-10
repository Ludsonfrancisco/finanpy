import hashlib
import hmac
import secrets
import time
from dataclasses import dataclass
from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import IntegrityError, OperationalError, connection, transaction
from django.utils import timezone

from .models import DeviceSession, UsedRefreshToken

ACCESS_LIFETIME = timedelta(minutes=15)
REFRESH_LIFETIME = timedelta(days=30)
SQLITE_LOCK_RETRIES = 5
SQLITE_LOCK_RETRY_DELAY = 0.01


class InvalidRefreshTokenError(ValueError):
    pass


class RefreshReuseError(InvalidRefreshTokenError):
    pass


@dataclass(frozen=True)
class IssuedTokens:
    session: DeviceSession
    access_token: str
    refresh_token: str


def digest_token(raw_token: str) -> str:
    return hmac.new(
        settings.SECRET_KEY.encode('utf-8'),
        raw_token.encode('utf-8'),
        hashlib.sha256,
    ).hexdigest()


def new_token() -> str:
    return secrets.token_urlsafe(48)


@transaction.atomic
def issue_session(*, user, household, default_owner, platform: str, name: str) -> IssuedTokens:
    now = timezone.now()
    access_token = new_token()
    refresh_token = new_token()
    session = DeviceSession(
        user=user,
        household=household,
        default_owner=default_owner,
        platform=platform,
        name=name,
        access_token_digest=digest_token(access_token),
        access_expires_at=now + ACCESS_LIFETIME,
        refresh_token_digest=digest_token(refresh_token),
        refresh_expires_at=now + REFRESH_LIFETIME,
        last_seen_at=now,
    )
    session.full_clean()
    session.save(force_insert=True)
    return IssuedTokens(
        session=session,
        access_token=access_token,
        refresh_token=refresh_token,
    )


def _revoke_if_used(token_digest: str) -> bool:
    with transaction.atomic():
        used_token = (
            UsedRefreshToken.objects.select_for_update()
            .select_related('session')
            .filter(token_digest=token_digest)
            .first()
        )
        if used_token is None:
            return False
        revoke_session(used_token.session)
        return True


def _claim_refresh_token(
    *,
    session: DeviceSession,
    old_token_digest: str,
    access_token_digest: str,
    refresh_token_digest: str,
    now,
) -> bool:
    with transaction.atomic():
        updated = DeviceSession.objects.filter(
            pk=session.pk,
            refresh_token_digest=old_token_digest,
            refresh_expires_at__gt=now,
            revoked_at__isnull=True,
            user__is_active=True,
            household__is_active=True,
            household__memberships__user_id=session.user_id,
            household__memberships__is_active=True,
            default_owner__household_id=session.household_id,
            default_owner__is_active=True,
            default_owner__type__in=(
                session.default_owner.SELF,
                session.default_owner.SPOUSE,
            ),
        ).update(
            access_token_digest=access_token_digest,
            access_expires_at=now + ACCESS_LIFETIME,
            refresh_token_digest=refresh_token_digest,
            refresh_expires_at=now + REFRESH_LIFETIME,
            last_seen_at=now,
            updated_at=now,
        )
        if not updated:
            return False
        UsedRefreshToken.objects.create(
            session=session,
            token_digest=old_token_digest,
            used_at=now,
            expires_at=session.refresh_expires_at,
        )
        return True


def _is_transient_sqlite_lock(exc: OperationalError) -> bool:
    return connection.vendor == 'sqlite' and 'locked' in str(exc).lower()


def rotate_refresh_token(raw_token: str) -> IssuedTokens:
    token_digest = digest_token(raw_token)
    if _revoke_if_used(token_digest):
        raise RefreshReuseError('Reutilização de refresh token detectada.')

    session = (
        DeviceSession.objects.select_related('user', 'household', 'default_owner')
        .filter(refresh_token_digest=token_digest)
        .first()
    )
    if session is None:
        if _revoke_if_used(token_digest):
            raise RefreshReuseError('Reutilização de refresh token detectada.')
        raise InvalidRefreshTokenError('Refresh token inválido, expirado ou revogado.')

    now = timezone.now()
    if session.revoked_at is not None or session.refresh_expires_at <= now:
        raise InvalidRefreshTokenError('Refresh token inválido, expirado ou revogado.')

    try:
        session.clean()
    except ValidationError:
        revoke_session(session)
        raise InvalidRefreshTokenError('Escopo da sessão inválido ou inativo.')

    access_token = new_token()
    refresh_token = new_token()
    access_token_digest = digest_token(access_token)
    refresh_token_digest = digest_token(refresh_token)

    for attempt in range(SQLITE_LOCK_RETRIES):
        try:
            claimed = _claim_refresh_token(
                session=session,
                old_token_digest=token_digest,
                access_token_digest=access_token_digest,
                refresh_token_digest=refresh_token_digest,
                now=now,
            )
        except OperationalError as exc:
            if not _is_transient_sqlite_lock(exc) or attempt == SQLITE_LOCK_RETRIES - 1:
                raise
            time.sleep(SQLITE_LOCK_RETRY_DELAY)
            continue
        except IntegrityError:
            if _revoke_if_used(token_digest):
                raise RefreshReuseError('Reutilização de refresh token detectada.')
            raise

        if claimed:
            session.access_token_digest = access_token_digest
            session.access_expires_at = now + ACCESS_LIFETIME
            session.refresh_token_digest = refresh_token_digest
            session.refresh_expires_at = now + REFRESH_LIFETIME
            session.last_seen_at = now
            session.updated_at = now
            return IssuedTokens(
                session=session,
                access_token=access_token,
                refresh_token=refresh_token,
            )

        if _revoke_if_used(token_digest):
            raise RefreshReuseError('Reutilização de refresh token detectada.')
        revoke_session(session)
        raise InvalidRefreshTokenError('Escopo da sessão inválido ou inativo.')

    raise InvalidRefreshTokenError('Refresh token inválido, expirado ou revogado.')


def revoke_session(session: DeviceSession) -> None:
    if session.revoked_at is not None:
        return
    now = timezone.now()
    updated = DeviceSession.objects.filter(
        pk=session.pk,
        revoked_at__isnull=True,
    ).update(revoked_at=now, updated_at=now)
    if updated:
        session.revoked_at = now
        session.updated_at = now
