from datetime import date
from decimal import Decimal
from pathlib import Path

from django.test import SimpleTestCase

from imports.ofx import (
    OfxParseError,
    OversizedOfxError,
    ParsedNubankOfx,
    UnsupportedOfxError,
    parse_nubank_ofx,
)

FIXTURES_DIR = Path(__file__).parent / 'fixtures'


class ParseNubankOfxTest(SimpleTestCase):
    def test_parses_synthetic_nubank_account_statement(self):
        parsed = parse_nubank_ofx(self._fixture_bytes('nubank-account.ofx'))

        self.assertEqual(
            parsed,
            ParsedNubankOfx(
                product_type='bank_account',
                external_account_id='synthetic-account-001',
                statement_start=date(2026, 1, 1),
                statement_end=date(2026, 1, 31),
                transactions=(
                    self._transaction(
                        external_id='synthetic-fitid-001',
                        posted_on=date(2026, 1, 2),
                        amount=Decimal('-42.50'),
                        description='Synthetic market purchase',
                        transaction_type='expense',
                    ),
                    self._transaction(
                        external_id=None,
                        posted_on=date(2026, 1, 3),
                        amount=Decimal('125.75'),
                        description='Synthetic payment received',
                        transaction_type='income',
                    ),
                ),
            ),
        )

    def test_parses_synthetic_nubank_card_statement(self):
        parsed = parse_nubank_ofx(self._fixture_bytes('nubank-card.ofx'))

        self.assertEqual(parsed.product_type, 'credit_card')
        self.assertEqual(parsed.external_account_id, 'synthetic-card-002')
        self.assertEqual(parsed.statement_start, date(2026, 2, 1))
        self.assertEqual(parsed.statement_end, date(2026, 2, 28))
        self.assertEqual(parsed.transactions[0].external_id, 'synthetic-card-fitid-001')
        self.assertEqual(parsed.transactions[0].transaction_type, 'expense')

    def test_parses_canonical_sgml_with_signon_status_and_ledger_sections(self):
        parsed = parse_nubank_ofx(self._fixture_bytes('nubank-canonical-sgml.ofx'))

        self.assertEqual(parsed.external_account_id, 'synthetic-canonical-003')
        self.assertEqual(parsed.transactions[0].posted_on, date(2026, 3, 2))

    def test_parses_sgml_signon_financial_institution_aggregate(self):
        parsed = parse_nubank_ofx(self._fixture_bytes('nubank-signon-fi-sgml.ofx'))

        self.assertEqual(parsed.external_account_id, 'synthetic-fi-account-004')

    def test_parses_utf8_none_account_statement(self):
        parsed = parse_nubank_ofx(
            self._fixture_bytes('nubank-account-utf8-none.ofx')
        )

        self.assertEqual(parsed.product_type, 'bank_account')
        self.assertEqual(parsed.external_account_id, 'synthetic-utf8-account-005')
        self.assertEqual(
            parsed.transactions[0].description,
            'Compra sintética ação',
        )

    def test_parses_equals_separated_utf8_none_header(self):
        content = self._fixture_bytes('nubank-account-utf8-none.ofx').replace(
            b'ENCODING:UTF-8',
            b'ENCODING=UTF-8',
        )
        content = content.replace(b'CHARSET:NONE', b'CHARSET=NONE')

        parsed = parse_nubank_ofx(content)

        self.assertEqual(parsed.product_type, 'bank_account')

    def test_preserves_legacy_cp1252_header_without_encoding(self):
        content = self._fixture_bytes('nubank-account.ofx').replace(
            b'ENCODING:USASCII\n',
            b'',
        )

        parsed = parse_nubank_ofx(content)

        self.assertEqual(parsed.external_account_id, 'synthetic-account-001')

    def test_parses_sgml_card_with_explicit_leaf_closing_tags(self):
        parsed = parse_nubank_ofx(
            self._fixture_bytes('nubank-card-explicit-leaf-closing.ofx')
        )

        self.assertEqual(parsed.product_type, 'credit_card')
        self.assertEqual(parsed.external_account_id, 'synthetic-explicit-card-006')
        self.assertEqual(
            parsed.transactions[0].external_id,
            'synthetic-explicit-card-fitid-001',
        )

    def test_rejects_bomless_utf8_declared_by_ofx_header(self):
        content = self._fixture_bytes('nubank-account.ofx').replace(
            b'CHARSET:1252', b'CHARSET:UTF-8'
        )

        with self.assertRaises(OfxParseError):
            parse_nubank_ofx(content + 'Synthetic caf\u00e9'.encode('utf-8'))

    def test_accepts_ofx_timezone_suffix_on_posted_date(self):
        parsed = parse_nubank_ofx(self._fixture_bytes('nubank-canonical-sgml.ofx'))

        self.assertEqual(parsed.transactions[0].posted_on, date(2026, 3, 2))

    def test_rejects_malformed_ofx_date_or_timezone(self):
        fixture = self._fixture_bytes('nubank-canonical-sgml.ofx')
        for malformed_value in (
            b'20260302invalid',
            b'20260302120000[-03',
            b'20260302240000',
            b'20260302126000',
            b'20260302125960',
            b'20260302120000[+99]',
        ):
            with self.subTest(value=malformed_value), self.assertRaises(OfxParseError):
                content = fixture.replace(b'20260302120000[-03:00]', malformed_value)
                parse_nubank_ofx(content)

    def test_rejects_malformed_xml_without_sgml_header_fallback(self):
        content = self._fixture_bytes('nubank-account.ofx').replace(
            b'DATA:OFXSGML', b'DATA:OFXXML'
        )

        with self.assertRaises(OfxParseError):
            parse_nubank_ofx(content)

    def test_rejects_unknown_encoding_and_mismatched_sgml_closing_tag(self):
        fixture = self._fixture_bytes('nubank-account-utf8-none.ofx')
        invalid_documents = (
            fixture.replace(b'ENCODING:UTF-8', b'ENCODING:UTF-16'),
            fixture.replace(b'</STMTTRN>', b'</BANKTRANLIST>', 1),
        )

        for content in invalid_documents:
            with self.subTest(content=content[:80]), self.assertRaises(OfxParseError):
                parse_nubank_ofx(content)

    def test_does_not_accept_encoding_declaration_spoofed_inside_ofx_body(self):
        content = self._fixture_bytes('nubank-account-utf8-none.ofx').replace(
            b'ENCODING:UTF-8\n',
            b'',
        )
        content = content.replace(
            b'<MEMO>Compra ',
            b'<MEMO>\nENCODING:UTF-8\nCompra ',
        )

        with self.assertRaises(OfxParseError):
            parse_nubank_ofx(content)

    def test_rejects_transactions_missing_required_fields(self):
        fixture = self._fixture_bytes('nubank-account.ofx')
        for tag, value in (
            (b'DTPOSTED', b'20260102120000'),
            (b'TRNAMT', b'-42.50'),
            (b'MEMO', b'Synthetic market purchase'),
        ):
            with self.subTest(tag=tag), self.assertRaises(OfxParseError):
                content = fixture.replace(b'<' + tag + b'>' + value, b'<' + tag + b'>')
                parse_nubank_ofx(content)

    def test_rejects_synthetic_non_ofx_content(self):
        with self.assertRaises(UnsupportedOfxError):
            parse_nubank_ofx(self._fixture_bytes('nubank-invalid.ofx'))

    def test_rejects_account_statement_without_account_id(self):
        content = self._fixture_bytes('nubank-account.ofx').replace(
            b'<ACCTID>synthetic-account-001', b'<ACCTID>'
        )

        with self.assertRaises(UnsupportedOfxError):
            parse_nubank_ofx(content)

    def test_rejects_non_brl_statement(self):
        content = self._fixture_bytes('nubank-account.ofx').replace(
            b'<CURDEF>BRL', b'<CURDEF>USD'
        )

        with self.assertRaises(UnsupportedOfxError):
            parse_nubank_ofx(content)

    def test_rejects_values_that_do_not_fit_normalized_models(self):
        fixture = self._fixture_bytes('nubank-account.ofx')
        invalid_replacements = (
            (
                b'<ACCTID>synthetic-account-001',
                b'<ACCTID>' + b'a' * 256,
            ),
            (
                b'<FITID>synthetic-fitid-001',
                b'<FITID>' + b'f' * 256,
            ),
            (
                b'<MEMO>Synthetic market purchase',
                b'<MEMO>' + b'm' * 256,
            ),
            (b'<TRNAMT>-42.50', b'<TRNAMT>12345678901.00'),
            (b'<TRNAMT>-42.50', b'<TRNAMT>1.001'),
            (b'<TRNAMT>-42.50', b'<TRNAMT>1.000'),
        )
        for old, new in invalid_replacements:
            with self.subTest(new=new[:32]), self.assertRaises(OfxParseError):
                parse_nubank_ofx(fixture.replace(old, new))

    def test_rejects_content_larger_than_ten_mebibytes(self):
        with self.assertRaises(OversizedOfxError):
            parse_nubank_ofx(b'x' * (10 * 1024 * 1024 + 1))

    def test_normalizes_negative_zero_to_zero_amount(self):
        content = self._fixture_bytes('nubank-account.ofx').replace(b'-42.50', b'-0')

        parsed = parse_nubank_ofx(content)

        self.assertEqual(parsed.transactions[0].amount, Decimal('0.00'))
        self.assertEqual(parsed.transactions[0].transaction_type, 'income')

    @staticmethod
    def _fixture_bytes(name):
        return (FIXTURES_DIR / name).read_bytes()

    @staticmethod
    def _transaction(**kwargs):
        from imports.ofx import ParsedOfxTransaction

        return ParsedOfxTransaction(**kwargs)
