from django import forms

from accounts.models import Account
from categories.models import Category

from .models import Transaction

_INPUT_CLASSES = (
    'block w-full rounded-xl border border-slate-700 bg-slate-800 '
    'px-4 py-2.5 text-sm text-slate-100 placeholder-slate-500 '
    'focus:border-emerald-500 focus:outline-none focus:ring-2 '
    'focus:ring-emerald-500/40'
)


class TransactionForm(forms.ModelForm):
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

    def __init__(self, *args, user=None, **kwargs):
        super().__init__(*args, **kwargs)
        if user:
            self.fields['account'].queryset = Account.objects.filter(user=user)
            self.fields['category'].queryset = Category.objects.filter(user=user)
