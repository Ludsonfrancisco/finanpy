import datetime
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse

from accounts.models import Account
from categories.models import Category
from households.services import ensure_household_for_user, get_financial_owner
from transactions.models import Transaction

from .models import BillInstance, RecurringBill
from .services import (
    ensure_monthly_bill_instances,
    get_bills_dashboard_metrics,
    get_month_due_date,
    pay_bill_instance,
    reopen_bill_instance,
)

User = get_user_model()


class BillsServiceAndModelTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='marcos@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.shared_owner = get_financial_owner(self.household)

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Nubank',
            type=Account.CHECKING,
            initial_balance=Decimal('5000.00'),
        )
        self.category_rent = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Moradia',
            type=Category.EXPENSE,
        )
        self.category_internet = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Serviços',
            type=Category.EXPENSE,
        )

        self.bill_rent = RecurringBill.objects.create(
            household=self.household,
            user=self.user,
            financial_owner=self.shared_owner,
            name='Aluguel e Condomínio',
            amount=Decimal('2500.00'),
            due_day=10,
            type=RecurringBill.EXPENSE,
            category=self.category_rent,
            default_account=self.account,
        )

        self.bill_internet = RecurringBill.objects.create(
            household=self.household,
            user=self.user,
            financial_owner=self.shared_owner,
            name='Internet Claro',
            amount=Decimal('150.00'),
            due_day=31,
            type=RecurringBill.EXPENSE,
            category=self.category_internet,
            default_account=self.account,
        )

    def test_get_month_due_date_clamps_february(self):
        due_feb = get_month_due_date(2026, 2, 31)
        self.assertEqual(due_feb, datetime.date(2026, 2, 28))

        due_apr = get_month_due_date(2026, 4, 31)
        self.assertEqual(due_apr, datetime.date(2026, 4, 30))

    def test_ensure_monthly_bill_instances_creates_instances_for_month(self):
        instances = ensure_monthly_bill_instances(self.household, month=8, year=2026)
        self.assertEqual(instances.count(), 2)

        inst_rent = instances.get(bill=self.bill_rent)
        self.assertEqual(inst_rent.amount, Decimal('2500.00'))
        self.assertEqual(inst_rent.due_date, datetime.date(2026, 8, 10))
        self.assertEqual(inst_rent.status, BillInstance.STATUS_PENDING)

        inst_net = instances.get(bill=self.bill_internet)
        self.assertEqual(inst_net.due_date, datetime.date(2026, 8, 31))

    def test_pay_bill_instance_creates_transaction_and_updates_status(self):
        instances = ensure_monthly_bill_instances(self.household, month=8, year=2026)
        inst_rent = instances.get(bill=self.bill_rent)

        tx = pay_bill_instance(
            instance=inst_rent,
            user=self.user,
            account=self.account,
            paid_amount=Decimal('2550.00'),
            paid_date=datetime.date(2026, 8, 10),
        )

        inst_rent.refresh_from_db()
        self.assertEqual(inst_rent.status, BillInstance.STATUS_PAID)
        self.assertEqual(inst_rent.paid_at, datetime.date(2026, 8, 10))
        self.assertEqual(inst_rent.amount, Decimal('2550.00'))
        self.assertEqual(inst_rent.transaction, tx)

        self.assertEqual(tx.amount, Decimal('2550.00'))
        self.assertEqual(tx.account, self.account)
        self.assertEqual(self.account.current_balance, Decimal('2450.00'))

    def test_reopen_bill_instance_reverts_payment_and_removes_transaction(self):
        instances = ensure_monthly_bill_instances(self.household, month=8, year=2026)
        inst_rent = instances.get(bill=self.bill_rent)

        tx = pay_bill_instance(
            instance=inst_rent,
            user=self.user,
            account=self.account,
            paid_amount=Decimal('2500.00'),
            paid_date=datetime.date(2026, 8, 10),
        )
        self.assertTrue(Transaction.objects.filter(pk=tx.pk).exists())

        reopen_bill_instance(inst_rent)
        inst_rent.refresh_from_db()
        self.assertEqual(inst_rent.status, BillInstance.STATUS_PENDING)
        self.assertIsNone(inst_rent.paid_at)
        self.assertIsNone(inst_rent.transaction)
        self.assertFalse(Transaction.objects.filter(pk=tx.pk).exists())
        self.assertEqual(self.account.current_balance, Decimal('5000.00'))

    def test_get_bills_dashboard_metrics_computes_real_free_cash(self):
        # Initial account balance = 5000.00
        # Pending bills = 2500.00 (rent) + 150.00 (internet) = 2650.00
        # Free cash balance = 5000.00 - 2650.00 = 2350.00
        metrics = get_bills_dashboard_metrics(self.household, month=8, year=2026)
        self.assertEqual(metrics['total_account_balance'], Decimal('5000.00'))
        self.assertEqual(metrics['pending_expenses_total'], Decimal('2650.00'))
        self.assertEqual(metrics['free_cash_balance'], Decimal('2350.00'))


class BillsViewsTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='carla@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.shared_owner = get_financial_owner(self.household)

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Inter',
            type=Account.CHECKING,
            initial_balance=Decimal('1000.00'),
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Contas',
            type=Category.EXPENSE,
        )
        self.client.force_login(self.user)

    def test_bill_list_view_renders_correctly(self):
        response = self.client.get(reverse('bills:list'))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Contas Fixas & Vencimentos')
        self.assertContains(response, 'Saldo Livre Real')

    def test_bill_create_and_delete_view_flow(self):
        # Create
        response = self.client.post(reverse('bills:create'), {
            'name': 'Energia Enel',
            'amount': '320.50',
            'due_day': 15,
            'type': RecurringBill.EXPENSE,
            'category': self.category.pk,
            'default_account': self.account.pk,
            'financial_owner': self.shared_owner.pk,
            'is_active': True,
        })
        self.assertRedirects(response, reverse('bills:list'))
        self.assertTrue(RecurringBill.objects.filter(name='Energia Enel').exists())

        bill = RecurringBill.objects.get(name='Energia Enel')
        instance = BillInstance.objects.filter(bill=bill).first()
        self.assertIsNotNone(instance)

        # Pay
        response = self.client.post(reverse('bills:pay', kwargs={'pk': instance.pk}), {
            'account': self.account.pk,
            'paid_amount': '320.50',
            'paid_date': '2026-08-15',
        })
        self.assertRedirects(response, reverse('bills:list'))
        instance.refresh_from_db()
        self.assertEqual(instance.status, BillInstance.STATUS_PAID)

        # Reopen
        response = self.client.post(reverse('bills:reopen', kwargs={'pk': instance.pk}))
        self.assertRedirects(response, reverse('bills:list'))
        instance.refresh_from_db()
        self.assertEqual(instance.status, BillInstance.STATUS_PENDING)

        # Delete
        response = self.client.post(reverse('bills:delete', kwargs={'pk': bill.pk}))
        self.assertRedirects(response, reverse('bills:list'))
        self.assertFalse(RecurringBill.objects.filter(name='Energia Enel').exists())

    def test_bill_create_with_minimal_fields_and_optional_values(self):
        # Create without default_account or financial_owner
        response = self.client.post(reverse('bills:create'), {
            'name': 'Netflix',
            'amount': '55.90',
            'due_day': 20,
            'type': RecurringBill.EXPENSE,
            'category': self.category.pk,
            'default_account': '',
            'financial_owner': '',
            'is_active': True,
        })
        self.assertRedirects(response, reverse('bills:list'))
        bill = RecurringBill.objects.filter(name='Netflix').first()
        self.assertIsNotNone(bill)
        self.assertIsNone(bill.default_account)
        self.assertEqual(bill.financial_owner, self.shared_owner)

    def test_bill_update_view(self):
        bill = RecurringBill.objects.create(
            household=self.household,
            user=self.user,
            financial_owner=self.shared_owner,
            name='Academia',
            amount=Decimal('120.00'),
            due_day=5,
            type=RecurringBill.EXPENSE,
            category=self.category,
        )

        response = self.client.post(reverse('bills:update', kwargs={'pk': bill.pk}), {
            'name': 'Academia Premium',
            'amount': '150.00',
            'due_day': 5,
            'type': RecurringBill.EXPENSE,
            'category': self.category.pk,
            'default_account': '',
            'financial_owner': self.shared_owner.pk,
            'is_active': True,
        })
        self.assertRedirects(response, reverse('bills:list'))
        bill.refresh_from_db()
        self.assertEqual(bill.name, 'Academia Premium')
        self.assertEqual(bill.amount, Decimal('150.00'))

