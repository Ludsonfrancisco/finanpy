import '../../../core/money/minor_units.dart';
import '../../../core/network/session_transport.dart';
import '../domain/cards_models.dart';

abstract interface class CardsRepository {
  Future<CardsSnapshot> fetchCards({int? month, int? year, String? owner});
  Future<CardDetailSnapshot> fetchCardDetail(
    int cardId, {
    int? month,
    int? year,
  });
  Future<CreditCardModel> createCard({
    required String name,
    required int limitMinor,
    required int closingDay,
    required int dueDay,
    String color = '#2F756A',
    String brand = 'visa',
    String lastDigits = '',
    String financialOwnerType = 'shared',
  });
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
  });
  Future<void> deleteCard(int id);
  Future<List<CardExpenseModel>> createExpense({
    required int cardId,
    required String description,
    required int amountMinor,
    required DateTime date,
    required int categoryId,
    int installmentsCount = 1,
    String? financialOwnerType,
  });
  Future<void> deleteExpense(int expenseId, {bool deleteAll = false});
  Future<CardInvoiceModel> payInvoice(
    int invoiceId, {
    required int accountId,
    required int paidAmountMinor,
    required DateTime paymentDate,
  });
  Future<CardInvoiceModel> reopenInvoice(int invoiceId);
}

final class HttpCardsRepository implements CardsRepository {
  HttpCardsRepository(this._transport);

  final SessionTransport _transport;

  @override
  Future<CardsSnapshot> fetchCards({
    int? month,
    int? year,
    String? owner,
  }) async {
    final queryParams = <String, String>{};
    if (month != null) queryParams['month'] = month.toString();
    if (year != null) queryParams['year'] = year.toString();
    if (owner != null && owner.isNotEmpty) queryParams['owner'] = owner;

    final uri = Uri(
      path: '/api/v1/cards/',
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final response = await _transport.getObject(uri.toString());

    final cardsJson = (response['cards'] as List<dynamic>?) ?? [];
    final summaryJson = (response['summary'] as Map<String, dynamic>?) ?? {};

    return CardsSnapshot(
      cards: cardsJson
          .map((c) => CreditCardModel.fromJson(c as Map<String, dynamic>))
          .toList(),
      summary: CardsSummaryModel.fromJson(summaryJson),
    );
  }

  @override
  Future<CardDetailSnapshot> fetchCardDetail(
    int cardId, {
    int? month,
    int? year,
  }) async {
    final queryParams = <String, String>{};
    if (month != null) queryParams['month'] = month.toString();
    if (year != null) queryParams['year'] = year.toString();

    final uri = Uri(
      path: '/api/v1/cards/$cardId/',
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final response = await _transport.getObject(uri.toString());

    final cardJson = (response['card'] as Map<String, dynamic>?) ?? {};
    final invoiceJson =
        (response['selected_invoice'] as Map<String, dynamic>?) ?? {};
    final futureInvoicesJson =
        (response['future_invoices'] as List<dynamic>?) ?? [];

    return CardDetailSnapshot(
      card: CreditCardModel.fromJson(cardJson),
      selectedInvoice: CardInvoiceModel.fromJson(invoiceJson),
      futureInvoices: futureInvoicesJson
          .map((i) => CardInvoiceModel.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

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
    final response = await _transport.postObject(
      '/api/v1/cards/',
      data: {
        'name': name,
        'limit': minorUnitsToApiDecimal(limitMinor),
        'closing_day': closingDay,
        'due_day': dueDay,
        'color': color,
        'brand': brand,
        'last_digits': lastDigits,
        'financial_owner_type': financialOwnerType,
      },
    );
    return CreditCardModel.fromJson(response);
  }

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
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (limitMinor != null) {
      payload['limit'] = minorUnitsToApiDecimal(limitMinor);
    }
    if (closingDay != null) payload['closing_day'] = closingDay;
    if (dueDay != null) payload['due_day'] = dueDay;
    if (color != null) payload['color'] = color;
    if (brand != null) payload['brand'] = brand;
    if (lastDigits != null) payload['last_digits'] = lastDigits;
    if (financialOwnerType != null) {
      payload['financial_owner_type'] = financialOwnerType;
    }

    final response = await _transport.patchObject(
      '/api/v1/cards/$id/',
      payload,
    );
    return CreditCardModel.fromJson(response);
  }

  @override
  Future<void> deleteCard(int id) async {
    await _transport.deleteObject('/api/v1/cards/$id/');
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
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final payload = <String, dynamic>{
      'card_id': cardId,
      'description': description,
      'amount': minorUnitsToApiDecimal(amountMinor),
      'date': dateStr,
      'category_id': categoryId,
      'installments_count': installmentsCount,
    };
    if (financialOwnerType != null) {
      payload['financial_owner_type'] = financialOwnerType;
    }

    final response = await _transport.postObject(
      '/api/v1/cards/expenses/',
      data: payload,
    );
    final expensesJson = (response['expenses'] as List<dynamic>?) ?? [];
    return expensesJson
        .map((e) => CardExpenseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> deleteExpense(int expenseId, {bool deleteAll = false}) async {
    final path = deleteAll
        ? '/api/v1/cards/expenses/$expenseId/?delete_all=true'
        : '/api/v1/cards/expenses/$expenseId/';
    await _transport.deleteObject(path);
  }

  @override
  Future<CardInvoiceModel> payInvoice(
    int invoiceId, {
    required int accountId,
    required int paidAmountMinor,
    required DateTime paymentDate,
  }) async {
    final dateStr =
        '${paymentDate.year.toString().padLeft(4, '0')}-${paymentDate.month.toString().padLeft(2, '0')}-${paymentDate.day.toString().padLeft(2, '0')}';
    final response = await _transport.postObject(
      '/api/v1/cards/invoices/$invoiceId/pay/',
      data: {
        'account_id': accountId,
        'paid_amount': minorUnitsToApiDecimal(paidAmountMinor),
        'payment_date': dateStr,
      },
    );
    return CardInvoiceModel.fromJson(response);
  }

  @override
  Future<CardInvoiceModel> reopenInvoice(int invoiceId) async {
    final response = await _transport.postObject(
      '/api/v1/cards/invoices/$invoiceId/reopen/',
      data: {},
    );
    return CardInvoiceModel.fromJson(response);
  }
}
