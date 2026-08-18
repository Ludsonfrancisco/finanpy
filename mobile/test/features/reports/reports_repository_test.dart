import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/features/home/domain/home_snapshot.dart';
import 'package:lar_finance/features/reports/data/reports_repository.dart';
import 'package:lar_finance/features/reports/domain/reports_models.dart';

void main() {
  late AppDatabase database;
  late DriftReportsRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftReportsRepository(database);
    await _seedReportsData(database);
  });

  tearDown(() => database.close());

  test(
    'watchReports calculates totals, distributions and monthly flows for household',
    () async {
      final summary = await repository
          .watchReports(const OwnerScope.household(), ReportPeriod.yearToDate)
          .first;

      expect(summary.totalIncomeMinor, 800000); // 8000.00
      expect(summary.totalExpenseMinor, 300000); // 3000.00
      expect(summary.netBalanceMinor, 500000); // 5000.00
      expect(summary.savingsRate, closeTo(62.5, 0.1)); // (5000 / 8000) * 100

      expect(summary.categoryDistributions, hasLength(2));
      final cat1 = summary.categoryDistributions.first;
      expect(cat1.categoryName, 'Alimentação');
      expect(cat1.totalMinor, 200000);
      expect(cat1.percentage, closeTo(66.67, 0.1));

      final cat2 = summary.categoryDistributions[1];
      expect(cat2.categoryName, 'Lazer');
      expect(cat2.totalMinor, 100000);
      expect(cat2.percentage, closeTo(33.33, 0.1));

      expect(summary.monthlyFlows, hasLength(6));
    },
  );

  test('watchReports filters totals by self owner scope', () async {
    final summary = await repository
        .watchReports(const OwnerScope.self(_selfUuid), ReportPeriod.yearToDate)
        .first;

    expect(summary.totalIncomeMinor, 800000);
    expect(summary.totalExpenseMinor, 200000); // Only txs by self
    expect(summary.netBalanceMinor, 600000);
  });

  test('readOwnerScopes returns self and spouse scopes', () async {
    final scopes = await repository.readOwnerScopes();
    expect(scopes.selfScope.kind, OwnerScopeKind.selfOwner);
    expect(scopes.selfScope.ownerUuid, _selfUuid);
    expect(scopes.spouseScope.kind, OwnerScopeKind.spouse);
    expect(scopes.spouseScope.ownerUuid, _spouseUuid);
  });
}

const _householdUuid = '10000000-0000-4000-8000-000000000001';
const _selfUuid = '20000000-0000-4000-8000-000000000001';
const _spouseUuid = '20000000-0000-4000-8000-000000000002';
const _accountUuid = '30000000-0000-4000-8000-000000000001';
const _expenseCat1Uuid = '40000000-0000-4000-8000-000000000001';
const _expenseCat2Uuid = '40000000-0000-4000-8000-000000000002';
const _incomeCatUuid = '40000000-0000-4000-8000-000000000003';

Future<void> _seedReportsData(AppDatabase db) async {
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
      .into(db.owners)
      .insert(
        OwnersCompanion.insert(
          uuid: _spouseUuid,
          type: 'spouse',
          name: 'Esposa',
        ),
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
          initialBalanceMinor: 100000,
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

  // Receita de 8000.00
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: 'tx-inc-1',
          householdUuid: _householdUuid,
          financialOwnerUuid: _selfUuid,
          accountUuid: _accountUuid,
          categoryUuid: _incomeCatUuid,
          description: 'Salário Mensal',
          amountMinor: 800000,
          date: now,
          type: 'income',
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

  // Despesa 1: Alimentação 2000.00 (Self)
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: 'tx-exp-1',
          householdUuid: _householdUuid,
          financialOwnerUuid: _selfUuid,
          accountUuid: _accountUuid,
          categoryUuid: _expenseCat1Uuid,
          description: 'Mercado',
          amountMinor: 200000,
          date: now,
          type: 'expense',
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

  // Despesa 2: Lazer 1000.00 (Spouse)
  await db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          uuid: 'tx-exp-2',
          householdUuid: _householdUuid,
          financialOwnerUuid: _spouseUuid,
          accountUuid: _accountUuid,
          categoryUuid: _expenseCat2Uuid,
          description: 'Cinema e Restaurante',
          amountMinor: 100000,
          date: now,
          type: 'expense',
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
}
