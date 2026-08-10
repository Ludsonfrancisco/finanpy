from contextlib import contextmanager
from contextvars import ContextVar

current_sync_context = ContextVar(
    'current_sync_context',
    default={'device_session': None, 'operation_id': None},
)


@contextmanager
def capture_sync_context(*, device_session=None, operation_id=None):
    token = current_sync_context.set(
        {
            'device_session': device_session,
            'operation_id': operation_id,
        }
    )
    try:
        yield
    finally:
        current_sync_context.reset(token)
