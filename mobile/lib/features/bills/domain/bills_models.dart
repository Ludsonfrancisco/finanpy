import 'package:flutter/foundation.dart';

@immutable
final class BillInstanceModel {
  const BillInstanceModel({
    required this.id,
    required this.billId,
    required this.name,
    required this.month,
    required this.year,
    required this.dueDate,
    required this.dueDay,
    required this.amount,
    required this.status,
    this.paidAt,
    required this.type,
    required this.categoryName,
    this.categoryId,
    this.accountName,
    this.accountId,
    this.defaultAccountId,
    required this.financialOwnerType,
    required this.financialOwnerName,
  });

  factory BillInstanceModel.fromJson(Map<String, Object?> json) {
    return BillInstanceModel(
      id: (json['id'] as num).toInt(),
      billId: (json['bill_id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      month: (json['month'] as num).toInt(),
      year: (json['year'] as num).toInt(),
      dueDate: DateTime.parse(json['due_date'] as String),
      dueDay: (json['due_day'] as num?)?.toInt() ?? 1,
      amount: double.tryParse(json['amount'] as String? ?? '0.00') ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      paidAt: json['paid_at'] != null ? DateTime.tryParse(json['paid_at'] as String) : null,
      type: json['type'] as String? ?? 'expense',
      categoryName: json['category_name'] as String? ?? 'Geral',
      categoryId: (json['category_id'] as num?)?.toInt(),
      accountName: json['account_name'] as String?,
      accountId: (json['account_id'] as num?)?.toInt(),
      defaultAccountId: (json['default_account_id'] as num?)?.toInt(),
      financialOwnerType: json['financial_owner_type'] as String? ?? 'shared',
      financialOwnerName: json['financial_owner_name'] as String? ?? 'Conjunto',
    );
  }

  final int id;
  final int billId;
  final String name;
  final int month;
  final int year;
  final DateTime dueDate;
  final int dueDay;
  final double amount;
  final String status;
  final DateTime? paidAt;
  final String type;
  final String categoryName;
  final int? categoryId;
  final String? accountName;
  final int? accountId;
  final int? defaultAccountId;
  final String financialOwnerType;
  final String financialOwnerName;

  bool get isPaid => status == 'paid';
  bool get isPending => status == 'pending';

  bool isOverdue(DateTime now) {
    if (!isPending) return false;
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.isBefore(today);
  }

  bool isDueToday(DateTime now) {
    if (!isPending) return false;
    return dueDate.year == now.year && dueDate.month == now.month && dueDate.day == now.day;
  }
}

@immutable
final class RecurringBillModel {
  const RecurringBillModel({
    required this.id,
    required this.name,
    required this.amount,
    required this.dueDay,
    required this.type,
    this.categoryId,
    required this.categoryName,
    this.defaultAccountId,
    this.defaultAccountName,
    required this.financialOwnerType,
    required this.financialOwnerName,
    required this.isActive,
    required this.notes,
  });

  factory RecurringBillModel.fromJson(Map<String, Object?> json) {
    return RecurringBillModel(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      amount: double.tryParse(json['amount'] as String? ?? '0.00') ?? 0.0,
      dueDay: (json['due_day'] as num?)?.toInt() ?? 1,
      type: json['type'] as String? ?? 'expense',
      categoryId: (json['category_id'] as num?)?.toInt(),
      categoryName: json['category_name'] as String? ?? 'Geral',
      defaultAccountId: (json['default_account_id'] as num?)?.toInt(),
      defaultAccountName: json['default_account_name'] as String?,
      financialOwnerType: json['financial_owner_type'] as String? ?? 'shared',
      financialOwnerName: json['financial_owner_name'] as String? ?? 'Conjunto',
      isActive: json['is_active'] as bool? ?? true,
      notes: json['notes'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final double amount;
  final int dueDay;
  final String type;
  final int? categoryId;
  final String categoryName;
  final int? defaultAccountId;
  final String? defaultAccountName;
  final String financialOwnerType;
  final String financialOwnerName;
  final bool isActive;
  final String notes;
}

@immutable
final class BillsMetricsModel {
  const BillsMetricsModel({
    required this.month,
    required this.year,
    required this.pendingExpensesTotal,
    required this.paidExpensesTotal,
    required this.totalCommitted,
    required this.overdueCount,
    required this.dueTodayCount,
    required this.totalAccountBalance,
    required this.freeCashBalance,
  });

  factory BillsMetricsModel.fromJson(Map<String, Object?> json) {
    return BillsMetricsModel(
      month: (json['month'] as num?)?.toInt() ?? DateTime.now().month,
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      pendingExpensesTotal: double.tryParse(json['pending_expenses_total'] as String? ?? '0.00') ?? 0.0,
      paidExpensesTotal: double.tryParse(json['paid_expenses_total'] as String? ?? '0.00') ?? 0.0,
      totalCommitted: double.tryParse(json['total_committed'] as String? ?? '0.00') ?? 0.0,
      overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
      dueTodayCount: (json['due_today_count'] as num?)?.toInt() ?? 0,
      totalAccountBalance: double.tryParse(json['total_account_balance'] as String? ?? '0.00') ?? 0.0,
      freeCashBalance: double.tryParse(json['free_cash_balance'] as String? ?? '0.00') ?? 0.0,
    );
  }

  static const empty = BillsMetricsModel(
    month: 1,
    year: 2026,
    pendingExpensesTotal: 0.0,
    paidExpensesTotal: 0.0,
    totalCommitted: 0.0,
    overdueCount: 0,
    dueTodayCount: 0,
    totalAccountBalance: 0.0,
    freeCashBalance: 0.0,
  );

  final int month;
  final int year;
  final double pendingExpensesTotal;
  final double paidExpensesTotal;
  final double totalCommitted;
  final int overdueCount;
  final int dueTodayCount;
  final double totalAccountBalance;
  final double freeCashBalance;
}
