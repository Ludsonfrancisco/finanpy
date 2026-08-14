import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/design_system/components/financial_amount.dart';
import 'package:lar_finance/design_system/components/owner_selector.dart';
import 'package:lar_finance/design_system/components/sync_status.dart';

void main() {
  testWidgets('financial amount uses tabular figures and hides only digits', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FinancialAmount(minorUnits: 2486040, hidden: false),
      ),
    );
    expect(find.text('R\$\u00a024.860,40'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: FinancialAmount(minorUnits: 2486040, hidden: true),
      ),
    );
    expect(find.text('R\$\u00a0••••••'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(FinancialAmount)).label,
      'Valor financeiro oculto',
    );
  });

  testWidgets('owner selector exposes exactly the approved household views', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: OwnerSelector(selected: 0, onSelected: (_) {})),
    );

    expect(find.text('Lar'), findsOneWidget);
    expect(find.text('Eu'), findsOneWidget);
    expect(find.text('Esposa'), findsOneWidget);
    expect(find.text('Conjunto'), findsNothing);
  });

  testWidgets('owner selector uses the native iOS segmented affordance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: OwnerSelector(selected: 0, onSelected: (_) {}),
      ),
    );

    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsNothing);
  });

  testWidgets(
    'financial amount formats signed minor units without losing cents',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: <Widget>[
              FinancialAmount(
                minorUnits: -28640,
                hidden: false,
                showPositiveSign: true,
              ),
              FinancialAmount(
                minorUnits: 780000,
                hidden: false,
                showPositiveSign: true,
              ),
            ],
          ),
        ),
      );

      expect(find.text('-R\$\u00a0286,40'), findsOneWidget);
      expect(find.text('+R\$\u00a07.800,00'), findsOneWidget);
    },
  );

  testWidgets('sync status communicates state without financial data', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SyncStatusView(
          data: SyncStatusData(
            state: SyncVisualState.offline,
            lastSuccessAt: null,
          ),
        ),
      ),
    );

    expect(find.text('Offline'), findsOneWidget);
    expect(tester.getSemantics(find.byType(SyncStatusView)).label, 'Offline');
  });
}
