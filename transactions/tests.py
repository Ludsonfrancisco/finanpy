import datetime
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase

from accounts.models import Account
from categories.models import Category
from households.models import HouseholdMembership
from households.services import ensure_household_for_user, get_financial_owner
from transactions.forms import TransactionForm
from transactions.models import Transaction

User = get_user_model()


class TransactionFormTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='irene@example.com', password='pass123')
        self.other_user = User.objects.create_user(email='jack@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.other_household = ensure_household_for_user(self.other_user)
        self.shared_owner = get_financial_owner(self.household)
        self.other_shared_owner = get_financial_owner(self.other_household)

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Nubank',
            type=Account.CHECKING,
            initial_balance=Decimal('0.00'),
        )
        self.other_account = Account.objects.create(
            user=self.other_user,
            household=self.other_household,
            financial_owner=self.other_shared_owner,
            name='Bradesco',
            type=Account.SAVINGS,
            initial_balance=Decimal('0.00'),
        )

        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Salário',
            type=Category.INCOME,
        )
        self.other_category = Category.objects.create(
            user=self.other_user,
            household=self.other_household,
            name='Aluguel',
            type=Category.EXPENSE,
        )

    def _valid_data(self):
        return {
            'account': self.account.pk,
            'category': self.category.pk,
            'description': 'Pagamento mensal',
            'amount': '3500.00',
            'date': datetime.date.today().isoformat(),
            'type': Transaction.INCOME,
        }

    def test_valid_data_passes(self):
        form = TransactionForm(data=self._valid_data(), household=self.household)
        self.assertTrue(form.is_valid(), form.errors)

    def test_missing_description_fails(self):
        data = self._valid_data()
        data['description'] = ''
        form = TransactionForm(data=data, household=self.household)
        self.assertFalse(form.is_valid())
        self.assertIn('description', form.errors)

    def test_missing_amount_fails(self):
        data = self._valid_data()
        data['amount'] = ''
        form = TransactionForm(data=data, household=self.household)
        self.assertFalse(form.is_valid())
        self.assertIn('amount', form.errors)

    def test_missing_date_fails(self):
        data = self._valid_data()
        data['date'] = ''
        form = TransactionForm(data=data, household=self.household)
        self.assertFalse(form.is_valid())
        self.assertIn('date', form.errors)

    def test_account_queryset_scoped_to_household(self):
        form = TransactionForm(household=self.household)
        account_qs = form.fields['account'].queryset
        self.assertIn(self.account, account_qs)
        self.assertNotIn(self.other_account, account_qs)

    def test_category_queryset_scoped_to_household(self):
        form = TransactionForm(household=self.household)
        category_qs = form.fields['category'].queryset
        self.assertIn(self.category, category_qs)
        self.assertNotIn(self.other_category, category_qs)

    def test_other_user_account_rejected_in_form(self):
        data = self._valid_data()
        data['account'] = self.other_account.pk
        form = TransactionForm(data=data, household=self.household)
        self.assertFalse(form.is_valid())
        self.assertIn('account', form.errors)

    def test_other_user_category_rejected_in_form(self):
        data = self._valid_data()
        data['category'] = self.other_category.pk
        form = TransactionForm(data=data, household=self.household)
        self.assertFalse(form.is_valid())
        self.assertIn('category', form.errors)

    def test_form_without_household_has_empty_querysets(self):
        form = TransactionForm()

        self.assertFalse(form.fields['account'].queryset.exists())
        self.assertFalse(form.fields['category'].queryset.exists())


