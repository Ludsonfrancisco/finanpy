from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user

from .models import CreditCard, CreditCardInvoice
from .services import (
    calculate_card_metrics,
    calculate_target_invoice_for_purchase,
    create_card_expense,
    get_safe_date,
    pay_card_invoice,
    reopen_card_invoice,
    resolve_or_create_invoice,
)

User = get_user_model()


class CreditCardDomainServicesTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='cards-test@example.com',
            password='testpassword123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner_shared = FinancialOwner.objects.get(
            household=self.household, type='shared'
        )
        self.owner_self = FinancialOwner.objects.get(
            household=self.household, type='self'
        )

        self.card = CreditCard.objects.create(
            household=self.household,
            user=self.user,
            financial_owner=self.owner_shared,
            name='Nubank Black',
            limit=Decimal('5000.00'),
            closing_day=10,
            due_day=17,
            color='#820AD1',
            brand='mastercard',
            last_digits='1234',
            is_active=True,
        )

        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Eletrônicos',
            type='expense',
        )

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner_shared,
            name='Conta Corrente Itaú',
            type=Account.CHECKING,
            initial_balance=Decimal('10000.00'),
        )

    def test_safe_date_calculation_for_short_months(self):
        # Fevereiro em ano não bissexto (max 28 dias)
        feb_date = get_safe_date(2025, 2, 31)
        self.assertEqual(feb_date, date(2025, 2, 28))

        # Fevereiro em ano bissexto (max 29 dias)
        leap_feb_date = get_safe_date(2024, 2, 31)
        self.assertEqual(leap_feb_date, date(2024, 2, 29))

        # Abril (30 dias)
        apr_date = get_safe_date(2026, 4, 31)
        self.assertEqual(apr_date, date(2026, 4, 30))

    def test_purchase_best_day_allocation(self):
        # Compra antes do dia 10 (fechamento) -> entra na fatura do próprio mês (08/2026)
        m1, y1 = calculate_target_invoice_for_purchase(self.card, date(2026, 8, 5))
        self.assertEqual((m1, y1), (8, 2026))

        # Compra no dia 10 (fechamento) -> entra na fatura do mês seguinte (09/2026)
        m2, y2 = calculate_target_invoice_for_purchase(self.card, date(2026, 8, 10))
        self.assertEqual((m2, y2), (9, 2026))

        # Compra após o dia 10 -> entra na fatura do mês seguinte (09/2026)
        m3, y3 = calculate_target_invoice_for_purchase(self.card, date(2026, 8, 20))
        self.assertEqual((m3, y3), (9, 2026))

        # Compra em dezembro após o fechamento -> fatura de janeiro do ano seguinte
        m4, y4 = calculate_target_invoice_for_purchase(self.card, date(2026, 12, 15))
        self.assertEqual((m4, y4), (1, 2027))

    def test_installment_creation_with_exact_penny_distribution(self):
        # R$ 100,00 parcelado em 3x (dízima 33.333...)
        expenses = create_card_expense(
            credit_card=self.card,
            description='Notebook Parcelado',
            total_amount=Decimal('100.00'),
            purchase_date=date(2026, 8, 5),
            category=self.category,
            installments_count=3,
            financial_owner=self.owner_self,
            user=self.user,
        )

        self.assertEqual(len(expenses), 3)

        # 1ª parcela absorve 1 centavo residual
        self.assertEqual(expenses[0].amount, Decimal('33.34'))
        self.assertEqual(expenses[0].installment_number, 1)
        self.assertEqual(expenses[0].invoice.month, 8)
        self.assertEqual(expenses[0].invoice.year, 2026)

        # 2ª parcela
        self.assertEqual(expenses[1].amount, Decimal('33.33'))
        self.assertEqual(expenses[1].installment_number, 2)
        self.assertEqual(expenses[1].invoice.month, 9)
        self.assertEqual(expenses[1].invoice.year, 2026)

        # 3ª parcela
        self.assertEqual(expenses[2].amount, Decimal('33.33'))
        self.assertEqual(expenses[2].installment_number, 3)
        self.assertEqual(expenses[2].invoice.month, 10)
        self.assertEqual(expenses[2].invoice.year, 2026)

        # Soma total exatamente igual a 100.00
        total_sum = sum(e.amount for e in expenses)
        self.assertEqual(total_sum, Decimal('100.00'))

    def test_limit_calculation_and_available_balance(self):
        # Compra de R$ 1.500,00
        create_card_expense(
            credit_card=self.card,
            description='Smartphone',
            total_amount=Decimal('1500.00'),
            purchase_date=date(2026, 8, 2),
            category=self.category,
            installments_count=3,
            user=self.user,
        )

        metrics = calculate_card_metrics(
            self.card, reference_month=8, reference_year=2026
        )
        self.assertEqual(metrics['unpaid_expenses_total'], Decimal('1500.00'))
        self.assertEqual(metrics['available_limit'], Decimal('3500.00'))  # 5000 - 1500
        self.assertEqual(
            metrics['current_invoice_total'], Decimal('500.00')
        )  # 1ª parcela

    def test_pay_and_reopen_invoice(self):
        create_card_expense(
            credit_card=self.card,
            description='Monitor 4K',
            total_amount=Decimal('2000.00'),
            purchase_date=date(2026, 8, 2),
            category=self.category,
            installments_count=1,
            user=self.user,
        )

        invoice = resolve_or_create_invoice(self.card, 8, 2026)
        self.assertIn(
            invoice.status,
            [
                CreditCardInvoice.STATUS_OPEN,
                CreditCardInvoice.STATUS_OVERDUE,
                CreditCardInvoice.STATUS_CLOSED,
            ],
        )

        # Pagar fatura
        paid_invoice = pay_card_invoice(
            invoice=invoice,
            payment_account=self.account,
            paid_amount=Decimal('2000.00'),
            payment_date=date(2026, 8, 17),
        )

        self.assertEqual(paid_invoice.status, CreditCardInvoice.STATUS_PAID)
        self.assertIsNotNone(paid_invoice.payment_transaction)
        self.assertEqual(paid_invoice.payment_transaction.amount, Decimal('2000.00'))
        self.assertEqual(paid_invoice.payment_transaction.account, self.account)

        # Limite liberado após pagamento da fatura
        metrics = calculate_card_metrics(
            self.card, reference_month=8, reference_year=2026
        )
        self.assertEqual(metrics['unpaid_expenses_total'], Decimal('0.00'))
        self.assertEqual(metrics['available_limit'], Decimal('5000.00'))

        # Estornar fatura
        reopened_invoice = reopen_card_invoice(paid_invoice)
        self.assertIn(
            reopened_invoice.status,
            [
                CreditCardInvoice.STATUS_OPEN,
                CreditCardInvoice.STATUS_CLOSED,
                CreditCardInvoice.STATUS_OVERDUE,
            ],
        )
        self.assertIsNone(reopened_invoice.payment_transaction)
