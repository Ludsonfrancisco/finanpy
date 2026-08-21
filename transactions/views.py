import json
from decimal import Decimal, InvalidOperation

from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.http import JsonResponse
from django.shortcuts import redirect, render
from django.urls import reverse, reverse_lazy
from django.utils import timezone
from django.utils.dateparse import parse_date
from django.views import View
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
        accounts = Account.objects.filter(household=self.household).select_related('financial_owner').order_by('name')
        categories = Category.objects.filter(household=self.household).order_by('name')

        context['filter_date_from'] = params.get('date_from', '')
        context['filter_date_to'] = params.get('date_to', '')
        context['filter_account'] = params.get('account', '')
        context['filter_category'] = params.get('category', '')
        context['filter_type'] = params.get('type', '')
        context['filter_accounts'] = accounts
        context['filter_categories'] = categories
        context['accounts'] = accounts
        context['categories'] = categories
        context['today_date'] = timezone.localdate().strftime('%Y-%m-%d')
        return context


class TransactionQuickCreateView(LoginRequiredMixin, HouseholdContextMixin, View):
    """Cria uma transação de forma assíncrona (AJAX/Fetch) para o Modo Planilha."""

    def post(self, request, *args, **kwargs):
        if request.content_type == 'application/json':
            try:
                data = json.loads(request.body)
            except Exception:
                return JsonResponse({'success': False, 'error': 'JSON inválido.'}, status=400)
        else:
            data = request.POST

        date_str = data.get('date')
        description = (data.get('description') or '').strip()
        amount_raw = str(data.get('amount') or '').strip().replace(',', '.')
        type_ = data.get('type', Transaction.EXPENSE)
        account_id = data.get('account')
        category_id = data.get('category')

        if not description:
            return JsonResponse({'success': False, 'error': 'A descrição é obrigatória.'}, status=400)

        if not amount_raw:
            return JsonResponse({'success': False, 'error': 'O valor é obrigatório.'}, status=400)

        try:
            amount = Decimal(amount_raw)
            if amount <= Decimal('0.00'):
                return JsonResponse({'success': False, 'error': 'O valor deve ser maior que zero.'}, status=400)
        except InvalidOperation:
            return JsonResponse({'success': False, 'error': 'Valor numérico inválido.'}, status=400)

        tx_date = parse_date(date_str) if date_str else timezone.localdate()
        if not tx_date:
            return JsonResponse({'success': False, 'error': 'Data inválida.'}, status=400)

        if type_ not in (Transaction.EXPENSE, Transaction.INCOME):
            type_ = Transaction.EXPENSE

        account = Account.objects.filter(household=self.household, pk=account_id).select_related('financial_owner').first()
        if not account:
            return JsonResponse({'success': False, 'error': 'Conta bancária inválida ou não encontrada no Lar.'}, status=400)

        category = Category.objects.filter(household=self.household, pk=category_id).first()
        if not category:
            return JsonResponse({'success': False, 'error': 'Categoria inválida ou não encontrada no Lar.'}, status=400)

        try:
            tx = Transaction(
                user=self.request.user,
                household=self.household,
                financial_owner=account.financial_owner,
                account=account,
                category=category,
                description=description,
                amount=amount,
                date=tx_date,
                type=type_,
            )
            tx.full_clean()
            tx.save()
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=400)

        owner_display = tx.financial_owner.get_type_display() if tx.financial_owner else ''
        cat_color = tx.category.color or '#8D958D'

        return JsonResponse({
            'success': True,
            'transaction': {
                'id': tx.pk,
                'date': tx.date.strftime('%Y-%m-%d'),
                'date_formatted': tx.date.strftime('%d %b, %Y'),
                'description': tx.description,
                'amount': float(tx.amount),
                'amount_formatted': f'{tx.amount:.2f}',
                'type': tx.type,
                'account_name': tx.account.name,
                'category_name': tx.category.name,
                'category_color': cat_color,
                'financial_owner_display': owner_display,
                'update_url': reverse('transactions:update', kwargs={'pk': tx.pk}),
                'delete_url': reverse('transactions:delete', kwargs={'pk': tx.pk}),
                'quick_delete_url': reverse('transactions:quick_delete', kwargs={'pk': tx.pk}),
            }
        })


class TransactionQuickDeleteView(LoginRequiredMixin, HouseholdContextMixin, View):
    """Exclui uma transação de forma assíncrona para o Modo Planilha."""

    def post(self, request, pk, *args, **kwargs):
        tx = Transaction.objects.filter(household=self.household, pk=pk).first()
        if not tx:
            return JsonResponse({'success': False, 'error': 'Transação não encontrada.'}, status=404)
        tx.delete()
        return JsonResponse({'success': True, 'id': pk})


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


