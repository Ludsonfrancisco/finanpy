from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.urls import reverse_lazy
from django.views.generic import CreateView, DeleteView, ListView, UpdateView

from accounts.models import Account
from categories.models import Category
from households.forms import validate_instance_or_add_form_errors
from households.mixins import HouseholdContextMixin

from .forms import TransactionForm
from .models import Transaction


class TransactionListView(LoginRequiredMixin, HouseholdContextMixin, ListView):
    model = Transaction
    template_name = 'transactions/list.html'
    context_object_name = 'transactions'
    paginate_by = 20

    def get_queryset(self):
        qs = super().get_queryset().filter(household=self.household)
        params = self.request.GET

        date_from = params.get('date_from')
        date_to = params.get('date_to')
        account = params.get('account')
        category = params.get('category')
        type_ = params.get('type')

        if date_from:
            qs = qs.filter(date__gte=date_from)
        if date_to:
            qs = qs.filter(date__lte=date_to)
        if account:
            qs = qs.filter(account_id=account)
        if category:
            qs = qs.filter(category_id=category)
        if type_:
            qs = qs.filter(type=type_)

        return qs

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        params = self.request.GET
        context['filter_date_from'] = params.get('date_from', '')
        context['filter_date_to'] = params.get('date_to', '')
        context['filter_account'] = params.get('account', '')
        context['filter_category'] = params.get('category', '')
        context['filter_type'] = params.get('type', '')
        context['filter_accounts'] = Account.objects.filter(household=self.household)
        context['filter_categories'] = Category.objects.filter(household=self.household)
        return context


class TransactionCreateView(LoginRequiredMixin, HouseholdContextMixin, CreateView):
    model = Transaction
    form_class = TransactionForm
    template_name = 'transactions/form.html'
    success_url = reverse_lazy('transactions:list')

    def get_form_kwargs(self):
        kwargs = super().get_form_kwargs()
        kwargs['household'] = self.household
        return kwargs

    def form_valid(self, form):
        form.instance.user = self.request.user
        form.instance.household = self.household
        form.instance.financial_owner = form.cleaned_data['account'].financial_owner
        if not validate_instance_or_add_form_errors(form):
            return self.form_invalid(form)
        messages.success(self.request, 'Transação criada com sucesso.')
        return super().form_valid(form)

    def form_invalid(self, form):
        messages.error(self.request, 'Por favor corrija os erros abaixo.')
        return super().form_invalid(form)


class TransactionUpdateView(LoginRequiredMixin, HouseholdContextMixin, UpdateView):
    model = Transaction
    form_class = TransactionForm
    template_name = 'transactions/form.html'
    success_url = reverse_lazy('transactions:list')

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)

    def get_form_kwargs(self):
        kwargs = super().get_form_kwargs()
        kwargs['household'] = self.household
        return kwargs

    def form_valid(self, form):
        if not validate_instance_or_add_form_errors(form):
            return self.form_invalid(form)
        messages.success(self.request, 'Transação atualizada com sucesso.')
        return super().form_valid(form)

    def form_invalid(self, form):
        messages.error(self.request, 'Por favor corrija os erros abaixo.')
        return super().form_invalid(form)


class TransactionDeleteView(LoginRequiredMixin, HouseholdContextMixin, DeleteView):
    model = Transaction
    template_name = 'transactions/confirm_delete.html'
    success_url = reverse_lazy('transactions:list')

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)

    def form_valid(self, form):
        messages.success(self.request, 'Transação excluída com sucesso.')
        return super().form_valid(form)


class TransactionExportOFXView(LoginRequiredMixin, HouseholdContextMixin, ListView):
    """Exporta as transações filtradas em formato padrão OFX 1.02."""

    def get(self, request, *args, **kwargs):
        from django.http import HttpResponse
        from django.utils import timezone

        qs = Transaction.objects.filter(household=self.household).order_by('date')
        params = request.GET

        date_from = params.get('date_from')
        date_to = params.get('date_to')
        account_id = params.get('account')
        category_id = params.get('category')
        type_ = params.get('type')

        if date_from:
            qs = qs.filter(date__gte=date_from)
        if date_to:
            qs = qs.filter(date__lte=date_to)
        if account_id:
            qs = qs.filter(account_id=account_id)
        if category_id:
            qs = qs.filter(category_id=category_id)
        if type_:
            qs = qs.filter(type=type_)

        account = None
        if account_id:
            account = Account.objects.filter(household=self.household, pk=account_id).first()

        acct_id = str(account.pk) if account else '000'
        currency = account.currency if account else 'BRL'
        bank_id = '0000'

        now = timezone.now()
        dtserver = now.strftime('%Y%m%d%H%M%S')

        first_tx = qs.first()
        last_tx = qs.last()
        dtstart = first_tx.date.strftime('%Y%m%d120000') if first_tx else dtserver
        dtend = last_tx.date.strftime('%Y%m%d120000') if last_tx else dtserver

        stmt_trns = []
        for tx in qs:
            trn_type = 'CREDIT' if tx.type == Transaction.INCOME else 'DEBIT'
            amount = tx.amount if tx.type == Transaction.INCOME else -tx.amount
            dtposted = tx.date.strftime('%Y%m%d120000')
            fitid = str(tx.uuid)
            clean_desc = tx.description.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            stmt_trns.append(
                f'<STMTTRN>\n'
                f'<TRNTYPE>{trn_type}\n'
                f'<DTPOSTED>{dtposted}\n'
                f'<TRNAMT>{amount:.2f}\n'
                f'<FITID>{fitid}\n'
                f'<MEMO>{clean_desc}\n'
                f'</STMTTRN>'
            )

        tran_list_xml = '\n'.join(stmt_trns)

        ofx_content = f"""OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:UTF-8
CHARSET:1252
COMPRESSION:NONE
OLDFILEVERSION:102
NEWFILEVERSION:102

<OFX>
<SIGNONMSGSRSV1>
<SONRS>
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<DTSERVER>{dtserver}
<LANGUAGE>POR
<FI>
<ORG>Lar Finance
<FID>1
</FID>
</SONRS>
</SIGNONMSGSRSV1>
<BANKMSGSRSV1>
<STMTTRNRS>
<TRNUID>1
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<STMTRS>
<CURDEF>{currency}
<BANKACCTFROM>
<BANKID>{bank_id}
<ACCTID>{acct_id}
<ACCTTYPE>CHECKING
</BANKACCTFROM>
<BANKTRANLIST>
<DTSTART>{dtstart}
<DTEND>{dtend}
{tran_list_xml}
</BANKTRANLIST>
<LEDGERBAL>
<BALAMT>0.00
<DTASOF>{dtserver}
</LEDGERBAL>
</STMTRS>
</STMTTRNRS>
</BANKMSGSRSV1>
</OFX>"""

        response = HttpResponse(ofx_content, content_type='application/x-ofx; charset=utf-8')
        filename = f'extrato-lar-finance-{now.strftime("%Y%m%d")}.ofx'
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response

