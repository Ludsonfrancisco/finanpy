import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class Category(models.Model):
    INCOME = 'income'
    EXPENSE = 'expense'

    TYPE_CHOICES = [
        (INCOME, 'Receita'),
        (EXPENSE, 'Despesa'),
    ]

    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    sync_version = models.PositiveBigIntegerField(default=1, editable=False)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='categories',
        verbose_name='usuário',
    )
    household = models.ForeignKey(
        'households.Household',
        on_delete=models.PROTECT,
        related_name='categories',
    )
    name = models.CharField(max_length=100, verbose_name='nome')
    type = models.CharField(
        max_length=10,
        choices=TYPE_CHOICES,
        default=EXPENSE,
        verbose_name='tipo',
    )
    color = models.CharField(
        max_length=7,
        default='#10b981',
        verbose_name='cor',
    )
    icon = models.CharField(
        max_length=50,
        blank=True,
        null=True,
        verbose_name='ícone',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'categoria'
        verbose_name_plural = 'categorias'
        ordering = ['name']
        constraints = [
            models.UniqueConstraint(
                fields=['household', 'name', 'type'],
                name='unique_category_per_household_name_type',
            )
        ]

    def __str__(self):
        return f'{self.name} ({self.get_type_display()})'

    def clean(self):
        super().clean()
        if self.user_id and self.household_id:
            from households.validators import has_active_household_membership

            if not has_active_household_membership(
                user_id=self.user_id,
                household_id=self.household_id,
            ):
                raise ValidationError(
                    {'user': 'Usuário sem associação ativa neste Lar.'}
                )
