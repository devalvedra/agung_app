import 'package:flutter/material.dart';

import '../screens/checker_screen.dart';
import '../screens/home_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/pickup_item_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/tracking_screen.dart';

class BottomMenuConfig {
  final String id;
  final String label;
  final IconData icon;
  final Widget screen;
  final bool enabled;

  const BottomMenuConfig({
    required this.id,
    required this.label,
    required this.icon,
    required this.screen,
    required this.enabled,
  });
}

const List<BottomMenuConfig> bottomMenuSettings = [
  BottomMenuConfig(
    id: 'home',
    label: 'Home',
    icon: Icons.home,
    screen: HomeScreen(),
    enabled: true,
  ),
  BottomMenuConfig(
    id: 'pickup',
    label: 'Pickup',
    icon: Icons.qr_code_scanner,
    screen: PickupItemScreen(),
    enabled: true,
  ),
  BottomMenuConfig(
    id: 'tracking',
    label: 'Tracking',
    icon: Icons.location_on,
    screen: TrackingScreen(),
    enabled: true,
  ),
  BottomMenuConfig(
    id: 'orders',
    label: 'Orders',
    icon: Icons.shopping_bag,
    screen: OrdersScreen(),
    enabled: false,
  ),
  BottomMenuConfig(
    id: 'checker',
    label: 'Checker',
    icon: Icons.fact_check,
    screen: CheckerScreen(),
    enabled: true,
  ),
  BottomMenuConfig(
    id: 'profile',
    label: 'Profile',
    icon: Icons.person,
    screen: ProfileScreen(),
    enabled: true,
  ),
];

List<BottomMenuConfig> get activeBottomMenuSettings {
  return bottomMenuSettings.where((menu) => menu.enabled).toList();
}
