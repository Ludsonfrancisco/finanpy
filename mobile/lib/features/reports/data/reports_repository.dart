import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../home/domain/home_snapshot.dart';
import '../domain/reports_models.dart';

abstract interface class ReportsRepository {
  Future<HomeOwnerScopes> readOwnerScopes();
  Stream<ReportsSummary> watchReports(OwnerScope scope, ReportPeriod period);
}

final class DriftReportsRepository implements ReportsRepository {
  DriftReportsRepository(this._database);

  final AppDatabase _database;

  static const List<String> _monthNames = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];

  @override
  Future<HomeOwnerScopes> readOwnerScopes() async {
    final rows = await _database.select(_database.owners).get();
    OwnerScope? selfScope;
    OwnerScope? spouseScope;

    for (final row in rows) {
      if (row.type == 'self') {
        selfScope = OwnerScope.self(row.uuid);
      } else if (row.type == 'spouse') {
        spouseScope = OwnerScope.spouse(row.uuid);
      }
    }

    return HomeOwnerScopes(
      selfScope: selfScope ?? const OwnerScope.household(),
      spouseScope: spouseScope ?? const OwnerScope.household(),
    );
  }

  @override
  Stream<ReportsSummary> watchReports(OwnerScope scope, ReportPeriod period) {
    return _database.select(_database.transactions).watch().asyncMap((_) async {
      final now = DateTime.now().toUtc();
      final (startDate, endDate) = period.calculateDateRange(now);
      final syncMeta = await (_database.select(
        _database.syncState,
      )).getSingleOrNull();

      // Buscar transações no período
      final periodQuery = _database.select(_database.transactions)
        ..where((t) => t.date.isBiggerOrEqualValue(startDate))
        ..where((t) => t.date.isSmallerOrEqualValue(endDate));

      if (scope.kind != OwnerScopeKind.household && scope.ownerUuid != null) {
        periodQuery.where((t) => t.financialOwnerUuid.equals(scope.ownerUuid!));
      }

      final periodTransactions = await periodQuery.get();

      int totalIncome = 0;
      int totalExpense = 0;
      final Map<String, int> expenseByCategory = {};
      final Map<String, int> countByCategory = {};

      for (final tx in periodTransactions) {
        if (tx.type == 'income') {
          totalIncome += tx.amountMinor;
        } else if (tx.type == 'expense') {
          totalExpense += tx.amountMinor;
          final catUuid = tx.categoryUuid;
          expenseByCategory[catUuid] =
              (expenseByCategory[catUuid] ?? 0) + tx.amountMinor;
          countByCategory[catUuid] = (countByCategory[catUuid] ?? 0) + 1;
        }
      }

      final netBalance = totalIncome - totalExpense;
      final savingsRate = totalIncome > 0
          ? ((netBalance > 0 ? netBalance : 0) / totalIncome) * 100
          : 0.0;

      // Buscar categorias para montar distribuição
      final categories = await _database.select(_database.categories).get();
      final categoryMap = {for (final c in categories) c.uuid: c};

      final distributions = <CategoryExpenseDistribution>[];
      for (final entry in expenseByCategory.entries) {
        final cat = categoryMap[entry.key];
        final catName = cat?.name ?? 'Outros';
        final catColor = cat?.color ?? '#2F756A';
        final amount = entry.value;
        final percentage = totalExpense > 0
            ? (amount / totalExpense) * 100
            : 0.0;

        distributions.add(
          CategoryExpenseDistribution(
            categoryUuid: entry.key,
            categoryName: catName,
            color: catColor,
            totalMinor: amount,
            percentage: percentage,
            transactionCount: countByCategory[entry.key] ?? 0,
          ),
        );
      }

      // Ordenar distribuição de despesas por maior valor
      distributions.sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

      // Calcular Fluxo Mensal dos últimos 6 meses
      final monthlyFlows = await _calculateMonthlyFlows(scope, now);

      return ReportsSummary(
        scope: scope,
        period: period,
        totalIncomeMinor: totalIncome,
        totalExpenseMinor: totalExpense,
        netBalanceMinor: netBalance,
        savingsRate: savingsRate,
        categoryDistributions: distributions,
        monthlyFlows: monthlyFlows,
        lastSyncedAt: syncMeta?.lastSuccessAt,
      );
    });
  }

  Future<List<MonthlyFlowData>> _calculateMonthlyFlows(
    OwnerScope scope,
    DateTime now,
  ) async {
    // 6 meses anteriores até o mês atual
    final months = <(int year, int month)>[];
    for (int i = 5; i >= 0; i--) {
      int m = now.month - i;
      int y = now.year;
      while (m < 1) {
        m += 12;
        y -= 1;
      }
      months.add((y, m));
    }

    final startOfSixMonths = DateTime.utc(months.first.$1, months.first.$2, 1);
    final endOfCurrentMonth = DateTime.utc(
      now.year,
      now.month + 1,
      0,
      23,
      59,
      59,
      999,
    );

    final sixMonthsQuery = _database.select(_database.transactions)
      ..where((t) => t.date.isBiggerOrEqualValue(startOfSixMonths))
      ..where((t) => t.date.isSmallerOrEqualValue(endOfCurrentMonth));

    if (scope.kind != OwnerScopeKind.household && scope.ownerUuid != null) {
      sixMonthsQuery.where(
        (t) => t.financialOwnerUuid.equals(scope.ownerUuid!),
      );
    }

    final txs = await sixMonthsQuery.get();

    final Map<String, int> monthlyIncome = {};
    final Map<String, int> monthlyExpense = {};

    for (final tx in txs) {
      final key = '${tx.date.year}-${tx.date.month}';
      if (tx.type == 'income') {
        monthlyIncome[key] = (monthlyIncome[key] ?? 0) + tx.amountMinor;
      } else if (tx.type == 'expense') {
        monthlyExpense[key] = (monthlyExpense[key] ?? 0) + tx.amountMinor;
      }
    }

    final result = <MonthlyFlowData>[];
    for (final (year, month) in months) {
      final key = '$year-$month';
      final inc = monthlyIncome[key] ?? 0;
      final exp = monthlyExpense[key] ?? 0;
      final net = inc - exp;
      final rate = inc > 0 ? ((net > 0 ? net : 0) / inc) * 100 : 0.0;
      final label = '${_monthNames[month - 1]}/${year.toString().substring(2)}';

      result.add(
        MonthlyFlowData(
          year: year,
          month: month,
          monthLabel: label,
          incomeMinor: inc,
          expenseMinor: exp,
          netSavingsMinor: net,
          savingsRate: rate,
        ),
      );
    }

    return result;
  }
}
