from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner, Household
from transactions.models import Transaction


class RecurringBill(models.Model):
    EXPENSE = 'expense'
    INCOME = 'income'
    TYPE_CHOICES = [
        (EXPENSE, 'Despesa'),
        (INCOME, 'Receita'),
    ]

    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='recurring_bills',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='recurring_bills',
    )
    financial_owner = models.ForeignKey(
        FinancialOwner,
        on_delete=models.CASCADE,
        related_name='recurring_bills',
    )
    name = models.CharField('Nome da Conta / Compromisso', max_length=150)
    amount = models.DecimalField(
        'Valor Base (R$)',
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(0.01)],
    )
    due_day = models.PositiveSmallIntegerField(
        'Dia do Vencimento',
        validators=[MinValueValidator(1), MaxValueValidator(31)],
        help_text='Dia do mês em que esta conta costuma vencer (1 a 31)',
    )
    type = models.CharField(
        'Tipo',
        max_length=10,
        choices=TYPE_CHOICES,
        default=EXPENSE,
    )
    category = models.ForeignKey(
        Category,
        on_delete=models.PROTECT,
        related_name='recurring_bills',
        verbose_name='Categoria',
    )
    default_account = models.ForeignKey(
        Account,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='recurring_bills',
        verbose_name='Conta Bancária Padrão',
        help_text='Conta bancária sugerida para débito',
    )
    is_active = models.BooleanField('Ativa?', default=True)
    notes = models.TextField('Observações', blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['due_day', 'name']
        verbose_name = 'Conta Fixa / Recorrente'
        verbose_name_plural = 'Contas Fixas & Recorrentes'

    def __str__(self):
        return f'{self.name} (Dia {self.due_day}) — R$ {self.amount}'


class BillInstance(models.Model):
    STATUS_PENDING = 'pending'
    STATUS_PAID = 'paid'
    STATUS_SKIPPED = 'skipped'
    STATUS_CHOICES = [
        (STATUS_PENDING, 'Pendente'),
        (STATUS_PAID, 'Paga'),
        (STATUS_SKIPPED, 'Ignorada'),
    ]

    bill = models.ForeignKey(
        RecurringBill,
        on_delete=models.CASCADE,
        related_name='instances',
    )
    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='bill_instances',
    )
    financial_owner = models.ForeignKey(
        FinancialOwner,
        on_delete=models.CASCADE,
        related_name='bill_instances',
    )
    month = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(12)]
    )
    year = models.PositiveIntegerField()
    due_date = models.DateField('Data de Vencimento')
    amount = models.DecimalField(
        'Valor do Mês (R$)',
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(0.01)],
    )
    status = models.CharField(
        'Status',
        max_length=15,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
    )
    paid_at = models.DateField('Data do Pagamento', null=True, blank=True)
    account = models.ForeignKey(
        Account,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='paid_bill_instances',
        verbose_name='Conta Debitada',
    )
    transaction = models.ForeignKey(
        Transaction,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='bill_instance',
        verbose_name='Transação Vinculada',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['due_date', 'bill__name']
        unique_together = ('bill', 'month', 'year')
        verbose_name = 'Instância Mensal de Conta'
        verbose_name_plural = 'Instâncias Mensais de Contas'

    def __str__(self):
        return f'{self.bill.name} - {self.month:02d}/{self.year} ({self.get_status_display()})'
