// Drift resolves self-references in column checks to SQL columns.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

class Households extends Table {
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {uuid};
}

class Owners extends Table {
  TextColumn get uuid => text()();
  TextColumn get type =>
      text().check(type.isIn(const ['self', 'spouse', 'shared']))();
  TextColumn get name => text()();

  @override
  Set<Column<Object>> get primaryKey => {uuid};
}

class Accounts extends Table {
  TextColumn get uuid => text()();
  TextColumn get householdUuid => text().references(
    Households,
    #uuid,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get financialOwnerUuid => text().references(
    Owners,
    #uuid,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get name => text()();
  TextColumn get type => text().check(
    type.isIn(const [
      'checking',
      'savings',
      'cash',
      'credit',
      'investment',
      'other',
    ]),
  )();
  IntColumn get initialBalanceMinor => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get version => integer().check(version.isBiggerOrEqualValue(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {uuid};
}

class Categories extends Table {
  TextColumn get uuid => text()();
  TextColumn get householdUuid => text().references(
    Households,
    #uuid,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get name => text()();
  TextColumn get type => text().check(type.isIn(const ['income', 'expense']))();
  TextColumn get color => text()();
  TextColumn get icon => text().nullable()();
  IntColumn get version => integer().check(version.isBiggerOrEqualValue(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {uuid};
}

class Transactions extends Table {
  TextColumn get uuid => text()();
  TextColumn get householdUuid => text().references(
    Households,
    #uuid,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get financialOwnerUuid => text().references(
    Owners,
    #uuid,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get accountUuid => text().references(
    Accounts,
    #uuid,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get categoryUuid => text().references(
    Categories,
    #uuid,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get description => text()();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerOrEqualValue(0))();
  DateTimeColumn get date => dateTime()();
  TextColumn get type => text().check(type.isIn(const ['income', 'expense']))();
  IntColumn get version => integer().check(version.isBiggerOrEqualValue(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {uuid};
}

class SyncState extends Table {
  TextColumn get key => text()
      .withDefault(const Constant('ledger'))
      .check(key.equals('ledger'))();
  TextColumn get cursor => text()();
  TextColumn get householdUuid => text().references(
    Households,
    #uuid,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get sessionDeviceUuid => text()();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class LocalSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
