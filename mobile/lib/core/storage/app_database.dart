import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Households,
    Owners,
    Accounts,
    Categories,
    Transactions,
    SyncState,
    LocalSettings,
    OutboxMutations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(syncState, syncState.sessionGeneration);
      }
      if (from < 3) {
        await migrator.addColumn(syncState, syncState.sessionIdentity);
      }
      if (from < 4) {
        await migrator.createTable(outboxMutations);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
