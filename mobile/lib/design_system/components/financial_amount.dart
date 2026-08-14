import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../lar_typography.dart';

final class FinancialAmount extends StatelessWidget {
  const FinancialAmount({
    required this.minorUnits,
    required this.hidden,
    super.key,
  });
  final int minorUnits;
  final bool hidden;
  String get _visible => NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  ).format(minorUnits / 100);
  @override
  Widget build(BuildContext context) {
    final value = hidden ? 'R\$\u00a0••••••' : _visible;
    return Semantics(
      label: hidden ? 'Valor financeiro oculto' : 'Valor financeiro',
      value: hidden ? null : _visible,
      child: ExcludeSemantics(
        child: Text(
          value,
          style: LarTypography.financial.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
