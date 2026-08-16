"""Secure lifecycle services for normalized OFX previews and ledger confirmation."""

import hashlib
import time
from datetime import timedelta
from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import IntegrityError, OperationalError, connection, models, transaction
from django.db.models import Count, Q, Sum, Value
from django.db.models.functions import Abs, Coalesce
from django.utils import timezone
from filelock import FileLock, Timeout

from accounts.models import Account
from api.models import DeviceSession
from categories.models import Category
from households.models import FinancialOwner
from sync.context import capture_sync_context
from transactions.models import Transaction

from .models import ImportAccountLink, ImportBatch, ImportRecord, SourceReference
from .ofx import parse_nubank_ofx


class ImportAccessError(Exception):
    """Raised when an import object crosses a household boundary."""


class ImportStateError(Exception):
    """Raised when a preview is not in an actionable state."""


class ExpiredPreviewError(ImportStateError):
    """Raised when an actionable preview has expired."""


class ImportConflictError(ImportStateError):
    """Raised when confirmation races an existing source reference."""


class ImportBusyError(ImportStateError):
    """Raised when SQLite import writes cannot be serialized safely."""


PREVIEW_TTL = timedelta(hours=23)
DEFAULT_IMPORT_LOCK_TIMEOUT_SECONDS = 5.0
DEFAULT_IMPORT_LOCK_RETRIES = 3
DEFAULT_IMPORT_LOCK_RETRY_DELAY_SECONDS = 0.05
DEFAULT_ACCOUNT_SPECS = {
    'bank_account': ('Nubank — Conta', Account.CHECKING),
    'credit_card': ('Nubank — Cartão', Account.CREDIT),
}
DEFAULT_RECORD_PAGE_LIMIT = 50
MAX_RECORD_PAGE_LIMIT = 100
TOTAL_OUTPUT_FIELD = models.DecimalField(max_digits=14, decimal_places=2)


def create_preview(*, household, device_session, content: bytes) -> ImportBatch:
    return _run_serialized_import_mutation(
        lambda: _create_preview(
            household=household,
            device_session=device_session,
            content=content,
        )
    )


def _create_preview(*, household, device_session, content: bytes) -> ImportBatch:
    """Parse bytes in memory and store only a normalized, non-ledger preview."""
    _purge_preview_records()
    if device_session.household_id != household.id:
        raise ImportAccessError('Device session is not available for this household.')

    parsed = parse_nubank_ofx(content)
    file_sha256 = hashlib.sha256(content).hexdigest()
    with transaction.atomic():
        link = (
            ImportAccountLink.objects.select_for_update()
            .select_related('account__financial_owner')
            .filter(
                household=household,
                provider='nubank',
                product_type=parsed.product_type,
                external_account_id=parsed.external_account_id,
            )
            .first()
        )
        if link is None:
            account = _get_or_create_default_account(
                household=household,
                device_session=device_session,
                product_type=parsed.product_type,
            )
            link = _get_or_create_account_link(
                household=household,
                account=account,
                product_type=parsed.product_type,
                external_account_id=parsed.external_account_id,
            )
        if not _account_is_compatible(parsed.product_type, link.account):
            raise ImportStateError(
                'The selected account is incompatible with this preview.'
            )
        repeated = ImportBatch.objects.filter(
            household=household,
            file_sha256=file_sha256,
            status=ImportBatch.COMPLETED,
        ).exists()
        batch = ImportBatch(
            household=household,
            device_session=device_session,
            account=link.account,
            financial_owner=link.account.financial_owner,
            provider='nubank',
            product_type=parsed.product_type,
            external_account_id=parsed.external_account_id,
            file_sha256=file_sha256,
            statement_start=parsed.statement_start,
            statement_end=parsed.statement_end,
            expires_at=timezone.now() + PREVIEW_TTL,
            status=ImportBatch.PREVIEW_READY,
            duplicate_count=len(parsed.transactions) if repeated else 0,
            is_repeated_file=repeated,
        )
        _save(batch)
        if repeated:
            return batch
        ambiguous = _ambiguous_external_ids(parsed.transactions)
        seen_in_file = set()
        for line_number, item in enumerate(parsed.transactions, start=1):
            record = _record_from_parsed(
                batch=batch, line_number=line_number, item=item
            )
            _classify_record(
                record,
                link.account,
                ambiguous=ambiguous,
                seen_in_file=seen_in_file,
            )
            _save(record)
        _update_counts(batch)
        return batch


