import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';

final class TransactionsSearchBar extends StatelessWidget {
  const TransactionsSearchBar({
    required this.searchController,
    required this.onChanged,
    required this.onClear,
    required this.onOpenFilters,
    required this.hasActiveFilters,
    super.key,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;
  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: const Key('transactions-search-field'),
            controller: searchController,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Buscar por descrição...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: onClear,
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: LarSpacing.md,
                vertical: LarSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.1),
                ),
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
            ),
          ),
        ),
        const SizedBox(width: LarSpacing.sm),
        Stack(
          alignment: Alignment.topRight,
          children: <Widget>[
            IconButton.filledTonal(
              key: const Key('transactions-filter-button'),
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filtrar movimentações',
              onPressed: onOpenFilters,
            ),
            if (hasActiveFilters)
              Container(
                margin: const EdgeInsets.only(top: 4, right: 4),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: LarColors.champagne,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
