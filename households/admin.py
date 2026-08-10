from django.contrib import admin

from .models import FinancialOwner, Household, HouseholdMembership


@admin.register(Household)
class HouseholdAdmin(admin.ModelAdmin):
    list_display = ('name', 'uuid', 'is_active', 'created_at')
    list_filter = ('is_active',)
    search_fields = ('name', 'uuid')


@admin.register(HouseholdMembership)
class HouseholdMembershipAdmin(admin.ModelAdmin):
    list_display = ('household', 'role', 'is_active', 'created_at')
    list_filter = ('role', 'is_active')
    search_fields = ('household__name',)


@admin.register(FinancialOwner)
class FinancialOwnerAdmin(admin.ModelAdmin):
    list_display = ('name', 'type', 'household', 'is_active')
    list_filter = ('type', 'is_active')
    search_fields = ('name', 'uuid', 'household__name')
