import 'package:flutter/cupertino.dart';
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
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return CupertinoTabBar(
        currentIndex: selectedIndex,
        onTap: onSelect,
        activeColor: Theme.of(context).colorScheme.primary,
        inactiveColor: CupertinoColors.inactiveGray.resolveFrom(context),
        backgroundColor: Theme.of(context).colorScheme.surface,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house),
            activeIcon: Icon(CupertinoIcons.house_fill),
            label: 'Início',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.ellipsis_circle),
            activeIcon: Icon(CupertinoIcons.ellipsis_circle_fill),
            label: 'Mais',
          ),
        ],
      );
    }
    return NavigationBar(
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
}
