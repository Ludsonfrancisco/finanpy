import 'package:flutter/material.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_spacing.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Saldo consolidado', style: textTheme.titleMedium),
          const SizedBox(height: LarSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) => FinancialAmount(
              minorUnits: balanceMinor,
              hidden: hidden,
              style: textTheme.displaySmall?.copyWith(
                fontSize: constraints.maxWidth >= 560 ? 48 : 40,
                fontWeight: FontWeight.w600,
                height: 1.1,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
