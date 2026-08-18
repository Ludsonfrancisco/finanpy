import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/transactions_models.dart';

final class TransactionFilterSheet extends StatefulWidget {
  const TransactionFilterSheet({
    required this.initialFilters,
    required this.availableAccounts,
    required this.availableCategories,
    required this.onApply,
    super.key,
  });

  final TransactionFilters initialFilters;
  final List<TransactionFilterOption> availableAccounts;
  final List<TransactionFilterOption> availableCategories;
  final ValueChanged<TransactionFilters> onApply;

  static Future<void> show(
    BuildContext context, {
    required TransactionFilters initialFilters,
    required List<TransactionFilterOption> availableAccounts,
    required List<TransactionFilterOption> availableCategories,
    required ValueChanged<TransactionFilters> onApply,
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
              child: TransactionFilterSheet(
                initialFilters: initialFilters,
                availableAccounts: availableAccounts,
                availableCategories: availableCategories,
                onApply: onApply,
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
          child: TransactionFilterSheet(
            initialFilters: initialFilters,
            availableAccounts: availableAccounts,
            availableCategories: availableCategories,
            onApply: onApply,
          ),
        ),
      ),
    );
  }

  @override
  State<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

final class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  late TransactionType? _selectedType;
  late String? _selectedAccountUuid;
  late String? _selectedCategoryUuid;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialFilters.type;
    _selectedAccountUuid = widget.initialFilters.accountUuid;
    _selectedCategoryUuid = widget.initialFilters.categoryUuid;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'Filtrar Movimentações',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: LarSpacing.lg),
          Text(
            'TIPO DE MOVIMENTAÇÃO',
            style: text.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: LarSpacing.xs),
          Wrap(
            spacing: LarSpacing.sm,
            children: <Widget>[
              ChoiceChip(
                label: const Text('Todos'),
                selected: _selectedType == null,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedType = null);
                },
              ),
              ChoiceChip(
                label: const Text('Receitas'),
                selected: _selectedType == TransactionType.income,
                selectedColor:
                    (isDark ? LarColors.mineralOnDark : LarColors.mineral)
                        .withValues(alpha: 0.25),
                onSelected: (selected) {
                  setState(
                    () => _selectedType = selected
                        ? TransactionType.income
                        : null,
                  );
                },
              ),
              ChoiceChip(
                label: const Text('Despesas'),
                selected: _selectedType == TransactionType.expense,
                selectedColor: LarColors.danger.withValues(alpha: 0.25),
                onSelected: (selected) {
                  setState(
                    () => _selectedType = selected
                        ? TransactionType.expense
                        : null,
                  );
                },
              ),
            ],
          ),
          if (widget.availableAccounts.isNotEmpty) ...[
            const SizedBox(height: LarSpacing.lg),
            Text(
              'CONTA BANCÁRIA',
              style: text.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: LarSpacing.xs),
            DropdownButtonFormField<String?>(
              initialValue: _selectedAccountUuid,
              decoration: const InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todas as contas'),
                ),
                ...widget.availableAccounts.map(
                  (a) => DropdownMenuItem<String?>(
                    value: a.uuid,
                    child: Text(a.name),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedAccountUuid = val),
            ),
          ],
          if (widget.availableCategories.isNotEmpty) ...[
            const SizedBox(height: LarSpacing.lg),
            Text(
              'CATEGORIA',
              style: text.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: LarSpacing.xs),
            DropdownButtonFormField<String?>(
              initialValue: _selectedCategoryUuid,
              decoration: const InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todas as categorias'),
                ),
                ...widget.availableCategories.map(
                  (c) => DropdownMenuItem<String?>(
                    value: c.uuid,
                    child: Text(c.name),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedCategoryUuid = val),
            ),
          ],
          const SizedBox(height: LarSpacing.xxl),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _selectedType = null;
                      _selectedAccountUuid = null;
                      _selectedCategoryUuid = null;
                    });
                  },
                  child: const Text('Limpar'),
                ),
              ),
              const SizedBox(width: LarSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final updated = widget.initialFilters.copyWith(
                      type: _selectedType,
                      accountUuid: _selectedAccountUuid,
                      categoryUuid: _selectedCategoryUuid,
                      clearType: _selectedType == null,
                      clearAccount: _selectedAccountUuid == null,
                      clearCategory: _selectedCategoryUuid == null,
                    );
                    widget.onApply(updated);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
