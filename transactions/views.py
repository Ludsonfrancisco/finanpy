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
