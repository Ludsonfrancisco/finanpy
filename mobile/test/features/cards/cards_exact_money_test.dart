import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/accounts/domain/accounts_models.dart';
import 'package:lar_finance/features/cards/application/cards_controller.dart';
import 'package:lar_finance/features/cards/data/cards_repository.dart';
import 'package:lar_finance/features/cards/domain/cards_models.dart';
import 'package:lar_finance/features/cards/presentation/widgets/card_expense_sheet.dart';
import 'package:lar_finance/features/cards/presentation/widgets/card_form_sheet.dart';
import 'package:lar_finance/features/cards/presentation/widgets/pay_invoice_sheet.dart';

import '../../support/recording_session_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('card money domain', () {
    test('keeps every cent and percentage stays double', () {
      final card = CreditCardModel.fromJson(validCardJson());

      expect(card.limitMinor, 1000001);
      expect(card.availableLimitMinor, 999999);
      expect(card.unpaidExpensesTotalMinor, 2);
      expect(card.currentInvoiceTotalMinor, 1);
      expect(card.limitUsagePercent, 12.5);
    });

    test('expense invoice and summary JSON use minor units', () {
      expect(CardExpenseModel.fromJson(expenseJson('0.01')).amountMinor, 1);

      final invoice = CardInvoiceModel.fromJson(invoiceJson('10.01', '0.01'));
      expect(invoice.totalAmountMinor, 1001);
      expect(invoice.paidAmountMinor, 1);

      final summary = CardsSummaryModel.fromJson(summaryJson());
      expect(summary.totalLimitMinor, 1000001);
      expect(summary.totalUsedMinor, 2);
      expect(summary.totalAvailableMinor, 999999);
      expect(summary.totalCurrentInvoicesMinor, 1);
    });

    test('malformed card money never becomes zero', () {
      final overPrecise = validCardJson(limit: '1.001');
      expect(
        () => CreditCardModel.fromJson(overPrecise),
        throwsFormatException,
      );

      final numeric = validCardJson(limit: 1.01);
      expect(() => CreditCardModel.fromJson(numeric), throwsFormatException);
    });
  });

  group('card money HTTP boundary', () {
    test('create and update card send exact decimal strings', () async {
      final transport = _successfulTransport(validCardJson());
      final repository = HttpCardsRepository(
        recordingSessionTransport(transport),
      );

      await repository.createCard(
        name: 'Casa',
        limitMinor: 1000001,
        closingDay: 10,
        dueDay: 17,
      );
      await repository.updateCard(1, limitMinor: 1);

      expect(transport.requests, hasLength(2));
      expect(_requestData(transport.requests[0])['limit'], '10000.01');
      expect(_requestData(transport.requests[1])['limit'], '0.01');
    });

    test('create expense sends cents and ISO date exactly', () async {
      final transport = _successfulTransport(<String, Object?>{
        'expenses': <Object?>[expenseJson('0.03')],
      });
      final repository = HttpCardsRepository(
        recordingSessionTransport(transport),
      );

      final expenses = await repository.createExpense(
        cardId: 1,
        description: 'Teste',
        amountMinor: 3,
        date: DateTime(2026, 8, 20),
        categoryId: 4,
        installmentsCount: 3,
      );

      expect(expenses.single.amountMinor, 3);
      final data = _requestData(transport.requests.single);
      expect(data['amount'], '0.03');
      expect(data['date'], '2026-08-20');
      expect(data['installments_count'], 3);
    });

    test('pay invoice sends one cent and ISO date exactly', () async {
      final transport = _successfulTransport(invoiceJson('0.01', '0.01'));
      final repository = HttpCardsRepository(
        recordingSessionTransport(transport),
      );

      final invoice = await repository.payInvoice(
        3,
        accountId: 4,
        paidAmountMinor: 1,
        paymentDate: DateTime(2026, 8, 20),
      );

      expect(invoice.paidAmountMinor, 1);
      final data = _requestData(transport.requests.single);
      expect(data['paid_amount'], '0.01');
      expect(data['payment_date'], '2026-08-20');
    });
  });

  group('card money forms', () {
    testWidgets('submit exact pt-BR values as minor units', (tester) async {
      final cardRepository = _RecordingCardsRepository();
      await _pumpCardForm(tester, cardRepository);
      await tester.enterText(find.byType(TextFormField).at(0), 'Casa');
      await tester.enterText(find.byType(TextFormField).at(1), r'R$ 1.234,56');
      await tester.tap(find.text('Cadastrar Cartão'));
      await tester.pumpAndSettle();
      expect(cardRepository.createdLimitMinor, 123456);

      final expenseRepository = _RecordingCardsRepository();
      await _pumpExpenseForm(tester, expenseRepository);
      await tester.enterText(find.byType(TextFormField).at(0), 'Mercado');
      await tester.enterText(find.byType(TextFormField).at(1), r'R$ 1.234,56');
      await tester.tap(find.text('Lançar na Fatura'));
      await tester.pumpAndSettle();
      expect(expenseRepository.createdExpenseMinor, 123456);

      final paymentRepository = _RecordingCardsRepository();
      await _pumpPaymentForm(tester, paymentRepository);
      await tester.enterText(find.byType(TextFormField), r'R$ 1.234,56');
      await tester.tap(find.text('Confirmar Pagamento'));
      await tester.pumpAndSettle();
      expect(paymentRepository.paidInvoiceMinor, 123456);
    });

    testWidgets('reject invalid or non-positive card values', (tester) async {
      for (final invalid in <String>['1,234', '0', '0,00', '-1,00']) {
        final repository = _RecordingCardsRepository();
        await _pumpCardForm(tester, repository);
        await tester.enterText(find.byType(TextFormField).at(0), 'Casa');
        await tester.enterText(find.byType(TextFormField).at(1), invalid);
        await tester.tap(find.text('Cadastrar Cartão'));
        await tester.pump();

        expect(find.text('Informe um limite válido'), findsOneWidget);
        expect(repository.createdLimitMinor, isNull);
      }
    });

    testWidgets('reject invalid or non-positive expense values', (
      tester,
    ) async {
      for (final invalid in <String>['1,234', '0', '0,00', '-1,00']) {
        final repository = _RecordingCardsRepository();
        await _pumpExpenseForm(tester, repository);
        await tester.enterText(find.byType(TextFormField).at(0), 'Mercado');
        await tester.enterText(find.byType(TextFormField).at(1), invalid);
        await tester.tap(find.text('Lançar na Fatura'));
        await tester.pump();

        expect(find.text('Informe um valor maior que 0'), findsOneWidget);
        expect(repository.createdExpenseMinor, isNull);
      }
    });

    testWidgets('reject invalid or non-positive invoice payments', (
      tester,
    ) async {
      for (final invalid in <String>['1,234', '0', '0,00', '-1,00']) {
        final repository = _RecordingCardsRepository();
        await _pumpPaymentForm(tester, repository);
        await tester.enterText(find.byType(TextFormField), invalid);
        await tester.tap(find.text('Confirmar Pagamento'));
        await tester.pump();

        expect(find.text('Informe um valor válido'), findsOneWidget);
        expect(repository.paidInvoiceMinor, isNull);
      }
    });

    testWidgets('installment preview mirrors exact backend cent split', (
      tester,
    ) async {
      final repository = _RecordingCardsRepository();
      await _pumpExpenseForm(tester, repository);
      await tester.enterText(find.byType(TextFormField).at(0), 'Mercado');
      await tester.enterText(find.byType(TextFormField).at(1), '100,00');
      await tester.tap(find.text('1x (À vista)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3x').last);
      await tester.pumpAndSettle();

      expect(find.text(r'1x de R$ 33,34 + 2x de R$ 33,33'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), '0,03');
      await tester.tap(find.text('3x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2x').last);
      await tester.pumpAndSettle();

      expect(find.text(r'1x de R$ 0,01 + 1x de R$ 0,02'), findsOneWidget);
    });
  });

  test('malformed refresh preserves the last valid card snapshot', () async {
    final repository = _RecordingCardsRepository();
    final controller = CardsController(repository: repository);
    addTearDown(controller.dispose);
    await controller.start();
    final cards = controller.state.cards;
    final summary = controller.state.summary;
    final selectedCard = controller.state.selectedCard;

    repository.failFetch = true;
    await controller.loadCards();

    expect(controller.state.cards, same(cards));
    expect(controller.state.summary, same(summary));
    expect(controller.state.selectedCard, same(selectedCard));
    expect(controller.state.errorMessage, isNotNull);
  });
}

