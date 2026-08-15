import 'package:dio/dio.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/session_transport.dart';
import '../domain/import_preview.dart';
import 'ofx_file_picker.dart';

abstract interface class ImportRepository {
  Future<ImportPreview> createPreview(SelectedOfx file);
  Future<ImportPreview> readPreview(String batchUuid, {int? after, int? limit});
  Future<ImportPreview> confirmPreview(String batchUuid);
  Future<ImportPreview> cancelPreview(String batchUuid);
}

/// Talks to the private import routes. The server stays the only authority:
/// nothing here parses OFX, deduplicates, or writes a transaction.
final class DjangoImportRepository implements ImportRepository {
  const DjangoImportRepository(this._transport);

  /// The upload never carries the real file name.
  static const uploadFileName = 'statement.ofx';
  static const defaultPageSize = 50;

  final SessionTransport _transport;

  @override
  Future<ImportPreview> createPreview(SelectedOfx file) async {
    if (file.bytes.lengthInBytes > maxOfxBytes) {
      throw const ImportFailure(ImportFailureKind.fileTooLarge);
    }
    return _guard(
      () => _transport.postObject(
        '/imports/ofx/preview/',
        data: FormData.fromMap(<String, Object?>{
          'file': MultipartFile.fromBytes(file.bytes, filename: uploadFileName),
        }),
      ),
    );
  }

  @override
  Future<ImportPreview> readPreview(
    String batchUuid, {
    int? after,
    int? limit,
  }) async {
    final path = _batchPath(batchUuid);
    final size = limit ?? defaultPageSize;
    if (after != null && after < 0) {
      throw ArgumentError.value(after, 'after', 'must not be negative');
    }
    if (size < 1 || size > maxImportPageSize) {
      throw ArgumentError.value(size, 'limit', 'must be between 1 and 100');
    }
    final query = <String>[if (after != null) 'after=$after', 'limit=$size'];
    return _guard(
      () => _transport.getObject(
        '$path?${query.join('&')}',
        surfaceServerErrors: true,
      ),
    );
  }

  @override
  Future<ImportPreview> confirmPreview(String batchUuid) async {
    final path = _batchPath(batchUuid);
    return _guard(() => _transport.postObject('${path}confirm/'));
  }

  @override
  Future<ImportPreview> cancelPreview(String batchUuid) async {
    final path = _batchPath(batchUuid);
    return _guard(() => _transport.postObject('${path}cancel/'));
  }

  String _batchPath(String batchUuid) =>
      '/imports/${canonicalImportUuid(batchUuid)}/';

  Future<ImportPreview> _guard(
    Future<Map<String, Object?>> Function() send,
  ) async {
    try {
      return parseImportPreview(await send());
    } on ServerFailure catch (failure) {
      throw ImportFailure(_kindFor(failure));
    } on OfflineFailure {
      throw const ImportFailure(ImportFailureKind.offline);
    } on RequestFailure {
      throw const ImportFailure(ImportFailureKind.unknown);
    }
  }

  ImportFailureKind _kindFor(ServerFailure failure) => switch (failure.code) {
    'unsupported_ofx' => ImportFailureKind.unsupportedFile,
    'file_too_large' => ImportFailureKind.fileTooLarge,
    'invalid_ofx' => ImportFailureKind.invalidFile,
    'invalid_import_state' ||
    'invalid_import_page' => ImportFailureKind.invalidState,
    'expired_import_preview' => ImportFailureKind.expiredPreview,
    'not_found' => ImportFailureKind.notFound,
    'import_temporarily_unavailable' => ImportFailureKind.busy,
    _ =>
      failure.statusCode == 404
          ? ImportFailureKind.notFound
          : ImportFailureKind.unknown,
  };
}
