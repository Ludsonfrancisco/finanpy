import 'package:drift/drift.dart';

import '../money/minor_units.dart';
import '../sync/sync_models.dart'
    show
        BootstrapPayload,
        JsonObject,
        SyncChangePayload,
        SyncMetadata,
        SyncPage;
import '../../features/home/data/home_repository.dart';
import '../../features/home/domain/home_snapshot.dart';
import 'app_database.dart';
import 'tables.dart';

abstract interface class LocalLedger {
  Stream<HomeSnapshot> watchHome(OwnerScope scope, DateTime now);
  Future<void> replaceBootstrap(
    BootstrapPayload payload,
    DateTime syncedAt,
    String sessionDeviceUuid, {
    int sessionGeneration = 0,
    String sessionIdentity = '',
    bool Function()? isSessionCurrent,
  });
  Future<void> applyDelta(
    SyncPage page,
    DateTime syncedAt, {
    int sessionGeneration = 0,
    String sessionIdentity = '',
    bool Function()? isSessionCurrent,
  });
  Future<void> applyDeltaChain(
    List<SyncPage> pages,
    DateTime syncedAt, {
    int sessionGeneration = 0,
    String sessionIdentity = '',
    bool Function()? isSessionCurrent,
  });
  Future<SyncMetadata?> readSyncMetadata();
  Future<List<OutboxMutation>> readPendingMutations({int limit = 100});
  Future<void> removeMutations(List<String> operationIds);
  Future<void> markMutationsFailed(List<String> operationIds);
}

final class DriftLocalLedger implements LocalLedger {
  DriftLocalLedger(
    AppDatabase database, {
    Future<void> Function()? beforeTransactionCommit,
  }) : _db = database,
       _homeRepository = DriftHomeRepository(database),
       _beforeTransactionCommit = beforeTransactionCommit;

  static const _syncKey = 'ledger';

  final AppDatabase _db;
  final HomeRepository _homeRepository;
  final Future<void> Function()? _beforeTransactionCommit;

  @override
  Stream<HomeSnapshot> watchHome(OwnerScope scope, DateTime now) =>
      _homeRepository.watchSnapshot(scope, now);

