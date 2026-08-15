import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/network/api_error.dart';
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/core/network/session_transport.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/data/secure_token_store.dart';
import 'package:lar_finance/features/auth/domain/session.dart';

void main() {
  group('SecureTokenStore', () {
    test('round-trips and clears only redacted session values', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      const storage = FlutterSecureStorage();
      final store = SecureTokenStore(storage);
      final tokens = _tokens().withSessionIdentity(
        'opaque-synthetic-session-identity',
      );

      await store.write(tokens);
      final restored = await store.read();

      expect(restored?.accessToken, tokens.accessToken);
      expect(restored?.refreshToken, tokens.refreshToken);
      expect(restored?.sessionIdentity, tokens.sessionIdentity);
      expect(restored.toString(), isNot(contains(tokens.accessToken)));
      expect(restored.toString(), isNot(contains(tokens.refreshToken)));
      expect(restored.toString(), isNot(contains(tokens.sessionIdentity!)));

      await store.clear();
      expect(await store.read(), isNull);
    });
  });

  group('AuthRepository', () {
    late AppDatabase database;
    late _FakeTokenStore tokenStore;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      tokenStore = _FakeTokenStore();
    });

    tearDown(() => database.close());

    test(
      'login posts the exact device body, stores tokens, and filters shared',
      () async {
        final transport = _AuthApiTransport();
        final repository = _repository(database, tokenStore, transport);

        final result = await repository.login(
          email: 'ana@example.com',
          password: 'correct horse battery staple',
        );

        expect(transport.requests.first.data, <String, Object?>{
          'email': 'ana@example.com',
          'password': 'correct horse battery staple',
          'platform': 'windows',
          'name': 'Lar Finance no Windows',
        });
        expect(transport.requests.first.path, '/auth/login/');
        expect((await tokenStore.read())?.deviceUuid, _deviceUuid);
        expect(result.session.deviceUuid, _deviceUuid);
        expect(result.owners.map((owner) => owner.type), <String>[
          'self',
          'spouse',
        ]);
        expect(result.owners.map((owner) => owner.name), <String>[
          'Ana',
          'Beto',
        ]);
      },
    );

    test('login 401 exposes only the generic authentication message', () async {
      final transport = _AuthApiTransport(loginStatus: 401);
      final repository = _repository(database, tokenStore, transport);

      Object? failure;
      try {
        await repository.login(
          email: 'ana@example.com',
          password: 'secret-value',
        );
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<AuthFailure>());
      expect(
        failure.toString(),
        'Não foi possível entrar. Confira os dados e tente novamente.',
      );
      expect(failure.toString(), isNot(contains('secret-value')));
    });

    test('login rolls back stored tokens when loading owners fails', () async {
      final transport = _AuthApiTransport(ownersOffline: true);
      final repository = _repository(database, tokenStore, transport);

      await expectLater(
        repository.login(email: 'ana@example.com', password: 'secret'),
        throwsA(isA<OfflineFailure>()),
      );

      expect(await tokenStore.read(), isNull);
    });

    test(
      'login clears the session when no eligible device owner is returned',
      () async {
        final transport = _AuthApiTransport(ownersOnlyShared: true);
        final repository = _repository(database, tokenStore, transport);

        await expectLater(
          repository.login(email: 'ana@example.com', password: 'secret'),
          throwsA(isA<RequestFailure>()),
        );

        expect(await tokenStore.read(), isNull);
      },
    );

    test(
      'selectDeviceOwner patches an eligible UUID and stores it locally',
      () async {
        final transport = _AuthApiTransport();
        final repository = _repository(database, tokenStore, transport);
        await repository.login(email: 'ana@example.com', password: 'secret');

        await repository.selectDeviceOwner(_spouseUuid);

        final patch = transport.requests.last;
        expect(patch.method, 'PATCH');
        expect(patch.path, '/devices/current/');
        expect(patch.data, <String, Object?>{
          'default_owner_uuid': _spouseUuid,
        });
        final local =
            await (database.select(database.localSettings)..where(
                  (row) =>
                      row.key.equals(AuthRepository.selectedOwnerSettingKey),
                ))
                .getSingle();
        expect(local.value, _spouseUuid);
      },
    );

    test('shared is never accepted as a device identity', () async {
      final transport = _AuthApiTransport();
      final repository = _repository(database, tokenStore, transport);
      await repository.login(email: 'ana@example.com', password: 'secret');

      await expectLater(
        repository.selectDeviceOwner(_sharedUuid),
        throwsA(isA<RequestFailure>()),
      );

      expect(
        transport.requests.where((request) => request.method == 'PATCH'),
        isEmpty,
      );
    });

    test(
      'logout clears the session offline while preserving ledger cache',
      () async {
        final transport = _AuthApiTransport(logoutOffline: true);
        final repository = _repository(database, tokenStore, transport);
        await repository.login(email: 'ana@example.com', password: 'secret');
        await database
            .into(database.households)
            .insert(
              HouseholdsCompanion.insert(
                uuid: '55555555-5555-4555-8555-555555555555',
                name: 'Casa',
                updatedAt: DateTime.utc(2030),
              ),
            );

        await repository.logout();

        expect(await tokenStore.read(), isNull);
        expect(await database.select(database.households).get(), hasLength(1));
      },
    );

    test(
      'failed vault cleanup blocks restore and retries on next startup',
      () async {
        final transport = _AuthApiTransport();
        final repository = _repository(database, tokenStore, transport);
        await repository.login(email: 'ana@example.com', password: 'secret');
        tokenStore.clearFailuresRemaining = 1;

        await repository.logout();

        expect(await tokenStore.read(), isNotNull);
        expect(
          await (database.select(database.localSettings)..where(
                (row) => row.key.equals(AuthRepository.logoutPendingSettingKey),
              ))
              .getSingleOrNull(),
          isNotNull,
        );

        expect(await repository.readSession(), isNull);
        expect(await tokenStore.read(), isNull);
        expect(
          await (database.select(database.localSettings)..where(
                (row) => row.key.equals(AuthRepository.logoutPendingSettingKey),
              ))
              .getSingleOrNull(),
          isNull,
        );
      },
    );

    test(
      'logout cannot be undone by a refresh that was already in flight',
      () async {
        final releaseRefresh = Completer<void>();
        final transport = _AuthApiTransport(refreshRelease: releaseRefresh);
        final sessionTransport = SessionTransport(
          transport: transport,
          tokenStore: tokenStore,
        );
        final repository = AuthRepository(
          publicTransport: transport,
          sessionTransport: sessionTransport,
          tokenStore: tokenStore,
          database: database,
          platformName: 'windows',
          deviceName: 'Lar Finance no Windows',
        );
        await repository.login(email: 'ana@example.com', password: 'secret');

        final pendingRequest = sessionTransport.getObject('/bootstrap/');
        await _eventually(() => transport.refreshCalls == 1);

        await repository.logout();
        expect(await tokenStore.read(), isNull);

        releaseRefresh.complete();
        await expectLater(pendingRequest, throwsA(isA<RequestFailure>()));
        expect(await tokenStore.read(), isNull);
      },
    );

    test('a stale refresh cannot overwrite a new login after logout', () async {
      final releaseRefresh = Completer<void>();
      final transport = _AuthApiTransport(
        refreshRelease: releaseRefresh,
        rotateSecondLogin: true,
      );
      final sessionTransport = SessionTransport(
        transport: transport,
        tokenStore: tokenStore,
      );
      final repository = AuthRepository(
        publicTransport: transport,
        sessionTransport: sessionTransport,
        tokenStore: tokenStore,
        database: database,
        platformName: 'windows',
        deviceName: 'Lar Finance no Windows',
      );
      await repository.login(email: 'ana@example.com', password: 'secret');

      final pendingRequest = sessionTransport.getObject('/bootstrap/');
      await _eventually(() => transport.refreshCalls == 1);
      await repository.logout();
      await repository.login(email: 'ana@example.com', password: 'new-secret');
      expect((await tokenStore.read())?.accessToken, 'access-new-login');

      releaseRefresh.complete();
      await expectLater(pendingRequest, throwsA(isA<RequestFailure>()));
      expect((await tokenStore.read())?.accessToken, 'access-new-login');
    });
  });
}

