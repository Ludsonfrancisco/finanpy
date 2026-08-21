import 'package:flutter/foundation.dart';

import '../../../core/money/minor_units.dart';

@immutable
final class CreditCardModel {
  const CreditCardModel({
    required this.id,
    required this.name,
    required this.limitMinor,
    required this.availableLimitMinor,
    required this.unpaidExpensesTotalMinor,
    required this.currentInvoiceTotalMinor,
    required this.limitUsagePercent,
    required this.closingDay,
    required this.dueDay,
    required this.color,
    required this.brand,
    required this.brandDisplay,
    required this.lastDigits,
    required this.isActive,
    required this.financialOwnerId,
    required this.financialOwnerType,
    required this.financialOwnerName,
  });

  final int id;
  final String name;
  final int limitMinor;
  final int availableLimitMinor;
  final int unpaidExpensesTotalMinor;
  final int currentInvoiceTotalMinor;
  final double limitUsagePercent;
  final int closingDay;
  final int dueDay;
  final String color;
  final String brand;
  final String brandDisplay;
  final String lastDigits;
  final bool isActive;
  final int? financialOwnerId;
  final String financialOwnerType;
  final String financialOwnerName;

  factory CreditCardModel.fromJson(Map<String, dynamic> json) {
    return CreditCardModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      limitMinor: parseApiMinorUnits(json['limit']),
      availableLimitMinor: parseApiMinorUnits(json['available_limit']),
      unpaidExpensesTotalMinor: parseApiMinorUnits(
        json['unpaid_expenses_total'],
      ),
      currentInvoiceTotalMinor: parseApiMinorUnits(
        json['current_invoice_total'],
      ),
      limitUsagePercent:
          (json['limit_usage_percent'] as num?)?.toDouble() ?? 0.0,
      closingDay: json['closing_day'] as int? ?? 10,
      dueDay: json['due_day'] as int? ?? 17,
      color: json['color'] as String? ?? '#2F756A',
      brand: json['brand'] as String? ?? 'visa',
      brandDisplay: json['brand_display'] as String? ?? 'Visa',
      lastDigits: json['last_digits'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      financialOwnerId: json['financial_owner_id'] as int?,
      financialOwnerType: json['financial_owner_type'] as String? ?? 'shared',
      financialOwnerName: json['financial_owner_name'] as String? ?? 'Lar',
    );
  }
}

@immutable
final class CardExpenseModel {
  const CardExpenseModel({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.invoiceId,
    required this.description,
    required this.amountMinor,
    required this.date,
    required this.categoryId,
    required this.categoryName,
    required this.financialOwnerId,
    required this.financialOwnerType,
    required this.financialOwnerName,
    required this.installmentsCount,
    required this.installmentNumber,
    required this.installmentGroupId,
  });

  final int id;
  final int cardId;
  final String cardName;
  final int invoiceId;
  final String description;
  final int amountMinor;
  final DateTime date;
  final int? categoryId;
  final String categoryName;
  final int? financialOwnerId;
  final String financialOwnerType;
  final String financialOwnerName;
  final int installmentsCount;
  final int installmentNumber;
  final String installmentGroupId;

  factory CardExpenseModel.fromJson(Map<String, dynamic> json) {
    return CardExpenseModel(
      id: json['id'] as int? ?? 0,
      cardId: json['card_id'] as int? ?? 0,
      cardName: json['card_name'] as String? ?? '',
      invoiceId: json['invoice_id'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      amountMinor: parseApiMinorUnits(json['amount']),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      categoryId: json['category_id'] as int?,
      categoryName: json['category_name'] as String? ?? 'Geral',
      financialOwnerId: json['financial_owner_id'] as int?,
      financialOwnerType: json['financial_owner_type'] as String? ?? 'shared',
      financialOwnerName: json['financial_owner_name'] as String? ?? 'Lar',
      installmentsCount: json['installments_count'] as int? ?? 1,
      installmentNumber: json['installment_number'] as int? ?? 1,
      installmentGroupId: json['installment_group_id'] as String? ?? '',
    );
  }
}

@immutable
final class CardInvoiceModel {
  const CardInvoiceModel({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.month,
    required this.year,
    required this.closingDate,
    required this.dueDate,
    required this.status,
    required this.statusDisplay,
    required this.totalAmountMinor,
    required this.paidAmountMinor,
    this.paidAt,
    this.paymentAccountId,
    this.paymentAccountName,
    this.expensesCount = 0,
    this.expenses = const [],
  });

