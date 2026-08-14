import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/sync/sync_state.dart';
import '../data/home_repository.dart';
import '../domain/home_snapshot.dart';

final class HomeViewState {
  const HomeViewState({
    required this.selectedKind,
    required this.isLoading,
    this.snapshot,
    this.error,
  });

  final OwnerScopeKind selectedKind;
  final bool isLoading;
  final HomeSnapshot? snapshot;
  final Object? error;

  HomeViewState copyWith({
    OwnerScopeKind? selectedKind,
    bool? isLoading,
    HomeSnapshot? snapshot,
    Object? error,
    bool clearSnapshot = false,
    bool clearError = false,
  }) => HomeViewState(
    selectedKind: selectedKind ?? this.selectedKind,
    isLoading: isLoading ?? this.isLoading,
    snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
    error: clearError ? null : error ?? this.error,
  );
}

final class HomeController extends ChangeNotifier {
  HomeController({
    required HomeRepository repository,
    required SyncState syncState,
    DateTime Function()? now,
  }) : _repository = repository,
       _syncState = syncState,
       _now = now ?? DateTime.now {
    _syncState.addListener(_handleSyncStateChanged);
  }

  final HomeRepository _repository;
  final SyncState _syncState;
  final DateTime Function() _now;
  HomeViewState _state = const HomeViewState(
    selectedKind: OwnerScopeKind.household,
    isLoading: true,
  );
  HomeOwnerScopes? _ownerScopes;
  StreamSubscription<HomeSnapshot>? _subscription;
  bool _started = false;
  bool _disposed = false;
  int _watchGeneration = 0;

  HomeViewState get state => _state;
  SyncPhase get syncPhase => _syncState.phase;
  DateTime? get syncTimestamp => _syncState.timestamp;
  DateTime get now => _now();

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _ownerScopes = await _repository.readOwnerScopes();
      if (_disposed) return;
      await _watch(const OwnerScope.household());
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
    if (scope.kind == _state.selectedKind) return;
    await _watch(scope);
  }

  Future<void> retrySync() async {
    await _syncState.retry();
  }

  Future<void> _watch(OwnerScope scope) async {
    final generation = ++_watchGeneration;
    final previous = _subscription;
    _subscription = null;
    unawaited(previous?.cancel());
    if (_disposed) return;
    _state = HomeViewState(selectedKind: scope.kind, isLoading: true);
    notifyListeners();
    _subscription = _repository
        .watchSnapshot(scope, _now())
        .listen(
          (snapshot) {
            if (_disposed || generation != _watchGeneration) return;
            _state = HomeViewState(
              selectedKind: scope.kind,
              isLoading: false,
              snapshot: snapshot,
            );
            notifyListeners();
          },
          onError: (Object error) {
            if (_disposed || generation != _watchGeneration) return;
            _state = _state.copyWith(
              isLoading: false,
              error: error,
              clearError: false,
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
