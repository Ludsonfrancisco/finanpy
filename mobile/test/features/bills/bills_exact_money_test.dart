import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/accounts/domain/accounts_models.dart';
import 'package:lar_finance/features/bills/application/bills_controller.dart';
import 'package:lar_finance/features/bills/data/bills_repository.dart';
import 'package:lar_finance/features/bills/domain/bills_models.dart';
import 'package:lar_finance/features/bills/presentation/widgets/bill_form_sheet.dart';
import 'package:lar_finance/features/bills/presentation/widgets/pay_bill_sheet.dart';

import '../../support/recording_session_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('exact bill money domain', () {
    test('bill instance and recurring rule preserve one cent', () {
      expect(BillInstanceModel.fromJson(instanceJson('0.01')).amountMinor, 1);
      expect(
        RecurringBillModel.fromJson(ruleJson('10000.01')).amountMinor,
        1000001,
      );
    });

    test('bill metrics preserve all exact totals', () {
      final metrics = BillsMetricsModel.fromJson(<String, Object?>{
        'month': 8,
        'year': 2026,
        'pending_expenses_total': '0.01',
        'paid_expenses_total': '0.02',
        'total_committed': '0.03',
        'overdue_count': 1,
        'due_today_count': 2,
        'total_account_balance': '10000.01',
        'free_cash_balance': '9999.98',
      });

      expect(metrics.pendingExpensesTotalMinor, 1);
      expect(metrics.paidExpensesTotalMinor, 2);
      expect(metrics.totalCommittedMinor, 3);
      expect(metrics.totalAccountBalanceMinor, 1000001);
      expect(metrics.freeCashBalanceMinor, 999998);
    });

    test('malformed bill money never becomes zero', () {
      expect(
        () => RecurringBillModel.fromJson(ruleJson('1.001')),
        throwsFormatException,
      );
      expect(
        () => RecurringBillModel.fromJson(ruleJson(1.01)),
        throwsFormatException,
      );
    });
  });

  group('exact bill money HTTP boundary', () {
    test('create and update recurring bills send decimal strings', () async {
      final transport = _successfulTransport(ruleJson('10000.01'));
      final repository = HttpBillsRepository(
        recordingSessionTransport(transport),
      );

      await repository.createRecurringBill(
        name: 'Internet',
        amountMinor: 1000001,
        dueDay: 10,
        type: 'expense',
      );
      await repository.updateRecurringBill(2, amountMinor: 1);

      expect(transport.requests, hasLength(2));
      expect(_requestData(transport.requests[0])['amount'], '10000.01');
      expect(_requestData(transport.requests[1])['amount'], '0.01');
    });

    test('pay bill sends one cent and ISO date exactly', () async {
      final transport = _successfulTransport(instanceJson('0.01'));
      final repository = HttpBillsRepository(
        recordingSessionTransport(transport),
      );

      final instance = await repository.payBillInstance(
        1,
        accountId: 4,
        paidAmountMinor: 1,
        paidDate: DateTime(2026, 8, 20),
      );

      expect(instance.amountMinor, 1);
      final data = _requestData(transport.requests.single);
      expect(data['paid_amount'], '0.01');
      expect(data['paid_date'], '2026-08-20');
    });
  });

  group('exact bill money forms', () {
    testWidgets('submit exact pt-BR values as minor units', (tester) async {
      int? createdAmountMinor;
      await _pumpSheet(
        tester,
        BillFormSheet(
          onSave:
              ({
                required name,
                required amountMinor,
                required dueDay,
                required type,
                financialOwnerType,
                isActive = true,
                notes = '',
              }) async {
                createdAmountMinor = amountMinor;
              },
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Internet');
      await tester.enterText(find.byType(TextFormField).at(1), r'R$ 1.234,56');
      await tester.tap(find.text('Cadastrar Conta Fixa'));
      await tester.pumpAndSettle();
      expect(createdAmountMinor, 123456);

      int? capturedPaidAmountMinor;
      await _pumpSheet(
        tester,
        PayBillSheet(
          instance: BillInstanceModel.fromJson(instanceJson('10000.01')),
          accounts: <AccountItem>[_account()],
          onPay:
              ({
                required accountId,
                required paidAmountMinor,
                required paidDate,
              }) async {
                capturedPaidAmountMinor = paidAmountMinor;
              },
        ),
      );
      await tester.enterText(find.byType(TextFormField), r'R$ 1.234,56');
      await tester.tap(find.text('Confirmar Pagamento'));
      await tester.pumpAndSettle();
      expect(capturedPaidAmountMinor, 123456);
    });

    testWidgets('edit starts exact and submits one cent', (tester) async {
      int? capturedAmountMinor;
      await _pumpSheet(
        tester,
        BillFormSheet(
          initialBill: RecurringBillModel.fromJson(ruleJson('10000.01')),
          onSave:
              ({
                required name,
                required amountMinor,
                required dueDay,
                required type,
                financialOwnerType,
                isActive = true,
                notes = '',
              }) async {
                capturedAmountMinor = amountMinor;
              },
        ),
      );

      expect(find.widgetWithText(TextFormField, '10000,01'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), '0,01');
      await tester.tap(find.text('Salvar Alterações'));
      await tester.pumpAndSettle();

      expect(capturedAmountMinor, 1);
    });

    testWidgets('reject invalid or non-positive recurring bill values', (
      tester,
    ) async {
      for (final invalid in <String>['1,234', '0', '0,00', '-1,00']) {
        int? capturedAmountMinor;
        await _pumpSheet(
          tester,
          BillFormSheet(
            onSave:
                ({
                  required name,
                  required amountMinor,
                  required dueDay,
                  required type,
                  financialOwnerType,
                  isActive = true,
                  notes = '',
                }) async {
                  capturedAmountMinor = amountMinor;
                },
          ),
        );
        await tester.enterText(find.byType(TextFormField).at(0), 'Internet');
        await tester.enterText(find.byType(TextFormField).at(1), invalid);
        await tester.tap(find.text('Cadastrar Conta Fixa'));
        await tester.pump();

        expect(find.text('Informe um valor válido'), findsOneWidget);
        expect(capturedAmountMinor, isNull);
      }
    });

    testWidgets('reject invalid or non-positive bill payments', (tester) async {
      for (final invalid in <String>['1,234', '0', '0,00', '-1,00']) {
        int? capturedAmountMinor;
        await _pumpSheet(
          tester,
          PayBillSheet(
            instance: BillInstanceModel.fromJson(instanceJson('10000.01')),
            accounts: <AccountItem>[_account()],
            onPay:
                ({
                  required accountId,
                  required paidAmountMinor,
                  required paidDate,
                }) async {
                  capturedAmountMinor = paidAmountMinor;
                },
          ),
        );
        await tester.enterText(find.byType(TextFormField), invalid);
        await tester.tap(find.text('Confirmar Pagamento'));
        await tester.pump();

        expect(find.text('Informe um valor válido'), findsOneWidget);
        expect(capturedAmountMinor, isNull);
      }
    });
  });

  test('malformed refresh preserves the last valid bills snapshot', () async {
    final repository = _RecordingBillsRepository();
    final controller = BillsController(repository: repository);
    addTearDown(controller.dispose);
    await controller.start();
    final instances = controller.state.instances;
    final recurringBills = controller.state.recurringBills;
    final metrics = controller.state.metrics;

    repository.failFetch = true;
    await controller.loadData();

    expect(controller.state.instances, same(instances));
    expect(controller.state.recurringBills, same(recurringBills));
    expect(controller.state.metrics, same(metrics));
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.error, isA<FormatException>());
  });
}

