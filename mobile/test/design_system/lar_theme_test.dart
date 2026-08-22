import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/design_system/lar_colors.dart';
import 'package:lar_finance/design_system/lar_spacing.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/design_system/lar_tokens.g.dart';
import 'package:lar_finance/design_system/lar_typography.dart';

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

  test('verde mineral de leitura mantém contraste AA no canvas escuro', () {
    expect(
      _contrastRatio(LarColors.mineralOnDark, LarColors.darkCanvas),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('public design-system facades consume generated tokens', () {
    expect(LarColors.darkCanvas, LarGeneratedColors.darkCanvas);
    expect(LarColors.lightTextSecondary, LarGeneratedLightColors.textSecondary);
    expect(LarColors.darkDanger, LarGeneratedDarkColors.stateDanger);
    expect(LarSpacing.md, LarGeneratedSpacing.md);
    expect(
      LarTypography.financial.fontSize,
      LarGeneratedTypography.financialFontSize,
    );
    expect(
      LarTypography.financial.height,
      LarGeneratedTypography.financialLineHeight,
    );
  });

  test('generated token file is imported only inside design_system', () {
    final violations = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.contains('design_system'))
        .where((file) => file.readAsStringSync().contains('lar_tokens.g.dart'))
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
