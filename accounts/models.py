from decimal import Decimal

from django.conf import settings
from django.db import models
from django.db.models import Q, Sum


class Account(models.Model):
    CHECKING = 'checking'
    SAVINGS = 'savings'
    CASH = 'cash'
    CREDIT = 'credit'
    INVESTMENT = 'investment'
    OTHER = 'other'

    TYPE_CHOICES = [
        (CHECKING, 'Conta corrente'),
        (SAVINGS, 'Poupança'),
        (CASH, 'Dinheiro'),
        (CREDIT, 'Cartão de crédito'),
        (INVESTMENT, 'Investimento'),
        (OTHER, 'Outro'),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='accounts',
        verbose_name='usuário',
    )
    name = models.CharField(max_length=120, verbose_name='nome')
    type = models.CharField(
        max_length=20,
        choices=TYPE_CHOICES,
        default=CHECKING,
        verbose_name='tipo',
    )
    initial_balance = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        default=Decimal('0.00'),
        verbose_name='saldo inicial',
    )
    currency = models.CharField(max_length=3, default='BRL', verbose_name='moeda')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'conta'
        verbose_name_plural = 'contas'
        ordering = ['name']

    def __str__(self):
        return self.name

    @property
    def current_balance(self):
        try:
            agg = self.transactions.aggregate(
                total_income=Sum('amount', filter=Q(type='income')),
                total_expense=Sum('amount', filter=Q(type='expense')),
            )
            income = agg['total_income'] or Decimal('0.00')
            expense = agg['total_expense'] or Decimal('0.00')
            return self.initial_balance + income - expense
        except AttributeError:
            return self.initial_balance
