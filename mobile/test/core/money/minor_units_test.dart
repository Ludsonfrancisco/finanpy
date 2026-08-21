import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/money/minor_units.dart';

void main() {
  test('parses exact BRL decimal strings to minor units', () {
    expect(parseMinorUnits('0.00'), 0);
    expect(parseMinorUnits('24860.40'), 2486040);
    expect(parseMinorUnits('-12.05'), -1205);
  });

  test('rejects exponent and more than two decimal places', () {
    expect(() => parseMinorUnits('1e3'), throwsFormatException);
    expect(() => parseMinorUnits('10.001'), throwsFormatException);
  });

  test('requires API money to be a canonical two-place string', () {
    expect(parseApiMinorUnits('0.01'), 1);
    expect(parseApiMinorUnits('90071992547409.91'), 9007199254740991);
    expect(() => parseApiMinorUnits(null), throwsFormatException);
    expect(() => parseApiMinorUnits(1.01), throwsFormatException);
    expect(() => parseApiMinorUnits('1.0'), throwsFormatException);
    expect(() => parseApiMinorUnits('1e3'), throwsFormatException);
  });

  test('parses approved pt-BR input without rounding', () {
    expect(parsePtBrMinorUnits('1234'), 123400);
    expect(parsePtBrMinorUnits('1234,5'), 123450);
    expect(parsePtBrMinorUnits('1234,56'), 123456);
    expect(parsePtBrMinorUnits('1.234,56'), 123456);
    expect(parsePtBrMinorUnits(' R\$ 1.234,56 '), 123456);
  });

  test('rejects ambiguous or over-precise pt-BR input', () {
    for (final value in <String>[
      '',
      '-1,00',
      '1,234',
      '12.34,56',
      '1.23.4,56',
      '1e3',
      'R\$ texto',
    ]) {
      expect(() => parsePtBrMinorUnits(value), throwsFormatException);
    }
  });

  test('serializes and formats minor units exactly', () {
    expect(minorUnitsToApiDecimal(0), '0.00');
    expect(minorUnitsToApiDecimal(1), '0.01');
    expect(minorUnitsToApiDecimal(105), '1.05');
    expect(minorUnitsToApiDecimal(-1205), '-12.05');
    expect(minorUnitsToPtBrInput(123456), '1234,56');
    expect(formatBrlMinorUnits(123456), r'R$ 1.234,56');
    expect(formatBrlMinorUnits(-1205), r'-R$ 12,05');
  });
}
