"""Preview-only services for synthetic-free, in-memory Nubank OFX imports."""

import hashlib
from datetime import timedelta
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone

from accounts.models import Account
from api.models import DeviceSession
from categories.models import Category
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
    with transaction.atomic():
        batch = (
            ImportBatch.objects.select_for_update()
            .select_related('household')
            .get(pk=batch.pk)
        )
        if account.household_id != batch.household_id:
            raise ImportAccessError('Account is not available for this household.')
        _require_actionable(batch)
        if batch.product_type == 'credit_card' and account.type != Account.CREDIT:
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
    """Cancel an actionable preview without deleting its audit receipt."""
    _require_actionable(batch)
    batch.status = ImportBatch.CANCELLED
    _save(batch)
    return batch


def confirm_preview(*, batch: ImportBatch, device_session) -> ImportBatch:
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
        reference_ids = [
            _reference_external_id(record)
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
                    external_id=_reference_external_id(record),
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
