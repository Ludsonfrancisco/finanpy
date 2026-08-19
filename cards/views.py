from decimal import Decimal

from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.shortcuts import get_object_or_404, redirect
from django.urls import reverse_lazy
from django.utils import timezone
from django.views import View
from django.views.generic import CreateView, DetailView, ListView, UpdateView

from households.mixins import HouseholdContextMixin

from .forms import CreditCardExpenseForm, CreditCardForm, PayInvoiceForm
from .models import CreditCard, CreditCardExpense, CreditCardInvoice
from .services import (
    calculate_card_metrics,
    create_card_expense,
    pay_card_invoice,
    reopen_card_invoice,
    resolve_or_create_invoice,
)


class CreditCardListView(LoginRequiredMixin, HouseholdContextMixin, ListView):
    model = CreditCard
    template_name = 'cards/list.html'
    context_object_name = 'cards'

    def get_queryset(self):
        return (
            CreditCard.objects.filter(household=self.household, is_active=True)
            .select_related('financial_owner')
            .order_by('name')
        )

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        now = timezone.localdate()

        cards_data = []
        total_limit = Decimal('0.00')
        total_used = Decimal('0.00')
        total_current_invoices = Decimal('0.00')

        for card in context['cards']:
            metrics = calculate_card_metrics(card, now.month, now.year)
            cards_data.append(metrics)
            total_limit += card.limit
            total_used += metrics['unpaid_expenses_total']
            total_current_invoices += metrics['current_invoice_total']

        total_available = max(Decimal('0.00'), total_limit - total_used)
        overall_usage_percent = (
            min(100.0, float((total_used / total_limit) * 100))
            if total_limit > 0
            else 0.0
        )

        context.update(
            {
                'cards_data': cards_data,
                'total_limit': total_limit,
                'total_used': total_used,
                'total_available': total_available,
                'total_current_invoices': total_current_invoices,
                'overall_usage_percent': overall_usage_percent,
                'card_form': CreditCardForm(household=self.household),
                'expense_form': CreditCardExpenseForm(household=self.household),
                'current_month': now.month,
                'current_year': now.year,
            }
        )
        return context


