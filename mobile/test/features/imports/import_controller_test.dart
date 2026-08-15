import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/features/imports/application/import_controller.dart';
import 'package:lar_finance/features/imports/data/import_repository.dart';
import 'package:lar_finance/features/imports/data/ofx_file_picker.dart';
import 'package:lar_finance/features/imports/domain/import_preview.dart';

const _batchUuid = '00000000-0000-4000-8000-000000000000';

void main() {
  group('ImportController selection', () {
    test('a cancelled picker returns to idle without an error', () async {
      final controller = _controller(picker: _FakePicker.cancelled());

      await controller.selectFile();

      expect(controller.state.phase, ImportPhase.idle);
      expect(controller.state.failure, isNull);
      expect(controller.state.preview, isNull);
    });

    test('an upload loads every page in order', () async {
      final repository = _FakeRepository(
        preview: _preview(records: <int>[1, 2], nextCursor: '2'),
        pages: <ImportPreview>[
          _preview(records: <int>[3, 4]),
        ],
      );
      final controller = _controller(repository: repository);

      await controller.selectFile();

      expect(controller.state.phase, ImportPhase.preview);
      expect(
        controller.state.records.map((record) => record.description),
        <String>['linha 1', 'linha 2', 'linha 3', 'linha 4'],
      );
      expect(repository.readCursors, <int?>[2]);
      expect(controller.state.preview!.hasMorePages, isFalse);
    });

    test('the selected bytes are dropped once the upload finishes', () async {
      final repository = _FakeRepository(preview: _preview());
      final controller = _controller(repository: repository);

      await controller.selectFile();

      expect(controller.debugRetainsBytes, isFalse);
    });

    for (final failure
        in <({String name, Object error, ImportFailureKind kind})>[
          (
            name: 'offline',
            error: const ImportFailure(ImportFailureKind.offline),
            kind: ImportFailureKind.offline,
          ),
          (
            name: 'invalid',
            error: const ImportFailure(ImportFailureKind.invalidFile),
            kind: ImportFailureKind.invalidFile,
          ),
          (
            name: 'oversized',
            error: const ImportFailure(ImportFailureKind.fileTooLarge),
            kind: ImportFailureKind.fileTooLarge,
          ),
          (
            name: 'expired',
            error: const ImportFailure(ImportFailureKind.expiredPreview),
            kind: ImportFailureKind.expiredPreview,
          ),
          (
            name: 'busy',
            error: const ImportFailure(ImportFailureKind.busy),
            kind: ImportFailureKind.busy,
          ),
          (
            name: 'malformed',
            error: const FormatException('bad payload'),
            kind: ImportFailureKind.unknown,
          ),
        ]) {
      test('${failure.name} becomes its own safe failure', () async {
        final controller = _controller(
          repository: _FakeRepository(previewError: failure.error),
        );

        await controller.selectFile();

        expect(controller.state.phase, ImportPhase.failure);
        expect(controller.state.failure, failure.kind);
        expect(controller.state.preview, isNull);
      });
    }

    test('a refused selection never reaches the network', () async {
      final repository = _FakeRepository(preview: _preview());
      final controller = _controller(
        picker: _FakePicker.failing(
          const ImportFailure(ImportFailureKind.unsupportedFile),
        ),
        repository: repository,
      );

      await controller.selectFile();

      expect(controller.state.failure, ImportFailureKind.unsupportedFile);
      expect(repository.createCalls, 0);
    });
  });

  group('ImportController serialization', () {
    test('a retry ignores the stale result of the previous attempt', () async {
      final slowUpload = Completer<ImportPreview>();
      final repository = _FakeRepository(previewFuture: slowUpload.future);
      final controller = _controller(repository: repository);

      final stale = controller.selectFile();
      controller.reset();
      slowUpload.complete(_preview());
      await stale;

      expect(controller.state.phase, ImportPhase.idle);
      expect(controller.state.preview, isNull);
    });

    test('two confirm taps produce a single call', () async {
      final repository = _FakeRepository(preview: _preview());
      final controller = _controller(repository: repository);
      await controller.selectFile();

      await Future.wait(<Future<void>>[
        controller.confirm(),
        controller.confirm(),
      ]);

      expect(repository.confirmCalls, 1);
      expect(controller.state.phase, ImportPhase.completed);
    });

    test('cancelling clears the preview held in memory', () async {
      final repository = _FakeRepository(preview: _preview());
      final controller = _controller(repository: repository);
      await controller.selectFile();

      await controller.cancel();

      expect(repository.cancelCalls, 1);
      expect(controller.state.phase, ImportPhase.idle);
      expect(controller.state.preview, isNull);
      expect(controller.state.records, isEmpty);
      expect(controller.debugRetainsBytes, isFalse);
    });

    test('a late future cannot touch a disposed controller', () async {
      final slowUpload = Completer<ImportPreview>();
      final controller = _controller(
        repository: _FakeRepository(previewFuture: slowUpload.future),
      );

      final pending = controller.selectFile();
      controller.dispose();
      slowUpload.complete(_preview());

      await pending;
      expect(controller.state.phase, ImportPhase.picking);
      expect(controller.state.preview, isNull);
    });
  });

  group('ImportController confirmation', () {
    test('the ledger is synchronized before the receipt is shown', () async {
      final order = <String>[];
      final repository = _FakeRepository(
        preview: _preview(),
        onConfirm: () => order.add('confirm'),
      );
      final controller = _controller(
        repository: repository,
        synchronize: () async => order.add('sync'),
      );
      await controller.selectFile();

      await controller.confirm();

      expect(order, <String>['confirm', 'sync']);
      expect(controller.state.phase, ImportPhase.completed);
      expect(controller.state.hasPendingSync, isFalse);
    });

    test('a failed pull keeps the receipt and flags pending data', () async {
      final controller = _controller(
        repository: _FakeRepository(preview: _preview()),
        synchronize: () async =>
            throw const ImportFailure(ImportFailureKind.offline),
      );
      await controller.selectFile();

      await controller.confirm();

      expect(controller.state.phase, ImportPhase.completed);
      expect(controller.state.hasPendingSync, isTrue);
      expect(controller.state.preview, isNotNull);
    });

    test('a refused confirmation keeps the batch for a retry', () async {
      final repository = _FakeRepository(
        preview: _preview(),
        confirmError: const ImportFailure(ImportFailureKind.busy),
      );
      final controller = _controller(repository: repository);
      await controller.selectFile();

      await controller.confirm();

      expect(controller.state.phase, ImportPhase.failure);
      expect(controller.state.failure, ImportFailureKind.busy);
      expect(controller.state.preview, isNotNull);
    });
  });

  group('ImportController retry', () {
    test('a page failure can be resumed from the last cursor', () async {
      final repository = _FakeRepository(
        preview: _preview(records: <int>[1, 2], nextCursor: '2'),
        pageError: const ImportFailure(ImportFailureKind.busy),
      );
      final controller = _controller(repository: repository);
      await controller.selectFile();
      expect(controller.state.phase, ImportPhase.failure);
      expect(controller.state.records, hasLength(2));

      repository.pageError = null;
      repository.pages = <ImportPreview>[
        _preview(records: <int>[3]),
      ];
      await controller.retry();

      expect(controller.state.phase, ImportPhase.preview);
      expect(
        controller.state.records.map((record) => record.description),
        <String>['linha 1', 'linha 2', 'linha 3'],
      );
      expect(repository.readCursors, <int?>[2, 2]);
    });

    test('loadMore advances exactly one page', () async {
      final repository = _FakeRepository(
        preview: _preview(records: <int>[1, 2], nextCursor: '2'),
        pageError: const ImportFailure(ImportFailureKind.busy),
      );
      final controller = _controller(repository: repository);
      await controller.selectFile();

      repository.pageError = null;
      repository.pages = <ImportPreview>[
        _preview(records: <int>[3], nextCursor: '3'),
      ];
      await controller.loadMore();

      expect(controller.state.records, hasLength(3));
      expect(controller.state.preview!.nextCursor, '3');
      expect(repository.readCursors, <int?>[2, 2]);
    });

    test('a failure without a batch asks for a new selection', () async {
      final controller = _controller(
        repository: _FakeRepository(
          previewError: const ImportFailure(ImportFailureKind.offline),
        ),
      );
      await controller.selectFile();

      await controller.retry();

      expect(controller.state.phase, ImportPhase.idle);
      expect(controller.state.failure, isNull);
    });
  });
}

