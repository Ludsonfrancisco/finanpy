from django.db import models


class ImmutableSyncChangeError(RuntimeError):
    pass


class SyncChange(models.Model):
    CREATE = 'create'
    UPDATE = 'update'
    DELETE = 'delete'
    OPERATION_CHOICES = [(CREATE, 'Create'), (UPDATE, 'Update'), (DELETE, 'Delete')]

    household = models.ForeignKey(
        'households.Household',
        on_delete=models.PROTECT,
        related_name='sync_changes',
    )
    device_session = models.ForeignKey(
        'api.DeviceSession',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name='sync_changes',
    )
    operation_id = models.UUIDField(null=True, blank=True)
    entity_type = models.CharField(max_length=32)
    entity_uuid = models.UUIDField()
    entity_version = models.PositiveBigIntegerField()
    operation = models.CharField(max_length=8, choices=OPERATION_CHOICES)
    payload = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['household', 'id']),
            models.Index(fields=['household', 'entity_type', 'entity_uuid']),
        ]

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise ImmutableSyncChangeError('SyncChange rows are append-only.')
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ImmutableSyncChangeError('SyncChange rows are append-only.')


class IdempotentOperation(models.Model):
    device_session = models.ForeignKey(
        'api.DeviceSession',
        on_delete=models.PROTECT,
        related_name='idempotent_operations',
    )
    operation_id = models.UUIDField()
    request_hash = models.CharField(max_length=64)
    status_code = models.PositiveSmallIntegerField()
    response_body = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['device_session', 'operation_id'],
                name='unique_idempotent_operation_per_device',
            )
        ]
