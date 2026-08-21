import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/money/minor_units.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../../accounts/domain/accounts_models.dart';
import '../../domain/bills_models.dart';

final class PayBillSheet extends StatefulWidget {
  const PayBillSheet({
    required this.instance,
    required this.accounts,
    required this.onPay,
    super.key,
  });

  final BillInstanceModel instance;
  final List<AccountItem> accounts;
  final Future<void> Function({
    required int accountId,
    required int paidAmountMinor,
    required DateTime paidDate,
  })
  onPay;

  static Future<void> show(
    BuildContext context, {
    required BillInstanceModel instance,
    required List<AccountItem> accounts,
    required Future<void> Function({
      required int accountId,
      required int paidAmountMinor,
      required DateTime paidDate,
    })
    onPay,
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
              child: PayBillSheet(
                instance: instance,
                accounts: accounts,
                onPay: onPay,
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
            child: PayBillSheet(
              instance: instance,
              accounts: accounts,
              onPay: onPay,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<PayBillSheet> createState() => _PayBillSheetState();
}

final class _PayBillSheetState extends State<PayBillSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late DateTime _selectedDate;
  AccountItem? _selectedAccount;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: minorUnitsToPtBrInput(widget.instance.amountMinor),
    );
    _selectedDate = DateTime.now();

    if (widget.accounts.isNotEmpty) {
      _selectedAccount = widget.accounts.first;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma conta bancária')),
      );
      return;
    }

    final paidAmountMinor = _parsedAmountMinor()!;

    setState(() => _submitting = true);
    try {
      final accountId = 1;
      await widget.onPay(
        accountId: accountId,
        paidAmountMinor: paidAmountMinor,
        paidDate: _selectedDate,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Conta "${widget.instance.name}" baixada com sucesso!',
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
            content: Text('Erro ao baixar pagamento: $e'),
            backgroundColor: LarColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');

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
                'Registrar Pagamento',
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
            'Dar baixa em "${widget.instance.name}". A despesa será lançada no extrato da conta.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: LarSpacing.lg),

          // Account selector
          if (widget.accounts.isNotEmpty) ...[
            Text(
              'Conta Débito',
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
                    '${acc.name} (${formatBrlMinorUnits(acc.currentBalanceMinor)})',
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedAccount = val),
            ),
            const SizedBox(height: LarSpacing.md),
          ],

          // Amount field
          Text(
            'Valor Pago (R\$)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: LarSpacing.xs),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Informe o valor';
              return _parsedAmountMinor() == null
                  ? 'Informe um valor válido'
                  : null;
            },
          ),
          const SizedBox(height: LarSpacing.md),

          // Date field
          Text(
            'Data do Pagamento',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: LarSpacing.xs),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              alignment: Alignment.centerLeft,
            ),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(dateFmt.format(_selectedDate)),
          ),
          const SizedBox(height: LarSpacing.xl),

          // Action buttons
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
                    horizontal: 20,
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
                    : const Text(
                        'Confirmar Pagamento',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int? _parsedAmountMinor() {
    try {
      final value = parsePtBrMinorUnits(_amountController.text);
      return value > 0 ? value : null;
    } on FormatException {
      return null;
    }
  }
}
