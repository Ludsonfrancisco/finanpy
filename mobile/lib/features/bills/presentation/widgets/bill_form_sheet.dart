import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/bills_models.dart';

final class BillFormSheet extends StatefulWidget {
  const BillFormSheet({this.initialBill, required this.onSave, super.key});

  final RecurringBillModel? initialBill;
  final Future<void> Function({
    required String name,
    required double amount,
    required int dueDay,
    required String type,
    String? financialOwnerType,
    bool isActive,
    String notes,
  })
  onSave;

  static Future<void> show(
    BuildContext context, {
    RecurringBillModel? initialBill,
    required Future<void> Function({
      required String name,
      required double amount,
      required int dueDay,
      required String type,
      String? financialOwnerType,
      bool isActive,
      String notes,
    })
    onSave,
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(LarSpacing.xl),
              child: BillFormSheet(initialBill: initialBill, onSave: onSave),
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
            child: BillFormSheet(initialBill: initialBill, onSave: onSave),
          ),
        ),
      ),
    );
  }

  @override
  State<BillFormSheet> createState() => _BillFormSheetState();
}

final class _BillFormSheetState extends State<BillFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _amountController;
  late TextEditingController _dueDayController;
  late TextEditingController _notesController;

  String _type = 'expense';
  String _ownerType = 'shared';
  bool _isActive = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final bill = widget.initialBill;
    _nameController = TextEditingController(text: bill?.name ?? '');
    _amountController = TextEditingController(
      text: bill != null ? bill.amount.toStringAsFixed(2) : '',
    );
    _dueDayController = TextEditingController(
      text: bill != null ? bill.dueDay.toString() : '10',
    );
    _notesController = TextEditingController(text: bill?.notes ?? '');
    _type = bill?.type ?? 'expense';
    _ownerType = bill?.financialOwnerType ?? 'shared';
    _isActive = bill?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dueDayController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0.0;
    final dueDay = int.tryParse(_dueDayController.text) ?? 10;

    setState(() => _submitting = true);
    try {
      await widget.onSave(
        name: name,
        amount: amount,
        dueDay: dueDay,
        type: _type,
        financialOwnerType: _ownerType,
        isActive: _isActive,
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.initialBill != null
                  ? 'Conta fixa atualizada com sucesso!'
                  : 'Conta fixa "$name" cadastrada com sucesso!',
            ),
            backgroundColor: LarColors.mineral,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: LarColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialBill != null;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isEditing ? 'Editar Conta Fixa' : 'Nova Conta Fixa',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: LarSpacing.xs),
          Text(
            isEditing
                ? 'Atualize as regras deste compromisso fixo.'
                : 'Cadastre despesas e receitas regulares para acompanhar os vencimentos automáticos.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: LarSpacing.lg),

          // Name
          Text(
            'Nome do Compromisso*',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: LarSpacing.xs),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Ex.: Aluguel, Luz, Internet Claro...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Informe o nome' : null,
          ),
          const SizedBox(height: LarSpacing.md),

          // Amount and Due Day in a row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Valor Estimado (R\$)*',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: LarSpacing.xs),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0,00',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Informe o valor';
                        }
                        if (double.tryParse(v.replaceAll(',', '.')) == null) {
                          return 'Inválido';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LarSpacing.md),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dia Venc.*',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: LarSpacing.xs),
                    TextFormField(
                      controller: _dueDayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '1 a 31',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      validator: (v) {
                        final val = int.tryParse(v ?? '');
                        if (val == null || val < 1 || val > 31) return '1 a 31';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LarSpacing.md),

          // Type and Owner
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tipo',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: LarSpacing.xs),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'expense',
                          child: Text('Despesa'),
                        ),
                        DropdownMenuItem(
                          value: 'income',
                          child: Text('Receita'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'expense'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LarSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Titular',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: LarSpacing.xs),
                    DropdownButtonFormField<String>(
                      initialValue: _ownerType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'shared',
                          child: Text('Conjunto (Lar)'),
                        ),
                        DropdownMenuItem(value: 'self', child: Text('Eu')),
                        DropdownMenuItem(
                          value: 'spouse',
                          child: Text('Esposa'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _ownerType = v ?? 'shared'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LarSpacing.md),

          // Notes
          Text('Observações', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: LarSpacing.xs),
          TextFormField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Código de barras, chave Pix ou anotações...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: LarSpacing.sm),

          // Active Switch
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Conta Fixa Ativa',
              style: TextStyle(fontSize: 14),
            ),
            subtitle: const Text(
              'Gera cobrança automaticamente nos próximos meses',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: LarSpacing.lg),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: LarSpacing.sm),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LarColors.mineral,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isEditing
                            ? 'Salvar Alterações'
                            : 'Cadastrar Conta Fixa',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
