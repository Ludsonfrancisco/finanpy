from django import forms

from .models import Profile

_INPUT_CLASSES = (
    'block w-full rounded-xl border border-[#24302A] bg-[#121815] px-4 py-3 '
    'text-sm text-[#E8ECE9] placeholder-[#5C665F] focus:border-mineral '
    'focus:outline-none focus:ring-2 focus:ring-mineral/30 transition'
)

_FILE_CLASSES = (
    'block w-full text-xs text-[#8D958D] file:mr-4 file:rounded-xl '
    'file:border-0 file:bg-mineral/15 file:px-4 file:py-2.5 '
    'file:text-xs file:font-bold file:text-mineral-light '
    'hover:file:bg-mineral/25 transition cursor-pointer'
)


class ProfileForm(forms.ModelForm):
    class Meta:
        model = Profile
        fields = ['first_name', 'last_name', 'birth_date', 'avatar']
        widgets = {
            'first_name': forms.TextInput(attrs={'class': _INPUT_CLASSES}),
            'last_name': forms.TextInput(attrs={'class': _INPUT_CLASSES}),
            'birth_date': forms.DateInput(
                format='%Y-%m-%d',
                attrs={'class': _INPUT_CLASSES, 'type': 'date'},
            ),
            'avatar': forms.ClearableFileInput(attrs={'class': _FILE_CLASSES}),
        }