class TransactionImportOFXView(LoginRequiredMixin, HouseholdContextMixin, View):
    """Permite fazer upload, pré-visualizar deduplicação e confirmar importação de OFX."""

    template_name = 'transactions/import.html'

    def get(self, request, *args, **kwargs):
        accounts = Account.objects.filter(household=self.household).order_by('name')
        categories = Category.objects.filter(household=self.household).order_by('name')
        if not accounts.exists():
            messages.warning(request, 'Cadastre uma conta antes de importar extratos.')
            return redirect('accounts:create')

        return render(request, self.template_name, {
            'accounts': accounts,
            'categories': categories,
            'preview_data': None,
        })

    def post(self, request, *args, **kwargs):
        from decimal import Decimal

        from django.db import transaction

        from imports.models import SourceReference
        from imports.ofx import OfxParseError, parse_nubank_ofx

        action = request.POST.get('action', 'preview')
        accounts = Account.objects.filter(household=self.household).order_by('name')
        categories = Category.objects.filter(household=self.household).order_by('name')

        if action == 'preview':
            ofx_file = request.FILES.get('ofx_file')
            account_id = request.POST.get('account')
            category_id = request.POST.get('category')

            if not ofx_file:
                messages.error(request, 'Por favor, selecione um arquivo .ofx para enviar.')
                return render(request, self.template_name, {
                    'accounts': accounts,
                    'categories': categories,
                    'preview_data': None,
                })

            account = Account.objects.filter(household=self.household, pk=account_id).first()
            if not account:
                messages.error(request, 'Conta de destino inválida.')
                return redirect('transactions:import_ofx')

            try:
                content = ofx_file.read()
                parsed = parse_nubank_ofx(content)
            except OfxParseError as e:
                messages.error(request, f'Erro ao ler o arquivo OFX: {e}')
                return render(request, self.template_name, {
                    'accounts': accounts,
                    'categories': categories,
                    'preview_data': None,
                })
            except Exception as e:
                messages.error(request, f'Formato de arquivo incompatível: {e}')
                return render(request, self.template_name, {
                    'accounts': accounts,
                    'categories': categories,
                    'preview_data': None,
                })

            items = []
            duplicate_count = 0
            new_count = 0

            for tx in parsed.transactions:
                is_duplicate = False
                if tx.external_id:
                    is_duplicate = SourceReference.objects.filter(
                        account=account,
                        external_id=tx.external_id,
                    ).exists()

                if not is_duplicate:
                    is_duplicate = Transaction.objects.filter(
                        account=account,
                        date=tx.posted_on,
                        amount=abs(tx.amount),
                        description=tx.description,
                    ).exists()

                if is_duplicate:
                    duplicate_count += 1
                else:
                    new_count += 1

                items.append({
                    'date': tx.posted_on.strftime('%Y-%m-%d'),
                    'description': tx.description,
                    'amount': float(abs(tx.amount)),
                    'type': tx.transaction_type,
                    'external_id': tx.external_id,
                    'is_duplicate': is_duplicate,
                })

            preview_data = {
                'account_id': str(account.pk),
                'account_name': account.name,
                'category_id': category_id,
                'period_start': parsed.statement_start.strftime('%d/%m/%Y'),
                'period_end': parsed.statement_end.strftime('%d/%m/%Y'),
                'total_count': len(items),
                'new_count': new_count,
                'duplicate_count': duplicate_count,
                'items': items,
            }

            request.session['ofx_import_preview'] = preview_data

            return render(request, self.template_name, {
                'accounts': accounts,
                'categories': categories,
                'preview_data': preview_data,
            })

        elif action == 'confirm':
            preview_data = request.session.pop('ofx_import_preview', None)
            if not preview_data or not preview_data.get('items'):
                messages.error(request, 'Nenhuma pré-visualização ativa encontrada. Por favor, envie o arquivo novamente.')
                return redirect('transactions:import_ofx')

            account = Account.objects.filter(
                household=self.household,
                pk=preview_data['account_id'],
            ).first()

            if not account:
                messages.error(request, 'Conta não encontrada.')
                return redirect('transactions:import_ofx')

            default_category = None
            if preview_data.get('category_id'):
                default_category = Category.objects.filter(
                    household=self.household,
                    pk=preview_data['category_id'],
                ).first()

            if not default_category:
                default_category = Category.objects.filter(household=self.household).first()

            if not default_category:
                default_category = Category.objects.create(
                    user=self.request.user,
                    household=self.household,
                    name='Outros',
                    type=Category.EXPENSE,
                )

            imported_count = 0
            with transaction.atomic():
                for item in preview_data['items']:
                    if item.get('is_duplicate'):
                        continue

                    tx = Transaction.objects.create(
                        user=self.request.user,
                        household=self.household,
                        financial_owner=account.financial_owner,
                        account=account,
                        category=default_category,
                        description=item['description'],
                        amount=Decimal(str(item['amount'])),
                        date=item['date'],
                        type=item['type'],
                    )

                    if item.get('external_id'):
                        SourceReference.objects.create(
                            account=account,
                            provider='nubank',
                            external_id=item['external_id'],
                            transaction=tx,
                        )

                    imported_count += 1

            messages.success(
                request,
                f'🎉 {imported_count} movimentações importadas com sucesso para a conta {account.name}!'
            )
            return redirect('transactions:list')

        return redirect('transactions:import_ofx')


