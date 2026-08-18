import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/reports_models.dart';

final class MonthlyBarChartWidget extends StatefulWidget {
  const MonthlyBarChartWidget({required this.monthlyFlows, super.key});

  final List<MonthlyFlowData> monthlyFlows;

  @override
  State<MonthlyBarChartWidget> createState() => _MonthlyBarChartWidgetState();
}

final class _MonthlyBarChartWidgetState extends State<MonthlyBarChartWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void didUpdateWidget(MonthlyBarChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.monthlyFlows != widget.monthlyFlows) {
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    if (widget.monthlyFlows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(LarSpacing.xl),
          child: Text(
            'Sem dados de fluxo mensal.',
            style: text.bodyMedium?.copyWith(
              color: isDark ? const Color(0xFF8D958D) : const Color(0xFF8B8A80),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Legenda do gráfico
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _legendItem('Receitas', LarColors.mineral, text),
            const SizedBox(width: LarSpacing.md),
            _legendItem('Despesas', LarColors.danger, text),
          ],
        ),
        const SizedBox(height: LarSpacing.md),
        SizedBox(
          height: 180,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              return CustomPaint(
                size: const Size(double.infinity, 180),
                painter: _MonthlyBarChartPainter(
                  monthlyFlows: widget.monthlyFlows,
                  progress: _animation.value,
                  isDark: isDark,
                  textColor: isDark
                      ? const Color(0xFF8D958D)
                      : const Color(0xFF8B8A80),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legendItem(String label, Color color, TextTheme text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: text.labelSmall),
      ],
    );
  }
}

final class _MonthlyBarChartPainter extends CustomPainter {
  _MonthlyBarChartPainter({
    required this.monthlyFlows,
    required this.progress,
    required this.isDark,
    required this.textColor,
  });

  final List<MonthlyFlowData> monthlyFlows;
  final double progress;
  final bool isDark;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (monthlyFlows.isEmpty) return;

    final chartHeight = size.height - 28.0; // Espaço para rótulos inferiores
    final chartWidth = size.width;

    // Encontrar o valor máximo para escala
    int maxVal = 1;
    for (final flow in monthlyFlows) {
      if (flow.incomeMinor > maxVal) maxVal = flow.incomeMinor;
      if (flow.expenseMinor > maxVal) maxVal = flow.expenseMinor;
    }

    final groupWidth = chartWidth / monthlyFlows.length;
    final barWidth = math.max(6.0, math.min(16.0, (groupWidth - 16) / 2));

    // Linhas de grade horizontais sutis
    final gridPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, chartHeight),
      Offset(chartWidth, chartHeight),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, chartHeight / 2),
      Offset(chartWidth, chartHeight / 2),
      gridPaint,
    );

    final incomePaint = Paint()
      ..color = LarColors.mineral
      ..style = PaintingStyle.fill;

    final expensePaint = Paint()
      ..color = LarColors.danger
      ..style = PaintingStyle.fill;

    for (int i = 0; i < monthlyFlows.length; i++) {
      final flow = monthlyFlows[i];
      final groupCenterX = (i * groupWidth) + (groupWidth / 2);

      final incomeHeight = (flow.incomeMinor / maxVal) * chartHeight * progress;
      final expenseHeight =
          (flow.expenseMinor / maxVal) * chartHeight * progress;

      final incomeX = groupCenterX - barWidth - 2;
      final expenseX = groupCenterX + 2;

      // Barra de Receita
      if (incomeHeight > 0) {
        final rRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            incomeX,
            chartHeight - incomeHeight,
            barWidth,
            incomeHeight,
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(rRect, incomePaint);
      }

      // Barra de Despesa
      if (expenseHeight > 0) {
        final rRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            expenseX,
            chartHeight - expenseHeight,
            barWidth,
            expenseHeight,
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(rRect, expensePaint);
      }

      // Rótulo do Mês abaixo da barra
      final textSpan = TextSpan(
        text: flow.monthLabel,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(groupCenterX - (textPainter.width / 2), chartHeight + 8),
      );
    }
  }

  @override
  bool shouldRepaint(_MonthlyBarChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.monthlyFlows != monthlyFlows ||
        oldDelegate.isDark != isDark;
  }
}
