from django import forms

from households.forms import HouseholdModelFormMixin

from .models import Account

_INPUT_CLASSES = (
    'block w-full rounded-xl border border-[#24302A] bg-[#121815] '
    'px-4 py-3 text-sm text-[#E8ECE9] placeholder-[#5C665F] '
    'focus:border-mineral focus:outline-none focus:ring-2 '
    'focus:ring-mineral/30 transition'
)


class AccountForm(HouseholdModelFormMixin, forms.ModelForm):
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
