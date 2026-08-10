import json
import logging
from datetime import UTC, datetime


class JsonFormatter(logging.Formatter):
    def format(self, record):
        return record.getMessage()


class SafeDjangoFormatter(logging.Formatter):
    def format(self, record):
        request = getattr(record, 'request', None)
        event = {
            'timestamp': datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            'level': record.levelname,
            'service': 'django',
            'logger': record.name,
            'request_id': getattr(request, 'request_id', None),
            'status': getattr(record, 'status_code', None),
        }
        return json.dumps(event, ensure_ascii=False, separators=(',', ':'))


class SkipApiRequestLogFilter(logging.Filter):
    def filter(self, record):
        request = getattr(record, 'request', None)
        path = getattr(request, 'path', '')
        return not path.startswith('/api/v1/')


def serialize_access_event(event):
    return json.dumps(event, ensure_ascii=False, separators=(',', ':'))
