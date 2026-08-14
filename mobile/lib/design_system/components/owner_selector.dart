import 'package:flutter/material.dart';
final class OwnerSelector extends StatelessWidget {
  const OwnerSelector({required this.selected, required this.onSelected, super.key});
  final int selected; final ValueChanged<int> onSelected;
  @override Widget build(BuildContext context) => Semantics(label: 'Visão financeira', child: SegmentedButton<int>(segments: const <ButtonSegment<int>>[ButtonSegment<int>(value: 0, label: Text('Lar')), ButtonSegment<int>(value: 1, label: Text('Eu')), ButtonSegment<int>(value: 2, label: Text('Esposa'))], selected: <int>{selected}, onSelectionChanged: (selection) => onSelected(selection.first), showSelectedIcon: false));
}
