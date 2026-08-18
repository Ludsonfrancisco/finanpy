import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/sync/sync_state.dart';
import '../../home/domain/home_snapshot.dart';
import '../data/reports_repository.dart';
import '../domain/reports_models.dart';

final class ReportsState {
  const ReportsState({
    required this.isLoading,
    this.ownerScopes,
    this.selectedScopeIndex = 0,
    this.selectedPeriod = ReportPeriod.currentMonth,
    this.summary,
    this.error,
  });

  const ReportsState.initial()
    : isLoading = true,
      ownerScopes = null,
      selectedScopeIndex = 0,
      selectedPeriod = ReportPeriod.currentMonth,
      summary = null,
      error = null;

  final bool isLoading;
  final HomeOwnerScopes? ownerScopes;
  final int selectedScopeIndex;
  final ReportPeriod selectedPeriod;
  final ReportsSummary? summary;
  final Object? error;

  ReportsState copyWith({
    bool? isLoading,
    HomeOwnerScopes? ownerScopes,
    int? selectedScopeIndex,
    ReportPeriod? selectedPeriod,
    ReportsSummary? summary,
    Object? error,
    bool clearError = false,
  }) {
    return ReportsState(
      isLoading: isLoading ?? this.isLoading,
      ownerScopes: ownerScopes ?? this.ownerScopes,
      selectedScopeIndex: selectedScopeIndex ?? this.selectedScopeIndex,
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
      summary: summary ?? this.summary,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final class ReportsController extends ChangeNotifier {
  ReportsController({
    required ReportsRepository repository,
    required SyncState syncState,
  }) : _repository = repository,
       _syncState = syncState {
    _syncState.addListener(_handleSyncStateChanged);
  }

  final ReportsRepository _repository;
  final SyncState _syncState;

  ReportsState _state = const ReportsState.initial();
  HomeOwnerScopes? _ownerScopes;
  StreamSubscription<ReportsSummary>? _subscription;
  bool _started = false;
  bool _disposed = false;
  int _watchGeneration = 0;

  ReportsState get state => _state;
  ReportsRepository get repository => _repository;
  SyncPhase get syncPhase => _syncState.phase;
  DateTime? get syncTimestamp => _syncState.timestamp;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _ownerScopes = await _repository.readOwnerScopes();
      if (_disposed) return;
      _state = _state.copyWith(ownerScopes: _ownerScopes);
      await _watch(const OwnerScope.household(), 0, _state.selectedPeriod);
    } catch (error) {
      if (_disposed) return;
      _state = _state.copyWith(isLoading: false, error: error);
      notifyListeners();
    }
  }

  Future<void> selectScope(int index) async {
    final scopes = _ownerScopes;
    if (scopes == null) return;
    final scope = switch (index) {
      0 => const OwnerScope.household(),
      1 => scopes.selfScope,
      2 => scopes.spouseScope,
      _ => throw RangeError.index(index, const <int>[0, 1, 2]),
    };
    if (index == _state.selectedScopeIndex && _state.summary != null) return;
    await _watch(scope, index, _state.selectedPeriod);
  }

  Future<void> selectPeriod(ReportPeriod period) async {
    if (period == _state.selectedPeriod && _state.summary != null) return;
    final scope = _currentScope();
    await _watch(scope, _state.selectedScopeIndex, period);
  }

  Future<void> retrySync() async {
    await _syncState.retry();
  }

  OwnerScope _currentScope() {
    final scopes = _ownerScopes;
    if (scopes == null) return const OwnerScope.household();
    return switch (_state.selectedScopeIndex) {
      1 => scopes.selfScope,
      2 => scopes.spouseScope,
      _ => const OwnerScope.household(),
    };
  }

  Future<void> _watch(
    OwnerScope scope,
    int scopeIndex,
    ReportPeriod period,
  ) async {
    final generation = ++_watchGeneration;
    await _subscription?.cancel();
    _subscription = null;

    if (_disposed || generation != _watchGeneration) return;

    _state = _state.copyWith(
      isLoading: _state.summary == null,
      selectedScopeIndex: scopeIndex,
      selectedPeriod: period,
    );
    notifyListeners();

    _subscription = _repository
        .watchReports(scope, period)
        .listen(
          (summary) {
            if (_disposed || generation != _watchGeneration) return;
            _state = _state.copyWith(
              isLoading: false,
              summary: summary,
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
