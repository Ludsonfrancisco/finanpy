import '../../transactions/domain/transactions_models.dart';

final class CategoryItem {
  const CategoryItem({
    required this.uuid,
    required this.name,
    required this.type,
    required this.color,
    this.icon,
    this.transactionCount = 0,
    required this.version,
    required this.updatedAt,
  });

  final String uuid;
  final String name;
  final TransactionType type;
  final String color;
  final String? icon;
  final int transactionCount;
  final int version;
  final DateTime updatedAt;
}

final class CategoryFilters {
  const CategoryFilters({this.type, this.searchQuery});

  final TransactionType? type;
  final String? searchQuery;

  bool get hasActiveFilters =>
      type != null || (searchQuery != null && searchQuery!.trim().isNotEmpty);

  CategoryFilters copyWith({
    TransactionType? type,
    bool clearType = false,
    String? searchQuery,
    bool clearSearch = false,
  }) {
    return CategoryFilters(
      type: clearType ? null : (type ?? this.type),
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
    );
  }
}

final class CategoriesSnapshot {
  const CategoriesSnapshot({
    required this.categories,
    required this.lastSyncedAt,
    this.filters = const CategoryFilters(),
  });

  final List<CategoryItem> categories;
  final DateTime? lastSyncedAt;
  final CategoryFilters filters;

  int get totalCount => categories.length;

  List<CategoryItem> get incomeCategories => categories
      .where((c) => c.type == TransactionType.income)
      .toList(growable: false);

  List<CategoryItem> get expenseCategories => categories
      .where((c) => c.type == TransactionType.expense)
      .toList(growable: false);

  bool get isEmpty => categories.isEmpty;
}
