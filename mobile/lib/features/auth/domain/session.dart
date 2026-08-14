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

final class SessionSnapshot {
  const SessionSnapshot({required this.tokens, required this.generation});

  final StoredTokens tokens;
  final int generation;
}

/// Serializes local session transitions and invalidates work that started
/// before a logout or a newer login.
final class SessionAuthority {
  SessionAuthority._(this._tokenStore);

  static final Expando<SessionAuthority> _byTokenStore =
      Expando<SessionAuthority>('sessionAuthority');

  factory SessionAuthority.forStore(TokenStore tokenStore) =>
      _byTokenStore[tokenStore] ??= SessionAuthority._(tokenStore);

  final TokenStore _tokenStore;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  Future<StoredTokens?> read() async => (await snapshot())?.tokens;

  Future<SessionSnapshot?> snapshot() => _serialize(() async {
    final tokens = await _tokenStore.read();
    return tokens == null
        ? null
        : SessionSnapshot(tokens: tokens, generation: _generation);
  });

  Future<void> write(StoredTokens tokens) {
    _generation++;
    return _serialize(() => _tokenStore.write(tokens));
  }

  Future<void> clear() {
    _generation++;
    return _serialize(_tokenStore.clear);
  }

  Future<StoredTokens?> clearAndRead() {
    _generation++;
    return _serialize(() async {
      final tokens = await _tokenStore.read();
      await _tokenStore.clear();
      return tokens;
    });
  }

  Future<bool> commitRefresh(SessionSnapshot expected, StoredTokens rotated) =>
      _serialize(() async {
        if (_generation != expected.generation) return false;
        await _tokenStore.write(rotated);
        return true;
      });

  Future<bool> clearIfCurrent(SessionSnapshot expected) => _serialize(() async {
    if (_generation != expected.generation) return false;
    _generation++;
    await _tokenStore.clear();
    return true;
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _tail.then<T>((_) => operation());
    _tail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }
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
