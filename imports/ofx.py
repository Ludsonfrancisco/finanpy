import re
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Literal
from xml.etree import ElementTree

MAX_OFX_BYTES = 10 * 1024 * 1024
OFX_DATE_PATTERN = re.compile(
    r'(?P<date>\d{8})(?:'
    r'(?P<hour>\d{2})(?P<minute>\d{2})(?P<second>\d{2})'
    r'(?:\.\d{1,3})?'
    r'(?:\[(?P<offset>[+-]\d{1,2})(?::[A-Za-z0-9 _+.-]+)?\])?'
    r')?'
)
CP1252_CHARSETS = {b'1252', b'CP1252', b'WINDOWS-1252'}


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
    """Parse a supported Nubank account or credit-card OFX statement from bytes."""
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

    account_id = _required_text(account, 'ACCTID', UnsupportedOfxError)
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
        if b'<OFX>' not in content.upper():
            return content.decode('cp1252')
        charset_match = re.search(br'(?im)^CHARSET\s*:\s*([^\r\n]+)', content)
        charset = charset_match.group(1).strip().upper() if charset_match else None
        if charset not in CP1252_CHARSETS:
            raise OfxParseError('OFX content has an unsupported encoding.')
        return content.decode('cp1252')
    except UnicodeDecodeError as error:
        raise OfxParseError('OFX content has an unsupported encoding.') from error


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
    root = ElementTree.Element('_ROOT')
    stack = [root]
    position = 0
    container_tags = {
        'OFX',
        'SIGNONMSGSRSV1',
        'SONRS',
        'STATUS',
        'FI',
        'BANKMSGSRSV1',
        'STMTTRNRS',
        'STMTRS',
        'BANKACCTFROM',
        'BANKTRANLIST',
        'STMTTRN',
        'LEDGERBAL',
        'CREDITCARDMSGSRSV1',
        'CCSTMTTRNRS',
        'CCSTMTRS',
        'CCACCTFROM',
    }

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
            while len(stack) > 1 and stack[-1].tag != closing_tag:
                stack.pop()
            if len(stack) == 1:
                raise OfxParseError('OFX markup is malformed.')
            stack.pop()
            continue

        tag = token.split()[0].upper()
        element = ElementTree.SubElement(stack[-1], tag)
        if tag not in container_tags:
            next_tag = text.find('<', position)
            if next_tag < 0:
                value = text[position:]
                position = len(text)
            else:
                value = text[position:next_tag]
                position = next_tag
            element.text = value.strip()
        else:
            stack.append(element)

    if len(stack) != 1 or len(root) != 1 or root[0].tag != 'OFX':
        raise OfxParseError('OFX markup is malformed.')
    return root[0]


def _parse_transaction(item: ElementTree.Element) -> ParsedOfxTransaction:
    amount = _parse_amount(_required_text(item, 'TRNAMT'))
    transaction_type: Literal['income', 'expense']
    transaction_type = 'expense' if amount < 0 else 'income'
    return ParsedOfxTransaction(
        external_id=_optional_text(item, 'FITID'),
        posted_on=_parse_date(_required_text(item, 'DTPOSTED')),
        amount=amount,
        description=_required_text(item, 'MEMO'),
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
    if amount.is_zero():
        return Decimal('0.00')
    return amount
