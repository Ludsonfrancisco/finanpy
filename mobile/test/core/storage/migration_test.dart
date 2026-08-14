import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/storage/app_database.dart';

void main() {
  test('schema v1 preserves settings and ledger rows after reopen', () async {
    final directory = await Directory.systemTemp.createTemp('lar-finance-v1-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}ledger.sqlite',
    );
    final now = DateTime.utc(2026, 8, 14, 12);

    var db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.localSettings)
        .insert(
          LocalSettingsCompanion.insert(key: 'theme_mode', value: 'dark'),
        );
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
            initialBalanceMinor: 12345,
            currency: 'BRL',
            version: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final setting = await db.select(db.localSettings).getSingle();
    final household = await db.select(db.households).getSingle();
    final account = await db.select(db.accounts).getSingle();
    expect(setting.value, 'dark');
    expect(household.uuid, 'household-1');
    expect(account.initialBalanceMinor, 12345);
    expect(
      await db
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((row) => row.read<int>('user_version')),
      1,
    );
  });
}
