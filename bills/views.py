from datetime import date
from decimal import Decimal

from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.shortcuts import get_object_or_404, redirect
from django.urls import reverse_lazy
from django.utils import timezone
from django.views import View
from django.views.generic import CreateView, DeleteView, TemplateView, UpdateView

from accounts.models import Account
from households.forms import validate_instance_or_add_form_errors
from households.mixins import HouseholdContextMixin
from households.models import FinancialOwner

from .forms import RecurringBillForm
from .models import BillInstance, RecurringBill
from .services import (
    ensure_monthly_bill_instances,
    get_bills_dashboard_metrics,
    pay_bill_instance,
    reopen_bill_instance,
)


class BillListView(LoginRequiredMixin, HouseholdContextMixin, TemplateView):
    template_name = 'bills/list.html'

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        today = timezone.localdate()

        try:
            month = int(self.request.GET.get('month', today.month))
            year = int(self.request.GET.get('year', today.year))
        except (ValueError, TypeError):
            month = today.month
            year = today.year

        owner_slug = self.request.GET.get('owner', 'household')
        financial_owners = FinancialOwner.objects.filter(household=self.household)
        financial_owner = None
        if owner_slug == 'self':
            financial_owner = financial_owners.filter(type=FinancialOwner.SELF).first()
        elif owner_slug == 'spouse':
            financial_owner = financial_owners.filter(type=FinancialOwner.SPOUSE).first()
        elif owner_slug == 'shared':
            financial_owner = financial_owners.filter(type=FinancialOwner.SHARED).first()

        try:
            instances = ensure_monthly_bill_instances(self.household, month, year)
            if financial_owner:
                instances = instances.filter(financial_owner=financial_owner)
        except Exception:
            instances = BillInstance.objects.none()

        recurring_bills = RecurringBill.objects.filter(
            household=self.household,
        ).select_related('category', 'default_account', 'financial_owner')
        if financial_owner:
            recurring_bills = recurring_bills.filter(financial_owner=financial_owner)

        try:
            metrics = get_bills_dashboard_metrics(self.household, month, year, financial_owner)
        except Exception:
            metrics = {
                'month': month,
                'year': year,
                'pending_expenses_total': Decimal('0.00'),
                'paid_expenses_total': Decimal('0.00'),
                'total_committed': Decimal('0.00'),
                'overdue_count': 0,
                'due_today_count': 0,
                'upcoming_bills': [],
                'total_account_balance': Decimal('0.00'),
                'free_cash_balance': Decimal('0.00'),
            }

        accounts = Account.objects.filter(household=self.household).order_by('name')

        context.update({
            'instances': instances,
            'recurring_bills': recurring_bills,
            'metrics': metrics,
            'accounts': accounts,
            'selected_month': month,
            'selected_year': year,
            'owner_filter': owner_slug,
            'today': today,
            'active_tab': self.request.GET.get('tab', 'month'),
        })
        return context


class BillCreateView(LoginRequiredMixin, HouseholdContextMixin, CreateView):
    model = RecurringBill
    form_class = RecurringBillForm
    template_name = 'bills/form.html'
    success_url = reverse_lazy('bills:list')

    def get_form_kwargs(self):
        kwargs = super().get_form_kwargs()
        kwargs['household'] = self.household
        return kwargs

    def form_valid(self, form):
        form.instance.user = self.request.user
        form.instance.household = self.household
        if not getattr(form.instance, 'financial_owner_id', None):
            from households.models import FinancialOwner
            from households.services import get_financial_owner
            try:
                form.instance.financial_owner = get_financial_owner(self.household, FinancialOwner.SHARED)
            except Exception:
                form.instance.financial_owner = FinancialOwner.objects.filter(household=self.household).first()

        if not validate_instance_or_add_form_errors(form):
            return self.form_invalid(form)

        response = super().form_valid(form)
        try:
            ensure_monthly_bill_instances(self.household)
        except Exception:
            pass
        messages.success(self.request, f'Conta fixa "{self.object.name}" cadastrada com sucesso!')
        return response

    def form_invalid(self, form):
        messages.error(self.request, 'Por favor corrija os erros abaixo.')
        return super().form_invalid(form)


class BillUpdateView(LoginRequiredMixin, HouseholdContextMixin, UpdateView):
    model = RecurringBill
    form_class = RecurringBillForm
    template_name = 'bills/form.html'
    success_url = reverse_lazy('bills:list')

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)

    def get_form_kwargs(self):
        kwargs = super().get_form_kwargs()
        kwargs['household'] = self.household
        return kwargs

    def form_valid(self, form):
        if not getattr(form.instance, 'financial_owner_id', None):
            from households.models import FinancialOwner
            from households.services import get_financial_owner
            try:
                form.instance.financial_owner = get_financial_owner(self.household, FinancialOwner.SHARED)
            except Exception:
                form.instance.financial_owner = FinancialOwner.objects.filter(household=self.household).first()

        if not validate_instance_or_add_form_errors(form):
            return self.form_invalid(form)

        response = super().form_valid(form)
        messages.success(self.request, f'Conta fixa "{self.object.name}" atualizada com sucesso!')
        return response

    def form_invalid(self, form):
        messages.error(self.request, 'Por favor corrija os erros abaixo.')
        return super().form_invalid(form)


class BillDeleteView(LoginRequiredMixin, HouseholdContextMixin, DeleteView):
    model = RecurringBill
    template_name = 'bills/confirm_delete.html'
    success_url = reverse_lazy('bills:list')

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)

    def form_valid(self, form):
        messages.success(self.request, f'Conta fixa "{self.object.name}" excluída com sucesso.')
        return super().form_valid(form)


class PayBillView(LoginRequiredMixin, HouseholdContextMixin, View):
    def post(self, request, pk, *args, **kwargs):
        instance = get_object_or_404(BillInstance, pk=pk, household=self.household)
        account_id = request.POST.get('account')
        paid_amount_str = request.POST.get('paid_amount', str(instance.amount))
        paid_date_str = request.POST.get('paid_date', timezone.localdate().isoformat())

        account = get_object_or_404(Account, pk=account_id, household=self.household)

        try:
            paid_amount = Decimal(paid_amount_str.replace(',', '.'))
            paid_date = date.fromisoformat(paid_date_str)
        except Exception:
            messages.error(request, 'Dados de pagamento inválidos.')
            return redirect('bills:list')

        pay_bill_instance(instance, request.user, account, paid_amount, paid_date)
        messages.success(request, f'🎉 Conta "{instance.bill.name}" marcada como PAGA! Transação lançada em {account.name}.')
        return redirect('bills:list')


class ReopenBillView(LoginRequiredMixin, HouseholdContextMixin, View):
    def post(self, request, pk, *args, **kwargs):
        instance = get_object_or_404(BillInstance, pk=pk, household=self.household)
        reopen_bill_instance(instance)
        messages.success(request, f'Pagamento de "{instance.bill.name}" desfeito com sucesso.')
        return redirect('bills:list')
