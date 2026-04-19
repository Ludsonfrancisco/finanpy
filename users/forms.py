from django.contrib.auth import get_user_model
from django.contrib.auth.forms import AuthenticationForm, UserCreationForm
from django import forms


_INPUT_CLASSES = (
    'w-full bg-slate-800 border border-slate-700 text-slate-100 '
    'rounded-xl px-4 py-2.5 focus:outline-none focus:ring-2 '
    'focus:ring-emerald-500 placeholder-slate-400'
)


class SignUpForm(UserCreationForm):
    class Meta:
        model = get_user_model()
        fields = ('email',)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields.values():
            field.widget.attrs.update({'class': _INPUT_CLASSES})
        self.fields['email'].widget.attrs['placeholder'] = 'seu@email.com'
        self.fields['password1'].widget.attrs['placeholder'] = 'Senha'
        self.fields['password2'].widget.attrs['placeholder'] = 'Confirme a senha'


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
