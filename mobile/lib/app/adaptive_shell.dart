import 'package:flutter/material.dart';
import 'lar_bottom_navigation.dart';
import 'lar_sidebar.dart';
abstract final class LarBreakpoints { static const desktop = 900.0; }
final class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.child, required this.selectedIndex, required this.onSelect, super.key});
  final Widget child; final int selectedIndex; final ValueChanged<int> onSelect;
  @override Widget build(BuildContext context) { final desktop = MediaQuery.sizeOf(context).width >= LarBreakpoints.desktop; return desktop ? Row(children: <Widget>[LarSidebar(selectedIndex: selectedIndex, onSelect: onSelect), Expanded(child: child)]) : Scaffold(body: child, bottomNavigationBar: LarBottomNavigation(selectedIndex: selectedIndex, onSelect: onSelect)); }
}
