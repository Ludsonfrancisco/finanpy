import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from .models import DeviceSession, UsedRefreshToken

ACCESS_LIFETIME = timedelta(minutes=15)
REFRESH_LIFETIME = timedelta(days=30)


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


def rotate_refresh_token(raw_token: str) -> IssuedTokens:
    token_digest = digest_token(raw_token)
    reused = False
    issued = None

    with transaction.atomic():
        used_token = (
            UsedRefreshToken.objects.select_for_update()
            .select_related('session')
            .filter(token_digest=token_digest)
            .first()
        )
        if used_token is not None:
            revoke_session(used_token.session)
            reused = True
        else:
            session = (
                DeviceSession.objects.select_for_update()
                .filter(refresh_token_digest=token_digest)
                .first()
            )
            now = timezone.now()
            if (
                session is None
                or session.revoked_at is not None
                or session.refresh_expires_at <= now
            ):
                raise InvalidRefreshTokenError('Refresh token inválido, expirado ou revogado.')

            access_token = new_token()
            refresh_token = new_token()
            UsedRefreshToken.objects.create(
                session=session,
                token_digest=token_digest,
                used_at=now,
                expires_at=session.refresh_expires_at,
            )
            session.access_token_digest = digest_token(access_token)
            session.access_expires_at = now + ACCESS_LIFETIME
            session.refresh_token_digest = digest_token(refresh_token)
            session.refresh_expires_at = now + REFRESH_LIFETIME
            session.last_seen_at = now
            session.save()
            issued = IssuedTokens(
                session=session,
                access_token=access_token,
                refresh_token=refresh_token,
            )

    if reused:
        raise RefreshReuseError('Reutilização de refresh token detectada.')
    return issued


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
