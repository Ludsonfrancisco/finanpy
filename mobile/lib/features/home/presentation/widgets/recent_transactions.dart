import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/home_snapshot.dart';
import 'home_financial_surface.dart';

final class RecentTransactions extends StatelessWidget {
  const RecentTransactions({
    required this.transactions,
    required this.hidden,
    super.key,
  });

  final List<HomeTransaction> transactions;
  final bool hidden;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: HomeFinancialSurface(
      key: const Key('home-recent-card'),
      padding: const EdgeInsets.all(LarSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Movimentações recentes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: LarSpacing.xs),
          Text(
            'Últimas atividades do responsável selecionado',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: LarSpacing.md),
          if (transactions.isEmpty)
            const Text('Nenhuma movimentação neste período')
          else
            for (var index = 0; index < transactions.length; index++) ...[
              _TransactionRow(transaction: transactions[index], hidden: hidden),
              if (index < transactions.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    ),
  );
}

final class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.hidden});

  final HomeTransaction transaction;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final income = transaction.type == HomeTransactionType.income;
    final typeLabel = income ? 'Receita' : 'Despesa';
    final amountColor = income
        ? Theme.of(context).brightness == Brightness.dark
              ? LarColors.mineralOnDark
              : LarColors.mineral
        : Theme.of(context).brightness == Brightness.dark
        ? LarColors.darkDanger
        : LarColors.lightDanger;
    final date = DateFormat('dd MMM', 'pt_BR').format(transaction.date);
    final details =
        '${transaction.categoryName} · ${transaction.ownerName} · $date';
    final amountSemantics = hidden
        ? 'Valor oculto'
        : formatBrlMinor(transaction.signedAmountMinor, showPositiveSign: true);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final amount = FinancialAmount(
      minorUnits: transaction.signedAmountMinor,
      hidden: hidden,
      showPositiveSign: true,
      wrapAtLargeText: false,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: amountColor,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        fontWeight: FontWeight.w600,
      ),
    );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          transaction.description,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          '$typeLabel · $details',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    return Semantics(
      container: true,
      label:
          '${transaction.description}. $typeLabel. $details. $amountSemantics.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: LarSpacing.md),
          child: scale >= 1.5
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    description,
                    const SizedBox(height: LarSpacing.sm),
                    amount,
                  ],
                )
              : Row(
                  children: <Widget>[
                    Expanded(child: description),
                    const SizedBox(width: LarSpacing.md),
                    amount,
                  ],
                ),
        ),
      ),
    );
  }
}
