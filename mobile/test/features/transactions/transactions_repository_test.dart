import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/features/home/domain/home_snapshot.dart';
import 'package:lar_finance/features/transactions/data/transactions_repository.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';

void main() {
  late AppDatabase database;
  late DriftTransactionsRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftTransactionsRepository(database);
    await _seedTransactionsData(database);
  });

  tearDown(() => database.close());

  test(
    'watchTransactions for household returns all grouped transactions and totals',
    () async {
      final snapshot = await repository
          .watchTransactions(
            const OwnerScope.household(),
            const TransactionFilters(),
          )
          .first;

      expect(snapshot.totalCount, 5);
      expect(snapshot.totalIncomeMinor, 10500); // 5000 + 4000 + 1500
      expect(snapshot.totalExpenseMinor, 3000); // 1000 + 2000
      expect(snapshot.groups, isNotEmpty);
      expect(snapshot.availableAccounts, hasLength(3));
      expect(snapshot.availableCategories, hasLength(2));
    },
  );

  test('watchTransactions filters by search query on description', () async {
    final snapshot = await repository
        .watchTransactions(
          const OwnerScope.household(),
          const TransactionFilters(searchQuery: 'mercado'),
        )
        .first;

    expect(snapshot.totalCount, 1);
    expect(
      snapshot.groups.first.transactions.first.description,
      'Mercado Central',
    );
  });

  test('watchTransactions filters by type (income vs expense)', () async {
    final incomeSnapshot = await repository
        .watchTransactions(
          const OwnerScope.household(),
          const TransactionFilters(type: TransactionType.income),
        )
        .first;

    expect(incomeSnapshot.totalCount, 3);
    expect(incomeSnapshot.totalIncomeMinor, 10500);
    expect(incomeSnapshot.totalExpenseMinor, 0);

    final expenseSnapshot = await repository
        .watchTransactions(
          const OwnerScope.household(),
          const TransactionFilters(type: TransactionType.expense),
        )
        .first;

    expect(expenseSnapshot.totalCount, 2);
    expect(expenseSnapshot.totalIncomeMinor, 0);
    expect(expenseSnapshot.totalExpenseMinor, 3000);
  });

  test('watchTransactions filters by owner scope', () async {
    final selfSnapshot = await repository
        .watchTransactions(
          const OwnerScope.self(_selfUuid),
          const TransactionFilters(),
        )
        .first;

    expect(selfSnapshot.totalCount, 2);
    expect(selfSnapshot.totalIncomeMinor, 5000);
    expect(selfSnapshot.totalExpenseMinor, 1000);
    expect(
      selfSnapshot.groups
          .expand((g) => g.transactions)
          .every((t) => t.ownerName == 'Ludson'),
      isTrue,
    );
  });

  test('watchTransactions filters by account UUID', () async {
    final snapshot = await repository
        .watchTransactions(
          const OwnerScope.household(),
          const TransactionFilters(accountUuid: _spouseAccountUuid),
        )
        .first;

    expect(snapshot.totalCount, 2);
    expect(
      snapshot.groups
          .expand((g) => g.transactions)
          .every((t) => t.accountUuid == _spouseAccountUuid),
      isTrue,
    );
  });

  test(
    'createTransaction inserts transaction and enqueues outbox mutation',
    () async {
      final newId = await repository.createTransaction(
        description: 'Padaria',
        amountMinor: 1550,
        date: DateTime.utc(2026, 8, 18),
        type: TransactionType.expense,
        accountUuid: _selfAccountUuid,
        categoryUuid: _expenseCategoryUuid,
        financialOwnerUuid: _selfUuid,
      );

      final inserted = await (database.select(
        database.transactions,
      )..where((t) => t.uuid.equals(newId))).getSingle();
      expect(inserted.description, 'Padaria');
      expect(inserted.amountMinor, 1550);
      expect(inserted.type, 'expense');

      final outbox = await (database.select(
        database.outboxMutations,
      )..where((o) => o.entityUuid.equals(newId))).getSingle();
      expect(outbox.action, 'create');
      expect(outbox.entity, 'transaction');
      expect(outbox.status, 'pending');
    },
  );

  test(
    'updateTransaction updates transaction and enqueues update outbox mutation',
    () async {
      const targetUuid = '50000000-0000-4000-8000-000000000001';
      await repository.updateTransaction(
        uuid: targetUuid,
        description: 'Salário Atualizado',
        amountMinor: 550000,
        date: DateTime.utc(2026, 8, 5),
        type: TransactionType.income,
        accountUuid: _selfAccountUuid,
        categoryUuid: _incomeCategoryUuid,
        financialOwnerUuid: _selfUuid,
      );

      final updated = await (database.select(
        database.transactions,
      )..where((t) => t.uuid.equals(targetUuid))).getSingle();
      expect(updated.description, 'Salário Atualizado');
      expect(updated.amountMinor, 550000);
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
    'deleteTransaction removes transaction and enqueues delete outbox mutation',
    () async {
      const targetUuid = '50000000-0000-4000-8000-000000000002';
      await repository.deleteTransaction(targetUuid);

      final exists = await (database.select(
        database.transactions,
      )..where((t) => t.uuid.equals(targetUuid))).getSingleOrNull();
      expect(exists, isNull);

      final outbox =
          await (database.select(database.outboxMutations)
                ..where((o) => o.entityUuid.equals(targetUuid))
                ..where((o) => o.action.equals('delete')))
              .getSingle();
      expect(outbox.action, 'delete');
    },
  );

  test('readAvailableAccounts, Categories and Owners return options', () async {
    final accounts = await repository.readAvailableAccounts();
    expect(accounts, hasLength(3));

    final categories = await repository.readAvailableCategories(
      TransactionType.expense,
    );
    expect(categories, hasLength(1));
    expect(categories.first.type, TransactionType.expense);

    final owners = await repository.readAvailableOwners();
    expect(owners, hasLength(3));
  });
}

