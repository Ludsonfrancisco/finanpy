import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/app_database.dart';

abstract interface class ValueVisibilityRepository {
  Future<bool?> readValuesHidden();

  Future<void> writeValuesHidden(bool hidden);
}

final class DriftValueVisibilityRepository
    implements ValueVisibilityRepository {
  DriftValueVisibilityRepository(this._database);

  static const settingKey = 'values.hidden';

  final AppDatabase _database;

  @override
  Future<bool?> readValuesHidden() async {
    final setting = await (_database.select(
      _database.localSettings,
    )..where((row) => row.key.equals(settingKey))).getSingleOrNull();
    return switch (setting?.value) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  @override
  Future<void> writeValuesHidden(bool hidden) => _database
      .into(_database.localSettings)
      .insertOnConflictUpdate(
        LocalSettingsCompanion.insert(
          key: settingKey,
          value: hidden.toString(),
        ),
      );
}

final class ValueVisibilityController extends ChangeNotifier {
  ValueVisibilityController(this._repository);

  final ValueVisibilityRepository _repository;
  bool _hidden = false;
  Future<void> _operations = Future<void>.value();

  bool get hidden => _hidden;

  void protectBeforeFirstReadForInactiveReturn() {
    if (_hidden) return;
    _hidden = true;
    notifyListeners();
  }

  Future<void> restore({required bool returningFromInactive}) async {
    if (returningFromInactive) protectBeforeFirstReadForInactiveReturn();
    return _serialize(() async {
      final persisted = await _repository.readValuesHidden();
      _setHidden(persisted ?? false);
    });
  }

  Future<void> toggle() => _serialize(() async {
    final next = !_hidden;
    await _repository.writeValuesHidden(next);
    _setHidden(next);
  });

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _operations.then((_) => action());
    _operations = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  void _setHidden(bool next) {
    if (_hidden == next) return;
    _hidden = next;
    notifyListeners();
  }
}

final valueVisibilityRepositoryProvider = Provider<ValueVisibilityRepository>(
  (ref) =>
      throw UnimplementedError('Value visibility repository not configured'),
);

final valueVisibilityControllerProvider =
    ChangeNotifierProvider<ValueVisibilityController>(
      (ref) => ValueVisibilityController(
        ref.watch(valueVisibilityRepositoryProvider),
      ),
    );
