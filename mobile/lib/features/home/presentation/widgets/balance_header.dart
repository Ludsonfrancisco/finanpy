import 'package:flutter/material.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import 'home_financial_surface.dart';

final class BalanceHeader extends StatelessWidget {
  const BalanceHeader({
    required this.balanceMinor,
    required this.hidden,
    super.key,
  });

  final int? balanceMinor;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: HomeFinancialSurface(
        key: const Key('home-position-card'),
        accentColor: Theme.of(context).brightness == Brightness.dark
            ? LarColors.mineralOnDark
            : LarColors.mineral,
        padding: const EdgeInsets.all(LarSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Saldo consolidado', style: textTheme.titleMedium),
            const SizedBox(height: LarSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) => FinancialAmount(
                minorUnits: balanceMinor,
                hidden: hidden,
                style: textTheme.displaySmall?.copyWith(
                  fontSize: constraints.maxWidth >= 560 ? 48 : 40,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: LarSpacing.sm),
            Text(
              'Soma das contas disponíveis neste responsável.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
