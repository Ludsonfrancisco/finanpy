import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/adaptive_shell.dart';
import 'package:lar_finance/design_system/lar_theme.dart';

void main() {
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

  testWidgets('1366 by 768 uses desktop sidebar without bottom navigation', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1366, 768));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Casa de Valores desktop shell is stable in dark mode', (tester) async {
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

  testWidgets('Casa de Valores desktop shell is stable in light mode', (tester) async {
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
  home: AdaptiveShell(
    selectedIndex: 0,
    onSelect: (_) {},
    child: Builder(
      builder: (context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Text('CASA DE VALORES\n\nInício\n\nDados ainda não sincronizados'),
        ),
      ),
    ),
  ),
);
