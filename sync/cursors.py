from django.core import signing

CURSOR_SALT = 'lar-finance.sync.cursor.v1'


class InvalidCursor(ValueError):
    pass


def encode_cursor(change_id: int, household_uuid) -> str:
    return signing.dumps(
        {'change_id': int(change_id), 'household_uuid': str(household_uuid)},
        salt=CURSOR_SALT,
        compress=True,
    )


def decode_cursor(cursor: str, household_uuid) -> int:
    try:
        payload = signing.loads(cursor, salt=CURSOR_SALT)
        change_id = int(payload['change_id'])
    except (signing.BadSignature, KeyError, TypeError, ValueError) as exc:
        raise InvalidCursor from exc
    if change_id < 0 or payload.get('household_uuid') != str(household_uuid):
        raise InvalidCursor
    return change_id
