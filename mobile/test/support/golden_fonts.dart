import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Family used by goldens so the rendering never depends on a system font.
const goldenFontFamily = 'LarGolden';

/// Loads the fixed text and icon fonts a golden run needs.
Future<void> loadGoldenFonts() async {
  await _loadFixedGoldenFont();
  await _loadMaterialIcons();
  await _loadCupertinoIcons();
}

/// Applies the fixed font family to a Lar theme for a platform and brightness.
ThemeData goldenTheme({
  required ThemeData base,
  required TargetPlatform platform,
  required Brightness brightness,
}) => base.copyWith(
  platform: platform,
  cupertinoOverrideTheme: CupertinoThemeData(
    brightness: brightness,
    primaryColor: base.colorScheme.primary,
    textTheme: const CupertinoTextThemeData(
      textStyle: TextStyle(fontFamily: goldenFontFamily),
      tabLabelTextStyle: TextStyle(fontFamily: goldenFontFamily, fontSize: 10),
    ),
  ),
  textTheme: base.textTheme.apply(fontFamily: goldenFontFamily),
  primaryTextTheme: base.primaryTextTheme.apply(fontFamily: goldenFontFamily),
);

Future<void> _loadFixedGoldenFont() async {
  final file = _flutterMaterialFont('Roboto-Regular.ttf');
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  final loader = FontLoader(goldenFontFamily)
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
