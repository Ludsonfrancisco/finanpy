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
