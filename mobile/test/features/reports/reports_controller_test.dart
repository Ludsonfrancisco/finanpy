import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/features/reports/application/reports_controller.dart';
import 'package:lar_finance/features/reports/data/reports_repository.dart';
import 'package:lar_finance/features/reports/domain/reports_models.dart';

void main() {
  test(
    'ReportsController starts in loading, loads scopes and sets summary',
    () async {
      final fakeRepo = _FakeReportsRepository();
      final syncState = SyncState(retry: () async => SyncResult.current);
      final controller = ReportsController(
        repository: fakeRepo,
        syncState: syncState,
      );

      expect(controller.state.isLoading, isTrue);
      expect(controller.state.summary, isNull);

      await controller.start();
      await pumpEventQueue();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.ownerScopes, isNotNull);
      expect(controller.state.summary, isNotNull);
      expect(controller.state.summary!.totalIncomeMinor, 500000);

      controller.dispose();
    },
  );

  test('selectScope switches owner scope and re-watches summary', () async {
    final fakeRepo = _FakeReportsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = ReportsController(
      repository: fakeRepo,
      syncState: syncState,
    );

    await controller.start();
    await pumpEventQueue();

    await controller.selectScope(1); // Self
    await pumpEventQueue();

    expect(controller.state.selectedScopeIndex, 1);
    expect(fakeRepo.lastScope.kind, OwnerScopeKind.selfOwner);

    controller.dispose();
  });

  test(
    'selectPeriod switches analysis period and re-watches summary',
    () async {
      final fakeRepo = _FakeReportsRepository();
      final syncState = SyncState(retry: () async => SyncResult.current);
      final controller = ReportsController(
        repository: fakeRepo,
        syncState: syncState,
      );

      await controller.start();
      await pumpEventQueue();

      await controller.selectPeriod(ReportPeriod.last6Months);
      await pumpEventQueue();

      expect(controller.state.selectedPeriod, ReportPeriod.last6Months);
      expect(fakeRepo.lastPeriod, ReportPeriod.last6Months);

      controller.dispose();
    },
  );
}

final class _FakeReportsRepository implements ReportsRepository {
  OwnerScope lastScope = const OwnerScope.household();
  ReportPeriod lastPeriod = ReportPeriod.currentMonth;

  @override
  Future<HomeOwnerScopes> readOwnerScopes() async {
    return const HomeOwnerScopes(
      selfScope: OwnerScope.self('self-uuid'),
      spouseScope: OwnerScope.spouse('spouse-uuid'),
    );
  }

  @override
  Stream<ReportsSummary> watchReports(OwnerScope scope, ReportPeriod period) {
    lastScope = scope;
    lastPeriod = period;
    return Stream.value(
      ReportsSummary(
        scope: scope,
        period: period,
        totalIncomeMinor: 500000,
        totalExpenseMinor: 200000,
        netBalanceMinor: 300000,
        savingsRate: 60.0,
        categoryDistributions: [
          const CategoryExpenseDistribution(
            categoryUuid: 'cat-1',
            categoryName: 'Alimentação',
            color: '#2F756A',
            totalMinor: 200000,
            percentage: 100.0,
            transactionCount: 2,
          ),
        ],
        monthlyFlows: [
          const MonthlyFlowData(
            year: 2026,
            month: 8,
            monthLabel: 'Ago/26',
            incomeMinor: 500000,
            expenseMinor: 200000,
            netSavingsMinor: 300000,
            savingsRate: 60.0,
          ),
        ],
        lastSyncedAt: DateTime.utc(2026, 8, 14),
      ),
    );
  }
}