  final int id;
  final int cardId;
  final String cardName;
  final int month;
  final int year;
  final DateTime closingDate;
  final DateTime dueDate;
  final String status;
  final String statusDisplay;
  final int totalAmountMinor;
  final int paidAmountMinor;
  final DateTime? paidAt;
  final int? paymentAccountId;
  final String? paymentAccountName;
  final int expensesCount;
  final List<CardExpenseModel> expenses;

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'overdue';

  factory CardInvoiceModel.fromJson(Map<String, dynamic> json) {
    final expList = json['expenses'] as List<dynamic>? ?? [];
    return CardInvoiceModel(
      id: json['id'] as int? ?? 0,
      cardId: json['card_id'] as int? ?? 0,
      cardName: json['card_name'] as String? ?? '',
      month: json['month'] as int? ?? 1,
      year: json['year'] as int? ?? 2026,
      closingDate:
          DateTime.tryParse(json['closing_date'] as String? ?? '') ??
          DateTime.now(),
      dueDate:
          DateTime.tryParse(json['due_date'] as String? ?? '') ??
          DateTime.now(),
      status: json['status'] as String? ?? 'open',
      statusDisplay: json['status_display'] as String? ?? 'Aberta',
      totalAmountMinor: parseApiMinorUnits(json['total_amount']),
      paidAmountMinor: parseApiMinorUnits(json['paid_amount']),
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'] as String)
          : null,
      paymentAccountId: json['payment_account_id'] as int?,
      paymentAccountName: json['payment_account_name'] as String?,
      expensesCount: json['expenses_count'] as int? ?? expList.length,
      expenses: expList
          .map((e) => CardExpenseModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

@immutable
final class CardsSummaryModel {
  const CardsSummaryModel({
    required this.month,
    required this.year,
    required this.totalLimitMinor,
    required this.totalUsedMinor,
    required this.totalAvailableMinor,
    required this.totalCurrentInvoicesMinor,
    required this.limitUsagePercent,
  });

  final int month;
  final int year;
  final int totalLimitMinor;
  final int totalUsedMinor;
  final int totalAvailableMinor;
  final int totalCurrentInvoicesMinor;
  final double limitUsagePercent;

  static const empty = CardsSummaryModel(
    month: 1,
    year: 2026,
    totalLimitMinor: 0,
    totalUsedMinor: 0,
    totalAvailableMinor: 0,
    totalCurrentInvoicesMinor: 0,
    limitUsagePercent: 0.0,
  );

  factory CardsSummaryModel.fromJson(Map<String, dynamic> json) {
    return CardsSummaryModel(
      month: json['month'] as int? ?? 1,
      year: json['year'] as int? ?? 2026,
      totalLimitMinor: parseApiMinorUnits(json['total_limit']),
      totalUsedMinor: parseApiMinorUnits(json['total_used']),
      totalAvailableMinor: parseApiMinorUnits(json['total_available']),
      totalCurrentInvoicesMinor: parseApiMinorUnits(
        json['total_current_invoices'],
      ),
      limitUsagePercent:
          (json['limit_usage_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

@immutable
final class CardsSnapshot {
  const CardsSnapshot({required this.cards, required this.summary});

  final List<CreditCardModel> cards;
  final CardsSummaryModel summary;
}

@immutable
final class CardDetailSnapshot {
  const CardDetailSnapshot({
    required this.card,
    required this.selectedInvoice,
    required this.futureInvoices,
  });

  final CreditCardModel card;
  final CardInvoiceModel selectedInvoice;
  final List<CardInvoiceModel> futureInvoices;
}
