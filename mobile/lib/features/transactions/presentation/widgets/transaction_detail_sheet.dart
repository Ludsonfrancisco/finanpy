import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../data/transactions_repository.dart';
import '../../domain/transactions_models.dart';
import 'transaction_form_sheet.dart';

final class TransactionDetailSheet extends StatelessWidget {
  const TransactionDetailSheet({
    required this.item,
    required this.hidden,
    this.repository,
    this.onEdit,
    super.key,
  });

  final TransactionItem item;
  final bool hidden;
  final TransactionsRepository? repository;
  final VoidCallback? onEdit;

  static Future<void> show(
    BuildContext context, {
    required TransactionItem item,
    required bool hidden,
    TransactionsRepository? repository,
    VoidCallback? onEdit,
  }) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    if (desktop) {
      return showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(LarSpacing.xl),
              child: TransactionDetailSheet(
                item: item,
                hidden: hidden,
                repository: repository,
                onEdit: onEdit,
              ),
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(LarSpacing.xl),
          child: TransactionDetailSheet(
            item: item,
            hidden: hidden,
            repository: repository,
            onEdit: onEdit,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final isIncome = item.type == TransactionType.income;

    final dateStr = DateFormat(
      "dd/MM/yyyy 'às' HH:mm",
      'pt_BR',
    ).format(item.date.toLocal());
    final updatedStr = DateFormat(
      "dd/MM/yyyy 'às' HH:mm",
      'pt_BR',
    ).format(item.updatedAt.toLocal());

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Detalhes da Movimentação',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: LarSpacing.lg),
        Center(
          child: Column(
            children: <Widget>[
              Text(
                item.description,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: LarSpacing.xs),
              FinancialAmount(
                minorUnits: item.signedAmountMinor,
                hidden: hidden,
                showPositiveSign: true,
                style: text.displaySmall?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isIncome
                      ? (isDark ? LarColors.mineralOnDark : LarColors.mineral)
                      : LarColors.danger,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LarSpacing.xl),
        const Divider(),
        const SizedBox(height: LarSpacing.md),
        _DetailRow(label: 'Tipo', value: item.type.label),
        _DetailRow(label: 'Data', value: dateStr),
        _DetailRow(label: 'Categoria', value: item.categoryName),
        _DetailRow(label: 'Conta', value: item.accountName),
        _DetailRow(label: 'Responsável', value: item.ownerName),
        _DetailRow(label: 'Última atualização', value: updatedStr),
        _DetailRow(
          label: 'Identificador (UUID)',
          value: item.uuid,
          isMono: true,
        ),
        if (repository != null || onEdit != null) ...[
          const SizedBox(height: LarSpacing.lg),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              if (onEdit != null) {
                onEdit!();
              } else if (repository != null) {
                TransactionFormSheet.show(
                  context,
                  repository: repository!,
                  initialItem: item,
                );
              }
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar Movimentação'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: LarSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        const SizedBox(height: LarSpacing.lg),
      ],
    );
  }
}

final class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isMono = false,
  });

  final String label;
  final String value;
  final bool isMono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LarSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: text.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: LarSpacing.md),
          Flexible(
            child: Text(
              value,
              style: isMono
                  ? text.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    )
                  : text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
