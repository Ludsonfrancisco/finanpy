import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/features/auth/application/auth_controller.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/domain/session.dart';
import 'package:lar_finance/main.dart';

void main() {
  testWidgets('app starts on login without a restored session', (tester) async {
    final controller = AuthController(_SignedOutGateway());
    await controller.initialize();
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pump();

    expect(find.text('Entre no Lar Finance'), findsOneWidget);
    expect(find.text('CASA DE VALORES'), findsNothing);
  });

  testWidgets('app follows the system theme mode', (tester) async {
    await tester.pumpWidget(
      MyApp(authController: AuthController(_SignedOutGateway())),
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });
}

final class _SignedOutGateway implements AuthGateway {
  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<List<DeviceOwnerOption>> loadOwners() => throw UnimplementedError();

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
  Future<void> selectDeviceOwner(String uuid) => throw UnimplementedError();
}
