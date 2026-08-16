import re
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Literal
from xml.etree import ElementTree

MAX_OFX_BYTES = 10 * 1024 * 1024
MAX_NORMALIZED_TEXT_LENGTH = 255
MAX_NORMALIZED_AMOUNT = Decimal('9999999999.99')
OFX_DATE_PATTERN = re.compile(
    r'(?P<date>\d{8})(?:'
    r'(?P<hour>\d{2})(?P<minute>\d{2})(?P<second>\d{2})'
    r'(?:\.\d{1,3})?'
    r'(?:\[(?P<offset>[+-]\d{1,2})(?::[A-Za-z0-9 _+.-]+)?\])?'
    r')?'
)
CP1252_CHARSETS = {b'1252', b'CP1252', b'WINDOWS-1252'}
CP1252_ENCODINGS = {None, b'ASCII', b'USASCII'}
UTF8_ENCODINGS = {b'UTF-8', b'UTF8'}
UTF8_CHARSETS = {b'NONE', b'UTF-8', b'UTF8'}


class OfxParseError(ValueError):
    """Raised when OFX content cannot be parsed safely."""


class UnsupportedOfxError(OfxParseError):
    """Raised when content is not a supported account or card OFX statement."""


class OversizedOfxError(OfxParseError):
    """Raised when OFX content exceeds the accepted size limit."""


@dataclass(frozen=True)
class ParsedOfxTransaction:
    external_id: str | None
    posted_on: date
    amount: Decimal
    description: str
    transaction_type: Literal['income', 'expense']


@dataclass(frozen=True)
class ParsedNubankOfx:
    product_type: Literal['bank_account', 'credit_card']
    external_account_id: str
    statement_start: date
    statement_end: date
    transactions: tuple[ParsedOfxTransaction, ...]


def parse_nubank_ofx(content: bytes) -> ParsedNubankOfx:
    """Parse a BRL OFX statement structurally compatible with the Nubank pilot."""
    if len(content) > MAX_OFX_BYTES:
        raise OversizedOfxError('OFX content exceeds the maximum accepted size.')

    root = _parse_ofx(_decode(content))
    bank_account = root.find('.//BANKACCTFROM')
    card_account = root.find('.//CCACCTFROM')
    if (bank_account is None) == (card_account is None):
        raise UnsupportedOfxError('OFX statement product is unsupported.')

    product_type: Literal['bank_account', 'credit_card']
    if bank_account is not None:
        product_type = 'bank_account'
        account = bank_account
    else:
        product_type = 'credit_card'
        account = card_account

    currency = _required_text(root, './/CURDEF', UnsupportedOfxError).upper()
    if currency != 'BRL':
        raise UnsupportedOfxError('OFX statement currency is unsupported.')

    account_id = _limited_text(
        _required_text(account, 'ACCTID', UnsupportedOfxError),
        'ACCTID',
        UnsupportedOfxError,
    )
    transaction_list = root.find('.//BANKTRANLIST')
    if transaction_list is None:
        raise OfxParseError('OFX statement is missing its transaction list.')

    return ParsedNubankOfx(
        product_type=product_type,
        external_account_id=account_id,
        statement_start=_parse_date(_required_text(transaction_list, 'DTSTART')),
        statement_end=_parse_date(_required_text(transaction_list, 'DTEND')),
        transactions=tuple(
            _parse_transaction(item) for item in transaction_list.findall('STMTTRN')
        ),
    )


def _decode(content: bytes) -> str:
    try:
        if content.startswith(b'\xef\xbb\xbf'):
            return content.decode('utf-8-sig')
        ofx_start = content.upper().find(b'<OFX>')
        if ofx_start < 0:
            return content.decode('cp1252')
        header = content[:ofx_start]
        encoding = _header_value(header, b'ENCODING')
        charset = _header_value(header, b'CHARSET')
        if encoding in UTF8_ENCODINGS and charset in UTF8_CHARSETS:
            return content.decode('utf-8')
        if encoding in CP1252_ENCODINGS and charset in CP1252_CHARSETS:
            return content.decode('cp1252')
        raise OfxParseError('OFX content has an unsupported encoding.')
    except UnicodeDecodeError as error:
        raise OfxParseError('OFX content has an unsupported encoding.') from error


def _header_value(content: bytes, name: bytes) -> bytes | None:
    match = re.search(
        rb'(?im)^' + re.escape(name) + rb'\s*[:=]\s*([^\r\n]+)',
        content,
    )
    return match.group(1).strip().upper() if match else None


def _parse_ofx(text: str) -> ElementTree.Element:
    ofx_start = text.upper().find('<OFX>')
    if ofx_start < 0:
        raise UnsupportedOfxError('Content is not an OFX document.')

    ofx = text[ofx_start:]
    if 'DATA:OFXSGML' in text[:ofx_start].upper():
        return _parse_sgml(ofx)
    try:
        return ElementTree.fromstring(ofx)
    except ElementTree.ParseError as error:
        raise OfxParseError('OFX XML markup is malformed.') from error