class TransactionViewTest(TestCase):
    """8.2.2 + 8.2.3 — list filtering and CRUD for transactions."""

    def setUp(self):
        self.user = User.objects.create_user(email='eve@example.com', password='pass123')
        self.other_user = User.objects.create_user(email='frank@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.other_household = ensure_household_for_user(self.other_user)
        self.shared_owner = get_financial_owner(self.household)
        self.other_shared_owner = get_financial_owner(self.other_household)
        self.client.login(username='eve@example.com', password='pass123')

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Nubank',
            type=Account.CHECKING,
            initial_balance=Decimal('0'),
        )
        self.other_account = Account.objects.create(
            user=self.other_user,
            household=self.other_household,
            financial_owner=self.other_shared_owner,
            name='Bradesco',
            type=Account.SAVINGS,
            initial_balance=Decimal('0'),
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Salário',
            type=Category.INCOME,
        )
        self.other_category = Category.objects.create(
            user=self.other_user,
            household=self.other_household,
            name='Aluguel',
            type=Category.EXPENSE,
        )

        self.tx = Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            account=self.account,
            category=self.category,
            description='Pagamento',
            amount=Decimal('1000'),
            date=datetime.date(2026, 1, 15),
            type=Transaction.INCOME,
        )
        self.other_tx = Transaction.objects.create(
            user=self.user,
            household=self.other_household,
            financial_owner=self.other_shared_owner,
            account=self.other_account,
            category=self.other_category,
            description='Aluguel janeiro',
            amount=Decimal('1500'),
            date=datetime.date(2026, 1, 10),
            type=Transaction.EXPENSE,
        )

    def _post_data(self, **overrides):
        data = {
            'account': self.account.pk,
            'category': self.category.pk,
            'description': 'Nova transação',
            'amount': '200.00',
            'date': '2026-02-01',
            'type': Transaction.INCOME,
        }
        data.update(overrides)
        return data

    def test_list_shows_only_own_transactions(self):
        response = self.client.get('/transacoes/')
        self.assertEqual(response.status_code, 200)
        transactions = list(response.context['transactions'])
        self.assertIn(self.tx, transactions)
        self.assertNotIn(self.other_tx, transactions)

    def test_create_transaction(self):
        response = self.client.post('/transacoes/nova/', self._post_data())
        self.assertRedirects(response, '/transacoes/')
        transaction = Transaction.objects.get(user=self.user, description='Nova transação')
        self.assertEqual(transaction.household, self.household)
        self.assertEqual(transaction.financial_owner, self.shared_owner)

    def test_update_transaction(self):
        response = self.client.post(
            f'/transacoes/{self.tx.pk}/editar/',
            self._post_data(description='Atualizado'),
        )
        self.assertRedirects(response, '/transacoes/')
        self.tx.refresh_from_db()
        self.assertEqual(self.tx.description, 'Atualizado')

    def test_create_transaction_with_revoked_membership_shows_form_error(self):
        with patch(
            'households.validators.has_active_household_membership',
            return_value=False,
        ):
            response = self.client.post('/transacoes/nova/', self._post_data())

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.context['form'].non_field_errors())
        self.assertFalse(
            Transaction.objects.filter(description='Nova transação').exists()
        )

    def test_update_transaction_with_revoked_membership_preserves_data(self):
        with patch(
            'households.validators.has_active_household_membership',
            return_value=False,
        ):
            response = self.client.post(
                f'/transacoes/{self.tx.pk}/editar/',
                self._post_data(description='Transação bloqueada'),
            )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.context['form'].non_field_errors())
        self.tx.refresh_from_db()
        self.assertNotEqual(self.tx.description, 'Transação bloqueada')

    def test_update_transaction_with_invalid_legacy_owner_shows_form_error(self):
        Transaction.objects.filter(pk=self.tx.pk).update(
            financial_owner=self.other_shared_owner,
        )

        response = self.client.post(
            f'/transacoes/{self.tx.pk}/editar/',
            self._post_data(description='Transação bloqueada'),
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.context['form'].non_field_errors())
        self.tx.refresh_from_db()
        self.assertNotEqual(self.tx.description, 'Transação bloqueada')
        self.assertEqual(self.tx.financial_owner, self.other_shared_owner)

    def test_update_account_preserves_existing_financial_owner(self):
        self_owner = self.household.financial_owners.get(type='self')
        self_account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self_owner,
            name='Conta individual',
            type=Account.CHECKING,
            initial_balance=Decimal('0'),
        )

        response = self.client.post(
            f'/transacoes/{self.tx.pk}/editar/',
            self._post_data(account=self_account.pk),
        )

        self.assertRedirects(response, '/transacoes/')
        self.tx.refresh_from_db()
        self.assertEqual(self.tx.account, self_account)
        self.assertEqual(self.tx.financial_owner, self.shared_owner)

    def test_delete_transaction(self):
        response = self.client.post(f'/transacoes/{self.tx.pk}/excluir/')
        self.assertRedirects(response, '/transacoes/')
        self.assertFalse(Transaction.objects.filter(pk=self.tx.pk).exists())

    def test_cannot_update_transaction_from_other_household(self):
        response = self.client.post(
            f'/transacoes/{self.other_tx.pk}/editar/',
            self._post_data(description='Hackeada'),
        )
        self.assertEqual(response.status_code, 404)

    def test_cannot_delete_transaction_from_other_household(self):
        response = self.client.post(f'/transacoes/{self.other_tx.pk}/excluir/')
        self.assertEqual(response.status_code, 404)


