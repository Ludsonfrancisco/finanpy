enum OwnerScopeKind { household, selfOwner, spouse }

final class OwnerScope {
  const OwnerScope.household()
    : kind = OwnerScopeKind.household,
      ownerUuid = null;

  const OwnerScope.self(String uuid)
    : kind = OwnerScopeKind.selfOwner,
      ownerUuid = uuid;

  const OwnerScope.spouse(String uuid)
    : kind = OwnerScopeKind.spouse,
      ownerUuid = uuid;

  final OwnerScopeKind kind;
  final String? ownerUuid;
}

final class HomeOwnerScopes {
  const HomeOwnerScopes({required this.selfScope, required this.spouseScope});

  final OwnerScope selfScope;
  final OwnerScope spouseScope;
}

final class HomeSnapshot {
  const HomeSnapshot({
    required this.scope,
    required this.balanceMinor,
    required this.monthExpenseMinor,
    required this.upcomingCommitmentMinor,
    required this.recentTransactions,
    required this.lastSyncedAt,
    required this.hasAccountData,
  });

  final OwnerScope scope;
  final int balanceMinor;
  final int monthExpenseMinor;
  final int upcomingCommitmentMinor;
  final List<HomeTransaction> recentTransactions;
  final DateTime? lastSyncedAt;

  /// False means the balance source is absent, so the presentation must not
  /// turn the aggregate's SQL fallback into a presumed financial zero.
  final bool hasAccountData;
}

enum HomeTransactionType { income, expense }

final class HomeTransaction {
  const HomeTransaction({
    required this.uuid,
    required this.description,
    required this.categoryName,
    required this.ownerName,
    required this.date,
    required this.type,
    required this.signedAmountMinor,
  });

  final String uuid;
  final String description;
  final String categoryName;
  final String ownerName;
  final DateTime date;
  final HomeTransactionType type;
  final int signedAmountMinor;
}
