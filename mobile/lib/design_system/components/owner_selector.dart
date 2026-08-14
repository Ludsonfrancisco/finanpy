import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../lar_colors.dart';

final class OwnerSelector extends StatelessWidget {
  const OwnerSelector({
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Semantics(
      container: true,
      label: 'Visão financeira',
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: ios ? 44 : 48),
        child: ios
            ? CupertinoSlidingSegmentedControl<int>(
                groupValue: selected,
                proportionalWidth: true,
                thumbColor: Theme.of(context).brightness == Brightness.dark
                    ? LarColors.champagneSelectedDark
                    : Theme.of(context).colorScheme.secondary,
                children: <int, Widget>{
                  0: _ownerLabel('Lar', 0, selected),
                  1: _ownerLabel('Eu', 1, selected),
                  2: _ownerLabel('Esposa', 2, selected),
                },
                onValueChanged: (value) {
                  if (value != null) onSelected(value);
                },
              )
            : SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: 0,
                    label: _ownerLabel('Lar', 0, selected),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: _ownerLabel('Eu', 1, selected),
                  ),
                  ButtonSegment<int>(
                    value: 2,
                    label: _ownerLabel('Esposa', 2, selected),
                  ),
                ],
                selected: <int>{selected},
                onSelectionChanged: (selection) => onSelected(selection.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (!states.contains(WidgetState.selected)) return null;
                    return Theme.of(context).brightness == Brightness.dark
                        ? LarColors.champagneSelectedDark
                        : const Color(0xFFD1B16C);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (!states.contains(WidgetState.selected)) return null;
                    return Theme.of(context).colorScheme.onSurface;
                  }),
                ),
              ),
      ),
    );
  }
}

Widget _ownerLabel(String label, int value, int selected) => Semantics(
  container: true,
  label: value == selected ? '$label, selecionado' : label,
  selected: value == selected,
  child: ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(label),
    ),
  ),
);
