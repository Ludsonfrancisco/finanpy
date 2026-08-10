from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.urls import reverse_lazy
from django.views.generic import CreateView, DeleteView, ListView, UpdateView

from households.forms import validate_instance_or_add_form_errors
from households.mixins import HouseholdContextMixin

from .forms import CategoryForm
from .models import Category


class CategoryListView(LoginRequiredMixin, HouseholdContextMixin, ListView):
    model = Category
    template_name = 'categories/list.html'
    context_object_name = 'categories'

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)


class CategoryCreateView(LoginRequiredMixin, HouseholdContextMixin, CreateView):
    model = Category
    form_class = CategoryForm
    template_name = 'categories/form.html'
    success_url = reverse_lazy('categories:list')

    def form_valid(self, form):
        form.instance.user = self.request.user
        form.instance.household = self.household
        if not validate_instance_or_add_form_errors(form):
            return self.form_invalid(form)
        messages.success(self.request, 'Categoria criada com sucesso.')
        return super().form_valid(form)

    def form_invalid(self, form):
        messages.error(self.request, 'Por favor corrija os erros abaixo.')
        return super().form_invalid(form)


class CategoryUpdateView(LoginRequiredMixin, HouseholdContextMixin, UpdateView):
    model = Category
    form_class = CategoryForm
    template_name = 'categories/form.html'
    success_url = reverse_lazy('categories:list')

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)

    def form_valid(self, form):
        if not validate_instance_or_add_form_errors(form):
            return self.form_invalid(form)
        messages.success(self.request, 'Categoria atualizada com sucesso.')
        return super().form_valid(form)

    def form_invalid(self, form):
        messages.error(self.request, 'Por favor corrija os erros abaixo.')
        return super().form_invalid(form)


class CategoryDeleteView(LoginRequiredMixin, HouseholdContextMixin, DeleteView):
    model = Category
    template_name = 'categories/confirm_delete.html'
    success_url = reverse_lazy('categories:list')

    def get_queryset(self):
        return super().get_queryset().filter(household=self.household)

    def form_valid(self, form):
        messages.success(self.request, 'Categoria excluída com sucesso.')
        return super().form_valid(form)
