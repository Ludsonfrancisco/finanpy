from django import forms
from django.utils import timezone

from accounts.models import Account
from categories.models import Category
from households.forms import HouseholdModelFormMixin
from households.models import FinancialOwner

from .models import RecurringBill

_INPUT_CLASSES = (
    'block w-full rounded-xl border border-[#24302A] bg-[#121815] '
    'px-4 py-3 text-sm text-[#E8ECE9] placeholder-[#5C665F] '
    'focus:border-mineral focus:outline-none focus:ring-2 '
    'focus:ring-mineral/30 transition'
)


class RecurringBillForm(HouseholdModelFormMixin, forms.ModelForm):
    class Meta:
        model = RecurringBill
        fields = [
            'name',
            'amount',
            'due_day',
            'type',
            'category',
            'default_account',
            'financial_owner',
            'is_active',
            'notes',
        ]
        widgets = {
            'name': forms.TextInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': 'Ex.: Aluguel, Internet Claro, Condomínio...',
            }),
            'amount': forms.NumberInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': '0.00',
                'step': '0.01',
            }),
            'due_day': forms.NumberInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': '1 a 31',
                'min': '1',
                'max': '31',
            }),
            'type': forms.Select(attrs={'class': _INPUT_CLASSES}),
            'category': forms.Select(attrs={'class': _INPUT_CLASSES}),
            'default_account': forms.Select(attrs={'class': _INPUT_CLASSES}),
            'financial_owner': forms.Select(attrs={'class': _INPUT_CLASSES}),
            'is_active': forms.CheckboxInput(attrs={
                'class': 'rounded-lg border-[#24302A] bg-[#121815] text-mineral focus:ring-mineral',
            }),
            'notes': forms.Textarea(attrs={
                'class': _INPUT_CLASSES,
                'rows': 3,
                'placeholder': 'Detalhes opcionais (código de barras, observações)...',
            }),
        }

    def __init__(self, *args, household=None, **kwargs):
        super().__init__(*args, **kwargs)
        if household:
            self.fields['category'].queryset = Category.objects.filter(household=household)
            self.fields['default_account'].queryset = Account.objects.filter(household=household)
            self.fields['financial_owner'].queryset = FinancialOwner.objects.filter(household=household)
            self.fields['default_account'].required = False
            self.fields['financial_owner'].required = False
        else:
            self.fields['category'].queryset = Category.objects.none()
            self.fields['default_account'].queryset = Account.objects.none()
            self.fields['financial_owner'].queryset = FinancialOwner.objects.none()


class PayBillModalForm(forms.Form):
    account = forms.ModelChoiceField(
        queryset=Account.objects.none(),
        label='Conta para Débito',
        widget=forms.Select(attrs={'class': _INPUT_CLASSES}),
    )
    paid_amount = forms.DecimalField(
        label='Valor Pago (R$)',
        max_digits=12,
        decimal_places=2,
        widget=forms.NumberInput(attrs={'class': _INPUT_CLASSES, 'step': '0.01'}),
    )
    paid_date = forms.DateField(
        label='Data do Pagamento',
        initial=timezone.localdate,
        widget=forms.DateInput(attrs={'class': _INPUT_CLASSES, 'type': 'date'}),
    )

    def __init__(self, *args, household=None, **kwargs):
        super().__init__(*args, **kwargs)
        if household:
            self.fields['account'].queryset = Account.objects.filter(household=household)
