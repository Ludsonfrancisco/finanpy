import 'package:flutter/foundation.dart';
import '../data/cards_repository.dart';
import '../domain/cards_models.dart';

@immutable
final class CardsState {
  const CardsState({
    this.isLoading = false,
    this.cards = const [],
    this.summary = CardsSummaryModel.empty,
    this.selectedCard,
    this.selectedInvoice,
    this.futureInvoices = const [],
    this.selectedMonth = 1,
    this.selectedYear = 2026,
    this.selectedOwner = 'household',
    this.activeTab = 0,
    this.errorMessage,
  });

  final bool isLoading;
  final List<CreditCardModel> cards;
  final CardsSummaryModel summary;
  final CreditCardModel? selectedCard;
  final CardInvoiceModel? selectedInvoice;
  final List<CardInvoiceModel> futureInvoices;
  final int selectedMonth;
  final int selectedYear;
  final String selectedOwner;
  final int activeTab;
  final String? errorMessage;

  CardsState copyWith({
    bool? isLoading,
    List<CreditCardModel>? cards,
    CardsSummaryModel? summary,
    CreditCardModel? Function()? selectedCard,
    CardInvoiceModel? Function()? selectedInvoice,
    List<CardInvoiceModel>? futureInvoices,
    int? selectedMonth,
    int? selectedYear,
    String? selectedOwner,
    int? activeTab,
    String? Function()? errorMessage,
  }) {
    return CardsState(
      isLoading: isLoading ?? this.isLoading,
      cards: cards ?? this.cards,
      summary: summary ?? this.summary,
      selectedCard: selectedCard != null ? selectedCard() : this.selectedCard,
      selectedInvoice: selectedInvoice != null ? selectedInvoice() : this.selectedInvoice,
      futureInvoices: futureInvoices ?? this.futureInvoices,
      selectedMonth: selectedMonth ?? this.selectedMonth,
      selectedYear: selectedYear ?? this.selectedYear,
      selectedOwner: selectedOwner ?? this.selectedOwner,
      activeTab: activeTab ?? this.activeTab,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

final class CardsController extends ChangeNotifier {
  CardsController({required CardsRepository repository}) : _repository = repository {
    final now = DateTime.now();
    _state = CardsState(selectedMonth: now.month, selectedYear: now.year);
  }

  final CardsRepository _repository;
  late CardsState _state;

  CardsState get state => _state;

  Future<void> start() async {
    await loadCards();
  }

  Future<void> loadCards() async {
    _state = _state.copyWith(isLoading: true, errorMessage: () => null);
    notifyListeners();

    try {
      final snapshot = await _repository.fetchCards(
        month: _state.selectedMonth,
        year: _state.selectedYear,
        owner: _state.selectedOwner == 'household' ? null : _state.selectedOwner,
      );

      CreditCardModel? selected = _state.selectedCard;
      if (selected == null && snapshot.cards.isNotEmpty) {
        selected = snapshot.cards.first;
      } else if (selected != null) {
        selected = snapshot.cards.where((c) => c.id == selected!.id).firstOrNull ?? snapshot.cards.firstOrNull;
      }

      _state = _state.copyWith(
        isLoading: false,
        cards: snapshot.cards,
        summary: snapshot.summary,
        selectedCard: () => selected,
      );
      notifyListeners();

      if (selected != null) {
        await loadCardDetail(selected.id);
      }
    } catch (e) {
      _state = _state.copyWith(isLoading: false, errorMessage: () => e.toString());
      notifyListeners();
    }
  }

  Future<void> selectCard(CreditCardModel card) async {
    _state = _state.copyWith(selectedCard: () => card);
    notifyListeners();
    await loadCardDetail(card.id);
  }

  Future<void> selectMonthYear(int month, int year) async {
    _state = _state.copyWith(selectedMonth: month, selectedYear: year);
    notifyListeners();
    await loadCards();
  }

  Future<void> selectOwner(String owner) async {
    _state = _state.copyWith(selectedOwner: owner);
    notifyListeners();
    await loadCards();
  }

  void setActiveTab(int tab) {
    _state = _state.copyWith(activeTab: tab);
    notifyListeners();
  }

  Future<void> loadCardDetail(int cardId) async {
    try {
      final detail = await _repository.fetchCardDetail(
        cardId,
        month: _state.selectedMonth,
        year: _state.selectedYear,
      );

      _state = _state.copyWith(
        selectedCard: () => detail.card,
        selectedInvoice: () => detail.selectedInvoice,
        futureInvoices: detail.futureInvoices,
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> createCard({
    required String name,
    required double limit,
    required int closingDay,
    required int dueDay,
    String color = '#2F756A',
    String brand = 'visa',
    String lastDigits = '',
    String financialOwnerType = 'shared',
  }) async {
    _state = _state.copyWith(isLoading: true, errorMessage: () => null);
    notifyListeners();

    try {
      final newCard = await _repository.createCard(
        name: name,
        limit: limit,
        closingDay: closingDay,
        dueDay: dueDay,
        color: color,
        brand: brand,
        lastDigits: lastDigits,
        financialOwnerType: financialOwnerType,
      );
      _state = _state.copyWith(selectedCard: () => newCard);
      await loadCards();
    } catch (e) {
      _state = _state.copyWith(isLoading: false, errorMessage: () => e.toString());
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateCard(
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
    try {
      await _repository.updateCard(
        id,
        name: name,
        limit: limit,
        closingDay: closingDay,
        dueDay: dueDay,
        color: color,
        brand: brand,
        lastDigits: lastDigits,
        financialOwnerType: financialOwnerType,
      );
      await loadCards();
    } catch (e) {
      _state = _state.copyWith(errorMessage: () => e.toString());
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteCard(int id) async {
    try {
      await _repository.deleteCard(id);
      _state = _state.copyWith(selectedCard: () => null);
      await loadCards();
    } catch (e) {
      _state = _state.copyWith(errorMessage: () => e.toString());
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createExpense({
    required int cardId,
    required String description,
    required double amount,
    required DateTime date,
    required int categoryId,
    int installmentsCount = 1,
    String? financialOwnerType,
  }) async {
    try {
      await _repository.createExpense(
        cardId: cardId,
        description: description,
        amount: amount,
        date: date,
        categoryId: categoryId,
        installmentsCount: installmentsCount,
        financialOwnerType: financialOwnerType,
      );
      await loadCards();
    } catch (e) {
      _state = _state.copyWith(errorMessage: () => e.toString());
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteExpense(int expenseId, {bool deleteAll = false}) async {
    try {
      await _repository.deleteExpense(expenseId, deleteAll: deleteAll);
      if (_state.selectedCard != null) {
        await loadCardDetail(_state.selectedCard!.id);
      }
      await loadCards();
    } catch (e) {
      _state = _state.copyWith(errorMessage: () => e.toString());
      notifyListeners();
      rethrow;
    }
  }

  Future<void> payInvoice({
    required int invoiceId,
    required int accountId,
    required double paidAmount,
    required DateTime paymentDate,
  }) async {
    try {
      await _repository.payInvoice(
        invoiceId,
        accountId: accountId,
        paidAmount: paidAmount,
        paymentDate: paymentDate,
      );
      await loadCards();
    } catch (e) {
      _state = _state.copyWith(errorMessage: () => e.toString());
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reopenInvoice(int invoiceId) async {
    try {
      await _repository.reopenInvoice(invoiceId);
      await loadCards();
    } catch (e) {
      _state = _state.copyWith(errorMessage: () => e.toString());
      notifyListeners();
      rethrow;
    }
  }
}
