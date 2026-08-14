import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/adaptive_shell.dart';
import 'package:lar_finance/design_system/lar_theme.dart';

void main() {
  test('golden environment does not paint text layout diagnostics', () {
    expect(debugPaintBaselinesEnabled, isFalse);
    expect(debugPaintTextLayoutBoxes, isFalse);
  });

  testWidgets('golden fixture contains no test-font text artifacts', (
    tester,
  ) async {
    await tester.pumpWidget(_goldenApp(LarTheme.dark));
    expect(find.byType(Text), findsNothing);
    expect(find.byType(Icon), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveShell(
          selectedIndex: 0,
          onSelect: (_) {},
          child: const ColoredBox(color: Color(0xFF091311)),
        ),
      ),
    );
  }

  testWidgets('390 by 844 uses mobile navigation', (tester) async {
    await pumpShell(tester, const Size(390, 844));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('iOS usa tab bar Cupertino e mantém interação nativa', (
    tester,
  ) async {
    var selected = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: LarTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: AdaptiveShell(
          selectedIndex: selected,
          onSelect: (value) => selected = value,
          child: const SizedBox.expand(),
        ),
      ),
    );

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Mais'));
    await tester.pump();
    expect(selected, 1);
  });

  testWidgets('1366 by 768 uses desktop sidebar without bottom navigation', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1366, 768));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Casa de Valores desktop shell is stable in dark mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_goldenApp(LarTheme.dark));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/casa_de_valores_dark.png'),
    );
  });

  testWidgets('Casa de Valores desktop shell is stable in light mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_goldenApp(LarTheme.light));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/casa_de_valores_light.png'),
    );
  });
}

Widget _goldenApp(ThemeData theme) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  home: Builder(
    builder: (context) => Row(
      children: <Widget>[
        ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: const SizedBox(
            width: 232,
            child: Column(
              children: <Widget>[
                SizedBox(height: 84),
                Icon(Icons.home_outlined, size: 28),
                SizedBox(height: 28),
                Icon(Icons.more_horiz, size: 28),
              ],
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(width: 280, height: 12),
                  SizedBox(height: 36),
                  Row(
                    children: <Widget>[
                      Icon(Icons.cloud_off_outlined, size: 22),
                      SizedBox(width: 16),
                      Icon(Icons.visibility_off_outlined, size: 22),
                    ],
                  ),
                  SizedBox(height: 48),
                  SizedBox(width: 420, height: 1),
                  SizedBox(height: 20),
                  SizedBox(width: 560, height: 96),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  ),
);
