import 'package:flutter/material.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';

final class AccountsSummaryHeader extends StatelessWidget {
  const AccountsSummaryHeader({
    required this.totalBalanceMinor,
    required this.accountCount,
    required this.hidden,
    super.key,
  });

  final int? totalBalanceMinor;
  final int accountCount;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      container: true,
      label: 'Resumo geral de contas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'TOTAL EM CONTAS',
                style: text.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: isDark ? LarColors.champagne : const Color(0xFF8C6D23),
                ),
              ),
              if (accountCount > 0)
                Text(
                  accountCount == 1
                      ? '1 conta ativa'
                      : '$accountCount contas ativas',
                  style: text.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: LarSpacing.xs),
          FinancialAmount(
            minorUnits: totalBalanceMinor,
            hidden: hidden,
            style: text.displaySmall?.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