class TransactionFilterViewTest(TestCase):
    """8.2.4 — transaction list view filters."""

    def setUp(self):
        self.user = User.objects.create_user(email='gina@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.shared_owner = get_financial_owner(self.household)
        self.client.login(username='gina@example.com', password='pass123')

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Conta',
            type=Account.CHECKING,
            initial_balance=Decimal('0'),
        )
        self.account2 = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Poupança',
            type=Account.SAVINGS,
            initial_balance=Decimal('0'),
        )
        self.cat_income = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Salário',
            type=Category.INCOME,
        )
        self.cat_expense = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Aluguel',
            type=Category.EXPENSE,
        )

        self.tx_jan_income = Transaction.objects.create(
            user=self.user, household=self.household, financial_owner=self.shared_owner,
            account=self.account, category=self.cat_income, description='Salário jan',
            amount=Decimal('3000'), date=datetime.date(2026, 1, 5),
            type=Transaction.INCOME,
        )
        self.tx_jan_expense = Transaction.objects.create(
            user=self.user, household=self.household, financial_owner=self.shared_owner,
            account=self.account2, category=self.cat_expense, description='Aluguel jan',
            amount=Decimal('1200'), date=datetime.date(2026, 1, 10),
            type=Transaction.EXPENSE,
        )
        self.tx_feb_income = Transaction.objects.create(
            user=self.user, household=self.household, financial_owner=self.shared_owner,
            account=self.account, category=self.cat_income, description='Salário fev',
            amount=Decimal('3000'), date=datetime.date(2026, 2, 5),
            type=Transaction.INCOME,
        )

    def _get_transactions(self, params):
        response = self.client.get('/transacoes/', params)
        self.assertEqual(response.status_code, 200)
        return list(response.context['transactions'])

    def test_filter_date_from(self):
        txs = self._get_transactions({'date_from': '2026-01-08'})
        self.assertNotIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertIn(self.tx_feb_income, txs)

    def test_filter_date_to(self):
        txs = self._get_transactions({'date_to': '2026-01-31'})
        self.assertIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertNotIn(self.tx_feb_income, txs)

    def test_filter_date_range(self):
        txs = self._get_transactions({'date_from': '2026-01-01', 'date_to': '2026-01-31'})
        self.assertIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertNotIn(self.tx_feb_income, txs)

    def test_filter_by_account(self):
        txs = self._get_transactions({'account': self.account.pk})
        self.assertIn(self.tx_jan_income, txs)
        self.assertNotIn(self.tx_jan_expense, txs)
        self.assertIn(self.tx_feb_income, txs)

    def test_filter_by_category(self):
        txs = self._get_transactions({'category': self.cat_expense.pk})
        self.assertNotIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertNotIn(self.tx_feb_income, txs)

    def test_filter_by_type_income(self):
        txs = self._get_transactions({'type': Transaction.INCOME})
        self.assertIn(self.tx_jan_income, txs)
        self.assertNotIn(self.tx_jan_expense, txs)
        self.assertIn(self.tx_feb_income, txs)

    def test_filter_by_type_expense(self):
        txs = self._get_transactions({'type': Transaction.EXPENSE})
        self.assertNotIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertNotIn(self.tx_feb_income, txs)

    def test_no_filter_returns_all_own_transactions(self):
        txs = self._get_transactions({})
        self.assertIn(self.tx_jan_income, txs)
        self.assertIn(self.tx_jan_expense, txs)
        self.assertIn(self.tx_feb_income, txs)

    def test_filter_options_include_same_household_member_and_exclude_other_household(self):
        member = User.objects.create_user(email='member@example.com', password='pass123')
        HouseholdMembership.objects.create(household=self.household, user=member)
        member_account = Account.objects.create(
            user=member,
            household=self.household,
            financial_owner=self.shared_owner,
            name='Conta do membro',
            type=Account.CHECKING,
            initial_balance=Decimal('0'),
        )
        member_category = Category.objects.create(
            user=member,
            household=self.household,
            name='Categoria do membro',
            type=Category.EXPENSE,
        )
        other_user = User.objects.create_user(email='outsider@example.com', password='pass123')
        other_household = ensure_household_for_user(other_user)
        other_owner = get_financial_owner(other_household)
        other_account = Account.objects.create(
            user=other_user,
            household=other_household,
            financial_owner=other_owner,
            name='Conta externa',
            type=Account.CHECKING,
            initial_balance=Decimal('0'),
        )
        other_category = Category.objects.create(
            user=other_user,
            household=other_household,
            name='Categoria externa',
            type=Category.EXPENSE,
        )

        response = self.client.get('/transacoes/')

        self.assertContains(response, member_account.name)
        self.assertContains(response, member_category.name)
        self.assertNotContains(response, other_account.name)
        self.assertNotContains(response, other_category.name)
        self.assertIn(member_account, response.context['filter_accounts'])
        self.assertIn(member_category, response.context['filter_categories'])
        self.assertNotIn(other_account, response.context['filter_accounts'])
        self.assertNotIn(other_category, response.context['filter_categories'])

    def _create_foreign_filter_objects(self):
        other_user = User.objects.create_user(email='foreign@example.com', password='pass123')
        other_household = ensure_household_for_user(other_user)
        other_owner = get_financial_owner(other_household)
        other_account = Account.objects.create(
            user=other_user,
            household=other_household,
            financial_owner=other_owner,
            name='Conta estrangeira',
            type=Account.CHECKING,
            initial_balance=Decimal('0'),
        )
        other_category = Category.objects.create(
            user=other_user,
            household=other_household,
            name='Categoria estrangeira',
            type=Category.EXPENSE,
        )
        foreign_transaction = Transaction.objects.create(
            user=other_user,
            household=other_household,
            financial_owner=other_owner,
            account=other_account,
            category=other_category,
            description='Transação estrangeira',
            amount=Decimal('500'),
            date=datetime.date(2026, 1, 15),
            type=Transaction.EXPENSE,
        )
        return other_account, other_category, foreign_transaction

    def test_foreign_account_filter_returns_no_transactions_or_filter_option(self):
        other_account, _, foreign_transaction = self._create_foreign_filter_objects()

        response = self.client.get(
            '/transacoes/',
            {'account': other_account.pk},
        )

        self.assertEqual(list(response.context['transactions']), [])
        self.assertNotContains(response, other_account.name)
        self.assertNotContains(response, foreign_transaction.description)
        self.assertNotIn(other_account, response.context['filter_accounts'])

    def test_foreign_category_filter_returns_no_transactions_or_filter_option(self):
        _, other_category, foreign_transaction = self._create_foreign_filter_objects()

        response = self.client.get(
            '/transacoes/',
            {'category': other_category.pk},
        )

        self.assertEqual(list(response.context['transactions']), [])
        self.assertNotContains(response, other_category.name)
        self.assertNotContains(response, foreign_transaction.description)
        self.assertNotIn(other_category, response.context['filter_categories'])

    def test_export_ofx_generates_valid_file_and_headers(self):
        response = self.client.get('/transacoes/exportar-ofx/')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response['Content-Type'].startswith('application/x-ofx'))
        self.assertTrue(response['Content-Disposition'].startswith('attachment; filename="extrato-lar-finance-'))
        content = response.content.decode('utf-8')
        self.assertIn('OFXHEADER:100', content)
        self.assertIn('<OFX>', content)
        self.assertIn('<STMTTRN>', content)
        self.assertIn('Salário jan', content)
        self.assertIn('Aluguel jan', content)

    def test_import_ofx_get_page_renders_form(self):
        response = self.client.get('/transacoes/importar/')
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Importar Extrato Bancário (OFX)')
        self.assertContains(response, self.account.name)

    def test_import_ofx_preview_and_confirm_flow(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from imports.models import SourceReference

        sample_ofx = (
            b'OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nSECURITY:NONE\nENCODING:UTF-8\nCHARSET:NONE\n\n'
            b'<OFX>\n<SIGNONMSGSRSV1><SONRS><STATUS><CODE>0\n<SEVERITY>INFO\n</STATUS>'
            b'<DTSERVER>20260131120000\n<LANGUAGE>POR\n</SONRS></SIGNONMSGSRSV1>\n'
            b'<BANKMSGSRSV1><STMTTRNRS><TRNUID>1\n<STATUS><CODE>0\n<SEVERITY>INFO\n</STATUS>'
            b'<STMTRS><CURDEF>BRL\n<BANKACCTFROM><BANKID>0260\n<ACCTID>123456\n<ACCTTYPE>CHECKING\n</BANKACCTFROM>\n'
            b'<BANKTRANLIST><DTSTART>20260101120000\n<DTEND>20260131120000\n'
            b'<STMTTRN><TRNTYPE>DEBIT\n<DTPOSTED>20260115120000\n<TRNAMT>-85.50\n<FITID>nubank-tx-001\n<MEMO>Supermercado Teste\n</STMTTRN>\n'
            b'<STMTTRN><TRNTYPE>CREDIT\n<DTPOSTED>20260120120000\n<TRNAMT>2500.00\n<FITID>nubank-tx-002\n<MEMO>Transferencia Teste\n</STMTTRN>\n'
            b'</BANKTRANLIST><LEDGERBAL><BALAMT>2414.50\n<DTASOF>20260131120000\n</LEDGERBAL></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>'
        )

        uploaded_file = SimpleUploadedFile('extrato.ofx', sample_ofx, content_type='application/x-ofx')

        # 1. Preview
        response = self.client.post('/transacoes/importar/', {
            'action': 'preview',
            'account': self.account.pk,
            'category': self.cat_expense.pk,
            'ofx_file': uploaded_file,
        })
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Lançamentos Identificados no Extrato')
        self.assertContains(response, 'Supermercado Teste')
        self.assertContains(response, 'Transferencia Teste')

        # 2. Confirm
        response = self.client.post('/transacoes/importar/', {
            'action': 'confirm',
        })
        self.assertRedirects(response, '/transacoes/')

        # 3. Verify created records
        self.assertTrue(Transaction.objects.filter(description='Supermercado Teste', amount=Decimal('85.50')).exists())
        self.assertTrue(Transaction.objects.filter(description='Transferencia Teste', amount=Decimal('2500.00')).exists())
        self.assertTrue(SourceReference.objects.filter(external_id='nubank-tx-001').exists())
        self.assertTrue(SourceReference.objects.filter(external_id='nubank-tx-002').exists())


class TransactionQuickEntryTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='quick@example.com', password='pass123')
        self.other_user = User.objects.create_user(email='other@example.com', password='pass123')
        self.household = ensure_household_for_user(self.user)
        self.other_household = ensure_household_for_user(self.other_user)
        self.owner = get_financial_owner(self.household)
        self.other_owner = get_financial_owner(self.other_household)
        self.client.login(username='quick@example.com', password='pass123')

        self.account = Account.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            name='Conta Corrente',
            type=Account.CHECKING,
            initial_balance=Decimal('100.00'),
        )
        self.other_account = Account.objects.create(
            user=self.other_user,
            household=self.other_household,
            financial_owner=self.other_owner,
            name='Conta Estrangeira',
            type=Account.CHECKING,
            initial_balance=Decimal('100.00'),
        )
        self.category = Category.objects.create(
            user=self.user,
            household=self.household,
            name='Supermercado',
            type=Category.EXPENSE,
            budget=Decimal('800.00'),
        )
        self.other_category = Category.objects.create(
            user=self.other_user,
            household=self.other_household,
            name='Outro Lar',
            type=Category.EXPENSE,
        )

    def test_quick_create_success_json(self):
        payload = {
            'date': '2026-08-19',
            'type': 'expense',
            'description': 'Padaria Pão Quente',
            'amount': '15,50',
            'account': self.account.pk,
            'category': self.category.pk,
        }
        response = self.client.post(
            '/transacoes/quick-create/',
            payload,
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data['success'])
        self.assertEqual(data['transaction']['description'], 'Padaria Pão Quente')
        self.assertEqual(data['transaction']['amount'], 15.5)

        tx = Transaction.objects.get(pk=data['transaction']['id'])
        self.assertEqual(tx.household, self.household)
        self.assertEqual(tx.financial_owner, self.owner)
        self.assertEqual(tx.amount, Decimal('15.50'))

    def test_quick_create_validation_error(self):
        payload = {
            'date': '2026-08-19',
            'type': 'expense',
            'description': '',
            'amount': '0.00',
            'account': self.account.pk,
            'category': self.category.pk,
        }
        response = self.client.post(
            '/transacoes/quick-create/',
            payload,
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertFalse(data['success'])

    def test_quick_create_rejects_foreign_account_or_category(self):
        payload = {
            'date': '2026-08-19',
            'type': 'expense',
            'description': 'Hacker attempt',
            'amount': '50.00',
            'account': self.other_account.pk,
            'category': self.category.pk,
        }
        response = self.client.post(
            '/transacoes/quick-create/',
            payload,
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 400)

    def test_quick_delete_success(self):
        tx = Transaction.objects.create(
            user=self.user,
            household=self.household,
            financial_owner=self.owner,
            account=self.account,
            category=self.category,
            description='Para excluir',
            amount=Decimal('20.00'),
            date=datetime.date.today(),
            type=Transaction.EXPENSE,
        )
        response = self.client.post(f'/transacoes/{tx.pk}/quick-delete/')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['success'])
        self.assertFalse(Transaction.objects.filter(pk=tx.pk).exists())

    def test_quick_delete_foreign_transaction_404(self):
        foreign_tx = Transaction.objects.create(
            user=self.other_user,
            household=self.other_household,
            financial_owner=self.other_owner,
            account=self.other_account,
            category=self.other_category,
            description='Estrangeira',
            amount=Decimal('20.00'),
            date=datetime.date.today(),
            type=Transaction.EXPENSE,
        )
        response = self.client.post(f'/transacoes/{foreign_tx.pk}/quick-delete/')
        self.assertEqual(response.status_code, 404)
        self.assertTrue(Transaction.objects.filter(pk=foreign_tx.pk).exists())


