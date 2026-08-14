import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/main.dart';

void main() {
  testWidgets('app opens the Casa de Valores shell', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.pump();

    expect(find.text('CASA DE VALORES'), findsOneWidget);
    expect(find.text('Dados ainda não sincronizados'), findsOneWidget);
  });

  testWidgets('app follows the system theme mode', (tester) async {
    await tester.pumpWidget(MyApp());
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });
}
