import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/features/home/data/home_repository.dart';
import 'package:lar_finance/features/home/domain/home_snapshot.dart';

void main() {
  late AppDatabase database;
  late DriftHomeRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHomeRepository(database);
    await _seedHousehold(database);
  });

  tearDown(() => database.close());

  test(
    'Lar soma saldos iniciais uma vez e inclui Eu Esposa e Conjunto',
    () async {
      final snapshot = await repository
          .watchSnapshot(
            const OwnerScope.household(),
            DateTime(2026, 8, 14, 12),
          )
          .first;

      expect(snapshot.balanceMinor, 67500);
      expect(snapshot.monthExpenseMinor, 3000);
      expect(snapshot.upcomingCommitmentMinor, 4500);
      expect(snapshot.hasAccountData, isTrue);
    },
  );

  test('Eu e Esposa isolam lançamentos e contas de Conjunto', () async {
    final self = await repository
        .watchSnapshot(
          const OwnerScope.self(_selfUuid),
          DateTime(2026, 8, 14, 12),
        )
        .first;
    final spouse = await repository
        .watchSnapshot(
          const OwnerScope.spouse(_spouseUuid),
          DateTime(2026, 8, 14, 12),
        )
        .first;

    expect(self.balanceMinor, 14000);
    expect(self.monthExpenseMinor, 1000);
    expect(self.upcomingCommitmentMinor, 1000);
    expect(spouse.balanceMinor, 22000);
    expect(spouse.monthExpenseMinor, 2000);
    expect(spouse.upcomingCommitmentMinor, 2000);
    expect(
      self.recentTransactions.map((transaction) => transaction.ownerName),
      everyElement('Ludson'),
    );
    expect(
      spouse.recentTransactions.map((transaction) => transaction.ownerName),
      everyElement('Esposa'),
    );
  });

  test(
    'recentes usam date updatedAt e uuid descendentes e limitam em cinco',
    () async {
      final snapshot = await repository
          .watchSnapshot(
            const OwnerScope.household(),
            DateTime(2026, 8, 14, 12),
          )
          .first;

      expect(snapshot.recentTransactions, hasLength(5));
      expect(snapshot.recentTransactions.first.uuid, _sharedExpenseUuid);
      expect(snapshot.recentTransactions.last.uuid, _spouseIncomeUuid);
    },
  );

  test('recentes preservam o tipo explícito para valores zero', () async {
    final createdAt = DateTime.utc(2026, 9, 2, 10);
    for (final transaction in <(String, String)>[
      ('50000000-0000-4000-8000-000000000010', 'income'),
      ('50000000-0000-4000-8000-000000000011', 'expense'),
    ]) {
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              uuid: transaction.$1,
              householdUuid: _householdUuid,
              financialOwnerUuid: _selfUuid,
              accountUuid: _selfAccountUuid,
              categoryUuid: transaction.$2 == 'expense'
                  ? _expenseCategoryUuid
                  : _incomeCategoryUuid,
              description: '${transaction.$2} zero',
              amountMinor: 0,
              date: createdAt,
              type: transaction.$2,
              version: 1,
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          );
    }

    final snapshot = await repository
        .watchSnapshot(const OwnerScope.household(), DateTime(2026, 9, 2, 12))
        .first;

    expect(snapshot.recentTransactions[0].type, HomeTransactionType.expense);
    expect(snapshot.recentTransactions[1].type, HomeTransactionType.income);
    expect(snapshot.recentTransactions.take(2), everyElement(isZeroAmount));
  });

  test(
    'cache sem contas preserva a ausência em vez de presumir saldo zero',
    () async {
      await database.delete(database.transactions).go();
      await database.delete(database.accounts).go();

      final snapshot = await repository
          .watchSnapshot(
            const OwnerScope.household(),
            DateTime(2026, 8, 14, 12),
          )
          .first;

      expect(snapshot.hasAccountData, isFalse);
      expect(snapshot.lastSyncedAt, DateTime.utc(2026, 8, 14, 11));
    },
  );

  test('resolve somente os escopos individuais reais do banco local', () async {
    final scopes = await repository.readOwnerScopes();

    expect(scopes.selfScope.ownerUuid, _selfUuid);
    expect(scopes.spouseScope.ownerUuid, _spouseUuid);
  });
}

final isZeroAmount = isA<HomeTransaction>().having(
  (transaction) => transaction.signedAmountMinor,
  'signedAmountMinor',
  0,
);

