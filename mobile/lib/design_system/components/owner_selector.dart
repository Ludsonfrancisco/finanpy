import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
      label: 'Visão financeira',
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: ios ? 44 : 48),
        child: ios
            ? CupertinoSlidingSegmentedControl<int>(
                groupValue: selected,
                proportionalWidth: true,
                thumbColor: Theme.of(context).colorScheme.secondary,
                children: const <int, Widget>{
                  0: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Lar'),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Eu'),
                  ),
                  2: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Esposa'),
                  ),
                },
                onValueChanged: (value) {
                  if (value != null) onSelected(value);
                },
              )
            : SegmentedButton<int>(
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 0, label: Text('Lar')),
                  ButtonSegment<int>(value: 1, label: Text('Eu')),
                  ButtonSegment<int>(value: 2, label: Text('Esposa')),
                ],
                selected: <int>{selected},
                onSelectionChanged: (selection) => onSelected(selection.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (!states.contains(WidgetState.selected)) return null;
                    return Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF4B4027)
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
