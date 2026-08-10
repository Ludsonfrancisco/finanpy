from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.exceptions import APIException, AuthenticationFailed

from households.models import FinancialOwner, HouseholdMembership

from .models import DeviceSession
from .tokens import digest_token, revoke_session


class InvalidToken(AuthenticationFailed):
    default_detail = 'Token de acesso inválido.'
    default_code = 'invalid_token'


class ExpiredToken(AuthenticationFailed):
    default_detail = 'Token de acesso expirado.'
    default_code = 'expired_token'


class RevokedDevice(AuthenticationFailed):
    default_detail = 'A sessão deste aparelho foi revogada.'
    default_code = 'revoked_device'


class InvalidCredentials(APIException):
    status_code = status.HTTP_401_UNAUTHORIZED
    default_detail = 'E-mail ou senha inválidos.'
    default_code = 'invalid_credentials'


class InvalidRefreshToken(APIException):
    status_code = status.HTTP_401_UNAUTHORIZED
    default_detail = 'Refresh token inválido, expirado ou revogado.'
    default_code = 'invalid_refresh_token'


class DeviceTokenAuthentication(BaseAuthentication):
    keyword = b'Bearer'
    last_seen_interval = timedelta(minutes=5)

    def authenticate(self, request):
        authorization = get_authorization_header(request)
        if not authorization:
            return None

        parts = authorization.split()
        if not parts:
            return None
        if parts[0] != self.keyword:
            return None
        if len(parts) != 2:
            raise InvalidToken()
        if authorization != self.keyword + b' ' + parts[1]:
            raise InvalidToken()

        try:
            raw_token = parts[1].decode('ascii')
        except UnicodeDecodeError as exc:
            raise InvalidToken() from exc

        session = (
            DeviceSession.objects.select_related('user', 'household', 'default_owner')
            .filter(access_token_digest=digest_token(raw_token))
            .first()
        )
        if session is None:
            raise InvalidToken()

        now = timezone.now()
        if session.revoked_at is not None:
            raise RevokedDevice()
        if session.access_expires_at <= now:
            raise ExpiredToken()
        if not self._has_active_scope(session):
            revoke_session(session)
            raise RevokedDevice()

        cutoff = now - self.last_seen_interval
        if session.last_seen_at < cutoff:
            updated = DeviceSession.objects.filter(
                pk=session.pk,
                revoked_at__isnull=True,
                last_seen_at__lt=cutoff,
            ).update(last_seen_at=now)
            if updated:
                session.last_seen_at = now

        return session.user, session

    def authenticate_header(self, request):
        return self.keyword.decode('ascii')

    @staticmethod
    def _has_active_scope(session):
        owner = session.default_owner
        owner_is_valid = (
            owner.household_id == session.household_id
            and owner.is_active
            and owner.type in (FinancialOwner.SELF, FinancialOwner.SPOUSE)
        )
        return (
            session.user.is_active
            and session.household.is_active
            and owner_is_valid
            and HouseholdMembership.objects.filter(
                user_id=session.user_id,
                household_id=session.household_id,
                is_active=True,
            ).exists()
        )
