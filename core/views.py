import calendar
from decimal import Decimal

from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Sum
from django.shortcuts import redirect
from django.utils import timezone
from django.views import View
from django.views.generic import TemplateView

from accounts.models import Account
from bills.services import get_bills_dashboard_metrics
from categories.models import Category
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

        # Módulo Ano da Seca: Tetos Orçamentários e Daily Burn Rate
        categories_expense_qs = Category.objects.filter(household=household, type=Category.EXPENSE)
        total_budget = categories_expense_qs.filter(budget__gt=0).aggregate(total=Sum('budget'))['total'] or Decimal('0.00')

        _, last_day = calendar.monthrange(today.year, today.month)
        days_remaining = max(1, last_day - today.day + 1)

        budgeted_cat_ids = categories_expense_qs.filter(budget__gt=0).values_list('id', flat=True)
        if total_budget > Decimal('0.00'):
            budgeted_expenses = (
                monthly_qs.filter(type=Transaction.EXPENSE, category_id__in=budgeted_cat_ids)
                .aggregate(total=Sum('amount'))['total']
                or Decimal('0.00')
            )
            budget_remaining = total_budget - budgeted_expenses
            if budget_remaining > Decimal('0.00'):
                daily_burn_rate = budget_remaining / Decimal(str(days_remaining))
                is_over_budget = False
                over_budget_amount = Decimal('0.00')
            else:
                daily_burn_rate = Decimal('0.00')
                is_over_budget = (budget_remaining < Decimal('0.00'))
                over_budget_amount = abs(budget_remaining)

            budget_usage_pct = round(float((budgeted_expenses / total_budget) * 100), 1)
            if is_over_budget:
                budget_status = 'danger'
                budget_status_label = f'Estouro de R$ {over_budget_amount:.2f}'
            elif budget_usage_pct >= 85.0:
                budget_status = 'warning'
                budget_status_label = f'{budget_usage_pct}% do teto consumido'
            else:
                budget_status = 'safe'
                budget_status_label = f'{budget_usage_pct}% do teto consumido'
        else:
            budgeted_expenses = Decimal('0.00')
            budget_remaining = Decimal('0.00')
            daily_burn_rate = Decimal('0.00')
            is_over_budget = False
            over_budget_amount = Decimal('0.00')
            budget_usage_pct = 0.0
            budget_status = 'unset'
            budget_status_label = 'Defina tetos nas categorias'

        # Maiores Despesas por Categoria no Mês (com teto e porcentagem)
        cat_raw = (
            monthly_qs.filter(type=Transaction.EXPENSE)
            .values('category__name', 'category__color', 'category__budget')
            .annotate(total=Sum('amount'))
            .order_by('-total')[:6]
        )
        expenses_by_category = []
        for item in cat_raw:
            tot = item['total'] or Decimal('0.00')
            pct = float((tot / monthly_expenses) * 100) if monthly_expenses > Decimal('0.00') else 0.0
            cat_budget = item.get('category__budget') or Decimal('0.00')
            cat_budget_pct = round(float((tot / cat_budget) * 100), 1) if cat_budget > Decimal('0.00') else None
            cat_is_over = tot > cat_budget if cat_budget > Decimal('0.00') else False

            expenses_by_category.append({
                'name': item['category__name'],
                'color': item['category__color'] or '#2F756A',
                'category__name': item['category__name'],
                'category__color': item['category__color'] or '#2F756A',
                'total': tot,
                'percentage': round(pct, 1),
                'budget': cat_budget,
                'budget_percentage': cat_budget_pct,
                'is_over_budget': cat_is_over,
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

        bills_metrics = get_bills_dashboard_metrics(household, today.month, today.year, selected_owner)

        context['total_balance'] = total_balance
        context['bills_metrics'] = bills_metrics
        context['free_cash_balance'] = bills_metrics['free_cash_balance']
        context['pending_bills_total'] = bills_metrics['pending_expenses_total']
        context['upcoming_bills'] = bills_metrics['upcoming_bills']
        context['overdue_bills_count'] = bills_metrics['overdue_count']
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

        # Contexto do Módulo Ano da Seca
        context['total_budget'] = total_budget
        context['budgeted_expenses'] = budgeted_expenses
        context['budget_remaining'] = budget_remaining
        context['daily_burn_rate'] = round(daily_burn_rate, 2)
        context['days_remaining'] = days_remaining
        context['is_over_budget'] = is_over_budget
        context['over_budget_amount'] = over_budget_amount
        context['budget_usage_pct'] = budget_usage_pct
        context['budget_status'] = budget_status
        context['budget_status_label'] = budget_status_label

        return context
