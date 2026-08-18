import calendar
from decimal import Decimal

from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Sum
from django.shortcuts import redirect
from django.utils import timezone
from django.views import View
from django.views.generic import TemplateView

from accounts.models import Account
from households.mixins import HouseholdContextMixin
from households.models import FinancialOwner
from transactions.models import Transaction


class HomeView(View):
    def get(self, request):
        if request.user.is_authenticated:
            return redirect('dashboard')
        return redirect('users:login')


class DashboardView(LoginRequiredMixin, HouseholdContextMixin, TemplateView):
    template_name = 'dashboard/index.html'

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        household = self.household
        today = timezone.localdate()

        # Seletor de titular contábil (Lar / Eu / Esposa / Conjunto)
        owner_filter = self.request.GET.get('owner', 'household')
        financial_owners = FinancialOwner.objects.filter(household=household)

        selected_owner = None
        if owner_filter == 'self':
            selected_owner = financial_owners.filter(type=FinancialOwner.SELF).first()
        elif owner_filter == 'spouse':
            selected_owner = financial_owners.filter(type=FinancialOwner.SPOUSE).first()
        elif owner_filter == 'shared':
            selected_owner = financial_owners.filter(type=FinancialOwner.SHARED).first()
        elif owner_filter and owner_filter != 'household':
            selected_owner = financial_owners.filter(uuid=owner_filter).first()

        # Contas bancárias
        accounts_qs = Account.objects.filter(household=household)
        if selected_owner:
            accounts_qs = accounts_qs.filter(financial_owner=selected_owner)

        total_balance = sum(
            (account.current_balance for account in accounts_qs),
            Decimal('0.00'),
        )

        # Transações base filtradas por titular contábil
        base_tx_qs = Transaction.objects.filter(household=household)
        if selected_owner:
            base_tx_qs = base_tx_qs.filter(financial_owner=selected_owner)

        # Receitas e Despesas do Mês Atual
        monthly_qs = base_tx_qs.filter(
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
        monthly_net = monthly_income - monthly_expenses

        # Taxa de Poupança Familiar (%)
        if monthly_income > Decimal('0.00') and monthly_expenses < monthly_income:
            savings_rate = float(((monthly_income - monthly_expenses) / monthly_income) * 100)
        else:
            savings_rate = 0.0

        # Maiores Despesas por Categoria no Mês (com cálculo de porcentagem)
        cat_raw = (
            monthly_qs.filter(type=Transaction.EXPENSE)
            .values('category__name', 'category__color')
            .annotate(total=Sum('amount'))
            .order_by('-total')[:6]
        )
        expenses_by_category = []
        for item in cat_raw:
            tot = item['total'] or Decimal('0.00')
            pct = float((tot / monthly_expenses) * 100) if monthly_expenses > Decimal('0.00') else 0.0
            expenses_by_category.append({
                'name': item['category__name'],
                'color': item['category__color'] or '#2F756A',
                'category__name': item['category__name'],
                'category__color': item['category__color'] or '#2F756A',
                'total': tot,
                'percentage': round(pct, 1),
            })

        # Fluxo Mensal dos Últimos 6 Meses
        monthly_flows = []
        pt_months = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez']
        for offset in reversed(range(6)):
            m = today.month - offset
            y = today.year
            while m <= 0:
                m += 12
                y -= 1
            
            flow_qs = base_tx_qs.filter(date__year=y, date__month=m)
            inc = flow_qs.filter(type=Transaction.INCOME).aggregate(t=Sum('amount'))['t'] or Decimal('0.00')
            exp = flow_qs.filter(type=Transaction.EXPENSE).aggregate(t=Sum('amount'))['t'] or Decimal('0.00')
            
            monthly_flows.append({
                'label': f'{pt_months[m]}/{str(y)[2:]}',
                'income': float(inc),
                'expense': float(exp),
                'net': float(inc - exp),
            })

        # 10 Transações Recentes
        recent_transactions = (
            base_tx_qs.select_related('account', 'category', 'financial_owner')[:10]
        )

        context['total_balance'] = total_balance
        context['monthly_income'] = monthly_income
        context['monthly_expenses'] = monthly_expenses
        context['monthly_net'] = monthly_net
        context['savings_rate'] = round(savings_rate, 1)
        context['expenses_by_category'] = expenses_by_category
        context['monthly_flows'] = monthly_flows
        context['recent_transactions'] = recent_transactions
        context['financial_owners'] = financial_owners
        context['owner_filter'] = owner_filter
        context['selected_owner'] = selected_owner

        return context
