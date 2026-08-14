import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/core/storage/local_ledger.dart';
import 'package:lar_finance/core/sync/sync_models.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 8, 14, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schema v1 stores exact minor units with valid relations', () async {
    await _seedParents(db, now);

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            uuid: 'transaction-1',
            householdUuid: 'household-1',
            financialOwnerUuid: 'owner-1',
            accountUuid: 'account-1',
            categoryUuid: 'category-1',
            description: 'Mercado',
            amountMinor: 2486040,
            date: DateTime.utc(2026, 8, 14),
            type: 'expense',
            version: 3,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final transaction = await db.select(db.transactions).getSingle();
    expect(db.schemaVersion, 1);
    expect(transaction.amountMinor, 2486040);
    expect(transaction.version, 3);
  });

  test('schema v1 rejects an invalid transaction relation', () async {
    await _seedParents(db, now);

    final insert = db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            uuid: 'transaction-invalid',
            householdUuid: 'household-1',
            financialOwnerUuid: 'owner-1',
            accountUuid: 'missing-account',
            categoryUuid: 'category-1',
            description: 'Inválida',
            amountMinor: 100,
            date: DateTime.utc(2026, 8, 14),
            type: 'expense',
            version: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await expectLater(insert, throwsA(isA<Exception>()));
  });

  test('schema v1 rejects an unknown owner type', () async {
    final insert = db
        .into(db.owners)
        .insert(
          OwnersCompanion.insert(
            uuid: 'owner-invalid',
            type: 'other',
            name: 'Inválido',
          ),
        );

    await expectLater(insert, throwsA(isA<Exception>()));
  });

  test('schema v1 rejects a sync-state key other than ledger', () async {
    await db
        .into(db.households)
        .insert(
          HouseholdsCompanion.insert(
            uuid: 'household-1',
            name: 'Casa',
            updatedAt: now,
          ),
        );

    final insert = db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            key: const Value('other'),
            cursor: 'cursor',
            householdUuid: 'household-1',
            sessionDeviceUuid: 'device-1',
          ),
        );

    await expectLater(insert, throwsA(isA<Exception>()));
  });

  test('schema v1 rejects a non-positive entity version', () async {
    await db
        .into(db.households)
        .insert(
          HouseholdsCompanion.insert(
            uuid: 'household-1',
            name: 'Casa',
            updatedAt: now,
          ),
        );
    await db
        .into(db.owners)
        .insert(
          OwnersCompanion.insert(uuid: 'owner-1', type: 'self', name: 'Eu'),
        );

    final insert = db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            uuid: 'account-invalid',
            householdUuid: 'household-1',
            financialOwnerUuid: 'owner-1',
            name: 'Conta',
            type: 'checking',
            initialBalanceMinor: 0,
            currency: 'BRL',
            version: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await expectLater(insert, throwsA(isA<Exception>()));
  });

  test(
    'replaceBootstrap rolls back ledger and cursor on invalid relation',
    () async {
      final ledger = DriftLocalLedger(db);
      await _seedOldLedger(db, now);

      final invalid = _bootstrap(
        cursor: 'cursor-after',
        accountUuid: 'account-new',
        transactionAccountUuid: 'missing-account',
      );

      await expectLater(
        ledger.replaceBootstrap(invalid, now, 'device-new'),
        throwsA(isA<Exception>()),
      );

      expect(await db.select(db.accounts).get(), hasLength(1));
      expect((await db.select(db.accounts).getSingle()).uuid, 'account-old');
      expect((await ledger.readSyncMetadata())?.cursor, 'cursor-before');
    },
  );

  test(
    'replaceBootstrap replaces all ledger rows and advances cursor',
    () async {
      final ledger = DriftLocalLedger(db);
      await _seedOldLedger(db, now);

      await ledger.replaceBootstrap(
        _bootstrap(cursor: 'cursor-after'),
        now,
        'device-new',
      );

      expect(
        (await db.select(db.households).getSingle()).uuid,
        'household-new',
      );
      expect((await db.select(db.accounts).getSingle()).uuid, 'account-new');
      expect(await db.select(db.transactions).get(), hasLength(1));
      expect(
        await ledger.readSyncMetadata(),
        isA<SyncMetadata>()
            .having((value) => value.cursor, 'cursor', 'cursor-after')
            .having(
              (value) => value.householdUuid,
              'householdUuid',
              'household-new',
            )
            .having(
              (value) => value.sessionDeviceUuid,
              'sessionDeviceUuid',
              'device-new',
            )
            .having((value) => value.lastSuccessAt, 'lastSuccessAt', now),
      );
    },
  );

  test(
    'applyDelta rejects unknown entities without row or cursor changes',
    () async {
      final ledger = DriftLocalLedger(db);
      await ledger.replaceBootstrap(
        _bootstrap(cursor: 'cursor-before'),
        now,
        'device-1',
      );

      final page = SyncPage(
        changes: [
          SyncChangePayload(
            entityType: 'account',
            entityUuid: 'account-new',
            entityVersion: 2,
            operation: 'update',
            payload: _accountPayload(name: 'Mutated', version: 2),
          ),
          const SyncChangePayload(
            entityType: 'unknown',
            entityUuid: 'unknown-1',
            entityVersion: 1,
            operation: 'create',
            payload: {'uuid': 'unknown-1', 'version': 1},
          ),
        ],
        cursor: 'cursor-after',
      );

      await expectLater(
        ledger.applyDelta(page, now.add(const Duration(minutes: 1))),
        throwsFormatException,
      );

      expect((await db.select(db.accounts).getSingle()).name, 'Nova conta');
      expect((await ledger.readSyncMetadata())?.cursor, 'cursor-before');
    },
  );

  test('applyDelta enforces monotonic versions and preserves cursor', () async {
    final ledger = DriftLocalLedger(db);
    await ledger.replaceBootstrap(
      _bootstrap(cursor: 'cursor-before'),
      now,
      'device-1',
    );

    await ledger.applyDelta(
      SyncPage(
        changes: [
          SyncChangePayload(
            entityType: 'account',
            entityUuid: 'account-new',
            entityVersion: 2,
            operation: 'update',
            payload: _accountPayload(name: 'Atualizada', version: 2),
          ),
        ],
        cursor: 'cursor-v2',
      ),
      now.add(const Duration(minutes: 1)),
    );

    await expectLater(
      ledger.applyDelta(
        SyncPage(
          changes: [
            SyncChangePayload(
              entityType: 'account',
              entityUuid: 'account-new',
              entityVersion: 2,
              operation: 'update',
              payload: _accountPayload(name: 'Stale', version: 2),
            ),
          ],
          cursor: 'cursor-stale',
        ),
        now.add(const Duration(minutes: 2)),
      ),
      throwsA(isA<StateError>()),
    );

    final account = await db.select(db.accounts).getSingle();
    expect(account.name, 'Atualizada');
    expect(account.version, 2);
    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-v2');
  });

  test('applyDelta deletes a UUID and advances cursor last', () async {
    final ledger = DriftLocalLedger(db);
    await ledger.replaceBootstrap(
      _bootstrap(cursor: 'cursor-before'),
      now,
      'device-1',
    );

    await ledger.applyDelta(
      const SyncPage(
        changes: [
          SyncChangePayload(
            entityType: 'transaction',
            entityUuid: 'transaction-new',
            entityVersion: 2,
            operation: 'delete',
            payload: {'uuid': 'transaction-new', 'deleted': true},
          ),
        ],
        cursor: 'cursor-after',
      ),
      now.add(const Duration(minutes: 1)),
    );

    expect(await db.select(db.transactions).get(), isEmpty);
    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-after');
  });
}

