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

final class SyncOperationPayload {
  const SyncOperationPayload({
    required this.operationId,
    required this.entity,
    required this.action,
    required this.entityUuid,
    required this.expectedVersion,
    required this.data,
  });

  final String operationId;
  final String entity;
  final String action;
  final String entityUuid;
  final int expectedVersion;
  final JsonObject data;

  JsonObject toJson() => <String, Object?>{
    'operation_id': operationId,
    'entity': entity,
    'action': action,
    'entity_uuid': entityUuid,
    'expected_version': expectedVersion,
    'data': data,
  };
}

final class SyncOperationResult {
  const SyncOperationResult({
    required this.status,
    this.code,
    this.entityType,
    this.entityUuid,
    this.version,
  });

  final String status;
  final String? code;
  final String? entityType;
  final String? entityUuid;
  final int? version;

  bool get isSuccessful => status == 'applied' || status == 'duplicate';
}
