import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone


class DeviceSession(models.Model):
    WINDOWS = 'windows'
    IOS = 'ios'
    ANDROID = 'android'
    PLATFORM_CHOICES = [(WINDOWS, 'Windows'), (IOS, 'iOS'), (ANDROID, 'Android')]

    uuid = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='device_sessions',
    )
    household = models.ForeignKey(
        'households.Household',
        on_delete=models.PROTECT,
        related_name='device_sessions',
    )
    default_owner = models.ForeignKey(
        'households.FinancialOwner',
        on_delete=models.PROTECT,
        related_name='device_sessions',
    )
    platform = models.CharField(max_length=16, choices=PLATFORM_CHOICES)
    name = models.CharField(max_length=80)
    access_token_digest = models.CharField(max_length=64, unique=True)
    access_expires_at = models.DateTimeField()
    refresh_token_digest = models.CharField(max_length=64, unique=True)
    refresh_expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)
    last_seen_at = models.DateTimeField(default=timezone.now)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        super().clean()
        errors = {}

        if self.user_id and self.household_id:
            has_active_membership = self.user.household_memberships.filter(
                household_id=self.household_id,
                household__is_active=True,
                is_active=True,
            ).exists()
            if not has_active_membership:
                errors['household'] = 'O usuário não possui membership ativo neste Lar.'

        if self.default_owner_id and self.household_id:
            if self.default_owner.household_id != self.household_id:
                errors['default_owner'] = 'O responsável padrão deve pertencer ao mesmo Lar.'
            elif self.default_owner.type == self.default_owner.SHARED:
                errors['default_owner'] = 'O responsável conjunto não pode ser o padrão do aparelho.'

        if errors:
            raise ValidationError(errors)


class UsedRefreshToken(models.Model):
    session = models.ForeignKey(
        DeviceSession,
        on_delete=models.PROTECT,
        related_name='used_refresh_tokens',
    )
    token_digest = models.CharField(max_length=64, unique=True)
    used_at = models.DateTimeField()
    expires_at = models.DateTimeField()
