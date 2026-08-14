import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/app/adaptive_shell.dart';
import 'package:lar_finance/core/sync/sync_models.dart' show SyncResult;
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/home/application/home_controller.dart';
import 'package:lar_finance/features/home/data/home_repository.dart';
import 'package:lar_finance/features/home/domain/home_snapshot.dart';
import 'package:lar_finance/features/home/presentation/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await _loadFixedGoldenFont();
    await _loadMaterialIcons();
  });

  for (final fixture in <_GoldenFixture>[
    const _GoldenFixture(
      name: 'mobile claro',
      size: Size(390, 844),
      brightness: Brightness.light,
      platform: TargetPlatform.android,
      file: '../../goldens/home_mobile_light.png',
    ),
    const _GoldenFixture(
      name: 'mobile escuro',
      size: Size(390, 844),
      brightness: Brightness.dark,
      platform: TargetPlatform.android,
      file: '../../goldens/home_mobile_dark.png',
    ),
    const _GoldenFixture(
      name: 'Windows claro',
      size: Size(1366, 768),
      brightness: Brightness.light,
      platform: TargetPlatform.windows,
      file: '../../goldens/home_windows_light.png',
    ),
    const _GoldenFixture(
      name: 'Windows escuro',
      size: Size(1366, 768),
      brightness: Brightness.dark,
      platform: TargetPlatform.windows,
      file: '../../goldens/home_windows_dark.png',
    ),
  ]) {
    testWidgets('Home Casa de Valores ${fixture.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = fixture.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = _GoldenHomeRepository();
      final syncState = SyncState(retry: () async => SyncResult.current)
        ..markCurrent(_syncedAt);
      final controller = HomeController(
        repository: repository,
        syncState: syncState,
        now: () => DateTime(2026, 8, 14, 12),
      );
      addTearDown(controller.dispose);
      final base = fixture.brightness == Brightness.dark
          ? LarTheme.dark
          : LarTheme.light;
      final theme = base.copyWith(
        platform: fixture.platform,
        textTheme: base.textTheme.apply(fontFamily: _goldenFontFamily),
        primaryTextTheme: base.primaryTextTheme.apply(
          fontFamily: _goldenFontFamily,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: AdaptiveShell(
            selectedIndex: 0,
            onSelect: (_) {},
            child: HomeScreen(controller: controller),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(fixture.file),
      );
    });
  }
}

const _goldenFontFamily = 'LarGolden';
const _selfUuid = '20000000-0000-4000-8000-000000000001';
const _spouseUuid = '20000000-0000-4000-8000-000000000002';
final _syncedAt = DateTime(2026, 8, 14, 11);

Future<void> _loadFixedGoldenFont() async {
  final candidates = <String>[
    r'C:\Windows\Fonts\segoeui.ttf',
    '${Platform.environment['FLUTTER_ROOT'] ?? ''}${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts${Platform.pathSeparator}Roboto-Regular.ttf',
  ];
  final file = candidates
      .map(File.new)
      .where((item) => item.existsSync())
      .first;
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  final loader = FontLoader(_goldenFontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _loadMaterialIcons() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\ludso\develop\flutter';
  final file = File(
    '$flutterRoot${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts${Platform.pathSeparator}materialicons-regular.otf',
  );
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

final class _GoldenFixture {
  const _GoldenFixture({
    required this.name,
    required this.size,
    required this.brightness,
    required this.platform,
    required this.file,
  });

  final String name;
  final Size size;
  final Brightness brightness;
  final TargetPlatform platform;
  final String file;
}

final class _GoldenHomeRepository implements HomeRepository {
  @override
  Future<HomeOwnerScopes> readOwnerScopes() async => const HomeOwnerScopes(
    selfScope: OwnerScope.self(_selfUuid),
    spouseScope: OwnerScope.spouse(_spouseUuid),
  );

  @override
  Stream<HomeSnapshot> watchSnapshot(OwnerScope scope, DateTime now) =>
      Stream<HomeSnapshot>.value(
        HomeSnapshot(
          scope: scope,
          balanceMinor: 2486040,
          monthExpenseMinor: 518472,
          upcomingCommitmentMinor: 342000,
          recentTransactions: <HomeTransaction>[
            HomeTransaction(
              uuid: '50000000-0000-4000-8000-000000000001',
              description: 'Supermercado',
              categoryName: 'Alimentação',
              ownerName: 'Conjunto',
              date: DateTime(2026, 8, 14),
              signedAmountMinor: -28640,
            ),
            HomeTransaction(
              uuid: '50000000-0000-4000-8000-000000000002',
              description: 'Salário',
              categoryName: 'Receita',
              ownerName: 'Eu',
              date: DateTime(2026, 8, 13),
              signedAmountMinor: 780000,
            ),
            HomeTransaction(
              uuid: '50000000-0000-4000-8000-000000000003',
              description: 'Energia',
              categoryName: 'Moradia',
              ownerName: 'Esposa',
              date: DateTime(2026, 8, 12),
              signedAmountMinor: -21490,
            ),
          ],
          lastSyncedAt: _syncedAt,
          hasAccountData: true,
        ),
      );
}
