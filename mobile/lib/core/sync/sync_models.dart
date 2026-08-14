export '../../features/home/domain/home_snapshot.dart';

typedef JsonObject = Map<String, Object?>;

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

enum SyncResult { current, updated, offlineWithCache, noCacheOffline, failed }
