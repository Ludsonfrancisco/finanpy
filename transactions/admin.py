from django.contrib import admin

from .models import Transaction


@admin.register(Transaction)
class TransactionAdmin(admin.ModelAdmin):
    list_display = ('description', 'amount', 'type', 'account', 'category', 'date', 'user', 'created_at')
    list_filter = ('type', 'account', 'category', 'date')
    search_fields = ('description',)
