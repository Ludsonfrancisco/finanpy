import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/design_system/lar_colors.dart';
import 'package:lar_finance/design_system/lar_theme.dart';

void main() {
  test('Casa de Valores tokens contain no purple family colors', () {
    for (final color in LarColors.all) {
      final hsv = HSVColor.fromColor(color);
      final purple = hsv.hue >= 260 && hsv.hue <= 330 && hsv.saturation > 0.15;
      expect(purple, isFalse, reason: color.toARGB32().toRadixString(16));
    }
    expect(LarColors.darkCanvas, const Color(0xFF091311));
    expect(LarColors.champagne, const Color(0xFFC7A35A));
  });

  test('light and dark themes use their explicit Casa de Valores canvases', () {
    expect(LarTheme.light.useMaterial3, isTrue);
    expect(LarTheme.dark.useMaterial3, isTrue);
    expect(LarTheme.light.scaffoldBackgroundColor, LarColors.lightCanvas);
    expect(LarTheme.dark.scaffoldBackgroundColor, LarColors.darkCanvas);
  });
}
