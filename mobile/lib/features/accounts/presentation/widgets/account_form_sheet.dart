import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../data/accounts_repository.dart';
import '../../domain/accounts_models.dart';
import '../../../transactions/domain/transactions_models.dart'
    show TransactionOwnerOption;

final class AccountFormSheet extends StatefulWidget {
  const AccountFormSheet({required this.repository, this.onSaved, super.key});

  final AccountsRepository repository;
  final VoidCallback? onSaved;

  static Future<void> show(
    BuildContext context, {
    required AccountsRepository repository,
    VoidCallback? onSaved,
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
              child: AccountFormSheet(repository: repository, onSaved: onSaved),
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
            child: AccountFormSheet(repository: repository, onSaved: onSaved),
          ),
        ),
      ),
    );
  }

  @override
  State<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _initialBalanceController;

  AccountType _selectedType = AccountType.checking;
  String? _selectedOwnerUuid;
  List<TransactionOwnerOption> _owners = [];

  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _initialBalanceController = TextEditingController(text: '0,00');
    _loadOwners();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _initialBalanceController.dispose();
    super.dispose();
  }

  Future<void> _loadOwners() async {
    try {
      final owners = await widget.repository.readAvailableOwners();
      if (!mounted) return;
      setState(() {
        _owners = owners;
        _selectedOwnerUuid = owners.isNotEmpty ? owners.first.uuid : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao carregar responsáveis.';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOwnerUuid == null) {
      setState(() => _errorMessage = 'Selecione o responsável pela conta.');
      return;
    }

    final rawBalance = double.tryParse(
      _initialBalanceController.text.replaceAll(',', '.'),
    );
    if (rawBalance == null) {
      setState(() => _errorMessage = 'Informe um saldo inicial válido.');
      return;
    }
    final initialBalanceMinor = (rawBalance * 100).round();

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.createAccount(
        name: _nameController.text.trim(),
        type: _selectedType,
        initialBalanceMinor: initialBalanceMinor,
        financialOwnerUuid: _selectedOwnerUuid!,
      );

      if (!mounted) return;
      widget.onSaved?.call();
      await Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao criar conta bancária.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

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
                  'Nova Conta Bancária',
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ],
            ),
            const SizedBox(height: LarSpacing.md),

            // Nome da Conta
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome da Conta / Banco*',
                hintText: 'Ex: Nubank, Itaú Corrente, Carteira',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Informe o nome da conta';
                }
                return null;
              },
            ),
            const SizedBox(height: LarSpacing.sm),

            // Tipo de Conta
            DropdownButtonFormField<AccountType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Tipo de Conta*',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              items: AccountType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedType = val);
              },
            ),
            const SizedBox(height: LarSpacing.sm),

            // Saldo Inicial
            TextFormField(
              controller: _initialBalanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: r'Saldo Inicial (R$)*',
                hintText: '0,00',
                prefixText: r'R$ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Informe o saldo inicial';
                }
                final parsed = double.tryParse(val.replaceAll(',', '.'));
                if (parsed == null) {
                  return 'Valor inválido';
                }
                return null;
              },
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
                  : const Text('Criar Conta'),
            ),
          ],
        ),
      ),
    );
  }
}
