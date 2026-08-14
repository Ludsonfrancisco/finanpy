import '../network/api_error.dart';
import '../storage/local_ledger.dart';
import 'sync_api.dart';
import 'sync_models.dart';
import 'sync_state.dart';

typedef ActiveDeviceUuid = Future<String?> Function();

final class LedgerSyncCoordinator {
  LedgerSyncCoordinator({
    required SyncApi api,
    required LocalLedger ledger,
    required ActiveDeviceUuid activeDeviceUuid,
    DateTime Function()? now,
  }) : _api = api,
       _ledger = ledger,
       _activeDeviceUuid = activeDeviceUuid,
       _now = now ?? DateTime.now {
    state = SyncState(retry: synchronize);
  }

  static const pageSize = DjangoSyncApi.pageSize;

  final SyncApi _api;
  final LocalLedger _ledger;
  final ActiveDeviceUuid _activeDeviceUuid;
  final DateTime Function() _now;
  late final SyncState state;
  Future<SyncResult>? _inFlight;

  Future<SyncResult> synchronize() {
    final active = _inFlight;
    if (active != null) return active;

    late final Future<SyncResult> guarded;
    guarded = _synchronize().whenComplete(() {
      if (identical(_inFlight, guarded)) _inFlight = null;
    });
    _inFlight = guarded;
    return guarded;
  }

  Future<bool> hasValidCache() async {
    final metadata = await _ledger.readSyncMetadata();
    final deviceUuid = await _activeDeviceUuid();
    return metadata != null &&
        deviceUuid != null &&
        metadata.sessionDeviceUuid == deviceUuid;
  }

  Future<SyncResult?> synchronizeIfStale(Duration maximumAge) async {
    final active = _inFlight;
    if (active != null) return active;

    final metadata = await _ledger.readSyncMetadata();
    final deviceUuid = await _activeDeviceUuid();
    if (metadata == null ||
        deviceUuid == null ||
        metadata.sessionDeviceUuid != deviceUuid) {
      return synchronize();
    }
    final age = _now().toUtc().difference(metadata.lastSuccessAt.toUtc());
    if (age <= maximumAge) return null;
    return synchronize();
  }

  Future<SyncResult> _synchronize() async {
    SyncMetadata? metadata;
    var hasValidCache = false;
    try {
      metadata = await _ledger.readSyncMetadata();
      final deviceUuid = await _activeDeviceUuid();
      hasValidCache =
          metadata != null &&
          deviceUuid != null &&
          metadata.sessionDeviceUuid == deviceUuid;
      state.markSyncing(hasValidCache ? metadata.lastSuccessAt : null);
      if (deviceUuid == null) {
        state.markFailed(null);
        return SyncResult.failed;
      }

      if (!hasValidCache) {
        final bootstrap = await _api.fetchBootstrap();
        await _ensureActiveDevice(deviceUuid);
        final syncedAt = _now().toUtc();
        await _ledger.replaceBootstrap(bootstrap, syncedAt, deviceUuid);
        state.markCurrent(syncedAt);
        return SyncResult.updated;
      }

      var cursor = metadata.cursor;
      var changed = false;
      final visitedCursors = <String>{cursor};
      while (true) {
        final page = await _api.fetchChanges(cursor);
        if (page.changes.isNotEmpty && !visitedCursors.add(page.cursor)) {
          throw const FormatException(
            'A non-empty sync page must advance the cursor.',
          );
        }
        await _ensureActiveDevice(deviceUuid);
        final syncedAt = _now().toUtc();
        await _ledger.applyDelta(page, syncedAt);
        changed = changed || page.changes.isNotEmpty;
        cursor = page.cursor;
        metadata = await _ledger.readSyncMetadata();
        if (page.changes.length < pageSize) {
          state.markCurrent(syncedAt);
          return changed ? SyncResult.updated : SyncResult.current;
        }
      }
    } on OfflineFailure {
      state.markOffline(hasValidCache ? metadata?.lastSuccessAt : null);
      return hasValidCache
          ? SyncResult.offlineWithCache
          : SyncResult.noCacheOffline;
    } catch (_) {
      state.markFailed(hasValidCache ? metadata?.lastSuccessAt : null);
      return SyncResult.failed;
    }
  }

  Future<void> _ensureActiveDevice(String expectedUuid) async {
    if (await _activeDeviceUuid() != expectedUuid) {
      throw StateError('The active session changed during synchronization.');
    }
  }
}
