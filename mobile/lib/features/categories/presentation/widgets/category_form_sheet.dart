import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../../transactions/domain/transactions_models.dart';
import '../../data/categories_repository.dart';
import '../../domain/categories_models.dart';

const List<String> _categoryColorPresets = [
  '#2F756A', // Mineral
  '#C7A35A', // Champanhe
  '#B8534F', // Terracota / Danger
  '#B9782D', // Âmbar
  '#1E3A8A', // Azul Profundo
  '#0D9488', // Teal
  '#6D28D9', // Índigo
  '#4D7C0F', // Oliva
  '#374151', // Grafite
];

final class CategoryFormSheet extends StatefulWidget {
  const CategoryFormSheet({
    required this.repository,
    this.initialItem,
    this.onSaved,
    this.onDeleted,
    super.key,
  });

  final CategoriesRepository repository;
  final CategoryItem? initialItem;
  final VoidCallback? onSaved;
  final VoidCallback? onDeleted;

  static Future<void> show(
    BuildContext context, {
    required CategoriesRepository repository,
    CategoryItem? initialItem,
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
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(LarSpacing.xl),
              child: CategoryFormSheet(
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LarSpacing.xl),
          child: CategoryFormSheet(
            repository: repository,
            initialItem: initialItem,
            onSaved: onSaved,
            onDeleted: onDeleted,
          ),
        ),
      ),
    );
  }

  @override
  State<CategoryFormSheet> createState() => _CategoryFormSheetState();
}

final class _CategoryFormSheetState extends State<CategoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  late TransactionType _type;
  late String _selectedColor;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialItem;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _type = initial?.type ?? TransactionType.expense;
    _selectedColor = initial?.color ?? _categoryColorPresets.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Color _parseHex(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return LarColors.mineral;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final isEditing = widget.initialItem != null;

    try {
      if (isEditing) {
        await widget.repository.updateCategory(
          uuid: widget.initialItem!.uuid,
          name: name,
          type: _type,
          color: _selectedColor,
        );
      } else {
        await widget.repository.createCategory(
          name: name,
          type: _type,
          color: _selectedColor,
        );
      }

      if (!mounted) return;
      widget.onSaved?.call();
      await Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao salvar categoria.';
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
        title: const Text('Excluir Categoria'),
        content: Text(
          item.transactionCount > 0
              ? 'A categoria "${item.name}" possui ${item.transactionCount} movimentações vinculadas. Deseja realmente excluir?'
              : 'Deseja realmente excluir a categoria "${item.name}"?',
        ),
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
        await widget.repository.deleteCategory(item.uuid);
        if (!mounted) return;
        widget.onDeleted?.call();
        await Navigator.maybePop(context);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Erro ao excluir categoria.';
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
                  isEditing ? 'Editar Categoria' : 'Nova Categoria',
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
              onSelectionChanged: (set) => setState(() => _type = set.first),
            ),
            const SizedBox(height: LarSpacing.md),

            // Nome da Categoria
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome da Categoria*',
                hintText: 'Ex: Alimentação, Lazer, Salário',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Informe o nome da categoria';
                }
                return null;
              },
            ),
            const SizedBox(height: LarSpacing.lg),

            // Seletor de Cores
            Text(
              'Cor de Identificação',
              style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: LarSpacing.xs),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _categoryColorPresets.map((hex) {
                final isSelected =
                    _selectedColor.toUpperCase() == hex.toUpperCase();
                final color = _parseHex(hex);
                return Semantics(
                  button: true,
                  label: 'Selecionar cor $hex',
                  selected: isSelected,
                  child: InkWell(
                    onTap: () => setState(() => _selectedColor = hex),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: LarSpacing.md),
              Text(
                _errorMessage!,
                style: text.bodySmall?.copyWith(color: LarColors.danger),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: LarSpacing.xl),

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
                  : Text(isEditing ? 'Salvar Alterações' : 'Criar Categoria'),
            ),

            if (isEditing) ...[
              const SizedBox(height: LarSpacing.sm),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline, color: LarColors.danger),
                label: const Text(
                  'Excluir Categoria',
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