def _parse_sgml(text: str) -> ElementTree.Element:
    """Read OFX SGML, deciding aggregate from leaf by shape rather than by name.

    A list of known aggregates cannot survive a real statement: every section
    the institution adds that the list never heard of would read as malformed.
    """
    root = ElementTree.Element('_ROOT')
    stack = [root]
    position = 0
    pending_leaf_tag = None

    while position < len(text):
        tag_start = text.find('<', position)
        if tag_start < 0:
            break
        tag_end = text.find('>', tag_start + 1)
        if tag_end < 0:
            raise OfxParseError('OFX markup is malformed.')
        token = text[tag_start + 1 : tag_end].strip()
        position = tag_end + 1
        if not token or token.startswith('?') or token.startswith('!'):
            continue
        if token.startswith('/'):
            closing_tag = token[1:].strip().upper()
            if pending_leaf_tag == closing_tag:
                pending_leaf_tag = None
                continue
            pending_leaf_tag = None
            if stack[-1] is root or stack[-1].tag != closing_tag:
                raise OfxParseError('OFX markup is malformed.')
            stack.pop()
            continue

        pending_leaf_tag = None
        tag = token.split()[0].upper()
        element = ElementTree.SubElement(stack[-1], tag)
        value, position = _sgml_content(text, position, tag)
        if value is None:
            stack.append(element)
        else:
            element.text = value
            pending_leaf_tag = tag

    if len(stack) != 1 or len(root) != 1 or root[0].tag != 'OFX':
        raise OfxParseError('OFX markup is malformed.')
    return root[0]


def _sgml_content(text: str, position: int, tag: str) -> tuple[str | None, int]:
    """Return the leaf text and the next position, or `None` for an aggregate.

    SGML omits the closing tag of a leaf, so what follows the tag tells them
    apart: text means a leaf, an opening tag means an aggregate. An empty leaf
    is the one ambiguous case, and only one question separates it from an
    aggregate — whether this tag is ever closed.
    """
    next_tag = text.find('<', position)
    if next_tag < 0:
        return text[position:].strip(), len(text)
    value = text[position:next_tag].strip()
    if value or text.startswith('</', next_tag):
        return value, next_tag
    if _closes_later(text, next_tag, tag):
        return None, next_tag
    return '', next_tag


def _closes_later(text: str, position: int, tag: str) -> bool:
    pattern = re.compile(r'<\s*/\s*' + re.escape(tag) + r'\s*>', re.IGNORECASE)
    return pattern.search(text, position) is not None


def _parse_transaction(item: ElementTree.Element) -> ParsedOfxTransaction:
    amount = _parse_amount(_required_text(item, 'TRNAMT'))
    transaction_type: Literal['income', 'expense']
    transaction_type = 'expense' if amount < 0 else 'income'
    return ParsedOfxTransaction(
        external_id=_limited_optional_text(item, 'FITID'),
        posted_on=_parse_date(_required_text(item, 'DTPOSTED')),
        amount=amount,
        description=_limited_text(
            ' '.join(_required_text(item, 'MEMO').split()),
            'MEMO',
        ),
        transaction_type=transaction_type,
    )


def _required_text(
    element: ElementTree.Element | None,
    tag: str,
    error_type: type[OfxParseError] = OfxParseError,
) -> str:
    value = _optional_text(element, tag)
    if value is None:
        raise error_type(f'OFX content is missing required {tag} data.')
    return value


def _optional_text(element: ElementTree.Element | None, tag: str) -> str | None:
    if element is None:
        return None
    child = element.find(tag)
    if child is None or child.text is None:
        return None
    value = child.text.strip()
    return value or None


def _limited_optional_text(
    element: ElementTree.Element | None,
    tag: str,
) -> str | None:
    value = _optional_text(element, tag)
    return _limited_text(value, tag) if value is not None else None


def _limited_text(
    value: str,
    tag: str,
    error_type: type[OfxParseError] = OfxParseError,
) -> str:
    if len(value) > MAX_NORMALIZED_TEXT_LENGTH:
        raise error_type(f'OFX {tag} data exceeds the accepted length.')
    return value


def _parse_date(value: str) -> date:
    match = OFX_DATE_PATTERN.fullmatch(value)
    if match is None:
        raise OfxParseError('OFX date is invalid.')
    try:
        parsed_date = date.fromisoformat(
            f'{match["date"][:4]}-{match["date"][4:6]}-{match["date"][6:8]}'
        )
    except ValueError as error:
        raise OfxParseError('OFX date is invalid.') from error
    if match['hour'] is not None:
        clock_limits = (('hour', 23), ('minute', 59), ('second', 59))
        if any(int(match[key]) > limit for key, limit in clock_limits):
            raise OfxParseError('OFX time is invalid.')
        if match['offset'] is not None and not -12 <= int(match['offset']) <= 14:
            raise OfxParseError('OFX timezone offset is invalid.')
    return parsed_date


def _parse_amount(value: str) -> Decimal:
    try:
        amount = Decimal(value)
    except InvalidOperation as error:
        raise OfxParseError('OFX amount is invalid.') from error
    if not amount.is_finite():
        raise OfxParseError('OFX amount is invalid.')
    if abs(amount) > MAX_NORMALIZED_AMOUNT:
        raise OfxParseError('OFX amount exceeds the accepted range.')
    if amount.as_tuple().exponent < -2:
        raise OfxParseError('OFX amount has unsupported precision.')
    if amount.is_zero():
        return Decimal('0.00')
    return amount
