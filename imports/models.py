import uuid

from django.core.exceptions import ValidationError
from django.db import models


class ImportAccountLink(models.Model):
    household = models.ForeignKey(
        'households.Household',
        on_delete=models.PROTECT,
        related_name='import_account_links',
    )
    account = models.ForeignKey(
        'accounts.Account',
        on_delete=models.PROTECT,
        related_name='import_account_links',
    )
    provider = models.CharField(max_length=32)
    product_type = models.CharField(max_length=32)
    external_account_id = models.CharField(max_length=255)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['household', 'provider', 'product_type', 'external_account_id'],
                name='unique_import_account_link',
            )
        ]

    def clean(self):
        super().clean()
        if (
            self.household_id
            and self.account_id
            and self.account.household_id != self.household_id
        ):
            raise ValidationError({'account': 'Conta pertence a outro Lar.'})


class ImportBatch(models.Model):
    PREVIEW_READY = 'preview_ready'
    NEEDS_ACCOUNT_LINK = 'needs_account_link'
    COMPLETED = 'completed'
    FAILED = 'failed'
    CANCELLED = 'cancelled'
    STATUS_CHOICES = [
        (PREVIEW_READY, 'Preview ready'),
        (NEEDS_ACCOUNT_LINK, 'Needs account link'),
        (COMPLETED, 'Completed'),
        (FAILED, 'Failed'),
        (CANCELLED, 'Cancelled'),
    ]

    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)

    household = models.ForeignKey(
        'households.Household',
        on_delete=models.PROTECT,
        related_name='import_batches',
    )
    device_session = models.ForeignKey(
        'api.DeviceSession',
        on_delete=models.PROTECT,
        related_name='import_batches',
    )
    account = models.ForeignKey(
        'accounts.Account',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name='import_batches',
    )
    financial_owner = models.ForeignKey(
        'households.FinancialOwner',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name='import_batches',
    )
    provider = models.CharField(max_length=32)
    product_type = models.CharField(max_length=32)
    external_account_id = models.CharField(max_length=255)
    file_sha256 = models.CharField(max_length=64)
    statement_start = models.DateField()
    statement_end = models.DateField()
    expires_at = models.DateTimeField()
    status = models.CharField(
        max_length=32, choices=STATUS_CHOICES, default=PREVIEW_READY
    )
    created_count = models.PositiveIntegerField(default=0)
    duplicate_count = models.PositiveIntegerField(default=0)
    warning_count = models.PositiveIntegerField(default=0)
    is_repeated_file = models.BooleanField(default=False)

    class Meta:
        indexes = [models.Index(fields=['household', 'status', 'expires_at'])]

    def clean(self):
        super().clean()
        errors = {}
        if self.household_id and self.device_session_id:
            if self.device_session.household_id != self.household_id:
                errors['device_session'] = 'Dispositivo pertence a outro Lar.'
        if (
            self.household_id
            and self.account_id
            and self.account.household_id != self.household_id
        ):
            errors['account'] = 'Conta pertence a outro Lar.'
        if (
            self.household_id
            and self.financial_owner_id
            and self.financial_owner.household_id != self.household_id
        ):
            errors['financial_owner'] = 'Responsável pertence a outro Lar.'
        if errors:
            raise ValidationError(errors)


class ImportRecord(models.Model):
    PENDING = 'pending'
    DUPLICATE = 'duplicate'
    WARNING = 'warning'
    CREATED = 'created'
    OUTCOME_CHOICES = [
        (PENDING, 'Pending'),
        (DUPLICATE, 'Duplicate'),
        (WARNING, 'Warning'),
        (CREATED, 'Created'),
    ]

    batch = models.ForeignKey(
        ImportBatch,
        on_delete=models.CASCADE,
        related_name='records',
    )
    line_number = models.PositiveIntegerField()
    external_id = models.CharField(max_length=255, null=True, blank=True)
    posted_on = models.DateField()
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    description = models.CharField(max_length=255)
    transaction_type = models.CharField(max_length=10)
    fingerprint = models.CharField(max_length=64)
    outcome = models.CharField(max_length=16, choices=OUTCOME_CHOICES)
    transaction = models.ForeignKey(
        'transactions.Transaction',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='import_records',
    )

    class Meta:
        indexes = [models.Index(fields=['batch', 'line_number'])]

    def clean(self):
        super().clean()
        if self.batch_id and self.transaction_id:
            if self.transaction.household_id != self.batch.household_id:
                raise ValidationError(
                    {'transaction': 'Transação pertence a outro Lar.'}
                )


class SourceReference(models.Model):
    account = models.ForeignKey(
        'accounts.Account',
        on_delete=models.PROTECT,
        related_name='source_references',
    )
    provider = models.CharField(max_length=32)
    external_id = models.CharField(max_length=255)
    transaction = models.ForeignKey(
        'transactions.Transaction',
        on_delete=models.PROTECT,
        related_name='source_references',
    )

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['account', 'provider', 'external_id'],
                name='unique_source_reference_external_id',
            )
        ]
        indexes = [models.Index(fields=['account', 'provider', 'external_id'])]

    def clean(self):
        super().clean()
        if self.account_id and self.transaction_id:
            if self.account.household_id != self.transaction.household_id:
                raise ValidationError(
                    {'transaction': 'Transação pertence a outro Lar.'}
                )
