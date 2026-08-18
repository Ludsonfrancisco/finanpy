import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/features/categories/data/categories_repository.dart';
import 'package:lar_finance/features/categories/domain/categories_models.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';

void main() {
  late AppDatabase database;
  late DriftCategoriesRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftCategoriesRepository(database);
    await _seedCategoriesData(database);
  });

  tearDown(() => database.close());

  test(
    'watchCategories returns all categories with transaction count',
    () async {
      final snapshot = await repository.watchCategories().first;

      expect(snapshot.totalCount, 3);
      expect(snapshot.incomeCategories, hasLength(1));
      expect(snapshot.expenseCategories, hasLength(2));

      final alimentacao = snapshot.categories.firstWhere(
        (c) => c.name == 'Alimentação',
      );
      expect(alimentacao.transactionCount, 2);
      expect(alimentacao.type, TransactionType.expense);
      expect(alimentacao.color, '#2F756A');

      final lazer = snapshot.categories.firstWhere((c) => c.name == 'Lazer');
      expect(lazer.transactionCount, 0);
    },
  );

  test('watchCategories filters by type and searchQuery', () async {
    final incomeOnly = await repository
        .watchCategories(const CategoryFilters(type: TransactionType.income))
        .first;
    expect(incomeOnly.totalCount, 1);
    expect(incomeOnly.categories.first.name, 'Salário');

    final searchLazer = await repository
        .watchCategories(const CategoryFilters(searchQuery: 'lazer'))
        .first;
    expect(searchLazer.totalCount, 1);
    expect(searchLazer.categories.first.name, 'Lazer');
  });

  test(
    'createCategory inserts into categories and enqueues outbox mutation',
    () async {
      final newId = await repository.createCategory(
        name: 'Educação',
        type: TransactionType.expense,
        color: '#1E3A8A',
        icon: 'school',
      );

      final inserted = await (database.select(
        database.categories,
      )..where((c) => c.uuid.equals(newId))).getSingle();
      expect(inserted.name, 'Educação');
      expect(inserted.color, '#1E3A8A');
      expect(inserted.icon, 'school');

      final outbox = await (database.select(
        database.outboxMutations,
      )..where((o) => o.entityUuid.equals(newId))).getSingle();
      expect(outbox.action, 'create');
      expect(outbox.entity, 'category');
      expect(outbox.status, 'pending');
    },
  );

  test(
    'updateCategory updates category and enqueues outbox update mutation',
    () async {
      const targetUuid = _expenseCat1Uuid;
      await repository.updateCategory(
        uuid: targetUuid,
        name: 'Supermercado & Feira',
        type: TransactionType.expense,
        color: '#B8534F',
      );

      final updated = await (database.select(
        database.categories,
      )..where((c) => c.uuid.equals(targetUuid))).getSingle();
      expect(updated.name, 'Supermercado & Feira');
      expect(updated.color, '#B8534F');
      expect(updated.version, 2);

      final outbox =
          await (database.select(database.outboxMutations)
                ..where((o) => o.entityUuid.equals(targetUuid))
                ..where((o) => o.action.equals('update')))
              .getSingle();
      expect(outbox.expectedVersion, 1);
    },
  );

  test(
    'deleteCategory deletes category and enqueues outbox delete mutation',
    () async {
      const targetUuid = _expenseCat2Uuid;
      await repository.deleteCategory(targetUuid);

      final exists = await (database.select(
        database.categories,
      )..where((c) => c.uuid.equals(targetUuid))).getSingleOrNull();
      expect(exists, isNull);

      final outbox =
          await (database.select(database.outboxMutations)
                ..where((o) => o.entityUuid.equals(targetUuid))
                ..where((o) => o.action.equals('delete')))
              .getSingle();
      expect(outbox.action, 'delete');
    },
  );
}

const _householdUuid = '10000000-0000-4000-8000-000000000001';
const _selfUuid = '20000000-0000-4000-8000-000000000001';
const _accountUuid = '30000000-0000-4000-8000-000000000001';
const _expenseCat1Uuid = '40000000-0000-4000-8000-000000000001';
const _expenseCat2Uuid = '40000000-0000-4000-8000-000000000002';
const _incomeCatUuid = '40000000-0000-4000-8000-000000000003';

Future<void> _seedCategoriesData(AppDatabase db) async {
  final now = DateTime.utc(2026, 8, 1);
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          uuid: _householdUuid,
          name: 'Lar',
          updatedAt: now,
        ),
      );
  await db
      .into(db.owners)
      .insert(
        OwnersCompanion.insert(uuid: _selfUuid, type: 'self', name: 'Ludson'),
      );
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          uuid: _accountUuid,
          householdUuid: _householdUuid,
          financialOwnerUuid: _selfUuid,
          name: 'Nubank',
          type: 'checking',
          initialBalanceMinor: 10000,
          currency: 'BRL',
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

  for (final cat in [
    (_expenseCat1Uuid, 'Alimentação', 'expense', '#2F756A'),
    (_expenseCat2Uuid, 'Lazer', 'expense', '#C7A35A'),
    (_incomeCatUuid, 'Salário', 'income', '#2F756A'),
  ]) {
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            uuid: cat.$1,
            householdUuid: _householdUuid,
            name: cat.$2,
            type: cat.$3,
            color: cat.$4,
            version: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  // 2 transações para Alimentação
  for (final tx in ['tx-1', 'tx-2']) {
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            uuid: tx,
            householdUuid: _householdUuid,
            financialOwnerUuid: _selfUuid,
            accountUuid: _accountUuid,
            categoryUuid: _expenseCat1Uuid,
            description: 'Compra $tx',
            amountMinor: 5000,
            date: now,
            type: 'expense',
            version: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
