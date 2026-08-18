import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/features/transactions/application/transactions_controller.dart';
import 'package:lar_finance/features/transactions/data/transactions_repository.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';

void main() {
  test(
    'starts in loading, watches household transactions and updates state',
    () async {
      final fakeRepo = _FakeTransactionsRepository();
      final syncState = SyncState(retry: () async => SyncResult.current);
      final controller = TransactionsController(
        repository: fakeRepo,
        syncState: syncState,
      );

      expect(controller.state.isLoading, isTrue);
      expect(controller.state.snapshot, isNull);

      await controller.start();
      await pumpEventQueue();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.snapshot, isNotNull);
      expect(controller.state.snapshot!.totalCount, 2);

      controller.dispose();
    },
  );

  test(
    'updateSearch updates search filter and re-queries repository',
    () async {
      final fakeRepo = _FakeTransactionsRepository();
      final syncState = SyncState(retry: () async => SyncResult.current);
      final controller = TransactionsController(
        repository: fakeRepo,
        syncState: syncState,
      );

      await controller.start();
      await pumpEventQueue();

      await controller.updateSearch('café');
      await pumpEventQueue();

      expect(controller.state.filters.searchQuery, 'café');
      expect(fakeRepo.lastFilters?.searchQuery, 'café');

      controller.dispose();
    },
  );

  test('updateFilters and clearFilters work correctly', () async {
    final fakeRepo = _FakeTransactionsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = TransactionsController(
      repository: fakeRepo,
      syncState: syncState,
    );

    await controller.start();
    await pumpEventQueue();

    await controller.updateFilters(
      const TransactionFilters(type: TransactionType.expense),
    );
    await pumpEventQueue();

    expect(controller.state.filters.type, TransactionType.expense);

    await controller.clearFilters();
    await pumpEventQueue();

    expect(controller.state.filters.type, isNull);
    expect(controller.state.filters.searchQuery, isEmpty);

    controller.dispose();
  });
}

final class _FakeTransactionsRepository implements TransactionsRepository {
  TransactionFilters? lastFilters;

  @override
  Future<HomeOwnerScopes> readOwnerScopes() async => const HomeOwnerScopes(
    selfScope: OwnerScope.self('20000000-0000-4000-8000-000000000001'),
    spouseScope: OwnerScope.spouse('20000000-0000-4000-8000-000000000002'),
  );

  @override
  Stream<TransactionsSnapshot> watchTransactions(
    OwnerScope scope,
    TransactionFilters filters,
  ) {
    lastFilters = filters;
    return Stream.value(
      TransactionsSnapshot(
        scope: scope,
        groups: [
          TransactionGroup(
            date: DateTime.utc(2026, 8, 14),
            transactions: [
              TransactionItem(
                uuid: '50000000-0000-4000-8000-000000000001',
                description: 'Mercado',
                categoryName: 'Alimentação',
                categoryColor: '#2F756A',
                categoryIcon: null,
                accountName: 'Nubank',
                accountUuid: '30000000-0000-4000-8000-000000000001',
                ownerName: 'Ludson',
                ownerType: 'self',
                date: DateTime.utc(2026, 8, 14),
                type: TransactionType.expense,
                amountMinor: 15000,
                signedAmountMinor: -15000,
                updatedAt: DateTime.utc(2026, 8, 14),
              ),
              TransactionItem(
                uuid: '50000000-0000-4000-8000-000000000002',
                description: 'Salário',
                categoryName: 'Renda',
                categoryColor: '#2F756A',
                categoryIcon: null,
                accountName: 'Nubank',
                accountUuid: '30000000-0000-4000-8000-000000000001',
                ownerName: 'Ludson',
                ownerType: 'self',
                date: DateTime.utc(2026, 8, 14),
                type: TransactionType.income,
                amountMinor: 50000,
                signedAmountMinor: 50000,
                updatedAt: DateTime.utc(2026, 8, 14),
              ),
            ],
            dayTotalIncomeMinor: 50000,
            dayTotalExpenseMinor: 15000,
          ),
        ],
        totalCount: 2,
        totalIncomeMinor: 50000,
        totalExpenseMinor: 15000,
        lastSyncedAt: DateTime.utc(2026, 8, 14),
        availableAccounts: const [],
        availableCategories: const [],
      ),
    );
  }

  @override
  Future<List<TransactionFilterOption>> readAvailableAccounts() async =>
      const [];

  @override
  Future<List<TransactionCategoryOption>> readAvailableCategories(
    TransactionType? type,
  ) async => const [];

  @override
  Future<List<TransactionOwnerOption>> readAvailableOwners() async => const [];

  @override
  Future<String> createTransaction({
    required String description,
    required int amountMinor,
    required DateTime date,
    required TransactionType type,
    required String accountUuid,
    required String categoryUuid,
    required String financialOwnerUuid,
  }) async => 'tx-mock-uuid';

  @override
  Future<void> updateTransaction({
    required String uuid,
    required String description,
    required int amountMinor,
    required DateTime date,
    required TransactionType type,
    required String accountUuid,
    required String categoryUuid,
    required String financialOwnerUuid,
  }) async {}

  @override
  Future<void> deleteTransaction(String uuid) async {}
}
