import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/home/domain/home_snapshot.dart';
import 'package:lar_finance/features/transactions/data/transactions_repository.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';
import 'package:lar_finance/features/transactions/presentation/widgets/transaction_form_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockTransactionsRepository mockRepo;

  setUp(() {
    mockRepo = _MockTransactionsRepository();
  });

  Widget buildTestApp({
    TransactionItem? initialItem,
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
        body: TransactionFormSheet(
          repository: mockRepo,
          initialItem: initialItem,
          onSaved: onSaved,
          onDeleted: onDeleted,
        ),
      ),
    );
  }

  testWidgets(
    'TransactionFormSheet renders in create mode and validates empty fields',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Nova Movimentação'), findsOneWidget);
      expect(find.text('Despesa'), findsOneWidget);
      expect(find.text('Receita'), findsOneWidget);
      expect(find.text('Criar Lançamento'), findsOneWidget);

      // Tap submit without filling fields
      await tester.ensureVisible(find.text('Criar Lançamento'));
      await tester.tap(find.text('Criar Lançamento'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o valor'), findsOneWidget);
    },
  );

  testWidgets(
    'TransactionFormSheet creates a new transaction on valid submit',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      var saved = false;
      await tester.pumpWidget(buildTestApp(onSaved: () => saved = true));
      await tester.pumpAndSettle();

      // Fill amount and description
      await tester.enterText(
        find.widgetWithText(TextFormField, '0,00'),
        '45,90',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ex: Supermercado, Salário'),
        'Supermercado',
      );

      await tester.ensureVisible(find.text('Criar Lançamento'));
      await tester.tap(find.text('Criar Lançamento'));
      await tester.pumpAndSettle();

      expect(mockRepo.createdTransactions, hasLength(1));
      expect(mockRepo.createdTransactions.first['description'], 'Supermercado');
      expect(mockRepo.createdTransactions.first['amountMinor'], 4590);
      expect(saved, isTrue);
    },
  );

  testWidgets(
    'TransactionFormSheet renders in edit mode and updates transaction',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final item = TransactionItem(
        uuid: 'tx-123',
        description: 'Lanche',
        categoryName: 'Alimentação',
        categoryColor: '#2F756A',
        categoryIcon: null,
        accountName: 'Nubank',
        accountUuid: 'acc-1',
        ownerName: 'Ludson',
        ownerType: 'self',
        date: DateTime.utc(2026, 8, 10),
        type: TransactionType.expense,
        amountMinor: 2500,
        signedAmountMinor: -2500,
        updatedAt: DateTime.utc(2026, 8, 10),
      );

      var saved = false;
      await tester.pumpWidget(
        buildTestApp(initialItem: item, onSaved: () => saved = true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editar Movimentação'), findsOneWidget);
      expect(find.text('Salvar Alterações'), findsOneWidget);
      expect(find.text('Excluir Movimentação'), findsOneWidget);

      // Change description
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ex: Supermercado, Salário'),
        'Lanche Especial',
      );
      await tester.ensureVisible(find.text('Salvar Alterações'));
      await tester.tap(find.text('Salvar Alterações'));
      await tester.pumpAndSettle();

      expect(mockRepo.updatedTransactions, hasLength(1));
      expect(mockRepo.updatedTransactions.first['uuid'], 'tx-123');
      expect(
        mockRepo.updatedTransactions.first['description'],
        'Lanche Especial',
      );
      expect(saved, isTrue);
    },
  );
}

final class _MockTransactionsRepository implements TransactionsRepository {
  final List<Map<String, Object?>> createdTransactions = [];
  final List<Map<String, Object?>> updatedTransactions = [];
  final List<String> deletedUuids = [];

  @override
  Future<HomeOwnerScopes> readOwnerScopes() async {
    return const HomeOwnerScopes(
      selfScope: OwnerScope.self('owner-1'),
      spouseScope: OwnerScope.spouse('owner-2'),
    );
  }

  @override
  Stream<TransactionsSnapshot> watchTransactions(
    OwnerScope scope,
    TransactionFilters filters,
  ) {
    return Stream.value(
      TransactionsSnapshot(
        scope: scope,
        groups: const [],
        totalCount: 0,
        totalIncomeMinor: 0,
        totalExpenseMinor: 0,
        lastSyncedAt: null,
        availableAccounts: const [
          TransactionFilterOption(uuid: 'acc-1', name: 'Nubank'),
        ],
        availableCategories: const [
          TransactionFilterOption(uuid: 'cat-1', name: 'Alimentação'),
        ],
      ),
    );
  }

  @override
  Future<List<TransactionFilterOption>> readAvailableAccounts() async {
    return const [TransactionFilterOption(uuid: 'acc-1', name: 'Nubank')];
  }

  @override
  Future<List<TransactionCategoryOption>> readAvailableCategories(
    TransactionType? type,
  ) async {
    return const [
      TransactionCategoryOption(
        uuid: 'cat-1',
        name: 'Alimentação',
        type: TransactionType.expense,
        color: '#2F756A',
      ),
    ];
  }

  @override
  Future<List<TransactionOwnerOption>> readAvailableOwners() async {
    return const [
      TransactionOwnerOption(uuid: 'owner-1', name: 'Ludson', type: 'self'),
    ];
  }

  @override
  Future<String> createTransaction({
    required String description,
    required int amountMinor,
    required DateTime date,
    required TransactionType type,
    required String accountUuid,
    required String categoryUuid,
    required String financialOwnerUuid,
  }) async {
    createdTransactions.add({
      'description': description,
      'amountMinor': amountMinor,
      'date': date,
      'type': type,
      'accountUuid': accountUuid,
      'categoryUuid': categoryUuid,
      'financialOwnerUuid': financialOwnerUuid,
    });
    return 'tx-created-uuid';
  }

  @override
  Future<void> updateTransaction({
    required String uuid,
    required String description,
    required int amountMinor,
    required DateTime date,
    required TransactionType type,
    required String accountUuid,
    required String categoryUuid,
    required String financialOwnerUuid,
  }) async {
    updatedTransactions.add({
      'uuid': uuid,
      'description': description,
      'amountMinor': amountMinor,
      'date': date,
      'type': type,
      'accountUuid': accountUuid,
      'categoryUuid': categoryUuid,
      'financialOwnerUuid': financialOwnerUuid,
    });
  }

  @override
  Future<void> deleteTransaction(String uuid) async {
    deletedUuids.add(uuid);
  }
}
