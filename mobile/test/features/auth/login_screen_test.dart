import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/network/api_error.dart';
import 'package:lar_finance/features/auth/application/auth_controller.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/domain/session.dart';
import 'package:lar_finance/features/auth/presentation/login_screen.dart';

void main() {
  testWidgets('rejects an invalid email before calling the repository', (
    tester,
  ) async {
    final gateway = _FakeAuthGateway();
    final controller = AuthController(gateway);
    await tester.pumpWidget(_testApp(controller));

    await tester.enterText(find.bySemanticsLabel('E-mail'), 'email inválido');
    await tester.enterText(find.bySemanticsLabel('Senha'), 'segredo');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();

    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(gateway.loginCalls, 0);
  });

  testWidgets('toggles password visibility without exposing its value', (
    tester,
  ) async {
    final controller = AuthController(_FakeAuthGateway());
    await tester.pumpWidget(_testApp(controller));

    expect(_passwordEditor(tester).obscureText, isTrue);
    await tester.tap(find.byTooltip('Mostrar senha'));
    await tester.pump();
    expect(_passwordEditor(tester).obscureText, isFalse);
    expect(find.byTooltip('Ocultar senha'), findsOneWidget);
  });

  testWidgets('disables submission and shows progress while login is pending', (
    tester,
  ) async {
    final pending = Completer<LoginResult>();
    final gateway = _FakeAuthGateway(loginFuture: pending.future);
    final controller = AuthController(gateway);
    await tester.pumpWidget(_testApp(controller));
    await _enterValidCredentials(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    pending.complete(_loginResult());
    await tester.pumpAndSettle();
  });

  testWidgets('shows the exact generic message for a 401', (tester) async {
    final controller = AuthController(
      _FakeAuthGateway(loginError: const AuthFailure()),
    );
    await tester.pumpWidget(_testApp(controller));
    await _enterValidCredentials(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível entrar. Confira os dados e tente novamente.'),
      findsOneWidget,
    );
    expect(find.textContaining('401'), findsNothing);
  });

  testWidgets('shows a safe offline message on timeout', (tester) async {
    final controller = AuthController(
      _FakeAuthGateway(loginError: const OfflineFailure()),
    );
    await tester.pumpWidget(_testApp(controller));
    await _enterValidCredentials(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sem conexão. Confira sua internet e tente novamente.'),
      findsOneWidget,
    );
  });

  testWidgets('supports 200 percent text scaling without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = AuthController(_FakeAuthGateway());
    await tester.pumpWidget(
      _testApp(
        controller,
        mediaQuery: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(2),
        ),
      ),
    );

    expect(find.text('Entre no Lar Finance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submits with the Windows Enter action from password', (
    tester,
  ) async {
    final gateway = _FakeAuthGateway();
    final controller = AuthController(gateway);
    await tester.pumpWidget(_testApp(controller));
    await _enterValidCredentials(tester);

    await tester.tap(find.bySemanticsLabel('Senha'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(gateway.loginCalls, 1);
  });
}

EditableText _passwordEditor(WidgetTester tester) =>
    tester.widgetList<EditableText>(find.byType(EditableText)).last;

Future<void> _enterValidCredentials(WidgetTester tester) async {
  await tester.enterText(find.bySemanticsLabel('E-mail'), 'ana@example.com');
  await tester.enterText(find.bySemanticsLabel('Senha'), 'segredo');
}

Widget _testApp(AuthController controller, {MediaQueryData? mediaQuery}) =>
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => controller,
          disposeNotifier: false,
        ),
      ],
      child: MaterialApp(
        home: mediaQuery == null
            ? const LoginScreen()
            : MediaQuery(data: mediaQuery, child: const LoginScreen()),
      ),
    );

LoginResult _loginResult() => LoginResult(
  session: StoredTokens(
    accessToken: 'access-secret',
    accessExpiresAt: DateTime.utc(2030, 1, 1),
    refreshToken: 'refresh-secret',
    refreshExpiresAt: DateTime.utc(2030, 2, 1),
    deviceUuid: '11111111-1111-4111-8111-111111111111',
  ),
  owners: const <DeviceOwnerOption>[
    DeviceOwnerOption(
      uuid: '22222222-2222-4222-8222-222222222222',
      type: 'self',
      name: 'Ana',
    ),
  ],
);

final class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({this.loginFuture, this.loginError});

  final Future<LoginResult>? loginFuture;
  final Object? loginError;
  int loginCalls = 0;

  @override
  Future<LoginResult> login({required String email, required String password}) {
    loginCalls++;
    if (loginError case final error?) return Future<LoginResult>.error(error);
    return loginFuture ?? Future<LoginResult>.value(_loginResult());
  }

  @override
  Future<List<DeviceOwnerOption>> loadOwners() async => _loginResult().owners;

  @override
  Future<void> logout() async {}

  @override
  Future<String> readDeviceName() async => 'Lar Finance no Windows';

  @override
  Future<DateTime?> readLastSyncAt() async => null;

  @override
  Future<String?> readSelectedOwnerUuid() async => null;

  @override
  Future<StoredTokens?> readSession() async => null;

  @override
  Future<String?> readSyncedDeviceUuid() async => null;

  @override
  Future<String?> readSyncedSessionIdentity() async => null;

  @override
  Future<void> selectDeviceOwner(String uuid) async {}
}
