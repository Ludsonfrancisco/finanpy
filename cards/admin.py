from django.contrib import admin

from .models import CreditCard, CreditCardExpense, CreditCardInvoice


@admin.register(CreditCard)
class CreditCardAdmin(admin.ModelAdmin):
    list_display = [
        'name',
        'household',
        'financial_owner',
        'limit',
        'closing_day',
        'due_day',
        'brand',
        'is_active',
    ]
    list_filter = ['is_active', 'brand', 'household']
    search_fields = ['name', 'last_digits']


@admin.register(CreditCardInvoice)
class CreditCardInvoiceAdmin(admin.ModelAdmin):
    list_display = [
        'credit_card',
        'month',
        'year',
        'status',
        'closing_date',
        'due_date',
        'paid_amount',
        'paid_at',
    ]
    list_filter = ['status', 'year', 'month']
    search_fields = ['credit_card__name']


@admin.register(CreditCardExpense)
class CreditCardExpenseAdmin(admin.ModelAdmin):
    list_display = [
        'description',
        'credit_card',
        'amount',
        'date',
        'installment_number',
        'installments_count',
        'category',
    ]
    list_filter = ['category', 'date', 'credit_card']
    search_fields = ['description', 'credit_card__name']
