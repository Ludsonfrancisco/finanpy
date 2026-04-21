from django import forms

from .models import Profile

_INPUT_CLASSES = (
    'block w-full rounded-xl border border-slate-700 bg-slate-800 px-4 py-2.5 '
    'text-sm text-slate-100 placeholder-slate-500 focus:border-emerald-500 '
    'focus:outline-none focus:ring-2 focus:ring-emerald-500/40'
)

_FILE_CLASSES = (
    'block w-full text-sm text-slate-400 file:mr-4 file:rounded-lg '
    'file:border-0 file:bg-emerald-500/10 file:px-4 file:py-2 '
    'file:text-xs file:font-medium file:text-emerald-400 '
    'hover:file:bg-emerald-500/20'
)


class ProfileForm(forms.ModelForm):
    class Meta:
        model = Profile
        fields = ['first_name', 'last_name', 'birth_date', 'avatar']
        widgets = {
            'first_name': forms.TextInput(attrs={'class': _INPUT_CLASSES}),
            'last_name': forms.TextInput(attrs={'class': _INPUT_CLASSES}),
            'birth_date': forms.DateInput(
                attrs={'class': _INPUT_CLASSES, 'type': 'date'}
            ),
            'avatar': forms.ClearableFileInput(attrs={'class': _FILE_CLASSES}),
        }
