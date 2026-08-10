from django.contrib.auth.views import LoginView, LogoutView  # noqa: F401

from .forms import LoginForm


class LoginView(LoginView):
    form_class = LoginForm
    template_name = 'users/login.html'
    redirect_authenticated_user = True
