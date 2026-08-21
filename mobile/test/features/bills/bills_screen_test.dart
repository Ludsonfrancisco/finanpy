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
    expect(find.text(r'R$ 10.000,01'), findsWidgets);
    expect(find.text(r'R$ 0,01'), findsWidgets);

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
          amountMinor: 1000001,
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
          amountMinor: 1,
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
          amountMinor: 1000001,
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
          amountMinor: 1,
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
        pendingExpensesTotalMinor: 1000001,
        paidExpensesTotalMinor: 1,
        totalCommittedMinor: 1000002,
        overdueCount: 0,
        dueTodayCount: 0,
        totalAccountBalanceMinor: 2000001,
        freeCashBalanceMinor: 1000000,
      ),
    );
  }

  @override
  Future<RecurringBillModel> createRecurringBill({
    required String name,
    required int amountMinor,
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
      amountMinor: amountMinor,
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
    int? amountMinor,
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
      amountMinor: amountMinor ?? 10000,
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
    required int paidAmountMinor,
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
      amountMinor: paidAmountMinor,
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
      amountMinor: 10000,
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
