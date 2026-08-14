import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final class FinancialAmount extends StatelessWidget {
  const FinancialAmount({
    required this.minorUnits,
    required this.hidden,
    this.showPositiveSign = false,
    this.style,
    this.wrapAtLargeText = true,
    super.key,
  });
  final int? minorUnits;
  final bool hidden;
  final bool showPositiveSign;
  final TextStyle? style;
  final bool wrapAtLargeText;

  @override
  Widget build(BuildContext context) {
    final amount = minorUnits;
    final visible = amount == null
        ? 'Indisponível'
        : formatBrlMinor(amount, showPositiveSign: showPositiveSign);
    final value = hidden ? 'R\$\u00a0••••••' : visible;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final paintedValue = wrapAtLargeText && scale >= 1.8
        ? value.replaceFirst('\u00a0', '\n')
        : value;
    final resolvedStyle =
        style ??
        Theme.of(context).textTheme.displaySmall?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          height: 1.15,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );
    return Semantics(
      label: hidden
          ? 'Valor oculto'
          : amount == null
          ? 'Valor financeiro indisponível'
          : 'Valor financeiro',
      value: amount == null || hidden ? null : visible,
      child: ExcludeSemantics(
        child: Text(
          paintedValue,
          style: resolvedStyle?.copyWith(
            color:
                resolvedStyle.color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

String formatBrlMinor(int minorUnits, {bool showPositiveSign = false}) {
  final negative = minorUnits < 0;
  final magnitude = negative ? -minorUnits : minorUnits;
  final whole = magnitude ~/ 100;
  final cents = (magnitude % 100).toString().padLeft(2, '0');
  final sign = negative
      ? '-'
      : showPositiveSign && minorUnits > 0
      ? '+'
      : '';
  final grouped = NumberFormat.decimalPattern('pt_BR').format(whole);
  return '${sign}R\$\u00a0$grouped,$cents';
}
