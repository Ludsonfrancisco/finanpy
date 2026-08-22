import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/app_config.dart';
import 'package:lar_finance/app/router.dart';
import 'package:lar_finance/core/network/api_error.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/features/auth/application/auth_controller.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/domain/session.dart';
import 'package:lar_finance/features/auth/presentation/device_owner_screen.dart';
import 'package:lar_finance/features/auth/presentation/more_screen.dart';

void main() {
  testWidgets('offers only self and spouse and continues with the choice', (
    tester,
  ) async {
    final gateway = _FakeAuthGateway();
    final controller = AuthController(gateway);
    await controller.login(email: 'ana@example.com', password: 'secret');
    await tester.pumpWidget(_screenApp(controller, const DeviceOwnerScreen()));

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Beto'), findsOneWidget);
    expect(find.text('Casa'), findsNothing);

    await tester.tap(find.text('Beto'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await tester.pumpAndSettle();

    expect(gateway.selectedUuid, _spouseUuid);
    expect(controller.state.phase, AuthPhase.initialSync);
  });

  testWidgets('owner choice remains usable at 200 percent text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = AuthController(_FakeAuthGateway());
    await controller.login(email: 'ana@example.com', password: 'secret');
    await tester.pumpWidget(
      _screenApp(
        controller,
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2),
          ),
          child: DeviceOwnerScreen(),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Continuar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More shows local device status and logs out offline', (
    tester,
  ) async {
    final gateway = _FakeAuthGateway(logoutThrows: true);
    final controller = AuthController(gateway);
    await controller.login(email: 'ana@example.com', password: 'secret');
    await tester.pumpWidget(
      _screenApp(
        controller,
        const MoreScreen(
          buildLabel: '1234567',
          serverHost: 'financeiro.palmbook.online',
        ),
      ),
    );

    expect(find.text('Lar Finance no Windows'), findsOneWidget);
    expect(find.text('Versão 1234567'), findsOneWidget);
    expect(find.text('financeiro.palmbook.online'), findsOneWidget);
    expect(find.textContaining('14/08/2030'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Sair'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sair'));
    await tester.pumpAndSettle();

    expect(gateway.logoutCalls, 1);
    expect(controller.state.phase, AuthPhase.signedOut);
  });

  testWidgets('More follows the live sync timestamp after authentication', (
    tester,
  ) async {
    final controller = AuthController(_FakeAuthGateway());
    await controller.login(email: 'ana@example.com', password: 'secret');
    final syncState = SyncState(retry: () async => SyncResult.current)
      ..markCurrent(DateTime(2030, 8, 15, 11, 45));

    await tester.pumpWidget(
      _screenApp(controller, MoreScreen(syncState: syncState)),
    );

    expect(find.text('15/08/2030, 11:45'), findsOneWidget);
    expect(find.text('14/08/2030, 10:30'), findsNothing);

    syncState.markCurrent(DateTime(2030, 8, 15, 12, 5));
    await tester.pump();

    expect(find.text('15/08/2030, 12:05'), findsOneWidget);
    expect(find.text('15/08/2030, 11:45'), findsNothing);
  });

  testWidgets('router injects the safe build identity into More', (
    tester,
  ) async {
    final controller = AuthController(
      _FakeAuthGateway(
        restoredSession: _sessionFor(_deviceUuid),
        selectedOwnerUuid: _selfUuid,
        syncedDeviceUuid: _deviceUuid,
      ),
    );
    await controller.initialize();
    expect(controller.state.phase, AuthPhase.authenticated);

    final router = createAppRouter(
      const AppConfig(
        apiBaseUrl: 'https://financeiro.palmbook.online/api/v1/',
        buildSha: '1234567890abcdef1234567890abcdef12345678',
      ),
      controller,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => controller,
            disposeNotifier: false,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.go('/more');
    await tester.pumpAndSettle();

    expect(find.text('Versão 1234567'), findsOneWidget);
    expect(find.text('financeiro.palmbook.online'), findsOneWidget);
  });

  test(
    'session expiration hides authenticated UI without deleting cache',
    () async {
      final gateway = _FakeAuthGateway(
        restoredSession: _sessionFor(_deviceUuid),
        selectedOwnerUuid: _selfUuid,
        syncedDeviceUuid: _deviceUuid,
      );
      final controller = AuthController(gateway);
      await controller.initialize();
      expect(controller.state.phase, AuthPhase.authenticated);

      controller.expireSession();

      expect(controller.state.phase, AuthPhase.signedOut);
      expect(controller.state.message, const SessionExpired().message);
      expect(gateway.logoutCalls, 0);
      expect(controller.state.lastSyncAt, isNotNull);
    },
  );

  test(
    'logout hides authenticated UI before remote or vault I/O completes',
    () async {
      final release = Completer<void>();
      final gateway = _FakeAuthGateway(
        restoredSession: _sessionFor(_deviceUuid),
        selectedOwnerUuid: _selfUuid,
        syncedDeviceUuid: _deviceUuid,
        logoutRelease: release,
      );
      final controller = AuthController(gateway);
      await controller.initialize();
      expect(controller.state.phase, AuthPhase.authenticated);

      final logout = controller.logout();

      expect(gateway.logoutCalls, 1);
      expect(controller.state.phase, AuthPhase.signedOut);
      release.complete();
      await logout;
    },
  );

  test(
    'login waits for prior logout cleanup before creating a new session',
    () async {
      final release = Completer<void>();
      final gateway = _FakeAuthGateway(
        restoredSession: _sessionFor(_deviceUuid),
        selectedOwnerUuid: _selfUuid,
        syncedDeviceUuid: _deviceUuid,
        logoutRelease: release,
      );
      final controller = AuthController(gateway);
      await controller.initialize();

      final logout = controller.logout();
      final login = controller.login(
        email: 'ana@example.com',
        password: 'synthetic-secret',
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, AuthPhase.signedOut);
      expect(controller.state.isSubmitting, isTrue);
      expect(gateway.loginCalls, 0);

      release.complete();
      await logout;
      await login;
      expect(controller.state.phase, AuthPhase.choosingOwner);

      await controller.selectDeviceOwner(_spouseUuid);
      expect(gateway.selectedUuid, _spouseUuid);
      expect(gateway.operations, <String>[
        'logout-start',
        'logout-cleanup',
        'login',
        'select:$_spouseUuid',
      ]);
    },
  );

  testWidgets('guarded routes move through login, owner, and initial sync', (
    tester,
  ) async {
    final gateway = _FakeAuthGateway();
    final controller = AuthController(gateway);
    await controller.initialize();
    final router = createAppRouter(
      const AppConfig(apiBaseUrl: 'https://example.test/api/v1'),
      controller,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => controller,
            disposeNotifier: false,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.go('/home');
    await tester.pumpAndSettle();
    expect(find.text('Entre no Lar Finance'), findsOneWidget);

    await controller.login(email: 'ana@example.com', password: 'secret');
    await tester.pumpAndSettle();
    expect(find.byType(DeviceOwnerScreen), findsOneWidget);

    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Preparando dados'), findsOneWidget);

    await controller.logout();
    await tester.pumpAndSettle();
    expect(find.text('Entre no Lar Finance'), findsOneWidget);
  });

  test(
    'restores home only when cached data belongs to the current device',
    () async {
      final matching = AuthController(
        _FakeAuthGateway(
          restoredSession: _sessionFor(_deviceUuid),
          selectedOwnerUuid: _selfUuid,
          syncedDeviceUuid: _deviceUuid,
        ),
      );
      await matching.initialize();
      expect(matching.state.phase, AuthPhase.authenticated);

      final mismatched = AuthController(
        _FakeAuthGateway(
          restoredSession: _sessionFor(_deviceUuid),
          selectedOwnerUuid: _selfUuid,
          syncedDeviceUuid: '55555555-5555-4555-8555-555555555555',
        ),
      );
      await mismatched.initialize();
      expect(mismatched.state.phase, AuthPhase.initialSync);
    },
  );

  test(
    'clears an unowned restored session when owners cannot load offline',
    () async {
      final gateway = _FakeAuthGateway(
        restoredSession: _sessionFor(_deviceUuid),
        loadOwnersError: const OfflineFailure(),
      );
      final controller = AuthController(gateway);

      await controller.initialize();

      expect(controller.state.phase, AuthPhase.signedOut);
      expect(gateway.logoutCalls, 1);
    },
  );

  test(
    'a failed expired-session refresh remains signed out without a logout race',
    () async {
      final gateway = _FakeAuthGateway(
        readSessionError: const OfflineFailure(),
      );
      final controller = AuthController(gateway);

      await controller.initialize();

      expect(controller.state.phase, AuthPhase.signedOut);
      expect(controller.state.message, const OfflineFailure().message);
      expect(gateway.logoutCalls, 0);
    },
  );

  test(
    'an empty owner result cannot leave the controller in a dead-end flow',
    () async {
      final controller = AuthController(
        _FakeAuthGateway(
          loginResult: LoginResult(
            session: _sessionFor(_deviceUuid),
            owners: const <DeviceOwnerOption>[],
          ),
        ),
      );

      await controller.login(email: 'ana@example.com', password: 'secret');

      expect(controller.state.phase, AuthPhase.signedOut);
      expect(controller.state.message, const RequestFailure().message);
    },
  );

  testWidgets(
    'checking never exposes a guarded deep link or redirects in a loop',
    (tester) async {
      final controller = AuthController(_FakeAuthGateway());
      final router = createAppRouter(
        const AppConfig(apiBaseUrl: 'https://example.test/api/v1'),
        controller,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => controller,
              disposeNotifier: false,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      router.go('/home');
      await tester.pumpAndSettle();

      expect(find.text('Entre no Lar Finance'), findsOneWidget);
      expect(find.text('CASA DE VALORES'), findsNothing);
    },
  );
}

Widget _screenApp(AuthController controller, Widget child) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(
      (ref) => controller,
      disposeNotifier: false,
    ),
  ],
  child: MaterialApp(home: child),
);

const _selfUuid = '22222222-2222-4222-8222-222222222222';
const _spouseUuid = '33333333-3333-4333-8333-333333333333';
const _sharedUuid = '44444444-4444-4444-8444-444444444444';
const _deviceUuid = '11111111-1111-4111-8111-111111111111';
const _sessionIdentity = 'synthetic-session-identity';

LoginResult _loginResult() => LoginResult(
  session: StoredTokens(
    accessToken: 'access-secret',
    accessExpiresAt: DateTime.utc(2030, 1, 1),
    refreshToken: 'refresh-secret',
    refreshExpiresAt: DateTime.utc(2030, 2, 1),
    deviceUuid: _deviceUuid,
  ),
  owners: const <DeviceOwnerOption>[
    DeviceOwnerOption(uuid: _selfUuid, type: 'self', name: 'Ana'),
    DeviceOwnerOption(uuid: _spouseUuid, type: 'spouse', name: 'Beto'),
    DeviceOwnerOption(uuid: _sharedUuid, type: 'shared', name: 'Casa'),
  ],
);

StoredTokens _sessionFor(String deviceUuid) => StoredTokens(
  accessToken: 'access-secret',
  accessExpiresAt: DateTime.utc(2030, 1, 1),
  refreshToken: 'refresh-secret',
  refreshExpiresAt: DateTime.utc(2030, 2, 1),
  deviceUuid: deviceUuid,
  sessionIdentity: _sessionIdentity,
);

final class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({
    this.logoutThrows = false,
    this.restoredSession,
    this.selectedOwnerUuid,
    this.syncedDeviceUuid,
    this.loadOwnersError,
    this.readSessionError,
    this.loginResult,
    this.logoutRelease,
  });

  final bool logoutThrows;
  final StoredTokens? restoredSession;
  final String? selectedOwnerUuid;
  final String? syncedDeviceUuid;
  final Object? loadOwnersError;
  final Object? readSessionError;
  final LoginResult? loginResult;
  final Completer<void>? logoutRelease;
  int logoutCalls = 0;
  int loginCalls = 0;
  String? selectedUuid;
  final List<String> operations = <String>[];

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    operations.add('login');
    return loginResult ?? _loginResult();
  }

  @override
  Future<List<DeviceOwnerOption>> loadOwners() {
    if (loadOwnersError case final error?) {
      return Future<List<DeviceOwnerOption>>.error(error);
    }
    return Future<List<DeviceOwnerOption>>.value(_loginResult().owners);
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    operations.add('logout-start');
    await logoutRelease?.future;
    operations.add('logout-cleanup');
    selectedUuid = null;
    if (logoutThrows) throw StateError('offline');
  }

  @override
  Future<String> readDeviceName() async => 'Lar Finance no Windows';

  @override
  Future<DateTime?> readLastSyncAt() async => DateTime(2030, 8, 14, 10, 30);

  @override
  Future<String?> readSelectedOwnerUuid() async => selectedOwnerUuid;

  @override
  Future<StoredTokens?> readSession() {
    if (readSessionError case final error?) {
      return Future<StoredTokens?>.error(error);
    }
    return Future<StoredTokens?>.value(restoredSession);
  }

  @override
  Future<String?> readSyncedDeviceUuid() async => syncedDeviceUuid;

  @override
  Future<String?> readSyncedSessionIdentity() async =>
      syncedDeviceUuid == null ? null : _sessionIdentity;

  @override
  Future<void> selectDeviceOwner(String uuid) async {
    operations.add('select:$uuid');
    selectedUuid = uuid;
  }
}
