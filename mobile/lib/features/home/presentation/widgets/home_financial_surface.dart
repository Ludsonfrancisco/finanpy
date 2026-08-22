import 'package:flutter/material.dart';

import '../../../../design_system/lar_radius.dart';
import '../../../../design_system/lar_spacing.dart';

final class HomeFinancialSurface extends StatelessWidget {
  const HomeFinancialSurface({
    required this.child,
    this.accentColor,
    this.padding = const EdgeInsets.all(LarSpacing.lg),
    super.key,
  });

  final Widget child;
  final Color? accentColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = accentColor ?? theme.dividerColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: border.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(LarRadius.lg),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
