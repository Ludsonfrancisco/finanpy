from django.contrib import admin

from .models import Profile


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'first_name', 'last_name', 'birth_date', 'created_at')
    list_filter = ('created_at',)
    search_fields = ('user__email', 'first_name', 'last_name')
