import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_error.dart';
import '../domain/session.dart';

final class SecureTokenStore implements TokenStore {
  SecureTokenStore(this.storage);

  final FlutterSecureStorage storage;

  static const _access = 'session.access';
  static const _accessExpiry = 'session.access_expiry';
  static const _refresh = 'session.refresh';
  static const _refreshExpiry = 'session.refresh_expiry';
  static const _deviceUuid = 'session.device_uuid';
  static const _identity = 'session.identity';

  @override
  Future<StoredTokens?> read() async {
    try {
      final values = await Future.wait<String?>([
        storage.read(key: _access),
        storage.read(key: _accessExpiry),
        storage.read(key: _refresh),
        storage.read(key: _refreshExpiry),
        storage.read(key: _deviceUuid),
        storage.read(key: _identity),
      ]);
      final requiredValues = values.take(5);
      if (requiredValues.every((value) => value == null)) {
        return null;
      }
      final accessExpiry = DateTime.tryParse(values[1] ?? '');
      final refreshExpiry = DateTime.tryParse(values[3] ?? '');
      if (requiredValues.any((value) => value == null || value.isEmpty) ||
          accessExpiry == null ||
          refreshExpiry == null) {
        await clear();
        return null;
      }
      return StoredTokens(
        accessToken: values[0]!,
        accessExpiresAt: accessExpiry,
        refreshToken: values[2]!,
        refreshExpiresAt: refreshExpiry,
        deviceUuid: values[4]!,
        sessionIdentity: values[5],
      );
    } catch (_) {
      throw const RequestFailure();
    }
  }

  @override
  Future<void> write(StoredTokens tokens) async {
    try {
      await storage.write(key: _access, value: tokens.accessToken);
      await storage.write(
        key: _accessExpiry,
        value: tokens.accessExpiresAt.toUtc().toIso8601String(),
      );
      await storage.write(key: _refresh, value: tokens.refreshToken);
      await storage.write(
        key: _refreshExpiry,
        value: tokens.refreshExpiresAt.toUtc().toIso8601String(),
      );
      await storage.write(key: _deviceUuid, value: tokens.deviceUuid);
      final identity = tokens.sessionIdentity;
      if (identity == null || identity.isEmpty) {
        await storage.delete(key: _identity);
      } else {
        await storage.write(key: _identity, value: identity);
      }
    } catch (_) {
      await clear();
      throw const RequestFailure();
    }
  }

  @override
  Future<void> clear() async {
    try {
      for (final key in const <String>[
        _access,
        _accessExpiry,
        _refresh,
        _refreshExpiry,
        _deviceUuid,
        _identity,
      ]) {
        await storage.delete(key: key);
      }
    } catch (_) {
      throw const RequestFailure();
    }
  }
}
