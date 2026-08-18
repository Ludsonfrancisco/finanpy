import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/app/value_visibility_controller.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/accounts/application/accounts_controller.dart';
import 'package:lar_finance/features/accounts/data/accounts_repository.dart';
import 'package:lar_finance/features/accounts/domain/accounts_models.dart';
import 'package:lar_finance/features/accounts/presentation/accounts_screen.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart'
    show TransactionOwnerOption;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('AccountsScreen renders account cards and total balance header', (
    tester,
  ) async {
    final fakeRepo = _MockAccountsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = AccountsController(
      repository: fakeRepo,
      syncState: syncState,
    );
    addTearDown(controller.dispose);

    await _pumpAccounts(tester, controller);

    expect(find.text('TOTAL EM CONTAS'), findsOneWidget);
    expect(find.text('Nubank Principal'), findsOneWidget);
    expect(find.text('Inter Reserva'), findsOneWidget);
    expect(find.byKey(const Key('accounts-privacy-toggle')), findsOneWidget);
    expect(find.byKey(const Key('accounts-owner-selector')), findsOneWidget);
  });

  testWidgets('AccountsScreen toggles privacy visibility', (tester) async {
    final fakeRepo = _MockAccountsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = AccountsController(
      repository: fakeRepo,
      syncState: syncState,
    );
    final visibilityRepo = _MockVisibilityRepository();
    final visibilityController = ValueVisibilityController(visibilityRepo);
    addTearDown(controller.dispose);

    await _pumpAccounts(
      tester,
      controller,
      visibilityController: visibilityController,
    );

    expect(find.textContaining('R\$'), findsWidgets);

    await tester.tap(find.byKey(const Key('accounts-privacy-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('R\$\u00a0••••••'), findsWidgets);
  });

  testWidgets('AccountsScreen renders empty state when no accounts exist', (
    tester,
  ) async {
    final emptyRepo = _EmptyAccountsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = AccountsController(
      repository: emptyRepo,
      syncState: syncState,
    );
    addTearDown(controller.dispose);

    await _pumpAccounts(tester, controller);

    expect(find.byKey(const Key('accounts-empty-state')), findsOneWidget);
    expect(find.text('Nenhuma conta encontrada'), findsOneWidget);
  });
}

Future<void> _pumpAccounts(
  WidgetTester tester,
  AccountsController controller, {
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
        body: AccountsScreen(
          controller: controller,
          visibilityController: visibilityController,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _MockAccountsRepository implements AccountsRepository {
  @override
  Future<HomeOwnerScopes> readOwnerScopes() async => const HomeOwnerScopes(
    selfScope: OwnerScope.self('20000000-0000-4000-8000-000000000001'),
    spouseScope: OwnerScope.spouse('20000000-0000-4000-8000-000000000002'),
  );

  @override
  Stream<AccountsSnapshot> watchAccounts(OwnerScope scope) {
    return Stream.value(
      AccountsSnapshot(
        scope: scope,
        accounts: [
          AccountItem(
            uuid: '30000000-0000-4000-8000-000000000001',
            name: 'Nubank Principal',
            type: AccountType.checking,
            initialBalanceMinor: 10000,
            currentBalanceMinor: 15450,
            currency: 'BRL',
            ownerName: 'Ludson',
            ownerType: 'self',
            updatedAt: DateTime.utc(2026, 8, 14, 10, 30),
          ),
          AccountItem(
            uuid: '30000000-0000-4000-8000-000000000002',
            name: 'Inter Reserva',
            type: AccountType.savings,
            initialBalanceMinor: 20000,
            currentBalanceMinor: 25000,
            currency: 'BRL',
            ownerName: 'Esposa',
            ownerType: 'spouse',
            updatedAt: DateTime.utc(2026, 8, 14, 11, 00),
          ),
        ],
        totalBalanceMinor: 40450,
        lastSyncedAt: DateTime.utc(2026, 8, 14, 12),
        hasAccountData: true,
      ),
    );
  }

  @override
  Future<List<TransactionOwnerOption>> readAvailableOwners() async => const [];

  @override
  Future<String> createAccount({
    required String name,
    required AccountType type,
    required int initialBalanceMinor,
    required String financialOwnerUuid,
  }) async => 'acc-mock-uuid';
}

final class _EmptyAccountsRepository implements AccountsRepository {
  @override
  Future<HomeOwnerScopes> readOwnerScopes() async => const HomeOwnerScopes(
    selfScope: OwnerScope.self('20000000-0000-4000-8000-000000000001'),
    spouseScope: OwnerScope.spouse('20000000-0000-4000-8000-000000000002'),
  );

  @override
  Stream<AccountsSnapshot> watchAccounts(OwnerScope scope) {
    return Stream.value(
      AccountsSnapshot(
        scope: scope,
        accounts: const [],
        totalBalanceMinor: 0,
        lastSyncedAt: null,
        hasAccountData: false,
      ),
    );
  }

  @override
  Future<List<TransactionOwnerOption>> readAvailableOwners() async => const [];

  @override
  Future<String> createAccount({
    required String name,
    required AccountType type,
    required int initialBalanceMinor,
    required String financialOwnerUuid,
  }) async => 'acc-mock-uuid';
}

final class _MockVisibilityRepository implements ValueVisibilityRepository {
  bool? _hidden = false;

  @override
  Future<bool?> readValuesHidden() async => _hidden;

  @override
  Future<void> writeValuesHidden(bool hidden) async {
    _hidden = hidden;
  }
}
