import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/design_system/components/financial_amount.dart';
import 'package:lar_finance/design_system/components/owner_selector.dart';

void main() {
  testWidgets('hidden financial values expose no digits through semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FinancialAmount(minorUnits: 2486040, hidden: true),
      ),
    );

    final semantics = tester.getSemantics(find.byType(FinancialAmount));
    expect(semantics.label, 'Valor oculto');
    expect(semantics.label, isNot(contains(RegExp(r'\d'))));
  });

  testWidgets('owner selector announces the selected household view', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: OwnerSelector(selected: 1, onSelected: (_) {})),
    );

    expect(find.bySemanticsLabel('Eu, selecionado'), findsOneWidget);
  });
}
