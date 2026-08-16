import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/lar_spacing.dart';
import '../../domain/import_preview.dart';

/// States the detected product and the window the file covers.
///
/// The label is the compatibility profile of the file, never a proof that the
/// statement came from the institution it resembles.
final class ImportSourceCard extends StatelessWidget {
  const ImportSourceCard({
    required this.preview,
    this.formatExpiry = formatLocalExpiry,
    super.key,
  });

  final ImportPreview preview;

  /// Renders the expiry in the local zone of the device. A golden pins its own
  /// formatter, because a wall clock would depend on the machine that runs it.
  final String Function(DateTime expiresAt) formatExpiry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final period =
        '${_day.format(preview.statementStart)} a '
        '${_day.format(preview.statementEnd)}';
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Origem declarada', style: text.labelLarge),
          const SizedBox(height: LarSpacing.xxs),
          Text(productLabel(preview.productType), style: text.titleLarge),
          const SizedBox(height: LarSpacing.xxs),
          Text(
            'Perfil compatível com o arquivo; não é prova de origem.',
            style: text.bodySmall,
          ),
          const SizedBox(height: LarSpacing.md),
          Text('Período', style: text.labelLarge),
          const SizedBox(height: LarSpacing.xxs),
          Text(period, style: text.bodyLarge),
          const SizedBox(height: LarSpacing.md),
          Text(
            'Prévia disponível até ${formatExpiry(preview.expiresAt)}',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

String productLabel(ImportProductType type) => switch (type) {
  ImportProductType.bankAccount => 'Nubank — Conta',
  ImportProductType.creditCard => 'Nubank — Cartão',
};

String formatLocalExpiry(DateTime expiresAt) =>
    _expiry.format(expiresAt.toLocal());

final DateFormat _day = DateFormat('dd MMM yyyy', 'pt_BR');
final DateFormat _expiry = DateFormat('dd/MM/yyyy, HH:mm', 'pt_BR');
