import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../data/transactions_repository.dart';
import '../../domain/transactions_models.dart';

final class TransactionFormSheet extends StatefulWidget {
  const TransactionFormSheet({
    required this.repository,
    this.initialItem,
    this.onSaved,
    this.onDeleted,
    super.key,
  });

  final TransactionsRepository repository;
  final TransactionItem? initialItem;
  final VoidCallback? onSaved;
  final VoidCallback? onDeleted;

  static Future<void> show(
    BuildContext context, {
    required TransactionsRepository repository,
    TransactionItem? initialItem,
    VoidCallback? onSaved,
    VoidCallback? onDeleted,
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
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(LarSpacing.xl),
              child: TransactionFormSheet(
                repository: repository,
                initialItem: initialItem,
                onSaved: onSaved,
                onDeleted: onDeleted,
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
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(LarSpacing.xl),
            child: TransactionFormSheet(
              repository: repository,
              initialItem: initialItem,
              onSaved: onSaved,
              onDeleted: onDeleted,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late TransactionType _type;
  late TextEditingController _descriptionController;
  late TextEditingController _amountController;
  late DateTime _selectedDate;

  String? _selectedAccountUuid;
  String? _selectedCategoryUuid;
  String? _selectedOwnerUuid;

  List<TransactionFilterOption> _accounts = [];
  List<TransactionCategoryOption> _categories = [];
  List<TransactionOwnerOption> _owners = [];

  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _type = item?.type ?? TransactionType.expense;
    _descriptionController = TextEditingController(
      text: item?.description ?? '',
    );
    final initialAmountStr = item != null
        ? (item.amountMinor / 100).toStringAsFixed(2)
        : '';
    _amountController = TextEditingController(text: initialAmountStr);
    _selectedDate = item?.date ?? DateTime.now();

    _loadOptions();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final accounts = await widget.repository.readAvailableAccounts();
      final categories = await widget.repository.readAvailableCategories(_type);
      final owners = await widget.repository.readAvailableOwners();

      if (!mounted) return;

      setState(() {
        _accounts = accounts;
        _categories = categories;
        _owners = owners;

        final item = widget.initialItem;
        if (item != null) {
          _selectedAccountUuid = item.accountUuid;
          // Match category by name if available
          final matchingCat = categories
              .where((c) => c.name == item.categoryName)
              .firstOrNull;
          _selectedCategoryUuid =
              matchingCat?.uuid ??
              (categories.isNotEmpty ? categories.first.uuid : null);
          // Match owner by name or type
          final matchingOwner = owners
              .where(
                (o) => o.name == item.ownerName || o.type == item.ownerType,
              )
              .firstOrNull;
          _selectedOwnerUuid =
              matchingOwner?.uuid ??
              (owners.isNotEmpty ? owners.first.uuid : null);
        } else {
          _selectedAccountUuid = accounts.isNotEmpty
              ? accounts.first.uuid
              : null;
          _selectedCategoryUuid = categories.isNotEmpty
              ? categories.first.uuid
              : null;
          _selectedOwnerUuid = owners.isNotEmpty ? owners.first.uuid : null;
        }

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao carregar opções.';
        _loading = false;
      });
    }
  }

  Future<void> _onTypeChanged(TransactionType newType) async {
    if (_type == newType) return;
    setState(() {
      _type = newType;
      _selectedCategoryUuid = null;
    });
    final categories = await widget.repository.readAvailableCategories(newType);
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _selectedCategoryUuid = categories.isNotEmpty
          ? categories.first.uuid
          : null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountUuid == null ||
        _selectedCategoryUuid == null ||
        _selectedOwnerUuid == null) {
      setState(() => _errorMessage = 'Preencha todos os campos obrigatórios.');
      return;
    }

    final rawAmount = double.tryParse(
      _amountController.text.replaceAll(',', '.'),
    );
    if (rawAmount == null || rawAmount <= 0) {
      setState(() => _errorMessage = 'Informe um valor válido maior que zero.');
      return;
    }
    final amountMinor = (rawAmount * 100).round();

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      if (widget.initialItem != null) {
        await widget.repository.updateTransaction(
          uuid: widget.initialItem!.uuid,
          description: _descriptionController.text.trim(),
          amountMinor: amountMinor,
          date: _selectedDate,
          type: _type,
          accountUuid: _selectedAccountUuid!,
          categoryUuid: _selectedCategoryUuid!,
          financialOwnerUuid: _selectedOwnerUuid!,
        );
      } else {
        await widget.repository.createTransaction(
          description: _descriptionController.text.trim(),
          amountMinor: amountMinor,
          date: _selectedDate,
          type: _type,
          accountUuid: _selectedAccountUuid!,
          categoryUuid: _selectedCategoryUuid!,
          financialOwnerUuid: _selectedOwnerUuid!,
        );
      }

      if (!mounted) return;
      widget.onSaved?.call();
      await Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao salvar movimentação.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final item = widget.initialItem;
    if (item == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Movimentação'),
        content: Text('Deseja realmente excluir "${item.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LarColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _submitting = true);
      try {
        await widget.repository.deleteTransaction(item.uuid);
        if (!mounted) return;
        widget.onDeleted?.call();
        await Navigator.maybePop(context);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Erro ao excluir movimentação.';
        });
      } finally {
        if (mounted) {
          setState(() => _submitting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isEditing = widget.initialItem != null;

    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEditing ? 'Editar Movimentação' : 'Nova Movimentação',
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ],
            ),
            const SizedBox(height: LarSpacing.md),

            // Tipo: Despesa vs Receita
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Despesa'),
                  icon: Icon(Icons.arrow_downward, color: LarColors.danger),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Receita'),
                  icon: Icon(Icons.arrow_upward, color: LarColors.mineral),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (set) => _onTypeChanged(set.first),
            ),
            const SizedBox(height: LarSpacing.md),

            // Valor
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: r'Valor (R$)*',
                hintText: '0,00',
                prefixText: r'R$ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Informe o valor';
                final parsed = double.tryParse(val.replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) return 'Valor inválido';
                return null;
              },
            ),
            const SizedBox(height: LarSpacing.sm),

