import datetime
from decimal import Decimal

from django.test import TestCase

from accounts.models import Account
from api.models import DeviceSession
from api.tokens import issue_session
from bills.models import BillInstance, RecurringBill
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from users.models import User


class BillsApiTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='api-bills@example.com',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type=FinancialOwner.SELF)
        self.shared_owner = get_financial_owner(self.household, owner_type=FinancialOwner.SHARED)

        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issued.access_token}'}

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Nubank',
            type=Account.CHECKING,
            initial_balance=Decimal('2000.00'),
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Serviços',
            type=Category.EXPENSE,
        )

    def test_bills_api_list_create_pay_reopen_cycle(self):
        # 1. Create a bill
        create_res = self.client.post(
            '/api/v1/bills/',
            {
                'name': 'Internet Claro',
                'amount': '120.00',
                'due_day': 10,
                'type': 'expense',
                'category_id': self.category.pk,
                'default_account_id': self.account.pk,
                'financial_owner_type': 'shared',
                'is_active': True,
                'notes': 'Plano 500mb',
            },
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(create_res.status_code, 201)
        bill_data = create_res.json()
        bill_id = bill_data['id']
        self.assertEqual(bill_data['name'], 'Internet Claro')
        self.assertEqual(bill_data['amount'], '120.00')

        # 2. Get list & instances
        list_res = self.client.get('/api/v1/bills/', **self.auth)
        self.assertEqual(list_res.status_code, 200)
        list_data = list_res.json()
        self.assertEqual(len(list_data['instances']), 1)
        self.assertEqual(len(list_data['recurring_bills']), 1)
        self.assertIn('metrics', list_data)
        inst = list_data['instances'][0]
        self.assertEqual(inst['status'], 'pending')

        # 3. Pay instance
        pay_res = self.client.post(
            f'/api/v1/bills/instances/{inst["id"]}/pay/',
            {
                'account_id': self.account.pk,
                'paid_amount': '120.00',
                'paid_date': datetime.date.today().isoformat(),
            },
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(pay_res.status_code, 200)
        paid_inst = pay_res.json()
        self.assertEqual(paid_inst['status'], 'paid')

        # 4. Get Metrics
        metrics_res = self.client.get('/api/v1/bills/metrics/', **self.auth)
        self.assertEqual(metrics_res.status_code, 200)
        metrics = metrics_res.json()
        self.assertEqual(metrics['paid_expenses_total'], '120.00')
        self.assertEqual(metrics['pending_expenses_total'], '0.00')

        # 5. Reopen instance
        reopen_res = self.client.post(
            f'/api/v1/bills/instances/{inst["id"]}/reopen/',
            **self.auth,
        )
        self.assertEqual(reopen_res.status_code, 200)
        reopened = reopen_res.json()
        self.assertEqual(reopened['status'], 'pending')

        # 6. Update bill
        patch_res = self.client.patch(
            f'/api/v1/bills/{bill_id}/',
            {'amount': '130.00'},
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(patch_res.status_code, 200)
        self.assertEqual(patch_res.json()['amount'], '130.00')

        # 7. Delete bill
        del_res = self.client.delete(f'/api/v1/bills/{bill_id}/', **self.auth)
        self.assertEqual(del_res.status_code, 200)
        self.assertFalse(RecurringBill.objects.filter(pk=bill_id).exists())
