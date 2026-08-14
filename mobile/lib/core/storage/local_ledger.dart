import 'package:drift/drift.dart';

import '../money/minor_units.dart';
import '../sync/sync_models.dart';
import 'app_database.dart';

abstract interface class LocalLedger {
  Stream<HomeSnapshot> watchHome(OwnerScope scope, DateTime now);
  Future<void> replaceBootstrap(
    BootstrapPayload payload,
    DateTime syncedAt,
    String sessionDeviceUuid,
  );
  Future<void> applyDelta(SyncPage page, DateTime syncedAt);
  Future<SyncMetadata?> readSyncMetadata();
}

final class DriftLocalLedger implements LocalLedger {
  DriftLocalLedger(this._db);

  static const _syncKey = 'ledger';

  final AppDatabase _db;

  @override
  Stream<HomeSnapshot> watchHome(OwnerScope scope, DateTime now) {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.accounts,
            _db.categories,
            _db.transactions,
            _db.owners,
            _db.syncState,
          },
        )
        .watch()
        .asyncMap((_) => _readHome(scope, now));
  }

  @override
  Future<void> replaceBootstrap(
    BootstrapPayload payload,
    DateTime syncedAt,
    String sessionDeviceUuid,
  ) {
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
              sessionDeviceUuid: _nonEmpty(
                sessionDeviceUuid,
                'sessionDeviceUuid',
              ),
              lastSuccessAt: Value(syncedAt),
            ),
          );
    });
  }

  @override
  Future<void> applyDelta(SyncPage page, DateTime syncedAt) {
    return _db.transaction(() async {
      final metadata = await (_db.select(
        _db.syncState,
      )..where((row) => row.key.equals(_syncKey))).getSingleOrNull();
      if (metadata == null) {
        throw StateError('A bootstrap is required before applying a delta.');
      }

      for (final change in page.changes) {
        await _applyChange(change);
      }

      await (_db.update(
        _db.syncState,
      )..where((row) => row.key.equals(_syncKey))).write(
        SyncStateCompanion(
          cursor: Value(_nonEmpty(page.cursor, 'cursor')),
          lastSuccessAt: Value(syncedAt),
        ),
      );
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
      lastSuccessAt: lastSuccessAt,
    );
  }

  Future<void> _applyChange(SyncChangePayload change) async {
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
      change.entityUuid,
    );
    if (existingVersion != null && change.entityVersion <= existingVersion) {
      throw StateError(
        'Version ${change.entityVersion} is not newer than $existingVersion.',
      );
    }

    if (change.operation == 'delete') {
      _validateDeletePayload(change);
      await _deleteEntity(change.entityType, change.entityUuid);
      return;
    }

    _validateEnvelope(change);
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

  Future<HomeSnapshot> _readHome(OwnerScope scope, DateTime now) async {
    final accounts = await _db.select(_db.accounts).get();
    final transactions = await _db.select(_db.transactions).get();
    final categories = {
      for (final category in await _db.select(_db.categories).get())
        category.uuid: category.name,
    };
    final owners = {
      for (final owner in await _db.select(_db.owners).get())
        owner.uuid: owner.name,
    };
    final ownerUuid = scope.ownerUuid;
    final scopedAccounts = ownerUuid == null
        ? accounts
        : accounts
              .where((account) => account.financialOwnerUuid == ownerUuid)
              .toList();
    final scopedTransactions = ownerUuid == null
        ? transactions
        : transactions
              .where(
                (transaction) => transaction.financialOwnerUuid == ownerUuid,
              )
              .toList();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    int signedAmount(Transaction transaction) => transaction.type == 'expense'
        ? -transaction.amountMinor
        : transaction.amountMinor;

    final recent = [...scopedTransactions]
      ..sort((left, right) => right.date.compareTo(left.date));
    final metadata = await readSyncMetadata();

    return HomeSnapshot(
      scope: scope,
      balanceMinor:
          scopedAccounts.fold(
            0,
            (sum, account) => sum + account.initialBalanceMinor,
          ) +
          scopedTransactions.fold(0, (sum, item) => sum + signedAmount(item)),
      monthExpenseMinor: scopedTransactions
          .where(
            (item) =>
                item.type == 'expense' &&
                !item.date.isBefore(monthStart) &&
                item.date.isBefore(nextMonth),
          )
          .fold(0, (sum, item) => sum + item.amountMinor),
      upcomingCommitmentMinor: scopedTransactions
          .where((item) => item.type == 'expense' && item.date.isAfter(now))
          .fold(0, (sum, item) => sum + item.amountMinor),
      recentTransactions: recent
          .take(5)
          .map((item) {
            return HomeTransaction(
              uuid: item.uuid,
              description: item.description,
              categoryName: categories[item.categoryUuid] ?? '',
              ownerName: owners[item.financialOwnerUuid] ?? '',
              date: item.date,
              signedAmountMinor: signedAmount(item),
            );
          })
          .toList(growable: false),
      lastSyncedAt: metadata?.lastSuccessAt,
    );
  }
}

HouseholdsCompanion _householdFrom(JsonObject json) {
  return HouseholdsCompanion.insert(
    uuid: _requiredString(json, 'uuid'),
    name: _requiredString(json, 'name'),
    updatedAt: _requiredDateTime(json, 'updated_at'),
  );
}

OwnersCompanion _ownerFrom(JsonObject json) {
  return OwnersCompanion.insert(
    uuid: _requiredString(json, 'uuid'),
    type: _requiredString(json, 'type'),
    name: _requiredString(json, 'name'),
  );
}

AccountsCompanion _accountFrom(JsonObject json) {
  return AccountsCompanion.insert(
    uuid: _requiredString(json, 'uuid'),
    householdUuid: _requiredString(json, 'household_uuid'),
    financialOwnerUuid: _requiredString(json, 'financial_owner_uuid'),
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
    uuid: _requiredString(json, 'uuid'),
    householdUuid: _requiredString(json, 'household_uuid'),
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
    uuid: _requiredString(json, 'uuid'),
    householdUuid: _requiredString(json, 'household_uuid'),
    financialOwnerUuid: _requiredString(json, 'financial_owner_uuid'),
    accountUuid: _requiredString(json, 'account_uuid'),
    categoryUuid: _requiredString(json, 'category_uuid'),
    description: _requiredString(json, 'description'),
    amountMinor: parseMinorUnits(_requiredString(json, 'amount')),
    date: _requiredDate(json, 'date'),
    type: _requiredString(json, 'type'),
    version: _requiredPositiveInt(json, 'version'),
    createdAt: _requiredDateTime(json, 'created_at'),
    updatedAt: _requiredDateTime(json, 'updated_at'),
  );
}

void _validateEnvelope(SyncChangePayload change) {
  if (_requiredString(change.payload, 'uuid') != change.entityUuid ||
      _requiredPositiveInt(change.payload, 'version') != change.entityVersion) {
    throw const FormatException(
      'Sync envelope UUID/version does not match its payload.',
    );
  }
}

void _validateDeletePayload(SyncChangePayload change) {
  if (_requiredString(change.payload, 'uuid') != change.entityUuid ||
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

DateTime _requiredDateTime(JsonObject json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !value.contains('T')) {
    throw FormatException('$key must be an ISO date-time string.');
  }
  return parsed;
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
