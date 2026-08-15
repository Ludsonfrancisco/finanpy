import 'package:flutter/material.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/import_preview.dart';

/// Counts and totals of the preview, or of the receipt after confirmation.
final class ImportSummary extends StatelessWidget {
  const ImportSummary({
    required this.preview,
    required this.isReceipt,
    required this.compact,
    super.key,
  });

  final ImportPreview preview;
  final bool isReceipt;

  /// Narrow layouts pair the counts side by side so the list stays reachable.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final counts = <(String, int)>[
      if (isReceipt)
        ('Criados', preview.createdCount)
      else
        ('Lançamentos', preview.recordCount),
      if (!isReceipt) ('Novos', preview.pendingCount),
      ('Duplicados', preview.duplicateCount),
      ('Avisos', preview.warningCount),
    ];
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(isReceipt ? 'Recibo' : 'Resumo', style: text.titleLarge),
          const SizedBox(height: LarSpacing.md),
          if (compact)
            Wrap(
              spacing: LarSpacing.xl,
              runSpacing: LarSpacing.md,
              children: <Widget>[
                for (final count in counts)
                  _CountTile(label: count.$1, value: count.$2),
              ],
            )
          else
            for (final count in counts) ...<Widget>[
              _CountRow(label: count.$1, value: count.$2),
              const Divider(height: 1),
            ],
          const SizedBox(height: LarSpacing.md),
          _TotalRow(
            label: 'Entradas',
            minorUnits: preview.incomeTotalMinor,
            income: true,
          ),
          const SizedBox(height: LarSpacing.sm),
          _TotalRow(
            label: 'Saídas',
            minorUnits: preview.expenseTotalMinor,
            income: false,
          ),
        ],
      ),
    );
  }
}

final class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label: $value',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}

final class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label: $value',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LarSpacing.sm),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            const SizedBox(width: LarSpacing.sm),
            Text(
              '$value',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.minorUnits,
    required this.income,
  });

  final String label;
  final int minorUnits;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = income
        ? theme.brightness == Brightness.dark
              ? LarColors.mineralOnDark
              : LarColors.mineral
        : theme.colorScheme.onSurface;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final amount = FinancialAmount(
      minorUnits: minorUnits,
      hidden: false,
      wrapAtLargeText: false,
      style: theme.textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    return Semantics(
      container: true,
      label: '$label: ${formatBrlMinor(minorUnits)}',
      child: ExcludeSemantics(
        child: scale >= 1.5
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[Text(label), amount],
              )
            : Row(
                children: <Widget>[
                  Expanded(child: Text(label)),
                  const SizedBox(width: LarSpacing.sm),
                  amount,
                ],
              ),
      ),
    );
  }
}
