from django.db.models.signals import post_save, pre_delete, pre_save

from sync.context import current_sync_context
from sync.models import SyncChange
from sync.registry import get_entity_type, serialize_entity


def advance_sync_version(sender, instance, raw=False, **kwargs):
    if raw or instance._state.adding:
        return
    stored_version = sender.objects.only('sync_version').get(pk=instance.pk).sync_version
    next_version = stored_version + 1
    if instance.sync_version != next_version:
        instance.sync_version = next_version


def append_saved_change(
    sender,
    instance,
    created,
    raw=False,
    update_fields=None,
    **kwargs,
):
    if raw:
        return
    if not created and update_fields is not None and 'sync_version' not in update_fields:
        sender.objects.filter(pk=instance.pk).update(
            sync_version=instance.sync_version
        )
    context = current_sync_context.get()
    SyncChange.objects.create(
        household=instance.household,
        device_session=context['device_session'],
        operation_id=context['operation_id'],
        entity_type=get_entity_type(instance),
        entity_uuid=instance.uuid,
        entity_version=instance.sync_version,
        operation=SyncChange.CREATE if created else SyncChange.UPDATE,
        payload=serialize_entity(instance),
    )


def append_delete_change(sender, instance, **kwargs):
    stored_version = sender.objects.only('sync_version').get(
        pk=instance.pk
    ).sync_version
    context = current_sync_context.get()
    SyncChange.objects.create(
        household=instance.household,
        device_session=context['device_session'],
        operation_id=context['operation_id'],
        entity_type=get_entity_type(instance),
        entity_uuid=instance.uuid,
        entity_version=stored_version + 1,
        operation=SyncChange.DELETE,
        payload={'uuid': str(instance.uuid), 'deleted': True},
    )


def connect_sync_signals(model):
    label = model._meta.label_lower
    pre_save.connect(
        advance_sync_version,
        sender=model,
        dispatch_uid=f'sync.advance_version.{label}',
    )
    post_save.connect(
        append_saved_change,
        sender=model,
        dispatch_uid=f'sync.append_saved.{label}',
    )
    pre_delete.connect(
        append_delete_change,
        sender=model,
        dispatch_uid=f'sync.append_deleted.{label}',
    )
