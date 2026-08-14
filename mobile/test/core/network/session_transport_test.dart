import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/network/api_error.dart';
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/core/network/session_transport.dart';
import 'package:lar_finance/features/auth/domain/session.dart';

void main() {
  group('SessionTransport', () {
    test(
      'coordinates one refresh for two simultaneous 401 responses',
      () async {
        final releaseRefresh = Completer<void>();
        final fake = _FakeApiTransport((request) async {
          if (request.path == '/auth/refresh/') {
            await releaseRefresh.future;
            return ApiResponse(statusCode: 200, data: _tokenPayload());
          }
          if (request.bearerToken == 'access-old') {
            return const ApiResponse(
              statusCode: 401,
              data: <String, Object?>{},
            );
          }
          return ApiResponse(
            statusCode: 200,
            data: <String, Object?>{'path': request.path},
          );
        });
        final store = _FakeTokenStore(_tokens());
        final client = SessionTransport(transport: fake, tokenStore: store);

        final responses = Future.wait([
          client.getObject('/bootstrap/'),
          client.getObject('/devices/current/'),
        ]);
        await _eventually(() => fake.refreshCalls == 1);
        releaseRefresh.complete();

        expect(await responses, hasLength(2));
        expect(fake.refreshCalls, 1);
        expect(fake.retriedRequests, 2);
        final refresh = fake.requests.singleWhere(
          (request) => request.path == '/auth/refresh/',
        );
        expect(refresh.method, 'POST');
        expect(refresh.bearerToken, isNull);
        expect(refresh.data, <String, Object?>{'refresh_token': 'refresh-old'});
        expect((await store.read())?.accessToken, 'access-new');
      },
    );

    test('reuses a completed refresh for a delayed old-token 401', () async {
      final secondInitialRequestStarted = Completer<void>();
      final releaseSecond401 = Completer<void>();
      final fake = _FakeApiTransport((request) async {
        if (request.path == '/auth/refresh/') {
          return ApiResponse(statusCode: 200, data: _tokenPayload());
        }
        if (request.path == '/second/' && request.bearerToken == 'access-old') {
          secondInitialRequestStarted.complete();
          await releaseSecond401.future;
          return const ApiResponse(statusCode: 401, data: <String, Object?>{});
        }
        if (request.bearerToken == 'access-old') {
          return const ApiResponse(statusCode: 401, data: <String, Object?>{});
        }
        return ApiResponse(
          statusCode: 200,
          data: <String, Object?>{'path': request.path},
        );
      });
      final store = _FakeTokenStore(_tokens());
      final client = SessionTransport(transport: fake, tokenStore: store);

      final delayed = client.getObject('/second/');
      await secondInitialRequestStarted.future;
      final first = client.getObject('/first/');
      await _eventually(() => fake.refreshCalls == 1);
      expect(await first, <String, Object?>{'path': '/first/'});

      releaseSecond401.complete();
      expect(await delayed, <String, Object?>{'path': '/second/'});
      expect(fake.refreshCalls, 1);
    });

    test(
      'starts a new-generation refresh when access tokens are identical',
      () async {
        final oldRefreshStarted = Completer<void>();
        final releaseOldRefresh = Completer<void>();
        addTearDown(() {
          if (!releaseOldRefresh.isCompleted) releaseOldRefresh.complete();
        });
        var newRefreshCalls = 0;
        final fake = _FakeApiTransport((request) async {
          if (request.path == '/auth/refresh/') {
            final refreshToken =
                (request.data! as Map<Object?, Object?>)['refresh_token'];
            if (refreshToken == 'refresh-old-generation') {
              oldRefreshStarted.complete();
              await releaseOldRefresh.future;
              return ApiResponse(
                statusCode: 200,
                data: _sessionPayload(
                  accessToken: 'access-refreshed-old',
                  refreshToken: 'refresh-refreshed-old',
                ),
              );
            }
            if (refreshToken == 'refresh-new-generation') {
              newRefreshCalls++;
              return ApiResponse(
                statusCode: 200,
                data: _sessionPayload(
                  accessToken: 'access-refreshed-new',
                  refreshToken: 'refresh-refreshed-new',
                ),
              );
            }
          }
          if (request.bearerToken == 'access-shared') {
            return const ApiResponse(
              statusCode: 401,
              data: <String, Object?>{},
            );
          }
          return ApiResponse(
            statusCode: 200,
            data: <String, Object?>{'path': request.path},
          );
        });
        final store = _FakeTokenStore(
          _tokensForGeneration(refreshToken: 'refresh-old-generation'),
        );
        final authority = SessionAuthority.forStore(store);
        final client = SessionTransport(
          transport: fake,
          tokenStore: store,
          sessionAuthority: authority,
        );

        final oldRequest = client.getObject('/old-generation/');
        await oldRefreshStarted.future;
        await authority.clear();
        await authority.write(
          _tokensForGeneration(refreshToken: 'refresh-new-generation'),
        );

        final newRequest = client.getObject('/new-generation/');
        await _eventually(() => newRefreshCalls == 1);
        expect(await newRequest, <String, Object?>{'path': '/new-generation/'});

        releaseOldRefresh.complete();
        await expectLater(oldRequest, throwsA(isA<RequestFailure>()));
        expect((await store.read())?.accessToken, 'access-refreshed-new');
      },
    );

    test('refresh 401 clears tokens and expires the session', () async {
      final fake = _FakeApiTransport(
        (request) async => ApiResponse(
          statusCode: request.path == '/auth/refresh/' ? 401 : 401,
          data: const <String, Object?>{},
        ),
      );
      final store = _FakeTokenStore(_tokens());
      final client = SessionTransport(transport: fake, tokenStore: store);

      await expectLater(
        client.getObject('/bootstrap/'),
        throwsA(isA<SessionExpired>()),
      );

      expect(await store.read(), isNull);
      expect(fake.refreshCalls, 1);
    });

    test('a retried 401 is not refreshed a second time', () async {
      final fake = _FakeApiTransport((request) async {
        if (request.path == '/auth/refresh/') {
          return ApiResponse(statusCode: 200, data: _tokenPayload());
        }
        return const ApiResponse(statusCode: 401, data: <String, Object?>{});
      });
      final store = _FakeTokenStore(_tokens());
      final client = SessionTransport(transport: fake, tokenStore: store);

      await expectLater(
        client.getObject('/bootstrap/'),
        throwsA(isA<SessionExpired>()),
      );

      expect(fake.refreshCalls, 1);
      expect(await store.read(), isNull);
    });

    test(
      'refresh timeout preserves tokens and raises OfflineFailure',
      () async {
        final fake = _FakeApiTransport((request) async {
          if (request.path == '/auth/refresh/') {
            throw const OfflineFailure();
          }
          return const ApiResponse(statusCode: 401, data: <String, Object?>{});
        });
        final original = _tokens();
        final store = _FakeTokenStore(original);
        final client = SessionTransport(transport: fake, tokenStore: store);

        await expectLater(
          client.getObject('/bootstrap/'),
          throwsA(isA<OfflineFailure>()),
        );

        expect(await store.read(), same(original));
      },
    );

    for (final status in <int>[429, 500]) {
      test(
        'refresh $status preserves tokens and remains recoverable',
        () async {
          final fake = _FakeApiTransport((request) async {
            if (request.path == '/auth/refresh/') {
              return ApiResponse(
                statusCode: status,
                data: const <String, Object?>{},
              );
            }
            return const ApiResponse(
              statusCode: 401,
              data: <String, Object?>{},
            );
          });
          final original = _tokens();
          final store = _FakeTokenStore(original);
          final client = SessionTransport(transport: fake, tokenStore: store);

          await expectLater(
            client.getObject('/bootstrap/'),
            throwsA(isA<RequestFailure>()),
          );

          expect(await store.read(), same(original));
        },
      );
    }

    test('restoring an expired refresh clears the local session', () async {
      final now = DateTime.utc(2030, 1, 10);
      final store = _FakeTokenStore(
        _tokensWith(
          accessExpiresAt: now.add(const Duration(days: 1)),
          refreshExpiresAt: now.subtract(const Duration(seconds: 1)),
        ),
      );
      final client = SessionTransport(
        transport: _FakeApiTransport((_) async => throw StateError('network')),
        tokenStore: store,
        now: () => now,
      );

      expect(await client.restoreSession(), isNull);
      expect(await store.read(), isNull);
    });

    test(
      'restoring an expired access refreshes before returning a session',
      () async {
        final now = DateTime.utc(2030, 1, 10);
        final fake = _FakeApiTransport((request) async {
          if (request.path == '/auth/refresh/') {
            return ApiResponse(
              statusCode: 200,
              data: _tokenPayloadWithExpiries(
                accessExpiresAt: now.add(const Duration(days: 1)),
                refreshExpiresAt: now.add(const Duration(days: 30)),
              ),
            );
          }
          throw StateError('Unexpected request.');
        });
        final store = _FakeTokenStore(
          _tokensWith(
            accessExpiresAt: now.subtract(const Duration(seconds: 1)),
            refreshExpiresAt: now.add(const Duration(days: 1)),
          ),
        );
        final client = SessionTransport(
          transport: fake,
          tokenStore: store,
          now: () => now,
        );

        final restored = await client.restoreSession();

        expect(restored?.accessToken, 'access-new');
        expect(restored?.accessExpiresAt.isAfter(now), isTrue);
        expect(fake.refreshCalls, 1);
        expect((await store.read())?.accessToken, 'access-new');
      },
    );

    test(
      'expired access stays signed out safely when refresh is offline',
      () async {
        final now = DateTime.utc(2030, 1, 10);
        final original = _tokensWith(
          accessExpiresAt: now.subtract(const Duration(seconds: 1)),
          refreshExpiresAt: now.add(const Duration(days: 1)),
        );
        final store = _FakeTokenStore(original);
        final client = SessionTransport(
          transport: _FakeApiTransport((request) async {
            if (request.path == '/auth/refresh/') throw const OfflineFailure();
            throw StateError('Unexpected request.');
          }),
          tokenStore: store,
          now: () => now,
        );

        await expectLater(
          client.restoreSession(),
          throwsA(isA<OfflineFailure>()),
        );
        expect(await store.read(), same(original));
      },
    );

    test('retries refresh after a transient offline failure', () async {
      var offline = true;
      final fake = _FakeApiTransport((request) async {
        if (request.path == '/auth/refresh/') {
          if (offline) {
            offline = false;
            throw const OfflineFailure();
          }
          return ApiResponse(statusCode: 200, data: _tokenPayload());
        }
        if (request.bearerToken == 'access-old') {
          return const ApiResponse(statusCode: 401, data: <String, Object?>{});
        }
        return const ApiResponse(
          statusCode: 200,
          data: <String, Object?>{'status': 'ok'},
        );
      });
      final store = _FakeTokenStore(_tokens());
      final client = SessionTransport(transport: fake, tokenStore: store);

      await expectLater(
        client.getObject('/bootstrap/'),
        throwsA(isA<OfflineFailure>()),
      );

      expect(await client.getObject('/bootstrap/'), <String, Object?>{
        'status': 'ok',
      });
      expect(fake.refreshCalls, 2);
      expect((await store.read())?.accessToken, 'access-new');
    });

    test(
      'tokens never appear in models, failures, or session events',
      () async {
        final events = <String>[];
        final fake = _FakeApiTransport((request) async {
          if (request.path == '/auth/refresh/') {
            return const ApiResponse(
              statusCode: 401,
              data: <String, Object?>{},
            );
          }
          return const ApiResponse(statusCode: 401, data: <String, Object?>{});
        });
        final original = _tokens();
        final store = _FakeTokenStore(original);
        final client = SessionTransport(
          transport: fake,
          tokenStore: store,
          onEvent: events.add,
        );

        Object? failure;
        try {
          await client.getObject('/bootstrap/');
        } catch (error) {
          failure = error;
        }
        final observable =
            '${original.toString()} ${failure.toString()} ${events.join(' ')}';

        expect(observable, isNot(contains('access-old')));
        expect(observable, isNot(contains('refresh-old')));
      },
    );
  });
}

