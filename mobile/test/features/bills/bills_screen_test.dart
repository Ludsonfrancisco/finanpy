import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/bills/application/bills_controller.dart';
import 'package:lar_finance/features/bills/data/bills_repository.dart';
import 'package:lar_finance/features/bills/domain/bills_models.dart';
import 'package:lar_finance/features/bills/presentation/bills_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('BillsScreen renders header, metric cards, tabs and instances', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = _FakeBillsRepository();
    final controller = BillsController(repository: fakeRepo);

    await tester.pumpWidget(
      MaterialApp(
        theme: LarTheme.dark,
        home: BillsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title & Header
    expect(find.text('Contas Fixas & Vencimentos'), findsOneWidget);
    expect(find.text('SALDO LIVRE REAL'), findsOneWidget);
    expect(find.text('A VENCER NO MÊS'), findsOneWidget);
    expect(find.text('JÁ PAGAS'), findsOneWidget);
    expect(find.text('TOTAL COMPROMETIDO'), findsOneWidget);

    // Verify Tabs
    expect(find.text('Vencimentos do Mês'), findsOneWidget);
    expect(find.text('Cadastros Fixos'), findsOneWidget);

    // Verify Instance listed
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Internet Fibra'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('BillsScreen switches to Cadastros Fixos tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = _FakeBillsRepository();
    final controller = BillsController(repository: fakeRepo);

    await tester.pumpWidget(
      MaterialApp(
        theme: LarTheme.dark,
        home: BillsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Cadastros Fixos tab
    await tester.tap(find.text('Cadastros Fixos'));
    await tester.pumpAndSettle();

    expect(find.text('Aluguel Mensal'), findsOneWidget);
    expect(find.text('Internet 500mb'), findsOneWidget);

    controller.dispose();
  });
}

class _FakeBillsRepository implements BillsRepository {
  @override
  Future<BillsDataSnapshot> fetchBillsData({
    int? month,
    int? year,
    String? owner,
  }) async {
    return BillsDataSnapshot(
      instances: [
        BillInstanceModel(
          id: 1,
          billId: 10,
          name: 'Aluguel',
          month: 8,
          year: 2026,
          dueDate: DateTime(2026, 8, 10),
          dueDay: 10,
          amount: 2500.0,
          status: 'pending',
          type: 'expense',
          categoryName: 'Moradia',
          financialOwnerType: 'shared',
          financialOwnerName: 'Conjunto',
        ),
        BillInstanceModel(
          id: 2,
          billId: 11,
          name: 'Internet Fibra',
          month: 8,
          year: 2026,
          dueDate: DateTime(2026, 8, 15),
          dueDay: 15,
          amount: 150.0,
          status: 'paid',
          type: 'expense',
          categoryName: 'Serviços',
          financialOwnerType: 'self',
          financialOwnerName: 'Eu',
        ),
      ],
      recurringBills: [
        const RecurringBillModel(
          id: 10,
          name: 'Aluguel Mensal',
          amount: 2500.0,
          dueDay: 10,
          type: 'expense',
          categoryName: 'Moradia',
          financialOwnerType: 'shared',
          financialOwnerName: 'Conjunto',
          isActive: true,
          notes: '',
        ),
        const RecurringBillModel(
          id: 11,
          name: 'Internet 500mb',
          amount: 150.0,
          dueDay: 15,
          type: 'expense',
          categoryName: 'Serviços',
          financialOwnerType: 'self',
          financialOwnerName: 'Eu',
          isActive: true,
          notes: '',
        ),
      ],
      metrics: const BillsMetricsModel(
        month: 8,
        year: 2026,
        pendingExpensesTotal: 2500.0,
        paidExpensesTotal: 150.0,
        totalCommitted: 2650.0,
        overdueCount: 0,
        dueTodayCount: 0,
        totalAccountBalance: 5000.0,
        freeCashBalance: 2500.0,
      ),
    );
  }

  @override
  Future<RecurringBillModel> createRecurringBill({
    required String name,
    required double amount,
    required int dueDay,
    required String type,
    int? categoryId,
    int? defaultAccountId,
    String? financialOwnerType,
    bool isActive = true,
    String notes = '',
  }) async {
    return RecurringBillModel(
      id: 99,
      name: name,
      amount: amount,
      dueDay: dueDay,
      type: type,
      categoryName: 'Geral',
      financialOwnerType: financialOwnerType ?? 'shared',
      financialOwnerName: 'Conjunto',
      isActive: isActive,
      notes: notes,
    );
  }

  @override
  Future<RecurringBillModel> updateRecurringBill(
    int id, {
    String? name,
    double? amount,
    int? dueDay,
    String? type,
    int? categoryId,
    int? defaultAccountId,
    String? financialOwnerType,
    bool? isActive,
    String? notes,
  }) async {
    return RecurringBillModel(
      id: id,
      name: name ?? 'Atualizado',
      amount: amount ?? 100.0,
      dueDay: dueDay ?? 1,
      type: type ?? 'expense',
      categoryName: 'Geral',
      financialOwnerType: financialOwnerType ?? 'shared',
      financialOwnerName: 'Conjunto',
      isActive: isActive ?? true,
      notes: notes ?? '',
    );
  }

  @override
  Future<void> deleteRecurringBill(int id) async {}

  @override
  Future<BillInstanceModel> payBillInstance(
    int instanceId, {
    required int accountId,
    required double paidAmount,
    required DateTime paidDate,
  }) async {
    return BillInstanceModel(
      id: instanceId,
      billId: 1,
      name: 'Pago',
      month: 8,
      year: 2026,
      dueDate: DateTime.now(),
      dueDay: 1,
      amount: paidAmount,
      status: 'paid',
      type: 'expense',
      categoryName: 'Geral',
      financialOwnerType: 'shared',
      financialOwnerName: 'Conjunto',
    );
  }

  @override
  Future<BillInstanceModel> reopenBillInstance(int instanceId) async {
    return BillInstanceModel(
      id: instanceId,
      billId: 1,
      name: 'Reaberto',
      month: 8,
      year: 2026,
      dueDate: DateTime.now(),
      dueDay: 1,
      amount: 100.0,
      status: 'pending',
      type: 'expense',
      categoryName: 'Geral',
      financialOwnerType: 'shared',
      financialOwnerName: 'Conjunto',
    );
  }

  @override
  Future<BillsMetricsModel> fetchMetrics({
    int? month,
    int? year,
    String? owner,
  }) async {
    return BillsMetricsModel.empty;
  }
}
