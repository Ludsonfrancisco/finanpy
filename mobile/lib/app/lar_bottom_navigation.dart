import 'package:flutter/material.dart';

final class LarBottomNavigation extends StatelessWidget {
  const LarBottomNavigation({
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: onSelect,
    destinations: const <NavigationDestination>[
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Início',
      ),
      NavigationDestination(
        icon: Icon(Icons.more_horiz),
        selectedIcon: Icon(Icons.more_horiz),
        label: 'Mais',
      ),
    ],
  );
}
