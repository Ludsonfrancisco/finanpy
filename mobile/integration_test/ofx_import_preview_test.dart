import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:lar_finance/features/auth/application/auth_controller.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/domain/session.dart';
import 'package:lar_finance/features/home/data/home_repository.dart';
import 'package:lar_finance/features/imports/data/import_repository.dart';
import 'package:lar_finance/features/imports/data/ofx_file_picker.dart';
import 'package:lar_finance/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a device previews a paged OFX, confirms it, pulls the ledger, cancels a '
    'second file and never pushes',
    (tester) async {
      await initializeDateFormatting('pt_BR');
      final directory = await Directory.systemTemp.createTemp(
        'lar-finance-import-',
      );
      final databaseFile = File('${directory.path}/ledger.sqlite');
      final server = _ImportApiServer();
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
      );

      await tester.pumpWidget(runtime.app);
      await _pumpUntil(tester, find.text('Entre no Lar Finance'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        _ImportApiServer.email,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        _ImportApiServer.password,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await _pumpUntil(tester, find.text('Alex'));
      await tester.tap(find.text('Alex'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await _pumpUntil(tester, find.text('Saldo consolidado'));

      await tester.tap(find.byIcon(Icons.more_horiz));
      await _pumpUntil(tester, find.text('Importar OFX'));
      await tester.tap(find.text('Importar OFX'));
      await _pumpUntil(tester, find.text('Importação OFX'));
      await _settle(tester);

      // The upload refuses the first access token once, so the flow proves a
      // single coordinated refresh before the preview arrives.
      server.expireAccessOnNextPreview = true;
      await tester.tap(find.text('Selecionar arquivo OFX'));
      await _pumpUntil(tester, find.text('Mercado sintético 3'));

      expect(server.refreshCalls, 1);
      expect(server.previewCalls, 1);
      expect(server.pageCursors, <String?>['2']);
      expect(find.text('Mercado sintético 1'), findsOneWidget);
      expect(find.text('Nubank — Conta'), findsOneWidget);
      expect(find.text('Confira antes de confirmar'), findsOneWidget);

      final upload = server.requests.firstWhere(
        (request) => request.path == '/api/v1/imports/ofx/preview/',
      );
      expect(upload.body, contains('filename="statement.ofx"'));
      expect(upload.body, isNot(contains('Downloads')));
      expect(upload.body, isNot(contains('Nubank_')));

      final pullsBeforeConfirm = server.changeCalls + server.bootstrapCalls;
      await tester.tap(find.text('Confirmar importação'));
      await _pumpUntil(tester, find.text('Importação concluída'));
      expect(server.confirmCalls, 1);
      await _eventually(
        () => server.changeCalls + server.bootstrapCalls > pullsBeforeConfirm,
        reason: server.requests.map((request) => request.path).join(' | '),
      );

      await tester.tap(find.byIcon(Icons.home_outlined));
      await _pumpUntil(tester, find.text('Saldo consolidado'));
      expect(find.text('Mercado sintético 1'), findsWidgets);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await _pumpUntil(tester, find.text('Importar OFX'));
      await tester.tap(find.text('Importar OFX'));
      await _pumpUntil(tester, find.text('Importação OFX'));
      await _settle(tester);
      // The receipt of the confirmed batch survives until a new choice.
      final newSelection = find.text('Importar outro arquivo');
      await tester.tap(
        newSelection.evaluate().isEmpty
            ? find.text('Selecionar arquivo OFX')
            : newSelection,
      );
      await _pumpUntil(tester, find.text('Confira antes de confirmar'));
      await tester.tap(find.text('Cancelar'));
      await _pumpUntil(tester, find.text('Nenhum arquivo selecionado'));

      expect(server.cancelCalls, 1);
      expect(server.confirmCalls, 1);
      expect(server.pushCalls, 0);
      expect(
        server.requests.every(
          (request) => !request.path.contains('/sync/push/'),
        ),
        isTrue,
      );
    },
  );
}

final class _TestRuntime {
  const _TestRuntime._({
    required this.database,
    required this.authController,
    required this.app,
  });

  static Future<_TestRuntime> create({
    required String apiBaseUrl,
    required File databaseFile,
  }) async {
    final database = AppDatabase(NativeDatabase(databaseFile));
    final tokenStore = _MemoryTokenStore();
    final authority = SessionAuthority.forStore(tokenStore);
    final transport = DioTransport(baseUrl: apiBaseUrl);
    final sessionTransport = SessionTransport(
      transport: transport,
      tokenStore: tokenStore,
      sessionAuthority: authority,
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
    );
    return _TestRuntime._(
      database: database,
      authController: authController,
      app: MyApp(
        appConfig: AppConfig(apiBaseUrl: apiBaseUrl),
        authController: authController,
        syncCoordinator: coordinator,
        homeRepository: DriftHomeRepository(database),
        importRepository: DjangoImportRepository(sessionTransport),
        ofxFilePicker: _SyntheticOfxPicker(),
      ),
    );
  }

  final AppDatabase database;
  final AuthController authController;
  final Widget app;

  Future<void> close() async {
    authController.dispose();
    await database.close();
  }
}

/// Stands in for the native dialog with bytes that never touch the disk.
final class _SyntheticOfxPicker implements OfxFilePicker {
  @override
  Future<SelectedOfx?> pick() async =>
      SelectedOfx(Uint8List.fromList(utf8.encode('OFXHEADER:100\n')));
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

final class _ImportApiServer {
  static const email = 'family@synthetic.example';
  static const password = 'synthetic-test-password';

  HttpServer? _server;
  int? _boundPort;
  String _accessToken = 'synthetic-access-1';
  String _refreshToken = 'synthetic-refresh-1';
  int _tokenGeneration = 1;
  bool _confirmed = false;

  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  final List<String?> pageCursors = <String?>[];
  int refreshCalls = 0;
  int previewCalls = 0;
  int confirmCalls = 0;
  int cancelCalls = 0;
  int changeCalls = 0;
  int bootstrapCalls = 0;
  int pushCalls = 0;
  bool expireAccessOnNextPreview = false;

  String get baseUrl => 'http://127.0.0.1:${_boundPort!}/api/v1';

  Future<void> start() async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
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
    final bytes = await request.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final body = utf8.decode(bytes, allowMalformed: true);
    final path = request.uri.path;
    requests.add(_RecordedRequest(path: path, body: body));

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
      final json = (jsonDecode(body) as Map).cast<String, Object?>();
      if (json['email'] != email || json['password'] != password) {
        await _json(request.response, HttpStatus.unauthorized, _error('auth'));
        return;
      }
      await _json(request.response, HttpStatus.ok, _sessionPayload());
      return;
    }
    if (path == '/api/v1/auth/refresh/' && request.method == 'POST') {
      refreshCalls++;
      _tokenGeneration++;
      _accessToken = 'synthetic-access-$_tokenGeneration';
      _refreshToken = 'synthetic-refresh-$_tokenGeneration';
      await _json(request.response, HttpStatus.ok, _sessionPayload());
      return;
    }
    if (path == '/api/v1/imports/ofx/preview/' && request.method == 'POST') {
      if (expireAccessOnNextPreview) {
        expireAccessOnNextPreview = false;
        await _json(request.response, HttpStatus.unauthorized, _error('auth'));
        return;
      }
      if (!_authorized(request)) {
        await _json(request.response, HttpStatus.unauthorized, _error('auth'));
        return;
      }
      previewCalls++;
      await _json(
        request.response,
        HttpStatus.created,
        _previewPayload(records: _records.take(2), nextCursor: '2'),
      );
      return;
    }
    if (!_authorized(request)) {
      await _json(request.response, HttpStatus.unauthorized, _error('auth'));
      return;
    }
    if (path == '/api/v1/imports/$_batchUuid/' && request.method == 'GET') {
      pageCursors.add(request.uri.queryParameters['after']);
      await _json(
        request.response,
        HttpStatus.ok,
        _previewPayload(records: _records.skip(2)),
      );
      return;
    }
    if (path == '/api/v1/imports/$_batchUuid/confirm/') {
      confirmCalls++;
      _confirmed = true;
      await _json(
        request.response,
        HttpStatus.ok,
        _previewPayload(
          records: _records,
          status: 'completed',
          createdCount: _records.length,
        ),
      );
      return;
    }
    if (path == '/api/v1/imports/$_batchUuid/cancel/') {
      cancelCalls++;
      await _json(
        request.response,
        HttpStatus.ok,
        _previewPayload(records: const <Object?>[], status: 'cancelled'),
      );
      return;
    }
    if (path == '/api/v1/owners/' && request.method == 'GET') {
      await _json(request.response, HttpStatus.ok, _owners);
      return;
    }
    if (path == '/api/v1/devices/current/' && request.method == 'PATCH') {
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'uuid': _deviceUuid,
        'name': 'Lar Finance Windows sintético',
        'platform': 'windows',
        'default_owner_uuid': _selfOwnerUuid,
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
      final cursor = request.uri.queryParameters['cursor'];
      if (_confirmed && cursor == _bootstrapCursor) {
        _confirmed = false;
        await _json(request.response, HttpStatus.ok, _deltaPayload);
        return;
      }
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'changes': <Object?>[],
        'cursor': cursor ?? _bootstrapCursor,
      });
      return;
    }
    await _json(request.response, HttpStatus.notFound, _error('not_found'));
  }

  bool _authorized(HttpRequest request) =>
      request.headers.value(HttpHeaders.authorizationHeader) ==
      'Bearer $_accessToken';

  Map<String, Object?> _error(String code) => <String, Object?>{
    'error': <String, Object?>{'code': code, 'message': 'sintético'},
    'request_id': '70000000-0000-4000-8000-000000000001',
  };

  Map<String, Object?> _sessionPayload() => <String, Object?>{
    'access_token': _accessToken,
    'access_expires_at': '2030-08-14T14:00:00Z',
    'refresh_token': _refreshToken,
    'refresh_expires_at': '2030-09-14T12:00:00Z',
    'device': <String, Object?>{
      'uuid': _deviceUuid,
      'name': 'Lar Finance Windows sintético',
      'platform': 'windows',
      'default_owner_uuid': _selfOwnerUuid,
    },
  };

  Map<String, Object?> _previewPayload({
    required Iterable<Object?> records,
    String? nextCursor,
    String status = 'preview_ready',
    int createdCount = 0,
  }) => <String, Object?>{
    'uuid': _batchUuid,
    'status': status,
    'provider': 'nubank',
    'product_type': 'bank_account',
    'statement_start': '2026-08-01',
    'statement_end': '2026-08-12',
    'expires_at': '2030-08-16T15:00:00Z',
    'account_uuid': _accountUuid,
    'financial_owner_uuid': _selfOwnerUuid,
    'created_count': createdCount,
    'duplicate_count': 0,
    'warning_count': 0,
    'record_count': 3,
    'pending_count': 3,
    'income_total': '0.00',
    'expense_total': '90.00',
    'is_repeated_file': false,
    'records': records.toList(growable: false),
    'next_cursor': nextCursor,
  };

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

