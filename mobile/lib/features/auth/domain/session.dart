import 'dart:convert';
import 'dart:math';

final class StoredTokens {
  const StoredTokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.deviceUuid,
    this.sessionIdentity,
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
  final String? sessionIdentity;

  StoredTokens withSessionIdentity(String identity) => StoredTokens(
    accessToken: accessToken,
    accessExpiresAt: accessExpiresAt,
    refreshToken: refreshToken,
    refreshExpiresAt: refreshExpiresAt,
    deviceUuid: deviceUuid,
    sessionIdentity: identity,
  );

  @override
  String toString() => 'StoredTokens(<redacted>)';
}

abstract interface class TokenStore {
  Future<StoredTokens?> read();
  Future<void> write(StoredTokens tokens);
  Future<void> clear();
}

final class SessionSnapshot {
  const SessionSnapshot({
    required this.tokens,
    required this.generation,
    required this.sessionIdentity,
  });

  final StoredTokens tokens;
  final int generation;
  final String sessionIdentity;
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
  String? _activeSessionIdentity;
  String? _activeDeviceUuid;

  static final Object _retrySnapshot = Object();

  Future<StoredTokens?> read() async => (await snapshot())?.tokens;

  Future<SessionSnapshot?> snapshot() async {
    while (true) {
      final result = await _serialize<Object?>(() async {
        final expectedGeneration = _generation;
        var tokens = await _tokenStore.read();
        if (_generation != expectedGeneration) return _retrySnapshot;
        if (tokens == null) {
          _activeSessionIdentity = null;
          _activeDeviceUuid = null;
          return null;
        }

        var identity = tokens.sessionIdentity;
        if (identity == null || identity.isEmpty) {
          identity = _newSessionIdentity();
          tokens = tokens.withSessionIdentity(identity);
          await _tokenStore.write(tokens);
          if (_generation != expectedGeneration) return _retrySnapshot;
        }
        _activeSessionIdentity = identity;
        _activeDeviceUuid = tokens.deviceUuid;
        return SessionSnapshot(
          tokens: tokens,
          generation: expectedGeneration,
          sessionIdentity: identity,
        );
      });
      if (!identical(result, _retrySnapshot)) {
        return result as SessionSnapshot?;
      }
    }
  }

  Future<bool> isCurrent(SessionSnapshot expected) => _serialize(() async {
    final expectedGeneration = expected.generation;
    if (_generation != expectedGeneration) return false;
    final tokens = await _tokenStore.read();
    if (_generation != expectedGeneration || tokens == null) return false;
    return tokens.sessionIdentity == expected.sessionIdentity &&
        tokens.deviceUuid == expected.tokens.deviceUuid;
  });

  bool isGenerationCurrent(SessionSnapshot expected) =>
      _generation == expected.generation &&
      _activeSessionIdentity == expected.sessionIdentity &&
      _activeDeviceUuid == expected.tokens.deviceUuid;

  Future<void> write(StoredTokens tokens) {
    _generation++;
    final generation = _generation;
    final identified = tokens.withSessionIdentity(_newSessionIdentity());
    _activeSessionIdentity = identified.sessionIdentity;
    _activeDeviceUuid = identified.deviceUuid;
    return _serialize(() async {
      if (_generation == generation) await _tokenStore.write(identified);
    });
  }

  Future<void> clear() {
    _generation++;
    _activeSessionIdentity = null;
    _activeDeviceUuid = null;
    return _serialize(_tokenStore.clear);
  }

  Future<StoredTokens?> clearAndRead() {
    _generation++;
    _activeSessionIdentity = null;
    _activeDeviceUuid = null;
    return _serialize(() async {
      final tokens = await _tokenStore.read();
      await _tokenStore.clear();
      return tokens;
    });
  }

  Future<bool> commitRefresh(SessionSnapshot expected, StoredTokens rotated) =>
      _serialize(() async {
        final expectedGeneration = expected.generation;
        if (_generation != expectedGeneration ||
            rotated.deviceUuid != expected.tokens.deviceUuid ||
            (rotated.sessionIdentity != null &&
                rotated.sessionIdentity != expected.sessionIdentity)) {
          return false;
        }
        final current = await _tokenStore.read();
        if (_generation != expectedGeneration ||
            current?.sessionIdentity != expected.sessionIdentity ||
            current?.deviceUuid != expected.tokens.deviceUuid) {
          return false;
        }
        final identified = rotated.withSessionIdentity(
          expected.sessionIdentity,
        );
        await _tokenStore.write(identified);
        if (_generation != expectedGeneration) return false;
        _activeSessionIdentity = expected.sessionIdentity;
        _activeDeviceUuid = expected.tokens.deviceUuid;
        return true;
      });

  Future<bool> clearIfCurrent(SessionSnapshot expected) => _serialize(() async {
    final expectedGeneration = expected.generation;
    if (_generation != expectedGeneration) return false;
    final current = await _tokenStore.read();
    if (_generation != expectedGeneration ||
        current?.sessionIdentity != expected.sessionIdentity ||
        current?.deviceUuid != expected.tokens.deviceUuid) {
      return false;
    }
    _generation++;
    _activeSessionIdentity = null;
    _activeDeviceUuid = null;
    await _tokenStore.clear();
    return true;
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _tail.then<T>((_) => operation());
    _tail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }
}

String _newSessionIdentity() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
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
