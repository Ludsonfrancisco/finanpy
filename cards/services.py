import calendar
import uuid
from datetime import date
from decimal import ROUND_DOWN, Decimal

from django.db import models, transaction
from django.utils import timezone

from categories.models import Category
from households.models import FinancialOwner
from transactions.models import Transaction

from .models import CreditCard, CreditCardExpense, CreditCardInvoice


def get_safe_date(year: int, month: int, day: int) -> date:
    """Calcula uma data segura limitando o dia ao último dia válido do mês."""
    max_days = calendar.monthrange(year, month)[1]
    safe_day = min(day, max_days)
    return date(year, month, safe_day)


def get_next_month_year(month: int, year: int, increment: int = 1) -> tuple[int, int]:
    """Calcula o mês e ano após N incrementos."""
    total_months = month - 1 + increment
    new_year = year + (total_months // 12)
    new_month = (total_months % 12) + 1
    return new_month, new_year


def get_invoice_dates(
    credit_card: CreditCard, month: int, year: int
) -> tuple[date, date]:
    """
    Calcula as datas de fechamento e vencimento para a fatura de um determinado mês de referência.
    - Data de vencimento: devidamente alocada no mês/ano de referência.
    - Data de fechamento: normalmente ocorre dias antes do vencimento (no mês anterior ou no mesmo mês).
    """
    due_date = get_safe_date(year, month, credit_card.due_day)

    # Se o dia de fechamento for maior que o dia de vencimento, a fatura fecha no mês anterior
    if credit_card.closing_day > credit_card.due_day:
        prev_month, prev_year = get_next_month_year(month, year, -1)
        closing_date = get_safe_date(prev_year, prev_month, credit_card.closing_day)
    else:
        closing_date = get_safe_date(year, month, credit_card.closing_day)

    return closing_date, due_date


def resolve_or_create_invoice(
    credit_card: CreditCard, month: int, year: int
) -> CreditCardInvoice:
    """Obtém ou cria a fatura de um cartão para um mês e ano específicos com status atualizado."""
    closing_date, due_date = get_invoice_dates(credit_card, month, year)

    invoice, created = CreditCardInvoice.objects.get_or_create(
        credit_card=credit_card,
        month=month,
        year=year,
        defaults={
            'household': credit_card.household,
            'closing_date': closing_date,
            'due_date': due_date,
            'status': CreditCardInvoice.STATUS_OPEN,
        },
    )

    # Atualiza status temporal caso ainda esteja aberta
    if not created and invoice.status in [
        CreditCardInvoice.STATUS_OPEN,
        CreditCardInvoice.STATUS_CLOSED,
    ]:
        today = timezone.localdate()
        if invoice.status != CreditCardInvoice.STATUS_PAID:
            if today > invoice.due_date:
                invoice.status = CreditCardInvoice.STATUS_OVERDUE
                invoice.save(update_fields=['status'])
            elif (
                today >= invoice.closing_date
                and invoice.status == CreditCardInvoice.STATUS_OPEN
            ):
                invoice.status = CreditCardInvoice.STATUS_CLOSED
                invoice.save(update_fields=['status'])

    return invoice


def calculate_target_invoice_for_purchase(
    credit_card: CreditCard, purchase_date: date
) -> tuple[int, int]:
    """
    Determina o mês e ano da fatura na qual uma compra efetuada em purchase_date será cobrada.
    Regra do Melhor Dia de Compra:
    - Se a compra foi feita ANTES do dia de fechamento -> fatura do mês atual (ou fatura com fechamento neste mês).
    - Se a compra foi feita NO DIA ou APÓS o fechamento -> fatura do mês subsequente.
    """
    p_day = purchase_date.day
    p_month = purchase_date.month
    p_year = purchase_date.year

    if p_day < credit_card.closing_day:
        # Compra entra na fatura cujo fechamento ocorre no mês da compra
        if credit_card.closing_day > credit_card.due_day:
            # Fechamento no mês anterior ao vencimento -> vence no mês seguinte ao fechamento
            target_month, target_year = get_next_month_year(p_month, p_year, 1)
        else:
            target_month, target_year = p_month, p_year
    else:
        # Compra entra na fatura cujo fechamento ocorre no mês seguinte
        if credit_card.closing_day > credit_card.due_day:
            target_month, target_year = get_next_month_year(p_month, p_year, 2)
        else:
            target_month, target_year = get_next_month_year(p_month, p_year, 1)

    return target_month, target_year


@transaction.atomic
def create_card_expense(
    credit_card: CreditCard,
    description: str,
    total_amount: Decimal,
    purchase_date: date,
    category: Category,
    installments_count: int = 1,
    financial_owner: FinancialOwner | None = None,
    user=None,
) -> list[CreditCardExpense]:
    """
    Registra uma compra (à vista ou parcelada) gerando as parcelas e vinculando às faturas correspondentes.
    Distribui centavos residuais na primeira parcela com precisão contábil exata.
    """
    owner = financial_owner or credit_card.financial_owner
    buyer = user or credit_card.user
    group_id = uuid.uuid4()

    installments_count = max(1, min(48, int(installments_count)))

    # Cálculo contábil das parcelas
    base_installment = (total_amount / Decimal(installments_count)).quantize(
        Decimal('0.01'), rounding=ROUND_DOWN
    )
    residual_cents = total_amount - (base_installment * Decimal(installments_count))

    # Fatura inicial da 1ª parcela
    first_month, first_year = calculate_target_invoice_for_purchase(
        credit_card, purchase_date
    )

    expenses = []
    for i in range(installments_count):
        installment_num = i + 1
        # Primeira parcela recebe os centavos residuais
        installment_val = (
            base_installment + residual_cents if i == 0 else base_installment
        )

        target_month, target_year = get_next_month_year(first_month, first_year, i)
        invoice = resolve_or_create_invoice(credit_card, target_month, target_year)

        expense = CreditCardExpense.objects.create(
            credit_card=credit_card,
            invoice=invoice,
            household=credit_card.household,
            user=buyer,
            financial_owner=owner,
            category=category,
            description=description,
            amount=installment_val,
            date=purchase_date,
            installments_count=installments_count,
            installment_number=installment_num,
            installment_group_id=group_id,
        )
        expenses.append(expense)

    return expenses


def calculate_card_metrics(
    credit_card: CreditCard,
    reference_month: int | None = None,
    reference_year: int | None = None,
) -> dict:
    """Calcula o resumo financeiro, limites e faturas do cartão."""
    now = timezone.localdate()
    month = reference_month or now.month
    year = reference_year or now.year

    current_invoice = resolve_or_create_invoice(credit_card, month, year)

    # Total comprometido = soma de todas as despesas em faturas NÃO pagas
    unpaid_expenses_total = (
        CreditCardExpense.objects.filter(
            credit_card=credit_card,
            invoice__status__in=[
                CreditCardInvoice.STATUS_OPEN,
                CreditCardInvoice.STATUS_CLOSED,
                CreditCardInvoice.STATUS_OVERDUE,
            ],
        ).aggregate(total=models.Sum('amount'))['total']
    ) or Decimal('0.00')

    available_limit = max(Decimal('0.00'), credit_card.limit - unpaid_expenses_total)

    # Próximas faturas futuras (após o mês atual)
    future_invoices_total = (
        CreditCardExpense.objects.filter(credit_card=credit_card)
        .exclude(invoice__month=month, invoice__year=year)
        .filter(
            models.Q(invoice__year__gt=year)
            | (models.Q(invoice__year=year) & models.Q(invoice__month__gt=month))
        )
        .filter(
            invoice__status__in=[
                CreditCardInvoice.STATUS_OPEN,
                CreditCardInvoice.STATUS_CLOSED,
            ]
        )
        .aggregate(total=models.Sum('amount'))['total']
    ) or Decimal('0.00')

    return {
        'credit_card': credit_card,
        'current_invoice': current_invoice,
        'current_invoice_total': current_invoice.total_amount,
        'unpaid_expenses_total': unpaid_expenses_total,
        'available_limit': available_limit,
        'future_invoices_total': future_invoices_total,
        'limit_usage_percent': min(
            100.0, float((unpaid_expenses_total / credit_card.limit) * 100)
        )
        if credit_card.limit > 0
        else 0.0,
    }


@transaction.atomic
def pay_card_invoice(
    invoice: CreditCardInvoice,
    payment_account,
    paid_amount: Decimal | None = None,
    payment_date: date | None = None,
) -> CreditCardInvoice:
    """
    Efetua a baixa de pagamento da fatura com débito atômico na conta bancária.
    """
    if invoice.status == CreditCardInvoice.STATUS_PAID:
        return invoice

    amount_to_pay = (
        paid_amount if (paid_amount and paid_amount > 0) else invoice.total_amount
    )
    pay_date = payment_date or timezone.localdate()

    # Categoria padrão para pagamento de fatura
    category, _ = Category.objects.get_or_create(
        household=invoice.household,
        user=invoice.credit_card.user,
        name='Pagamento de Cartão',
        type='expense',
        defaults={'color': '#2F756A', 'icon': 'credit-card'},
    )

    # Criação da transação contábil
    trans = Transaction.objects.create(
        user=invoice.credit_card.user,
        household=invoice.household,
        financial_owner=invoice.credit_card.financial_owner,
        account=payment_account,
        category=category,
        description=f'Pagamento Fatura {invoice.credit_card.name} ({invoice.month:02d}/{invoice.year})',
        amount=amount_to_pay,
        date=pay_date,
        type=Transaction.EXPENSE,
    )

    invoice.status = CreditCardInvoice.STATUS_PAID
    invoice.paid_amount = amount_to_pay
    invoice.paid_at = timezone.now()
    invoice.payment_account = payment_account
    invoice.payment_transaction = trans
    invoice.save(
        update_fields=[
            'status',
            'paid_amount',
            'paid_at',
            'payment_account',
            'payment_transaction',
            'updated_at',
        ]
    )

    return invoice


@transaction.atomic
def reopen_card_invoice(invoice: CreditCardInvoice) -> CreditCardInvoice:
    """Estorna o pagamento da fatura e remove a transação vinculada."""
    if invoice.payment_transaction:
        invoice.payment_transaction.delete()

    today = timezone.localdate()
    status = (
        CreditCardInvoice.STATUS_CLOSED
        if today >= invoice.closing_date
        else CreditCardInvoice.STATUS_OPEN
    )
    if today > invoice.due_date:
        status = CreditCardInvoice.STATUS_OVERDUE

    invoice.status = status
    invoice.paid_amount = Decimal('0.00')
    invoice.paid_at = None
    invoice.payment_account = None
    invoice.payment_transaction = None
    invoice.save(
        update_fields=[
            'status',
            'paid_amount',
            'paid_at',
            'payment_account',
            'payment_transaction',
            'updated_at',
        ]
    )

    return invoice


def check_card_expense_duplicate(credit_card: CreditCard, tx) -> bool:
    """Verifica se uma transação do extrato OFX já existe como despesa no cartão."""
    ext_id = getattr(tx, 'external_id', None) or (
        tx.get('external_id') if isinstance(tx, dict) else None
    )
    p_date = getattr(tx, 'posted_on', None) or (
        date.fromisoformat(tx['date'])
        if isinstance(tx.get('date'), str)
        else tx.get('date')
    )
    amt = abs(
        getattr(tx, 'amount', None)
        if not isinstance(tx, dict)
        else Decimal(str(tx['amount']))
    )
    desc = getattr(tx, 'description', None) or tx.get('description')

    if ext_id:
        # Verifica external_id + valor (pois compras internacionais e IOF compartilham o mesmo FITID no Nubank)
        if CreditCardExpense.objects.filter(
            credit_card=credit_card, external_id=ext_id, amount=amt
        ).exists():
            return True

    return CreditCardExpense.objects.filter(
        credit_card=credit_card,
        date=p_date,
        amount=amt,
        description=desc,
    ).exists()


@transaction.atomic
def import_card_ofx_expenses(
    credit_card: CreditCard,
    transactions: list,
    default_category: Category,
    user,
    financial_owner: FinancialOwner | None = None,
) -> dict:
    """
    Importa compras de extrato OFX para despesas de cartão:
    - Ignora pagamentos de fatura recebidos (não são despesas novas).
    - Deduplica despesas com base em external_id (FITID) + valor ou (credit_card, date, amount, description).
    - Projeta a fatura de destino (CreditCardInvoice) com base na data de compra e regras de fechamento/vencimento.
    - Persiste instâncias de CreditCardExpense.
    - Retorna resumo com quantidade importada, duplicadas ignoradas, faturas afetadas e valor total.
    """
    owner = financial_owner or credit_card.financial_owner
    imported_expenses = []
    duplicate_count = 0
    invoices_affected = set()
    total_amount = Decimal('0.00')

    for tx in transactions:
        if isinstance(tx, dict):
            ext_id = tx.get('external_id')
            p_date = (
                date.fromisoformat(tx['date'])
                if isinstance(tx['date'], str)
                else tx['date']
            )
            desc = tx['description']
            raw_amt = Decimal(str(tx['amount']))
            is_dup = tx.get('is_duplicate', False)
            is_payment = tx.get('is_payment', False)
        else:
            ext_id = tx.external_id
            p_date = tx.posted_on
            desc = tx.description
            raw_amt = tx.amount
            is_dup = False
            is_payment = (
                raw_amt > 0
                and any(
                    p in desc.lower() for p in ('pagamento', 'pgto', 'pago')
                )
            )

        if is_payment:
            continue

        amt = abs(raw_amt)

        if is_dup:
            duplicate_count += 1
            continue

        if (
            ext_id
            and CreditCardExpense.objects.filter(
                credit_card=credit_card, external_id=ext_id, amount=amt
            ).exists()
        ):
            duplicate_count += 1
            continue

        if (
            not ext_id
            and CreditCardExpense.objects.filter(
                credit_card=credit_card, date=p_date, amount=amt, description=desc
            ).exists()
        ):
            duplicate_count += 1
            continue

        target_month, target_year = calculate_target_invoice_for_purchase(
            credit_card, p_date
        )
        invoice = resolve_or_create_invoice(credit_card, target_month, target_year)
        invoices_affected.add(invoice)

        expense = CreditCardExpense.objects.create(
            credit_card=credit_card,
            invoice=invoice,
            household=credit_card.household,
            user=user,
            financial_owner=owner,
            category=default_category,
            description=desc,
            amount=amt,
            date=p_date,
            installments_count=1,
            installment_number=1,
            installment_group_id=uuid.uuid4(),
            external_id=ext_id,
        )
        imported_expenses.append(expense)
        total_amount += amt

    return {
        'imported_count': len(imported_expenses),
        'duplicate_count': duplicate_count,
        'invoices': list(invoices_affected),
        'total_amount': total_amount,
        'expenses': imported_expenses,
    }