const _householdUuid = '10000000-0000-4000-8000-000000000001';
const _selfUuid = '20000000-0000-4000-8000-000000000001';
const _spouseUuid = '20000000-0000-4000-8000-000000000002';
const _sharedUuid = '20000000-0000-4000-8000-000000000003';
const _selfAccountUuid = '30000000-0000-4000-8000-000000000001';
const _spouseAccountUuid = '30000000-0000-4000-8000-000000000002';
const _sharedAccountUuid = '30000000-0000-4000-8000-000000000003';
const _expenseCategoryUuid = '40000000-0000-4000-8000-000000000001';
const _incomeCategoryUuid = '40000000-0000-4000-8000-000000000002';
const _selfIncomeUuid = '50000000-0000-4000-8000-000000000001';
const _spouseIncomeUuid = '50000000-0000-4000-8000-000000000002';
const _sharedIncomeUuid = '50000000-0000-4000-8000-000000000003';
const _selfExpenseUuid = '50000000-0000-4000-8000-000000000004';
const _spouseExpenseUuid = '50000000-0000-4000-8000-000000000005';
const _sharedExpenseUuid = '50000000-0000-4000-8000-000000000006';

Future<void> _seedHousehold(AppDatabase db) async {
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
  for (final account in <(String, String, int)>[
    (_selfAccountUuid, _selfUuid, 10000),
    (_spouseAccountUuid, _spouseUuid, 20000),
    (_sharedAccountUuid, _sharedUuid, 30000),
  ]) {
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            uuid: account.$1,
            householdUuid: _householdUuid,
            financialOwnerUuid: account.$2,
            name: 'Conta',
            type: 'checking',
            initialBalanceMinor: account.$3,
            currency: 'BRL',
            version: 1,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
  }
  for (final category in <(String, String, String)>[
    (_expenseCategoryUuid, 'expense', 'Casa'),
    (_incomeCategoryUuid, 'income', 'Receita'),
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
  final transactions =
      <
        ({
          String uuid,
          String owner,
          String account,
          String type,
          int amount,
          DateTime date,
          DateTime updatedAt,
        })
      >[
        (
          uuid: _selfIncomeUuid,
          owner: _selfUuid,
          account: _selfAccountUuid,
          type: 'income',
          amount: 5000,
          date: DateTime.utc(2026, 8, 10),
          updatedAt: DateTime.utc(2026, 8, 10, 10),
        ),
        (
          uuid: _spouseIncomeUuid,
          owner: _spouseUuid,
          account: _spouseAccountUuid,
          type: 'income',
          amount: 4000,
          date: DateTime.utc(2026, 8, 11),
          updatedAt: DateTime.utc(2026, 8, 11, 10),
        ),
        (
          uuid: _sharedIncomeUuid,
          owner: _sharedUuid,
          account: _sharedAccountUuid,
          type: 'income',
          amount: 3000,
          date: DateTime.utc(2026, 8, 12),
          updatedAt: DateTime.utc(2026, 8, 12, 10),
        ),
        (
          uuid: _selfExpenseUuid,
          owner: _selfUuid,
          account: _selfAccountUuid,
          type: 'expense',
          amount: 1000,
          date: DateTime.utc(2026, 8, 15),
          updatedAt: DateTime.utc(2026, 8, 15, 10),
        ),
        (
          uuid: _spouseExpenseUuid,
          owner: _spouseUuid,
          account: _spouseAccountUuid,
          type: 'expense',
          amount: 2000,
          date: DateTime.utc(2026, 8, 16),
          updatedAt: DateTime.utc(2026, 8, 16, 10),
        ),
        (
          uuid: _sharedExpenseUuid,
          owner: _sharedUuid,
          account: _sharedAccountUuid,
          type: 'expense',
          amount: 1500,
          date: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1, 10),
        ),
      ];
  for (final transaction in transactions) {
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            uuid: transaction.uuid,
            householdUuid: _householdUuid,
            financialOwnerUuid: transaction.owner,
            accountUuid: transaction.account,
            categoryUuid: transaction.type == 'expense'
                ? _expenseCategoryUuid
                : _incomeCategoryUuid,
            description: transaction.uuid,
            amountMinor: transaction.amount,
            date: transaction.date,
            type: transaction.type,
            version: 1,
            createdAt: transaction.updatedAt,
            updatedAt: transaction.updatedAt,
          ),
        );
  }
  await db
      .into(db.syncState)
      .insert(
        SyncStateCompanion.insert(
          cursor: 'cursor',
          householdUuid: _householdUuid,
          sessionDeviceUuid: '70000000-0000-4000-8000-000000000001',
          lastSuccessAt: Value(DateTime.utc(2026, 8, 14, 11)),
        ),
      );
}
