import '../../../core/money/minor_units.dart';

/// The upload limit enforced by the server, mirrored here to refuse early.
const maxOfxBytes = 10 * 1024 * 1024;

/// The largest page the private contract may return.
const maxImportPageSize = 100;

typedef _JsonObject = Map<String, Object?>;

enum ImportProductType { bankAccount, creditCard }

enum ImportBatchStatus {
  previewReady,
  needsAccountLink,
  completed,
  failed,
  cancelled,
}

enum ImportRecordOutcome { pending, duplicate, warning, created }

enum ImportEntryType { income, expense }

/// Every way the import flow can stop, expressed without remote text.
enum ImportFailureKind {
  invalidFile,
  unsupportedFile,
  fileTooLarge,
  invalidState,
  expiredPreview,
  notFound,
  busy,
  offline,
  unknown,
}

final class ImportFailure implements Exception {
  const ImportFailure(this.kind);

  final ImportFailureKind kind;

  @override
  String toString() => 'ImportFailure(${kind.name})';
}

final class ImportRecordPreview {
  const ImportRecordPreview({
    required this.uuid,
    required this.postedOn,
    required this.description,
    required this.amountMinor,
    required this.type,
    required this.outcome,
  });

  final String uuid;
  final DateTime postedOn;
  final String description;

  /// Absolute magnitude in minor units. The direction lives in [type].
  final int amountMinor;
  final ImportEntryType type;
  final ImportRecordOutcome outcome;
}

final class ImportPreview {
  const ImportPreview({
    required this.uuid,
    required this.status,
    required this.productType,
    required this.statementStart,
    required this.statementEnd,
    required this.expiresAt,
    required this.accountUuid,
    required this.financialOwnerUuid,
    required this.createdCount,
    required this.duplicateCount,
    required this.warningCount,
    required this.recordCount,
    required this.pendingCount,
    required this.incomeTotalMinor,
    required this.expenseTotalMinor,
    required this.isRepeatedFile,
    required this.records,
    required this.nextCursor,
  });

  final String uuid;
  final ImportBatchStatus status;
  final ImportProductType productType;
  final DateTime statementStart;
  final DateTime statementEnd;
  final DateTime expiresAt;
  final String? accountUuid;
  final String? financialOwnerUuid;
  final int createdCount;
  final int duplicateCount;
  final int warningCount;
  final int recordCount;
  final int pendingCount;
  final int incomeTotalMinor;
  final int expenseTotalMinor;
  final bool isRepeatedFile;
  final List<ImportRecordPreview> records;
  final String? nextCursor;

  bool get isActionable => status == ImportBatchStatus.previewReady;
  bool get hasMorePages => nextCursor != null;

  /// Keeps the records already received and adopts the newest page metadata.
  ImportPreview appendPage(ImportPreview page) => ImportPreview(
    uuid: page.uuid,
    status: page.status,
    productType: page.productType,
    statementStart: page.statementStart,
    statementEnd: page.statementEnd,
    expiresAt: page.expiresAt,
    accountUuid: page.accountUuid,
    financialOwnerUuid: page.financialOwnerUuid,
    createdCount: page.createdCount,
    duplicateCount: page.duplicateCount,
    warningCount: page.warningCount,
    recordCount: page.recordCount,
    pendingCount: page.pendingCount,
    incomeTotalMinor: page.incomeTotalMinor,
    expenseTotalMinor: page.expenseTotalMinor,
    isRepeatedFile: page.isRepeatedFile,
    records: <ImportRecordPreview>[...records, ...page.records],
    nextCursor: page.nextCursor,
  );
}

/// Builds a preview only when every field of the payload is acceptable.
ImportPreview parseImportPreview(Map<String, Object?> json) {
  final records = _requiredObjectList(json, 'records');
  if (records.length > maxImportPageSize) {
    throw const FormatException('An import page cannot exceed 100 records.');
  }
  return ImportPreview(
    uuid: _requiredUuid(json, 'uuid'),
    status: _requiredEnum(json, 'status', _statuses),
    productType: _requiredEnum(json, 'product_type', _productTypes),
    statementStart: _requiredCivilDate(json, 'statement_start'),
    statementEnd: _requiredCivilDate(json, 'statement_end'),
    expiresAt: _requiredUtcInstant(json, 'expires_at'),
    accountUuid: _optionalUuid(json, 'account_uuid'),
    financialOwnerUuid: _optionalUuid(json, 'financial_owner_uuid'),
    createdCount: _requiredCount(json, 'created_count'),
    duplicateCount: _requiredCount(json, 'duplicate_count'),
    warningCount: _requiredCount(json, 'warning_count'),
    recordCount: _requiredCount(json, 'record_count'),
    pendingCount: _requiredCount(json, 'pending_count'),
    incomeTotalMinor: _requiredMagnitudeMinor(json, 'income_total'),
    expenseTotalMinor: _requiredMagnitudeMinor(json, 'expense_total'),
    isRepeatedFile: _requiredBool(json, 'is_repeated_file'),
    records: records.map(_parseRecord).toList(growable: false),
    nextCursor: _optionalCursor(json, 'next_cursor'),
  );
}

