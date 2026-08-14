import 'dart:io';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_transport.dart';
import '../../../core/network/session_transport.dart';
import '../../../core/storage/app_database.dart';
import '../domain/session.dart';

final class DeviceOwnerOption {
  const DeviceOwnerOption({
    required this.uuid,
    required this.type,
    required this.name,
  });

  final String uuid;
  final String type;
  final String name;
}

final class LoginResult {
  const LoginResult({required this.session, required this.owners});

  final StoredTokens session;
  final List<DeviceOwnerOption> owners;
}

abstract interface class AuthGateway {
  Future<LoginResult> login({required String email, required String password});
  Future<List<DeviceOwnerOption>> loadOwners();
  Future<void> selectDeviceOwner(String uuid);
  Future<void> logout();
  Future<StoredTokens?> readSession();
  Future<String?> readSelectedOwnerUuid();
  Future<String> readDeviceName();
  Future<DateTime?> readLastSyncAt();
  Future<String?> readSyncedDeviceUuid();
}

final class AuthRepository implements AuthGateway {
  AuthRepository({
    required ApiTransport publicTransport,
    required SessionTransport sessionTransport,
    required TokenStore tokenStore,
    required AppDatabase database,
    String? platformName,
    String? deviceName,
  }) : _publicTransport = publicTransport,
       _sessionTransport = sessionTransport,
       _tokenStore = tokenStore,
       _database = database,
       _platformName = platformName ?? _currentPlatformName(),
       _deviceName = deviceName ?? _currentDeviceName();

  static const selectedOwnerSettingKey = 'device.default_owner_uuid';
  static const deviceNameSettingKey = 'device.name';

  final ApiTransport _publicTransport;
  final SessionTransport _sessionTransport;
  final TokenStore _tokenStore;
  final AppDatabase _database;
  final String _platformName;
  final String _deviceName;
  Set<String> _eligibleOwnerUuids = const <String>{};

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _safePublicRequest(
      '/auth/login/',
      method: 'POST',
      data: <String, Object?>{
        'email': email,
        'password': password,
        'platform': _platformName,
        'name': _deviceName,
      },
    );
    if (response.statusCode == 400 || response.statusCode == 401) {
      throw const AuthFailure();
    }
    if (!response.isSuccessful) {
      throw const RequestFailure();
    }

    final session = _parseSession(response.data);
    try {
      await _tokenStore.write(session);
      await _writeSetting(deviceNameSettingKey, _deviceName);
      final owners = await loadOwners();
      return LoginResult(session: session, owners: owners);
    } on ApiError {
      await _clearTokensSafely();
      rethrow;
    } catch (_) {
      await _clearTokensSafely();
      throw const RequestFailure();
    }
  }

  @override
  Future<List<DeviceOwnerOption>> loadOwners() async {
    final body = await _sessionTransport.getList('/owners/');
    final owners = <DeviceOwnerOption>[];
    for (final item in body) {
      if (item is! Map) {
        throw const RequestFailure();
      }
      final json = item.cast<String, Object?>();
      final uuid = json['uuid'];
      final type = json['type'];
      final name = json['name'];
      if (uuid is! String ||
          uuid.isEmpty ||
          type is! String ||
          name is! String ||
          name.isEmpty) {
        throw const RequestFailure();
      }
      if (type == 'self' || type == 'spouse') {
        owners.add(DeviceOwnerOption(uuid: uuid, type: type, name: name));
      }
    }
    _eligibleOwnerUuids = owners.map((owner) => owner.uuid).toSet();
    return List<DeviceOwnerOption>.unmodifiable(owners);
  }

  @override
  Future<void> selectDeviceOwner(String uuid) async {
    if (!_eligibleOwnerUuids.contains(uuid)) {
      throw const RequestFailure();
    }
    await _sessionTransport.patchObject('/devices/current/', <String, Object?>{
      'default_owner_uuid': uuid,
    });
    await _writeSetting(selectedOwnerSettingKey, uuid);
  }

  @override
  Future<void> logout() async {
    try {
      await _sessionTransport.postEmpty('/auth/logout/');
    } catch (_) {
      // Local logout is authoritative even when the server is unreachable.
    } finally {
      await _clearTokensSafely();
      await (_database.delete(
        _database.localSettings,
      )..where((row) => row.key.equals(selectedOwnerSettingKey))).go();
      _eligibleOwnerUuids = const <String>{};
    }
  }

  @override
  Future<String?> readSelectedOwnerUuid() =>
      _readSetting(selectedOwnerSettingKey);

  @override
  Future<String> readDeviceName() async =>
      await _readSetting(deviceNameSettingKey) ?? _deviceName;

  @override
  Future<DateTime?> readLastSyncAt() async {
    final sync = await (_database.select(
      _database.syncState,
    )..where((row) => row.key.equals('ledger'))).getSingleOrNull();
    return sync?.lastSuccessAt;
  }

  @override
  Future<String?> readSyncedDeviceUuid() async {
    final sync = await (_database.select(
      _database.syncState,
    )..where((row) => row.key.equals('ledger'))).getSingleOrNull();
    return sync?.sessionDeviceUuid;
  }

  @override
  Future<StoredTokens?> readSession() async {
    try {
      return await _tokenStore.read();
    } catch (_) {
      await _clearTokensSafely();
      return null;
    }
  }

  Future<ApiResponse> _safePublicRequest(
    String path, {
    required String method,
    Object? data,
  }) async {
    try {
      return await _publicTransport.request(path, method: method, data: data);
    } on OfflineFailure {
      rethrow;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const RequestFailure();
    }
  }

  StoredTokens _parseSession(Object? body) {
    if (body is! Map) {
      throw const RequestFailure();
    }
    try {
      return StoredTokens.fromJson(body.cast<String, Object?>());
    } catch (_) {
      throw const RequestFailure();
    }
  }

  Future<void> _writeSetting(String key, String value) => _database
      .into(_database.localSettings)
      .insertOnConflictUpdate(
        LocalSettingsCompanion.insert(key: key, value: value),
      );

  Future<String?> _readSetting(String key) async => (await (_database.select(
    _database.localSettings,
  )..where((row) => row.key.equals(key))).getSingleOrNull())?.value;

  Future<void> _clearTokensSafely() async {
    try {
      await _tokenStore.clear();
    } catch (_) {
      // The caller still transitions to signed out and exposes no credentials.
    }
  }

  static String _currentPlatformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    throw UnsupportedError('Unsupported mobile platform.');
  }

  static String _currentDeviceName() {
    if (Platform.isWindows) return 'Lar Finance no Windows';
    if (Platform.isAndroid) return 'Lar Finance no Android';
    if (Platform.isIOS) return 'Lar Finance no iPhone';
    throw UnsupportedError('Unsupported mobile platform.');
  }
}
