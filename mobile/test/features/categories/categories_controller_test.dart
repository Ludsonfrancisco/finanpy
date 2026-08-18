import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/features/categories/application/categories_controller.dart';
import 'package:lar_finance/features/categories/data/categories_repository.dart';
import 'package:lar_finance/features/categories/domain/categories_models.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';

void main() {
  test('starts in loading, watches categories and updates snapshot', () async {
    final fakeRepo = _FakeCategoriesRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = CategoriesController(
      repository: fakeRepo,
      syncState: syncState,
    );

    expect(controller.state.isLoading, isTrue);
    expect(controller.state.snapshot, isNull);

    await controller.start();
    await pumpEventQueue();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.snapshot, isNotNull);
    expect(controller.state.snapshot!.totalCount, 2);

    controller.dispose();
  });

  test('setTypeFilter updates filters and triggers query', () async {
    final fakeRepo = _FakeCategoriesRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = CategoriesController(
      repository: fakeRepo,
      syncState: syncState,
    );

    await controller.start();
    await pumpEventQueue();

    await controller.setTypeFilter(TransactionType.expense);
    await pumpEventQueue();

    expect(controller.state.filters.type, TransactionType.expense);
    expect(fakeRepo.lastFilters.type, TransactionType.expense);

    controller.dispose();
  });

  test('setSearchQuery updates filters with trimmed text', () async {
    final fakeRepo = _FakeCategoriesRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = CategoriesController(
      repository: fakeRepo,
      syncState: syncState,
    );

    await controller.start();
    await pumpEventQueue();

    await controller.setSearchQuery('  alimentação  ');
    await pumpEventQueue();

    expect(controller.state.filters.searchQuery, 'alimentação');
    expect(fakeRepo.lastFilters.searchQuery, 'alimentação');

    controller.dispose();
  });
}

final class _FakeCategoriesRepository implements CategoriesRepository {
  CategoryFilters lastFilters = const CategoryFilters();

  @override
  Stream<CategoriesSnapshot> watchCategories([
    CategoryFilters filters = const CategoryFilters(),
  ]) {
    lastFilters = filters;
    return Stream.value(
      CategoriesSnapshot(
        categories: [
          CategoryItem(
            uuid: 'cat-1',
            name: 'Alimentação',
            type: TransactionType.expense,
            color: '#2F756A',
            version: 1,
            updatedAt: DateTime.utc(2026, 8, 14),
          ),
          CategoryItem(
            uuid: 'cat-2',
            name: 'Salário',
            type: TransactionType.income,
            color: '#2F756A',
            version: 1,
            updatedAt: DateTime.utc(2026, 8, 14),
          ),
        ],
        lastSyncedAt: DateTime.utc(2026, 8, 14),
        filters: filters,
      ),
    );
  }

  @override
  Future<String> createCategory({
    required String name,
    required TransactionType type,
    required String color,
    String? icon,
  }) async => 'cat-created-uuid';

  @override
  Future<void> updateCategory({
    required String uuid,
    required String name,
    required TransactionType type,
    required String color,
    String? icon,
  }) async {}

  @override
  Future<void> deleteCategory(String uuid) async {}
}
