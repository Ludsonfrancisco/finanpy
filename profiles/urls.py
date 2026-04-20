from django.urls import path

from .views import ProfileUpdateView

app_name = 'profiles'

urlpatterns = [
    path('profile/edit/', ProfileUpdateView.as_view(), name='edit'),
]