def _get_or_create_default_account(*, household, device_session, product_type):
    try:
        name, account_type = DEFAULT_ACCOUNT_SPECS[product_type]
    except KeyError as error:
        raise ImportStateError('Import product is unsupported.') from error
    owner = (
        FinancialOwner.objects.select_for_update()
        .filter(
            household=household,
            type=FinancialOwner.SELF,
            is_active=True,
        )
        .first()
    )
    if owner is None:
        raise ImportStateError('Default financial owner is unavailable.')
    candidates = list(
        Account.objects.select_for_update()
        .filter(
            household=household,
            financial_owner=owner,
            name=name,
            type=account_type,
            currency='BRL',
        )
        .order_by('pk')[:2]
    )
    if len(candidates) > 1:
        raise ImportStateError('Default import account is ambiguous.')
    if candidates:
        return candidates[0]
    account = Account(
        user=device_session.user,
        household=household,
        financial_owner=owner,
        name=name,
        type=account_type,
        initial_balance=Decimal('0.00'),
        currency='BRL',
    )
    with capture_sync_context(device_session=device_session, operation_id=None):
        _save(account)
    return account


def _get_or_create_account_link(
    *, household, account, product_type, external_account_id
):
    try:
        with transaction.atomic():
            link = ImportAccountLink(
                household=household,
                account=account,
                provider='nubank',
                product_type=product_type,
                external_account_id=external_account_id,
            )
            _save(link)
            return link
    except IntegrityError:
        link = (
            ImportAccountLink.objects.select_related('account__financial_owner')
            .filter(
                household=household,
                provider='nubank',
                product_type=product_type,
                external_account_id=external_account_id,
            )
            .first()
        )
        if link is None or link.account_id != account.id:
            raise ImportStateError('Account link could not be created safely.')
        return link


def bind_preview_account(*, batch: ImportBatch, account: Account) -> ImportBatch:
    return _run_serialized_import_mutation(
        lambda: _bind_preview_account(batch=batch, account=account)
    )


def _bind_preview_account(*, batch: ImportBatch, account: Account) -> ImportBatch:
    """Bind a still-actionable preview to a local account and classify its records."""
    with transaction.atomic():
        batch = (
            ImportBatch.objects.select_for_update()
            .select_related('household')
            .get(pk=batch.pk)
        )
        if account.household_id != batch.household_id:
            raise ImportAccessError('Account is not available for this household.')
        _require_actionable(batch)
        if not _account_is_compatible(batch.product_type, account):
            raise ImportStateError(
                'The selected account is incompatible with this preview.'
            )
        link = ImportAccountLink.objects.filter(
            household=batch.household,
            provider=batch.provider,
            product_type=batch.product_type,
            external_account_id=batch.external_account_id,
        ).first()
        if link is None:
            try:
                with transaction.atomic():
                    link = ImportAccountLink(
                        household=batch.household,
                        account=account,
                        provider=batch.provider,
                        product_type=batch.product_type,
                        external_account_id=batch.external_account_id,
                    )
                    _save(link)
            except IntegrityError:
                link = ImportAccountLink.objects.filter(
                    household=batch.household,
                    provider=batch.provider,
                    product_type=batch.product_type,
                    external_account_id=batch.external_account_id,
                ).first()
                if link is None:
                    raise ImportStateError('Account link could not be created safely.')
        if link.account_id != account.id:
            raise ImportStateError('This preview is already linked to another account.')
        batch.account = account
        batch.financial_owner = account.financial_owner
        batch.status = ImportBatch.PREVIEW_READY
        _save(batch)
        for record in batch.records.all():
            if not record.external_id:
                record.fingerprint = _record_fingerprint(account, record)
            _classify_record(record, account)
            _save(record)
        _update_counts(batch)
        return batch


def cancel_preview(*, batch: ImportBatch) -> ImportBatch:
    return _run_serialized_import_mutation(lambda: _cancel_preview(batch=batch))


def _cancel_preview(*, batch: ImportBatch) -> ImportBatch:
    """Cancel an actionable preview without deleting its audit receipt."""
    with transaction.atomic():
        batch = ImportBatch.objects.select_for_update().get(pk=batch.pk)
        if batch.status == ImportBatch.CANCELLED:
            return batch
        if batch.status == ImportBatch.COMPLETED:
            raise ImportStateError('A completed import cannot be cancelled.')
        _require_actionable(batch)
        batch.status = ImportBatch.CANCELLED
        _save(batch)
        batch.records.filter(transaction__isnull=True).delete()
        return batch


def confirm_preview(*, batch: ImportBatch, device_session) -> ImportBatch:
    return _run_serialized_import_mutation(
        lambda: _confirm_preview(batch=batch, device_session=device_session)
    )


