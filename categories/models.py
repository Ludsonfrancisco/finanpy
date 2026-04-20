from django.conf import settings
from django.db import models


class Category(models.Model):
    INCOME = 'income'
    EXPENSE = 'expense'

    TYPE_CHOICES = [
        (INCOME, 'Receita'),
        (EXPENSE, 'Despesa'),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='categories',
        verbose_name='usuário',
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
        unique_together = ('user', 'name', 'type')

    def __str__(self):
        return f'{self.name} ({self.get_type_display()})'