/// Lets a route transition finish so a tap is not swallowed by it.
Future<void> _settle(WidgetTester tester) async {
  for (var pump = 0; pump < 10; pump++) {
    await tester.pump(const Duration(milliseconds: 50));
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
    debugPrint(
      'import integration timeout; visible: '
      '${tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).whereType<String>().toList()}',
    );
  }
  expect(finder, findsWidgets);
}

Future<void> _eventually(bool Function() condition, {String? reason}) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: reason);
}

const _deviceUuid = '10000000-0000-4000-8000-000000000001';
const _householdUuid = '20000000-0000-4000-8000-000000000001';
const _selfOwnerUuid = '30000000-0000-4000-8000-000000000001';
const _spouseOwnerUuid = '30000000-0000-4000-8000-000000000002';
const _sharedOwnerUuid = '30000000-0000-4000-8000-000000000003';
const _accountUuid = '40000000-0000-4000-8000-000000000001';
const _categoryUuid = '50000000-0000-4000-8000-000000000001';
const _batchUuid = '60000000-0000-4000-8000-000000000001';
const _transactionUuid = '80000000-0000-4000-8000-000000000001';
const _bootstrapCursor = 'synthetic-bootstrap-cursor';
const _deltaCursor = 'synthetic-delta-cursor';

const _records = <Object?>[
  <String, Object?>{
    'uuid': '90000000-0000-4000-8000-000000000001',
    'posted_on': '2026-08-02',
    'description': 'Mercado sintético 1',
    'amount': '30.00',
    'transaction_type': 'expense',
    'outcome': 'pending',
  },
  <String, Object?>{
    'uuid': '90000000-0000-4000-8000-000000000002',
    'posted_on': '2026-08-03',
    'description': 'Mercado sintético 2',
    'amount': '30.00',
    'transaction_type': 'expense',
    'outcome': 'pending',
  },
  <String, Object?>{
    'uuid': '90000000-0000-4000-8000-000000000003',
    'posted_on': '2026-08-04',
    'description': 'Mercado sintético 3',
    'amount': '30.00',
    'transaction_type': 'expense',
    'outcome': 'pending',
  },
];

