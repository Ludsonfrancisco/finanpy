import uuid

from django.conf import settings
from django.db import models


class Household(models.Model):
    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    name = models.CharField(max_length=120, default='Lar Finance')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name', 'pk']

    def __str__(self):
        return self.name


class HouseholdMembership(models.Model):
    ADMIN = 'admin'
    ROLE_CHOICES = [(ADMIN, 'Administrador')]

    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='memberships',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='household_memberships',
    )
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default=ADMIN)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['household', 'user'],
                name='unique_household_membership',
            ),
            models.UniqueConstraint(
                fields=['user'],
                condition=models.Q(is_active=True),
                name='unique_active_household_membership_user',
            ),
        ]


class FinancialOwner(models.Model):
    SELF = 'self'
    SPOUSE = 'spouse'
    SHARED = 'shared'
    TYPE_CHOICES = [
        (SELF, 'Eu'),
        (SPOUSE, 'Esposa'),
        (SHARED, 'Conjunto'),
    ]

    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='financial_owners',
    )
    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    type = models.CharField(max_length=20, choices=TYPE_CHOICES)
    name = models.CharField(max_length=80)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['household_id', 'type']
        constraints = [
            models.UniqueConstraint(
                fields=['household', 'type'],
                name='unique_financial_owner_type_per_household',
            )
        ]

    def __str__(self):
        return self.name
