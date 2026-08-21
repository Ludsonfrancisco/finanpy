import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/money/minor_units.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../../accounts/domain/accounts_models.dart';
import '../../application/cards_controller.dart';
import '../../domain/cards_models.dart';

final class PayInvoiceSheet extends StatefulWidget {
  const PayInvoiceSheet({
    required this.controller,
    required this.invoice,
    required this.accounts,
    super.key,
  });

  final CardsController controller;
  final CardInvoiceModel invoice;
  final List<AccountItem> accounts;

  static Future<void> show(
    BuildContext context, {
    required CardsController controller,
    required CardInvoiceModel invoice,
    required List<AccountItem> accounts,
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
            child: PayInvoiceSheet(
              controller: controller,
              invoice: invoice,
              accounts: accounts,
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
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: PayInvoiceSheet(
          controller: controller,
          invoice: invoice,
          accounts: accounts,
        ),
      ),
    );
  }

  @override
  State<PayInvoiceSheet> createState() => _PayInvoiceSheetState();
}

final class _PayInvoiceSheetState extends State<PayInvoiceSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountCtrl;
  AccountItem? _selectedAccount;
  DateTime _paymentDate = DateTime.now();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: minorUnitsToPtBrInput(widget.invoice.totalAmountMinor),
    );
    _selectedAccount = widget.accounts.firstOrNull;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  int? get _parsedAmountMinor {
    try {
      return parsePtBrMinorUnits(_amountCtrl.text);
    } on FormatException {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedAccount == null) return;

    setState(() => _isSubmitting = true);
    try {
      final accountId = int.tryParse(_selectedAccount!.uuid) ?? 1;
      await widget.controller.payInvoice(
        invoiceId: widget.invoice.id,
        accountId: accountId,
        paidAmountMinor: _parsedAmountMinor!,
        paymentDate: _paymentDate,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fatura paga com sucesso!'),
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

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');

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
                  'Baixa de Fatura',
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
            const SizedBox(height: LarSpacing.md),

            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF101B18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LarColors.mineral.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.invoice.cardName} (${widget.invoice.month.toString().padLeft(2, '0')}/${widget.invoice.year})',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatBrlMinorUnits(widget.invoice.totalAmountMinor),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: LarColors.mineralOnDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vencimento: ${dateFmt.format(widget.invoice.dueDate)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LarSpacing.lg),

            // Account selector
            if (widget.accounts.isNotEmpty) ...[
              Text(
                'Conta de Débito',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: LarSpacing.xs),
              DropdownButtonFormField<AccountItem>(
                initialValue: _selectedAccount,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                items: widget.accounts.map((acc) {
                  return DropdownMenuItem(
                    value: acc,
                    child: Text(
                      '${acc.name} '
                      '(${formatBrlMinorUnits(acc.currentBalanceMinor)})',
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedAccount = val),
              ),
              const SizedBox(height: LarSpacing.md),
            ],

            // Amount and Date
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Valor Pago (R\$)',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: LarSpacing.xs),
                      TextFormField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (_parsedAmountMinor ?? 0) <= 0
                            ? 'Informe um valor válido'
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
                        'Data do Pagamento',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: LarSpacing.xs),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _paymentDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _paymentDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            dateFmt.format(_paymentDate),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                    : const Text(
                        'Confirmar Pagamento',
                        style: TextStyle(
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
