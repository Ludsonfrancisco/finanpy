import '../../home/domain/home_snapshot.dart';

enum AccountType {
  checking,
  savings,
  cash,
  credit,
  investment,
  other;

  static AccountType fromString(String value) => switch (value) {
    'checking' => checking,
    'savings' => savings,
    'cash' => cash,
    'credit' => credit,
    'investment' => investment,
    _ => other,
  };

  String get label => switch (this) {
    checking => 'Conta Corrente',
    savings => 'Poupança / Reserva',
    cash => 'Dinheiro',
    credit => 'Cartão de Crédito',
    investment => 'Investimento',
    other => 'Outros',
  };
}

final class AccountItem {
  const AccountItem({
    required this.uuid,
    required this.name,
    required this.type,
    required this.initialBalanceMinor,
    required this.currentBalanceMinor,
    required this.currency,
    required this.ownerName,
    required this.ownerType,
    required this.updatedAt,
  });

  final String uuid;
  final String name;
  final AccountType type;
  final int initialBalanceMinor;
  final int currentBalanceMinor;
  final String currency;
  final String ownerName;
  final String ownerType;
  final DateTime updatedAt;
}

final class AccountsSnapshot {
  const AccountsSnapshot({
    required this.scope,
    required this.accounts,
    required this.totalBalanceMinor,
    required this.lastSyncedAt,
    required this.hasAccountData,
  });

  final OwnerScope scope;
  final List<AccountItem> accounts;
  final int totalBalanceMinor;
  final DateTime? lastSyncedAt;
  final bool hasAccountData;
}

final class AccountsState {
  const AccountsState({
    required this.snapshot,
    required this.selectedScopeIndex,
    required this.ownerScopes,
    required this.isLoading,
    this.error,
  });

  const AccountsState.initial()
    : snapshot = null,
      selectedScopeIndex = 0,
      ownerScopes = null,
      isLoading = true,
      error = null;

  final AccountsSnapshot? snapshot;
  final int selectedScopeIndex;
  final HomeOwnerScopes? ownerScopes;
  final bool isLoading;
  final Object? error;

  AccountsState copyWith({
    AccountsSnapshot? snapshot,
    int? selectedScopeIndex,
    HomeOwnerScopes? ownerScopes,
    bool? isLoading,
    Object? error,
  }) => AccountsState(
    snapshot: snapshot ?? this.snapshot,
    selectedScopeIndex: selectedScopeIndex ?? this.selectedScopeIndex,
    ownerScopes: ownerScopes ?? this.ownerScopes,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}
