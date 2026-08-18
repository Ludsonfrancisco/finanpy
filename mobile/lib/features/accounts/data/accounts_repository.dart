import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/uuid/uuid_generator.dart';
import '../../home/domain/home_snapshot.dart';
import '../../transactions/domain/transactions_models.dart'
    show TransactionOwnerOption;
import '../domain/accounts_models.dart';

abstract interface class AccountsRepository {
  Future<HomeOwnerScopes> readOwnerScopes();
  Stream<AccountsSnapshot> watchAccounts(OwnerScope scope);
  Future<List<TransactionOwnerOption>> readAvailableOwners();
  Future<String> createAccount({
    required String name,
    required AccountType type,
    required int initialBalanceMinor,
    required String financialOwnerUuid,
  });
}

final class DriftAccountsRepository implements AccountsRepository {
  DriftAccountsRepository(this._database);

  final AppDatabase _database;

  @override
  Future<HomeOwnerScopes> readOwnerScopes() async {
    final rows =
        await (_database.select(_database.owners)..where(
              (owner) => owner.type.isIn(const <String>['self', 'spouse']),
            ))
            .get();

    String uuidFor(String type) {
      final matching = rows.where((owner) => owner.type == type);
      if (matching.length != 1) {
        throw StateError('The local ledger must contain one $type owner.');
      }
      return matching.single.uuid;
    }

    return HomeOwnerScopes(
      selfScope: OwnerScope.self(uuidFor('self')),
      spouseScope: OwnerScope.spouse(uuidFor('spouse')),
    );
  }

  @override
  Stream<AccountsSnapshot> watchAccounts(OwnerScope scope) {
    return _database
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _database.accounts,
            _database.transactions,
            _database.owners,
            _database.syncState,
          },
        )
        .watch()
        .asyncMap((_) => _readAccountsSnapshot(scope));
  }

  Future<AccountsSnapshot> _readAccountsSnapshot(OwnerScope scope) async {
    final ownerUuid = scope.ownerUuid == null
        ? null
        : _canonicalUuid(scope.ownerUuid!, 'ownerUuid');
    final canonicalScope = switch (scope.kind) {
      OwnerScopeKind.household => const OwnerScope.household(),
      OwnerScopeKind.selfOwner => OwnerScope.self(ownerUuid!),
      OwnerScopeKind.spouse => OwnerScope.spouse(ownerUuid!),
    };

    return _database.transaction(() async {
      final variables = <Variable>[];
      final whereClause = ownerUuid == null
          ? '1 = 1'
          : (() {
              variables.add(Variable(ownerUuid));
              return 'a.financial_owner_uuid = ?';
            })();

      final rows = await _database
          .customSelect(
            '''
SELECT a.uuid, a.name, a.type, a.initial_balance_minor, a.currency,
       a.updated_at, o.name AS owner_name, o.type AS owner_type,
       (a.initial_balance_minor + COALESCE((
          SELECT SUM(CASE WHEN t.type = 'expense' THEN -t.amount_minor ELSE t.amount_minor END)
            FROM transactions t
           WHERE t.account_uuid = a.uuid
       ), 0)) AS current_balance_minor
  FROM accounts a
  JOIN owners o ON o.uuid = a.financial_owner_uuid
 WHERE $whereClause
 ORDER BY a.name ASC, a.uuid ASC
''',
            variables: variables,
            readsFrom: {
              _database.accounts,
              _database.transactions,
              _database.owners,
            },
          )
          .get();

      final syncRow = await _database
          .customSelect(
            "SELECT last_success_at FROM sync_state WHERE key = 'ledger'",
            readsFrom: {_database.syncState},
          )
          .getSingleOrNull();

      final lastSuccessText = syncRow?.readNullable<String>('last_success_at');
      final accounts = rows
          .map((row) {
            return AccountItem(
              uuid: row.read<String>('uuid'),
              name: row.read<String>('name'),
              type: AccountType.fromString(row.read<String>('type')),
              initialBalanceMinor: row.read<int>('initial_balance_minor'),
              currentBalanceMinor: row.read<int>('current_balance_minor'),
              currency: row.read<String>('currency'),
              ownerName: row.read<String>('owner_name'),
              ownerType: row.read<String>('owner_type'),
              updatedAt: DateTime.parse(row.read<String>('updated_at')),
            );
          })
          .toList(growable: false);

      final totalBalance = accounts.fold<int>(
        0,
        (acc, item) => acc + item.currentBalanceMinor,
      );

      return AccountsSnapshot(
        scope: canonicalScope,
        accounts: accounts,
        totalBalanceMinor: totalBalance,
        lastSyncedAt: lastSuccessText == null
            ? null
            : DateTime.parse(lastSuccessText).toUtc(),
        hasAccountData: accounts.isNotEmpty,
      );
    });
  }

  @override
  Future<List<TransactionOwnerOption>> readAvailableOwners() async {
    final rows = await (_database.select(
      _database.owners,
    )..orderBy([(o) => OrderingTerm.asc(o.name)])).get();
    return rows
        .map(
          (o) =>
              TransactionOwnerOption(uuid: o.uuid, name: o.name, type: o.type),
        )
        .toList(growable: false);
  }

  @override
  Future<String> createAccount({
    required String name,
    required AccountType type,
    required int initialBalanceMinor,
    required String financialOwnerUuid,
  }) async {
    final newUuid = generateUuidV4();
    final operationId = generateUuidV4();
    final now = DateTime.now().toUtc();
    final typeStr = type.name;
    final initialBalanceDecimalStr = (initialBalanceMinor / 100)
        .toStringAsFixed(2);

    final householdRow = await _database
        .select(_database.households)
        .getSingleOrNull();
    final householdUuid = householdRow?.uuid ?? '';

    final payloadJson = jsonEncode({
      'name': name,
      'type': typeStr,
      'initial_balance': initialBalanceDecimalStr,
      'currency': 'BRL',
      'financial_owner_uuid': financialOwnerUuid,
    });

    await _database.transaction(() async {
      await _database
          .into(_database.accounts)
          .insert(
            AccountsCompanion.insert(
              uuid: newUuid,
              householdUuid: householdUuid,
              financialOwnerUuid: financialOwnerUuid,
              name: name,
              type: typeStr,
              initialBalanceMinor: initialBalanceMinor,
              currency: 'BRL',
              version: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _database
          .into(_database.outboxMutations)
          .insert(
            OutboxMutationsCompanion.insert(
              operationId: operationId,
              entity: 'account',
              action: 'create',
              entityUuid: newUuid,
              expectedVersion: 0,
              payloadJson: payloadJson,
              createdAt: now,
              status: const Value('pending'),
            ),
          );
    });

    return newUuid;
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _canonicalUuid(String value, String field) {
  if (!_uuidPattern.hasMatch(value)) {
    throw FormatException('$field must be a canonical UUID string.');
  }
  return value.toLowerCase();
}