StoredTokens _tokens() => StoredTokens(
  accessToken: 'access-old',
  accessExpiresAt: DateTime.utc(2030, 1, 1),
  refreshToken: 'refresh-old',
  refreshExpiresAt: DateTime.utc(2030, 2, 1),
  deviceUuid: '11111111-1111-4111-8111-111111111111',
);

StoredTokens _tokensWith({
  required DateTime accessExpiresAt,
  required DateTime refreshExpiresAt,
}) => StoredTokens(
  accessToken: 'access-old',
  accessExpiresAt: accessExpiresAt,
  refreshToken: 'refresh-old',
  refreshExpiresAt: refreshExpiresAt,
  deviceUuid: '11111111-1111-4111-8111-111111111111',
);

StoredTokens _tokensForGeneration({required String refreshToken}) =>
    StoredTokens(
      accessToken: 'access-shared',
      accessExpiresAt: DateTime.utc(2030, 1, 1),
      refreshToken: refreshToken,
      refreshExpiresAt: DateTime.utc(2030, 2, 1),
      deviceUuid: '11111111-1111-4111-8111-111111111111',
    );

Map<String, Object?> _tokenPayload() => <String, Object?>{
  'access_token': 'access-new',
  'access_expires_at': '2030-01-02T00:00:00Z',
  'refresh_token': 'refresh-new',
  'refresh_expires_at': '2030-02-02T00:00:00Z',
  'device': <String, Object?>{
    'uuid': '11111111-1111-4111-8111-111111111111',
    'name': 'Lar Finance no Windows',
    'platform': 'windows',
    'default_owner_uuid': '22222222-2222-4222-8222-222222222222',
  },
};

