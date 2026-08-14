import 'package:flutter/foundation.dart';

import 'sync_models.dart';

enum SyncPhase { idle, syncing, current, offline, failed }

typedef SyncRetry = Future<SyncResult> Function();

final class SyncState extends ChangeNotifier {
  SyncState({required SyncRetry retry}) : _retry = retry;

  final SyncRetry _retry;
  SyncPhase _phase = SyncPhase.idle;
  DateTime? _timestamp;

  SyncPhase get phase => _phase;
  DateTime? get timestamp => _timestamp;

  Future<SyncResult> retry() => _retry();

  void markSyncing(DateTime? timestamp) => _set(SyncPhase.syncing, timestamp);

  void markCurrent(DateTime timestamp) => _set(SyncPhase.current, timestamp);

  void markOffline(DateTime? timestamp) => _set(SyncPhase.offline, timestamp);

  void markFailed(DateTime? timestamp) => _set(SyncPhase.failed, timestamp);

  void _set(SyncPhase phase, DateTime? timestamp) {
    _phase = phase;
    _timestamp = timestamp;
    notifyListeners();
  }
}
