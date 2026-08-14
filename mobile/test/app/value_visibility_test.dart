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