Map<String, Object?> _tokenPayloadWithExpiries({
  required DateTime accessExpiresAt,
  required DateTime refreshExpiresAt,
}) => <String, Object?>{
  'access_token': 'access-new',
  'access_expires_at': accessExpiresAt.toIso8601String(),
  'refresh_token': 'refresh-new',
  'refresh_expires_at': refreshExpiresAt.toIso8601String(),
  'device': <String, Object?>{
    'uuid': '11111111-1111-4111-8111-111111111111',
    'name': 'Lar Finance no Windows',
    'platform': 'windows',
    'default_owner_uuid': '22222222-2222-4222-8222-222222222222',
  },
};

Map<String, Object?> _sessionPayload({
  required String accessToken,
  required String refreshToken,
}) => <String, Object?>{
  'access_token': accessToken,
  'access_expires_at': '2030-01-02T00:00:00Z',
  'refresh_token': refreshToken,
  'refresh_expires_at': '2030-02-02T00:00:00Z',
  'device': <String, Object?>{
    'uuid': '11111111-1111-4111-8111-111111111111',
    'name': 'Lar Finance no Windows',
    'platform': 'windows',
    'default_owner_uuid': '22222222-2222-4222-8222-222222222222',
  },
};

Future<void> _eventually(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
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

final class _RequestRecord {
  const _RequestRecord({
    required this.method,
    required this.path,
    required this.data,
    required this.bearerToken,
  });

  final String method;
  final String path;
  final Object? data;
  final String? bearerToken;
}

final class _FakeApiTransport implements ApiTransport {
  _FakeApiTransport(this.handler);

  final Future<ApiResponse> Function(_RequestRecord request) handler;
  final List<_RequestRecord> requests = <_RequestRecord>[];
  int refreshCalls = 0;
  int retriedRequests = 0;

  @override
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  }) {
    if (path == '/auth/refresh/') {
      refreshCalls++;
    } else if (bearerToken == 'access-new') {
      retriedRequests++;
    }
    final record = _RequestRecord(
      method: method,
      path: path,
      data: data,
      bearerToken: bearerToken,
    );
    requests.add(record);
    return handler(record);
  }
}
