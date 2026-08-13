import json
from datetime import UTC


def serialize_backup_event(
    *,
    timestamp,
    event,
    status,
    stage,
    key=None,
    size=None,
    sha256=None,
    duration_ms=None,
    deleted_count=0,
    error_code=None,
) -> str:
    payload = {
        'timestamp': timestamp.astimezone(UTC).isoformat(),
        'service': 'lar-finance-backup',
        'event': event,
        'status': status,
        'stage': stage,
        'key': key,
        'size': size,
        'sha256': sha256[:12] if sha256 else None,
        'duration_ms': duration_ms,
        'deleted_count': deleted_count,
        'error_code': error_code,
    }
    return json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
