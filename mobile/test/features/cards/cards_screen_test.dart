import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/cards/application/cards_controller.dart';
import 'package:lar_finance/features/cards/data/cards_repository.dart';
import 'package:lar_finance/features/cards/domain/cards_models.dart';
import 'package:lar_finance/features/cards/presentation/cards_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('CardsScreen renders cards deck, metrics, tabs and invoice expenses', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = _FakeCardsRepository();
    final controller = CardsController(repository: fakeRepo);

    await tester.pumpWidget(
      MaterialApp(
        theme: LarTheme.dark,
        home: CardsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Cartões de Crédito'), findsOneWidget);

    // Verify Cards in deck
    expect(find.text('Nubank Ultravioleta'), findsOneWidget);
    expect(find.text('XP Infinite'), findsOneWidget);

    // Verify Selected Invoice metrics
    expect(find.text('FATURA 08/2026'), findsOneWidget);
    expect(find.text('Pagar Fatura'), findsOneWidget);

    // Verify Tabs
    expect(find.text('Compras da Fatura'), findsOneWidget);
    expect(find.text('Faturas Futuras'), findsOneWidget);

    // Verify Expenses
    expect(find.text('Supermercado Extra'), findsOneWidget);
    expect(find.text('Passagens Aéreas'), findsOneWidget);
    expect(find.text('1/3x'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('CardsScreen switches to Faturas Futuras tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = _FakeCardsRepository();
    final controller = CardsController(repository: fakeRepo);

    await tester.pumpWidget(
      MaterialApp(
        theme: LarTheme.dark,
        home: CardsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Switch tab
    await tester.tap(find.text('Faturas Futuras'));
    await tester.pumpAndSettle();

    expect(find.text('Fatura 09/2026'), findsOneWidget);
    expect(find.text('Fatura 10/2026'), findsOneWidget);

    controller.dispose();
  });
}

final class _FakeCardsRepository implements CardsRepository {
  final _cards = [
    const CreditCardModel(
      id: 1,
      name: 'Nubank Ultravioleta',
      limit: 10000.0,
      availableLimit: 7500.0,
      unpaidExpensesTotal: 2500.0,
      currentInvoiceTotal: 1500.0,
      limitUsagePercent: 25.0,
      closingDay: 10,
      dueDay: 17,
      color: '#820AD1',
      brand: 'mastercard',
      brandDisplay: 'Mastercard',
      lastDigits: '4321',
      isActive: true,
      financialOwnerId: 1,
      financialOwnerType: 'shared',
      financialOwnerName: 'Lar',
    ),
    const CreditCardModel(
      id: 2,
      name: 'XP Infinite',
      limit: 20000.0,
      availableLimit: 18000.0,
      unpaidExpensesTotal: 2000.0,
      currentInvoiceTotal: 1000.0,
      limitUsagePercent: 10.0,
      closingDay: 5,
      dueDay: 15,
      color: '#111111',
      brand: 'visa',
      brandDisplay: 'Visa',
      lastDigits: '9988',
      isActive: true,
      financialOwnerId: 2,
      financialOwnerType: 'self',
      financialOwnerName: 'Eu',
    ),
  ];

  @override
  Future<CardsSnapshot> fetchCards({int? month, int? year, String? owner}) async {
    return CardsSnapshot(
      cards: _cards,
      summary: const CardsSummaryModel(
        month: 8,
        year: 2026,
        totalLimit: 30000.0,
        totalUsed: 4500.0,
        totalAvailable: 25500.0,
        totalCurrentInvoices: 2500.0,
        limitUsagePercent: 15.0,
      ),
    );
  }

  @override
  Future<CardDetailSnapshot> fetchCardDetail(int cardId, {int? month, int? year}) async {
    final card = _cards.firstWhere((c) => c.id == cardId, orElse: () => _cards.first);
    return CardDetailSnapshot(
      card: card,
      selectedInvoice: CardInvoiceModel(
        id: 10,
        cardId: card.id,
        cardName: card.name,
        month: 8,
        year: 2026,
        closingDate: DateTime(2026, 8, 10),
        dueDate: DateTime(2026, 8, 17),
        status: 'open',
        statusDisplay: 'Aberta',
        totalAmount: 1500.0,
        paidAmount: 0.0,
        expensesCount: 2,
        expenses: [
          CardExpenseModel(
            id: 101,
            cardId: 1,
            cardName: 'Nubank Ultravioleta',
            invoiceId: 10,
            description: 'Supermercado Extra',
            amount: 500.0,
            date: DateTime(2026, 8, 2),
            categoryId: 1,
            categoryName: 'Alimentação',
            financialOwnerId: 1,
            financialOwnerType: 'shared',
            financialOwnerName: 'Lar',
            installmentsCount: 1,
            installmentNumber: 1,
            installmentGroupId: 'uuid-1',
          ),
          CardExpenseModel(
            id: 102,
            cardId: 1,
            cardName: 'Nubank Ultravioleta',
            invoiceId: 10,
            description: 'Passagens Aéreas',
            amount: 1000.0,
            date: DateTime(2026, 8, 3),
            categoryId: 2,
            categoryName: 'Viagem',
            financialOwnerId: 1,
            financialOwnerType: 'shared',
            financialOwnerName: 'Lar',
            installmentsCount: 3,
            installmentNumber: 1,
            installmentGroupId: 'uuid-2',
          ),
        ],
      ),
      futureInvoices: [
        CardInvoiceModel(
          id: 11,
          cardId: card.id,
          cardName: card.name,
          month: 9,
          year: 2026,
          closingDate: DateTime(2026, 9, 10),
          dueDate: DateTime(2026, 9, 17),
          status: 'open',
          statusDisplay: 'Aberta',
          totalAmount: 1000.0,
          paidAmount: 0.0,
          expensesCount: 1,
        ),
        CardInvoiceModel(
          id: 12,
          cardId: card.id,
          cardName: card.name,
          month: 10,
          year: 2026,
          closingDate: DateTime(2026, 10, 10),
          dueDate: DateTime(2026, 10, 17),
          status: 'open',
          statusDisplay: 'Aberta',
          totalAmount: 1000.0,
          paidAmount: 0.0,
          expensesCount: 1,
        ),
      ],
    );
  }

  @override
  Future<CreditCardModel> createCard({
    required String name,
    required double limit,
    required int closingDay,
    required int dueDay,
    String color = '#2F756A',
    String brand = 'visa',
    String lastDigits = '',
    String financialOwnerType = 'shared',
  }) async {
    return _cards.first;
  }

  @override
  Future<CreditCardModel> updateCard(
    int id, {
    String? name,
    double? limit,
    int? closingDay,
    int? dueDay,
    String? color,
    String? brand,
    String? lastDigits,
    String? financialOwnerType,
  }) async {
    return _cards.first;
  }

  @override
  Future<void> deleteCard(int id) async {}

  @override
  Future<List<CardExpenseModel>> createExpense({
    required int cardId,
    required String description,
    required double amount,
    required DateTime date,
    required int categoryId,
    int installmentsCount = 1,
    String? financialOwnerType,
  }) async {
    return [];
  }

  @override
  Future<void> deleteExpense(int expenseId, {bool deleteAll = false}) async {}

  @override
  Future<CardInvoiceModel> payInvoice(
    int invoiceId, {
    required int accountId,
    required double paidAmount,
    required DateTime paymentDate,
  }) async {
    return _cards.first as dynamic;
  }

  @override
  Future<CardInvoiceModel> reopenInvoice(int invoiceId) async {
    return _cards.first as dynamic;
  }
}
