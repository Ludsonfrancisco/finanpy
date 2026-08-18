import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../../transactions/domain/transactions_models.dart';
import '../../domain/categories_models.dart';

final class CategoryCard extends StatelessWidget {
  const CategoryCard({required this.category, this.onTap, super.key});

  final CategoryItem category;
  final VoidCallback? onTap;

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
    final catColor = _parseColor(category.color);
    final isIncome = category.type == TransactionType.income;

    return Semantics(
      button: true,
      label:
          'Categoria ${category.name}, ${category.type.label}, ${category.transactionCount} movimentações',
      child: Material(
        color: isDark ? LarColors.darkSurface : LarColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(LarSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF31403A)
                    : const Color(0xFFCBC5B9),
              ),
            ),
            child: Row(
              children: [
                // Avatar com cor da categoria
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: catColor.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Text(
                      category.name.isNotEmpty
                          ? category.name[0].toUpperCase()
                          : '?',
                      style: text.titleMedium?.copyWith(
                        color: catColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: LarSpacing.md),

                // Nome e contagem
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${category.transactionCount} ${category.transactionCount == 1 ? "movimentação" : "movimentações"}',
                        style: text.bodySmall?.copyWith(
                          color: isDark
                              ? const Color(0xFF8D958D)
                              : const Color(0xFF8B8A80),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: LarSpacing.sm),

                // Badge de tipo
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isIncome
                        ? LarColors.mineral.withValues(alpha: 0.12)
                        : LarColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    category.type.label,
                    style: text.labelSmall?.copyWith(
                      color: isIncome ? LarColors.mineral : LarColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: LarSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: isDark
                      ? const Color(0xFF8D958D)
                      : const Color(0xFF8B8A80),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
