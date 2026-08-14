final class StoredTokens {
  const StoredTokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.deviceUuid,
  });

  factory StoredTokens.fromJson(Map<String, Object?> json) {
    final device = json['device'];
    if (device is! Map) {
      throw const FormatException('Invalid session response.');
    }
    final normalizedDevice = device.cast<String, Object?>();
    return StoredTokens(
      accessToken: _requiredString(json, 'access_token'),
      accessExpiresAt: _requiredDate(json, 'access_expires_at'),
      refreshToken: _requiredString(json, 'refresh_token'),
      refreshExpiresAt: _requiredDate(json, 'refresh_expires_at'),
      deviceUuid: _requiredString(normalizedDevice, 'uuid'),
    );
  }

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String deviceUuid;

  @override
  String toString() => 'StoredTokens(<redacted>)';
}

abstract interface class TokenStore {
  Future<StoredTokens?> read();
  Future<void> write(StoredTokens tokens);
  Future<void> clear();
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid session response.');
  }
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = json[key];
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) {
    throw const FormatException('Invalid session response.');
  }
  return parsed;
}
