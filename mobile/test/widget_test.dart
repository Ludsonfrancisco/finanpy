import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/main.dart';

void main() {
  testWidgets('app opens the Casa de Valores shell', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.pump();

    expect(find.text('CASA DE VALORES'), findsOneWidget);
    expect(find.text('Dados ainda não sincronizados'), findsOneWidget);
  });
}
