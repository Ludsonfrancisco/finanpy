import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/import_preview.dart';

/// The normalized lines of the preview, one by one, with no invented data.
final class ImportRecordList extends StatelessWidget {
  const ImportRecordList({
    required this.records,
    required this.emptyMessage,
    super.key,
  });

  final List<ImportRecordPreview> records;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        'Lançamentos do arquivo',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: LarSpacing.md),
      if (records.isEmpty)
        Text(emptyMessage)
      else
        for (var index = 0; index < records.length; index++) ...<Widget>[
          _RecordRow(record: records[index]),
          if (index < records.length - 1) const Divider(height: 1),
        ],
    ],
  );
}

final class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final ImportRecordPreview record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final income = record.type == ImportEntryType.income;
    final color = income
        ? theme.brightness == Brightness.dark
              ? LarColors.mineralOnDark
              : LarColors.mineral
        : theme.colorScheme.onSurface;
    final signedMinor = income ? record.amountMinor : -record.amountMinor;
    final date = _day.format(record.postedOn);
    final details =
        '${entryLabel(record.type)} · ${outcomeLabel(record.outcome)} · $date';
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final amount = FinancialAmount(
      minorUnits: signedMinor,
      hidden: false,
      showPositiveSign: true,
      wrapAtLargeText: false,
      style: theme.textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(record.description, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(details, style: theme.textTheme.bodySmall),
      ],
    );
    return Semantics(
      container: true,
      label:
          '${record.description}. $details. '
          '${formatBrlMinor(signedMinor, showPositiveSign: true)}.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: LarSpacing.md),
          child: scale >= 1.5
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    description,
                    const SizedBox(height: LarSpacing.sm),
                    amount,
                  ],
                )
              : Row(
                  children: <Widget>[
                    Expanded(child: description),
                    const SizedBox(width: LarSpacing.md),
                    amount,
                  ],
                ),
        ),
      ),
    );
  }
}

String entryLabel(ImportEntryType type) => switch (type) {
  ImportEntryType.income => 'Entrada',
  ImportEntryType.expense => 'Saída',
};

String outcomeLabel(ImportRecordOutcome outcome) => switch (outcome) {
  ImportRecordOutcome.pending => 'Novo',
  ImportRecordOutcome.duplicate => 'Duplicado',
  ImportRecordOutcome.warning => 'Aviso',
  ImportRecordOutcome.created => 'Importado',
};

final DateFormat _day = DateFormat('dd MMM', 'pt_BR');