ImportController _controller({
  _FakePicker? picker,
  _FakeRepository? repository,
  Future<void> Function()? synchronize,
}) => ImportController(
  picker: picker ?? _FakePicker.selecting(),
  repository: repository ?? _FakeRepository(preview: _preview()),
  synchronize: synchronize ?? () async {},
);

ImportPreview _preview({
  List<int> records = const <int>[1],
  String? nextCursor,
  ImportBatchStatus status = ImportBatchStatus.previewReady,
}) => ImportPreview(
  uuid: _batchUuid,
  status: status,
  productType: ImportProductType.bankAccount,
  statementStart: DateTime.utc(2026, 8, 1),
  statementEnd: DateTime.utc(2026, 8, 12),
  expiresAt: DateTime.utc(2026, 8, 16, 12),
  accountUuid: '00000000-0000-4000-8000-000000000001',
  financialOwnerUuid: '00000000-0000-4000-8000-000000000002',
  createdCount: 0,
  duplicateCount: 0,
  warningCount: 0,
  recordCount: 4,
  pendingCount: 4,
  incomeTotalMinor: 0,
  expenseTotalMinor: 1000,
  isRepeatedFile: false,
  records: records
      .map(
        (line) => ImportRecordPreview(
          uuid: '00000000-0000-4000-8000-00000000000$line',
          postedOn: DateTime.utc(2026, 8, line),
          description: 'linha $line',
          amountMinor: 100 * line,
          type: ImportEntryType.expense,
          outcome: ImportRecordOutcome.pending,
        ),
      )
      .toList(growable: false),
  nextCursor: nextCursor,
);

