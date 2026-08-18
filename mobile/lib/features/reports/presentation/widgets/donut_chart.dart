import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../domain/reports_models.dart';

final class DonutChartWidget extends StatefulWidget {
  const DonutChartWidget({
    required this.distributions,
    required this.totalExpenseMinor,
    super.key,
  });

  final List<CategoryExpenseDistribution> distributions;
  final int totalExpenseMinor;

  @override
  State<DonutChartWidget> createState() => _DonutChartWidgetState();
}

final class _DonutChartWidgetState extends State<DonutChartWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _animation;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void didUpdateWidget(DonutChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalExpenseMinor != widget.totalExpenseMinor ||
        oldWidget.distributions.length != widget.distributions.length) {
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatReais(int minorUnits) {
    final double value = minorUnits / 100.0;
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    if (widget.distributions.isEmpty || widget.totalExpenseMinor == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(LarSpacing.xl),
          child: Text(
            'Nenhuma despesa no período selecionado.',
            style: text.bodyMedium?.copyWith(
              color: isDark ? const Color(0xFF8D958D) : const Color(0xFF8B8A80),
            ),
          ),
        ),
      );
    }

    final highlightedCat =
        _hoveredIndex != null && _hoveredIndex! < widget.distributions.length
        ? widget.distributions[_hoveredIndex!]
        : null;

    final displayLabel = highlightedCat != null
        ? highlightedCat.categoryName
        : 'Total Despesas';
    final displayAmount = highlightedCat != null
        ? _formatReais(highlightedCat.totalMinor)
        : _formatReais(widget.totalExpenseMinor);
    final displayPercent = highlightedCat != null
        ? '${highlightedCat.percentage.toStringAsFixed(1)}%'
        : null;

    return Column(
      children: [
        SizedBox(
          height: 220,
          width: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _animation,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(220, 220),
                    painter: _DonutChartPainter(
                      distributions: widget.distributions,
                      progress: _animation.value,
                      highlightedIndex: _hoveredIndex,
                      isDark: isDark,
                    ),
                  );
                },
              ),
              // Conteúdo central
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayLabel,
                    style: text.labelSmall?.copyWith(
                      color: isDark
                          ? const Color(0xFF8D958D)
                          : const Color(0xFF8B8A80),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayAmount,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E2621),
                    ),
                  ),
                  if (displayPercent != null) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: LarColors.mineral.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        displayPercent,
                        style: text.labelSmall?.copyWith(
                          color: LarColors.mineral,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: LarSpacing.md),
        // Legenda interativa compacta
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List.generate(math.min(6, widget.distributions.length), (
            i,
          ) {
            final cat = widget.distributions[i];
            final isHovered = _hoveredIndex == i;
            return InkWell(
              onTap: () {
                setState(() {
                  _hoveredIndex = _hoveredIndex == i ? null : i;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isHovered
                      ? (isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.05))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _parseColor(cat.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${cat.categoryName} (${cat.percentage.toStringAsFixed(0)}%)',
                      style: text.labelSmall?.copyWith(
                        fontWeight: isHovered
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

Color _parseColor(String hex) {
  try {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return LarColors.mineral;
  }
}

final class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({
    required this.distributions,
    required this.progress,
    required this.highlightedIndex,
    required this.isDark,
  });

  final List<CategoryExpenseDistribution> distributions;
  final double progress;
  final int? highlightedIndex;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 24.0;
    final arcRadius = radius - strokeWidth / 2;

    // Fundo da trilha
    final trackPaint = Paint()
      ..color = isDark ? const Color(0xFF222C27) : const Color(0xFFE4DFD5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, arcRadius, trackPaint);

    double startAngle = -math.pi / 2;
    final totalProgressAngle = 2 * math.pi * progress;

    for (int i = 0; i < distributions.length; i++) {
      final item = distributions[i];
      final sweepAngle = (item.percentage / 100.0) * 2 * math.pi;
      final effectiveSweep = math.min(
        sweepAngle,
        math.max(0.0, totalProgressAngle - (startAngle + math.pi / 2)),
      );

      if (effectiveSweep > 0) {
        final isHighlighted = highlightedIndex == i;
        final paint = Paint()
          ..color = _parseColor(item.color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlighted ? strokeWidth + 6.0 : strokeWidth
          ..strokeCap = StrokeCap.butt;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: arcRadius),
          startAngle,
          effectiveSweep,
          false,
          paint,
        );
      }

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(_DonutChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.highlightedIndex != highlightedIndex ||
        oldDelegate.distributions != distributions;
  }
}
