from decimal import Decimal
from datetime import date

from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Sum
from django.utils import timezone
from django.views.generic import TemplateView

from accounts.models import Account
from transactions.models import Transaction
from ai.models import AIAnalysis


class HomeView(TemplateView):
    template_name = 'pages/home.html'


class DashboardView(LoginRequiredMixin, TemplateView):
    template_name = 'dashboard/index.html'

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        user = self.request.user
        
        # 1. Month/Year selection logic
        today = timezone.localdate()
        month = int(self.request.GET.get('month', today.month))
        year = int(self.request.GET.get('year', today.year))
        
        # Helper for date ranges
        import calendar
        _, last_day = calendar.monthrange(year, month)
        start_date = date(year, month, 1)
        end_date = date(year, month, last_day)

        # 2. Metrics (Filtered by selected month)
        accounts = Account.objects.filter(user=user)
        total_balance = sum((acc.current_balance for acc in accounts), Decimal('0.00'))

        monthly_qs = Transaction.objects.filter(user=user, date__range=[start_date, end_date])
        monthly_income = monthly_qs.filter(type=Transaction.INCOME).aggregate(total=Sum('amount'))['total'] or Decimal('0.00')
        monthly_expenses = monthly_qs.filter(type=Transaction.EXPENSE).aggregate(total=Sum('amount'))['total'] or Decimal('0.00')

        # 3. Chart Data: Last 6 Months Cash Flow
        six_months_ago = today - timezone.timedelta(days=180)
        history_qs = Transaction.objects.filter(user=user, date__gte=six_months_ago)
        
        cash_flow_labels = []
        cash_flow_income = []
        cash_flow_expense = []
        
        # Simple loop to get last 6 months
        for i in range(5, -1, -1):
            d = today - timezone.timedelta(days=i*30)
            month_idx = d.month
            year_idx = d.year
            label = d.strftime('%b')
            
            period_data = Transaction.objects.filter(user=user, date__year=year_idx, date__month=month_idx)
            inc = period_data.filter(type=Transaction.INCOME).aggregate(total=Sum('amount'))['total'] or 0
            exp = period_data.filter(type=Transaction.EXPENSE).aggregate(total=Sum('amount'))['total'] or 0
            
            cash_flow_labels.append(label)
            cash_flow_income.append(float(inc))
            cash_flow_expense.append(float(exp))

        # 4. Expenses by category (Pie Chart Data)
        expenses_by_category = (
            monthly_qs.filter(type=Transaction.EXPENSE)
            .values('category__name', 'category__color')
            .annotate(total=Sum('amount'))
            .order_by('-total')
        )

        context.update({
            'total_balance': total_balance,
            'monthly_income': monthly_income,
            'monthly_expenses': monthly_expenses,
            'expenses_by_category': expenses_by_category,
            'recent_transactions': Transaction.objects.filter(user=user).select_related('account', 'category')[:10],
            'latest_analysis': AIAnalysis.objects.filter(user=user).order_by('-created_at').first(),
            'chart_labels': cash_flow_labels,
            'chart_income': cash_flow_income,
            'chart_expense': cash_flow_expense,
            'selected_month': month,
            'selected_year': year,
            'available_months': range(1, 13),
            'available_years': range(today.year - 2, today.year + 1),
        })
        return context
