from django.conf import settings
from django.db import models


class Transaction(models.Model):
    INCOME = 'income'
    EXPENSE = 'expense'

    TYPE_CHOICES = [
        (INCOME, 'Receita'),
        (EXPENSE, 'Despesa'),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='transactions',
        verbose_name='usuário',
    )
    account = models.ForeignKey(
        'accounts.Account',
        on_delete=models.CASCADE,
        related_name='transactions',
        verbose_name='conta',
    )
    category = models.ForeignKey(
        'categories.Category',
        on_delete=models.CASCADE,
        related_name='transactions',
        verbose_name='categoria',
    )
    description = models.CharField(max_length=255, verbose_name='descrição')
    amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        verbose_name='valor',
    )
    date = models.DateField(verbose_name='data')
    type = models.CharField(
        max_length=10,
        choices=TYPE_CHOICES,
        default=EXPENSE,
        verbose_name='tipo',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'transação'
        verbose_name_plural = 'transações'
        ordering = ['-date', '-created_at']

    def __str__(self):
        return f'{self.description} - {self.amount}'
