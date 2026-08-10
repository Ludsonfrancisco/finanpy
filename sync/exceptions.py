class IdempotencyConflict(RuntimeError):
    """An operation id was reused with a different request body."""

    code = 'idempotency_conflict'
