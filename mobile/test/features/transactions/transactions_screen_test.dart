import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/app/value_visibility_controller.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/transactions/application/transactions_controller.dart';
import 'package:lar_finance/features/transactions/data/transactions_repository.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';
import 'package:lar_finance/features/transactions/presentation/transactions_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets(
    'TransactionsScreen renders list, search bar, summary card and owner selector',
    (tester) async {
      final fakeRepo = _MockTransactionsRepository();
      final syncState = SyncState(retry: () async => SyncResult.current);
      final controller = TransactionsController(
        repository: fakeRepo,
        syncState: syncState,
      );
      addTearDown(controller.dispose);

      await _pumpTransactions(tester, controller);

      expect(
        find.byKey(const Key('transactions-search-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('transactions-owner-selector')),
        findsOneWidget,
      );
      expect(find.text('RECEITAS'), findsOneWidget);
      expect(find.text('DESPESAS'), findsOneWidget);
      expect(find.text('BALANÇO'), findsOneWidget);
      expect(find.text('Supermercado'), findsOneWidget);
    },
  );

  testWidgets('TransactionsScreen tapping an item opens detail sheet', (
    tester,
  ) async {
    final fakeRepo = _MockTransactionsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = TransactionsController(
      repository: fakeRepo,
      syncState: syncState,
    );
    addTearDown(controller.dispose);

    await _pumpTransactions(tester, controller);

    final item = find.text('Supermercado');
    expect(item, findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(find.text('Detalhes da Movimentação'), findsOneWidget);
    expect(find.text('Supermercado'), findsWidgets);
    expect(find.text('Alimentação'), findsWidgets);
  });

  testWidgets(
    'TransactionsScreen renders empty state when no transactions exist',
    (tester) async {
      final emptyRepo = _EmptyTransactionsRepository();
      final syncState = SyncState(retry: () async => SyncResult.current);
      final controller = TransactionsController(
        repository: emptyRepo,
        syncState: syncState,
      );
      addTearDown(controller.dispose);

      await _pumpTransactions(tester, controller);

      expect(find.byKey(const Key('transactions-empty-state')), findsOneWidget);
      expect(find.text('Nenhuma movimentação encontrada'), findsOneWidget);
    },
  );
}

Future<void> _pumpTransactions(
  WidgetTester tester,
  TransactionsController controller, {
  ValueVisibilityController? visibilityController,
  Size viewportSize = const Size(800, 1200),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewportSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: LarTheme.light,
      home: Scaffold(
        body: TransactionsScreen(
          controller: controller,
          visibilityController: visibilityController,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _MockTransactionsRepository implements TransactionsRepository {
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
    return Stream.value(
      TransactionsSnapshot(
        scope: scope,
        groups: [
          TransactionGroup(
            date: DateTime.utc(2026, 8, 14),
            transactions: [
              TransactionItem(
                uuid: '50000000-0000-4000-8000-000000000001',
                description: 'Supermercado',
                categoryName: 'Alimentação',
                categoryColor: '#2F756A',
                categoryIcon: null,
                accountName: 'Nubank Conta',
                accountUuid: '30000000-0000-4000-8000-000000000001',
                ownerName: 'Ludson',
                ownerType: 'self',
                date: DateTime.utc(2026, 8, 14, 15, 30),
                type: TransactionType.expense,
                amountMinor: 25000,
                signedAmountMinor: -25000,
                updatedAt: DateTime.utc(2026, 8, 14, 15, 30),
              ),
            ],
            dayTotalIncomeMinor: 0,
            dayTotalExpenseMinor: 25000,
          ),
        ],
        totalCount: 1,
        totalIncomeMinor: 0,
        totalExpenseMinor: 25000,
        lastSyncedAt: DateTime.utc(2026, 8, 14),
        availableAccounts: [
          const TransactionFilterOption(
            uuid: '30000000-0000-4000-8000-000000000001',
            name: 'Nubank Conta',
          ),
        ],
        availableCategories: [
          const TransactionFilterOption(
            uuid: '40000000-0000-4000-8000-000000000001',
            name: 'Alimentação',
          ),
        ],
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

final class _EmptyTransactionsRepository implements TransactionsRepository {
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
    return Stream.value(
      TransactionsSnapshot(
        scope: scope,
        groups: const [],
        totalCount: 0,
        totalIncomeMinor: 0,
        totalExpenseMinor: 0,
        lastSyncedAt: null,
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
