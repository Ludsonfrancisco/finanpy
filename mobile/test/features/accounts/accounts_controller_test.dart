import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/features/accounts/application/accounts_controller.dart';
import 'package:lar_finance/features/accounts/data/accounts_repository.dart';
import 'package:lar_finance/features/accounts/domain/accounts_models.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart'
    show TransactionOwnerOption;

void main() {
  test(
    'starts in loading, watches household scope and updates state',
    () async {
      final fakeRepo = _FakeAccountsRepository();
      final syncState = SyncState(retry: () async => SyncResult.current);
      final controller = AccountsController(
        repository: fakeRepo,
        syncState: syncState,
      );

      expect(controller.state.isLoading, isTrue);
      expect(controller.state.snapshot, isNull);

      await controller.start();
      await pumpEventQueue();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.snapshot, isNotNull);
      expect(controller.state.selectedScopeIndex, 0);
      expect(controller.state.snapshot!.totalBalanceMinor, 50000);

      controller.dispose();
    },
  );

  test('select updates scope and emits new snapshot', () async {
    final fakeRepo = _FakeAccountsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = AccountsController(
      repository: fakeRepo,
      syncState: syncState,
    );

    await controller.start();
    await pumpEventQueue();

    await controller.select(1);
    await pumpEventQueue();

    expect(controller.state.selectedScopeIndex, 1);
    expect(controller.state.snapshot!.scope.kind, OwnerScopeKind.selfOwner);
    expect(controller.state.snapshot!.totalBalanceMinor, 20000);

    await controller.select(2);
    await pumpEventQueue();

    expect(controller.state.selectedScopeIndex, 2);
    expect(controller.state.snapshot!.scope.kind, OwnerScopeKind.spouse);
    expect(controller.state.snapshot!.totalBalanceMinor, 30000);

    controller.dispose();
  });

  test('handles repository error gracefully', () async {
    final failingRepo = _FailingAccountsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = AccountsController(
      repository: failingRepo,
      syncState: syncState,
    );

    await controller.start();
    await pumpEventQueue();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.error, isNotNull);

    controller.dispose();
  });
}

final class _FakeAccountsRepository implements AccountsRepository {
  @override
  Future<HomeOwnerScopes> readOwnerScopes() async => const HomeOwnerScopes(
    selfScope: OwnerScope.self('20000000-0000-4000-8000-000000000001'),
    spouseScope: OwnerScope.spouse('20000000-0000-4000-8000-000000000002'),
  );

  @override
  Stream<AccountsSnapshot> watchAccounts(OwnerScope scope) {
    final total = switch (scope.kind) {
      OwnerScopeKind.household => 50000,
      OwnerScopeKind.selfOwner => 20000,
      OwnerScopeKind.spouse => 30000,
    };
    return Stream.value(
      AccountsSnapshot(
        scope: scope,
        accounts: [
          AccountItem(
            uuid: '30000000-0000-4000-8000-000000000001',
            name: 'Conta Teste',
            type: AccountType.checking,
            initialBalanceMinor: total,
            currentBalanceMinor: total,
            currency: 'BRL',
            ownerName: 'Ludson',
            ownerType: 'self',
            updatedAt: DateTime.utc(2026, 8, 14),
          ),
        ],
        totalBalanceMinor: total,
        lastSyncedAt: DateTime.utc(2026, 8, 14),
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

final class _FailingAccountsRepository implements AccountsRepository {
  @override
  Future<HomeOwnerScopes> readOwnerScopes() async {
    throw Exception('Failed to read owner scopes');
  }

  @override
  Stream<AccountsSnapshot> watchAccounts(OwnerScope scope) {
    return Stream.error(Exception('Failed to watch accounts'));
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
