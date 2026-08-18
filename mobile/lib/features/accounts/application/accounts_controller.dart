import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/sync/sync_state.dart';
import '../../home/domain/home_snapshot.dart';
import '../data/accounts_repository.dart';
import '../domain/accounts_models.dart';

final class AccountsController extends ChangeNotifier {
  AccountsController({
    required AccountsRepository repository,
    required SyncState syncState,
  }) : _repository = repository,
       _syncState = syncState {
    _syncState.addListener(_handleSyncStateChanged);
  }

  final AccountsRepository _repository;
  final SyncState _syncState;

  AccountsState _state = const AccountsState.initial();
  HomeOwnerScopes? _ownerScopes;
  StreamSubscription<AccountsSnapshot>? _subscription;
  bool _started = false;
  bool _disposed = false;
  int _watchGeneration = 0;

  AccountsState get state => _state;
  AccountsRepository get repository => _repository;
  SyncPhase get syncPhase => _syncState.phase;
  DateTime? get syncTimestamp => _syncState.timestamp;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _ownerScopes = await _repository.readOwnerScopes();
      if (_disposed) return;
      _state = _state.copyWith(ownerScopes: _ownerScopes);
      await _watch(const OwnerScope.household(), 0);
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
    await _watch(scope, index);
  }

  Future<void> retrySync() async {
    await _syncState.retry();
  }

  Future<void> _watch(OwnerScope scope, int index) async {
    final generation = ++_watchGeneration;
    final previous = _subscription;
    _subscription = null;
    unawaited(previous?.cancel());
    if (_disposed) return;

    _state = _state.copyWith(
      selectedScopeIndex: index,
      isLoading: true,
      error: null,
    );
    notifyListeners();

    _subscription = _repository
        .watchAccounts(scope)
        .listen(
          (snapshot) {
            if (_disposed || generation != _watchGeneration) return;
            _state = _state.copyWith(
              selectedScopeIndex: index,
              isLoading: false,
              snapshot: snapshot,
              error: null,
            );
            notifyListeners();
          },
          onError: (Object error) {
            if (_disposed || generation != _watchGeneration) return;
            _state = _state.copyWith(
              selectedScopeIndex: index,
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