const _owners = <Object?>[
  <String, Object?>{'uuid': _selfOwnerUuid, 'type': 'self', 'name': 'Alex'},
  <String, Object?>{'uuid': _spouseOwnerUuid, 'type': 'spouse', 'name': 'Rui'},
  <String, Object?>{
    'uuid': _sharedOwnerUuid,
    'type': 'shared',
    'name': 'Conjunto',
  },
];

final _bootstrapPayload = <String, Object?>{
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
      'name': 'Nubank — Conta',
      'type': 'checking',
      'initial_balance': '0.00',
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
      'name': 'Não categorizado',
      'type': 'expense',
      'color': '#8B6F47',
      'icon': 'home',
      'version': 1,
      'created_at': '2026-08-01T09:00:00Z',
      'updated_at': '2026-08-14T12:00:00Z',
    },
  ],
  'transactions': <Object?>[],
  'summary': <String, Object?>{
    'total_balance': '0.00',
    'monthly_income': '0.00',
    'monthly_expenses': '0.00',
  },
  'cursor': _bootstrapCursor,
};

final _deltaPayload = <String, Object?>{
  'changes': <Object?>[
    <String, Object?>{
      'entity_type': 'transaction',
      'entity_uuid': _transactionUuid,
      'entity_version': 1,
      'operation': 'create',
      'payload': <String, Object?>{
        'uuid': _transactionUuid,
        'household_uuid': _householdUuid,
        'financial_owner_uuid': _selfOwnerUuid,
        'account_uuid': _accountUuid,
        'category_uuid': _categoryUuid,
        'description': 'Mercado sintético 1',
        'amount': '30.00',
        'date': '2026-08-02',
        'type': 'expense',
        'version': 1,
        'created_at': '2026-08-14T12:05:00Z',
        'updated_at': '2026-08-14T12:05:00Z',
      },
    },
  ],
  'cursor': _deltaCursor,
};
