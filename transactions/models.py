from django.conf import settings
from django.core.exceptions import ValidationError
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
    household = models.ForeignKey(
        'households.Household',
        on_delete=models.PROTECT,
        related_name='transactions',
        null=True,
        blank=True,
    )
    financial_owner = models.ForeignKey(
        'households.FinancialOwner',
        on_delete=models.PROTECT,
        related_name='transactions',
        null=True,
        blank=True,
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

    def clean(self):
        super().clean()
        errors = {}
        if self.household_id and self.account_id and self.account.household_id != self.household_id:
            errors['account'] = 'Conta pertence a outro Lar.'
        if self.household_id and self.category_id and self.category.household_id != self.household_id:
            errors['category'] = 'Categoria pertence a outro Lar.'
        if (
            self.household_id
            and self.financial_owner_id
            and self.financial_owner.household_id != self.household_id
        ):
            errors['financial_owner'] = 'Responsável pertence a outro Lar.'
        if errors:
            raise ValidationError(errors)
