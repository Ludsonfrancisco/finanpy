import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/uuid/uuid_generator.dart';
import '../../transactions/domain/transactions_models.dart';
import '../domain/categories_models.dart';

abstract interface class CategoriesRepository {
  Stream<CategoriesSnapshot> watchCategories([
    CategoryFilters filters = const CategoryFilters(),
  ]);
  Future<String> createCategory({
    required String name,
    required TransactionType type,
    required String color,
    String? icon,
  });
  Future<void> updateCategory({
    required String uuid,
    required String name,
    required TransactionType type,
    required String color,
    String? icon,
  });
  Future<void> deleteCategory(String uuid);
}

final class DriftCategoriesRepository implements CategoriesRepository {
  DriftCategoriesRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<CategoriesSnapshot> watchCategories([
    CategoryFilters filters = const CategoryFilters(),
  ]) {
    final query = _database.select(_database.categories).join([
      leftOuterJoin(
        _database.transactions,
        _database.transactions.categoryUuid.equalsExp(
          _database.categories.uuid,
        ),
        useColumns: false,
      ),
    ]);

    final txCount = _database.transactions.uuid.count();
    query.addColumns([txCount]);
    query.groupBy([_database.categories.uuid]);
    query.orderBy([OrderingTerm.asc(_database.categories.name)]);

    return query.watch().asyncMap((rows) async {
      final syncMeta = await (_database.select(
        _database.syncState,
      )).getSingleOrNull();

      final items = <CategoryItem>[];
      final queryLower = filters.searchQuery?.trim().toLowerCase();

      for (final row in rows) {
        final cat = row.readTable(_database.categories);
        final count = row.read(txCount) ?? 0;
        final catType = cat.type == 'income'
            ? TransactionType.income
            : TransactionType.expense;

        if (filters.type != null && catType != filters.type) {
          continue;
        }

        if (queryLower != null && queryLower.isNotEmpty) {
          if (!cat.name.toLowerCase().contains(queryLower)) {
            continue;
          }
        }

        items.add(
          CategoryItem(
            uuid: cat.uuid,
            name: cat.name,
            type: catType,
            color: cat.color,
            icon: cat.icon,
            transactionCount: count,
            version: cat.version,
            updatedAt: cat.updatedAt,
          ),
        );
      }

      return CategoriesSnapshot(
        categories: items,
        lastSyncedAt: syncMeta?.lastSuccessAt,
        filters: filters,
      );
    });
  }

  @override
  Future<String> createCategory({
    required String name,
    required TransactionType type,
    required String color,
    String? icon,
  }) async {
    final household = await (_database.select(
      _database.households,
    )..limit(1)).getSingleOrNull();
    if (household == null) {
      throw StateError('Household not initialized');
    }

    final newUuid = generateUuidV4();
    final operationId = generateUuidV4();
    final now = DateTime.now().toUtc();
    final typeStr = type == TransactionType.income ? 'income' : 'expense';

    final payloadJson = jsonEncode({
      'name': name,
      'type': typeStr,
      'color': color,
      'icon': ?icon,
    });

    await _database.transaction(() async {
      await _database
          .into(_database.categories)
          .insert(
            CategoriesCompanion.insert(
              uuid: newUuid,
              householdUuid: household.uuid,
              name: name,
              type: typeStr,
              color: color,
              icon: Value(icon),
              version: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await _database
          .into(_database.outboxMutations)
          .insert(
            OutboxMutationsCompanion.insert(
              operationId: operationId,
              entity: 'category',
              action: 'create',
              entityUuid: newUuid,
              expectedVersion: 0,
              payloadJson: payloadJson,
              createdAt: now,
              status: const Value('pending'),
            ),
          );
    });

    return newUuid;
  }

  @override
  Future<void> updateCategory({
    required String uuid,
    required String name,
    required TransactionType type,
    required String color,
    String? icon,
  }) async {
    final existing = await (_database.select(
      _database.categories,
    )..where((c) => c.uuid.equals(uuid))).getSingleOrNull();
    if (existing == null) {
      throw StateError('Category not found: $uuid');
    }

    final operationId = generateUuidV4();
    final now = DateTime.now().toUtc();
    final typeStr = type == TransactionType.income ? 'income' : 'expense';

    final payloadJson = jsonEncode({
      'name': name,
      'type': typeStr,
      'color': color,
      'icon': ?icon,
    });

    await _database.transaction(() async {
      await (_database.update(
        _database.categories,
      )..where((c) => c.uuid.equals(uuid))).write(
        CategoriesCompanion(
          name: Value(name),
          type: Value(typeStr),
          color: Value(color),
          icon: Value(icon),
          version: Value(existing.version + 1),
          updatedAt: Value(now),
        ),
      );

      await _database
          .into(_database.outboxMutations)
          .insert(
            OutboxMutationsCompanion.insert(
              operationId: operationId,
              entity: 'category',
              action: 'update',
              entityUuid: uuid,
              expectedVersion: existing.version,
              payloadJson: payloadJson,
              createdAt: now,
              status: const Value('pending'),
            ),
          );
    });
  }

  @override
  Future<void> deleteCategory(String uuid) async {
    final existing = await (_database.select(
      _database.categories,
    )..where((c) => c.uuid.equals(uuid))).getSingleOrNull();
    if (existing == null) return;

    final operationId = generateUuidV4();
    final now = DateTime.now().toUtc();

    await _database.transaction(() async {
      await (_database.delete(
        _database.categories,
      )..where((c) => c.uuid.equals(uuid))).go();

      await _database
          .into(_database.outboxMutations)
          .insert(
            OutboxMutationsCompanion.insert(
              operationId: operationId,
              entity: 'category',
              action: 'delete',
              entityUuid: uuid,
              expectedVersion: existing.version,
              payloadJson: '{}',
              createdAt: now,
              status: const Value('pending'),
            ),
          );
    });
  }
}
