import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/sync/sync_state.dart';
import '../../home/domain/home_snapshot.dart';
import '../data/transactions_repository.dart';
import '../domain/transactions_models.dart';

final class TransactionsController extends ChangeNotifier {
  TransactionsController({
    required TransactionsRepository repository,
    required SyncState syncState,
  }) : _repository = repository,
       _syncState = syncState {
    _syncState.addListener(_handleSyncStateChanged);
  }

  final TransactionsRepository _repository;
  final SyncState _syncState;

  TransactionsState _state = const TransactionsState.initial();
  HomeOwnerScopes? _ownerScopes;
  StreamSubscription<TransactionsSnapshot>? _subscription;
  OwnerScope? _activeScope;
  bool _started = false;
  bool _disposed = false;
  int _watchGeneration = 0;

  TransactionsState get state => _state;
  TransactionsRepository get repository => _repository;
  SyncPhase get syncPhase => _syncState.phase;
  DateTime? get syncTimestamp => _syncState.timestamp;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _ownerScopes = await _repository.readOwnerScopes();
      if (_disposed) return;
      _state = _state.copyWith(ownerScopes: _ownerScopes);
      await _watch(const OwnerScope.household(), 0, _state.filters);
    } catch (error) {
      if (_disposed) return;
      _state = _state.copyWith(isLoading: false, error: error);
      notifyListeners();
    }
  }

  Future<void> select(int index) async {
    final scopes = _ownerScopes;
    if (scopes == null) return;
    final scope = switch (index) {
      0 => const OwnerScope.household(),
      1 => scopes.selfScope,
      2 => scopes.spouseScope,
      _ => throw RangeError.index(index, const <int>[0, 1, 2]),
    };
    if (index == _state.selectedScopeIndex && _state.snapshot != null) return;
    await _watch(scope, index, _state.filters);
  }

  Future<void> updateSearch(String query) async {
    if (query == _state.filters.searchQuery) return;
    final newFilters = _state.filters.copyWith(searchQuery: query);
    final scope = _activeScope ?? const OwnerScope.household();
    await _watch(scope, _state.selectedScopeIndex, newFilters);
  }

  Future<void> updateFilters(TransactionFilters filters) async {
    final scope = _activeScope ?? const OwnerScope.household();
    await _watch(scope, _state.selectedScopeIndex, filters);
  }

  Future<void> clearFilters() async {
    final newFilters = const TransactionFilters();
    final scope = _activeScope ?? const OwnerScope.household();
    await _watch(scope, _state.selectedScopeIndex, newFilters);
  }

  Future<void> retrySync() async {
    await _syncState.retry();
  }

  Future<void> _watch(
    OwnerScope scope,
    int scopeIndex,
    TransactionFilters filters,
  ) async {
    _activeScope = scope;
    final generation = ++_watchGeneration;
    final previous = _subscription;
    _subscription = null;
    unawaited(previous?.cancel());
    if (_disposed) return;

    _state = _state.copyWith(
      selectedScopeIndex: scopeIndex,
      filters: filters,
      isLoading: true,
      error: null,
    );
    notifyListeners();

    _subscription = _repository
        .watchTransactions(scope, filters)
        .listen(
          (snapshot) {
            if (_disposed || generation != _watchGeneration) return;
            _state = _state.copyWith(
              selectedScopeIndex: scopeIndex,
              filters: filters,
              isLoading: false,
              snapshot: snapshot,
              error: null,
            );
            notifyListeners();
          },
          onError: (Object error) {
            if (_disposed || generation != _watchGeneration) return;
            _state = _state.copyWith(
              selectedScopeIndex: scopeIndex,
              filters: filters,
              isLoading: false,
              error: error,
            );
            notifyListeners();
          },
        );
  }

  void _handleSyncStateChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncState.removeListener(_handleSyncStateChanged);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
