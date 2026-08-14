import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/app_lifecycle.dart';
import 'package:lar_finance/app/app_config.dart';
import 'package:lar_finance/app/router.dart';
import 'package:lar_finance/core/network/api_error.dart';
import 'package:lar_finance/core/storage/local_ledger.dart';
import 'package:lar_finance/core/sync/sync_api.dart';
import 'package:lar_finance/core/sync/sync_coordinator.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/features/auth/application/auth_controller.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/domain/session.dart';
import 'package:lar_finance/features/auth/presentation/initial_sync_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

const _deviceUuid = '70000000-0000-4000-8000-000000000001';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets(
    'initial sync shows indeterminate progress until cache is valid',
    (tester) async {
      final release = Completer<BootstrapPayload>();
      final ledger = _MemoryLedger();
      final coordinator = _coordinator(
        ledger,
        _SequenceSyncApi(bootstrapFuture: release.future),
      );
      var readyCalls = 0;
      await tester.pumpWidget(
        _app(
          InitialSyncScreen(
            coordinator: coordinator,
            onReady: (_, _) async {
              readyCalls++;
              return true;
            },
          ),
        ),
      );
      await tester.pump();

      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.value, isNull);
      expect(find.textContaining('%'), findsNothing);
      expect(readyCalls, 0);

      release.complete(_bootstrap());
      await _pumpUntil(tester, () => readyCalls == 1);
      expect(readyCalls, 1);
      expect(await coordinator.hasValidCache(), isTrue);
    },
  );

  testWidgets('offline without cache is explicit and retry can recover', (
    tester,
  ) async {
    final ledger = _MemoryLedger();
    final api = _SequenceSyncApi(
      bootstrapOutcomes: <Object>[const OfflineFailure(), _bootstrap()],
    );
    final coordinator = _coordinator(ledger, api);
    var readyCalls = 0;
    await tester.pumpWidget(
      _app(
        InitialSyncScreen(
          coordinator: coordinator,
          onReady: (_, _) async {
            readyCalls++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Sem conexão e sem dados salvos neste dispositivo.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Tentar novamente'),
      findsOneWidget,
    );
    expect(readyCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Tentar novamente'));
    await _pumpUntil(tester, () => readyCalls == 1);
    expect(readyCalls, 1);
    expect(api.bootstrapCalls, 2);
  });

  testWidgets('unexpected sync errors expose only a safe retry message', (
    tester,
  ) async {
    final coordinator = _coordinator(
      _MemoryLedger(),
      _SequenceSyncApi(
        bootstrapOutcomes: <Object>[StateError('secret detail')],
      ),
    );
    await tester.pumpWidget(
      _app(
        InitialSyncScreen(
          coordinator: coordinator,
          onReady: (_, _) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível sincronizar seus dados. Tente novamente.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret detail'), findsNothing);
  });

  testWidgets(
    'authenticated launch paints cached Home before network returns',
    (tester) async {
      final release = Completer<SyncPage>();
      final ledger = _MemoryLedger(
        metadata: _metadata(DateTime.utc(2026, 8, 14, 12)),
      );
      final api = _SequenceSyncApi(changeFuture: release.future);
      final coordinator = _coordinator(ledger, api);

      await tester.pumpWidget(
        _app(
          AppSyncLifecycle(
            coordinator: coordinator,
            isAuthenticated: () => true,
            child: const Text('Home em cache'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Home em cache'), findsOneWidget);
      expect(api.changeCalls, 1);

      release.complete(
        const SyncPage(
          changes: <SyncChangePayload>[],
          cursor: 'cursor-current',
        ),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'resume syncs only when last success is older than five minutes',
    (tester) async {
      var authenticated = false;
      var now = DateTime.utc(2026, 8, 14, 12, 4, 59);
      final ledger = _MemoryLedger(
        metadata: _metadata(DateTime.utc(2026, 8, 14, 12)),
      );
      final api = _SequenceSyncApi(
        changeOutcomes: const <Object>[
          SyncPage(
            changes: <SyncChangePayload>[],
            cursor: 'cursor-after-resume',
          ),
        ],
      );
      final coordinator = _coordinator(ledger, api, now: () => now);
      await tester.pumpWidget(
        _app(
          AppSyncLifecycle(
            coordinator: coordinator,
            isAuthenticated: () => authenticated,
            child: const Text('Home'),
          ),
        ),
      );
      await tester.pump();
      authenticated = true;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(api.changeCalls, 0);

      now = DateTime.utc(2026, 8, 14, 12, 5, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.changeCalls, 1);
    },
  );

  testWidgets('a valid initial snapshot unlocks the guarded Home route', (
    tester,
  ) async {
    final authority = SessionAuthority.forStore(_MemoryTokenStore(_session()));
    final auth = AuthController(
      _TestAuthGateway(),
      sessionAuthority: authority,
    );
    await auth.login(email: 'synthetic@example.test', password: 'synthetic');
    await auth.selectDeviceOwner('20000000-0000-4000-8000-000000000001');
    expect(auth.state.phase, AuthPhase.initialSync);
    final coordinator = _coordinator(
      _MemoryLedger(),
      _SequenceSyncApi(bootstrapOutcomes: <Object>[_bootstrap()]),
      sessionAuthority: authority,
    );
    final router = createAppRouter(
      const AppConfig(apiBaseUrl: 'https://example.test/api/v1'),
      auth,
      syncCoordinator: coordinator,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => auth,
            disposeNotifier: false,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpUntil(tester, () => auth.state.phase == AuthPhase.authenticated);
    await tester.pumpAndSettle();

    expect(find.text('Dados ainda não sincronizados'), findsOneWidget);
    expect(find.byType(InitialSyncScreen), findsNothing);
  });

  testWidgets('pull-to-refresh always requests and reuses in-flight sync', (
    tester,
  ) async {
    final release = Completer<SyncPage>();
    final ledger = _MemoryLedger(
      metadata: _metadata(DateTime.utc(2026, 8, 14, 12)),
    );
    final api = _SequenceSyncApi(changeFuture: release.future);
    final coordinator = _coordinator(ledger, api);
    final auth = AuthController(
      _TestAuthGateway(
        restoredSession: _session(),
        selectedOwnerUuid: '20000000-0000-4000-8000-000000000001',
        syncedDeviceUuid: _deviceUuid,
      ),
    );
    await auth.initialize();
    final router = createAppRouter(
      const AppConfig(apiBaseUrl: 'https://example.test/api/v1'),
      auth,
      syncCoordinator: coordinator,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );

    final first = refresh.onRefresh();
    final second = refresh.onRefresh();
    await tester.pump();
    expect(api.changeCalls, 1);

    release.complete(
      const SyncPage(changes: <SyncChangePayload>[], cursor: 'cursor-refresh'),
    );
    await Future.wait(<Future<void>>[first, second]);
    expect((await ledger.readSyncMetadata())?.cursor, 'cursor-refresh');
  });

  testWidgets(
    'stale bootstrap cannot release Home after same-value session replacement',
    (tester) async {
      final store = _MemoryTokenStore(_session());
      final authority = SessionAuthority.forStore(store);
      final expectedSession = await authority.snapshot();
      final release = Completer<BootstrapPayload>();
      final ledger = _MemoryLedger();
      final api = _SequenceSyncApi(bootstrapFuture: release.future);
      final coordinator = _coordinator(
        ledger,
        api,
        sessionAuthority: authority,
      );
      var readyCalls = 0;
      await tester.pumpWidget(
        _app(
          InitialSyncScreen(
            coordinator: coordinator,
            onReady: (_, _) async {
              readyCalls++;
              return true;
            },
          ),
        ),
      );
      await _pumpUntil(tester, () => api.bootstrapCalls == 1);

      await authority.clear();
      final replacement = _session();
      await authority.write(replacement);
      expect(
        (await authority.snapshot())?.generation,
        greaterThan(expectedSession!.generation),
      );
      release.complete(_bootstrap());
      await _pumpUntil(
        tester,
        () => coordinator.state.phase != SyncPhase.syncing,
      );
      await tester.pump();

      expect(readyCalls, 0);
      expect(ledger.metadata, isNull);
      expect(await store.read(), same(replacement));
      expect(
        find.text('Não foi possível sincronizar seus dados. Tente novamente.'),
        findsOneWidget,
      );
    },
  );

  test(
    'completeInitialSync accepts only the expected session generation',
    () async {
      final store = _MemoryTokenStore(_session());
      final authority = SessionAuthority.forStore(store);
      final auth = AuthController(
        _TestAuthGateway(),
        sessionAuthority: authority,
      );
      await auth.login(email: 'synthetic@example.test', password: 'synthetic');
      await auth.selectDeviceOwner('20000000-0000-4000-8000-000000000001');
      final stale = await authority.snapshot();
      await authority.clear();
      await authority.write(_session());

      expect(
        await auth.completeInitialSync(stale!, DateTime.utc(2026, 8, 14, 14)),
        isFalse,
      );
      expect(auth.state.phase, AuthPhase.initialSync);

      final current = await authority.snapshot();
      expect(
        await auth.completeInitialSync(current!, DateTime.utc(2026, 8, 14, 14)),
        isTrue,
      );
      expect(auth.state.phase, AuthPhase.authenticated);
    },
  );
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

LedgerSyncCoordinator _coordinator(
  LocalLedger ledger,
  SyncApi api, {
  DateTime Function()? now,
  SessionAuthority? sessionAuthority,
}) {
  return LedgerSyncCoordinator(
    api: api,
    ledger: ledger,
    sessionAuthority:
        sessionAuthority ??
        SessionAuthority.forStore(_MemoryTokenStore(_session())),
    now: now ?? () => DateTime.utc(2026, 8, 14, 14),
  );
}

BootstrapPayload _bootstrap() => const BootstrapPayload(
  household: <String, Object?>{'uuid': '10000000-0000-4000-8000-000000000001'},
  owners: <JsonObject>[],
  accounts: <JsonObject>[],
  categories: <JsonObject>[],
  transactions: <JsonObject>[],
  cursor: 'cursor-bootstrap',
);

SyncMetadata _metadata(DateTime timestamp) => SyncMetadata(
  cursor: 'cursor-cache',
  householdUuid: '10000000-0000-4000-8000-000000000001',
  sessionDeviceUuid: _deviceUuid,
  sessionGeneration: 0,
  lastSuccessAt: timestamp,
);

final class _MemoryLedger implements LocalLedger {
  _MemoryLedger({this.metadata});

  SyncMetadata? metadata;

  @override
  Future<void> applyDelta(
    SyncPage page,
    DateTime syncedAt, {
    int sessionGeneration = 0,
    bool Function()? isSessionCurrent,
  }) async {
    await applyDeltaChain(
      <SyncPage>[page],
      syncedAt,
      sessionGeneration: sessionGeneration,
      isSessionCurrent: isSessionCurrent,
    );
  }

  @override
  Future<void> applyDeltaChain(
    List<SyncPage> pages,
    DateTime syncedAt, {
    int sessionGeneration = 0,
    bool Function()? isSessionCurrent,
  }) async {
    if (isSessionCurrent != null && !isSessionCurrent()) {
      throw StateError('stale session');
    }
    final current = metadata!;
    metadata = SyncMetadata(
      cursor: pages.last.cursor,
      householdUuid: current.householdUuid,
      sessionDeviceUuid: current.sessionDeviceUuid,
      sessionGeneration: sessionGeneration,
      lastSuccessAt: syncedAt,
    );
  }

  @override
  Future<SyncMetadata?> readSyncMetadata() async => metadata;

  @override
  Future<void> replaceBootstrap(
    BootstrapPayload payload,
    DateTime syncedAt,
    String sessionDeviceUuid, {
    int sessionGeneration = 0,
    bool Function()? isSessionCurrent,
  }) async {
    if (isSessionCurrent != null && !isSessionCurrent()) {
      throw StateError('stale session');
    }
    metadata = SyncMetadata(
      cursor: payload.cursor,
      householdUuid: payload.household['uuid']! as String,
      sessionDeviceUuid: sessionDeviceUuid,
      sessionGeneration: sessionGeneration,
      lastSuccessAt: syncedAt,
    );
  }

  @override
  Stream<HomeSnapshot> watchHome(OwnerScope scope, DateTime now) =>
      const Stream<HomeSnapshot>.empty();
}

final class _SequenceSyncApi implements SyncApi {
  _SequenceSyncApi({
    this.bootstrapFuture,
    this.changeFuture,
    this.bootstrapOutcomes = const <Object>[],
    this.changeOutcomes = const <Object>[],
  });

  final Future<BootstrapPayload>? bootstrapFuture;
  final Future<SyncPage>? changeFuture;
  final List<Object> bootstrapOutcomes;
  final List<Object> changeOutcomes;
  int bootstrapCalls = 0;
  int changeCalls = 0;

  @override
  Future<BootstrapPayload> fetchBootstrap() async {
    final index = bootstrapCalls++;
    if (bootstrapFuture case final future?) return future;
    final outcome = bootstrapOutcomes[index];
    if (outcome is BootstrapPayload) return outcome;
    throw outcome;
  }

  @override
  Future<SyncPage> fetchChanges(String cursor) async {
    final index = changeCalls++;
    if (changeFuture case final future?) return future;
    final outcome = changeOutcomes[index];
    if (outcome is SyncPage) return outcome;
    throw outcome;
  }
}

StoredTokens _session() => StoredTokens(
  accessToken: 'synthetic-access',
  accessExpiresAt: DateTime.utc(2030),
  refreshToken: 'synthetic-refresh',
  refreshExpiresAt: DateTime.utc(2031),
  deviceUuid: _deviceUuid,
);

final class _TestAuthGateway implements AuthGateway {
  _TestAuthGateway({
    this.restoredSession,
    this.selectedOwnerUuid,
    this.syncedDeviceUuid,
  });

  final StoredTokens? restoredSession;
  final String? selectedOwnerUuid;
  final String? syncedDeviceUuid;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async => LoginResult(
    session: _session(),
    owners: const <DeviceOwnerOption>[
      DeviceOwnerOption(
        uuid: '20000000-0000-4000-8000-000000000001',
        type: 'self',
        name: 'Alex',
      ),
    ],
  );

  @override
  Future<List<DeviceOwnerOption>> loadOwners() async =>
      const <DeviceOwnerOption>[
        DeviceOwnerOption(
          uuid: '20000000-0000-4000-8000-000000000001',
          type: 'self',
          name: 'Alex',
        ),
      ];

  @override
  Future<void> logout() async {}

  @override
  Future<String> readDeviceName() async => 'Dispositivo sintético';

  @override
  Future<DateTime?> readLastSyncAt() async => DateTime.utc(2026, 8, 14, 12);

  @override
  Future<String?> readSelectedOwnerUuid() async => selectedOwnerUuid;

  @override
  Future<StoredTokens?> readSession() async => restoredSession;

  @override
  Future<String?> readSyncedDeviceUuid() async => syncedDeviceUuid;

  @override
  Future<void> selectDeviceOwner(String uuid) async {}
}

final class _MemoryTokenStore implements TokenStore {
  _MemoryTokenStore(this.value);

  StoredTokens? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredTokens?> read() async => value;

  @override
  Future<void> write(StoredTokens tokens) async => value = tokens;
}
