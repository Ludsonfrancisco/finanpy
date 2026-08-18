import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/reports_models.dart';

final class ReportsMetricsCard extends StatelessWidget {
  const ReportsMetricsCard({required this.summary, super.key});

  final ReportsSummary summary;

  String _formatReais(int minorUnits) {
    final double value = minorUnits / 100.0;
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    final isPositiveNet = summary.netBalanceMinor >= 0;

    return Container(
      padding: const EdgeInsets.all(LarSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? LarColors.darkSurface : LarColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF31403A) : const Color(0xFFCBC5B9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _metricItem(
                  label: 'Receitas',
                  value: _formatReais(summary.totalIncomeMinor),
                  color: LarColors.mineral,
                  icon: Icons.arrow_upward,
                  text: text,
                  isDark: isDark,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: isDark
                    ? const Color(0xFF31403A)
                    : const Color(0xFFCBC5B9),
              ),
              Expanded(
                child: _metricItem(
                  label: 'Despesas',
                  value: _formatReais(summary.totalExpenseMinor),
                  color: LarColors.danger,
                  icon: Icons.arrow_downward,
                  text: text,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: LarSpacing.md),
          Divider(
            color: isDark ? const Color(0xFF31403A) : const Color(0xFFCBC5B9),
          ),
          const SizedBox(height: LarSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saldo Líquido',
                      style: text.labelSmall?.copyWith(
                        color: isDark
                            ? const Color(0xFF8D958D)
                            : const Color(0xFF8B8A80),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatReais(summary.netBalanceMinor),
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isPositiveNet
                            ? LarColors.mineral
                            : LarColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: summary.savingsRate > 0
                      ? LarColors.mineral.withValues(alpha: 0.15)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: summary.savingsRate > 0
                        ? LarColors.mineral.withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.savings_outlined,
                      size: 16,
                      color: summary.savingsRate > 0
                          ? LarColors.mineral
                          : (isDark
                                ? const Color(0xFF8D958D)
                                : const Color(0xFF8B8A80)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Poupança: ${summary.savingsRate.toStringAsFixed(1)}%',
                      style: text.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: summary.savingsRate > 0
                            ? LarColors.mineral
                            : (isDark
                                  ? const Color(0xFF8D958D)
                                  : const Color(0xFF8B8A80)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricItem({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required TextTheme text,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LarSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: text.labelSmall?.copyWith(
                  color: isDark
                      ? const Color(0xFF8D958D)
                      : const Color(0xFF8B8A80),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
