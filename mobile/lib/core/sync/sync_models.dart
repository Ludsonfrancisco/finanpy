typedef JsonObject = Map<String, Object?>;

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

final class BootstrapPayload {
  const BootstrapPayload({
    required this.household,
    required this.owners,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.cursor,
  });

  final JsonObject household;
  final List<JsonObject> owners;
  final List<JsonObject> accounts;
  final List<JsonObject> categories;
  final List<JsonObject> transactions;
  final String cursor;
}

final class SyncChangePayload {
  const SyncChangePayload({
    required this.entityType,
    required this.entityUuid,
    required this.entityVersion,
    required this.operation,
    required this.payload,
  });

  final String entityType;
  final String entityUuid;
  final int entityVersion;
  final String operation;
  final JsonObject payload;
}

final class SyncPage {
  const SyncPage({required this.changes, required this.cursor});

  final List<SyncChangePayload> changes;
  final String cursor;
}

final class SyncMetadata {
  const SyncMetadata({
    required this.cursor,
    required this.householdUuid,
    required this.sessionDeviceUuid,
    required this.sessionGeneration,
    required this.sessionIdentity,
    required this.lastSuccessAt,
  });

  final String cursor;
  final String householdUuid;
  final String sessionDeviceUuid;
  final int sessionGeneration;
  final String sessionIdentity;
  final DateTime lastSuccessAt;
}

final class HomeSnapshot {
  const HomeSnapshot({
    required this.scope,
    required this.balanceMinor,
    required this.monthExpenseMinor,
    required this.upcomingCommitmentMinor,
    required this.recentTransactions,
    required this.lastSyncedAt,
  });

  final OwnerScope scope;
  final int balanceMinor;
  final int monthExpenseMinor;
  final int upcomingCommitmentMinor;
  final List<HomeTransaction> recentTransactions;
  final DateTime? lastSyncedAt;
}

final class HomeTransaction {
  const HomeTransaction({
    required this.uuid,
    required this.description,
    required this.categoryName,
    required this.ownerName,
    required this.date,
    required this.signedAmountMinor,
  });

  final String uuid;
  final String description;
  final String categoryName;
  final String ownerName;
  final DateTime date;
  final int signedAmountMinor;
}

enum SyncResult { current, updated, offlineWithCache, noCacheOffline, failed }
