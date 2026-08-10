import hashlib
import json


def request_hash(operation: dict) -> str:
    canonical = json.dumps(
        operation,
        sort_keys=True,
        separators=(',', ':'),
        ensure_ascii=False,
    )
    return hashlib.sha256(canonical.encode('utf-8')).hexdigest()
