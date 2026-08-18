import '../network/session_transport.dart';
import 'sync_models.dart';

abstract interface class SyncApi {
  Future<BootstrapPayload> fetchBootstrap();
  Future<SyncPage> fetchChanges(String cursor);
  Future<List<SyncOperationResult>> pushOperations(
    List<SyncOperationPayload> operations,
  );
}

final class DjangoSyncApi implements SyncApi {
  const DjangoSyncApi(this._transport);

  static const pageSize = 100;

  final SessionTransport _transport;

  @override
  Future<BootstrapPayload> fetchBootstrap() async {
    return parseBootstrapPayload(await _transport.getObject('/bootstrap/'));
  }

  @override
  Future<SyncPage> fetchChanges(String cursor) async {
    final encodedCursor = Uri.encodeQueryComponent(cursor);
    final body = await _transport.getObject(
      '/sync/changes/?cursor=$encodedCursor&limit=$pageSize',
    );
    return parseSyncPage(body);
  }

  @override
  Future<List<SyncOperationResult>> pushOperations(
    List<SyncOperationPayload> operations,
  ) async {
    if (operations.isEmpty) return const [];
    final payload = <String, Object?>{
      'operations': operations.map((op) => op.toJson()).toList(growable: false),
    };
    final body = await _transport.postObject('/sync/push/', data: payload);
    return parseSyncPushResponse(body);
  }
}

List<SyncOperationResult> parseSyncPushResponse(JsonObject json) {
  final results = _requiredObjectList(json, 'results');
  return results
      .map(
        (res) => SyncOperationResult(
          status: _requiredString(res, 'status'),
          code: res['code'] as String?,
          entityType: res['entity_type'] as String?,
          entityUuid: res['entity_uuid'] as String?,
          version: res['version'] as int?,
        ),
      )
      .toList(growable: false);
}

BootstrapPayload parseBootstrapPayload(Map<String, Object?> json) {
  final summary = _requiredObject(json, 'summary');
  _requiredString(summary, 'total_balance');
  _requiredString(summary, 'monthly_income');
  _requiredString(summary, 'monthly_expenses');
  return BootstrapPayload(
    household: _requiredObject(json, 'household'),
    owners: _requiredObjectList(json, 'owners'),
    accounts: _requiredObjectList(json, 'accounts'),
    categories: _requiredObjectList(json, 'categories'),
    transactions: _requiredObjectList(json, 'transactions'),
    cursor: _requiredString(json, 'cursor'),
  );
}

SyncPage parseSyncPage(Map<String, Object?> json) {
  final changes = _requiredObjectList(json, 'changes')
      .map(
        (change) => SyncChangePayload(
          entityType: _requiredString(change, 'entity_type'),
          entityUuid: _requiredString(change, 'entity_uuid'),
          entityVersion: _requiredPositiveInt(change, 'entity_version'),
          operation: _requiredString(change, 'operation'),
          payload: _requiredObject(change, 'payload'),
        ),
      )
      .toList(growable: false);
  if (changes.length > DjangoSyncApi.pageSize) {
    throw const FormatException('A sync page cannot contain over 100 changes.');
  }
  return SyncPage(changes: changes, cursor: _requiredString(json, 'cursor'));
}

JsonObject _requiredObject(JsonObject json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('$key must be an object.');
  }
  return value.cast<String, Object?>();
}

List<JsonObject> _requiredObjectList(JsonObject json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('$key must be an array.');
  }
  return value
      .map((item) {
        if (item is! Map) {
          throw FormatException('$key must contain only objects.');
        }
        return item.cast<String, Object?>();
      })
      .toList(growable: false);
}

String _requiredString(JsonObject json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

int _requiredPositiveInt(JsonObject json, String key) {
  final value = json[key];
  if (value is! int || value < 1) {
    throw FormatException('$key must be a positive integer.');
  }
  return value;
}
