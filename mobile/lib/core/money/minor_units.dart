final RegExp _minorUnitsPattern = RegExp(r'^-?\d+\.\d{2}$');

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
