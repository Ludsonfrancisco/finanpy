import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/uuid/uuid_generator.dart';
import '../../home/domain/home_snapshot.dart';
import '../domain/transactions_models.dart';

abstract interface class TransactionsRepository {
  Future<HomeOwnerScopes> readOwnerScopes();
  Stream<TransactionsSnapshot> watchTransactions(
    OwnerScope scope,
    TransactionFilters filters,
  );
  Future<List<TransactionFilterOption>> readAvailableAccounts();
  Future<List<TransactionCategoryOption>> readAvailableCategories(
    TransactionType? type,
  );
  Future<List<TransactionOwnerOption>> readAvailableOwners();
  Future<String> createTransaction({
    required String description,
    required int amountMinor,
    required DateTime date,
    required TransactionType type,
    required String accountUuid,
    required String categoryUuid,
    required String financialOwnerUuid,
  });
  Future<void> updateTransaction({
    required String uuid,
    required String description,
    required int amountMinor,
    required DateTime date,
    required TransactionType type,
    required String accountUuid,
    required String categoryUuid,
    required String financialOwnerUuid,
  });
  Future<void> deleteTransaction(String uuid);
}

final class DriftTransactionsRepository implements TransactionsRepository {
  DriftTransactionsRepository(this._database);

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
  Stream<TransactionsSnapshot> watchTransactions(
    OwnerScope scope,
    TransactionFilters filters,
  ) {
    return _database
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _database.transactions,
            _database.categories,
            _database.accounts,
            _database.owners,
            _database.syncState,
          },
        )
        .watch()
        .asyncMap((_) => _readTransactionsSnapshot(scope, filters));
  }

  Future<TransactionsSnapshot> _readTransactionsSnapshot(
    OwnerScope scope,
    TransactionFilters filters,
  ) async {
    final ownerUuid = scope.ownerUuid == null
        ? null
        : _canonicalUuid(scope.ownerUuid!, 'ownerUuid');
    final canonicalScope = switch (scope.kind) {
      OwnerScopeKind.household => const OwnerScope.household(),
      OwnerScopeKind.selfOwner => OwnerScope.self(ownerUuid!),
      OwnerScopeKind.spouse => OwnerScope.spouse(ownerUuid!),
    };

    return _database.transaction(() async {
      final accountRows = await (_database.select(
        _database.accounts,
      )..orderBy([(a) => OrderingTerm.asc(a.name)])).get();

      final categoryRows = await (_database.select(
        _database.categories,
      )..orderBy([(c) => OrderingTerm.asc(c.name)])).get();

      final availableAccounts = accountRows
          .map((a) => TransactionFilterOption(uuid: a.uuid, name: a.name))
          .toList(growable: false);

      final availableCategories = categoryRows
          .map((c) => TransactionFilterOption(uuid: c.uuid, name: c.name))
          .toList(growable: false);

      final variables = <Variable>[];
      final clauses = <String>[];

      if (ownerUuid != null) {
        clauses.add('t.financial_owner_uuid = ?');
        variables.add(Variable(ownerUuid));
      }

      if (filters.searchQuery.trim().isNotEmpty) {
        final query = '%${filters.searchQuery.trim().toLowerCase()}%';
        clauses.add('LOWER(t.description) LIKE ?');
        variables.add(Variable(query));
      }

      if (filters.type != null) {
        clauses.add('t.type = ?');
        variables.add(Variable(filters.type!.name));
      }

      if (filters.accountUuid != null) {
        clauses.add('t.account_uuid = ?');
        variables.add(Variable(filters.accountUuid!));
      }

      if (filters.categoryUuid != null) {
        clauses.add('t.category_uuid = ?');
        variables.add(Variable(filters.categoryUuid!));
      }

      if (filters.startDate != null) {
        clauses.add('t.date >= ?');
        variables.add(Variable.withDateTime(filters.startDate!));
      }

      if (filters.endDate != null) {
        clauses.add('t.date <= ?');
        variables.add(Variable.withDateTime(filters.endDate!));
      }

      final whereClause = clauses.isEmpty ? '1 = 1' : clauses.join(' AND ');

      final rows = await _database
          .customSelect(
            '''
SELECT t.uuid, t.description, t.amount_minor, t.date, t.type, t.updated_at,
       c.name AS category_name, c.color AS category_color, c.icon AS category_icon,
       a.uuid AS account_uuid, a.name AS account_name,
       o.name AS owner_name, o.type AS owner_type
  FROM transactions t
  JOIN categories c ON c.uuid = t.category_uuid
  JOIN accounts a ON a.uuid = t.account_uuid
  JOIN owners o ON o.uuid = t.financial_owner_uuid
 WHERE $whereClause
 ORDER BY t.date DESC, t.updated_at DESC, t.uuid DESC
''',
            variables: variables,
            readsFrom: {
              _database.transactions,
              _database.categories,
              _database.accounts,
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

      int totalIncome = 0;
      int totalExpense = 0;
      final items = <TransactionItem>[];

      for (final row in rows) {
        final amount = row.read<int>('amount_minor');
        final typeStr = row.read<String>('type');
        final type = TransactionType.fromString(typeStr);

        if (type == TransactionType.income) {
          totalIncome += amount;
        } else {
          totalExpense += amount;
        }

        items.add(
          TransactionItem(
            uuid: row.read<String>('uuid'),
            description: row.read<String>('description'),
            categoryName: row.read<String>('category_name'),
            categoryColor: row.read<String>('category_color'),
            categoryIcon: row.readNullable<String>('category_icon'),
            accountName: row.read<String>('account_name'),
            accountUuid: row.read<String>('account_uuid'),
            ownerName: row.read<String>('owner_name'),
            ownerType: row.read<String>('owner_type'),
            date: DateTime.parse(row.read<String>('date')),
            type: type,
            amountMinor: amount,
            signedAmountMinor: type == TransactionType.expense
                ? -amount
                : amount,
            updatedAt: DateTime.parse(row.read<String>('updated_at')),
          ),
        );
      }

      // Group items by calendar day
      final groupedMap = <DateTime, List<TransactionItem>>{};
      for (final item in items) {
        final day = DateTime.utc(
          item.date.year,
          item.date.month,
          item.date.day,
        );
        groupedMap.putIfAbsent(day, () => <TransactionItem>[]).add(item);
      }

      final groups = groupedMap.entries
          .map((entry) {
            int dayIncome = 0;
            int dayExpense = 0;
            for (final t in entry.value) {
              if (t.type == TransactionType.income) {
                dayIncome += t.amountMinor;
              } else {
                dayExpense += t.amountMinor;
              }
            }
            return TransactionGroup(
              date: entry.key,
              transactions: entry.value,
              dayTotalIncomeMinor: dayIncome,
              dayTotalExpenseMinor: dayExpense,
            );
          })
          .toList(growable: false);

      return TransactionsSnapshot(
        scope: canonicalScope,
        groups: groups,
        totalCount: items.length,
        totalIncomeMinor: totalIncome,
        totalExpenseMinor: totalExpense,
        lastSyncedAt: lastSuccessText == null
            ? null
            : DateTime.parse(lastSuccessText).toUtc(),
        availableAccounts: availableAccounts,
        availableCategories: availableCategories,
      );
    });
  }

  @override
  Future<List<TransactionFilterOption>> readAvailableAccounts() async {
    final rows = await (_database.select(
      _database.accounts,
    )..orderBy([(a) => OrderingTerm.asc(a.name)])).get();
    return rows
        .map((a) => TransactionFilterOption(uuid: a.uuid, name: a.name))
        .toList(growable: false);
  }

  @override
  Future<List<TransactionCategoryOption>> readAvailableCategories(
    TransactionType? type,
  ) async {
    var query = _database.select(_database.categories);
    if (type != null) {
      final typeStr = type == TransactionType.income ? 'income' : 'expense';
      query = query..where((c) => c.type.equals(typeStr));
    }
    query = query..orderBy([(c) => OrderingTerm.asc(c.name)]);
    final rows = await query.get();
    return rows
        .map(
          (c) => TransactionCategoryOption(
            uuid: c.uuid,
            name: c.name,
            type: TransactionType.fromString(c.type),
            color: c.color,
            icon: c.icon,
          ),
        )
        .toList(growable: false);
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
  Future<String> createTransaction({
    required String description,
    required int amountMinor,
    required DateTime date,
    required TransactionType type,
    required String accountUuid,
    required String categoryUuid,
    required String financialOwnerUuid,
  }) async {
    final newUuid = generateUuidV4();
    final operationId = generateUuidV4();
    final now = DateTime.now().toUtc();
    final typeStr = type == TransactionType.income ? 'income' : 'expense';
    final amountDecimalStr = (amountMinor / 100).toStringAsFixed(2);
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final householdRow = await _database
        .select(_database.households)
        .getSingleOrNull();
    final householdUuid = householdRow?.uuid ?? '';

    final payloadJson = jsonEncode({
      'description': description,
      'amount': amountDecimalStr,
      'date': dateStr,
      'type': typeStr,
      'financial_owner_uuid': financialOwnerUuid,
      'account_uuid': accountUuid,
      'category_uuid': categoryUuid,
    });

    await _database.transaction(() async {
      await _database
          .into(_database.transactions)
          .insert(
            TransactionsCompanion.insert(
              uuid: newUuid,
              householdUuid: householdUuid,
              financialOwnerUuid: financialOwnerUuid,
              accountUuid: accountUuid,
              categoryUuid: categoryUuid,
              description: description,
              amountMinor: amountMinor,
              date: date,
              type: typeStr,
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
              entity: 'transaction',
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

  @override
  Future<void> updateTransaction({
    required String uuid,
    required String description,
    required int amountMinor,
    required DateTime date,
    required TransactionType type,
    required String accountUuid,
    required String categoryUuid,
    required String financialOwnerUuid,
  }) async {
    final existing = await (_database.select(
      _database.transactions,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (existing == null) {
      throw StateError('Transaction not found: $uuid');
    }

    final operationId = generateUuidV4();
    final now = DateTime.now().toUtc();
    final typeStr = type == TransactionType.income ? 'income' : 'expense';
    final amountDecimalStr = (amountMinor / 100).toStringAsFixed(2);
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final payloadJson = jsonEncode({
      'description': description,
      'amount': amountDecimalStr,
      'date': dateStr,
      'type': typeStr,
      'financial_owner_uuid': financialOwnerUuid,
      'account_uuid': accountUuid,
      'category_uuid': categoryUuid,
    });

    await _database.transaction(() async {
      await (_database.update(
        _database.transactions,
      )..where((t) => t.uuid.equals(uuid))).write(
        TransactionsCompanion(
          description: Value(description),
          amountMinor: Value(amountMinor),
          date: Value(date),
          type: Value(typeStr),
          accountUuid: Value(accountUuid),
          categoryUuid: Value(categoryUuid),
          financialOwnerUuid: Value(financialOwnerUuid),
          version: Value(existing.version + 1),
          updatedAt: Value(now),
        ),
      );
      await _database
          .into(_database.outboxMutations)
          .insert(
            OutboxMutationsCompanion.insert(
              operationId: operationId,
              entity: 'transaction',
              action: 'update',
              entityUuid: uuid,
              expectedVersion: existing.version,
              payloadJson: payloadJson,
              createdAt: now,
              status: const Value('pending'),
            ),
          );
    });
  }

  @override
  Future<void> deleteTransaction(String uuid) async {
    final existing = await (_database.select(
      _database.transactions,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (existing == null) return;

    final operationId = generateUuidV4();
    final now = DateTime.now().toUtc();

    await _database.transaction(() async {
      await (_database.delete(
        _database.transactions,
      )..where((t) => t.uuid.equals(uuid))).go();
      await _database
          .into(_database.outboxMutations)
          .insert(
            OutboxMutationsCompanion.insert(
              operationId: operationId,
              entity: 'transaction',
              action: 'delete',
              entityUuid: uuid,
              expectedVersion: existing.version,
              payloadJson: '{}',
              createdAt: now,
              status: const Value('pending'),
            ),
          );
    });
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
