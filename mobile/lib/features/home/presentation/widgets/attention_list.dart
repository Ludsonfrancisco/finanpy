import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';

final class AttentionList extends StatelessWidget {
  const AttentionList({required this.messages, super.key});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE1B86A)
        : LarColors.amber;
    return Semantics(
      container: true,
      label: 'Atenção',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Atenção', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: LarSpacing.sm),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: LarSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(Icons.info_outline, size: 20, color: color),
                  ),
                  const SizedBox(width: LarSpacing.sm),
                  Expanded(child: Text(message)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