class CreditCardDetailView(LoginRequiredMixin, HouseholdContextMixin, DetailView):
    model = CreditCard
    template_name = 'cards/detail.html'
    context_object_name = 'card'

    def get_queryset(self):
        return CreditCard.objects.filter(household=self.household)

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        card = self.object
        now = timezone.localdate()

        try:
            month = int(self.request.GET.get('month', now.month))
            year = int(self.request.GET.get('year', now.year))
        except (ValueError, TypeError):
            month = now.month
            year = now.year

        # Fatura selecionada
        selected_invoice = resolve_or_create_invoice(card, month, year)
        expenses = selected_invoice.expenses.select_related(
            'category', 'financial_owner'
        ).order_by('-date', '-created_at')

        # Faturas futuras (próximos 6 meses)
        future_invoices = []
        for i in range(1, 7):
            f_month = ((month - 1 + i) % 12) + 1
            f_year = year + ((month - 1 + i) // 12)
            f_inv = resolve_or_create_invoice(card, f_month, f_year)
            if f_inv.expenses.exists():
                future_invoices.append(f_inv)

        # Faturas anteriores (últimos 6 meses)
        past_invoices = []
        for i in range(1, 7):
            p_month = ((month - 1 - i) % 12) + 1
            p_year = year + ((month - 1 - i) // 12)
            p_inv = CreditCardInvoice.objects.filter(
                credit_card=card, month=p_month, year=p_year
            ).first()
            if p_inv and p_inv.expenses.exists():
                past_invoices.append(p_inv)

        metrics = calculate_card_metrics(card, month, year)

        context.update(
            {
                'selected_invoice': selected_invoice,
                'expenses': expenses,
                'future_invoices': future_invoices,
                'past_invoices': past_invoices,
                'metrics': metrics,
                'selected_month': month,
                'selected_year': year,
                'card_form': CreditCardForm(instance=card, household=self.household),
                'expense_form': CreditCardExpenseForm(
                    initial={'credit_card': card},
                    household=self.household,
                ),
                'pay_form': PayInvoiceForm(
                    initial={'paid_amount': selected_invoice.total_amount},
                    household=self.household,
                ),
            }
        )
        return context


class CreditCardCreateView(LoginRequiredMixin, HouseholdContextMixin, CreateView):
    model = CreditCard
    form_class = CreditCardForm
    success_url = reverse_lazy('cards:list')

    def get_form_kwargs(self):
        kwargs = super().get_form_kwargs()
        kwargs['household'] = self.household
        return kwargs

    def form_valid(self, form):
        form.instance.household = self.household
        form.instance.user = self.request.user
        messages.success(
            self.request, f'Cartão "{form.instance.name}" criado com sucesso!'
        )
        return super().form_valid(form)


class CreditCardUpdateView(LoginRequiredMixin, HouseholdContextMixin, UpdateView):
    model = CreditCard
    form_class = CreditCardForm
    success_url = reverse_lazy('cards:list')

    def get_queryset(self):
        return CreditCard.objects.filter(household=self.household)

    def get_form_kwargs(self):
        kwargs = super().get_form_kwargs()
        kwargs['household'] = self.household
        return kwargs

    def form_valid(self, form):
        messages.success(
            self.request, f'Cartão "{form.instance.name}" atualizado com sucesso!'
        )
        return super().form_valid(form)


class CreditCardDeleteView(LoginRequiredMixin, HouseholdContextMixin, View):
    def post(self, request, pk):
        card = get_object_or_404(CreditCard, pk=pk, household=self.household)
        card.is_active = False
        card.save(update_fields=['is_active'])
        messages.success(request, f'Cartão "{card.name}" arquivado com sucesso!')
        return redirect('cards:list')


class CreditCardExpenseCreateView(LoginRequiredMixin, HouseholdContextMixin, View):
    def post(self, request):
        form = CreditCardExpenseForm(request.POST, household=self.household)
        if form.is_valid():
            card = form.cleaned_data['credit_card']
            expenses = create_card_expense(
                credit_card=card,
                description=form.cleaned_data['description'],
                total_amount=form.cleaned_data['amount'],
                purchase_date=form.cleaned_data['date'],
                category=form.cleaned_data['category'],
                installments_count=form.cleaned_data['installments_count'],
                financial_owner=form.cleaned_data.get('financial_owner'),
                user=request.user,
            )
            count = len(expenses)
            if count > 1:
                messages.success(
                    request,
                    f'Compra de R$ {form.cleaned_data["amount"]} parcelada em {count}x cadastrada com sucesso!',
                )
            else:
                messages.success(
                    request,
                    f'Compra "{expenses[0].description}" de R$ {expenses[0].amount} lançada na fatura!',
                )

            # Redireciona para o detalhe do cartão ou lista
            next_url = request.POST.get('next')
            if next_url:
                return redirect(next_url)
            return redirect('cards:detail', pk=card.pk)
        else:
            messages.error(
                request, 'Erro ao lançar despesa no cartão. Verifique os campos.'
            )
            return redirect('cards:list')


class CreditCardExpenseDeleteView(LoginRequiredMixin, HouseholdContextMixin, View):
    def post(self, request, pk):
        expense = get_object_or_404(CreditCardExpense, pk=pk, household=self.household)
        card_pk = expense.credit_card_id
        delete_all = request.POST.get('delete_all_installments') == 'true'

        if delete_all and expense.installments_count > 1:
            CreditCardExpense.objects.filter(
                installment_group_id=expense.installment_group_id,
                household=self.household,
            ).delete()
            messages.success(request, 'Todas as parcelas desta compra foram removidas.')
        else:
            expense.delete()
            messages.success(request, 'Lançamento removido da fatura.')

        next_url = request.POST.get('next')
        if next_url:
            return redirect(next_url)
        return redirect('cards:detail', pk=card_pk)


class PayInvoiceView(LoginRequiredMixin, HouseholdContextMixin, View):
    def post(self, request, pk):
        invoice = get_object_or_404(CreditCardInvoice, pk=pk, household=self.household)
        form = PayInvoiceForm(request.POST, household=self.household)

        if form.is_valid():
            account = form.cleaned_data['payment_account']
            amount = form.cleaned_data['paid_amount']
            p_date = form.cleaned_data['payment_date']

            pay_card_invoice(
                invoice=invoice,
                payment_account=account,
                paid_amount=amount,
                payment_date=p_date,
            )
            messages.success(
                request,
                f'Fatura de {invoice.month:02d}/{invoice.year} ({invoice.credit_card.name}) paga com sucesso via conta {account.name}!',
            )
        else:
            messages.error(request, 'Erro ao realizar pagamento da fatura.')

        return redirect('cards:detail', pk=invoice.credit_card_id)


class ReopenInvoiceView(LoginRequiredMixin, HouseholdContextMixin, View):
    def post(self, request, pk):
        invoice = get_object_or_404(CreditCardInvoice, pk=pk, household=self.household)
        reopen_card_invoice(invoice)
        messages.success(
            request,
            f'Pagamento da fatura de {invoice.month:02d}/{invoice.year} foi estornado com sucesso.',
        )
        return redirect('cards:detail', pk=invoice.credit_card_id)
