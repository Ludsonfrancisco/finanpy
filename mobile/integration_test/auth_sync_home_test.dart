import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/app/app_config.dart';
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/core/network/session_transport.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/core/storage/local_ledger.dart';
import 'package:lar_finance/core/sync/sync_api.dart';
import 'package:lar_finance/core/sync/sync_coordinator.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/features/auth/application/auth_controller.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/domain/session.dart';
import 'package:lar_finance/features/home/data/home_repository.dart';
import 'package:lar_finance/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'clean install survives offline relaunch, pulls a delta, refreshes once, '
    'and logs out without pushing or deleting cache',
    (tester) async {
      await initializeDateFormatting('pt_BR');
      final directory = await Directory.systemTemp.createTemp(
        'lar-finance-task9-',
      );
      final databaseFile = File('${directory.path}/ledger.sqlite');
      final server = _SyntheticApiServer();
      final tokenStore = _MemoryTokenStore();
      final clock = _MutableClock(DateTime.utc(2026, 8, 14, 12));
      late _TestRuntime runtime;

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await runtime.close();
        await server.stop();
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      await server.start();
      runtime = await _TestRuntime.create(
        apiBaseUrl: server.baseUrl,
        databaseFile: databaseFile,
        tokenStore: tokenStore,
        clock: clock,
      );
      expect(
        await runtime.database.select(runtime.database.households).get(),
        isEmpty,
      );

      await tester.pumpWidget(runtime.app);
      await _pumpUntil(tester, find.text('Entre no Lar Finance'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        _SyntheticApiServer.email,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        _SyntheticApiServer.password,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await _pumpUntil(tester, find.text('Alex'));

      await tester.tap(find.text('Alex'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await _pumpUntil(tester, find.text('Saldo consolidado'));
      expect(find.text('Despesa planejada sintética'), findsOneWidget);
      expect(server.loginCalls, 1);
      expect(server.ownerPatchCalls, 1);
      expect(server.bootstrapCalls, 1);
      expect(server.lastSelectedOwnerUuid, _selfOwnerUuid);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await runtime.close();
      await server.stop();
      clock.value = DateTime.utc(2026, 8, 14, 12, 10);

      runtime = await _TestRuntime.create(
        apiBaseUrl: server.baseUrl,
        databaseFile: databaseFile,
        tokenStore: tokenStore,
        clock: clock,
      );
      await tester.pumpWidget(runtime.app);
      await _pumpUntil(tester, find.text('Saldo consolidado'));
      expect(find.text('Despesa planejada sintética'), findsOneWidget);
      await _eventually(
        () => runtime.coordinator.state.phase.name == 'offline',
      );

      server.serveDelta = true;
      await server.start(port: server.port);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpUntil(tester, find.text('Manutenção sintética'));
      expect(server.changeCalls, greaterThanOrEqualTo(1));

      server.expireAccessOnNextChanges = true;
      final refreshResult = await runtime.coordinator.synchronize();
      expect(refreshResult, SyncResult.current);
      expect(server.refreshCalls, 1);

      await tester.tap(find.text('Mais'));
      await _pumpUntil(tester, find.text('Dispositivo'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Sair'));
      await _pumpUntil(tester, find.text('Entre no Lar Finance'));
      expect(await tokenStore.read(), isNull);
      expect(
        await runtime.database.select(runtime.database.transactions).get(),
        hasLength(4),
      );
      expect(server.logoutCalls, 1);
      expect(
        server.pushCalls,
        0,
        reason: 'Sprint 4 is read-only and must never call /sync/push/.',
      );
      expect(
        server.requests.every(
          (request) => !request.body.contains('production'),
        ),
        isTrue,
        reason: 'The integration journey must contain only synthetic data.',
      );
    },
  );
}

final class _TestRuntime {
  _TestRuntime._({
    required this.database,
    required this.authController,
    required this.coordinator,
    required this.app,
  });

  static Future<_TestRuntime> create({
    required String apiBaseUrl,
    required File databaseFile,
    required TokenStore tokenStore,
    required _MutableClock clock,
  }) async {
    final database = AppDatabase(NativeDatabase(databaseFile));
    final authority = SessionAuthority.forStore(tokenStore);
    final transport = DioTransport(baseUrl: apiBaseUrl);
    final sessionTransport = SessionTransport(
      transport: transport,
      tokenStore: tokenStore,
      sessionAuthority: authority,
      now: clock.call,
    );
    final repository = AuthRepository(
      publicTransport: transport,
      sessionTransport: sessionTransport,
      tokenStore: tokenStore,
      sessionAuthority: authority,
      database: database,
      platformName: 'windows',
      deviceName: 'Lar Finance Windows sintético',
    );
    final authController = AuthController(
      repository,
      sessionAuthority: authority,
    );
    await authController.initialize();
    final coordinator = LedgerSyncCoordinator(
      api: DjangoSyncApi(sessionTransport),
      ledger: DriftLocalLedger(database),
      sessionAuthority: authority,
      now: clock.call,
    );
    final app = MyApp(
      appConfig: AppConfig(apiBaseUrl: apiBaseUrl),
      authController: authController,
      syncCoordinator: coordinator,
      homeRepository: DriftHomeRepository(database),
    );
    return _TestRuntime._(
      database: database,
      authController: authController,
      coordinator: coordinator,
      app: app,
    );
  }

  final AppDatabase database;
  final AuthController authController;
  final LedgerSyncCoordinator coordinator;
  final Widget app;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    authController.dispose();
    await database.close();
  }
}

final class _MutableClock {
  _MutableClock(this.value);

  DateTime value;

  DateTime call() => value;
}

final class _MemoryTokenStore implements TokenStore {
  StoredTokens? _tokens;

  @override
  Future<void> clear() async => _tokens = null;

  @override
  Future<StoredTokens?> read() async => _tokens;

  @override
  Future<void> write(StoredTokens tokens) async => _tokens = tokens;
}

final class _RecordedRequest {
  const _RecordedRequest({required this.path, required this.body});

  final String path;
  final String body;
}

final class _SyntheticApiServer {
  static const email = 'family@synthetic.example';
  static const password = 'synthetic-test-password';

  HttpServer? _server;
  int? _boundPort;
  String _accessToken = 'synthetic-access-1';
  String _refreshToken = 'synthetic-refresh-1';
  int _tokenGeneration = 1;

  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  int loginCalls = 0;
  int ownerPatchCalls = 0;
  int bootstrapCalls = 0;
  int changeCalls = 0;
  int refreshCalls = 0;
  int logoutCalls = 0;
  int pushCalls = 0;
  String? lastSelectedOwnerUuid;
  bool serveDelta = false;
  bool expireAccessOnNextChanges = false;

  int get port => _boundPort!;
  String get baseUrl => 'http://127.0.0.1:$port/api/v1';

  Future<void> start({int? port}) async {
    if (_server != null) return;
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port ?? 0,
      shared: true,
    );
    _boundPort = _server!.port;
    unawaited(_serve(_server!));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      await _handle(request);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    requests.add(_RecordedRequest(path: request.uri.path, body: body));
    final path = request.uri.path;
    if (path == '/api/v1/sync/push/') {
      pushCalls++;
      await _json(
        request.response,
        HttpStatus.methodNotAllowed,
        <String, Object?>{
          'error': <String, Object?>{'code': 'read_only_test'},
        },
      );
      return;
    }
    if (path == '/api/v1/auth/login/' && request.method == 'POST') {
      loginCalls++;
      final json = _decodeBody(body);
      if (json['email'] != email || json['password'] != password) {
        await _json(
          request.response,
          HttpStatus.unauthorized,
          <String, Object?>{},
        );
        return;
      }
      await _json(request.response, HttpStatus.ok, _sessionPayload());
      return;
    }
    if (path == '/api/v1/auth/refresh/' && request.method == 'POST') {
      refreshCalls++;
      final json = _decodeBody(body);
      if (json['refresh_token'] != _refreshToken) {
        await _json(
          request.response,
          HttpStatus.unauthorized,
          <String, Object?>{},
        );
        return;
      }
      _tokenGeneration++;
      _accessToken = 'synthetic-access-$_tokenGeneration';
      _refreshToken = 'synthetic-refresh-$_tokenGeneration';
      await _json(request.response, HttpStatus.ok, _sessionPayload());
      return;
    }
    if (!_authorized(request)) {
      await _json(
        request.response,
        HttpStatus.unauthorized,
        <String, Object?>{},
      );
      return;
    }
    if (path == '/api/v1/owners/' && request.method == 'GET') {
      await _json(request.response, HttpStatus.ok, _owners);
      return;
    }
    if (path == '/api/v1/devices/current/' && request.method == 'PATCH') {
      ownerPatchCalls++;
      final json = _decodeBody(body);
      lastSelectedOwnerUuid = json['default_owner_uuid'] as String?;
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'uuid': _deviceUuid,
        'name': 'Lar Finance Windows sintético',
        'platform': 'windows',
        'default_owner_uuid': lastSelectedOwnerUuid,
      });
      return;
    }
    if (path == '/api/v1/bootstrap/' && request.method == 'GET') {
      bootstrapCalls++;
      await _json(request.response, HttpStatus.ok, _bootstrapPayload);
      return;
    }
    if (path == '/api/v1/sync/changes/' && request.method == 'GET') {
      changeCalls++;
      if (expireAccessOnNextChanges) {
        expireAccessOnNextChanges = false;
        await _json(
          request.response,
          HttpStatus.unauthorized,
          <String, Object?>{},
        );
        return;
      }
      final cursor = request.uri.queryParameters['cursor'];
      if (serveDelta && cursor == _bootstrapCursor) {
        serveDelta = false;
        await _json(request.response, HttpStatus.ok, _deltaPayload);
      } else {
        await _json(request.response, HttpStatus.ok, <String, Object?>{
          'changes': <Object?>[],
          'cursor': cursor ?? _deltaCursor,
        });
      }
      return;
    }
    if (path == '/api/v1/auth/logout/' && request.method == 'POST') {
      logoutCalls++;
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    await _json(request.response, HttpStatus.notFound, <String, Object?>{});
  }

  bool _authorized(HttpRequest request) =>
      request.headers.value(HttpHeaders.authorizationHeader) ==
      'Bearer $_accessToken';

  Map<String, Object?> _sessionPayload() => <String, Object?>{
    'access_token': _accessToken,
    'access_expires_at': '2026-08-14T14:00:00Z',
    'refresh_token': _refreshToken,
    'refresh_expires_at': '2026-09-14T12:00:00Z',
    'device': <String, Object?>{
      'uuid': _deviceUuid,
      'name': 'Lar Finance Windows sintético',
      'platform': 'windows',
      'default_owner_uuid': _selfOwnerUuid,
    },
  };

  Map<String, Object?> _decodeBody(String body) =>
      (jsonDecode(body) as Map).cast<String, Object?>();

  Future<void> _json(
    HttpResponse response,
    int statusCode,
    Object payload,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 200,
}) async {
  for (var pump = 0; pump < maxPumps && finder.evaluate().isEmpty; pump++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (finder.evaluate().isEmpty) {
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList(growable: false);
    debugPrint('Task 9 integration timeout; visible text: $visibleText');
    final pendingException = tester.takeException();
    if (pendingException != null) {
      debugPrint('Task 9 integration pending exception: $pendingException');
    }
  }
  expect(finder, findsWidgets);
}

Future<void> _eventually(bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

const _deviceUuid = '10000000-0000-4000-8000-000000000001';
const _householdUuid = '20000000-0000-4000-8000-000000000001';
const _selfOwnerUuid = '30000000-0000-4000-8000-000000000001';
const _spouseOwnerUuid = '30000000-0000-4000-8000-000000000002';
const _sharedOwnerUuid = '30000000-0000-4000-8000-000000000003';
const _accountUuid = '40000000-0000-4000-8000-000000000001';
const _categoryUuid = '50000000-0000-4000-8000-000000000001';
const _bootstrapCursor = 'synthetic-bootstrap-cursor';
const _deltaCursor = 'synthetic-delta-cursor';

const _owners = <Object?>[
  <String, Object?>{'uuid': _selfOwnerUuid, 'type': 'self', 'name': 'Alex'},
  <String, Object?>{'uuid': _spouseOwnerUuid, 'type': 'spouse', 'name': 'Rui'},
  <String, Object?>{'uuid': _sharedOwnerUuid, 'type': 'shared', 'name': 'Casa'},
];

const _bootstrapPayload = <String, Object?>{
  'household': <String, Object?>{
    'uuid': _householdUuid,
    'name': 'Casa Sintética',
    'updated_at': '2026-08-14T12:00:00Z',
  },
  'owners': _owners,
  'accounts': <Object?>[
    <String, Object?>{
      'uuid': _accountUuid,
      'household_uuid': _householdUuid,
      'financial_owner_uuid': _selfOwnerUuid,
      'name': 'Conta Sintética',
      'type': 'checking',
      'initial_balance': '1250.00',
      'currency': 'BRL',
      'version': 1,
      'created_at': '2026-08-01T09:00:00Z',
      'updated_at': '2026-08-14T12:00:00Z',
    },
  ],
  'categories': <Object?>[
    <String, Object?>{
      'uuid': _categoryUuid,
      'household_uuid': _householdUuid,
      'name': 'Moradia sintética',
      'type': 'expense',
      'color': '#8B6F47',
      'icon': 'home',
      'version': 1,
      'created_at': '2026-08-01T09:00:00Z',
      'updated_at': '2026-08-14T12:00:00Z',
    },
  ],
  'transactions': <Object?>[
    <String, Object?>{
      'uuid': '60000000-0000-4000-8000-000000000001',
      'household_uuid': _householdUuid,
      'financial_owner_uuid': _selfOwnerUuid,
      'account_uuid': _accountUuid,
      'category_uuid': _categoryUuid,
      'description': 'Despesa planejada sintética',
      'amount': '75.00',
      'date': '2026-08-14',
      'type': 'expense',
      'version': 1,
      'created_at': '2026-08-14T10:00:00Z',
      'updated_at': '2026-08-14T10:00:00Z',
    },
    <String, Object?>{
      'uuid': '60000000-0000-4000-8000-000000000002',
      'household_uuid': _householdUuid,
      'financial_owner_uuid': _spouseOwnerUuid,
      'account_uuid': _accountUuid,
      'category_uuid': _categoryUuid,
      'description': 'Compra doméstica sintética',
      'amount': '20.00',
      'date': '2026-08-13',
      'type': 'expense',
      'version': 1,
      'created_at': '2026-08-13T10:00:00Z',
      'updated_at': '2026-08-13T10:00:00Z',
    },
    <String, Object?>{
      'uuid': '60000000-0000-4000-8000-000000000003',
      'household_uuid': _householdUuid,
      'financial_owner_uuid': _sharedOwnerUuid,
      'account_uuid': _accountUuid,
      'category_uuid': _categoryUuid,
      'description': 'Reserva sintética',
      'amount': '10.00',
      'date': '2026-08-12',
      'type': 'expense',
      'version': 1,
      'created_at': '2026-08-12T10:00:00Z',
      'updated_at': '2026-08-12T10:00:00Z',
    },
  ],
  'summary': <String, Object?>{
    'total_balance': '1145.00',
    'monthly_income': '0.00',
    'monthly_expenses': '105.00',
  },
  'cursor': _bootstrapCursor,
};

const _deltaPayload = <String, Object?>{
  'changes': <Object?>[
    <String, Object?>{
      'entity_type': 'transaction',
      'entity_uuid': '60000000-0000-4000-8000-000000000004',
      'entity_version': 1,
      'operation': 'create',
      'payload': <String, Object?>{
        'uuid': '60000000-0000-4000-8000-000000000004',
        'household_uuid': _householdUuid,
        'financial_owner_uuid': _selfOwnerUuid,
        'account_uuid': _accountUuid,
        'category_uuid': _categoryUuid,
        'description': 'Manutenção sintética',
        'amount': '15.00',
        'date': '2026-08-14',
        'type': 'expense',
        'version': 1,
        'created_at': '2026-08-14T12:05:00Z',
        'updated_at': '2026-08-14T12:05:00Z',
      },
    },
  ],
  'cursor': _deltaCursor,
};
