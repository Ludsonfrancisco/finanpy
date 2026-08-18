import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/transactions_models.dart';

final class TransactionGroupHeader extends StatelessWidget {
  const TransactionGroupHeader({
    required this.group,
    required this.hidden,
    super.key,
  });

  final TransactionGroup group;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groupDate = group.date;
    final String dateLabel;
    if (groupDate.year == today.year &&
        groupDate.month == today.month &&
        groupDate.day == today.day) {
      dateLabel =
          'Hoje, ${DateFormat("d 'de' MMMM", 'pt_BR').format(groupDate)}';
    } else if (groupDate.year == yesterday.year &&
        groupDate.month == yesterday.month &&
        groupDate.day == yesterday.day) {
      dateLabel =
          'Ontem, ${DateFormat("d 'de' MMMM", 'pt_BR').format(groupDate)}';
    } else {
      dateLabel = DateFormat(
        "EEEE, d 'de' MMMM 'de' yyyy",
        'pt_BR',
      ).format(groupDate);
    }

    final netDay = group.dayTotalIncomeMinor - group.dayTotalExpenseMinor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LarSpacing.md,
        LarSpacing.lg,
        LarSpacing.md,
        LarSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(
            child: Text(
              dateLabel.toUpperCase(),
              style: text.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: LarSpacing.sm),
          FinancialAmount(
            minorUnits: netDay,
            hidden: hidden,
            showPositiveSign: true,
            style: text.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}
