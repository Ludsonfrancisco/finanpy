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
}
