import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/features/accounts/data/accounts_repository.dart';
import 'package:lar_finance/features/accounts/domain/accounts_models.dart';
import 'package:lar_finance/features/home/domain/home_snapshot.dart';

void main() {
  late AppDatabase database;
  late DriftAccountsRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftAccountsRepository(database);
    await _seedHousehold(database);
  });

  tearDown(() => database.close());

  test('readOwnerScopes returns self and spouse scopes correctly', () async {
    final scopes = await repository.readOwnerScopes();
    expect(scopes.selfScope.ownerUuid, _selfUuid);
    expect(scopes.spouseScope.ownerUuid, _spouseUuid);
  });

  test(
    'watchAccounts for household calculates current balances and overall total',
    () async {
      final snapshot = await repository
          .watchAccounts(const OwnerScope.household())
          .first;

      expect(snapshot.hasAccountData, isTrue);
      expect(snapshot.accounts, hasLength(3));

      // Self account: 10000 (initial) + 5000 (income) - 1000 (expense) = 14000
      final selfAcc = snapshot.accounts.firstWhere(
        (a) => a.uuid == _selfAccountUuid,
      );
      expect(selfAcc.initialBalanceMinor, 10000);
      expect(selfAcc.currentBalanceMinor, 14000);

      // Spouse account: 20000 (initial) + 4000 (income) - 2000 (expense) = 22000
      final spouseAcc = snapshot.accounts.firstWhere(
        (a) => a.uuid == _spouseAccountUuid,
      );
      expect(spouseAcc.currentBalanceMinor, 22000);

      // Shared account: 30000 (initial) + 1500 (income) = 31500
      final sharedAcc = snapshot.accounts.firstWhere(
        (a) => a.uuid == _sharedAccountUuid,
      );
      expect(sharedAcc.currentBalanceMinor, 31500);

      // Total balance: 14000 + 22000 + 31500 = 67500
      expect(snapshot.totalBalanceMinor, 67500);
    },
  );

  test(
    'watchAccounts for self and spouse filters by financial owner',
    () async {
      final selfSnapshot = await repository
          .watchAccounts(const OwnerScope.self(_selfUuid))
          .first;
      expect(selfSnapshot.accounts, hasLength(1));
      expect(selfSnapshot.accounts.first.ownerName, 'Ludson');
      expect(selfSnapshot.totalBalanceMinor, 14000);

      final spouseSnapshot = await repository
          .watchAccounts(const OwnerScope.spouse(_spouseUuid))
          .first;
      expect(spouseSnapshot.accounts, hasLength(1));
      expect(spouseSnapshot.accounts.first.ownerName, 'Esposa');
      expect(spouseSnapshot.totalBalanceMinor, 22000);
    },
  );

  test(
    'watchAccounts returns hasAccountData false when no accounts exist',
    () async {
      final emptyDb = AppDatabase(NativeDatabase.memory());
      final emptyRepo = DriftAccountsRepository(emptyDb);
      final snapshot = await emptyRepo
          .watchAccounts(const OwnerScope.household())
          .first;
      expect(snapshot.hasAccountData, isFalse);
      expect(snapshot.accounts, isEmpty);
      expect(snapshot.totalBalanceMinor, 0);
      await emptyDb.close();
    },
  );

  test('createAccount inserts account and enqueues outbox mutation', () async {
    final newId = await repository.createAccount(
      name: 'Itaú Cartão',
      type: AccountType.checking,
      initialBalanceMinor: 5000,
      financialOwnerUuid: _selfUuid,
    );

    final inserted = await (database.select(
      database.accounts,
    )..where((a) => a.uuid.equals(newId))).getSingle();
    expect(inserted.name, 'Itaú Cartão');
    expect(inserted.initialBalanceMinor, 5000);

    final outbox = await (database.select(
      database.outboxMutations,
    )..where((o) => o.entityUuid.equals(newId))).getSingle();
    expect(outbox.action, 'create');
    expect(outbox.entity, 'account');
    expect(outbox.status, 'pending');
  });

  test('readAvailableOwners returns household owners', () async {
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
          description: 'Mercado',
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
          description: 'Farmácia',
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
          description: 'Rendimento',
          amountMinor: 1500,
          date: DateTime.utc(2026, 8, 10),
          type: 'income',
          version: 1,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
}
