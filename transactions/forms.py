from django import forms

from accounts.models import Account
from categories.models import Category
from households.forms import HouseholdModelFormMixin

from .models import Transaction

_INPUT_CLASSES = (
    'block w-full rounded-xl border border-[#24302A] bg-[#121815] '
    'px-4 py-3 text-sm text-[#E8ECE9] placeholder-[#5C665F] '
    'focus:border-mineral focus:outline-none focus:ring-2 '
    'focus:ring-mineral/30 transition'
)


class TransactionForm(HouseholdModelFormMixin, forms.ModelForm):
    class Meta:
        model = Transaction
        fields = ['account', 'category', 'description', 'amount', 'date', 'type']
        widgets = {
            'account': forms.Select(attrs={'class': _INPUT_CLASSES}),
            'category': forms.Select(attrs={'class': _INPUT_CLASSES}),
            'description': forms.TextInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': 'Ex.: Supermercado, Salário...',
            }),
            'amount': forms.NumberInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': '0.00',
                'step': '0.01',
            }),
            'date': forms.DateInput(attrs={
                'class': _INPUT_CLASSES,
                'type': 'date',
            }),
            'type': forms.Select(attrs={'class': _INPUT_CLASSES}),
        }

    def __init__(self, *args, household=None, **kwargs):
        super().__init__(*args, **kwargs)
        if household:
            self.fields['account'].queryset = Account.objects.filter(household=household)
            self.fields['category'].queryset = Category.objects.filter(household=household)
        else:
            self.fields['account'].queryset = Account.objects.none()
            self.fields['category'].queryset = Category.objects.none()
