from decimal import Decimal

from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Sum
from django.utils import timezone
from django.views.generic import TemplateView

from accounts.models import Account
from transactions.models import Transaction


class HomeView(TemplateView):
    template_name = 'pages/home.html'


class DashboardView(LoginRequiredMixin, TemplateView):
    template_name = 'dashboard/index.html'

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        user = self.request.user
        today = timezone.localdate()

        # 6.4.1 — total balance: sum current_balance across all user accounts
        accounts = Account.objects.filter(user=user)
        total_balance = sum(
            (account.current_balance for account in accounts),
            Decimal('0.00'),
        )

        # 6.4.2 — monthly income and expenses via ORM aggregates
        monthly_qs = Transaction.objects.filter(
            user=user,
            date__year=today.year,
            date__month=today.month,
        )
        monthly_income = (
            monthly_qs.filter(type=Transaction.INCOME)
            .aggregate(total=Sum('amount'))['total']
            or Decimal('0.00')
        )
        monthly_expenses = (
            monthly_qs.filter(type=Transaction.EXPENSE)
            .aggregate(total=Sum('amount'))['total']
            or Decimal('0.00')
        )

        # 6.4.3 — top 5 expense categories for the current month
        expenses_by_category = (
            Transaction.objects.filter(
                user=user,
                type=Transaction.EXPENSE,
                date__year=today.year,
                date__month=today.month,
            )
            .values('category__name', 'category__color')
            .annotate(total=Sum('amount'))
            .order_by('-total')[:5]
        )

        # 6.4.extra — 10 most recent transactions with FK data pre-fetched
        recent_transactions = (
            Transaction.objects.filter(user=user)
            .select_related('account', 'category')[:10]
        )

        context['total_balance'] = total_balance
        context['monthly_income'] = monthly_income
        context['monthly_expenses'] = monthly_expenses
        context['expenses_by_category'] = expenses_by_category
        context['recent_transactions'] = recent_transactions

        return context