def _confirm_preview(*, batch: ImportBatch, device_session) -> ImportBatch:
    """Atomically apply one linked, actionable preview to the household ledger."""
    with transaction.atomic():
        device_session = DeviceSession.objects.select_for_update().get(
            pk=device_session.pk
        )
        batch = (
            ImportBatch.objects.select_for_update()
            .select_related('account__financial_owner', 'financial_owner')
            .get(pk=batch.pk)
        )
        _require_confirmation_access(batch, device_session)
        if batch.status == ImportBatch.COMPLETED:
            return batch
        if batch.status != ImportBatch.PREVIEW_READY or batch.account_id is None:
            raise ImportStateError('Import preview is not ready for confirmation.')
        _require_actionable(batch)
        if batch.financial_owner_id != batch.account.financial_owner_id:
            raise ImportStateError('Import preview owner is invalid.')

        records = list(batch.records.select_for_update().order_by('line_number'))
        ambiguous = _ambiguous_external_ids(records)
        reference_ids = [
            _effective_reference_id(record, ambiguous)
            for record in records
            if record.outcome in (ImportRecord.PENDING, ImportRecord.WARNING)
        ]
        if len(reference_ids) != len(set(reference_ids)):
            raise ImportConflictError('Import preview contains repeated references.')
        if (
            SourceReference.objects.select_for_update()
            .filter(
                account=batch.account,
                provider=batch.provider,
                external_id__in=reference_ids,
            )
            .exists()
        ):
            raise ImportConflictError(
                'Import preview conflicts with an existing reference.'
            )

        categories = {}
        for record in records:
            if record.outcome not in (ImportRecord.PENDING, ImportRecord.WARNING):
                continue
            category = categories.setdefault(
                record.transaction_type,
                _uncategorized_category(
                    household=batch.household,
                    user=device_session.user,
                    transaction_type=record.transaction_type,
                ),
            )
            with capture_sync_context(device_session=device_session, operation_id=None):
                ledger_transaction = Transaction(
                    user=device_session.user,
                    household=batch.household,
                    financial_owner=batch.account.financial_owner,
                    account=batch.account,
                    category=category,
                    description=record.description,
                    amount=abs(record.amount),
                    date=record.posted_on,
                    type=record.transaction_type,
                )
                _save(ledger_transaction)
            try:
                reference = SourceReference(
                    account=batch.account,
                    provider=batch.provider,
                    external_id=_effective_reference_id(record, ambiguous),
                    transaction=ledger_transaction,
                )
                _save(reference)
            except (IntegrityError, ValidationError) as error:
                raise ImportConflictError(
                    'Import preview conflicts with an existing reference.'
                ) from error
            record.transaction = ledger_transaction
            record.outcome = ImportRecord.CREATED
            _save(record)

        batch.status = ImportBatch.COMPLETED
        _update_counts(batch)
        return batch


def get_batch_for_household(*, household, batch_uuid) -> ImportBatch:
    """Return a batch only when it belongs to the requested household."""
    purge_preview_records()
    try:
        return ImportBatch.objects.get(uuid=batch_uuid, household=household)
    except ImportBatch.DoesNotExist as error:
        raise ImportAccessError(
            'Import batch is not available for this household.'
        ) from error


def read_preview_page(*, batch, after=None, limit=None) -> dict:
    """Return one stable page of preview records with the totals of the batch."""
    limit = DEFAULT_RECORD_PAGE_LIMIT if limit is None else limit
    records = batch.records.order_by('line_number', 'pk')
    if after is not None:
        records = records.filter(line_number__gt=after)
    page = list(records[: limit + 1])
    next_cursor = None
    if len(page) > limit:
        page = page[:limit]
        next_cursor = str(page[-1].line_number)
    return {
        **_summarize_records(batch),
        'records': page,
        'next_cursor': next_cursor,
    }


def _summarize_records(batch) -> dict:
    return batch.records.aggregate(
        record_count=Count('pk'),
        pending_count=Count('pk', filter=Q(outcome=ImportRecord.PENDING)),
        income_total=_absolute_total('income'),
        expense_total=_absolute_total('expense'),
    )


def _absolute_total(transaction_type):
    return Coalesce(
        Sum(Abs('amount'), filter=Q(transaction_type=transaction_type)),
        Value(Decimal('0.00')),
        output_field=TOTAL_OUTPUT_FIELD,
    )


def purge_preview_records(*, now=None) -> int:
    return _run_serialized_import_mutation(
        lambda: _purge_preview_records(now=now)
    )