AuthRepository _repository(
  AppDatabase database,
  TokenStore tokenStore,
  ApiTransport transport,
) {
  final sessionTransport = SessionTransport(
    transport: transport,
    tokenStore: tokenStore,
  );
  return AuthRepository(
    publicTransport: transport,
    sessionTransport: sessionTransport,
    tokenStore: tokenStore,
    database: database,
    platformName: 'windows',
    deviceName: 'Lar Finance no Windows',
  );
}

const _deviceUuid = '11111111-1111-4111-8111-111111111111';
const _selfUuid = '22222222-2222-4222-8222-222222222222';
const _spouseUuid = '33333333-3333-4333-8333-333333333333';
const _sharedUuid = '44444444-4444-4444-8444-444444444444';

StoredTokens _tokens() => StoredTokens(
  accessToken: 'access-secret',
  accessExpiresAt: DateTime.utc(2030, 1, 1),
  refreshToken: 'refresh-secret',
  refreshExpiresAt: DateTime.utc(2030, 2, 1),
  deviceUuid: _deviceUuid,
);

Map<String, Object?> _tokenPayload() => <String, Object?>{
  'access_token': 'access-secret',
  'access_expires_at': '2030-01-01T00:00:00Z',
  'refresh_token': 'refresh-secret',
  'refresh_expires_at': '2030-02-01T00:00:00Z',
  'device': <String, Object?>{
    'uuid': _deviceUuid,
    'name': 'Lar Finance no Windows',
    'platform': 'windows',
    'default_owner_uuid': _selfUuid,
  },
};

