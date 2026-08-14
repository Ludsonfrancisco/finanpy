import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/value_visibility_controller.dart';
import 'package:lar_finance/core/storage/app_database.dart';

void main() {
  test(
    'persists the global hidden preference across controller recreation',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftValueVisibilityRepository(database);
      final first = ValueVisibilityController(repository);

      await first.restore(returningFromInactive: false);
      expect(first.hidden, isFalse);

      await first.toggle();
      final setting = await (database.select(
        database.localSettings,
      )..where((row) => row.key.equals('values.hidden'))).getSingle();
      expect(setting.value, 'true');

      final restored = ValueVisibilityController(repository);
      await restored.restore(returningFromInactive: false);
      expect(restored.hidden, isTrue);
    },
  );

  test(
    'only defaults to hidden before reading when returning from inactive',
    () {
      final controller = ValueVisibilityController(
        _MemoryVisibilityRepository(),
      );

      controller.protectBeforeFirstReadForInactiveReturn();

      expect(controller.hidden, isTrue);
    },
  );

  test('a delayed restore cannot overwrite a newer toggle', () async {
    final repository = _ControlledVisibilityRepository();
    final controller = ValueVisibilityController(repository);

    final restore = controller.restore(returningFromInactive: false);
    await Future<void>.delayed(Duration.zero);
    final toggle = controller.toggle();
    repository.completeRead(false);
    await restore;
    repository.completeNextWrite();
    await toggle;

    expect(controller.hidden, isTrue);
    expect(repository.values['values.hidden'], 'true');
  });

  test(
    'concurrent toggles serialize persistence in invocation order',
    () async {
      final repository = _ControlledVisibilityRepository()..completeRead(false);
      final controller = ValueVisibilityController(repository);
      await controller.restore(returningFromInactive: false);

      final first = controller.toggle();
      await Future<void>.delayed(Duration.zero);
      final second = controller.toggle();

      expect(repository.writeValues, <bool>[true]);
      repository.completeNextWrite();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(repository.writeValues, <bool>[true, false]);
      repository.completeNextWrite();
      await second;

      expect(controller.hidden, isFalse);
      expect(repository.values['values.hidden'], 'false');
    },
  );

  test('a failed write leaves visibility and persistence unchanged', () async {
    final repository = _ControlledVisibilityRepository()..completeRead(false);
    final controller = ValueVisibilityController(repository);
    await controller.restore(returningFromInactive: false);

    final toggle = controller.toggle();
    await Future<void>.delayed(Duration.zero);
    repository.completeNextWriteError(StateError('storage unavailable'));

    await expectLater(toggle, throwsStateError);
    expect(controller.hidden, isFalse);
    expect(repository.values['values.hidden'], isNull);
  });
}

final class _MemoryVisibilityRepository implements ValueVisibilityRepository {
  final Map<String, String> values = <String, String>{};

  @override
  Future<bool?> readValuesHidden() async => switch (values['values.hidden']) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  @override
  Future<void> writeValuesHidden(bool hidden) async {
    values['values.hidden'] = hidden.toString();
  }
}

final class _ControlledVisibilityRepository
    implements ValueVisibilityRepository {
  final Map<String, String> values = <String, String>{};
  final Completer<bool?> _read = Completer<bool?>();
  final List<bool> writeValues = <bool>[];
  final List<Completer<void>> _writes = <Completer<void>>[];

  @override
  Future<bool?> readValuesHidden() => _read.future;

  @override
  Future<void> writeValuesHidden(bool hidden) {
    writeValues.add(hidden);
    final write = Completer<void>();
    _writes.add(write);
    return write.future.then((_) {
      values['values.hidden'] = hidden.toString();
    });
  }

  void completeRead(bool? value) {
    if (!_read.isCompleted) _read.complete(value);
  }

  void completeNextWrite() =>
      _writes.firstWhere((item) => !item.isCompleted).complete();

  void completeNextWriteError(Object error) =>
      _writes.firstWhere((item) => !item.isCompleted).completeError(error);
}
