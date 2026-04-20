from django.contrib import admin

from .models import Account


@admin.register(Account)
class AccountAdmin(admin.ModelAdmin):
    list_display = ('name', 'type', 'user', 'initial_balance', 'currency', 'created_at')
    list_filter = ('type', 'currency')
    search_fields = ('name', 'user__email')
