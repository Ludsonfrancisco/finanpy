import 'package:flutter/material.dart';

final class LarSidebar extends StatelessWidget {
  const LarSidebar({
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => NavigationRail(
    extended: true,
    minExtendedWidth: 232,
    selectedIndex: selectedIndex,
    onDestinationSelected: onSelect,
    leading: const Padding(
      padding: EdgeInsets.fromLTRB(20, 28, 20, 32),
      child: Text('LAR\nFINANCE', style: TextStyle(letterSpacing: 1.8)),
    ),
    destinations: const <NavigationRailDestination>[
      NavigationRailDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: Text('Início'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: Text('Movimentações'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.account_balance_outlined),
        selectedIcon: Icon(Icons.account_balance),
        label: Text('Contas'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.more_horiz),
        selectedIcon: Icon(Icons.more_horiz),
        label: Text('Mais'),
      ),
    ],
  );
}
