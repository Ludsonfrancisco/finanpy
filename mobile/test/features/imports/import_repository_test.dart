import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/network/api_error.dart';
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/core/network/session_transport.dart';
import 'package:lar_finance/features/auth/domain/session.dart';
import 'package:lar_finance/features/imports/data/import_repository.dart';
import 'package:lar_finance/features/imports/data/ofx_file_picker.dart';
import 'package:lar_finance/features/imports/domain/import_preview.dart';

const _batchUuid = '00000000-0000-4000-8000-000000000000';

void main() {
  group('DjangoImportRepository upload', () {
    test('a preview is uploaded as multipart with a constant name', () async {
      final transport = _FakeApiTransport(
        (request) async => ApiResponse(statusCode: 201, data: _previewJson()),
      );
      final repository = _repository(transport);

      await repository.createPreview(
        SelectedOfx(Uint8List.fromList(const <int>[79, 70, 88])),
      );

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/imports/ofx/preview/');
      final form = request.data! as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'statement.ofx');
      expect(form.fields, isEmpty);
    });

    test('an oversized selection never reaches the network', () async {
      final transport = _FakeApiTransport(
        (request) async => ApiResponse(statusCode: 201, data: _previewJson()),
      );
      final repository = _repository(transport);

      await expectLater(
        repository.createPreview(SelectedOfx(Uint8List(maxOfxBytes + 1))),
        throwsA(
          isA<ImportFailure>().having(
            (failure) => failure.kind,
            'kind',
            ImportFailureKind.fileTooLarge,
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('DjangoImportRepository parsing', () {
    test('a full preview becomes canonical domain values', () async {
      final repository = _repository(
        _FakeApiTransport(
          (request) async => ApiResponse(statusCode: 200, data: _previewJson()),
        ),
      );

      final preview = await repository.readPreview(_batchUuid);

      expect(preview.uuid, _batchUuid);
      expect(preview.status, ImportBatchStatus.previewReady);
      expect(preview.productType, ImportProductType.bankAccount);
      expect(preview.statementStart, DateTime.utc(2026, 8, 1));
      expect(preview.statementEnd, DateTime.utc(2026, 8, 12));
      expect(preview.expiresAt, DateTime.utc(2026, 8, 16, 12));
      expect(preview.expiresAt.isUtc, isTrue);
      expect(preview.accountUuid, '00000000-0000-4000-8000-000000000001');
      expect(
        preview.financialOwnerUuid,
        '00000000-0000-4000-8000-000000000002',
      );
      expect(preview.recordCount, 3);
      expect(preview.pendingCount, 2);
      expect(preview.incomeTotalMinor, 100000);
      expect(preview.expenseTotalMinor, 25050);
      expect(preview.isRepeatedFile, isFalse);
      expect(preview.nextCursor, '2');
      expect(preview.records, hasLength(2));

      final first = preview.records.first;
      expect(first.uuid, '00000000-0000-4000-8000-000000000003');
      expect(first.postedOn, DateTime.utc(2026, 8, 1));
      expect(first.description, 'Compra sintetica');
      expect(first.amountMinor, 2500);
      expect(first.type, ImportEntryType.expense);
      expect(first.outcome, ImportRecordOutcome.pending);
      expect(preview.records.last.type, ImportEntryType.income);
      expect(preview.records.last.outcome, ImportRecordOutcome.duplicate);
    });

    test('a null cursor closes the pagination', () async {
      final repository = _repository(
        _FakeApiTransport(
          (request) async => ApiResponse(
            statusCode: 200,
            data: _previewJson(nextCursor: null, records: const <Object?>[]),
          ),
        ),
      );

      final preview = await repository.readPreview(_batchUuid);

      expect(preview.nextCursor, isNull);
      expect(preview.records, isEmpty);
    });

    for (final malformed in <({String name, Map<String, Object?> json})>[
      (name: 'a missing field', json: _previewJson()..remove('record_count')),
      (name: 'a non canonical uuid', json: _previewJson(uuid: 'not-a-uuid')),
      (
        name: 'a naive instant',
        json: _previewJson(expiresAt: '2026-08-16T12:00:00'),
      ),
      (
        name: 'an impossible civil date',
        json: _previewJson(statementStart: '2026-02-31'),
      ),
      (name: 'a float amount', json: _previewJson(incomeTotal: '1000.0')),
      (
        name: 'a negative magnitude',
        json: _previewJson(incomeTotal: '-1000.00'),
      ),
      (name: 'an unknown status', json: _previewJson(status: 'archived')),
      (
        name: 'an unknown outcome',
        json: _previewJson(records: <Object?>[_recordJson(outcome: 'ignored')]),
      ),
      (
        name: 'a page above the documented maximum',
        json: _previewJson(
          records: List<Object?>.generate(101, (index) => _recordJson()),
        ),
      ),
    ]) {
      test('${malformed.name} is rejected without a partial model', () async {
        final repository = _repository(
          _FakeApiTransport(
            (request) async =>
                ApiResponse(statusCode: 200, data: malformed.json),
          ),
        );

        await expectLater(
          repository.readPreview(_batchUuid),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });

  group('DjangoImportRepository routes', () {
    test('paging builds an ordered cursor query', () async {
      final transport = _FakeApiTransport(
        (request) async => ApiResponse(statusCode: 200, data: _previewJson()),
      );
      final repository = _repository(transport);

      await repository.readPreview(_batchUuid);
      await repository.readPreview(_batchUuid, after: 2, limit: 10);

      expect(transport.requests.first.method, 'GET');
      expect(transport.requests.first.path, '/imports/$_batchUuid/?limit=50');
      expect(
        transport.requests.last.path,
        '/imports/$_batchUuid/?after=2&limit=10',
      );
    });

    test('confirm and cancel post to their own routes', () async {
      final transport = _FakeApiTransport(
        (request) async => ApiResponse(statusCode: 200, data: _previewJson()),
      );
      final repository = _repository(transport);

      await repository.confirmPreview(_batchUuid);
      await repository.cancelPreview(_batchUuid);

      expect(transport.requests.map((request) => request.path), <String>[
        '/imports/$_batchUuid/confirm/',
        '/imports/$_batchUuid/cancel/',
      ]);
      expect(transport.requests.map((request) => request.method), <String>[
        'POST',
        'POST',
      ]);
    });

    test(
      'an identifier that is not a canonical uuid never builds a path',
      () async {
        final transport = _FakeApiTransport(
          (request) async => ApiResponse(statusCode: 200, data: _previewJson()),
        );
        final repository = _repository(transport);

        await expectLater(
          repository.readPreview('../../accounts'),
          throwsA(isA<FormatException>()),
        );
        expect(transport.requests, isEmpty);
      },
    );

    test('paging arguments outside the contract are refused', () async {
      final transport = _FakeApiTransport(
        (request) async => ApiResponse(statusCode: 200, data: _previewJson()),
      );
      final repository = _repository(transport);

      await expectLater(
        repository.readPreview(_batchUuid, after: -1),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.readPreview(_batchUuid, limit: 0),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.readPreview(_batchUuid, limit: 101),
        throwsA(isA<ArgumentError>()),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('DjangoImportRepository failures', () {
    for (final mapping in <({String code, int status, ImportFailureKind kind})>[
      (
        code: 'unsupported_ofx',
        status: 400,
        kind: ImportFailureKind.unsupportedFile,
      ),
      (code: 'invalid_ofx', status: 400, kind: ImportFailureKind.invalidFile),
      (
        code: 'file_too_large',
        status: 400,
        kind: ImportFailureKind.fileTooLarge,
      ),
      (
        code: 'invalid_import_state',
        status: 400,
        kind: ImportFailureKind.invalidState,
      ),
      (
        code: 'invalid_import_page',
        status: 400,
        kind: ImportFailureKind.invalidState,
      ),
      (
        code: 'expired_import_preview',
        status: 400,
        kind: ImportFailureKind.expiredPreview,
      ),
      (code: 'not_found', status: 404, kind: ImportFailureKind.notFound),
      (
        code: 'import_temporarily_unavailable',
        status: 503,
        kind: ImportFailureKind.busy,
      ),
      (code: 'internal_error', status: 500, kind: ImportFailureKind.unknown),
    ]) {
      test('${mapping.code} becomes ${mapping.kind.name}', () async {
        final repository = _repository(
          _FakeApiTransport(
            (request) async => ApiResponse(
              statusCode: mapping.status,
              data: <String, Object?>{
                'error': <String, Object?>{
                  'code': mapping.code,
                  'message': 'mensagem remota que nao pode virar UI',
                },
              },
            ),
          ),
        );

        final failure = await _captureError(
          repository.confirmPreview(_batchUuid),
        );

        expect(failure, isA<ImportFailure>());
        expect((failure! as ImportFailure).kind, mapping.kind);
        expect(
          failure.toString(),
          isNot(contains('mensagem remota que nao pode virar UI')),
        );
      });
    }

    test('an offline transport keeps its own domain state', () async {
      final repository = _repository(
        _FakeApiTransport((request) async => throw const OfflineFailure()),
      );

      final failure = await _captureError(repository.cancelPreview(_batchUuid));

      expect((failure! as ImportFailure).kind, ImportFailureKind.offline);
    });

    test('an expired session is not disguised as an import failure', () async {
      final repository = _repository(
        _FakeApiTransport(
          (request) async =>
              const ApiResponse(statusCode: 401, data: <String, Object?>{}),
        ),
        tokens: _expiredRefreshTokens(),
      );

      await expectLater(
        repository.confirmPreview(_batchUuid),
        throwsA(isA<SessionExpired>()),
      );
    });
  });
}

DjangoImportRepository _repository(
  _FakeApiTransport transport, {
  StoredTokens? tokens,
}) => DjangoImportRepository(
  SessionTransport(
    transport: transport,
    tokenStore: _FakeTokenStore(tokens ?? _tokens()),
  ),
);

Future<Object?> _captureError(Future<Object?> future) async {
  try {
    await future;
  } catch (error) {
    return error;
  }
  return null;
}

Map<String, Object?> _previewJson({
  String uuid = _batchUuid,
  String status = 'preview_ready',
  String statementStart = '2026-08-01',
  String expiresAt = '2026-08-16T12:00:00Z',
  String incomeTotal = '1000.00',
  Object? nextCursor = '2',
  List<Object?>? records,
}) => <String, Object?>{
  'uuid': uuid,
  'status': status,
  'provider': 'nubank',
  'product_type': 'bank_account',
  'statement_start': statementStart,
  'statement_end': '2026-08-12',
  'expires_at': expiresAt,
  'account_uuid': '00000000-0000-4000-8000-000000000001',
  'financial_owner_uuid': '00000000-0000-4000-8000-000000000002',
  'created_count': 0,
  'duplicate_count': 1,
  'warning_count': 0,
  'record_count': 3,
  'pending_count': 2,
  'income_total': incomeTotal,
  'expense_total': '250.50',
  'is_repeated_file': false,
  'records':
      records ??
      <Object?>[
        _recordJson(),
        _recordJson(
          uuid: '00000000-0000-4000-8000-000000000004',
          amount: '1000.00',
          transactionType: 'income',
          outcome: 'duplicate',
        ),
      ],
  'next_cursor': nextCursor,
};

Map<String, Object?> _recordJson({
  String uuid = '00000000-0000-4000-8000-000000000003',
  String amount = '25.00',
  String transactionType = 'expense',
  String outcome = 'pending',
}) => <String, Object?>{
  'uuid': uuid,
  'posted_on': '2026-08-01',
  'description': 'Compra sintetica',
  'amount': amount,
  'transaction_type': transactionType,
  'outcome': outcome,
};

StoredTokens _tokens() => StoredTokens(
  accessToken: 'access-old',
  accessExpiresAt: DateTime.utc(2030, 1, 1),
  refreshToken: 'refresh-old',
  refreshExpiresAt: DateTime.utc(2030, 2, 1),
  deviceUuid: '11111111-1111-4111-8111-111111111111',
);

StoredTokens _expiredRefreshTokens() => StoredTokens(
  accessToken: 'access-old',
  accessExpiresAt: DateTime.utc(2030, 1, 1),
  refreshToken: 'refresh-old',
  refreshExpiresAt: DateTime.utc(2020, 1, 1),
  deviceUuid: '11111111-1111-4111-8111-111111111111',
);

final class _RequestRecord {
  const _RequestRecord({
    required this.method,
    required this.path,
    required this.data,
  });

  final String method;
  final String path;
  final Object? data;
}

final class _FakeApiTransport implements ApiTransport {
  _FakeApiTransport(this.handler);

  final Future<ApiResponse> Function(_RequestRecord request) handler;
  final List<_RequestRecord> requests = <_RequestRecord>[];

  @override
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  }) {
    final record = _RequestRecord(method: method, path: path, data: data);
    requests.add(record);
    return handler(record);
  }
}

final class _FakeTokenStore implements TokenStore {
  _FakeTokenStore(this.value);

  StoredTokens? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredTokens?> read() async => value;

  @override
  Future<void> write(StoredTokens tokens) async => value = tokens;
}