def _purge_preview_records(*, now=None) -> int:
    """Discard private normalized rows while preserving minimal batch receipts."""
    cutoff = now or timezone.now()
    actionable_statuses = (
        ImportBatch.PREVIEW_READY,
        ImportBatch.NEEDS_ACCOUNT_LINK,
    )
    with transaction.atomic():
        batches = list(
            ImportBatch.objects.select_for_update()
            .filter(
                Q(status=ImportBatch.CANCELLED)
                | Q(status__in=actionable_statuses, expires_at__lte=cutoff)
            )
            .order_by('pk')
        )
        if not batches:
            return 0
        expired = [batch for batch in batches if batch.status in actionable_statuses]
        for batch in expired:
            batch.status = ImportBatch.FAILED
            _save(batch)
        deleted, _ = ImportRecord.objects.filter(
            batch_id__in=[batch.pk for batch in batches],
            transaction__isnull=True,
        ).delete()
        return deleted


def next_preview_purge_delay(*, max_delay_seconds: int, now=None) -> float:
    """Return a bounded wait that wakes no later than the nearest preview expiry."""
    cutoff = now or timezone.now()
    nearest_expiry = (
        ImportBatch.objects.filter(
            status__in=(
                ImportBatch.PREVIEW_READY,
                ImportBatch.NEEDS_ACCOUNT_LINK,
            )
        )
        .order_by('expires_at')
        .values_list('expires_at', flat=True)
        .first()
    )
    if nearest_expiry is None:
        return float(max_delay_seconds)
    until_expiry = max(0.0, (nearest_expiry - cutoff).total_seconds())
    return min(float(max_delay_seconds), until_expiry)


def _record_from_parsed(*, batch, line_number, item):
    description = ' '.join(item.description.split())
    return ImportRecord(
        batch=batch,
        line_number=line_number,
        external_id=item.external_id,
        posted_on=item.posted_on,
        amount=item.amount,
        description=description,
        transaction_type=item.transaction_type,
        fingerprint=_fingerprint(batch.account, item, description),
        outcome=ImportRecord.PENDING,
    )


def _content_digest(entry):
    """What the entry says, independent of the identity the file gave it."""
    value = '|'.join(
        (
            entry.posted_on.isoformat(),
            _normalized_decimal(entry.amount),
            entry.transaction_type,
            ' '.join(entry.description.split()),
        )
    )
    return hashlib.sha256(value.encode()).hexdigest()


def _ambiguous_external_ids(entries):
    """External ids the file gives to entries that say different things.

    A Nubank card statement reuses one FITID for a purchase and the tax
    charged on it. Both are real, so neither can inherit the other identity.
    An id repeated over an identical entry is just a repeated line.
    """
    digests = {}
    for entry in entries:
        if not entry.external_id:
            continue
        digests.setdefault(entry.external_id, set()).add(_content_digest(entry))
    return {
        external_id
        for external_id, values in digests.items()
        if len(values) > 1
    }


def _effective_reference_id(record, ambiguous):
    """The identity stored for a record, unique even when a FITID repeats."""
    if record.external_id and record.external_id in ambiguous:
        return f'{record.external_id}#{_content_digest(record)[:16]}'
    return _reference_external_id(record)


def _classify_record(record, account, *, ambiguous=frozenset(), seen_in_file=None):
    if seen_in_file is None:
        seen_in_file = set()
    entry = (record.external_id, _content_digest(record))
    if record.external_id and entry in seen_in_file:
        # The same line twice in one file is one entry, not two.
        record.outcome = ImportRecord.DUPLICATE
        return
    if record.external_id:
        seen_in_file.add(entry)
    if (
        record.external_id
        and SourceReference.objects.filter(
            account=account,
            provider='nubank',
            external_id=_effective_reference_id(record, ambiguous),
        ).exists()
    ):
        record.outcome = ImportRecord.DUPLICATE
    elif (
        not record.external_id
        and ImportRecord.objects.filter(
            batch__household=account.household,
            batch__account=account,
            batch__status=ImportBatch.COMPLETED,
            fingerprint=record.fingerprint,
        ).exists()
    ):
        record.outcome = ImportRecord.WARNING
    elif record.external_id in ambiguous:
        # Importable, but the person should see that the file reused an id.
        record.outcome = ImportRecord.WARNING
    else:
        record.outcome = ImportRecord.PENDING


def _account_is_compatible(product_type, account):
    if product_type == 'credit_card':
        return account.type == Account.CREDIT
    if product_type == 'bank_account':
        return account.type != Account.CREDIT
    return False


