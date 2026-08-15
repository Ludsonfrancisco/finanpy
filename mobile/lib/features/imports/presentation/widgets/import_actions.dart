import 'package:flutter/material.dart';

import '../../../../design_system/lar_spacing.dart';

/// Minimum target that satisfies Android (48 dp) and iOS (44 pt) at once.
const double kImportTargetHeight = 48;

final ButtonStyle _target = ButtonStyle(
  minimumSize: WidgetStateProperty.all(const Size(64, kImportTargetHeight)),
);

/// The persistent decisions of the flow. They never cover the content.
final class ImportActions extends StatelessWidget {
  const ImportActions({
    required this.canConfirm,
    required this.canCancel,
    required this.showConfirmation,
    required this.showSelect,
    required this.selectLabel,
    required this.canSelect,
    required this.showRetry,
    required this.onSelect,
    required this.onConfirm,
    required this.onCancel,
    required this.onRetry,
    required this.retryFocusNode,
    super.key,
  });

  final bool canConfirm;
  final bool canCancel;
  final bool showConfirmation;
  final bool showSelect;
  final String selectLabel;
  final bool canSelect;
  final bool showRetry;
  final VoidCallback onSelect;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final FocusNode retryFocusNode;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (showConfirmation)
        FocusTraversalOrder(
          order: const NumericFocusOrder(1),
          child: FilledButton.icon(
            key: const Key('import-confirm'),
            style: _target,
            onPressed: canConfirm ? onConfirm : null,
            icon: const Icon(Icons.check),
            label: const Text('Confirmar importação'),
          ),
        ),
      if (showConfirmation)
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: OutlinedButton.icon(
            key: const Key('import-cancel'),
            style: _target,
            onPressed: canCancel ? onCancel : null,
            icon: const Icon(Icons.close),
            label: const Text('Cancelar'),
          ),
        ),
      if (showRetry)
        FocusTraversalOrder(
          order: const NumericFocusOrder(1),
          child: FilledButton.icon(
            key: const Key('import-retry'),
            style: _target,
            focusNode: retryFocusNode,
            autofocus: true,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ),
      if (showSelect)
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: OutlinedButton.icon(
            key: const Key('import-select'),
            style: _target,
            onPressed: canSelect ? onSelect : null,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(selectLabel),
          ),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: LarSpacing.md,
      runSpacing: LarSpacing.sm,
      children: buttons,
    );
  }
}
