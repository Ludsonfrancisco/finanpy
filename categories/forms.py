from django import forms

from .models import Category


class CategoryForm(forms.ModelForm):
    class Meta:
        model = Category
        fields = ('name', 'type', 'color', 'icon')
        widgets = {
            'name': forms.TextInput(attrs={
                'class': 'w-full rounded-xl border border-slate-700 bg-slate-800 px-4 py-2.5 text-slate-100 placeholder-slate-500 transition focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/40',
                'placeholder': 'Ex: Alimentação'
            }),
            'type': forms.Select(attrs={
                'class': 'w-full rounded-xl border border-slate-700 bg-slate-800 px-4 py-2.5 text-slate-100 transition focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/40'
            }),
            'color': forms.TextInput(attrs={
                'type': 'color',
                'class': 'h-12 w-full cursor-pointer rounded-xl border border-slate-700 bg-slate-800 p-1 transition focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/40'
            }),
            'icon': forms.TextInput(attrs={
                'class': 'w-full rounded-xl border border-slate-700 bg-slate-800 px-4 py-2.5 text-slate-100 placeholder-slate-500 transition focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/40',
                'placeholder': 'Ex: fast-food'
            }),
        }