final class _FakePicker implements OfxFilePicker {
  _FakePicker.selecting() : _selection = _bytes(), _error = null;
  _FakePicker.cancelled() : _selection = null, _error = null;
  _FakePicker.failing(Object error) : _selection = null, _error = error;

  final SelectedOfx? _selection;
  final Object? _error;

  @override
  Future<SelectedOfx?> pick() async {
    final error = _error;
    if (error != null) throw error;
    return _selection;
  }
}

SelectedOfx _bytes() =>
    SelectedOfx(Uint8List.fromList(const <int>[79, 70, 88]));

final class _FakeRepository implements ImportRepository {
  _FakeRepository({
    ImportPreview? preview,
    Future<ImportPreview>? previewFuture,
    this.previewError,
    this.confirmError,
    this.pageError,
    this.pages = const <ImportPreview>[],
    this.onConfirm,
  }) : _preview = preview,
       _previewFuture = previewFuture;

  final ImportPreview? _preview;
  final Future<ImportPreview>? _previewFuture;
  final Object? previewError;
  final Object? confirmError;
  Object? pageError;
  List<ImportPreview> pages;
  final void Function()? onConfirm;

  final List<int?> readCursors = <int?>[];
  int createCalls = 0;
  int confirmCalls = 0;
  int cancelCalls = 0;

  @override
  Future<ImportPreview> createPreview(SelectedOfx file) {
    createCalls++;
    final error = previewError;
    if (error != null) return Future<ImportPreview>.error(error);
    return _previewFuture ?? Future<ImportPreview>.value(_preview);
  }

  @override
  Future<ImportPreview> readPreview(
    String batchUuid, {
    int? after,
    int? limit,
  }) async {
    readCursors.add(after);
    final error = pageError;
    if (error != null) throw error;
    if (pages.isEmpty) throw StateError('No page was prepared.');
    return pages.removeAt(0);
  }

  @override
  Future<ImportPreview> confirmPreview(String batchUuid) async {
    confirmCalls++;
    onConfirm?.call();
    final error = confirmError;
    if (error != null) throw error;
    return _preview!;
  }

  @override
  Future<ImportPreview> cancelPreview(String batchUuid) async {
    cancelCalls++;
    return _preview!;
  }
}
