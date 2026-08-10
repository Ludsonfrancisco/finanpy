from uuid import uuid4

from django.test import SimpleTestCase

from sync.cursors import InvalidCursor, decode_cursor, encode_cursor

CURSOR_CASES = (
    ('round_trip', 42, 'same_household', 42),
    ('tampered', 42, 'changed_signature', 'invalid_cursor'),
    ('foreign_household', 42, 'other_household', 'invalid_cursor'),
)


class SignedCursorTest(SimpleTestCase):
    def test_cursor_cases(self):
        self.assertEqual(len(CURSOR_CASES), 3)
        household_uuid = uuid4()

        for case, change_id, variation, expected in CURSOR_CASES:
            with self.subTest(case=case):
                cursor = encode_cursor(change_id, household_uuid)
                if variation == 'same_household':
                    self.assertEqual(decode_cursor(cursor, household_uuid), expected)
                    self.assertNotEqual(cursor, str(change_id))
                elif variation == 'changed_signature':
                    replacement = 'a' if cursor[-1] != 'a' else 'b'
                    with self.assertRaises(InvalidCursor):
                        decode_cursor(cursor[:-1] + replacement, household_uuid)
                else:
                    with self.assertRaises(InvalidCursor):
                        decode_cursor(cursor, uuid4())

    def test_negative_change_id_is_invalid(self):
        household_uuid = uuid4()

        cursor = encode_cursor(-1, household_uuid)

        with self.assertRaises(InvalidCursor):
            decode_cursor(cursor, household_uuid)
