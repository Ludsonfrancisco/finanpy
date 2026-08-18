import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/reports_models.dart';

final class CategoryDistributionListWidget extends StatelessWidget {
  const CategoryDistributionListWidget({
    required this.distributions,
    super.key,
  });

  final List<CategoryExpenseDistribution> distributions;

  String _formatReais(int minorUnits) {
    final double value = minorUnits / 100.0;
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return LarColors.mineral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    if (distributions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Despesas por Categoria',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: LarSpacing.md),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: distributions.length,
          separatorBuilder: (_, _) => const SizedBox(height: LarSpacing.md),
          itemBuilder: (context, index) {
            final item = distributions[index];
            final catColor = _parseColor(item.color);

            return Container(
              padding: const EdgeInsets.all(LarSpacing.md),
              decoration: BoxDecoration(
                color: isDark ? LarColors.darkSurface : LarColors.lightSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF31403A)
                      : const Color(0xFFCBC5B9),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: catColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: LarSpacing.sm),
                      Expanded(
                        child: Text(
                          item.categoryName,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatReais(item.totalMinor),
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: LarSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (item.percentage / 100.0).clamp(0.0, 1.0),
                            backgroundColor: isDark
                                ? const Color(0xFF222C27)
                                : const Color(0xFFE4DFD5),
                            valueColor: AlwaysStoppedAnimation<Color>(catColor),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: LarSpacing.md),
                      Text(
                        '${item.percentage.toStringAsFixed(1)}%',
                        style: text.labelSmall?.copyWith(
                          color: isDark
                              ? const Color(0xFF8D958D)
                              : const Color(0xFF8B8A80),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.transactionCount} ${item.transactionCount == 1 ? "lançamento" : "lançamentos"}',
                    style: text.bodySmall?.copyWith(
                      color: isDark
                          ? const Color(0xFF8D958D)
                          : const Color(0xFF8B8A80),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
