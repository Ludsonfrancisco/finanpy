from datetime import date
from decimal import Decimal
from django.db.models import Sum, Q
from django.utils import timezone

from accounts.models import Account
from transactions.models import Transaction
from ai.models import AIAnalysis
from ai.agents.finance_insight_agent import FinanceInsightAgent

class AnalysisService:
    @staticmethod
    def run_for_user(user):
        # Define o período (mês atual)
        today = date.today()
        period_start = date(today.year, today.month, 1)
        # Próximo mês para calcular o fim deste mês
        if today.month == 12:
            period_end = date(today.year, today.month, 31)
        else:
            # Simplificação para pegar o último dia do mês atual
            import calendar
            _, last_day = calendar.monthrange(today.year, today.month)
            period_end = date(today.year, today.month, last_day)

        # Coleta de contexto
        user_name = user.profile.first_name or user.email
        
        # Contas e saldos atuais
        accounts_data = []
        for acc in Account.objects.filter(user=user):
            accounts_data.append({
                'name': acc.name,
                'type': acc.get_type_display(),
                'balance': float(acc.current_balance)
            })

        # Transações do período atual
        transactions = Transaction.objects.filter(user=user, date__range=[period_start, period_end])
        
        # Dados do mês anterior para comparação de tendência
        from datetime import timedelta
        last_month_end = period_start - timedelta(days=1)
        last_month_start = date(last_month_end.year, last_month_end.month, 1)
        prev_transactions = Transaction.objects.filter(user=user, date__range=[last_month_start, last_month_end])
        
        prev_aggregates = prev_transactions.aggregate(
            income=Sum('amount', filter=Q(type='income')),
            expense=Sum('amount', filter=Q(type='expense'))
        )

        # Totais do período atual
        aggregates = transactions.aggregate(
            total_income=Sum('amount', filter=Q(type='income')),
            total_expense=Sum('amount', filter=Q(type='expense'))
        )
        
        total_income = float(aggregates['total_income'] or 0)
        total_expense = float(aggregates['total_expense'] or 0)
        net = total_income - total_expense
        savings_rate = (net / total_income * 100) if total_income > 0 else 0

        # Breakdown por categoria
        category_breakdown = []
        breakdown_qs = transactions.values('category__name', 'type').annotate(
            total=Sum('amount')
        ).order_by('-total')

        for item in breakdown_qs:
            category_breakdown.append({
                'category': item['category__name'],
                'type': item['type'],
                'total': float(item['total'])
            })

        # Monta dict context rico
        context = {
            'user_name': user_name,
            'period': {
                'current_month': period_start.strftime('%B %Y'),
                'net_income': net,
                'savings_rate': f"{savings_rate:.1f}%",
            },
            'comparison_with_last_month': {
                'prev_income': float(prev_aggregates['income'] or 0),
                'prev_expense': float(prev_aggregates['expense'] or 0),
            },
            'accounts': accounts_data,
            'totals': {
                'income': total_income,
                'expense': total_expense,
            },
            'category_breakdown': category_breakdown
        }

        # Chama o agente
        agent = FinanceInsightAgent()
        result = agent.analyze(context)

        # Persiste a análise
        analysis = AIAnalysis.objects.create(
            user=user,
            analysis_text=result.summary,
            insights=result.insights,
            period_start=period_start,
            period_end=period_end,
            model_used='gpt-5-mini'
        )
        
        return analysis
