import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/bills_repository.dart';
import '../domain/bills_models.dart';

@immutable
final class BillsState {
  const BillsState({
    required this.isLoading,
    this.error,
    required this.instances,
    required this.recurringBills,
    required this.metrics,
    required this.selectedMonth,
    required this.selectedYear,
    required this.ownerFilter,
    required this.activeTab,
  });

  factory BillsState.initial() {
    final now = DateTime.now();
    return BillsState(
      isLoading: true,
      error: null,
      instances: const [],
      recurringBills: const [],
      metrics: BillsMetricsModel.empty,
      selectedMonth: now.month,
      selectedYear: now.year,
      ownerFilter: 'household',
      activeTab: 0,
    );
  }

  final bool isLoading;
  final Object? error;
  final List<BillInstanceModel> instances;
  final List<RecurringBillModel> recurringBills;
  final BillsMetricsModel metrics;
  final int selectedMonth;
  final int selectedYear;
  final String ownerFilter;
  final int activeTab;

  BillsState copyWith({
    bool? isLoading,
    Object? error = _sentinel,
    List<BillInstanceModel>? instances,
    List<RecurringBillModel>? recurringBills,
    BillsMetricsModel? metrics,
    int? selectedMonth,
    int? selectedYear,
    String? ownerFilter,
    int? activeTab,
  }) {
    return BillsState(
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _sentinel) ? this.error : error,
      instances: instances ?? this.instances,
      recurringBills: recurringBills ?? this.recurringBills,
      metrics: metrics ?? this.metrics,
      selectedMonth: selectedMonth ?? this.selectedMonth,
      selectedYear: selectedYear ?? this.selectedYear,
      ownerFilter: ownerFilter ?? this.ownerFilter,
      activeTab: activeTab ?? this.activeTab,
    );
  }
}

const Object _sentinel = Object();

final class BillsController extends ChangeNotifier {
  BillsController({required BillsRepository repository})
    : _repository = repository;

  final BillsRepository _repository;
  BillsState _state = BillsState.initial();
  bool _started = false;

  BillsState get state => _state;
  BillsRepository get repository => _repository;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await loadData();
  }

  Future<void> loadData() async {
    _state = _state.copyWith(isLoading: true, error: null);
    notifyListeners();

    try {
      final snapshot = await _repository.fetchBillsData(
        month: _state.selectedMonth,
        year: _state.selectedYear,
        owner: _state.ownerFilter,
      );

      _state = _state.copyWith(
        isLoading: false,
        instances: snapshot.instances,
        recurringBills: snapshot.recurringBills,
        metrics: snapshot.metrics,
      );
    } catch (err) {
      _state = _state.copyWith(isLoading: false, error: err);
    }
    notifyListeners();
  }

  Future<void> setMonth(int month, int year) async {
    if (_state.selectedMonth == month && _state.selectedYear == year) return;
    _state = _state.copyWith(selectedMonth: month, selectedYear: year);
    await loadData();
  }

  Future<void> setOwnerFilter(String owner) async {
    if (_state.ownerFilter == owner) return;
    _state = _state.copyWith(ownerFilter: owner);
    await loadData();
  }

  void setActiveTab(int tab) {
    if (_state.activeTab == tab) return;
    _state = _state.copyWith(activeTab: tab);
    notifyListeners();
  }

  Future<void> payBill({
    required int instanceId,
    required int accountId,
    required int paidAmountMinor,
    required DateTime paidDate,
  }) async {
    try {
      await _repository.payBillInstance(
        instanceId,
        accountId: accountId,
        paidAmountMinor: paidAmountMinor,
        paidDate: paidDate,
      );
      await loadData();
    } catch (err) {
      _state = _state.copyWith(error: err);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reopenBill(int instanceId) async {
    try {
      await _repository.reopenBillInstance(instanceId);
      await loadData();
    } catch (err) {
      _state = _state.copyWith(error: err);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createRecurringBill({
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
    try {
      await _repository.createRecurringBill(
        name: name,
        amountMinor: amountMinor,
        dueDay: dueDay,
        type: type,
        categoryId: categoryId,
        defaultAccountId: defaultAccountId,
        financialOwnerType: financialOwnerType,
        isActive: isActive,
        notes: notes,
      );
      await loadData();
    } catch (err) {
      _state = _state.copyWith(error: err);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateRecurringBill(
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
    try {
      await _repository.updateRecurringBill(
        id,
        name: name,
        amountMinor: amountMinor,
        dueDay: dueDay,
        type: type,
        categoryId: categoryId,
        defaultAccountId: defaultAccountId,
        financialOwnerType: financialOwnerType,
        isActive: isActive,
        notes: notes,
      );
      await loadData();
    } catch (err) {
      _state = _state.copyWith(error: err);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteRecurringBill(int id) async {
    try {
      await _repository.deleteRecurringBill(id);
      await loadData();
    } catch (err) {
      _state = _state.copyWith(error: err);
      notifyListeners();
      rethrow;
    }
  }
}
