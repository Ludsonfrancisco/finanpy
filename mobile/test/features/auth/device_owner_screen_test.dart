import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/app_config.dart';
import 'package:lar_finance/app/router.dart';
import 'package:lar_finance/core/network/api_error.dart';
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
    await tester.pumpWidget(_screenApp(controller, const MoreScreen()));

    expect(find.text('Lar Finance no Windows'), findsOneWidget);
    expect(find.textContaining('14/08/2030'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sair'));
    await tester.pumpAndSettle();

    expect(gateway.logoutCalls, 1);
    expect(controller.state.phase, AuthPhase.signedOut);
  });

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
  });

  final bool logoutThrows;
  final StoredTokens? restoredSession;
  final String? selectedOwnerUuid;
  final String? syncedDeviceUuid;
  final Object? loadOwnersError;
  final Object? readSessionError;
  final LoginResult? loginResult;
  int logoutCalls = 0;
  String? selectedUuid;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async => loginResult ?? _loginResult();

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
  Future<void> selectDeviceOwner(String uuid) async => selectedUuid = uuid;
}