Map<String, Object?> _newLoginTokenPayload() => <String, Object?>{
  'access_token': 'access-new-login',
  'access_expires_at': '2030-01-03T00:00:00Z',
  'refresh_token': 'refresh-new-login',
  'refresh_expires_at': '2030-02-03T00:00:00Z',
  'device': <String, Object?>{
    'uuid': _deviceUuid,
    'name': 'Lar Finance no Windows',
    'platform': 'windows',
    'default_owner_uuid': _selfUuid,
  },
};

Map<String, Object?> _refreshedTokenPayload() => <String, Object?>{
  'access_token': 'access-refreshed-old',
  'access_expires_at': '2030-01-04T00:00:00Z',
  'refresh_token': 'refresh-refreshed-old',
  'refresh_expires_at': '2030-02-04T00:00:00Z',
  'device': <String, Object?>{
    'uuid': _deviceUuid,
    'name': 'Lar Finance no Windows',
    'platform': 'windows',
    'default_owner_uuid': _selfUuid,
  },
};

List<Object?> _ownersPayload() => <Object?>[
  <String, Object?>{'uuid': _selfUuid, 'type': 'self', 'name': 'Ana'},
  <String, Object?>{'uuid': _spouseUuid, 'type': 'spouse', 'name': 'Beto'},
  <String, Object?>{'uuid': _sharedUuid, 'type': 'shared', 'name': 'Casa'},
];

final class _RequestRecord {
  const _RequestRecord({
    required this.path,
    required this.method,
    required this.data,
    required this.bearerToken,
  });

  final String path;
  final String method;
  final Object? data;
  final String? bearerToken;
}

final class _AuthApiTransport implements ApiTransport {
  _AuthApiTransport({
    this.loginStatus = 200,
    this.logoutOffline = false,
    this.ownersOffline = false,
    this.refreshRelease,
    this.rotateSecondLogin = false,
    this.ownersOnlyShared = false,
  });

  final int loginStatus;
  final bool logoutOffline;
  final bool ownersOffline;
  final Completer<void>? refreshRelease;
  final bool rotateSecondLogin;
  final bool ownersOnlyShared;
  final List<_RequestRecord> requests = <_RequestRecord>[];
  int loginCalls = 0;
  int refreshCalls = 0;

  @override
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  }) async {
    requests.add(
      _RequestRecord(
        path: path,
        method: method,
        data: data,
        bearerToken: bearerToken,
      ),
    );
    if (path == '/auth/login/') {
      loginCalls++;
      return ApiResponse(
        statusCode: loginStatus,
        data: rotateSecondLogin && loginCalls > 1
            ? _newLoginTokenPayload()
            : _tokenPayload(),
      );
    }
    if (path == '/auth/refresh/') {
      refreshCalls++;
      await refreshRelease?.future;
      return ApiResponse(statusCode: 200, data: _refreshedTokenPayload());
    }
    if (path == '/bootstrap/') {
      if (bearerToken == 'access-secret') {
        return const ApiResponse(statusCode: 401, data: <String, Object?>{});
      }
      return const ApiResponse(
        statusCode: 200,
        data: <String, Object?>{'status': 'ok'},
      );
    }
    if (path == '/owners/') {
      if (ownersOffline) {
        throw const OfflineFailure();
      }
      return ApiResponse(
        statusCode: 200,
        data: ownersOnlyShared
            ? <Object?>[
                <String, Object?>{
                  'uuid': _sharedUuid,
                  'type': 'shared',
                  'name': 'Casa',
                },
              ]
            : _ownersPayload(),
      );
    }
    if (path == '/devices/current/') {
      return ApiResponse(
        statusCode: 200,
        data: <String, Object?>{
          'uuid': _deviceUuid,
          'name': 'Lar Finance no Windows',
          'platform': 'windows',
          'default_owner_uuid': _spouseUuid,
          'last_seen_at': '2030-01-01T00:00:00Z',
          'created_at': '2030-01-01T00:00:00Z',
          'revoked_at': null,
        },
      );
    }
    if (path == '/auth/logout/' && logoutOffline) {
      throw const OfflineFailure();
    }
    if (path == '/auth/logout/') {
      return const ApiResponse(statusCode: 204, data: null);
    }
    throw StateError('Unexpected fake request.');
  }
}

final class _FakeTokenStore implements TokenStore {
  StoredTokens? value;
  int clearFailuresRemaining = 0;

  @override
  Future<void> clear() async {
    if (clearFailuresRemaining > 0) {
      clearFailuresRemaining--;
      throw StateError('synthetic vault failure');
    }
    value = null;
  }

  @override
  Future<StoredTokens?> read() async => value;

  @override
  Future<void> write(StoredTokens tokens) async => value = tokens;
}

Future<void> _eventually(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}