Future<void> _seedParents(AppDatabase db, DateTime now) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          uuid: 'household-1',
          name: 'Casa',
          updatedAt: now,
        ),
      );
  await db
      .into(db.owners)
      .insert(
        OwnersCompanion.insert(uuid: 'owner-1', type: 'self', name: 'Eu'),
      );
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          uuid: 'account-1',
          householdUuid: 'household-1',
          financialOwnerUuid: 'owner-1',
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
          uuid: 'category-1',
          householdUuid: 'household-1',
          name: 'Mercado',
          type: 'expense',
          color: '#000000',
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _seedOldLedger(AppDatabase db, DateTime now) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          uuid: 'household-old',
          name: 'Casa antiga',
          updatedAt: now,
        ),
      );
  await db
      .into(db.owners)
      .insert(
        OwnersCompanion.insert(uuid: 'owner-old', type: 'self', name: 'Eu'),
      );
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          uuid: 'account-old',
          householdUuid: 'household-old',
          financialOwnerUuid: 'owner-old',
          name: 'Conta antiga',
          type: 'checking',
          initialBalanceMinor: 100,
          currency: 'BRL',
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.syncState)
      .insert(
        SyncStateCompanion.insert(
          cursor: 'cursor-before',
          householdUuid: 'household-old',
          sessionDeviceUuid: 'device-old',
          lastSuccessAt: Value(now),
        ),
      );
}

BootstrapPayload _bootstrap({
  required String cursor,
  String accountUuid = 'account-new',
  String transactionAccountUuid = 'account-new',
}) {
  return BootstrapPayload(
    household: {
      'uuid': 'household-new',
      'name': 'Casa nova',
      'created_at': '2026-08-01T00:00:00Z',
      'updated_at': '2026-08-14T12:00:00Z',
    },
    owners: const [
      {'uuid': 'owner-new', 'type': 'self', 'name': 'Eu'},
    ],
    accounts: [_accountPayload(uuid: accountUuid)],
    categories: const [
      {
        'uuid': 'category-new',
        'version': 1,
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-14T12:00:00Z',
        'household_uuid': 'household-new',
        'name': 'Mercado',
        'type': 'expense',
        'color': '#000000',
        'icon': null,
      },
    ],
    transactions: [
      {
        'uuid': 'transaction-new',
        'version': 1,
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-14T12:00:00Z',
        'household_uuid': 'household-new',
        'financial_owner_uuid': 'owner-new',
        'account_uuid': transactionAccountUuid,
        'category_uuid': 'category-new',
        'description': 'Mercado',
        'amount': '25.40',
        'date': '2026-08-14',
        'type': 'expense',
      },
    ],
    cursor: cursor,
  );
}

JsonObject _accountPayload({
  String uuid = 'account-new',
  String name = 'Nova conta',
  int version = 1,
}) {
  return {
    'uuid': uuid,
    'version': version,
    'created_at': '2026-08-01T00:00:00Z',
    'updated_at': '2026-08-14T12:00:00Z',
    'household_uuid': 'household-new',
    'financial_owner_uuid': 'owner-new',
    'name': name,
    'type': 'checking',
    'initial_balance': '100.00',
    'currency': 'BRL',
  };
}
