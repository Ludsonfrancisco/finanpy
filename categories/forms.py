from django import forms

from households.forms import HouseholdModelFormMixin

from .models import Category

_INPUT_CLASSES = (
    'w-full rounded-xl border border-[#24302A] bg-[#121815] '
    'px-4 py-3 text-sm text-[#E8ECE9] placeholder-[#5C665F] '
    'transition focus:border-mineral focus:outline-none focus:ring-2 focus:ring-mineral/30'
)


class CategoryForm(HouseholdModelFormMixin, forms.ModelForm):
    class Meta:
        model = Category
        fields = ('name', 'type', 'color', 'icon')
        widgets = {
            'name': forms.TextInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': 'Ex: Alimentação, Moradia...'
            }),
            'type': forms.Select(attrs={
                'class': _INPUT_CLASSES
            }),
            'color': forms.TextInput(attrs={
                'type': 'color',
                'class': 'h-12 w-full cursor-pointer rounded-xl border border-[#24302A] bg-[#121815] p-1.5 transition focus:border-mineral focus:outline-none focus:ring-2 focus:ring-mineral/30'
            }),
            'icon': forms.TextInput(attrs={
                'class': _INPUT_CLASSES,
                'placeholder': 'Ex: fast-food'
            }),
        }
