import uuid
from decimal import Decimal

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner, Household
from transactions.models import Transaction


class CreditCard(models.Model):
    BRAND_VISA = 'visa'
    BRAND_MASTERCARD = 'mastercard'
    BRAND_ELO = 'elo'
    BRAND_AMEX = 'amex'
    BRAND_HIPERCARD = 'hipercard'
    BRAND_OTHER = 'other'

    BRAND_CHOICES = [
        (BRAND_VISA, 'Visa'),
        (BRAND_MASTERCARD, 'Mastercard'),
        (BRAND_ELO, 'Elo'),
        (BRAND_AMEX, 'American Express'),
        (BRAND_HIPERCARD, 'Hipercard'),
        (BRAND_OTHER, 'Outro'),
    ]

    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='credit_cards',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='credit_cards',
    )
    financial_owner = models.ForeignKey(
        FinancialOwner,
        on_delete=models.CASCADE,
        related_name='credit_cards',
    )
    name = models.CharField('Nome do Cartão', max_length=120)
    limit = models.DecimalField(
        'Limite Total (R$)',
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    closing_day = models.PositiveSmallIntegerField(
        'Dia do Fechamento',
        validators=[MinValueValidator(1), MaxValueValidator(31)],
        help_text='Dia do mês em que a fatura fecha (1 a 31)',
    )
    due_day = models.PositiveSmallIntegerField(
        'Dia do Vencimento',
        validators=[MinValueValidator(1), MaxValueValidator(31)],
        help_text='Dia do mês em que a fatura vence (1 a 31)',
    )
    color = models.CharField('Cor (Hex)', max_length=20, default='#2F756A')
    brand = models.CharField(
        'Bandeira', max_length=30, choices=BRAND_CHOICES, default=BRAND_VISA
    )
    last_digits = models.CharField(
        'Últimos 4 Dígitos', max_length=4, blank=True, default=''
    )
    is_active = models.BooleanField('Ativo', default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'cartão de crédito'
        verbose_name_plural = 'cartões de crédito'
        ordering = ['name']

    def __str__(self):
        digits = f' (•••• {self.last_digits})' if self.last_digits else ''
        return f'{self.name}{digits}'


class CreditCardInvoice(models.Model):
    STATUS_OPEN = 'open'
    STATUS_CLOSED = 'closed'
    STATUS_PAID = 'paid'
    STATUS_OVERDUE = 'overdue'

    STATUS_CHOICES = [
        (STATUS_OPEN, 'Aberta'),
        (STATUS_CLOSED, 'Fechada'),
        (STATUS_PAID, 'Paga'),
        (STATUS_OVERDUE, 'Atrasada'),
    ]

    credit_card = models.ForeignKey(
        CreditCard,
        on_delete=models.CASCADE,
        related_name='invoices',
    )
    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='credit_card_invoices',
    )
    month = models.PositiveSmallIntegerField(
        'Mês de Referência',
        validators=[MinValueValidator(1), MaxValueValidator(12)],
    )
    year = models.PositiveSmallIntegerField('Ano de Referência')
    closing_date = models.DateField('Data de Fechamento')
    due_date = models.DateField('Data de Vencimento')
    status = models.CharField(
        'Status', max_length=15, choices=STATUS_CHOICES, default=STATUS_OPEN
    )
    paid_amount = models.DecimalField(
        'Valor Pago (R$)',
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
    )
    paid_at = models.DateTimeField('Pago em', null=True, blank=True)
    payment_account = models.ForeignKey(
        Account,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='card_invoice_payments',
        verbose_name='Conta de Débito',
    )
    payment_transaction = models.ForeignKey(
        Transaction,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='card_invoice',
        verbose_name='Transação Financeira de Pagamento',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'fatura de cartão'
        verbose_name_plural = 'faturas de cartão'
        unique_together = ('credit_card', 'month', 'year')
        ordering = ['-year', '-month']

    def __str__(self):
        return f'Fatura {self.month:02d}/{self.year} - {self.credit_card.name}'

    @property
    def total_amount(self):
        total = self.expenses.aggregate(total=models.Sum('amount'))['total']
        return total or Decimal('0.00')


class CreditCardExpense(models.Model):
    credit_card = models.ForeignKey(
        CreditCard,
        on_delete=models.CASCADE,
        related_name='expenses',
    )
    invoice = models.ForeignKey(
        CreditCardInvoice,
        on_delete=models.CASCADE,
        related_name='expenses',
    )
    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='credit_card_expenses',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='credit_card_expenses',
    )
    financial_owner = models.ForeignKey(
        FinancialOwner,
        on_delete=models.CASCADE,
        related_name='credit_card_expenses',
    )
    category = models.ForeignKey(
        Category,
        on_delete=models.PROTECT,
        related_name='credit_card_expenses',
        verbose_name='Categoria',
    )
    description = models.CharField('Descrição', max_length=200)
    amount = models.DecimalField(
        'Valor da Parcela (R$)',
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    date = models.DateField('Data da Compra')
    installments_count = models.PositiveSmallIntegerField(
        'Total de Parcelas',
        default=1,
        validators=[MinValueValidator(1), MaxValueValidator(48)],
    )
    installment_number = models.PositiveSmallIntegerField(
        'Número da Parcela',
        default=1,
        validators=[MinValueValidator(1), MaxValueValidator(48)],
    )
    installment_group_id = models.UUIDField(default=uuid.uuid4, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'despesa no cartão'
        verbose_name_plural = 'despesas no cartão'
        ordering = ['-date', '-created_at']

    def __str__(self):
        installment_info = (
            f' ({self.installment_number}/{self.installments_count})'
            if self.installments_count > 1
            else ''
        )
        return f'{self.description}{installment_info} - R$ {self.amount}'
