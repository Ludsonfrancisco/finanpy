from django import forms
from django.contrib.auth.forms import AuthenticationForm

_INPUT_CLASSES = (
    'block w-full rounded-xl border border-slate-700 bg-slate-800 '
    'px-4 py-2.5 text-sm text-slate-100 placeholder-slate-400 '
    'focus:border-emerald-500 focus:outline-none focus:ring-2 '
    'focus:ring-emerald-500/40'
)


class LoginForm(AuthenticationForm):
    username = forms.EmailField(
        label='E-mail',
        widget=forms.EmailInput(attrs={
            'class': _INPUT_CLASSES,
            'placeholder': 'seu@email.com',
            'autofocus': True,
        }),
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['password'].widget.attrs.update({
            'class': _INPUT_CLASSES,
            'placeholder': 'Senha',
        })
