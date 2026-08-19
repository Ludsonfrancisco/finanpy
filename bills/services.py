import calendar
from datetime import date
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from accounts.models import Account
from transactions.models import Transaction

from .models import BillInstance, RecurringBill


def get_month_due_date(year: int, month: int, day: int) -> date:
    """Calcula a data de vencimento garantindo ajuste para meses com menos dias."""
    _, last_day = calendar.monthrange(year, month)
    clamped_day = min(day, last_day)
    return date(year, month, clamped_day)


def ensure_monthly_bill_instances(household, month: int = None, year: int = None):
    """Garante que todas as contas fixas ativas tenham uma instância no mês/ano."""
    today = timezone.localdate()
    month = month or today.month
    year = year or today.year

    active_bills = RecurringBill.objects.filter(
        household=household,
        is_active=True,
    )

    for bill in active_bills:
        due_date = get_month_due_date(year, month, bill.due_day)
        BillInstance.objects.get_or_create(
            bill=bill,
            month=month,
            year=year,
            defaults={
                'household': household,
                'financial_owner': bill.financial_owner,
                'due_date': due_date,
                'amount': bill.amount,
                'status': BillInstance.STATUS_PENDING,
                'account': bill.default_account,
            },
        )

    return BillInstance.objects.filter(
        household=household,
        month=month,
        year=year,
    ).select_related('bill', 'bill__category', 'financial_owner', 'account')


def pay_bill_instance(instance: BillInstance, user, account: Account, paid_amount: Decimal, paid_date: date) -> Transaction:
    """Registra a baixa de pagamento da conta fixa e cria a transação no extrato."""
    with transaction.atomic():
        tx = Transaction.objects.create(
            user=user,
            household=instance.household,
            financial_owner=instance.financial_owner,
            account=account,
            category=instance.bill.category,
            description=f'{instance.bill.name} ({instance.month:02d}/{instance.year})',
            amount=paid_amount,
            date=paid_date,
            type=instance.bill.type,
        )

        instance.status = BillInstance.STATUS_PAID
        instance.paid_at = paid_date
        instance.amount = paid_amount
        instance.account = account
        instance.transaction = tx
        instance.save(update_fields=['status', 'paid_at', 'amount', 'account', 'transaction', 'updated_at'])

        return tx


def reopen_bill_instance(instance: BillInstance) -> None:
    """Reabre uma conta paga, estornando a transação vinculada."""
    with transaction.atomic():
        if instance.transaction:
            tx = instance.transaction
            instance.transaction = None
            instance.save(update_fields=['transaction', 'updated_at'])
            tx.delete()

        instance.status = BillInstance.STATUS_PENDING
        instance.paid_at = None
        instance.save(update_fields=['status', 'paid_at', 'updated_at'])


def get_bills_dashboard_metrics(household, month: int = None, year: int = None, financial_owner=None):
    """Calcula as métricas de contas fixas e Saldo Livre Real."""
    today = timezone.localdate()
    month = month or today.month
    year = year or today.year

    instances = ensure_monthly_bill_instances(household, month, year)
    if financial_owner:
        instances = instances.filter(financial_owner=financial_owner)

    pending_expenses = instances.filter(
        bill__type=RecurringBill.EXPENSE,
        status=BillInstance.STATUS_PENDING,
    )
    paid_expenses = instances.filter(
        bill__type=RecurringBill.EXPENSE,
        status=BillInstance.STATUS_PAID,
    )

    pending_expenses_total = pending_expenses.aggregate(total=Sum('amount'))['total'] or Decimal('0.00')
    paid_expenses_total = paid_expenses.aggregate(total=Sum('amount'))['total'] or Decimal('0.00')
    total_committed = pending_expenses_total + paid_expenses_total

    overdue_count = pending_expenses.filter(due_date__lt=today).count()
    due_today_count = pending_expenses.filter(due_date=today).count()

    upcoming_bills = pending_expenses.order_by('due_date')[:5]

    # Total account balances in household
    accounts_qs = Account.objects.filter(household=household)
    if financial_owner:
        accounts_qs = accounts_qs.filter(financial_owner=financial_owner)

    total_account_balance = Decimal('0.00')
    for acc in accounts_qs:
        total_account_balance += acc.current_balance

    free_cash_balance = total_account_balance - pending_expenses_total

    return {
        'month': month,
        'year': year,
        'pending_expenses_total': pending_expenses_total,
        'paid_expenses_total': paid_expenses_total,
        'total_committed': total_committed,
        'overdue_count': overdue_count,
        'due_today_count': due_today_count,
        'upcoming_bills': upcoming_bills,
        'total_account_balance': total_account_balance,
        'free_cash_balance': free_cash_balance,
    }
