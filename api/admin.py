from django.contrib import admin

from .models import DeviceSession, UsedRefreshToken


@admin.register(DeviceSession)
class DeviceSessionAdmin(admin.ModelAdmin):
    list_display = ('uuid', 'user', 'household', 'platform', 'name', 'revoked_at', 'last_seen_at')
    list_filter = ('platform', 'revoked_at')
    search_fields = ('uuid', 'user__email', 'household__name', 'name')
    readonly_fields = ('uuid', 'created_at', 'updated_at')


@admin.register(UsedRefreshToken)
class UsedRefreshTokenAdmin(admin.ModelAdmin):
    list_display = ('session', 'used_at', 'expires_at')
    readonly_fields = ('session', 'token_digest', 'used_at', 'expires_at')
