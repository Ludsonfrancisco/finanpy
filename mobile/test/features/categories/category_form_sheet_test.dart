import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/categories/data/categories_repository.dart';
import 'package:lar_finance/features/categories/domain/categories_models.dart';
import 'package:lar_finance/features/categories/presentation/widgets/category_form_sheet.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockCategoriesRepository mockRepo;

  setUp(() {
    mockRepo = _MockCategoriesRepository();
  });

  Widget buildTestApp({
    CategoryItem? initialItem,
    VoidCallback? onSaved,
    VoidCallback? onDeleted,
  }) {
    return MaterialApp(
      theme: LarTheme.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      home: Scaffold(
        body: CategoryFormSheet(
          repository: mockRepo,
          initialItem: initialItem,
          onSaved: onSaved,
          onDeleted: onDeleted,
        ),
      ),
    );
  }

  testWidgets(
    'CategoryFormSheet renders in create mode and validates empty name',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Nova Categoria'), findsOneWidget);
      expect(find.text('Despesa'), findsOneWidget);
      expect(find.text('Receita'), findsOneWidget);
      expect(find.text('Criar Categoria'), findsOneWidget);

      await tester.ensureVisible(find.text('Criar Categoria'));
      await tester.tap(find.text('Criar Categoria'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome da categoria'), findsOneWidget);
    },
  );

  testWidgets('CategoryFormSheet creates category on valid submit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    var saved = false;
    await tester.pumpWidget(buildTestApp(onSaved: () => saved = true));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ex: Alimentação, Lazer, Salário'),
      'Supermercado',
    );
    await tester.ensureVisible(find.text('Criar Categoria'));
    await tester.tap(find.text('Criar Categoria'));
    await tester.pumpAndSettle();

    expect(mockRepo.createdCategories, hasLength(1));
    expect(mockRepo.createdCategories.first['name'], 'Supermercado');
    expect(saved, isTrue);
  });

  testWidgets('CategoryFormSheet renders in edit mode and updates category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final item = CategoryItem(
      uuid: 'cat-123',
      name: 'Lazer & Viagens',
      type: TransactionType.expense,
      color: '#C7A35A',
      version: 1,
      updatedAt: DateTime.utc(2026, 8, 14),
    );

    var saved = false;
    await tester.pumpWidget(
      buildTestApp(initialItem: item, onSaved: () => saved = true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Editar Categoria'), findsOneWidget);
    expect(find.text('Salvar Alterações'), findsOneWidget);
    expect(find.text('Excluir Categoria'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ex: Alimentação, Lazer, Salário'),
      'Lazer & Passeios',
    );
    await tester.ensureVisible(find.text('Salvar Alterações'));
    await tester.tap(find.text('Salvar Alterações'));
    await tester.pumpAndSettle();

    expect(mockRepo.updatedCategories, hasLength(1));
    expect(mockRepo.updatedCategories.first['uuid'], 'cat-123');
    expect(mockRepo.updatedCategories.first['name'], 'Lazer & Passeios');
    expect(saved, isTrue);
  });

  testWidgets('CategoryFormSheet confirms and deletes category in edit mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final item = CategoryItem(
      uuid: 'cat-456',
      name: 'Investimentos',
      type: TransactionType.expense,
      color: '#2F756A',
      version: 1,
      updatedAt: DateTime.utc(2026, 8, 14),
    );

    var deleted = false;
    await tester.pumpWidget(
      buildTestApp(initialItem: item, onDeleted: () => deleted = true),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Excluir Categoria'));
    await tester.tap(find.text('Excluir Categoria'));
    await tester.pumpAndSettle();

    // Dialog appears
    expect(
      find.text('Deseja realmente excluir a categoria "Investimentos"?'),
      findsOneWidget,
    );

    // Tap confirm Excluir
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(mockRepo.deletedUuids, contains('cat-456'));
    expect(deleted, isTrue);
  });
}

final class _MockCategoriesRepository implements CategoriesRepository {
  final List<Map<String, Object?>> createdCategories = [];
  final List<Map<String, Object?>> updatedCategories = [];
  final List<String> deletedUuids = [];

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
  }) async {
    createdCategories.add({
      'name': name,
      'type': type,
      'color': color,
      'icon': icon,
    });
    return 'cat-new-uuid';
  }

  @override
  Future<void> updateCategory({
    required String uuid,
    required String name,
    required TransactionType type,
    required String color,
    String? icon,
  }) async {
    updatedCategories.add({
      'uuid': uuid,
      'name': name,
      'type': type,
      'color': color,
      'icon': icon,
    });
  }

  @override
  Future<void> deleteCategory(String uuid) async {
    deletedUuids.add(uuid);
  }
}
