import 'package:flutter/material.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import 'home_financial_surface.dart';

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
      cardKey: const Key('home-commitment-card'),
      accentColor: LarColors.champagne,
      label: 'Compromissos próximos',
      minorUnits: commitmentMinor,
      hidden: hidden,
    );
    final expense = _SummaryValue(
      cardKey: const Key('home-expense-card'),
      accentColor: LarColors.danger,
      label: 'Gasto em $monthLabel',
      minorUnits: monthExpenseMinor,
      hidden: hidden,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (scale >= 1.5 || constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              commitment,
              const SizedBox(height: LarSpacing.lg),
              expense,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: commitment),
            const SizedBox(width: LarSpacing.lg),
            Expanded(child: expense),
          ],
        );
      },
    );
  }
}

final class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.cardKey,
    required this.accentColor,
    required this.label,
    required this.minorUnits,
    required this.hidden,
  });

  final Key cardKey;
  final Color accentColor;
  final String label;
  final int? minorUnits;
  final bool hidden;

  @override
  Widget build(BuildContext context) => HomeFinancialSurface(
    key: cardKey,
    accentColor: accentColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: LarSpacing.md),
        FinancialAmount(
          minorUnits: minorUnits,
          hidden: hidden,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
