import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/features/auth/application/auth_controller.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/domain/session.dart';
import 'package:lar_finance/features/imports/data/import_repository.dart';
import 'package:lar_finance/features/imports/data/ofx_file_picker.dart';
import 'package:lar_finance/features/imports/domain/import_preview.dart';
import 'package:lar_finance/main.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('an authenticated device opens the import route', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Importar OFX'), findsOneWidget);

    await tester.tap(find.text('Importar OFX'));
    await tester.pumpAndSettle();

    expect(find.text('Importação OFX'), findsOneWidget);
  });

  testWidgets('a signed out device cannot reach the import route', (
    tester,
  ) async {
    final controller = AuthController(_SignedOutGateway());
    await controller.initialize();
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pumpAndSettle();

    controller.state;
    final router = (tester.widget<MyApp>(find.byType(MyApp))).router;
    router.go('/more/import-ofx');
    await tester.pumpAndSettle();

    expect(find.text('Entre no Lar Finance'), findsOneWidget);
    expect(find.text('Importação OFX'), findsNothing);
  });

  testWidgets('the import entry can be reached and activated by keyboard', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    final entry = find.widgetWithText(OutlinedButton, 'Importar OFX');
    await _focusOn(tester, entry);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Importação OFX'), findsOneWidget);
  });

  testWidgets('the focus lost to the file dialog keeps the selection alive', (
    tester,
  ) async {
    // The native dialog steals the focus, which drives the app through
    // inactive/resumed and rebuilds the route. That must not restart the
    // import state and swallow the file the person chose.
    final picked = Completer<SelectedOfx?>();
    final repository = _FakeImportRepository(null);
    final controller = AuthController(_AuthenticatedGateway());
    await controller.initialize();

    await tester.pumpWidget(
      MyApp(
        authController: controller,
        importRepository: repository,
        ofxFilePicker: _DeferredPicker(() => picked.future),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar OFX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selecionar arquivo OFX'));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    picked.complete(SelectedOfx(Uint8List.fromList(const <int>[79, 70, 88])));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('Nenhum arquivo selecionado'), findsNothing);
  });

  testWidgets('leaving during an upload does not start a second one', (
    tester,
  ) async {
    final upload = Completer<ImportPreview>();
    final repository = _FakeImportRepository(upload.future);
    await _pumpApp(tester, repository: repository);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar OFX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selecionar arquivo OFX'));
    await tester.pump();

    final router = (tester.widget<MyApp>(find.byType(MyApp))).router;
    router.go('/more');
    await tester.pumpAndSettle();
    upload.complete(_preview());
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('Sair'), findsOneWidget);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  _FakeImportRepository? repository,
}) async {
  final controller = AuthController(_AuthenticatedGateway());
  await controller.initialize();
  await tester.pumpWidget(
    MyApp(
      authController: controller,
      importRepository: repository ?? _FakeImportRepository(null),
      ofxFilePicker: _AlwaysSelectingPicker(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _focusOn(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (_isFocused(tester, target)) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('The target never received the keyboard focus.');
}

bool _isFocused(WidgetTester tester, Finder target) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final element = tester.element(target);
  var found = false;
  context.visitAncestorElements((ancestor) {
    if (ancestor == element) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

ImportPreview _preview() => ImportPreview(
  uuid: '00000000-0000-4000-8000-000000000000',
  status: ImportBatchStatus.previewReady,
  productType: ImportProductType.bankAccount,
  statementStart: DateTime.utc(2026, 8, 1),
  statementEnd: DateTime.utc(2026, 8, 12),
  expiresAt: DateTime.utc(2026, 8, 16, 12),
  accountUuid: '00000000-0000-4000-8000-000000000001',
  financialOwnerUuid: '00000000-0000-4000-8000-000000000002',
  createdCount: 0,
  duplicateCount: 0,
  warningCount: 0,
  recordCount: 0,
  pendingCount: 0,
  incomeTotalMinor: 0,
  expenseTotalMinor: 0,
  isRepeatedFile: false,
  records: const <ImportRecordPreview>[],
  nextCursor: null,
);

final class _DeferredPicker implements OfxFilePicker {
  const _DeferredPicker(this._pick);

  final Future<SelectedOfx?> Function() _pick;

  @override
  Future<SelectedOfx?> pick() => _pick();
}

final class _AlwaysSelectingPicker implements OfxFilePicker {
  @override
  Future<SelectedOfx?> pick() async =>
      SelectedOfx(Uint8List.fromList(const <int>[79, 70, 88]));
}

final class _FakeImportRepository implements ImportRepository {
  _FakeImportRepository(this._upload);

  final Future<ImportPreview>? _upload;
  int createCalls = 0;

  @override
  Future<ImportPreview> createPreview(SelectedOfx file) {
    createCalls++;
    return _upload ?? Future<ImportPreview>.value(_preview());
  }

  @override
  Future<ImportPreview> readPreview(
    String batchUuid, {
    int? after,
    int? limit,
  }) async => _preview();

  @override
  Future<ImportPreview> confirmPreview(String batchUuid) async => _preview();

  @override
  Future<ImportPreview> cancelPreview(String batchUuid) async => _preview();
}

final class _AuthenticatedGateway implements AuthGateway {
  static const _deviceUuid = '11111111-1111-4111-8111-111111111111';
  static const _sessionIdentity = 'synthetic-session-identity';

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
  Future<DateTime?> readLastSyncAt() async => DateTime.utc(2026, 8, 15, 12);

  @override
  Future<String?> readSelectedOwnerUuid() async =>
      '22222222-2222-4222-8222-222222222222';

  @override
  Future<StoredTokens?> readSession() async => StoredTokens(
    accessToken: 'access',
    accessExpiresAt: DateTime.utc(2030),
    refreshToken: 'refresh',
    refreshExpiresAt: DateTime.utc(2030, 2),
    deviceUuid: _deviceUuid,
    sessionIdentity: _sessionIdentity,
  );

  @override
  Future<String?> readSyncedDeviceUuid() async => _deviceUuid;

  @override
  Future<String?> readSyncedSessionIdentity() async => _sessionIdentity;

  @override
  Future<void> selectDeviceOwner(String uuid) async {}
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
  Future<String?> readSyncedSessionIdentity() async => null;

  @override
  Future<void> selectDeviceOwner(String uuid) async {}
}
