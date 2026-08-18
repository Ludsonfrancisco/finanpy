import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/reports/application/reports_controller.dart';
import 'package:lar_finance/features/reports/data/reports_repository.dart';
import 'package:lar_finance/features/reports/domain/reports_models.dart';
import 'package:lar_finance/features/reports/presentation/reports_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets(
    'ReportsScreen renders scope selector, period selector, metrics and charts',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = _FakeReportsRepository();
      final syncState = SyncState(retry: () async => SyncResult.current);
      final controller = ReportsController(
        repository: fakeRepo,
        syncState: syncState,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: LarTheme.light,
          home: Scaffold(body: ReportsScreen(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lar'), findsOneWidget);
      expect(find.text('Eu'), findsOneWidget);
      expect(find.text('Esposa'), findsOneWidget);

      expect(find.text('Mês Atual'), findsOneWidget);
      expect(find.text('3 Meses'), findsOneWidget);
      expect(find.text('6 Meses'), findsOneWidget);
      expect(find.text('Este Ano'), findsOneWidget);

      expect(find.text('Receitas'), findsWidgets);
      expect(find.text('Despesas'), findsWidgets);
      expect(find.text('Saldo Líquido'), findsOneWidget);
      expect(find.text('Distribuição de Gastos'), findsOneWidget);
      expect(find.text('Fluxo Mensal (6 Meses)'), findsOneWidget);
      expect(find.text('Despesas por Categoria'), findsOneWidget);

      controller.dispose();
    },
  );

  testWidgets('ReportsScreen renders empty state when summary has no data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final emptyRepo = _EmptyReportsRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = ReportsController(
      repository: emptyRepo,
      syncState: syncState,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: LarTheme.light,
        home: Scaffold(body: ReportsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reports-empty-state')), findsOneWidget);
    expect(find.text('Sem dados no período selecionado'), findsOneWidget);

    controller.dispose();
  });
}

final class _FakeReportsRepository implements ReportsRepository {
  @override
  Future<HomeOwnerScopes> readOwnerScopes() async {
    return const HomeOwnerScopes(
      selfScope: OwnerScope.self('self-uuid'),
      spouseScope: OwnerScope.spouse('spouse-uuid'),
    );
  }

  @override
  Stream<ReportsSummary> watchReports(OwnerScope scope, ReportPeriod period) {
    return Stream.value(
      ReportsSummary(
        scope: scope,
        period: period,
        totalIncomeMinor: 600000,
        totalExpenseMinor: 300000,
        netBalanceMinor: 300000,
        savingsRate: 50.0,
        categoryDistributions: const [
          CategoryExpenseDistribution(
            categoryUuid: 'cat-1',
            categoryName: 'Alimentação',
            color: '#2F756A',
            totalMinor: 200000,
            percentage: 66.7,
            transactionCount: 4,
          ),
          CategoryExpenseDistribution(
            categoryUuid: 'cat-2',
            categoryName: 'Transporte',
            color: '#B8534F',
            totalMinor: 100000,
            percentage: 33.3,
            transactionCount: 2,
          ),
        ],
        monthlyFlows: const [
          MonthlyFlowData(
            year: 2026,
            month: 8,
            monthLabel: 'Ago/26',
            incomeMinor: 600000,
            expenseMinor: 300000,
            netSavingsMinor: 300000,
            savingsRate: 50.0,
          ),
        ],
        lastSyncedAt: DateTime.utc(2026, 8, 14),
      ),
    );
  }
}

final class _EmptyReportsRepository implements ReportsRepository {
  @override
  Future<HomeOwnerScopes> readOwnerScopes() async {
    return const HomeOwnerScopes(
      selfScope: OwnerScope.self('self-uuid'),
      spouseScope: OwnerScope.spouse('spouse-uuid'),
    );
  }

  @override
  Stream<ReportsSummary> watchReports(OwnerScope scope, ReportPeriod period) {
    return Stream.value(
      ReportsSummary(
        scope: scope,
        period: period,
        totalIncomeMinor: 0,
        totalExpenseMinor: 0,
        netBalanceMinor: 0,
        savingsRate: 0.0,
        categoryDistributions: const [],
        monthlyFlows: const [],
        lastSyncedAt: null,
      ),
    );
  }
}
