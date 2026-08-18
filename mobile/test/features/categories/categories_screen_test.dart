import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/categories/application/categories_controller.dart';
import 'package:lar_finance/features/categories/data/categories_repository.dart';
import 'package:lar_finance/features/categories/domain/categories_models.dart';
import 'package:lar_finance/features/categories/presentation/categories_screen.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('CategoriesScreen renders list, search bar and category cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = _FakeCategoriesRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = CategoriesController(
      repository: fakeRepo,
      syncState: syncState,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: LarTheme.light,
        home: Scaffold(body: CategoriesScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nova Categoria'), findsWidgets); // Header button + FAB
    expect(find.byType(TextField), findsOneWidget); // Search bar
    expect(find.text('Todas'), findsOneWidget);
    expect(find.text('Despesas'), findsOneWidget);
    expect(find.text('Receitas'), findsOneWidget);

    expect(find.text('Alimentação'), findsOneWidget);
    expect(find.text('Salário'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('CategoriesScreen renders empty state when no categories exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final emptyRepo = _EmptyCategoriesRepository();
    final syncState = SyncState(retry: () async => SyncResult.current);
    final controller = CategoriesController(
      repository: emptyRepo,
      syncState: syncState,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: LarTheme.light,
        home: Scaffold(body: CategoriesScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('categories-empty-state')), findsOneWidget);
    expect(find.text('Nenhuma categoria cadastrada'), findsOneWidget);

    controller.dispose();
  });
}

final class _FakeCategoriesRepository implements CategoriesRepository {
  @override
  Stream<CategoriesSnapshot> watchCategories([
    CategoryFilters filters = const CategoryFilters(),
  ]) {
    return Stream.value(
      CategoriesSnapshot(
        categories: [
          CategoryItem(
            uuid: 'cat-1',
            name: 'Alimentação',
            type: TransactionType.expense,
            color: '#2F756A',
            transactionCount: 3,
            version: 1,
            updatedAt: DateTime.utc(2026, 8, 14),
          ),
          CategoryItem(
            uuid: 'cat-2',
            name: 'Salário',
            type: TransactionType.income,
            color: '#2F756A',
            transactionCount: 1,
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
  }) async => 'cat-new-uuid';

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

final class _EmptyCategoriesRepository implements CategoriesRepository {
  @override
  Stream<CategoriesSnapshot> watchCategories([
    CategoryFilters filters = const CategoryFilters(),
  ]) {
    return Stream.value(
      CategoriesSnapshot(
        categories: const [],
        lastSyncedAt: null,
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
  }) async => 'cat-new-uuid';

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
