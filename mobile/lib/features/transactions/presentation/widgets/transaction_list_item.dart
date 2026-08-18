import 'package:flutter/material.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/transactions_models.dart';

final class TransactionListItem extends StatelessWidget {
  const TransactionListItem({
    required this.item,
    required this.hidden,
    this.onTap,
    super.key,
  });

  final TransactionItem item;
  final bool hidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final isIncome = item.type == TransactionType.income;

    final categoryColor = _parseColor(
      item.categoryColor,
      fallback: isDark ? LarColors.mineralOnDark : LarColors.mineral,
    );

    return InkWell(
      key: Key('transaction-item-${item.uuid}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LarSpacing.md,
          vertical: LarSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: isDark ? 0.2 : 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  isIncome
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 20,
                  color: isIncome
                      ? (isDark ? LarColors.mineralOnDark : LarColors.mineral)
                      : LarColors.danger,
                ),
              ),
            ),
            const SizedBox(width: LarSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.description,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          item.categoryName,
                          style: text.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '•',
                        style: text.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.accountName,
                          style: text.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: LarSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FinancialAmount(
                  minorUnits: item.signedAmountMinor,
                  hidden: hidden,
                  showPositiveSign: true,
                  style: text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isIncome
                        ? (isDark ? LarColors.mineralOnDark : LarColors.mineral)
                        : (isDark ? const Color(0xFFF28B82) : LarColors.danger),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.ownerName,
                  style: text.labelSmall?.copyWith(
                    fontSize: 10,
                    color: isDark
                        ? LarColors.champagne
                        : const Color(0xFF8C6D23),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color _parseColor(String hexString, {required Color fallback}) {
  final buffer = StringBuffer();
  String cleaned = hexString.replaceAll('#', '').trim();
  if (cleaned.length == 6) {
    buffer.write('ff');
    buffer.write(cleaned);
  } else if (cleaned.length == 8) {
    buffer.write(cleaned);
  } else {
    return fallback;
  }
  try {
    return Color(int.parse(buffer.toString(), radix: 16));
  } catch (_) {
    return fallback;
  }
}
