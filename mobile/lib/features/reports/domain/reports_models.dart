import '../../home/domain/home_snapshot.dart';

enum ReportPeriod {
  currentMonth,
  last3Months,
  last6Months,
  yearToDate;

  String get label => switch (this) {
    currentMonth => 'Mês Atual',
    last3Months => '3 Meses',
    last6Months => '6 Meses',
    yearToDate => 'Este Ano',
  };

  (DateTime start, DateTime end) calculateDateRange(DateTime now) {
    final endOfToday = DateTime.utc(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );

    switch (this) {
      case currentMonth:
        return (DateTime.utc(now.year, now.month, 1), endOfToday);
      case last3Months:
        final startMonth = now.month - 2;
        final startYear = startMonth < 1 ? now.year - 1 : now.year;
        final normalizedMonth = startMonth < 1 ? startMonth + 12 : startMonth;
        return (DateTime.utc(startYear, normalizedMonth, 1), endOfToday);
      case last6Months:
        final startMonth = now.month - 5;
        final startYear = startMonth < 1 ? now.year - 1 : now.year;
        final normalizedMonth = startMonth < 1 ? startMonth + 12 : startMonth;
        return (DateTime.utc(startYear, normalizedMonth, 1), endOfToday);
      case yearToDate:
        return (DateTime.utc(now.year, 1, 1), endOfToday);
    }
  }
}

final class CategoryExpenseDistribution {
  const CategoryExpenseDistribution({
    required this.categoryUuid,
    required this.categoryName,
    required this.color,
    required this.totalMinor,
    required this.percentage,
    required this.transactionCount,
  });

  final String categoryUuid;
  final String categoryName;
  final String color;
  final int totalMinor;
  final double percentage; // 0.0 a 100.0
  final int transactionCount;
}

final class MonthlyFlowData {
  const MonthlyFlowData({
    required this.year,
    required this.month,
    required this.monthLabel,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netSavingsMinor,
    required this.savingsRate,
  });

  final int year;
  final int month;
  final String monthLabel;
  final int incomeMinor;
  final int expenseMinor;
  final int netSavingsMinor;
  final double savingsRate; // 0.0 a 100.0
}

final class ReportsSummary {
  const ReportsSummary({
    required this.scope,
    required this.period,
    required this.totalIncomeMinor,
    required this.totalExpenseMinor,
    required this.netBalanceMinor,
    required this.savingsRate,
    required this.categoryDistributions,
    required this.monthlyFlows,
    required this.lastSyncedAt,
  });

  final OwnerScope scope;
  final ReportPeriod period;
  final int totalIncomeMinor;
  final int totalExpenseMinor;
  final int netBalanceMinor;
  final double savingsRate;
  final List<CategoryExpenseDistribution> categoryDistributions;
  final List<MonthlyFlowData> monthlyFlows;
  final DateTime? lastSyncedAt;

  bool get hasData => totalIncomeMinor > 0 || totalExpenseMinor > 0;
}