  @override
  Future<List<OutboxMutation>> readPendingMutations({int limit = 100}) {
    return (_db.select(_db.outboxMutations)
          ..where((row) => row.status.equals('pending'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
          ..limit(limit))
        .get();
  }

  @override
  Future<void> removeMutations(List<String> operationIds) async {
    if (operationIds.isEmpty) return;
    await (_db.delete(
      _db.outboxMutations,
    )..where((row) => row.operationId.isIn(operationIds))).go();
  }

  @override
  Future<void> markMutationsFailed(List<String> operationIds) async {
    if (operationIds.isEmpty) return;
    await (_db.update(_db.outboxMutations)
          ..where((row) => row.operationId.isIn(operationIds)))
        .write(const OutboxMutationsCompanion(status: Value('failed')));
  }

  @override
  Future<void> replaceBootstrap(
    BootstrapPayload payload,
    DateTime syncedAt,
    String sessionDeviceUuid, {
    int sessionGeneration = 0,
    String sessionIdentity = '',
    bool Function()? isSessionCurrent,
  }) {
    return _db.transaction(() async {
      final household = _householdFrom(payload.household);
      final owners = payload.owners.map(_ownerFrom).toList(growable: false);
      final accounts = payload.accounts
          .map(_accountFrom)
          .toList(growable: false);
      final categories = payload.categories
          .map(_categoryFrom)
          .toList(growable: false);
      final transactions = payload.transactions
          .map(_transactionFrom)
          .toList(growable: false);

      await _db.delete(_db.transactions).go();
      await _db.delete(_db.accounts).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.syncState).go();
      await _db.delete(_db.owners).go();
      await _db.delete(_db.households).go();

      await _db.into(_db.households).insert(household);
      for (final owner in owners) {
        await _db.into(_db.owners).insert(owner);
      }
      for (final account in accounts) {
        await _db.into(_db.accounts).insert(account);
      }
      for (final category in categories) {
        await _db.into(_db.categories).insert(category);
      }
      for (final transaction in transactions) {
        await _db.into(_db.transactions).insert(transaction);
      }

      await _db
          .into(_db.syncState)
          .insert(
            SyncStateCompanion.insert(
              key: const Value(_syncKey),
              cursor: _nonEmpty(payload.cursor, 'cursor'),
              householdUuid: household.uuid.value,
              sessionDeviceUuid: _requiredUuidValue(
                sessionDeviceUuid,
                'sessionDeviceUuid',
              ),
              sessionGeneration: Value(sessionGeneration),
              sessionIdentity: Value(PersistedSessionIdentity(sessionIdentity)),
              lastSuccessAt: Value(syncedAt),
            ),
          );
      await _beforeTransactionCommit?.call();
      _ensureSessionCurrent(isSessionCurrent);
    });
  }

  @override
  Future<void> applyDelta(
    SyncPage page,
    DateTime syncedAt, {
    int sessionGeneration = 0,
    String sessionIdentity = '',
    bool Function()? isSessionCurrent,
  }) {
    return applyDeltaChain(
      <SyncPage>[page],
      syncedAt,
      sessionGeneration: sessionGeneration,
      sessionIdentity: sessionIdentity,
      isSessionCurrent: isSessionCurrent,
    );
  }

  @override
  Future<void> applyDeltaChain(
    List<SyncPage> pages,
    DateTime syncedAt, {
    int sessionGeneration = 0,
    String sessionIdentity = '',
    bool Function()? isSessionCurrent,
  }) {
    if (pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', 'must not be empty');
    }
    return _db.transaction(() async {
      final metadata = await (_db.select(
        _db.syncState,
      )..where((row) => row.key.equals(_syncKey))).getSingleOrNull();
      if (metadata == null) {
        throw StateError('A bootstrap is required before applying a delta.');
      }

      for (final page in pages) {
        for (final change in page.changes) {
          await _applyChange(change);
        }
      }

      await (_db.update(
        _db.syncState,
      )..where((row) => row.key.equals(_syncKey))).write(
        SyncStateCompanion(
          cursor: Value(_nonEmpty(pages.last.cursor, 'cursor')),
          sessionGeneration: Value(sessionGeneration),
          sessionIdentity: Value(PersistedSessionIdentity(sessionIdentity)),
          lastSuccessAt: Value(syncedAt),
        ),
      );
      await _beforeTransactionCommit?.call();
      _ensureSessionCurrent(isSessionCurrent);
    });
  }

  @override
  Future<SyncMetadata?> readSyncMetadata() async {
    final row = await (_db.select(
      _db.syncState,
    )..where((candidate) => candidate.key.equals(_syncKey))).getSingleOrNull();
    final lastSuccessAt = row?.lastSuccessAt;
    if (row == null || lastSuccessAt == null) {
      return null;
    }

    return SyncMetadata(
      cursor: row.cursor,
      householdUuid: row.householdUuid,
      sessionDeviceUuid: row.sessionDeviceUuid,
      sessionGeneration: row.sessionGeneration,
      sessionIdentity: row.sessionIdentity.value,
      lastSuccessAt: lastSuccessAt,
    );
  }

  Future<void> _applyChange(SyncChangePayload change) async {
    final entityUuid = _requiredUuidValue(change.entityUuid, 'entity_uuid');
    if (change.entityVersion < 1) {
      throw FormatException('entity_version must be positive.');
    }
    if (change.entityType != 'account' &&
        change.entityType != 'category' &&
        change.entityType != 'transaction') {
      throw FormatException('Unknown entity_type: ${change.entityType}');
    }
    if (change.operation != 'create' &&
        change.operation != 'update' &&
        change.operation != 'delete') {
      throw FormatException('Unknown operation: ${change.operation}');
    }

    final existingVersion = await _existingVersion(
      change.entityType,
      entityUuid,
    );
    if (existingVersion != null && change.entityVersion <= existingVersion) {
      throw StateError(
        'Version ${change.entityVersion} is not newer than $existingVersion.',
      );
    }

    if (change.operation == 'delete') {
      _validateDeletePayload(change, entityUuid);
      await _deleteEntity(change.entityType, entityUuid);
      return;
    }

    _validateEnvelope(change, entityUuid);
    switch (change.entityType) {
      case 'account':
        await _db
            .into(_db.accounts)
            .insertOnConflictUpdate(_accountFrom(change.payload));
      case 'category':
        await _db
            .into(_db.categories)
            .insertOnConflictUpdate(_categoryFrom(change.payload));
      case 'transaction':
        await _db
            .into(_db.transactions)
            .insertOnConflictUpdate(_transactionFrom(change.payload));
    }
  }

  Future<int?> _existingVersion(String entityType, String uuid) async {
    switch (entityType) {
      case 'account':
        return (_db.select(_db.accounts)..where((row) => row.uuid.equals(uuid)))
            .map((row) => row.version)
            .getSingleOrNull();
      case 'category':
        return (_db.select(_db.categories)
              ..where((row) => row.uuid.equals(uuid)))
            .map((row) => row.version)
            .getSingleOrNull();
      case 'transaction':
        return (_db.select(_db.transactions)
              ..where((row) => row.uuid.equals(uuid)))
            .map((row) => row.version)
            .getSingleOrNull();
    }
    throw FormatException('Unknown entity_type: $entityType');
  }

  Future<void> _deleteEntity(String entityType, String uuid) async {
    switch (entityType) {
      case 'account':
        await (_db.delete(
          _db.accounts,
        )..where((row) => row.uuid.equals(uuid))).go();
      case 'category':
        await (_db.delete(
          _db.categories,
        )..where((row) => row.uuid.equals(uuid))).go();
      case 'transaction':
        await (_db.delete(
          _db.transactions,
        )..where((row) => row.uuid.equals(uuid))).go();
    }
  }
}

void _ensureSessionCurrent(bool Function()? isSessionCurrent) {
  if (isSessionCurrent != null && !isSessionCurrent()) {
    throw StateError('The active session changed during the ledger commit.');
  }
}

HouseholdsCompanion _householdFrom(JsonObject json) {
  return HouseholdsCompanion.insert(
    uuid: _requiredUuid(json, 'uuid'),
    name: _requiredString(json, 'name'),
    updatedAt: _requiredDateTime(json, 'updated_at'),
  );
}

OwnersCompanion _ownerFrom(JsonObject json) {
  return OwnersCompanion.insert(
    uuid: _requiredUuid(json, 'uuid'),
    type: _requiredString(json, 'type'),
    name: _requiredString(json, 'name'),
  );
}

AccountsCompanion _accountFrom(JsonObject json) {
  return AccountsCompanion.insert(
    uuid: _requiredUuid(json, 'uuid'),
    householdUuid: _requiredUuid(json, 'household_uuid'),
    financialOwnerUuid: _requiredUuid(json, 'financial_owner_uuid'),
    name: _requiredString(json, 'name'),
    type: _requiredString(json, 'type'),
    initialBalanceMinor: parseMinorUnits(
      _requiredString(json, 'initial_balance'),
    ),
    currency: _requiredString(json, 'currency'),
    version: _requiredPositiveInt(json, 'version'),
    createdAt: _requiredDateTime(json, 'created_at'),
    updatedAt: _requiredDateTime(json, 'updated_at'),
  );
}

CategoriesCompanion _categoryFrom(JsonObject json) {
  return CategoriesCompanion.insert(
    uuid: _requiredUuid(json, 'uuid'),
    householdUuid: _requiredUuid(json, 'household_uuid'),
    name: _requiredString(json, 'name'),
    type: _requiredString(json, 'type'),
    color: _requiredString(json, 'color'),
    icon: Value(_nullableString(json, 'icon')),
    version: _requiredPositiveInt(json, 'version'),
    createdAt: _requiredDateTime(json, 'created_at'),
    updatedAt: _requiredDateTime(json, 'updated_at'),
  );
}

TransactionsCompanion _transactionFrom(JsonObject json) {
  return TransactionsCompanion.insert(
    uuid: _requiredUuid(json, 'uuid'),
    householdUuid: _requiredUuid(json, 'household_uuid'),
    financialOwnerUuid: _requiredUuid(json, 'financial_owner_uuid'),
    accountUuid: _requiredUuid(json, 'account_uuid'),
    categoryUuid: _requiredUuid(json, 'category_uuid'),
    description: _requiredString(json, 'description'),
    amountMinor: _requiredTransactionMinor(json),
    date: _requiredDate(json, 'date'),
    type: _requiredString(json, 'type'),
    version: _requiredPositiveInt(json, 'version'),
    createdAt: _requiredDateTime(json, 'created_at'),
    updatedAt: _requiredDateTime(json, 'updated_at'),
  );
}

void _validateEnvelope(SyncChangePayload change, String entityUuid) {
  if (_requiredUuid(change.payload, 'uuid') != entityUuid ||
      _requiredPositiveInt(change.payload, 'version') != change.entityVersion) {
    throw const FormatException(
      'Sync envelope UUID/version does not match its payload.',
    );
  }
}

void _validateDeletePayload(SyncChangePayload change, String entityUuid) {
  if (_requiredUuid(change.payload, 'uuid') != entityUuid ||
      change.payload['deleted'] != true) {
    throw const FormatException('Invalid delete payload.');
  }
}

String _requiredString(JsonObject json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _requiredUuid(JsonObject json, String key) {
  return _requiredUuidValue(_requiredString(json, key), key);
}

String _requiredUuidValue(String value, String field) {
  if (!_uuidPattern.hasMatch(value)) {
    throw FormatException('$field must be a canonical UUID string.');
  }
  return value.toLowerCase();
}

String _nonEmpty(String value, String field) {
  if (value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

String? _nullableString(JsonObject json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('$key must be a string or null.');
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

int _requiredTransactionMinor(JsonObject json) {
  final amount = parseMinorUnits(_requiredString(json, 'amount'));
  if (amount < 0) {
    throw const FormatException('amount must be a non-negative magnitude.');
  }
  return amount;
}

DateTime _requiredDateTime(JsonObject json, String key) {
  final value = _requiredString(json, key);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (match == null) {
    throw FormatException('$key must be a strict RFC3339 string.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final localComponents = DateTime.utc(year, month, day, hour, minute, second);
  if (localComponents.year != year ||
      localComponents.month != month ||
      localComponents.day != day ||
      localComponents.hour != hour ||
      localComponents.minute != minute ||
      localComponents.second != second) {
    throw FormatException('$key has invalid RFC3339 components.');
  }
  final zone = match.group(7)!;
  if (zone != 'Z') {
    final zoneHour = int.parse(zone.substring(1, 3));
    final zoneMinute = int.parse(zone.substring(4, 6));
    if (zoneHour > 23 || zoneMinute > 59) {
      throw FormatException('$key has an invalid RFC3339 offset.');
    }
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$key must be a valid RFC3339 string.');
  }
  return parsed.toUtc();
}

DateTime _requiredDate(JsonObject json, String key) {
  final value = _requiredString(json, key);
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw FormatException('$key must be an ISO date string.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw FormatException('$key must be a valid ISO date string.');
  }
  return parsed;
}
