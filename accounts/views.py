from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.urls import reverse_lazy
from django.views.generic import CreateView, DeleteView, ListView, UpdateView

from households.mixins import HouseholdContextMixin
from households.services import get_financial_owner

from .forms import AccountForm
from .models import Account


class AccountListView(LoginRequiredMixin, HouseholdContextMixin, ListView):
    model = Account
    template_name = 'accounts/list.html'
    context_object_name = 'accounts'

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)


class AccountCreateView(LoginRequiredMixin, HouseholdContextMixin, CreateView):
    model = Account
    form_class = AccountForm
    template_name = 'accounts/form.html'
    success_url = reverse_lazy('accounts:list')

    def form_valid(self, form):
        form.instance.user = self.request.user
        form.instance.household = self.household
        form.instance.financial_owner = get_financial_owner(self.household)
        form.instance.full_clean()
        messages.success(self.request, 'Conta criada com sucesso.')
        return super().form_valid(form)

    def form_invalid(self, form):
        messages.error(self.request, 'Por favor corrija os erros abaixo.')
        return super().form_invalid(form)


class AccountUpdateView(LoginRequiredMixin, HouseholdContextMixin, UpdateView):
    model = Account
    form_class = AccountForm
    template_name = 'accounts/form.html'
    success_url = reverse_lazy('accounts:list')

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)

    def form_valid(self, form):
        messages.success(self.request, 'Conta atualizada com sucesso.')
        return super().form_valid(form)

    def form_invalid(self, form):
        messages.error(self.request, 'Por favor corrija os erros abaixo.')
        return super().form_invalid(form)


class AccountDeleteView(LoginRequiredMixin, HouseholdContextMixin, DeleteView):
    model = Account
    template_name = 'accounts/confirm_delete.html'
    success_url = reverse_lazy('accounts:list')

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)

    def form_valid(self, form):
        messages.success(self.request, 'Conta excluída com sucesso.')
        return super().form_valid(form)
