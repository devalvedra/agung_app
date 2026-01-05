import 'dart:developer';

import 'package:get/get.dart';

/// Controller to persist scanned items globally across the app
///
/// Scanned item format example:
/// ```dart
/// {
///   'invoice_code': 'INV001',           // Invoice number
///   'route_code': 'A',                  // Route identifier
///   'drop_point_code': 'T-001',         // Drop point code
///   'num_of_items': 'B',                // Total items category (A, B, C, etc.)
///   'item_size': '2',                   // Size category (1, 2, 3, etc.)
///   'num_of_items_per_size': '5',       // Number of items for this size
///   'index': '00001',                   // Unique item index
///   'full_code': 'INV001|A|T-001|B|2|5|00001',  // Full scanned code
///   'scanned_at': '2026-01-03T10:30:00', // Timestamp when scanned
///   'drop_point_name': 'Toko ABC',      // Optional: drop point name
/// }
/// ```
///
/// To manually add items in debug mode:
/// ```dart
/// final controller = Get.find<ScannedItemsController>();
/// controller.addScannedItem({
///   'invoice_code': 'INV001',
///   'route_code': 'A',
///   'drop_point_code': 'T-001',
///   'num_of_items': 'B',
///   'item_size': '2',
///   'num_of_items_per_size': '5',
///   'index': '00001',
///   'full_code': 'INV001|A|T-001|B|2|5|00001',
///   'scanned_at': DateTime.now().toIso8601String(),
/// });
/// ```
class ScannedItemsController extends GetxController {
  // All scanned items across all sessions
  final RxList<Map<String, String>> masterItemsList =
      <Map<String, String>>[].obs;

  // Items grouped by drop point code
  final RxMap<String, List<Map<String, String>>> itemsByDropPoint =
      <String, List<Map<String, String>>>{}.obs;

  // Items grouped by route code (for Kendaraan)
  final RxMap<String, List<Map<String, String>>> itemsByRoute =
      <String, List<Map<String, String>>>{}.obs;

  /// Add a single scanned item
  void addScannedItem(Map<String, String> item) {
    // Add timestamp if not present
    if (!item.containsKey('scanned_at')) {
      item['scanned_at'] = DateTime.now().toIso8601String();
    }

    masterItemsList.add(item);

    // Group by drop point
    final dropPointCode = item['drop_point_code'] ?? '';
    if (dropPointCode.isNotEmpty) {
      if (!itemsByDropPoint.containsKey(dropPointCode)) {
        itemsByDropPoint[dropPointCode] = [];
      }
      itemsByDropPoint[dropPointCode]!.add(item);
    }

    // Group by route
    final routeCode = item['route_code'] ?? '';
    if (routeCode.isNotEmpty) {
      if (!itemsByRoute.containsKey(routeCode)) {
        itemsByRoute[routeCode] = [];
      }
      itemsByRoute[routeCode]!.add(item);
    }
  }

  /// Add multiple scanned items at once
  void addScannedItems(List<Map<String, String>> items) {
    for (final item in items) {
      addScannedItem(item);
    }
    log(masterItemsList.toString());
  }

  /// Remove items for a specific drop point (when delivered)
  void removeItemsForDropPoint(String dropPointCode) {
    // Remove from all scanned items
    masterItemsList.removeWhere(
      (item) => item['drop_point_code'] == dropPointCode,
    );

    // Remove from grouped items
    itemsByDropPoint.remove(dropPointCode);
  }

  /// Get items for a specific drop point
  List<Map<String, String>> getItemsForDropPoint(String dropPointCode) {
    return itemsByDropPoint[dropPointCode] ?? [];
  }

  /// Get items for a specific route
  List<Map<String, String>> getItemsForRoute(String routeCode) {
    return itemsByRoute[routeCode] ?? [];
  }

  /// Get items for a specific invoice
  List<Map<String, String>> getItemsForInvoice(String invoiceCode) {
    return masterItemsList
        .where((item) => item['invoice_code'] == invoiceCode)
        .toList();
  }

  /// Clear all scanned items
  void clearAll() {
    masterItemsList.clear();
    itemsByDropPoint.clear();
    itemsByRoute.clear();
  }

  /// Get total count of scanned items
  int get totalItemsCount => masterItemsList.length;

  /// Get count for specific drop point
  int getCountForDropPoint(String dropPointCode) {
    return getItemsForDropPoint(dropPointCode).length;
  }

  /// Check if item already scanned
  bool isItemScanned(String fullCode) {
    return masterItemsList.any((item) => item['full_code'] == fullCode);
  }
}
