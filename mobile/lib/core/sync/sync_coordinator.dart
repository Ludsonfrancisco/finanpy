import '../network/api_error.dart';
import '../storage/local_ledger.dart';
import '../../features/auth/domain/session.dart';
import 'sync_api.dart';
import 'sync_models.dart';
import 'sync_state.dart';

final class LedgerSyncCoordinator {
  LedgerSyncCoordinator({
    required SyncApi api,
    required LocalLedger ledger,
    required SessionAuthority sessionAuthority,
    DateTime Function()? now,
  }) : _api = api,
       _ledger = ledger,
       _sessionAuthority = sessionAuthority,
       _now = now ?? DateTime.now {
    state = SyncState(retry: synchronize);
  }

  static const pageSize = DjangoSyncApi.pageSize;

  final SyncApi _api;
  final LocalLedger _ledger;
  final SessionAuthority _sessionAuthority;
  final DateTime Function() _now;
  late final SyncState state;
  Future<SyncResult>? _inFlight;
  SessionSnapshot? _lastSuccessfulSession;

  SessionSnapshot? get lastSuccessfulSession => _lastSuccessfulSession;

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
    final session = await _sessionAuthority.snapshot();
    if (session == null) return false;
    return hasValidCacheFor(session);
  }

  Future<bool> hasValidCacheFor(SessionSnapshot expected) async {
    if (!await _sessionAuthority.isCurrent(expected)) return false;
    final metadata = await _ledger.readSyncMetadata();
    return metadata != null &&
        metadata.sessionDeviceUuid == expected.tokens.deviceUuid &&
        metadata.sessionGeneration == expected.generation;
  }

  Future<SyncResult?> synchronizeIfStale(Duration maximumAge) async {
    final active = _inFlight;
    if (active != null) return active;

    final expected = await _sessionAuthority.snapshot();
    final metadata = await _ledger.readSyncMetadata();
    if (metadata == null ||
        expected == null ||
        metadata.sessionDeviceUuid != expected.tokens.deviceUuid ||
        metadata.sessionGeneration != expected.generation) {
      return synchronize();
    }
    final age = _now().toUtc().difference(metadata.lastSuccessAt.toUtc());
    if (age <= maximumAge) return null;
    return synchronize();
  }

  Future<SyncResult> _synchronize() async {
    SyncMetadata? metadata;
    SessionSnapshot? expectedSession;
    var hasValidCache = false;
    _lastSuccessfulSession = null;
    try {
      metadata = await _ledger.readSyncMetadata();
      expectedSession = await _sessionAuthority.snapshot();
      final deviceUuid = expectedSession?.tokens.deviceUuid;
      hasValidCache =
          metadata != null &&
          deviceUuid != null &&
          metadata.sessionDeviceUuid == deviceUuid &&
          metadata.sessionGeneration == expectedSession?.generation;
      state.markSyncing(hasValidCache ? metadata.lastSuccessAt : null);
      if (deviceUuid == null) {
        state.markFailed(null);
        return SyncResult.failed;
      }

      if (!hasValidCache) {
        final bootstrap = await _api.fetchBootstrap();
        await _ensureCurrentSession(expectedSession!);
        final syncedAt = _now().toUtc();
        await _ledger.replaceBootstrap(
          bootstrap,
          syncedAt,
          deviceUuid,
          sessionGeneration: expectedSession.generation,
          isSessionCurrent: () =>
              _sessionAuthority.isGenerationCurrent(expectedSession!),
        );
        await _ensureCurrentSession(expectedSession);
        _lastSuccessfulSession = expectedSession;
        state.markCurrent(syncedAt);
        return SyncResult.updated;
      }

      var cursor = metadata.cursor;
      final pages = <SyncPage>[];
      final visitedCursors = <String>{cursor};
      while (true) {
        final page = await _api.fetchChanges(cursor);
        final returnsHistoricalCursor =
            page.cursor != cursor && visitedCursors.contains(page.cursor);
        final doesNotAdvanceChanges =
            page.changes.isNotEmpty && page.cursor == cursor;
        if (returnsHistoricalCursor || doesNotAdvanceChanges) {
          throw const FormatException(
            'A sync page cannot regress or repeat changes at its cursor.',
          );
        }
        visitedCursors.add(page.cursor);
        pages.add(page);
        cursor = page.cursor;
        if (page.changes.length < pageSize) {
          break;
        }
      }

      final changed = pages.any((page) => page.changes.isNotEmpty);
      await _ensureCurrentSession(expectedSession!);
      final syncedAt = _now().toUtc();
      await _ledger.applyDeltaChain(
        pages,
        syncedAt,
        sessionGeneration: expectedSession.generation,
        isSessionCurrent: () =>
            _sessionAuthority.isGenerationCurrent(expectedSession!),
      );
      await _ensureCurrentSession(expectedSession);
      _lastSuccessfulSession = expectedSession;
      state.markCurrent(syncedAt);
      return changed ? SyncResult.updated : SyncResult.current;
    } on OfflineFailure {
      final sessionStillCurrent =
          expectedSession != null &&
          await _sessionAuthority.isCurrent(expectedSession);
      if (hasValidCache && sessionStillCurrent) {
        _lastSuccessfulSession = expectedSession;
      }
      state.markOffline(
        hasValidCache && sessionStillCurrent ? metadata?.lastSuccessAt : null,
      );
      return hasValidCache && sessionStillCurrent
          ? SyncResult.offlineWithCache
          : expectedSession == null
          ? SyncResult.failed
          : SyncResult.noCacheOffline;
    } catch (_) {
      state.markFailed(hasValidCache ? metadata?.lastSuccessAt : null);
      return SyncResult.failed;
    }
  }

  Future<void> _ensureCurrentSession(SessionSnapshot expected) async {
    if (!await _sessionAuthority.isCurrent(expected)) {
      throw StateError('The active session changed during synchronization.');
    }
  }
}
