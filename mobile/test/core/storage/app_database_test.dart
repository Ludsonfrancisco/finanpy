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
            uuid: '55555555-5555-4555-8555-555555555555',
            householdUuid: '11111111-1111-4111-8111-111111111111',
            financialOwnerUuid: '22222222-2222-4222-8222-222222222222',
            accountUuid: '33333333-3333-4333-8333-333333333333',
            categoryUuid: '44444444-4444-4444-8444-444444444444',
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
            uuid: '56666666-6666-4666-8666-666666666666',
            householdUuid: '11111111-1111-4111-8111-111111111111',
            financialOwnerUuid: '22222222-2222-4222-8222-222222222222',
            accountUuid: '36666666-6666-4666-8666-666666666666',
            categoryUuid: '44444444-4444-4444-8444-444444444444',
            description: 'Inválida',
            amountMinor: 100,
            date: DateTime.utc(2026, 8, 14),
            type: 'expense',
            version: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await expectLater(
      insert,
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'SQLite constraint',
          contains('FOREIGN KEY constraint failed'),
        ),
      ),
    );
  });

  test('schema v1 rejects an unknown owner type', () async {
    final insert = db
        .into(db.owners)
        .insert(
          OwnersCompanion.insert(
            uuid: '26666666-6666-4666-8666-666666666666',
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
            uuid: '11111111-1111-4111-8111-111111111111',
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
            householdUuid: '11111111-1111-4111-8111-111111111111',
            sessionDeviceUuid: '77777777-7777-4777-8777-777777777777',
          ),
        );

    await expectLater(insert, throwsA(isA<Exception>()));
  });

  test('schema v1 rejects a non-positive entity version', () async {
    await db
        .into(db.households)
        .insert(
          HouseholdsCompanion.insert(
            uuid: '11111111-1111-4111-8111-111111111111',
            name: 'Casa',
            updatedAt: now,
          ),
        );
    await db
        .into(db.owners)
        .insert(
          OwnersCompanion.insert(
            uuid: '22222222-2222-4222-8222-222222222222',
            type: 'self',
            name: 'Eu',
          ),
        );

    final insert = db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            uuid: '36666666-6666-4666-8666-666666666666',
            householdUuid: '11111111-1111-4111-8111-111111111111',
            financialOwnerUuid: '22222222-2222-4222-8222-222222222222',
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

  test('schema v1 rejects a negative transaction magnitude', () async {
    await _seedParents(db, now);
    final insert = db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            uuid: '57777777-7777-4777-8777-777777777777',
            householdUuid: '11111111-1111-4111-8111-111111111111',
            financialOwnerUuid: '22222222-2222-4222-8222-222222222222',
            accountUuid: '33333333-3333-4333-8333-333333333333',
            categoryUuid: '44444444-4444-4444-8444-444444444444',
            description: 'Inválida',
            amountMinor: -1,
            date: DateTime.utc(2026, 8, 14),
            type: 'expense',
            version: 1,
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
        accountUuid: 'b3333333-3333-4333-8333-333333333333',
        transactionAccountUuid: 'b6666666-6666-4666-8666-666666666666',
      );

      await expectLater(
        ledger.replaceBootstrap(
          invalid,
          now,
          'c7777777-7777-4777-8777-777777777777',
        ),
        throwsA(isA<Exception>()),
      );

      expect(await db.select(db.accounts).get(), hasLength(1));
      expect(
        (await db.select(db.accounts).getSingle()).uuid,
        'a3333333-3333-4333-8333-333333333333',
      );
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
        'c7777777-7777-4777-8777-777777777777',
      );

      expect(
        (await db.select(db.households).getSingle()).uuid,
        'b1111111-1111-4111-8111-111111111111',
      );
      expect(
        (await db.select(db.accounts).getSingle()).uuid,
        'b3333333-3333-4333-8333-333333333333',
      );
      expect(await db.select(db.transactions).get(), hasLength(1));
      expect(
        await ledger.readSyncMetadata(),
        isA<SyncMetadata>()
            .having((value) => value.cursor, 'cursor', 'cursor-after')
            .having(
              (value) => value.householdUuid,
              'householdUuid',
              'b1111111-1111-4111-8111-111111111111',
            )
            .having(
              (value) => value.sessionDeviceUuid,
              'sessionDeviceUuid',
              'c7777777-7777-4777-8777-777777777777',
            )
            .having((value) => value.lastSuccessAt, 'lastSuccessAt', now),
      );
    },
  );

  test(
    'replaceBootstrap rejects malformed UUIDs and rolls back cursor',
    () async {
      final ledger = DriftLocalLedger(db);
      await _seedOldLedger(db, now);

      await expectLater(
        ledger.replaceBootstrap(
          _bootstrap(
            cursor: 'cursor-invalid',
            accountUuid: 'not-a-uuid',
            transactionAccountUuid: 'not-a-uuid',
          ),
          now,
          'c7777777-7777-4777-8777-777777777777',
        ),
        throwsFormatException,
      );

      expect(
        (await db.select(db.accounts).getSingle()).uuid,
        'a3333333-3333-4333-8333-333333333333',
      );
      expect((await ledger.readSyncMetadata())?.cursor, 'cursor-before');
    },
  );

  test('applyDelta rejects malformed UUIDs without advancing cursor', () async {
    final ledger = DriftLocalLedger(db);
    await ledger.replaceBootstrap(
      _bootstrap(cursor: 'cursor-before'),
      now,
      '77777777-7777-4777-8777-777777777777',
    );

    await expectLater(
      ledger.applyDelta(
        SyncPage(
          changes: [
            SyncChangePayload(
              entityType: 'account',
              entityUuid: 'not-a-uuid',
              entityVersion: 1,
              operation: 'create',
              payload: _accountPayload(uuid: 'not-a-uuid'),
            ),
          ],
          cursor: 'cursor-invalid',
        ),
        now,
      ),
      throwsFormatException,
    );

    expect(await db.select(db.accounts).get(), hasLength(1));
    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-before');
  });

  test('replaceBootstrap requires RFC3339 timezone and rolls back', () async {
    final ledger = DriftLocalLedger(db);
    await _seedOldLedger(db, now);
    final payload = _bootstrap(cursor: 'cursor-invalid');
    payload.accounts.single['updated_at'] = '2026-08-14T12:00:00';

    await expectLater(
      ledger.replaceBootstrap(
        payload,
        now,
        'c7777777-7777-4777-8777-777777777777',
      ),
      throwsFormatException,
    );

    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-before');
  });

  test('replaceBootstrap rejects overflowing RFC3339 components', () async {
    final ledger = DriftLocalLedger(db);
    await _seedOldLedger(db, now);
    final payload = _bootstrap(cursor: 'cursor-invalid');
    payload.accounts.single['updated_at'] = '2026-02-30T12:00:00Z';

    await expectLater(
      ledger.replaceBootstrap(
        payload,
        now,
        'c7777777-7777-4777-8777-777777777777',
      ),
      throwsFormatException,
    );

    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-before');
  });

  test('replaceBootstrap normalizes RFC3339 offsets to UTC', () async {
    final ledger = DriftLocalLedger(db);
    final payload = _bootstrap(cursor: 'cursor-offset');
    payload.accounts.single['updated_at'] = '2026-08-14T09:30:00-03:00';

    await ledger.replaceBootstrap(
      payload,
      now,
      'c7777777-7777-4777-8777-777777777777',
    );

    expect(
      (await db.select(db.accounts).getSingle()).updatedAt,
      DateTime.utc(2026, 8, 14, 12, 30),
    );
  });

  test('replaceBootstrap rejects a negative transaction atomically', () async {
    final ledger = DriftLocalLedger(db);
    await _seedOldLedger(db, now);
    final payload = _bootstrap(cursor: 'cursor-invalid');
    payload.transactions.single['amount'] = '-1.00';

    await expectLater(
      ledger.replaceBootstrap(
        payload,
        now,
        'c7777777-7777-4777-8777-777777777777',
      ),
      throwsFormatException,
    );

    expect(
      (await db.select(db.accounts).getSingle()).uuid,
      'a3333333-3333-4333-8333-333333333333',
    );
    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-before');
  });

  test(
    'applyDelta rejects unknown entities without row or cursor changes',
    () async {
      final ledger = DriftLocalLedger(db);
      await ledger.replaceBootstrap(
        _bootstrap(cursor: 'cursor-before'),
        now,
        '77777777-7777-4777-8777-777777777777',
      );

      final page = SyncPage(
        changes: [
          SyncChangePayload(
            entityType: 'account',
            entityUuid: 'b3333333-3333-4333-8333-333333333333',
            entityVersion: 2,
            operation: 'update',
            payload: _accountPayload(name: 'Mutated', version: 2),
          ),
          const SyncChangePayload(
            entityType: 'unknown',
            entityUuid: 'b6666666-6666-4666-8666-666666666666',
            entityVersion: 1,
            operation: 'create',
            payload: {
              'uuid': 'b6666666-6666-4666-8666-666666666666',
              'version': 1,
            },
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

  test(
    'applyDelta rejects equal and older versions and preserves cursor',
    () async {
      final ledger = DriftLocalLedger(db);
      await ledger.replaceBootstrap(
        _bootstrap(cursor: 'cursor-before'),
        now,
        '77777777-7777-4777-8777-777777777777',
      );

      await ledger.applyDelta(
        SyncPage(
          changes: [
            SyncChangePayload(
              entityType: 'account',
              entityUuid: 'b3333333-3333-4333-8333-333333333333',
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
                entityUuid: 'b3333333-3333-4333-8333-333333333333',
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

      await expectLater(
        ledger.applyDelta(
          SyncPage(
            changes: [
              SyncChangePayload(
                entityType: 'account',
                entityUuid: 'b3333333-3333-4333-8333-333333333333',
                entityVersion: 1,
                operation: 'update',
                payload: _accountPayload(name: 'Older', version: 1),
              ),
            ],
            cursor: 'cursor-older',
          ),
          now.add(const Duration(minutes: 3)),
        ),
        throwsA(isA<StateError>()),
      );

      final account = await db.select(db.accounts).getSingle();
      expect(account.name, 'Atualizada');
      expect(account.version, 2);
      expect((await ledger.readSyncMetadata())?.cursor, 'cursor-v2');
    },
  );

  test('applyDelta canonicalizes uppercase UUIDs before updating', () async {
    final ledger = DriftLocalLedger(db);
    await ledger.replaceBootstrap(
      _bootstrap(cursor: 'cursor-before'),
      now,
      '77777777-7777-4777-8777-777777777777',
    );

    await ledger.applyDelta(
      SyncPage(
        changes: [
          SyncChangePayload(
            entityType: 'account',
            entityUuid: 'B3333333-3333-4333-8333-333333333333',
            entityVersion: 2,
            operation: 'update',
            payload: _accountPayload(
              uuid: 'B3333333-3333-4333-8333-333333333333',
              name: 'Atualizada',
              version: 2,
            ),
          ),
        ],
        cursor: 'cursor-uppercase',
      ),
      now.add(const Duration(minutes: 1)),
    );

    final accounts = await db.select(db.accounts).get();
    expect(accounts, hasLength(1));
    expect(accounts.single.uuid, 'b3333333-3333-4333-8333-333333333333');
    expect(accounts.single.name, 'Atualizada');
    expect(accounts.single.version, 2);
    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-uppercase');
  });

  test('applyDelta canonicalizes uppercase UUIDs before deleting', () async {
    final ledger = DriftLocalLedger(db);
    await ledger.replaceBootstrap(
      _bootstrap(cursor: 'cursor-before'),
      now,
      '77777777-7777-4777-8777-777777777777',
    );

    await ledger.applyDelta(
      const SyncPage(
        changes: [
          SyncChangePayload(
            entityType: 'transaction',
            entityUuid: 'B5555555-5555-4555-8555-555555555555',
            entityVersion: 2,
            operation: 'delete',
            payload: {
              'uuid': 'B5555555-5555-4555-8555-555555555555',
              'deleted': true,
            },
          ),
        ],
        cursor: 'cursor-uppercase',
      ),
      now.add(const Duration(minutes: 1)),
    );

    expect(await db.select(db.transactions).get(), isEmpty);
    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-uppercase');
  });

  test('applyDelta deletes a UUID and advances cursor last', () async {
    final ledger = DriftLocalLedger(db);
    await ledger.replaceBootstrap(
      _bootstrap(cursor: 'cursor-before'),
      now,
      '77777777-7777-4777-8777-777777777777',
    );

    await ledger.applyDelta(
      const SyncPage(
        changes: [
          SyncChangePayload(
            entityType: 'transaction',
            entityUuid: 'b5555555-5555-4555-8555-555555555555',
            entityVersion: 2,
            operation: 'delete',
            payload: {
              'uuid': 'b5555555-5555-4555-8555-555555555555',
              'deleted': true,
            },
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
          uuid: '11111111-1111-4111-8111-111111111111',
          name: 'Casa',
          updatedAt: now,
        ),
      );
  await db
      .into(db.owners)
      .insert(
        OwnersCompanion.insert(
          uuid: '22222222-2222-4222-8222-222222222222',
          type: 'self',
          name: 'Eu',
        ),
      );
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          uuid: '33333333-3333-4333-8333-333333333333',
          householdUuid: '11111111-1111-4111-8111-111111111111',
          financialOwnerUuid: '22222222-2222-4222-8222-222222222222',
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
          uuid: '44444444-4444-4444-8444-444444444444',
          householdUuid: '11111111-1111-4111-8111-111111111111',
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
          uuid: 'a1111111-1111-4111-8111-111111111111',
          name: 'Casa antiga',
          updatedAt: now,
        ),
      );
  await db
      .into(db.owners)
      .insert(
        OwnersCompanion.insert(
          uuid: 'a2222222-2222-4222-8222-222222222222',
          type: 'self',
          name: 'Eu',
        ),
      );
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          uuid: 'a3333333-3333-4333-8333-333333333333',
          householdUuid: 'a1111111-1111-4111-8111-111111111111',
          financialOwnerUuid: 'a2222222-2222-4222-8222-222222222222',
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
          householdUuid: 'a1111111-1111-4111-8111-111111111111',
          sessionDeviceUuid: 'a7777777-7777-4777-8777-777777777777',
          lastSuccessAt: Value(now),
        ),
      );
}

BootstrapPayload _bootstrap({
  required String cursor,
  String accountUuid = 'b3333333-3333-4333-8333-333333333333',
  String transactionAccountUuid = 'b3333333-3333-4333-8333-333333333333',
}) {
  return BootstrapPayload(
    household: {
      'uuid': 'b1111111-1111-4111-8111-111111111111',
      'name': 'Casa nova',
      'created_at': '2026-08-01T00:00:00Z',
      'updated_at': '2026-08-14T12:00:00Z',
    },
    owners: const [
      {
        'uuid': 'b2222222-2222-4222-8222-222222222222',
        'type': 'self',
        'name': 'Eu',
      },
    ],
    accounts: [_accountPayload(uuid: accountUuid)],
    categories: const [
      {
        'uuid': 'b4444444-4444-4444-8444-444444444444',
        'version': 1,
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-14T12:00:00Z',
        'household_uuid': 'b1111111-1111-4111-8111-111111111111',
        'name': 'Mercado',
        'type': 'expense',
        'color': '#000000',
        'icon': null,
      },
    ],
    transactions: [
      {
        'uuid': 'b5555555-5555-4555-8555-555555555555',
        'version': 1,
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-14T12:00:00Z',
        'household_uuid': 'b1111111-1111-4111-8111-111111111111',
        'financial_owner_uuid': 'b2222222-2222-4222-8222-222222222222',
        'account_uuid': transactionAccountUuid,
        'category_uuid': 'b4444444-4444-4444-8444-444444444444',
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
  String uuid = 'b3333333-3333-4333-8333-333333333333',
  String name = 'Nova conta',
  int version = 1,
}) {
  return {
    'uuid': uuid,
    'version': version,
    'created_at': '2026-08-01T00:00:00Z',
    'updated_at': '2026-08-14T12:00:00Z',
    'household_uuid': 'b1111111-1111-4111-8111-111111111111',
    'financial_owner_uuid': 'b2222222-2222-4222-8222-222222222222',
    'name': name,
    'type': 'checking',
    'initial_balance': '100.00',
    'currency': 'BRL',
  };
}