Future<void> _pumpCardForm(
  WidgetTester tester,
  _RecordingCardsRepository repository,
) async {
  await _pumpSheet(
    tester,
    CardFormSheet(controller: CardsController(repository: repository)),
  );
}

Future<void> _pumpExpenseForm(
  WidgetTester tester,
  _RecordingCardsRepository repository,
) async {
  await _pumpSheet(
    tester,
    CardExpenseSheet(
      controller: CardsController(repository: repository),
      cards: repository.cards,
    ),
  );
}

Future<void> _pumpPaymentForm(
  WidgetTester tester,
  _RecordingCardsRepository repository,
) async {
  await _pumpSheet(
    tester,
    PayInvoiceSheet(
      controller: CardsController(repository: repository),
      invoice: repository.invoice,
      accounts: <AccountItem>[
        AccountItem(
          uuid: '4',
          name: 'Conta',
          type: AccountType.checking,
          initialBalanceMinor: 1000001,
          currentBalanceMinor: 1000001,
          currency: 'BRL',
          ownerName: 'Eu',
          ownerType: 'self',
          updatedAt: DateTime.utc(2026, 8, 20),
        ),
      ],
    ),
  );
}

Future<void> _pumpSheet(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: LarTheme.dark,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

RecordingApiTransport _successfulTransport(Object? response) =>
    RecordingApiTransport(
      (_) async => ApiResponse(statusCode: 200, data: response),
    );

Map<String, Object?> _requestData(RecordedApiRequest request) =>
    (request.data! as Map).cast<String, Object?>();

Map<String, dynamic> validCardJson({Object? limit = '10000.01'}) =>
    <String, dynamic>{
      'id': 1,
      'name': 'Casa',
      'limit': limit,
      'available_limit': '9999.99',
      'unpaid_expenses_total': '0.02',
      'current_invoice_total': '0.01',
      'limit_usage_percent': 12.5,
      'closing_day': 10,
      'due_day': 17,
      'color': '#2F756A',
      'brand': 'visa',
      'brand_display': 'Visa',
      'last_digits': '1234',
      'is_active': true,
      'financial_owner_id': 1,
      'financial_owner_type': 'self',
      'financial_owner_name': 'Eu',
    };

Map<String, dynamic> expenseJson(Object? amount) => <String, dynamic>{
  'id': 2,
  'card_id': 1,
  'card_name': 'Casa',
  'invoice_id': 3,
  'description': 'Teste',
  'amount': amount,
  'date': '2026-08-20',
  'category_id': 4,
  'category_name': 'Geral',
  'financial_owner_id': 1,
  'financial_owner_type': 'self',
  'financial_owner_name': 'Eu',
  'installments_count': 1,
  'installment_number': 1,
  'installment_group_id': '00000000-0000-4000-8000-000000000001',
};

Map<String, dynamic> invoiceJson(Object? total, Object? paid) =>
    <String, dynamic>{
      'id': 3,
      'card_id': 1,
      'card_name': 'Casa',
      'month': 8,
      'year': 2026,
      'closing_date': '2026-08-10',
      'due_date': '2026-08-17',
      'status': 'open',
      'status_display': 'Aberta',
      'total_amount': total,
      'paid_amount': paid,
      'paid_at': null,
      'payment_account_id': null,
      'payment_account_name': null,
      'expenses_count': 0,
      'expenses': <Object?>[],
    };

Map<String, dynamic> summaryJson() => <String, dynamic>{
  'month': 8,
  'year': 2026,
  'total_limit': '10000.01',
  'total_used': '0.02',
  'total_available': '9999.99',
  'total_current_invoices': '0.01',
  'limit_usage_percent': 12.5,
};

final class _RecordingCardsRepository implements CardsRepository {
  _RecordingCardsRepository()
    : cards = <CreditCardModel>[CreditCardModel.fromJson(validCardJson())],
      invoice = CardInvoiceModel.fromJson(invoiceJson('10000.01', '0.00'));

  final List<CreditCardModel> cards;
  final CardInvoiceModel invoice;
  int? createdLimitMinor;
  int? createdExpenseMinor;
  int? paidInvoiceMinor;
  bool failFetch = false;

  @override
  Future<CreditCardModel> createCard({
    required String name,
    required int limitMinor,
    required int closingDay,
    required int dueDay,
    String color = '#2F756A',
    String brand = 'visa',
    String lastDigits = '',
    String financialOwnerType = 'shared',
  }) async {
    createdLimitMinor = limitMinor;
    return cards.single;
  }

  @override
  Future<List<CardExpenseModel>> createExpense({
    required int cardId,
    required String description,
    required int amountMinor,
    required DateTime date,
    required int categoryId,
    int installmentsCount = 1,
    String? financialOwnerType,
  }) async {
    createdExpenseMinor = amountMinor;
    return <CardExpenseModel>[CardExpenseModel.fromJson(expenseJson('0.01'))];
  }

  @override
  Future<CardInvoiceModel> payInvoice(
    int invoiceId, {
    required int accountId,
    required int paidAmountMinor,
    required DateTime paymentDate,
  }) async {
    paidInvoiceMinor = paidAmountMinor;
    return invoice;
  }

  @override
  Future<CardsSnapshot> fetchCards({
    int? month,
    int? year,
    String? owner,
  }) async {
    if (failFetch) throw const FormatException('Invalid money response.');
    return CardsSnapshot(
      cards: cards,
      summary: CardsSummaryModel.fromJson(summaryJson()),
    );
  }

  @override
  Future<CardDetailSnapshot> fetchCardDetail(
    int cardId, {
    int? month,
    int? year,
  }) async => CardDetailSnapshot(
    card: cards.single,
    selectedInvoice: invoice,
    futureInvoices: const <CardInvoiceModel>[],
  );

  @override
  Future<CreditCardModel> updateCard(
    int id, {
    String? name,
    int? limitMinor,
    int? closingDay,
    int? dueDay,
    String? color,
    String? brand,
    String? lastDigits,
    String? financialOwnerType,
  }) async {
    createdLimitMinor = limitMinor;
    return cards.single;
  }

  @override
  Future<void> deleteCard(int id) async {}

  @override
  Future<void> deleteExpense(int expenseId, {bool deleteAll = false}) async {}

  @override
  Future<CardInvoiceModel> reopenInvoice(int invoiceId) async => invoice;
}
