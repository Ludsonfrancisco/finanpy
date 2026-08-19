import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../../categories/domain/categories_models.dart';
import '../../../transactions/domain/transactions_models.dart';
import '../../application/cards_controller.dart';
import '../../domain/cards_models.dart';

final class CardExpenseSheet extends StatefulWidget {
  const CardExpenseSheet({
    required this.controller,
    required this.cards,
    this.initialCard,
    this.categories = const [],
    super.key,
  });

  final CardsController controller;
  final List<CreditCardModel> cards;
  final CreditCardModel? initialCard;
  final List<CategoryItem> categories;

  static Future<void> show(
    BuildContext context, {
    required CardsController controller,
    required List<CreditCardModel> cards,
    CreditCardModel? initialCard,
    List<CategoryItem> categories = const [],
  }) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (isDesktop) {
      return showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF1A221E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: CardExpenseSheet(
              controller: controller,
              cards: cards,
              initialCard: initialCard,
              categories: categories,
            ),
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
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: CardExpenseSheet(
          controller: controller,
          cards: cards,
          initialCard: initialCard,
          categories: categories,
        ),
      ),
    );
  }

  @override
  State<CardExpenseSheet> createState() => _CardExpenseSheetState();
}

final class _CardExpenseSheetState extends State<CardExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  late CreditCardModel? _selectedCard;
  String? _selectedCategoryUuid;
  DateTime _purchaseDate = DateTime.now();
  int _installments = 1;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedCard = widget.initialCard ?? widget.cards.firstOrNull;
    final expenseCats = widget.categories.where((c) => c.type == TransactionType.expense).toList();
    _selectedCategoryUuid = expenseCats.firstOrNull?.uuid;
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _parsedAmount {
    final text = _amountCtrl.text.replaceAll('R\$', '').replaceAll('.', '').replaceAll(',', '.').trim();
    return double.tryParse(text) ?? 0.0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedCard == null) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.controller.createExpense(
        cardId: _selectedCard!.id,
        description: _descriptionCtrl.text.trim(),
        amount: _parsedAmount,
        date: _purchaseDate,
        categoryId: 1,
        installmentsCount: _installments,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compra lançada com sucesso no cartão!'),
            backgroundColor: LarColors.mineral,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: LarColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFmt = DateFormat('dd/MM/yyyy');
    final expenseCategories = widget.categories.where((c) => c.type == TransactionType.expense).toList();

    final installmentValue = _installments > 0 && _parsedAmount > 0 ? _parsedAmount / _installments : 0.0;

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
                  'Lançar Compra no Cartão',
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

            // Card selector
            if (widget.cards.isNotEmpty) ...[
              Text('Cartão de Crédito', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: LarSpacing.xs),
              DropdownButtonFormField<CreditCardModel>(
                initialValue: _selectedCard,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                items: widget.cards.map((c) {
                  return DropdownMenuItem(
                    value: c,
                    child: Text('${c.name} (${c.brandDisplay})'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedCard = val),
              ),
              const SizedBox(height: LarSpacing.md),
            ],

            // Description
            Text('Descrição da Compra', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: LarSpacing.xs),
            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(
                hintText: 'Ex: Supermercado, Passagens',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a descrição' : null,
            ),
            const SizedBox(height: LarSpacing.md),

            // Amount and Date
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor Total (R\$)', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: LarSpacing.xs),
                      TextFormField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          hintText: '0,00',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) => _parsedAmount <= 0 ? 'Informe um valor maior que 0' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: LarSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Data da Compra', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: LarSpacing.xs),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _purchaseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) setState(() => _purchaseDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                          child: Text(dateFmt.format(_purchaseDate), style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: LarSpacing.md),

            // Category & Installments
            Row(
              children: [
                if (expenseCategories.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Categoria', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: LarSpacing.xs),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategoryUuid,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          items: expenseCategories.map((cat) {
                            return DropdownMenuItem<String>(value: cat.uuid, child: Text(cat.name));
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedCategoryUuid = val),
                        ),
                      ],
                    ),
                  ),
                if (expenseCategories.isNotEmpty) const SizedBox(width: LarSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Parcelas', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: LarSpacing.xs),
                      DropdownButtonFormField<int>(
                        initialValue: _installments,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        items: List.generate(24, (i) => i + 1).map((n) {
                          return DropdownMenuItem(
                            value: n,
                            child: Text(n == 1 ? '1x (À vista)' : '${n}x'),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _installments = val ?? 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_installments > 1 && _parsedAmount > 0) ...[
              const SizedBox(height: LarSpacing.md),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF101B18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LarColors.champagne.withAlpha(50)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Plano de Parcelamento:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    Text(
                      '${_installments}x de ${currencyFmt.format(installmentValue)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: LarColors.champagne),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: LarSpacing.xl),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: LarColors.champagne,
                  foregroundColor: const Color(0xFF0F1714),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSubmitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Lançar na Fatura', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
