import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/components/financial_amount.dart';
import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/accounts_models.dart';

final class AccountCard extends StatelessWidget {
  const AccountCard({required this.account, required this.hidden, super.key});

  final AccountItem account;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final isCredit = account.type == AccountType.credit;
    final icon = switch (account.type) {
      AccountType.checking => Icons.account_balance_outlined,
      AccountType.savings => Icons.savings_outlined,
      AccountType.credit => Icons.credit_card_outlined,
      AccountType.cash => Icons.payments_outlined,
      AccountType.investment => Icons.trending_up_outlined,
      AccountType.other => Icons.account_balance_wallet_outlined,
    };

    final dateFormatted = DateFormat(
      'dd/MM/yyyy HH:mm',
      'pt_BR',
    ).format(account.updatedAt.toLocal());

    return Card(
      key: Key('account-card-${account.uuid}'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      color: isDark ? LarColors.darkSurface : LarColors.lightSurface,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(LarSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? LarColors.champagneSelectedDark
                        : const Color(0xFFEADBBE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isDark
                        ? LarColors.champagne
                        : const Color(0xFF8C6D23),
                  ),
                ),
                const SizedBox(width: LarSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        account.name,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account.type.label,
                        style: text.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LarSpacing.sm,
                    vertical: LarSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    account.ownerName,
                    style: text.labelSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? LarColors.champagne
                          : const Color(0xFF8C6D23),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LarSpacing.lg),
            Text(
              isCredit ? 'Saldo / Fatura atual' : 'Saldo atual',
              style: text.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            FinancialAmount(
              minorUnits: account.currentBalanceMinor,
              hidden: hidden,
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: account.currentBalanceMinor < 0
                    ? LarColors.danger
                    : (isDark ? LarColors.mineralOnDark : LarColors.mineral),
              ),
            ),
            const SizedBox(height: LarSpacing.sm),
            Text(
              'Atualizado em $dateFormatted',
              style: text.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
