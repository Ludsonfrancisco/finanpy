from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import TemplateView


class HomeView(TemplateView):
    template_name = 'pages/home.html'


class DashboardView(LoginRequiredMixin, TemplateView):
    template_name = 'dashboard/index.html'

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)

        # TODO: wire to Account.objects and Transaction.objects once models are defined
        context['total_balance'] = 0
        context['monthly_income'] = 0
        context['monthly_expenses'] = 0
        context['recent_transactions'] = []

        return context