def _update_counts(batch):
    outcomes = list(batch.records.values_list('outcome', flat=True))
    created_outcome = (
        ImportRecord.CREATED
        if batch.status == ImportBatch.COMPLETED
        else ImportRecord.PENDING
    )
    batch.created_count = outcomes.count(created_outcome)
    batch.duplicate_count = outcomes.count(ImportRecord.DUPLICATE)
    batch.warning_count = outcomes.count(ImportRecord.WARNING)
    _save(batch)


def _fingerprint(account, item, description):
    if item.external_id:
        value = item.external_id
    else:
        value = '|'.join(
            (
                str(account.uuid) if account else '',
                item.posted_on.isoformat(),
                _normalized_decimal(item.amount),
                item.transaction_type,
                description,
            )
        )
    return hashlib.sha256(value.encode()).hexdigest()


def _normalized_decimal(value: Decimal) -> str:
    return format(value.normalize(), 'f') if value else '0'


def _record_fingerprint(account, record):
    value = '|'.join(
        (
            str(account.uuid),
            record.posted_on.isoformat(),
            _normalized_decimal(record.amount),
            record.transaction_type,
            record.description,
        )
    )
    return hashlib.sha256(value.encode()).hexdigest()


def _reference_external_id(record):
    return record.external_id or record.fingerprint


def _uncategorized_category(*, household, user, transaction_type):
    category = Category.objects.filter(
        household=household,
        name='Não categorizado',
        type=transaction_type,
    ).first()
    if category is not None:
        return category
    try:
        with transaction.atomic():
            category = Category(
                user=user,
                household=household,
                name='Não categorizado',
                type=transaction_type,
            )
            _save(category)
            return category
    except (IntegrityError, ValidationError):
        category = Category.objects.filter(
            household=household,
            name='Não categorizado',
            type=transaction_type,
        ).first()
        if category is None:
            raise ImportStateError(
                'Uncategorized category could not be created safely.'
            )
        return category


def _require_confirmation_access(batch, device_session):
    if device_session.household_id != batch.household_id:
        raise ImportAccessError('Device session is not available for this household.')
    if (
        device_session.revoked_at is not None
        or device_session.access_expires_at <= timezone.now()
    ):
        raise ImportAccessError('Device session is not active.')


def _require_actionable(batch):
    if batch.expires_at <= timezone.now():
        raise ExpiredPreviewError('Import preview has expired.')
    if batch.status not in (ImportBatch.PREVIEW_READY, ImportBatch.NEEDS_ACCOUNT_LINK):
        raise ImportStateError('Import preview is not actionable.')


def _save(instance):
    instance.full_clean()
    instance.save()


def _run_serialized_import_mutation(operation):
    """Serialize cooperative SQLite writers and bound lock-contention retries."""
    if connection.vendor != 'sqlite':
        return operation()

    timeout_seconds = max(
        0.0,
        float(
            getattr(
                settings,
                'IMPORT_MUTATION_LOCK_TIMEOUT_SECONDS',
                DEFAULT_IMPORT_LOCK_TIMEOUT_SECONDS,
            )
        ),
    )
    retries = max(
        1,
        int(
            getattr(
                settings,
                'IMPORT_MUTATION_LOCK_RETRIES',
                DEFAULT_IMPORT_LOCK_RETRIES,
            )
        ),
    )
    retry_delay = max(
        0.0,
        float(
            getattr(
                settings,
                'IMPORT_MUTATION_LOCK_RETRY_DELAY_SECONDS',
                DEFAULT_IMPORT_LOCK_RETRY_DELAY_SECONDS,
            )
        ),
    )

    try:
        with FileLock(_import_mutation_lock_path(), timeout=timeout_seconds):
            for attempt in range(retries):
                try:
                    return operation()
                except OperationalError as error:
                    if not _is_transient_sqlite_lock(error):
                        raise
                    if attempt == retries - 1:
                        raise ImportBusyError(
                            'Import operation is temporarily busy.'
                        ) from error
                    time.sleep(retry_delay)
    except Timeout as error:
        raise ImportBusyError('Import operation is temporarily busy.') from error

    raise ImportBusyError('Import operation is temporarily busy.')


def _import_mutation_lock_path() -> str:
    configured = getattr(settings, 'IMPORT_MUTATION_LOCK_PATH', None)
    if configured:
        return str(configured)

    database_name = str(connection.settings_dict['NAME'])
    if database_name == ':memory:' or database_name.startswith('file:'):
        return str(Path(settings.BASE_DIR) / '.lar-finance-imports.lock')
    return str(Path(database_name).resolve().parent / '.lar-finance-imports.lock')


def _is_transient_sqlite_lock(error: OperationalError) -> bool:
    return connection.vendor == 'sqlite' and 'locked' in str(error).lower()
