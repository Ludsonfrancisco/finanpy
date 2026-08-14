import 'package:flutter/material.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_spacing.dart';

final class CommitmentsSummary extends StatelessWidget {
  const CommitmentsSummary({
    required this.commitmentMinor,
    required this.monthExpenseMinor,
    required this.monthLabel,
    required this.hidden,
    super.key,
  });

  final int? commitmentMinor;
  final int? monthExpenseMinor;
  final String monthLabel;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final commitment = _SummaryValue(
      label: 'Compromissos próximos',
      minorUnits: commitmentMinor,
      hidden: hidden,
    );
    final expense = _SummaryValue(
      label: 'Gasto em $monthLabel',
      minorUnits: monthExpenseMinor,
      hidden: hidden,
    );
    if (scale >= 1.5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          commitment,
          const SizedBox(height: LarSpacing.xl),
          expense,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: commitment),
        const SizedBox(width: LarSpacing.xl),
        Expanded(child: expense),
      ],
    );
  }
}

final class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.minorUnits,
    required this.hidden,
  });

  final String label;
  final int? minorUnits;
  final bool hidden;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: LarSpacing.sm),
      FinancialAmount(
        minorUnits: minorUnits,
        hidden: hidden,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
