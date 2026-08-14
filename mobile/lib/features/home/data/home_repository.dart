import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../domain/home_snapshot.dart';

abstract interface class HomeRepository {
  Future<HomeOwnerScopes> readOwnerScopes();
  Stream<HomeSnapshot> watchSnapshot(OwnerScope scope, DateTime now);
}

final class DriftHomeRepository implements HomeRepository {
  DriftHomeRepository(this._database);

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
  Stream<HomeSnapshot> watchSnapshot(OwnerScope scope, DateTime now) {
    return _database
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _database.accounts,
            _database.categories,
            _database.transactions,
            _database.owners,
            _database.syncState,
          },
        )
        .watch()
        .asyncMap((_) => _readSnapshot(scope, now));
  }

  Future<HomeSnapshot> _readSnapshot(OwnerScope scope, DateTime now) async {
    final localNow = now.toLocal();
    final monthStart = DateTime.utc(localNow.year, localNow.month);
    final nextMonth = DateTime.utc(localNow.year, localNow.month + 1);
    final tomorrow = DateTime.utc(
      localNow.year,
      localNow.month,
      localNow.day + 1,
    );
    final afterThirtyDays = DateTime.utc(
      localNow.year,
      localNow.month,
      localNow.day + 31,
    );
    final ownerUuid = scope.ownerUuid == null
        ? null
        : _canonicalUuid(scope.ownerUuid!, 'ownerUuid');
    final canonicalScope = switch (scope.kind) {
      OwnerScopeKind.household => const OwnerScope.household(),
      OwnerScopeKind.selfOwner => OwnerScope.self(ownerUuid!),
      OwnerScopeKind.spouse => OwnerScope.spouse(ownerUuid!),
    };

    return _database.transaction(() async {
      final aggregateVariables = <Variable>[];
      String predicate(String alias) {
        if (ownerUuid == null) return '1 = 1';
        aggregateVariables.add(Variable(ownerUuid));
        return '$alias.financial_owner_uuid = ?';
      }

      final accountCountScope = predicate('a');
      final accountBalanceScope = predicate('a');
      final balanceScope = predicate('t');
      final monthScope = predicate('t');
      aggregateVariables
        ..add(Variable.withDateTime(monthStart))
        ..add(Variable.withDateTime(nextMonth));
      final upcomingScope = predicate('t');
      aggregateVariables
        ..add(Variable.withDateTime(tomorrow))
        ..add(Variable.withDateTime(afterThirtyDays));

      final aggregate = await _database
          .customSelect(
            '''
SELECT
  (SELECT COUNT(*) FROM accounts a WHERE $accountCountScope) AS account_count,
  (SELECT COALESCE(SUM(a.initial_balance_minor), 0)
     FROM accounts a WHERE $accountBalanceScope)
  +
  (SELECT COALESCE(SUM(
      CASE WHEN t.type = 'expense' THEN -t.amount_minor ELSE t.amount_minor END
    ), 0) FROM transactions t WHERE $balanceScope) AS balance_minor,
  (SELECT COALESCE(SUM(t.amount_minor), 0)
     FROM transactions t
    WHERE $monthScope AND t.type = 'expense'
      AND t.date >= ? AND t.date < ?) AS month_expense_minor,
  (SELECT COALESCE(SUM(t.amount_minor), 0)
     FROM transactions t
    WHERE $upcomingScope AND t.type = 'expense'
      AND t.date >= ? AND t.date < ?) AS upcoming_commitment_minor,
  (SELECT last_success_at FROM sync_state WHERE key = 'ledger') AS last_success_at
''',
            variables: aggregateVariables,
            readsFrom: {
              _database.accounts,
              _database.transactions,
              _database.syncState,
            },
          )
          .getSingle();

      final recentVariables = <Variable>[];
      final recentScope = ownerUuid == null
          ? '1 = 1'
          : (() {
              recentVariables.add(Variable(ownerUuid));
              return 't.financial_owner_uuid = ?';
            })();
      final recentRows = await _database
          .customSelect(
            '''
SELECT t.uuid, t.description, c.name AS category_name, o.name AS owner_name,
       t.date, t.type, t.amount_minor
  FROM transactions t
  JOIN categories c ON c.uuid = t.category_uuid
  JOIN owners o ON o.uuid = t.financial_owner_uuid
 WHERE $recentScope
 ORDER BY t.date DESC, t.updated_at DESC, t.uuid DESC
 LIMIT 5
''',
            variables: recentVariables,
            readsFrom: {
              _database.transactions,
              _database.categories,
              _database.owners,
            },
          )
          .get();
      final lastSuccessText = aggregate.readNullable<String>('last_success_at');

      return HomeSnapshot(
        scope: canonicalScope,
        balanceMinor: aggregate.read<int>('balance_minor'),
        monthExpenseMinor: aggregate.read<int>('month_expense_minor'),
        upcomingCommitmentMinor: aggregate.read<int>(
          'upcoming_commitment_minor',
        ),
        recentTransactions: recentRows
            .map((row) {
              final amount = row.read<int>('amount_minor');
              return HomeTransaction(
                uuid: row.read<String>('uuid'),
                description: row.read<String>('description'),
                categoryName: row.read<String>('category_name'),
                ownerName: row.read<String>('owner_name'),
                date: DateTime.parse(row.read<String>('date')),
                signedAmountMinor: row.read<String>('type') == 'expense'
                    ? -amount
                    : amount,
              );
            })
            .toList(growable: false),
        lastSyncedAt: lastSuccessText == null
            ? null
            : DateTime.parse(lastSuccessText).toUtc(),
        hasAccountData: aggregate.read<int>('account_count') > 0,
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
