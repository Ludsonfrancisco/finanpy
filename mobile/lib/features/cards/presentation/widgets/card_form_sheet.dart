import 'package:flutter/material.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../application/cards_controller.dart';
import '../../domain/cards_models.dart';

final class CardFormSheet extends StatefulWidget {
  const CardFormSheet({required this.controller, this.card, super.key});

  final CardsController controller;
  final CreditCardModel? card;

  static Future<void> show(
    BuildContext context, {
    required CardsController controller,
    CreditCardModel? card,
  }) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (isDesktop) {
      return showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF1A221E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: CardFormSheet(controller: controller, card: card),
          ),
        ),
      );
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A221E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: CardFormSheet(controller: controller, card: card),
      ),
    );
  }

  @override
  State<CardFormSheet> createState() => _CardFormSheetState();
}

final class _CardFormSheetState extends State<CardFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _limitCtrl;
  late TextEditingController _lastDigitsCtrl;

  late int _closingDay;
  late int _dueDay;
  late String _brand;
  late String _color;
  late String _ownerType;
  bool _isSubmitting = false;

  final List<String> _colorPresets = [
    '#2F756A', // Mineral Lar
    '#820AD1', // Nubank
    '#111111', // Black
    '#1E3A8A', // Blue
    '#B8534F', // Terracotta
    '#D97706', // Gold / Amber
    '#047857', // Emerald
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.card;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _limitCtrl = TextEditingController(
      text: c != null ? c.limit.toStringAsFixed(2) : '',
    );
    _lastDigitsCtrl = TextEditingController(text: c?.lastDigits ?? '');
    _closingDay = c?.closingDay ?? 10;
    _dueDay = c?.dueDay ?? 17;
    _brand = c?.brand ?? 'visa';
    _color = c?.color ?? '#2F756A';
    _ownerType = c?.financialOwnerType ?? 'shared';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _limitCtrl.dispose();
    _lastDigitsCtrl.dispose();
    super.dispose();
  }

  double get _parsedLimit {
    final text = _limitCtrl.text
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .trim();
    return double.tryParse(text) ?? 0.0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      if (widget.card != null) {
        await widget.controller.updateCard(
          widget.card!.id,
          name: _nameCtrl.text.trim(),
          limit: _parsedLimit,
          closingDay: _closingDay,
          dueDay: _dueDay,
          color: _color,
          brand: _brand,
          lastDigits: _lastDigitsCtrl.text.trim(),
          financialOwnerType: _ownerType,
        );
      } else {
        await widget.controller.createCard(
          name: _nameCtrl.text.trim(),
          limit: _parsedLimit,
          closingDay: _closingDay,
          dueDay: _dueDay,
          color: _color,
          brand: _brand,
          lastDigits: _lastDigitsCtrl.text.trim(),
          financialOwnerType: _ownerType,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.card != null
                  ? 'Cartão atualizado com sucesso!'
                  : 'Cartão criado com sucesso!',
            ),
            backgroundColor: LarColors.mineral,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: LarColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Color _parseColor(String hex) {
    try {
      final buffer = StringBuffer();
      if (hex.length == 6 || hex.length == 7) buffer.write('ff');
      buffer.write(hex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return LarColors.mineral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.card != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit ? 'Editar Cartão' : 'Novo Cartão de Crédito',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: LarSpacing.lg),

            // Card name
            Text(
              'Nome do Cartão',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: LarSpacing.xs),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: 'Ex: Nubank Ultravioleta, XP Infinite',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Informe o nome do cartão'
                  : null,
            ),
            const SizedBox(height: LarSpacing.md),

            // Limit & Brand
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Limite Total (R\$)',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: LarSpacing.xs),
                      TextFormField(
                        controller: _limitCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          hintText: '5000,00',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => _parsedLimit <= 0
                            ? 'Informe um limite válido'
                            : null,
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
                        'Bandeira',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: LarSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue: _brand,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'visa', child: Text('Visa')),
                          DropdownMenuItem(
                            value: 'mastercard',
                            child: Text('Mastercard'),
                          ),
                          DropdownMenuItem(value: 'elo', child: Text('Elo')),
                          DropdownMenuItem(value: 'amex', child: Text('Amex')),
                          DropdownMenuItem(
                            value: 'hipercard',
                            child: Text('Hipercard'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Outro'),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _brand = val ?? 'visa'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: LarSpacing.md),

            // Closing Day & Due Day
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dia Fechamento',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: LarSpacing.xs),
                      DropdownButtonFormField<int>(
                        initialValue: _closingDay,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        items: List.generate(31, (i) => i + 1).map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text('Dia $d'),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setState(() => _closingDay = val ?? 10),
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
                        'Dia Vencimento',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: LarSpacing.xs),
                      DropdownButtonFormField<int>(
                        initialValue: _dueDay,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        items: List.generate(31, (i) => i + 1).map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text('Dia $d'),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _dueDay = val ?? 17),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: LarSpacing.md),

            // Owner and Digits
            Row(
              children: [
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
                        onChanged: (val) =>
                            setState(() => _ownerType = val ?? 'shared'),
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
                        'Últimos 4 Dígitos',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: LarSpacing.xs),
                      TextFormField(
                        controller: _lastDigitsCtrl,
                        maxLength: 4,
                        decoration: const InputDecoration(
                          hintText: '1234',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: LarSpacing.md),

            // Color Palette Selector
            Text(
              'Cor do Cartão',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: LarSpacing.xs),
            Wrap(
              spacing: 8,
              children: _colorPresets.map((hex) {
                final isSelected = _color.toLowerCase() == hex.toLowerCase();
                return GestureDetector(
                  onTap: () => setState(() => _color = hex),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _parseColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: _parseColor(hex).withAlpha(150),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: LarSpacing.xl),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: LarColors.mineral,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isEdit ? 'Salvar Alterações' : 'Cadastrar Cartão',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
