import json
import logging


class JsonFormatter(logging.Formatter):
    def format(self, record):
        return record.getMessage()


def serialize_access_event(event):
    return json.dumps(event, ensure_ascii=False, separators=(',', ':'))