Future<void> _pumpSheet(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: LarTheme.dark,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

AccountItem _account() => AccountItem(
  uuid: '4',
  name: 'Conta',
  type: AccountType.checking,
  initialBalanceMinor: 1000001,
  currentBalanceMinor: 1000001,
  currency: 'BRL',
  ownerName: 'Eu',
  ownerType: 'self',
  updatedAt: DateTime.utc(2026, 8, 20),
);

RecordingApiTransport _successfulTransport(Object? response) =>
    RecordingApiTransport(
      (_) async => ApiResponse(statusCode: 200, data: response),
    );

Map<String, Object?> _requestData(RecordedApiRequest request) =>
    (request.data! as Map).cast<String, Object?>();

Map<String, Object?> instanceJson(Object? amount) => <String, Object?>{
  'id': 1,
  'bill_id': 2,
  'name': 'Internet',
  'month': 8,
  'year': 2026,
  'due_date': '2026-08-10',
  'due_day': 10,
  'amount': amount,
  'status': 'pending',
  'paid_at': null,
  'type': 'expense',
  'category_name': 'Casa',
  'category_id': 3,
  'account_name': null,
  'account_id': null,
  'default_account_id': 4,
  'financial_owner_type': 'self',
  'financial_owner_name': 'Eu',
};

Map<String, Object?> ruleJson(Object? amount) => <String, Object?>{
  'id': 2,
  'name': 'Internet',
  'amount': amount,
  'due_day': 10,
  'type': 'expense',
  'category_id': 3,
  'category_name': 'Casa',
  'default_account_id': 4,
  'default_account_name': 'Conta',
  'financial_owner_type': 'self',
  'financial_owner_name': 'Eu',
  'is_active': true,
  'notes': '',
};

final class _RecordingBillsRepository implements BillsRepository {
  _RecordingBillsRepository()
    : snapshot = BillsDataSnapshot(
        instances: <BillInstanceModel>[
          BillInstanceModel.fromJson(instanceJson('10000.01')),
        ],
        recurringBills: <RecurringBillModel>[
          RecurringBillModel.fromJson(ruleJson('0.01')),
        ],
        metrics: BillsMetricsModel.fromJson(<String, Object?>{
          'month': 8,
          'year': 2026,
          'pending_expenses_total': '10000.01',
          'paid_expenses_total': '0.01',
          'total_committed': '10000.02',
          'overdue_count': 0,
          'due_today_count': 0,
          'total_account_balance': '20000.01',
          'free_cash_balance': '9999.99',
        }),
      );

  final BillsDataSnapshot snapshot;
  bool failFetch = false;

  @override
  Future<BillsDataSnapshot> fetchBillsData({
    int? month,
    int? year,
    String? owner,
  }) async {
    if (failFetch) throw const FormatException('Invalid money response.');
    return snapshot;
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
  }) async => snapshot.recurringBills.single;

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
  }) async => snapshot.recurringBills.single;

  @override
  Future<void> deleteRecurringBill(int id) async {}

  @override
  Future<BillInstanceModel> payBillInstance(
    int instanceId, {
    required int accountId,
    required int paidAmountMinor,
    required DateTime paidDate,
  }) async => snapshot.instances.single;

  @override
  Future<BillInstanceModel> reopenBillInstance(int instanceId) async =>
      snapshot.instances.single;

  @override
  Future<BillsMetricsModel> fetchMetrics({
    int? month,
    int? year,
    String? owner,
  }) async => snapshot.metrics;
}
