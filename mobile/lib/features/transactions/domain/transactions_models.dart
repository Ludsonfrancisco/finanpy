import '../../home/domain/home_snapshot.dart';

enum TransactionType {
  income,
  expense;

  static TransactionType fromString(String value) => switch (value) {
    'income' => income,
    'expense' => expense,
    _ => expense,
  };

  String get label => switch (this) {
    income => 'Receita',
    expense => 'Despesa',
  };
}

final class TransactionItem {
  const TransactionItem({
    required this.uuid,
    required this.description,
    required this.categoryName,
    required this.categoryColor,
    required this.categoryIcon,
    required this.accountName,
    required this.accountUuid,
    required this.ownerName,
    required this.ownerType,
    required this.date,
    required this.type,
    required this.amountMinor,
    required this.signedAmountMinor,
    required this.updatedAt,
  });

  final String uuid;
  final String description;
  final String categoryName;
  final String categoryColor;
  final String? categoryIcon;
  final String accountName;
  final String accountUuid;
  final String ownerName;
  final String ownerType;
  final DateTime date;
  final TransactionType type;
  final int amountMinor;
  final int signedAmountMinor;
  final DateTime updatedAt;
}

final class TransactionFilterOption {
  const TransactionFilterOption({required this.uuid, required this.name});

  final String uuid;
  final String name;
}

final class TransactionOwnerOption {
  const TransactionOwnerOption({
    required this.uuid,
    required this.name,
    required this.type,
  });

  final String uuid;
  final String name;
  final String type;
}

final class TransactionCategoryOption {
  const TransactionCategoryOption({
    required this.uuid,
    required this.name,
    required this.type,
    required this.color,
    this.icon,
  });

  final String uuid;
  final String name;
  final TransactionType type;
  final String color;
  final String? icon;
}

final class TransactionFilters {
  const TransactionFilters({
    this.searchQuery = '',
    this.type,
    this.accountUuid,
    this.categoryUuid,
    this.startDate,
    this.endDate,
  });

  final String searchQuery;
  final TransactionType? type;
  final String? accountUuid;
  final String? categoryUuid;
  final DateTime? startDate;
  final DateTime? endDate;

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      type != null ||
      accountUuid != null ||
      categoryUuid != null ||
      startDate != null ||
      endDate != null;

  TransactionFilters copyWith({
    String? searchQuery,
    TransactionType? type,
    String? accountUuid,
    String? categoryUuid,
    DateTime? startDate,
    DateTime? endDate,
    bool clearType = false,
    bool clearAccount = false,
    bool clearCategory = false,
    bool clearDates = false,
  }) => TransactionFilters(
    searchQuery: searchQuery ?? this.searchQuery,
    type: clearType ? null : type ?? this.type,
    accountUuid: clearAccount ? null : accountUuid ?? this.accountUuid,
    categoryUuid: clearCategory ? null : categoryUuid ?? this.categoryUuid,
    startDate: clearDates ? null : startDate ?? this.startDate,
    endDate: clearDates ? null : endDate ?? this.endDate,
  );
}

final class TransactionGroup {
  const TransactionGroup({
    required this.date,
    required this.transactions,
    required this.dayTotalIncomeMinor,
    required this.dayTotalExpenseMinor,
  });

  final DateTime date;
  final List<TransactionItem> transactions;
  final int dayTotalIncomeMinor;
  final int dayTotalExpenseMinor;
}

final class TransactionsSnapshot {
  const TransactionsSnapshot({
    required this.scope,
    required this.groups,
    required this.totalCount,
    required this.totalIncomeMinor,
    required this.totalExpenseMinor,
    required this.lastSyncedAt,
    required this.availableAccounts,
    required this.availableCategories,
  });

  final OwnerScope scope;
  final List<TransactionGroup> groups;
  final int totalCount;
  final int totalIncomeMinor;
  final int totalExpenseMinor;
  final DateTime? lastSyncedAt;
  final List<TransactionFilterOption> availableAccounts;
  final List<TransactionFilterOption> availableCategories;

  bool get isEmpty => totalCount == 0;
}

final class TransactionsState {
  const TransactionsState({
    required this.snapshot,
    required this.filters,
    required this.selectedScopeIndex,
    required this.ownerScopes,
    required this.isLoading,
    this.error,
  });

  const TransactionsState.initial()
    : snapshot = null,
      filters = const TransactionFilters(),
      selectedScopeIndex = 0,
      ownerScopes = null,
      isLoading = true,
      error = null;

  final TransactionsSnapshot? snapshot;
  final TransactionFilters filters;
  final int selectedScopeIndex;
  final HomeOwnerScopes? ownerScopes;
  final bool isLoading;
  final Object? error;

  TransactionsState copyWith({
    TransactionsSnapshot? snapshot,
    TransactionFilters? filters,
    int? selectedScopeIndex,
    HomeOwnerScopes? ownerScopes,
    bool? isLoading,
    Object? error,
  }) => TransactionsState(
    snapshot: snapshot ?? this.snapshot,
    filters: filters ?? this.filters,
    selectedScopeIndex: selectedScopeIndex ?? this.selectedScopeIndex,
    ownerScopes: ownerScopes ?? this.ownerScopes,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}
