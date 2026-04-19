from django.conf import settings
from django.contrib.auth import login
from django.contrib.auth.views import LoginView, LogoutView  # noqa: F401 — re-exported for urls.py
from django.urls import reverse_lazy
from django.views.generic import CreateView

from .forms import LoginForm, SignUpForm


class SignUpView(CreateView):
    form_class = SignUpForm
    template_name = 'users/signup.html'
    success_url = reverse_lazy('users:login')

    def form_valid(self, form):
        response = super().form_valid(form)
        login(self.request, self.object)
        return response

    def get_success_url(self):
        return settings.LOGIN_REDIRECT_URL


class LoginView(LoginView):
    form_class = LoginForm
    template_name = 'users/login.html'
