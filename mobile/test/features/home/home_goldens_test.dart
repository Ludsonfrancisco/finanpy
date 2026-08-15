import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
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
    await _loadCupertinoIcons();
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
      name: 'iOS claro',
      size: Size(390, 844),
      brightness: Brightness.light,
      platform: TargetPlatform.iOS,
      file: '../../goldens/home_ios_light.png',
    ),
    const _GoldenFixture(
      name: 'iOS escuro',
      size: Size(390, 844),
      brightness: Brightness.dark,
      platform: TargetPlatform.iOS,
      file: '../../goldens/home_ios_dark.png',
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
        timerFactory: (duration, callback) => _GoldenTimer(),
      );
      addTearDown(controller.dispose);
      final base = fixture.brightness == Brightness.dark
          ? LarTheme.dark
          : LarTheme.light;
      final theme = base.copyWith(
        platform: fixture.platform,
        cupertinoOverrideTheme: CupertinoThemeData(
          brightness: fixture.brightness,
          primaryColor: base.colorScheme.primary,
          textTheme: const CupertinoTextThemeData(
            textStyle: TextStyle(fontFamily: _goldenFontFamily),
            tabLabelTextStyle: TextStyle(
              fontFamily: _goldenFontFamily,
              fontSize: 10,
            ),
          ),
        ),
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
    }, tags: 'golden');
  }
}

const _goldenFontFamily = 'LarGolden';
const _selfUuid = '20000000-0000-4000-8000-000000000001';
const _spouseUuid = '20000000-0000-4000-8000-000000000002';
final _syncedAt = DateTime(2026, 8, 14, 11);

Future<void> _loadFixedGoldenFont() async {
  final file = _flutterMaterialFont('Roboto-Regular.ttf');
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  final loader = FontLoader(_goldenFontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _loadMaterialIcons() async {
  final file = _flutterMaterialFont('materialicons-regular.otf');
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _loadCupertinoIcons() async {
  final file = _packageAsset(
    packageName: 'cupertino_icons',
    assetPath: 'assets/CupertinoIcons.ttf',
  );
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  final effectiveFamily = const TextStyle(
    fontFamily: CupertinoIcons.iconFont,
    package: CupertinoIcons.iconFontPackage,
  ).fontFamily!;
  final loader = FontLoader(effectiveFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

File _flutterMaterialFont(String name) {
  final flutterRoot = _packageRoot('flutter').parent.parent;
  final materialFonts = Directory(
    '${flutterRoot.path}${Platform.pathSeparator}bin'
    '${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts'
    '${Platform.pathSeparator}material_fonts',
  );
  final matches = materialFonts
      .listSync()
      .whereType<File>()
      .where(
        (candidate) =>
            candidate.uri.pathSegments.last.toLowerCase() == name.toLowerCase(),
      )
      .toList();
  if (matches.length != 1) {
    throw StateError('Flutter golden font not found: $name');
  }
  return matches.single;
}

File _packageAsset({required String packageName, required String assetPath}) {
  final root = _packageRoot(packageName);
  final file = File.fromUri(root.uri.resolve(assetPath));
  if (!file.existsSync()) {
    throw StateError('Package asset not found: ${file.path}');
  }
  return file;
}

Directory _packageRoot(String packageName) {
  final packageConfig = File('.dart_tool/package_config.json');
  final decoded = jsonDecode(packageConfig.readAsStringSync());
  final packages = (decoded as Map<String, Object?>)['packages'];
  if (packages is! List) {
    throw StateError('Invalid Dart package configuration.');
  }
  final package = packages.cast<Map>().singleWhere(
    (candidate) => candidate['name'] == packageName,
  );
  final rootUri = package['rootUri'];
  if (rootUri is! String) {
    throw StateError('Package $packageName has no root URI.');
  }
  final normalizedRootUri = rootUri.endsWith('/') ? rootUri : '$rootUri/';
  final resolvedRoot = packageConfig.parent.uri.resolve(normalizedRootUri);
  final directory = Directory.fromUri(resolvedRoot);
  if (!directory.existsSync()) {
    throw StateError('Package root not found: $packageName');
  }
  return directory;
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
              type: HomeTransactionType.expense,
              signedAmountMinor: -28640,
            ),
            HomeTransaction(
              uuid: '50000000-0000-4000-8000-000000000002',
              description: 'Salário',
              categoryName: 'Receita',
              ownerName: 'Eu',
              date: DateTime(2026, 8, 13),
              type: HomeTransactionType.income,
              signedAmountMinor: 780000,
            ),
            HomeTransaction(
              uuid: '50000000-0000-4000-8000-000000000003',
              description: 'Energia',
              categoryName: 'Moradia',
              ownerName: 'Esposa',
              date: DateTime(2026, 8, 12),
              type: HomeTransactionType.expense,
              signedAmountMinor: -21490,
            ),
          ],
          lastSyncedAt: _syncedAt,
          hasAccountData: true,
        ),
      );
}

final class _GoldenTimer implements Timer {
  @override
  bool get isActive => true;

  @override
  int get tick => 0;

  @override
  void cancel() {}
}
