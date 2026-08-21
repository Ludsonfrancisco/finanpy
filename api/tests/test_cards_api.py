from decimal import Decimal

from django.test import TestCase

from accounts.models import Account
from api.models import DeviceSession
from api.tokens import issue_session
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from users.models import User


class CardsApiTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='api-cards@example.com',
            password='Strong-pass-123',
        )
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type=FinancialOwner.SELF)
        self.shared_owner = get_financial_owner(
            self.household, owner_type=FinancialOwner.SHARED
        )

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
            name='Conta Nubank',
            type=Account.CHECKING,
            initial_balance=Decimal('5000.00'),
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Tecnologia',
            type=Category.EXPENSE,
        )

    def test_cards_api_complete_lifecycle(self):
        # 1. Create card
        create_res = self.client.post(
            '/api/v1/cards/',
            {
                'name': 'XP Visa Infinite',
                'limit': '10000.01',
                'closing_day': 10,
                'due_day': 17,
                'color': '#111111',
                'brand': 'visa',
                'last_digits': '9988',
                'financial_owner_type': 'shared',
            },
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(create_res.status_code, 201)
        created_card = create_res.json()
        card_id = created_card['id']
        self.assertEqual(created_card['limit'], '10000.01')

        # 2. List cards
        list_res = self.client.get('/api/v1/cards/', **self.auth)
        self.assertEqual(list_res.status_code, 200)
        cards = list_res.json()['cards']
        self.assertEqual(len(cards), 1)
        self.assertEqual(cards[0]['name'], 'XP Visa Infinite')

        # 3. Create Expense (3x installments)
        expense_res = self.client.post(
            '/api/v1/cards/expenses/',
            {
                'card_id': card_id,
                'description': 'Headset Gamer',
                'amount': '0.03',
                'date': '2026-08-05',
                'category_id': self.category.pk,
                'installments_count': 3,
            },
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(expense_res.status_code, 201)
        expense_data = expense_res.json()
        self.assertEqual(expense_data['created_count'], 3)
        self.assertEqual(
            [expense['amount'] for expense in expense_data['expenses']],
            ['0.01', '0.01', '0.01'],
        )

        # 4. Get Card Details and Invoices
        detail_res = self.client.get(
            f'/api/v1/cards/{card_id}/?month=8&year=2026', **self.auth
        )
        self.assertEqual(detail_res.status_code, 200)
        data = detail_res.json()
        self.assertEqual(data['selected_invoice']['total_amount'], '0.01')
        invoice_id = data['selected_invoice']['id']

        # Add one cent so the explicit payment differs from the endpoint default.
        adjustment_res = self.client.post(
            '/api/v1/cards/expenses/',
            {
                'card_id': card_id,
                'description': 'Ajuste de centavo',
                'amount': '0.01',
                'date': '2026-08-06',
                'category_id': self.category.pk,
                'installments_count': 1,
            },
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(adjustment_res.status_code, 201)
        adjusted_detail = self.client.get(
            f'/api/v1/cards/{card_id}/?month=8&year=2026', **self.auth
        )
        self.assertEqual(
            adjusted_detail.json()['selected_invoice']['total_amount'], '0.02'
        )

        # 5. Pay Invoice with an explicit amount instead of the 0.02 default.
        pay_res = self.client.post(
            f'/api/v1/cards/invoices/{invoice_id}/pay/',
            {
                'account_id': self.account.pk,
                'paid_amount': '0.01',
                'payment_date': '2026-08-17',
            },
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(pay_res.status_code, 200)
        self.assertEqual(pay_res.json()['status'], 'paid')
        self.assertEqual(pay_res.json()['paid_amount'], '0.01')

        # 6. Reopen Invoice
        reopen_res = self.client.post(
            f'/api/v1/cards/invoices/{invoice_id}/reopen/',
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(reopen_res.status_code, 200)
        self.assertIn(reopen_res.json()['status'], ['open', 'closed', 'overdue'])

        # 7. Update Card
        patch_res = self.client.patch(
            f'/api/v1/cards/{card_id}/',
            {'limit': '15000.01'},
            content_type='application/json',
            **self.auth,
        )
        self.assertEqual(patch_res.status_code, 200)
        self.assertEqual(patch_res.json()['limit'], '15000.01')

        # 8. Archive Card
        del_res = self.client.delete(f'/api/v1/cards/{card_id}/', **self.auth)
        self.assertEqual(del_res.status_code, 200)
