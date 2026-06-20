import 'package:flutter/material.dart';
import '../constants/navigation_menu_settings.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;
  late final List<BottomMenuConfig> _activeMenus;

  @override
  void initState() {
    super.initState();
    _activeMenus = activeBottomMenuSettings;
    _currentIndex = _normalizeIndex(widget.initialIndex);
  }

  int _normalizeIndex(int index) {
    if (_activeMenus.isEmpty) {
      return 0;
    }

    if (index < 0 || index >= _activeMenus.length) {
      return 0;
    }

    return index;
  }

  @override
  Widget build(BuildContext context) {
    if (_activeMenus.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No active menu items configured.')),
      );
    }

    final safeIndex = _normalizeIndex(_currentIndex);

    return Scaffold(
      body: _activeMenus[safeIndex].screen,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: _activeMenus
            .map(
              (menu) => BottomNavigationBarItem(
                icon: Icon(menu.icon),
                label: menu.label,
              ),
            )
            .toList(),
      ),
    );
  }
}