const _householdUuid = '10000000-0000-4000-8000-000000000001';
const _selfUuid = '20000000-0000-4000-8000-000000000001';
const _spouseUuid = '20000000-0000-4000-8000-000000000002';
const _sharedUuid = '20000000-0000-4000-8000-000000000003';
const _selfAccountUuid = '30000000-0000-4000-8000-000000000001';
const _spouseAccountUuid = '30000000-0000-4000-8000-000000000002';
const _sharedAccountUuid = '30000000-0000-4000-8000-000000000003';
const _expenseCategoryUuid = '40000000-0000-4000-8000-000000000001';
const _incomeCategoryUuid = '40000000-0000-4000-8000-000000000002';

Future<void> _seedTransactionsData(AppDatabase db) async {
  final createdAt = DateTime.utc(2026, 8, 1);
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          uuid: _householdUuid,
          name: 'Lar',
          updatedAt: createdAt,
        ),
      );
  for (final owner in <(String, String, String)>[
    (_selfUuid, 'self', 'Ludson'),
    (_spouseUuid, 'spouse', 'Esposa'),
    (_sharedUuid, 'shared', 'Conjunto'),
  ]) {
    await db
        .into(db.owners)
        .insert(
          OwnersCompanion.insert(
            uuid: owner.$1,
            type: owner.$2,
            name: owner.$3,
          ),
        );
  }
  for (final account in <(String, String, String, int)>[
    (_selfAccountUuid, _selfUuid, 'Nubank Conta', 10000),
    (_spouseAccountUuid, _spouseUuid, 'Inter Conta', 20000),
    (_sharedAccountUuid, _sharedUuid, 'Reserva Conjunta', 30000),
  ]) {
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            uuid: account.$1,
            householdUuid: _householdUuid,
            financialOwnerUuid: account.$2,
            name: account.$3,
            type: 'checking',
            initialBalanceMinor: account.$4,
            currency: 'BRL',
            version: 1,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
  }
  for (final category in <(String, String, String)>[
    (_expenseCategoryUuid, 'expense', 'Casa'),
    (_incomeCategoryUuid, 'income', 'Salário'),
  ]) {
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            uuid: category.$1,
            householdUuid: _householdUuid,
            name: category.$3,
            type: category.$2,
            color: '#2F756A',
            version: 1,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
  }
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: '50000000-0000-4000-8000-000000000001',
          householdUuid: _householdUuid,
          financialOwnerUuid: _selfUuid,
          accountUuid: _selfAccountUuid,
          categoryUuid: _incomeCategoryUuid,
          description: 'Salário Ludson',
          amountMinor: 5000,
          date: DateTime.utc(2026, 8, 5),
          type: 'income',
          version: 1,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: '50000000-0000-4000-8000-000000000002',
          householdUuid: _householdUuid,
          financialOwnerUuid: _selfUuid,
          accountUuid: _selfAccountUuid,
          categoryUuid: _expenseCategoryUuid,
          description: 'Mercado Central',
          amountMinor: 1000,
          date: DateTime.utc(2026, 8, 6),
          type: 'expense',
          version: 1,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: '50000000-0000-4000-8000-000000000003',
          householdUuid: _householdUuid,
          financialOwnerUuid: _spouseUuid,
          accountUuid: _spouseAccountUuid,
          categoryUuid: _incomeCategoryUuid,
          description: 'Salário Esposa',
          amountMinor: 4000,
          date: DateTime.utc(2026, 8, 5),
          type: 'income',
          version: 1,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: '50000000-0000-4000-8000-000000000004',
          householdUuid: _householdUuid,
          financialOwnerUuid: _spouseUuid,
          accountUuid: _spouseAccountUuid,
          categoryUuid: _expenseCategoryUuid,
          description: 'Farmácia Popular',
          amountMinor: 2000,
          date: DateTime.utc(2026, 8, 7),
          type: 'expense',
          version: 1,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: '50000000-0000-4000-8000-000000000005',
          householdUuid: _householdUuid,
          financialOwnerUuid: _sharedUuid,
          accountUuid: _sharedAccountUuid,
          categoryUuid: _incomeCategoryUuid,
          description: 'Rendimento Poupança',
          amountMinor: 1500,
          date: DateTime.utc(2026, 8, 10),
          type: 'income',
          version: 1,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
}
