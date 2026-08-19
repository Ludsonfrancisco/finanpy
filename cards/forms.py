from decimal import Decimal

from django import forms
from django.utils import timezone

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner

from .models import CreditCard


class CreditCardForm(forms.ModelForm):
    class Meta:
        model = CreditCard
        fields = [
            'name',
            'limit',
            'closing_day',
            'due_day',
            'color',
            'brand',
            'last_digits',
            'financial_owner',
        ]
        widgets = {
            'name': forms.TextInput(
                attrs={
                    'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500',
                    'placeholder': 'Ex: Nubank Ultravioleta, XP Infinite',
                }
            ),
            'limit': forms.NumberInput(
                attrs={
                    'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500',
                    'placeholder': '5000.00',
                    'step': '0.01',
                }
            ),
            'closing_day': forms.NumberInput(
                attrs={
                    'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500',
                    'min': '1',
                    'max': '31',
                    'placeholder': 'Ex: 10',
                }
            ),
            'due_day': forms.NumberInput(
                attrs={
                    'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500',
                    'min': '1',
                    'max': '31',
                    'placeholder': 'Ex: 17',
                }
            ),
            'color': forms.TextInput(
                attrs={
                    'class': 'w-full h-10 px-2 py-1 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
                    'type': 'color',
                }
            ),
            'brand': forms.Select(
                attrs={
                    'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
                }
            ),
            'last_digits': forms.TextInput(
                attrs={
                    'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500',
                    'placeholder': 'Ex: 1234',
                    'maxlength': '4',
                }
            ),
            'financial_owner': forms.Select(
                attrs={
                    'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
                }
            ),
        }

    def __init__(self, *args, household=None, **kwargs):
        super().__init__(*args, **kwargs)
        if household:
            self.fields['financial_owner'].queryset = FinancialOwner.objects.filter(
                household=household, is_active=True
            )


class CreditCardExpenseForm(forms.Form):
    credit_card = forms.ModelChoiceField(
        queryset=CreditCard.objects.none(),
        label='Cartão de Crédito',
        widget=forms.Select(
            attrs={
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
            }
        ),
    )
    description = forms.CharField(
        max_length=200,
        label='Descrição da Compra',
        widget=forms.TextInput(
            attrs={
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500',
                'placeholder': 'Ex: Passagens aéreas, Restaurante',
            }
        ),
    )
    amount = forms.DecimalField(
        max_digits=12,
        decimal_places=2,
        min_value=Decimal('0.01'),
        label='Valor Total da Compra (R$)',
        widget=forms.NumberInput(
            attrs={
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500',
                'placeholder': '0.00',
                'step': '0.01',
            }
        ),
    )
    date = forms.DateField(
        label='Data da Compra',
        initial=timezone.localdate,
        widget=forms.DateInput(
            attrs={
                'type': 'date',
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
            }
        ),
    )
    category = forms.ModelChoiceField(
        queryset=Category.objects.none(),
        label='Categoria',
        widget=forms.Select(
            attrs={
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
            }
        ),
    )
    installments_count = forms.IntegerField(
        min_value=1,
        max_value=48,
        initial=1,
        label='Número de Parcelas',
        widget=forms.NumberInput(
            attrs={
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
                'min': '1',
                'max': '48',
            }
        ),
    )
    financial_owner = forms.ModelChoiceField(
        queryset=FinancialOwner.objects.none(),
        required=False,
        label='Titular (Opcional)',
        widget=forms.Select(
            attrs={
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
            }
        ),
    )

    def __init__(self, *args, household=None, **kwargs):
        super().__init__(*args, **kwargs)
        if household:
            self.fields['credit_card'].queryset = CreditCard.objects.filter(
                household=household, is_active=True
            )
            self.fields['category'].queryset = Category.objects.filter(
                household=household, type='expense'
            )
            self.fields['financial_owner'].queryset = FinancialOwner.objects.filter(
                household=household, is_active=True
            )


class PayInvoiceForm(forms.Form):
    payment_account = forms.ModelChoiceField(
        queryset=Account.objects.none(),
        label='Conta Bancária para Débito',
        widget=forms.Select(
            attrs={
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
            }
        ),
    )
    paid_amount = forms.DecimalField(
        max_digits=12,
        decimal_places=2,
        min_value=Decimal('0.01'),
        label='Valor do Pagamento (R$)',
        widget=forms.NumberInput(
            attrs={
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
                'step': '0.01',
            }
        ),
    )
    payment_date = forms.DateField(
        label='Data do Pagamento',
        initial=timezone.localdate,
        widget=forms.DateInput(
            attrs={
                'type': 'date',
                'class': 'w-full px-4 py-2.5 bg-slate-800 border border-slate-700 rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-emerald-500',
            }
        ),
    )

    def __init__(self, *args, household=None, **kwargs):
        super().__init__(*args, **kwargs)
        if household:
            self.fields['payment_account'].queryset = Account.objects.filter(
                household=household
            )