            // Descrição
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descrição*',
                hintText: 'Ex: Supermercado, Salário',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Informe a descrição';
                }
                return null;
              },
            ),
            const SizedBox(height: LarSpacing.sm),

            // Data
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data*',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
              ),
            ),
            const SizedBox(height: LarSpacing.sm),

            // Conta Bancária
            if (_accounts.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedAccountUuid,
                decoration: const InputDecoration(
                  labelText: 'Conta Bancária*',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                items: _accounts
                    .map(
                      (a) =>
                          DropdownMenuItem(value: a.uuid, child: Text(a.name)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedAccountUuid = val),
              ),
            const SizedBox(height: LarSpacing.sm),

            // Categoria
            if (_categories.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedCategoryUuid,
                decoration: const InputDecoration(
                  labelText: 'Categoria*',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                items: _categories
                    .map(
                      (c) =>
                          DropdownMenuItem(value: c.uuid, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategoryUuid = val),
              ),
            const SizedBox(height: LarSpacing.sm),

            // Responsável
            if (_owners.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedOwnerUuid,
                decoration: const InputDecoration(
                  labelText: 'Responsável*',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                items: _owners
                    .map(
                      (o) =>
                          DropdownMenuItem(value: o.uuid, child: Text(o.name)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedOwnerUuid = val),
              ),

            if (_errorMessage != null) ...[
              const SizedBox(height: LarSpacing.sm),
              Text(
                _errorMessage!,
                style: text.bodySmall?.copyWith(color: LarColors.danger),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: LarSpacing.lg),

            // Ações
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: LarSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isEditing ? 'Salvar Alterações' : 'Criar Lançamento'),
            ),

            if (isEditing) ...[
              const SizedBox(height: LarSpacing.sm),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline, color: LarColors.danger),
                label: const Text(
                  'Excluir Movimentação',
                  style: TextStyle(color: LarColors.danger),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: LarColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: LarSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
