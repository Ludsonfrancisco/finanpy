import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/core/storage/local_ledger.dart';
import 'package:lar_finance/core/sync/sync_models.dart';

void main() {
  late AppDatabase db;
  late DriftLocalLedger ledger;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = DriftLocalLedger(db);
    await _seedHome(db);
  });

  tearDown(() => db.close());

  test(
    'watchHome uses local civil month and a bounded 30-day window',
    () async {
      final now = DateTime(2026, 8, 14, 12);
      await _insertTransaction(
        db,
        '50000000-0000-4000-8000-000000000001',
        DateTime.utc(2026, 8, 1),
        500,
        updatedAt: now,
      );
      await _insertTransaction(
        db,
        '50000000-0000-4000-8000-000000000002',
        DateTime.utc(2026, 8, 14),
        100,
        updatedAt: now,
      );
      await _insertTransaction(
        db,
        '50000000-0000-4000-8000-000000000003',
        DateTime.utc(2026, 8, 15),
        200,
        updatedAt: now,
      );
      await _insertTransaction(
        db,
        '50000000-0000-4000-8000-000000000004',
        DateTime.utc(2026, 9, 13),
        300,
        updatedAt: now,
      );
      await _insertTransaction(
        db,
        '50000000-0000-4000-8000-000000000005',
        DateTime.utc(2026, 9, 14),
        400,
        updatedAt: now,
      );
      await _insertTransaction(
        db,
        '50000000-0000-4000-8000-000000000006',
        DateTime.utc(2026, 7, 1),
        1000,
        type: 'income',
        updatedAt: now,
      );

      final snapshot = await ledger
          .watchHome(const OwnerScope.household(), now)
          .first;

      expect(snapshot.balanceMinor, 9500);
      expect(snapshot.monthExpenseMinor, 800);
      expect(snapshot.upcomingCommitmentMinor, 500);
    },
  );

  test('watchHome derives month boundaries from local time', () async {
    final localNow = DateTime(2026, 8, 31, 23, 30);
    await _insertTransaction(
      db,
      '51000000-0000-4000-8000-000000000001',
      DateTime.utc(2026, 8, 31),
      100,
      updatedAt: localNow,
    );
    await _insertTransaction(
      db,
      '51000000-0000-4000-8000-000000000002',
      DateTime.utc(2026, 9, 1),
      200,
      updatedAt: localNow,
    );

    final snapshot = await ledger
        .watchHome(const OwnerScope.household(), localNow.toUtc())
        .first;

    expect(snapshot.monthExpenseMinor, 100);
  });

  test('watchHome orders ties by date updatedAt and UUID descending', () async {
    final date = DateTime.utc(2026, 8, 10);
    await _insertTransaction(
      db,
      '52000000-0000-4000-8000-000000000001',
      date,
      100,
      updatedAt: DateTime.utc(2026, 8, 10, 12),
    );
    await _insertTransaction(
      db,
      '52000000-0000-4000-8000-000000000003',
      date,
      100,
      updatedAt: DateTime.utc(2026, 8, 10, 13),
    );
    await _insertTransaction(
      db,
      '52000000-0000-4000-8000-000000000002',
      date,
      100,
      updatedAt: DateTime.utc(2026, 8, 10, 12),
    );

    final snapshot = await ledger
        .watchHome(const OwnerScope.household(), DateTime(2026, 8, 14))
        .first;

    expect(snapshot.recentTransactions.map((item) => item.uuid), [
      '52000000-0000-4000-8000-000000000003',
      '52000000-0000-4000-8000-000000000002',
      '52000000-0000-4000-8000-000000000001',
    ]);
  });

  test(
    'watchHome reacts once with a coherent post-transaction snapshot',
    () async {
      final stream = ledger.watchHome(
        const OwnerScope.household(),
        DateTime(2026, 8, 14),
      );
      expect((await stream.first).balanceMinor, 10000);
      final nextSnapshot = stream.skip(1).first;

      await db.transaction(() async {
        await (db.update(db.accounts)..where(
              (row) => row.uuid.equals('30000000-0000-4000-8000-000000000001'),
            ))
            .write(const AccountsCompanion(initialBalanceMinor: Value(20000)));
        await _insertTransaction(
          db,
          '53000000-0000-4000-8000-000000000001',
          DateTime.utc(2026, 8, 14),
          1000,
          updatedAt: DateTime.utc(2026, 8, 14, 12),
        );
      });

      final snapshot = await nextSnapshot.timeout(const Duration(seconds: 2));
      expect(snapshot.balanceMinor, 19000);
      expect(snapshot.monthExpenseMinor, 1000);
      expect(
        snapshot.recentTransactions.single.uuid,
        '53000000-0000-4000-8000-000000000001',
      );
    },
  );
}

Future<void> _seedHome(AppDatabase db) async {
  final now = DateTime.utc(2026, 8, 1);
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          uuid: '10000000-0000-4000-8000-000000000001',
          name: 'Casa',
          updatedAt: now,
        ),
      );
  await db
      .into(db.owners)
      .insert(
        OwnersCompanion.insert(
          uuid: '20000000-0000-4000-8000-000000000001',
          type: 'self',
          name: 'Eu',
        ),
      );
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          uuid: '30000000-0000-4000-8000-000000000001',
          householdUuid: '10000000-0000-4000-8000-000000000001',
          financialOwnerUuid: '20000000-0000-4000-8000-000000000001',
          name: 'Conta',
          type: 'checking',
          initialBalanceMinor: 10000,
          currency: 'BRL',
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          uuid: '40000000-0000-4000-8000-000000000001',
          householdUuid: '10000000-0000-4000-8000-000000000001',
          name: 'Geral',
          type: 'expense',
          color: '#000000',
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.syncState)
      .insert(
        SyncStateCompanion.insert(
          cursor: 'cursor',
          householdUuid: '10000000-0000-4000-8000-000000000001',
          sessionDeviceUuid: '70000000-0000-4000-8000-000000000001',
          lastSuccessAt: Value(now),
        ),
      );
}

Future<void> _insertTransaction(
  AppDatabase db,
  String uuid,
  DateTime date,
  int amountMinor, {
  String type = 'expense',
  required DateTime updatedAt,
}) {
  return db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: uuid,
          householdUuid: '10000000-0000-4000-8000-000000000001',
          financialOwnerUuid: '20000000-0000-4000-8000-000000000001',
          accountUuid: '30000000-0000-4000-8000-000000000001',
          categoryUuid: '40000000-0000-4000-8000-000000000001',
          description: uuid,
          amountMinor: amountMinor,
          date: date,
          type: type,
          version: 1,
          createdAt: updatedAt,
          updatedAt: updatedAt,
        ),
      );
}
