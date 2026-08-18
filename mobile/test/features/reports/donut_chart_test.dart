import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/reports/domain/reports_models.dart';
import 'package:lar_finance/features/reports/presentation/widgets/donut_chart.dart';

void main() {
  testWidgets(
    'DonutChartWidget renders empty state message when distributions empty',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LarTheme.light,
          home: const Scaffold(
            body: DonutChartWidget(distributions: [], totalExpenseMinor: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhuma despesa no período selecionado.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'DonutChartWidget renders chart with center total and legend items',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final distributions = [
        const CategoryExpenseDistribution(
          categoryUuid: 'cat-1',
          categoryName: 'Alimentação',
          color: '#2F756A',
          totalMinor: 150000,
          percentage: 75.0,
          transactionCount: 5,
        ),
        const CategoryExpenseDistribution(
          categoryUuid: 'cat-2',
          categoryName: 'Lazer',
          color: '#C7A35A',
          totalMinor: 50000,
          percentage: 25.0,
          transactionCount: 2,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: LarTheme.light,
          home: Scaffold(
            body: DonutChartWidget(
              distributions: distributions,
              totalExpenseMinor: 200000,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total Despesas'), findsOneWidget);
      expect(find.text('R\$ 2000,00'), findsOneWidget);
      expect(find.text('Alimentação (75%)'), findsOneWidget);
      expect(find.text('Lazer (25%)'), findsOneWidget);

      // Tapping a legend item updates center text to focus on that category
      await tester.tap(find.text('Alimentação (75%)'));
      await tester.pumpAndSettle();

      expect(find.text('Alimentação'), findsWidgets);
      expect(find.text('R\$ 1500,00'), findsOneWidget);
      expect(find.text('75.0%'), findsOneWidget);
    },
  );
}
