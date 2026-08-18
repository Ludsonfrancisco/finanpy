from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import ProtectedError
from django.shortcuts import redirect
from django.urls import reverse_lazy
from django.views.generic import CreateView, DeleteView, ListView, UpdateView

from households.forms import validate_instance_or_add_form_errors
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
        if not validate_instance_or_add_form_errors(form):
            return self.form_invalid(form)
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
        if not validate_instance_or_add_form_errors(form):
            return self.form_invalid(form)
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
        try:
            response = super().form_valid(form)
            messages.success(self.request, 'Conta excluída com sucesso.')
            return response
        except ProtectedError:
            messages.error(
                self.request,
                'Não foi possível excluir a conta porque existem registros vinculados protegidos.'
            )
            return redirect('accounts:list')

