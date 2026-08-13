"""Preview-only services for synthetic-free, in-memory Nubank OFX imports."""

import hashlib
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from accounts.models import Account

from .models import ImportAccountLink, ImportBatch, ImportRecord, SourceReference
from .ofx import parse_nubank_ofx


class ImportAccessError(Exception):
    """Raised when an import object crosses a household boundary."""


class ImportStateError(Exception):
    """Raised when a preview is not in an actionable state."""


class ExpiredPreviewError(ImportStateError):
    """Raised when an actionable preview has expired."""


def create_preview(*, household, device_session, content: bytes) -> ImportBatch:
    """Parse bytes in memory and store only a normalized, non-ledger preview."""
    if device_session.household_id != household.id:
        raise ImportAccessError('Device session is not available for this household.')

    parsed = parse_nubank_ofx(content)
    file_sha256 = hashlib.sha256(content).hexdigest()
    link = (
        ImportAccountLink.objects.select_related('account__financial_owner')
        .filter(
            household=household,
            provider='nubank',
            product_type=parsed.product_type,
            external_account_id=parsed.external_account_id,
        )
        .first()
    )
    repeated = ImportBatch.objects.filter(
        household=household,
        file_sha256=file_sha256,
        status=ImportBatch.COMPLETED,
    ).exists()
    if (
        link
        and parsed.product_type == 'credit_card'
        and link.account.type != Account.CREDIT
    ):
        raise ImportStateError(
            'The selected account is incompatible with this preview.'
        )
    with transaction.atomic():
        batch = ImportBatch(
            household=household,
            device_session=device_session,
            account=link.account if link else None,
            financial_owner=link.account.financial_owner if link else None,
            provider='nubank',
            product_type=parsed.product_type,
            external_account_id=parsed.external_account_id,
            file_sha256=file_sha256,
            statement_start=parsed.statement_start,
            statement_end=parsed.statement_end,
            expires_at=timezone.now() + timedelta(hours=24),
            status=ImportBatch.PREVIEW_READY
            if link or repeated
            else ImportBatch.NEEDS_ACCOUNT_LINK,
            duplicate_count=len(parsed.transactions) if repeated else 0,
            is_repeated_file=repeated,
        )
        _save(batch)
        if repeated:
            return batch
        for line_number, item in enumerate(parsed.transactions, start=1):
            record = _record_from_parsed(
                batch=batch, line_number=line_number, item=item
            )
            if link:
                _classify_record(record, link.account)
            _save(record)
        if link:
            _update_counts(batch)
        return batch


def bind_preview_account(*, batch: ImportBatch, account: Account) -> ImportBatch:
    """Bind a still-actionable preview to a local account and classify its records."""
    if account.household_id != batch.household_id:
        raise ImportAccessError('Account is not available for this household.')
    _require_actionable(batch)
    if batch.product_type == 'credit_card' and account.type != Account.CREDIT:
        raise ImportStateError(
            'The selected account is incompatible with this preview.'
        )
    with transaction.atomic():
        link = ImportAccountLink.objects.filter(
            household=batch.household,
            provider=batch.provider,
            product_type=batch.product_type,
            external_account_id=batch.external_account_id,
        ).first()
        if link is None:
            link = ImportAccountLink(
                household=batch.household,
                account=account,
                provider=batch.provider,
                product_type=batch.product_type,
                external_account_id=batch.external_account_id,
            )
            _save(link)
        elif link.account_id != account.id:
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
    """Cancel an actionable preview without deleting its audit receipt."""
    _require_actionable(batch)
    batch.status = ImportBatch.CANCELLED
    _save(batch)
    return batch


def get_batch_for_household(*, household, batch_uuid) -> ImportBatch:
    """Return a batch only when it belongs to the requested household."""
    try:
        return ImportBatch.objects.get(uuid=batch_uuid, household=household)
    except ImportBatch.DoesNotExist as error:
        raise ImportAccessError(
            'Import batch is not available for this household.'
        ) from error


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


def _classify_record(record, account):
    if (
        record.external_id
        and SourceReference.objects.filter(
            account=account, provider='nubank', external_id=record.external_id
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
    else:
        record.outcome = ImportRecord.PENDING


def _update_counts(batch):
    outcomes = list(batch.records.values_list('outcome', flat=True))
    batch.created_count = outcomes.count(ImportRecord.PENDING)
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


def _require_actionable(batch):
    if batch.expires_at <= timezone.now():
        raise ExpiredPreviewError('Import preview has expired.')
    if batch.status not in (ImportBatch.PREVIEW_READY, ImportBatch.NEEDS_ACCOUNT_LINK):
        raise ImportStateError('Import preview is not actionable.')


def _save(instance):
    instance.full_clean()
    instance.save()
