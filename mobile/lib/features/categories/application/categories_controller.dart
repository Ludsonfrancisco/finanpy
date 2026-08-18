import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/sync/sync_state.dart';
import '../data/categories_repository.dart';
import '../domain/categories_models.dart';
import '../../transactions/domain/transactions_models.dart';

final class CategoriesState {
  const CategoriesState({
    required this.isLoading,
    this.snapshot,
    this.filters = const CategoryFilters(),
    this.error,
  });

  const CategoriesState.initial()
    : isLoading = true,
      snapshot = null,
      filters = const CategoryFilters(),
      error = null;

  final bool isLoading;
  final CategoriesSnapshot? snapshot;
  final CategoryFilters filters;
  final Object? error;

  CategoriesState copyWith({
    bool? isLoading,
    CategoriesSnapshot? snapshot,
    CategoryFilters? filters,
    Object? error,
    bool clearError = false,
  }) {
    return CategoriesState(
      isLoading: isLoading ?? this.isLoading,
      snapshot: snapshot ?? this.snapshot,
      filters: filters ?? this.filters,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final class CategoriesController extends ChangeNotifier {
  CategoriesController({
    required CategoriesRepository repository,
    required SyncState syncState,
  }) : _repository = repository,
       _syncState = syncState {
    _syncState.addListener(_handleSyncStateChanged);
  }

  final CategoriesRepository _repository;
  final SyncState _syncState;

  CategoriesState _state = const CategoriesState.initial();
  StreamSubscription<CategoriesSnapshot>? _subscription;
  bool _started = false;
  bool _disposed = false;
  int _watchGeneration = 0;

  CategoriesState get state => _state;
  CategoriesRepository get repository => _repository;
  SyncPhase get syncPhase => _syncState.phase;
  DateTime? get syncTimestamp => _syncState.timestamp;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _watch(_state.filters);
  }

  Future<void> updateFilters(CategoryFilters filters) async {
    _state = _state.copyWith(filters: filters);
    notifyListeners();
    await _watch(filters);
  }

  Future<void> setTypeFilter(TransactionType? type) async {
    final newFilters = _state.filters.copyWith(
      type: type,
      clearType: type == null,
    );
    await updateFilters(newFilters);
  }

  Future<void> setSearchQuery(String query) async {
    final trimmed = query.trim();
    final newFilters = _state.filters.copyWith(
      searchQuery: trimmed,
      clearSearch: trimmed.isEmpty,
    );
    await updateFilters(newFilters);
  }

  Future<void> retrySync() async {
    await _syncState.retry();
  }

  Future<void> _watch(CategoryFilters filters) async {
    final generation = ++_watchGeneration;
    await _subscription?.cancel();
    _subscription = null;

    if (_disposed || generation != _watchGeneration) return;

    _state = _state.copyWith(isLoading: _state.snapshot == null);
    notifyListeners();

    _subscription = _repository
        .watchCategories(filters)
        .listen(
          (snapshot) {
            if (_disposed || generation != _watchGeneration) return;
            _state = _state.copyWith(
              isLoading: false,
              snapshot: snapshot,
              clearError: true,
            );
            notifyListeners();
          },
          onError: (Object error) {
            if (_disposed || generation != _watchGeneration) return;
            _state = _state.copyWith(isLoading: false, error: error);
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