ImportRecordPreview _parseRecord(_JsonObject json) => ImportRecordPreview(
  uuid: _requiredUuid(json, 'uuid'),
  postedOn: _requiredCivilDate(json, 'posted_on'),
  description: _requiredString(json, 'description'),
  amountMinor: _requiredMagnitudeMinor(json, 'amount'),
  type: _requiredEnum(json, 'transaction_type', _entryTypes),
  outcome: _requiredEnum(json, 'outcome', _outcomes),
);

const _statuses = <String, ImportBatchStatus>{
  'preview_ready': ImportBatchStatus.previewReady,
  'needs_account_link': ImportBatchStatus.needsAccountLink,
  'completed': ImportBatchStatus.completed,
  'failed': ImportBatchStatus.failed,
  'cancelled': ImportBatchStatus.cancelled,
};

const _productTypes = <String, ImportProductType>{
  'bank_account': ImportProductType.bankAccount,
  'credit_card': ImportProductType.creditCard,
};

const _outcomes = <String, ImportRecordOutcome>{
  'pending': ImportRecordOutcome.pending,
  'duplicate': ImportRecordOutcome.duplicate,
  'warning': ImportRecordOutcome.warning,
  'created': ImportRecordOutcome.created,
};

const _entryTypes = <String, ImportEntryType>{
  'income': ImportEntryType.income,
  'expense': ImportEntryType.expense,
};

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _civilDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _magnitudePattern = RegExp(r'^\d+\.\d{2}$');
final RegExp _cursorPattern = RegExp(r'^\d+$');

/// Canonical UUIDs are the only identifiers allowed to reach a request path.
String canonicalImportUuid(String value) {
  if (!_uuidPattern.hasMatch(value)) {
    throw const FormatException('Expected a canonical UUID string.');
  }
  return value.toLowerCase();
}

List<_JsonObject> _requiredObjectList(_JsonObject json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('$key must be an array.');
  }
  return value
      .map((item) {
        if (item is! Map) {
          throw FormatException('$key must contain only objects.');
        }
        return item.cast<String, Object?>();
      })
      .toList(growable: false);
}

String _requiredString(_JsonObject json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

String _requiredUuid(_JsonObject json, String key) {
  try {
    return canonicalImportUuid(_requiredString(json, key));
  } on FormatException {
    throw FormatException('$key must be a canonical UUID string.');
  }
}

String? _optionalUuid(_JsonObject json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('$key must be present.');
  }
  return json[key] == null ? null : _requiredUuid(json, key);
}

T _requiredEnum<T>(_JsonObject json, String key, Map<String, T> known) {
  final value = known[_requiredString(json, key)];
  if (value == null) {
    throw FormatException('$key is not a known value of this contract.');
  }
  return value;
}

DateTime _requiredCivilDate(_JsonObject json, String key) {
  final match = _civilDatePattern.firstMatch(_requiredString(json, key));
  if (match == null) {
    throw FormatException('$key must be a civil date.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw FormatException('$key is not a date that exists.');
  }
  return date;
}

DateTime _requiredUtcInstant(_JsonObject json, String key) {
  final value = _requiredString(json, key);
  if (!value.endsWith('Z')) {
    throw FormatException('$key must be an RFC3339 instant in UTC.');
  }
  return DateTime.parse(value).toUtc();
}

int _requiredCount(_JsonObject json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('$key must be a non-negative integer.');
  }
  return value;
}

bool _requiredBool(_JsonObject json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

int _requiredMagnitudeMinor(_JsonObject json, String key) {
  final value = _requiredString(json, key);
  if (!_magnitudePattern.hasMatch(value)) {
    throw FormatException('$key must be an unsigned decimal with two places.');
  }
  return parseMinorUnits(value);
}

String? _optionalCursor(_JsonObject json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('$key must be present.');
  }
  final value = json[key];
  if (value == null) return null;
  if (value is! String || !_cursorPattern.hasMatch(value)) {
    throw FormatException('$key must be a decimal cursor.');
  }
  return value;
}
