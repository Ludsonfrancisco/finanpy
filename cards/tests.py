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


SAMPLE_CARD_OFX = b"""OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:1252
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX>
  <SIGNONMSGSRSV1>
    <SONRS>
      <STATUS>
        <CODE>0
        <SEVERITY>INFO
      </STATUS>
      <DTSERVER>20260819120000[-3:BRT]
      <LANGUAGE>POR
    </SONRS>
  </SIGNONMSGSRSV1>
  <CREDITCARDMSGSRSV1>
    <CCSTMTTRNRS>
      <TRNUID>1001
      <STATUS>
        <CODE>0
        <SEVERITY>INFO
      </STATUS>
      <CCSTMTRS>
        <CURDEF>BRL
        <CCACCTFROM>
          <ACCTID>card-nubank-1234
        </CCACCTFROM>
        <BANKTRANLIST>
          <DTSTART>20260801120000[-3:BRT]
          <DTEND>20260820120000[-3:BRT]
          <STMTTRN>
            <TRNTYPE>DEBIT
            <DTPOSTED>20260805120000[-3:BRT]
            <TRNAMT>-150.50
            <FITID>card-tx-001
            <MEMO>Supermercado Pao de Acucar
          </STMTTRN>
          <STMTTRN>
            <TRNTYPE>DEBIT
            <DTPOSTED>20260815120000[-3:BRT]
            <TRNAMT>-89.90
            <FITID>card-tx-002
            <MEMO>Farmacia Drogasil
          </STMTTRN>
        </BANKTRANLIST>
      </CCSTMTRS>
    </CCSTMTTRNRS>
  </CREDITCARDMSGSRSV1>
</OFX>"""


class CreditCardOFXImportTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='card-ofx@example.com',
            password='testpassword123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner_shared = FinancialOwner.objects.get(
            household=self.household, type='shared'
        )

        self.card = CreditCard.objects.create(
            household=self.household,
            user=self.user,
            financial_owner=self.owner_shared,
            name='Nubank Roxinho',
            limit=Decimal('4000.00'),
            closing_day=10,
            due_day=17,
            color='#820AD1',
            brand='mastercard',
            last_digits='4321',
            is_active=True,
        )

        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Alimentação',
            type='expense',
        )

        self.client.force_login(self.user)

    def test_import_ofx_preview_flow(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from django.urls import reverse

        ofx_file = SimpleUploadedFile(
            'fatura.ofx', SAMPLE_CARD_OFX, content_type='application/x-ofx'
        )

        response = self.client.post(
            reverse('cards:import_ofx'),
            {
                'action': 'preview',
                'card': self.card.pk,
                'category': self.category.pk,
                'ofx_file': ofx_file,
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn('preview_data', response.context)
        preview = response.context['preview_data']
        self.assertEqual(preview['total_count'], 2)
        self.assertEqual(preview['new_count'], 2)
        self.assertEqual(preview['duplicate_count'], 0)
        self.assertEqual(Decimal(str(preview['total_amount'])), Decimal('240.40'))

    def test_import_ofx_confirm_creates_expenses_and_invoices(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from django.urls import reverse

        from cards.models import CreditCardExpense

        ofx_file = SimpleUploadedFile(
            'fatura.ofx', SAMPLE_CARD_OFX, content_type='application/x-ofx'
        )

        # 1. Preview
        self.client.post(
            reverse('cards:import_ofx'),
            {
                'action': 'preview',
                'card': self.card.pk,
                'category': self.category.pk,
                'ofx_file': ofx_file,
            },
        )

        # 2. Confirm
        response = self.client.post(
            reverse('cards:import_ofx'),
            {'action': 'confirm'},
            follow=True,
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            CreditCardExpense.objects.filter(credit_card=self.card).count(), 2
        )

        # Todas as compras do extrato pertencem à fatura correspondente ao período do extrato (08/2026)
        tx1 = CreditCardExpense.objects.get(external_id='card-tx-001')
        self.assertEqual(tx1.amount, Decimal('150.50'))
        self.assertEqual(tx1.invoice.month, 8)
        self.assertEqual(tx1.invoice.year, 2026)

        tx2 = CreditCardExpense.objects.get(external_id='card-tx-002')
        self.assertEqual(tx2.amount, Decimal('89.90'))
        self.assertEqual(tx2.invoice.month, 8)
        self.assertEqual(tx2.invoice.year, 2026)

    def test_import_ofx_deduplication(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from django.urls import reverse

        from cards.models import CreditCardExpense

        ofx_file = SimpleUploadedFile(
            'fatura.ofx', SAMPLE_CARD_OFX, content_type='application/x-ofx'
        )

        # 1ª Importação
        self.client.post(
            reverse('cards:import_ofx'),
            {
                'action': 'preview',
                'card': self.card.pk,
                'category': self.category.pk,
                'ofx_file': ofx_file,
            },
        )
        self.client.post(reverse('cards:import_ofx'), {'action': 'confirm'})
        self.assertEqual(
            CreditCardExpense.objects.filter(credit_card=self.card).count(), 2
        )

        # 2ª Importação com o mesmo arquivo
        ofx_file2 = SimpleUploadedFile(
            'fatura_repetida.ofx', SAMPLE_CARD_OFX, content_type='application/x-ofx'
        )
        preview_resp = self.client.post(
            reverse('cards:import_ofx'),
            {
                'action': 'preview',
                'card': self.card.pk,
                'category': self.category.pk,
                'ofx_file': ofx_file2,
            },
        )
        preview = preview_resp.context['preview_data']
        self.assertEqual(preview['new_count'], 0)
        self.assertEqual(preview['duplicate_count'], 2)

        self.client.post(reverse('cards:import_ofx'), {'action': 'confirm'})
        # Contagem de despesas permanece inalterada em 2
        self.assertEqual(
            CreditCardExpense.objects.filter(credit_card=self.card).count(), 2
        )

    def test_import_ofx_household_isolation(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from django.urls import reverse

        other_user = User.objects.create_user(
            email='other-user-card@example.com',
            password='password123',
        )
        other_household = ensure_household_for_user(other_user)
        other_owner = FinancialOwner.objects.get(
            household=other_household, type='shared'
        )
        other_card = CreditCard.objects.create(
            household=other_household,
            user=other_user,
            financial_owner=other_owner,
            name='Cartão Vizinho',
            limit=Decimal('2000.00'),
            closing_day=5,
            due_day=12,
        )

        ofx_file = SimpleUploadedFile(
            'fatura.ofx', SAMPLE_CARD_OFX, content_type='application/x-ofx'
        )

        # Usuário tenta postar no cartão de outro lar
        response = self.client.post(
            reverse('cards:import_ofx'),
            {
                'action': 'preview',
                'card': other_card.pk,
                'ofx_file': ofx_file,
            },
        )
        self.assertEqual(response.status_code, 302)


class CreditCardCRUDViewsTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='crud-test@example.com',
            password='password123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = FinancialOwner.objects.get(
            household=self.household, type='shared'
        )
        self.client.login(email='crud-test@example.com', password='password123')

    def test_credit_card_create_view_get(self):
        from django.urls import reverse

        response = self.client.get(reverse('cards:create'))
        self.assertEqual(response.status_code, 200)
        self.assertTemplateUsed(response, 'cards/form.html')
        self.assertContains(response, 'Novo Cartão de Crédito')

    def test_credit_card_create_view_post(self):
        from django.urls import reverse

        response = self.client.post(
            reverse('cards:create'),
            {
                'name': 'Inter Gold',
                'limit': '3500.00',
                'closing_day': 15,
                'due_day': 22,
                'color': '#FF7A00',
                'brand': 'mastercard',
                'last_digits': '9988',
                'financial_owner': self.owner.pk,
            },
        )
        self.assertEqual(response.status_code, 302)
        card = CreditCard.objects.get(name='Inter Gold')
        self.assertEqual(card.limit, Decimal('3500.00'))
        self.assertEqual(card.household, self.household)

    def test_credit_card_update_view_get(self):
        from django.urls import reverse

        card = CreditCard.objects.create(
            household=self.household,
            user=self.user,
            financial_owner=self.owner,
            name='C6 Carbon',
            limit=Decimal('10000.00'),
            closing_day=1,
            due_day=8,
        )
        response = self.client.get(reverse('cards:edit', kwargs={'pk': card.pk}))
        self.assertEqual(response.status_code, 200)
        self.assertTemplateUsed(response, 'cards/form.html')
        self.assertContains(response, 'Editar Cartão de Crédito')

