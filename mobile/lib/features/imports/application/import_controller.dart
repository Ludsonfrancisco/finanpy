import 'package:flutter/foundation.dart';

import '../data/import_repository.dart';
import '../data/ofx_file_picker.dart';
import '../domain/import_preview.dart';

typedef LedgerSynchronizer = Future<void> Function();

enum ImportPhase {
  idle,
  picking,
  uploading,
  preview,
  confirming,
  completed,
  failure,
}

final class ImportViewState {
  const ImportViewState({
    this.phase = ImportPhase.idle,
    this.preview,
    this.failure,
    this.hasPendingSync = false,
  });

  final ImportPhase phase;
  final ImportPreview? preview;
  final ImportFailureKind? failure;

  /// The ledger was written but the following pull did not land.
  final bool hasPendingSync;

  List<ImportRecordPreview> get records =>
      preview?.records ?? const <ImportRecordPreview>[];

  bool get isBusy =>
      phase == ImportPhase.picking ||
      phase == ImportPhase.uploading ||
      phase == ImportPhase.confirming;

  ImportViewState copyWith({
    ImportPhase? phase,
    ImportPreview? preview,
    ImportFailureKind? failure,
    bool? hasPendingSync,
    bool clearFailure = false,
  }) => ImportViewState(
    phase: phase ?? this.phase,
    preview: preview ?? this.preview,
    failure: clearFailure ? null : failure ?? this.failure,
    hasPendingSync: hasPendingSync ?? this.hasPendingSync,
  );
}

/// Serializes one import at a time. Every asynchronous result is bound to the
/// epoch that started it, so a stale answer can never move the interface.
final class ImportController extends ChangeNotifier {
  ImportController({
    required OfxFilePicker picker,
    required ImportRepository repository,
    required LedgerSynchronizer synchronize,
  }) : _picker = picker,
       _repository = repository,
       _synchronize = synchronize;

  final OfxFilePicker _picker;
  final ImportRepository _repository;
  final LedgerSynchronizer _synchronize;

  ImportViewState _state = const ImportViewState();
  SelectedOfx? _selection;
  Future<void>? _confirmInFlight;
  int _epoch = 0;
  bool _disposed = false;

  ImportViewState get state => _state;

  /// The bytes must exist only between the picker and the upload.
  @visibleForTesting
  bool get debugRetainsBytes => _selection != null;

  Future<void> selectFile() async {
    final epoch = ++_epoch;
    _emit(const ImportViewState(phase: ImportPhase.picking), epoch);

    final SelectedOfx? selection;
    try {
      selection = await _picker.pick();
    } catch (error) {
      _fail(error, epoch);
      return;
    }
    if (!_isCurrent(epoch)) return;
    if (selection == null) {
      _emit(const ImportViewState(), epoch);
      return;
    }

    _selection = selection;
    _emit(const ImportViewState(phase: ImportPhase.uploading), epoch);
    final ImportPreview preview;
    try {
      preview = await _repository.createPreview(selection);
    } catch (error) {
      _fail(error, epoch);
      return;
    } finally {
      _selection = null;
    }
    if (!_isCurrent(epoch)) return;

    _emit(ImportViewState(phase: ImportPhase.preview, preview: preview), epoch);
    await _drainPages(epoch);
  }

  /// Loads the next page only, for a screen that resumes after a page error.
  Future<void> loadMore() async {
    final preview = _state.preview;
    if (preview == null || !preview.hasMorePages || _state.isBusy) return;
    final epoch = ++_epoch;
    _emit(
      _state.copyWith(phase: ImportPhase.preview, clearFailure: true),
      epoch,
    );
    await _loadNextPage(epoch);
  }

  Future<void> retry() async {
    if (_state.preview == null) {
      reset();
      return;
    }
    final epoch = ++_epoch;
    _emit(
      _state.copyWith(phase: ImportPhase.preview, clearFailure: true),
      epoch,
    );
    await _drainPages(epoch);
  }

  Future<void> confirm() {
    final active = _confirmInFlight;
    if (active != null) return active;
    final preview = _state.preview;
    if (preview == null || _state.phase != ImportPhase.preview) {
      return Future<void>.value();
    }
    late final Future<void> guarded;
    guarded = _confirm(preview).whenComplete(() {
      if (identical(_confirmInFlight, guarded)) _confirmInFlight = null;
    });
    _confirmInFlight = guarded;
    return guarded;
  }

  Future<void> cancel() async {
    final preview = _state.preview;
    final epoch = ++_epoch;
    _selection = null;
    ImportFailureKind? remoteFailure;
    if (preview != null) {
      try {
        await _repository.cancelPreview(preview.uuid);
      } catch (error) {
        // The local copy is dropped either way; the server preview expires.
        remoteFailure = _kindOf(error);
      }
    }
    if (!_isCurrent(epoch)) return;
    _emit(ImportViewState(failure: remoteFailure), epoch);
  }

  void reset() {
    final epoch = ++_epoch;
    _selection = null;
    _emit(const ImportViewState(), epoch);
  }

  Future<void> _confirm(ImportPreview preview) async {
    final epoch = ++_epoch;
    _emit(
      _state.copyWith(phase: ImportPhase.confirming, clearFailure: true),
      epoch,
    );

    final ImportPreview receipt;
    try {
      receipt = await _repository.confirmPreview(preview.uuid);
    } catch (error) {
      _fail(error, epoch, keepPreview: true);
      return;
    }
    if (!_isCurrent(epoch)) return;

    var hasPendingSync = false;
    try {
      await _synchronize();
    } catch (_) {
      hasPendingSync = true;
    }
    if (!_isCurrent(epoch)) return;

    _emit(
      ImportViewState(
        phase: ImportPhase.completed,
        preview: receipt,
        hasPendingSync: hasPendingSync,
      ),
      epoch,
    );
  }

  Future<void> _drainPages(int epoch) async {
    while (_isCurrent(epoch) && (_state.preview?.hasMorePages ?? false)) {
      if (!await _loadNextPage(epoch)) return;
    }
  }

  Future<bool> _loadNextPage(int epoch) async {
    final preview = _state.preview;
    if (preview == null || !preview.hasMorePages) return false;
    final cursor = int.parse(preview.nextCursor!);

    final ImportPreview page;
    try {
      page = await _repository.readPreview(preview.uuid, after: cursor);
    } catch (error) {
      _fail(error, epoch, keepPreview: true);
      return false;
    }
    if (!_isCurrent(epoch)) return false;

    _emit(
      ImportViewState(
        phase: ImportPhase.preview,
        preview: preview.appendPage(page),
      ),
      epoch,
    );
    return true;
  }

  void _fail(Object error, int epoch, {bool keepPreview = false}) {
    if (!_isCurrent(epoch)) return;
    _emit(
      ImportViewState(
        phase: ImportPhase.failure,
        preview: keepPreview ? _state.preview : null,
        failure: _kindOf(error),
      ),
      epoch,
    );
  }

  ImportFailureKind _kindOf(Object error) =>
      error is ImportFailure ? error.kind : ImportFailureKind.unknown;

  bool _isCurrent(int epoch) => !_disposed && _epoch == epoch;

  void _emit(ImportViewState state, int epoch) {
    if (!_isCurrent(epoch)) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
