from django import forms

from .models import Account

_INPUT_CLASSES = (
    'block w-full rounded-xl border border-slate-700 bg-slate-800 '
    'px-4 py-2.5 text-sm text-slate-100 placeholder-slate-500 '
    'focus:border-emerald-500 focus:outline-none focus:ring-2 '
    'focus:ring-emerald-500/40'
)


class AccountForm(forms.ModelForm):
    class Meta:
        model = Account
        fields = ['name', 'type', 'initial_balance', 'currency']
        widgets = {
            'name': forms.TextInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': 'Ex.: Nubank, Bradesco...',
            }),
            'type': forms.Select(attrs={
                'class': _INPUT_CLASSES,
            }),
            'initial_balance': forms.TextInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': '0.00',
            }),
            'currency': forms.TextInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': 'BRL',
                'maxlength': '3',
            }),
        }
