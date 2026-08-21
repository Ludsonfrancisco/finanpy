final RegExp _minorUnitsPattern = RegExp(r'^-?\d+\.\d{2}$');
final RegExp _ptBrMoneyPattern = RegExp(
  r'^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?$',
);

int parseMinorUnits(String value) {
  if (!_minorUnitsPattern.hasMatch(value)) {
    throw FormatException('Expected a decimal string with exactly two places.');
  }

  final isNegative = value.startsWith('-');
  final unsignedValue = isNegative ? value.substring(1) : value;
  final parts = unsignedValue.split('.');
  final minorUnits = int.parse(parts[0]) * 100 + int.parse(parts[1]);

  return isNegative ? -minorUnits : minorUnits;
}

int parseApiMinorUnits(Object? value) {
  if (value is! String) {
    throw const FormatException('Expected a decimal string.');
  }
  return parseMinorUnits(value);
}

int parsePtBrMinorUnits(String value) {
  var normalized = value.trim();
  if (normalized.startsWith(r'R$')) {
    normalized = normalized.substring(2).trimLeft();
  }
  final match = _ptBrMoneyPattern.firstMatch(normalized);
  if (match == null) {
    throw const FormatException('Expected a positive pt-BR money value.');
  }
  final whole = int.parse(match.group(1)!.replaceAll('.', ''));
  final rawFraction = match.group(2) ?? '';
  final fraction = rawFraction.isEmpty
      ? 0
      : int.parse(rawFraction.padRight(2, '0'));
  return whole * 100 + fraction;
}

String minorUnitsToApiDecimal(int value) {
  final negative = value < 0;
  final magnitude = value.abs();
  final whole = magnitude ~/ 100;
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
}

String minorUnitsToPtBrInput(int value) =>
    minorUnitsToApiDecimal(value).replaceFirst('.', ',');

String formatBrlMinorUnits(int value) {
  final negative = value < 0;
  final magnitude = value.abs();
  final whole = _groupThousands((magnitude ~/ 100).toString());
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}R\$ $whole,$fraction';
}

String _groupThousands(String digits) {
  final firstGroup = digits.length % 3;
  final parts = <String>[];
  var index = 0;
  if (firstGroup != 0) {
    parts.add(digits.substring(0, firstGroup));
    index = firstGroup;
  }
  while (index < digits.length) {
    parts.add(digits.substring(index, index + 3));
    index += 3;
  }
  return parts.join('.');
}
