import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:get/get.dart';
import '../controllers/scanned_items_controller.dart';
import '../services/settings_service.dart';
import 'proof_capture_screen.dart';

/// Implementation of Mobile Scanner example with multiple code scanning
class DeliveryScanner extends StatefulWidget {
  /// Constructor for multiple code scanner example
  final bool fromTracking;
  final String? dropPointCode;
  final Map<String, dynamic>? currentPoint;

  const DeliveryScanner({
    super.key,
    this.fromTracking = false,
    this.dropPointCode,
    this.currentPoint,
  });

  @override
  State<DeliveryScanner> createState() => _DeliveryScannerState();
}

class _DeliveryScannerState extends State<DeliveryScanner> {
  // Global scanned items controller
  final ScannedItemsController _scannedItemsController = Get.put(
    ScannedItemsController(),
  );

  /// Scanned item format:
  /// {
  ///   'invoice_code': 'INV001',           // Invoice number
  ///   'route_code': 'A',                  // Route identifier (A, B, C, etc.)
  ///   'drop_point_code': 'T-001',         // Drop point code (T-001, K-A, etc.)
  ///   'num_of_items': 'B',                // Total items category (A, B, C, etc.)
  ///   'item_size': '2',                   // Size category (1, 2, 3, etc.)
  ///   'num_of_items_per_size': '5',       // Number of items for this size
  ///   'index': '00001',                   // Unique item index
  ///   'full_code': 'INV001|A|T-001|B|2|5|00001',  // Full scanned barcode
  /// }
  ///
  /// Example to add manually in debug:
  /// _scannedItemsController.addScannedItem({
  ///   'invoice_code': 'INV001',
  ///   'route_code': 'A',
  ///   'drop_point_code': 'T-001',
  ///   'num_of_items': 'B',
  ///   'item_size': '2',
  ///   'num_of_items_per_size': '5',
  ///   'index': '00001',
  ///   'full_code': 'INV001|A|T-001|B|2|5|00001',
  /// });

  // Current scanned drop point
  Map<String, dynamic>? _currentDropPoint;

  // Pending drop point waiting for confirmation
  Map<String, dynamic>? _pendingDropPoint;

  // Track scanned item codes for current drop point
  final List<Map<String, String>> _scannedItems = [];

  // Temporary storage for scanned items before confirmation
  final List<Map<String, String>> _tempScannedItems = [];

  // Expected items for Toko drop point
  List<Map<String, String>> _expectedTokoItems = [];

  // Track route code for Kendaraan category
  String? _currentRouteCode;
  String? _currentRouteName;

  // Track route points and current section for Kendaraan
  List<Map<String, dynamic>> _routePoints = [];
  int _currentSectionIndex = 0;
  // Group items by section, then by invoice
  Map<int, Map<String, List<Map<String, String>>>> _sectionInvoiceItems = {};
  Map<int, Map<String, int>> _invoiceExpectedCounts = {};
  Map<int, Map<String, Map<String, int>>> _invoiceSizeExpectedCounts = {};
  Map<int, Map<String, Map<String, int>>> _invoiceSizeActualCounts = {};

  // Track which section expansion tile is expanded
  int? _expandedSectionIndex;

  // Audio player for success sound
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Mobile scanner controller
  late MobileScannerController _scannerController;

  bool _canScan = true;

  OverlayEntry? _overlayEntry;

  // Debug mode state
  bool _debugMode = true; // Set to false to disable debug button
  String? _debugSelectedCategory; // 'Kendaraan' or 'Toko'

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: false,
    );

    // Start the scanner after a short delay to avoid conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scannerController.start();
        // If coming from tracking, auto-load the drop point
        if (widget.fromTracking && widget.dropPointCode != null) {
          _autoLoadDropPoint();
        }
      }
    });
  }

  void _autoLoadDropPoint() {
    if (!mounted) return;
    final code = widget.dropPointCode!;
    final dropPoint = {'code': code, 'category': _getCategoryFromCode(code)};
    setState(() {
      _currentDropPoint = dropPoint;
    });
    _showTopMessage('Scanning for $code', Colors.blue);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _audioPlayer.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _showTopMessage(String message, Color backgroundColor) {
    if (!mounted) return;

    // Remove existing overlay if any
    _overlayEntry?.remove();
    _overlayEntry = null;

    // Create overlay entry
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 10,
        right: 10,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Insert overlay
    Overlay.of(context).insert(_overlayEntry!);

    // Auto-remove after duration
    final duration =
        backgroundColor == Colors.red || backgroundColor == Colors.orange
        ? const Duration(seconds: 2)
        : const Duration(seconds: 1);

    Future.delayed(duration, () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  /// Determines category from drop point code prefix:
  /// codes starting with 'K-' → 'Kendaraan', 'T-' → 'Toko'
  String _getCategoryFromCode(String code) {
    if (code.toUpperCase().startsWith('K-')) return 'Kendaraan';
    return 'Toko';
  }

  void _handleBarcode(BarcodeCapture barcodes) {
    if (!mounted || !_canScan) return;

    // Disable scanning when confirmation dialog is shown
    if (_pendingDropPoint != null) return;

    for (final barcode in barcodes.barcodes) {
      final code = barcode.displayValue ?? barcode.rawValue;

      if (code == null || code.isEmpty) continue;

      // If no drop point is selected, treat any non-item code as a drop point
      if (_currentDropPoint == null && _pendingDropPoint == null) {
        if (!code.contains('INV')) {
          final category = _getCategoryFromCode(code);

          // For Toko category, check if there are items for this drop point
          if (category == 'Toko') {
            final itemsForToko = _scannedItemsController.masterItemsList
                .where((item) => item['drop_point_code'] == code)
                .toList();

            if (itemsForToko.isEmpty) {
              _showTopMessage(
                '✗ No items found for $code. Please scan Kendaraan first.',
                Colors.red,
              );
              _addScanDelay();
              continue;
            }
          }

          // Set pending drop point for confirmation
          setState(() {
            _pendingDropPoint = {'code': code, 'category': category};
          });

          // Play success sound
          _audioPlayer.play(AssetSource('sounds/success.mp3'));

          // Vibrate
          Vibration.vibrate(duration: 100);

          _addScanDelay();
        }
      } else {
        // Drop point is selected, scan items
        // Only accept codes containing 'INV'
        if (code.contains('INV')) {
          // Parse the item code format: INV001|A|T-001|B|2|00001
          final parts = code.split('|');

          if (parts.length != 7) {
            _showTopMessage('✗ Invalid item format: $code', Colors.red);
            _addScanDelay();
            continue;
          }

          final itemData = {
            'invoice_code': parts[0],
            'route_code': parts[1],
            'drop_point_code': parts[2],
            'num_of_items': parts[3],
            'item_size': parts[4],
            'num_of_items_per_size': parts[5],
            'index': parts[6],
            'full_code': code,
          };

          // Check if item already scanned
          final alreadyScanned = _scannedItems.any(
            (item) => item['full_code'] == code,
          );

          if (alreadyScanned) {
            continue;
          }

          // Validate based on drop point category
          final category = _currentDropPoint!['category'];

          if (category == 'Kendaraan') {
            // For Kendaraan: check route_code consistency
            if (_currentRouteCode == null) {
              // First item overall, store the route_code
              _currentRouteCode = itemData['route_code'];
            } else if (_currentRouteCode != itemData['route_code']) {
              // Route code doesn't match
              _showTopMessage(
                '✗ Barang ini tidak berada di rute yang sama',
                Colors.red,
              );
              _addScanDelay();
              continue;
            }

            // Dynamically add drop point as a section if it's new
            final dropPointCode = itemData['drop_point_code'];

            // Find if this drop point already exists in route points
            int sectionIndex = _routePoints.indexWhere(
              (rp) => rp['drop_point_code'] == dropPointCode,
            );

            if (sectionIndex == -1) {
              // New drop point encountered, add it as a new section
              _routePoints.add({'drop_point_code': dropPointCode});
              sectionIndex = _routePoints.length - 1;
              _currentSectionIndex = sectionIndex;
            } else {
              // Section exists, update current section if needed
              _currentSectionIndex = sectionIndex;
            }

            if (sectionIndex != -1) {
              final invoiceCode = itemData['invoice_code'] ?? '';

              // Initialize tracking for this section and invoice if needed
              _sectionInvoiceItems[_currentSectionIndex] ??= {};
              _invoiceExpectedCounts[_currentSectionIndex] ??= {};
              _invoiceSizeExpectedCounts[_currentSectionIndex] ??= {};
              _invoiceSizeActualCounts[_currentSectionIndex] ??= {};

              // Set expected count for this invoice if this is the first item
              if ((_sectionInvoiceItems[_currentSectionIndex]![invoiceCode] ??
                      [])
                  .isEmpty) {
                _invoiceExpectedCounts[_currentSectionIndex]![invoiceCode] =
                    int.tryParse(itemData['num_of_items'] ?? '0') ?? 0;
              }

              // Track and validate size counts per invoice
              final itemSize = itemData['item_size'] ?? '';
              final numPerSize =
                  int.tryParse(itemData['num_of_items_per_size'] ?? '0') ?? 0;

              // Initialize size tracking for this invoice if needed
              _invoiceSizeExpectedCounts[_currentSectionIndex]![invoiceCode] ??=
                  {};
              _invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode] ??=
                  {};

              // Set expected count for this size if this is the first item of this size for this invoice
              if (!_invoiceSizeExpectedCounts[_currentSectionIndex]![invoiceCode]!
                  .containsKey(itemSize)) {
                _invoiceSizeExpectedCounts[_currentSectionIndex]![invoiceCode]![itemSize] =
                    numPerSize;
                _invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode]![itemSize] =
                    0;
              }

              // Check if we've already scanned enough items of this size for this invoice
              final currentCount =
                  _invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode]![itemSize] ??
                  0;
              final expectedCount =
                  _invoiceSizeExpectedCounts[_currentSectionIndex]![invoiceCode]![itemSize] ??
                  0;

              if (currentCount >= expectedCount) {
                _showTopMessage(
                  '✗ Invoice $invoiceCode: Sudah mencapai limit untuk ukuran $itemSize ($currentCount/$expectedCount items)',
                  Colors.red,
                );
                _addScanDelay();
                continue;
              }
            }
          } else if (category == 'Toko') {
            if (itemData['drop_point_code'] != _currentDropPoint!['code']) {
              _showTopMessage(
                '✗ Item ini untuk ${itemData['drop_point_code']}, bukan ${_currentDropPoint!['code']}',
                Colors.red,
              );
              _addScanDelay();
              continue;
            }
          }

          // Valid item, add to list
          setState(() {
            if (category == 'Kendaraan') {
              final invoiceCode = itemData['invoice_code'] ?? '';
              // Add to current section and invoice
              _sectionInvoiceItems[_currentSectionIndex] ??= {};
              _sectionInvoiceItems[_currentSectionIndex]![invoiceCode] = [
                ...(_sectionInvoiceItems[_currentSectionIndex]![invoiceCode] ??
                    []),
                itemData,
              ];
              // Increment size count for this invoice
              final itemSize = itemData['item_size'] ?? '';
              _invoiceSizeActualCounts[_currentSectionIndex] ??= {};
              _invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode] ??=
                  {};
              _invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode]![itemSize] =
                  (_invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode]![itemSize] ??
                      0) +
                  1;
            }
            _scannedItems.add(itemData);
            // Store temporarily, will be saved to global state on confirm
            _tempScannedItems.add(itemData);
          });

          // Show feedback
          _showTopMessage(
            '✓ Item scanned: ${itemData['invoice_code']}',
            Colors.green,
          );

          // Play success sound
          _audioPlayer.play(AssetSource('sounds/success.mp3'));

          // Vibrate
          Vibration.vibrate(duration: 100);

          _addScanDelay();
        }
      }
    }
  }

  Future<void> _confirmItems() async {
    final category = _currentDropPoint!['category'];

    if (category == 'Kendaraan') {
      // Check if current section has any invoices
      final invoicesInSection =
          _sectionInvoiceItems[_currentSectionIndex] ?? {};

      if (invoicesInSection.isEmpty) {
        // Skip empty section
        if (_currentSectionIndex < _routePoints.length - 1) {
          setState(() {
            _currentSectionIndex++;
            _expandedSectionIndex = _currentSectionIndex; // Open new section
          });
          _showTopMessage(
            'Section ${_currentSectionIndex} skipped (no items). Moving to ${_routePoints[_currentSectionIndex]['drop_point_code']}',
            Colors.blue,
          );
        } else {
          // Last section was empty - finish
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('All Sections Complete'),
              content: Text(
                'All ${_routePoints.length} sections completed with ${_scannedItems.length} total items',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _currentDropPoint = null;
                      _scannedItems.clear();
                      _currentRouteCode = null;
                      _currentRouteName = null;
                      _routePoints = [];
                      _currentSectionIndex = 0;
                      _sectionInvoiceItems = {};
                      _invoiceExpectedCounts = {};
                      _invoiceSizeExpectedCounts = {};
                      _invoiceSizeActualCounts = {};
                      _expandedSectionIndex = null;
                    });
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Validate each invoice in the section
      for (var invoiceEntry in invoicesInSection.entries) {
        final invoiceCode = invoiceEntry.key;
        final invoiceItems = invoiceEntry.value;
        final expectedCount =
            _invoiceExpectedCounts[_currentSectionIndex]?[invoiceCode] ?? 0;

        // Check if expected items are scanned for this invoice
        if (expectedCount > 0 && invoiceItems.length < expectedCount) {
          _showTopMessage(
            'Invoice $invoiceCode incomplete: ${invoiceItems.length}/$expectedCount items',
            Colors.orange,
          );
          return;
        }

        // Check if all size requirements are met for this invoice
        final sizeExpected =
            _invoiceSizeExpectedCounts[_currentSectionIndex]?[invoiceCode] ??
            {};
        final sizeActual =
            _invoiceSizeActualCounts[_currentSectionIndex]?[invoiceCode] ?? {};

        for (var entry in sizeExpected.entries) {
          final size = entry.key;
          final expected = entry.value;
          final actual = sizeActual[size] ?? 0;

          if (actual < expected) {
            _showTopMessage(
              'Invoice $invoiceCode - Ukuran $size incomplete: $actual/$expected items',
              Colors.orange,
            );
            return;
          }
        }
      }

      // All invoices complete, save items to global state and move to next section or finish
      // Save all temp items for this section to global state
      _scannedItemsController.addScannedItems(_tempScannedItems);
      _tempScannedItems.clear();

      if (_currentSectionIndex < _routePoints.length - 1) {
        setState(() {
          _currentSectionIndex++;
          _expandedSectionIndex = _currentSectionIndex; // Open new section
        });
        _showTopMessage(
          'Section ${_currentSectionIndex} complete! Moving to ${_routePoints[_currentSectionIndex]['drop_point_code']}',
          Colors.green,
        );
      } else {
        // All current sections complete, but stay in Kendaraan category for new drop points

        // Send put request to update the delivery status
        final invoiceCodes = _scannedItems
            .map((item) => item['invoice_code'] ?? '')
            .where((inv) => inv.isNotEmpty)
            .toSet();
        for (final invoiceCode in invoiceCodes) {
          try {
            final baseUrl = SettingsService.instance.baseUrl;
            final uri = Uri.parse('$baseUrl/api/delivery/$invoiceCode/status');
            await http.put(
              uri,
              body: {
                'vehicle_no': _currentDropPoint?['code'],
                'username': 'Aling',
                'status': 'Menunggu Supir',
              },
            );
          } catch (e) {
            log('Failed to update status for $invoiceCode: $e');
          }
        }

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sections Complete'),
            content: Text(
              'All ${_routePoints.length} sections completed with ${_scannedItems.length} total items.\n\nYou can continue scanning items for additional drop points in the same route.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    // Keep _currentDropPoint and _currentRouteCode to stay in Kendaraan category
                    // Only clear section-specific data
                    _scannedItems.clear();
                    _routePoints = [];
                    _currentSectionIndex = 0;
                    _sectionInvoiceItems = {};
                    _invoiceExpectedCounts = {};
                    _expandedSectionIndex = null;
                    _invoiceSizeExpectedCounts = {};
                    _invoiceSizeActualCounts = {};
                  });

                  // If from tracking, return to tracking screen
                  if (widget.fromTracking) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else {
      // Toko category
      if (_scannedItems.isEmpty) {
        _showTopMessage('No items scanned', Colors.orange);
        return;
      }

      // Check if all expected items are scanned
      if (_scannedItems.length < _expectedTokoItems.length) {
        _showTopMessage(
          'Incomplete: ${_scannedItems.length}/${_expectedTokoItems.length} items scanned',
          Colors.orange,
        );
        return;
      }

      // Remove items for this drop point from global state (before clearing local list)
      if (_currentDropPoint != null) {
        _scannedItemsController.removeItemsForDropPoint(
          _currentDropPoint?['code'],
        );
      }

      // Collect invoice numbers from scanned items
      final invoiceNumbers = _scannedItems
          .map((item) => item['invoice_code'] ?? '')
          .where((inv) => inv.isNotEmpty)
          .toSet()
          .toList();

      final dropPointCode = _currentDropPoint!['code'];
      final itemCount = _scannedItems.length;

      // Navigate to proof capture screen
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => ProofCaptureScreen(
            dropPointCode: dropPointCode,
            invoiceNumbers: invoiceNumbers,
          ),
        ),
      );

      if (result == true && mounted) {
        // Show success message
        _showTopMessage(
          '✓ $itemCount items delivered to $dropPointCode with proof',
          Colors.green,
        );

        setState(() {
          _currentDropPoint = null;
          _scannedItems.clear();
          _currentRouteCode = null;
          _currentRouteName = null;
          _expectedTokoItems = [];
        });

        // If from tracking, return to tracking screen
        if (widget.fromTracking) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  void _cancelScanning() {
    setState(() {
      // Remove only the temporary scanned items (not yet confirmed) from _scannedItems
      for (final tempItem in _tempScannedItems) {
        _scannedItems.removeWhere(
          (item) => item['full_code'] == tempItem['full_code'],
        );
      }

      // Clear temporary items (they were never saved to global state)
      _tempScannedItems.clear();

      _currentDropPoint = null;
      _currentRouteCode = null;
      _currentRouteName = null;
      _routePoints = [];
      _currentSectionIndex = 0;
      _sectionInvoiceItems = {};
      _invoiceExpectedCounts = {};
      _expandedSectionIndex = null;
      _invoiceSizeExpectedCounts = {};
      _invoiceSizeActualCounts = {};
      _expectedTokoItems = [];
    });
  }

  void _clearItems() {
    setState(() {
      if (_currentDropPoint != null &&
          _currentDropPoint!['category'] == 'Kendaraan') {
        // Only clear current section for Kendaraan
        _sectionInvoiceItems[_currentSectionIndex] = {};
        _invoiceExpectedCounts.remove(_currentSectionIndex);
        _invoiceSizeExpectedCounts.remove(_currentSectionIndex);
        _invoiceSizeActualCounts.remove(_currentSectionIndex);
        // Remove items from current section from _scannedItems
        if (_routePoints.isNotEmpty) {
          final currentDropPointCode =
              _routePoints[_currentSectionIndex]['drop_point_code'];
          _scannedItems.removeWhere(
            (item) => item['drop_point_code'] == currentDropPointCode,
          );

          // Also remove from global state
          _scannedItemsController.removeItemsForDropPoint(currentDropPointCode);

          // Play success sound
          _audioPlayer.play(AssetSource('sounds/success.mp3'));

          // clear all drop point
          _routePoints.clear();
        }
      } else {
        // Clear all for Toko
        _scannedItems.clear();
        _currentRouteCode = null;
        _currentRouteName = null;
      }
    });
    _showTopMessage('All items cleared', Colors.orange);
  }

  bool _canConfirm() {
    if (_currentDropPoint == null) return false;

    final category = _currentDropPoint!['category'];

    if (category == 'Kendaraan') {
      // Disable if no sections/route points
      if (_routePoints.isEmpty) return false;

      // For Kendaraan: check if all invoices in current section are complete
      final invoicesInSection =
          _sectionInvoiceItems[_currentSectionIndex] ?? {};

      // Allow skip if no items scanned yet in this section
      if (invoicesInSection.isEmpty) return true;

      // Check each invoice
      for (var invoiceEntry in invoicesInSection.entries) {
        final invoiceCode = invoiceEntry.key;
        final invoiceItems = invoiceEntry.value;
        final expectedCount =
            _invoiceExpectedCounts[_currentSectionIndex]?[invoiceCode] ?? 0;

        // Must have expected number of items
        if (expectedCount > 0 && invoiceItems.length < expectedCount) {
          return false;
        }

        // Check if all size requirements are met for this invoice
        final sizeExpected =
            _invoiceSizeExpectedCounts[_currentSectionIndex]?[invoiceCode] ??
            {};
        final sizeActual =
            _invoiceSizeActualCounts[_currentSectionIndex]?[invoiceCode] ?? {};

        for (var entry in sizeExpected.entries) {
          final expected = entry.value;
          final actual = sizeActual[entry.key] ?? 0;
          if (actual < expected) {
            return false;
          }
        }
      }

      return true;
    } else {
      // For Toko: need all expected items to be scanned
      return _scannedItems.length >= _expectedTokoItems.length;
    }
  }

  void _addScanDelay() {
    setState(() {
      _canScan = false;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _canScan = true;
        });
      }
    });
  }

  void _debugAutoAddItems() {
    if (_currentDropPoint == null) {
      _showTopMessage('Please select a drop point first', Colors.orange);
      return;
    }

    final category = _currentDropPoint!['category'];

    if (category == 'Kendaraan') {
      // Auto-add items for Kendaraan category
      if (_routePoints.isEmpty) {
        // Create a default section using the current drop point code
        final defaultCode = 'apo-rahayu-farma';
        _routePoints.add({'drop_point_code': defaultCode});
        _currentRouteCode ??= 'DEBUG';
        _currentSectionIndex = 0;
        _expandedSectionIndex = 0;
      }

      final currentPoint = _routePoints[_currentSectionIndex];
      print('currentPoint: $currentPoint');
      final dropPointCode = currentPoint['drop_point_code'] as String;

      // Generate 3 sample items with different sizes
      // List<Map<String, String>> sampleItems = [
      //   {
      //     'invoice_code': 'INV001',
      //     'route_code': _currentRouteCode ?? '',
      //     'drop_point_code': dropPointCode,
      //     'num_of_items': '3',
      //     'item_size': '1',
      //     'num_of_items_per_size': '3',
      //     'index': '00001',
      //     'full_code':
      //         'INV001|${_currentRouteCode ?? ''}|$dropPointCode|3|1|3|00001',
      //   },
      //   {
      //     'invoice_code': 'INV001',
      //     'route_code': _currentRouteCode ?? '',
      //     'drop_point_code': dropPointCode,
      //     'num_of_items': '3',
      //     'item_size': '1',
      //     'num_of_items_per_size': '3',
      //     'index': '00002',
      //     'full_code':
      //         'INV001|${_currentRouteCode ?? ''}|$dropPointCode|3|1|3|00002',
      //   },
      //   {
      //     'invoice_code': 'INV001',
      //     'route_code': _currentRouteCode ?? '',
      //     'drop_point_code': dropPointCode,
      //     'num_of_items': '3',
      //     'item_size': '1',
      //     'num_of_items_per_size': '3',
      //     'index': '00003',
      //     'full_code':
      //         'INV001|${_currentRouteCode ?? ''}|$dropPointCode|3|1|3|00003',
      //   },
      // ];

      List<Map<String, String>> sampleItems = [
        {
          'invoice_code': 'INV-2026-03-30-0002',
          'route_code': _currentRouteCode ?? '',
          'drop_point_code': dropPointCode,
          'num_of_items': '3',
          'item_size': 'B',
          'num_of_items_per_size': '1',
          'index': '00001',
          'full_code':
              'INV-2026-03-30-0002|${_currentRouteCode ?? ''}|$dropPointCode|3|1|1|00001',
        },
        {
          'invoice_code': 'INV-2026-03-30-0002',
          'route_code': _currentRouteCode ?? '',
          'drop_point_code': dropPointCode,
          'num_of_items': '3',
          'item_size': 'S',
          'num_of_items_per_size': '1',
          'index': '00002',
          'full_code':
              'INV-2026-03-30-0002|${_currentRouteCode ?? ''}|$dropPointCode|3|2|1|00002',
        },
        {
          'invoice_code': 'INV-2026-03-30-0002',
          'route_code': _currentRouteCode ?? '',
          'drop_point_code': dropPointCode,
          'num_of_items': '3',
          'item_size': 'K',
          'num_of_items_per_size': '1',
          'index': '00003',
          'full_code':
              'INV-2026-03-30-0002|${_currentRouteCode ?? ''}|$dropPointCode|3|3|1|00003',
        },
      ];

      setState(() {
        // Initialize tracking for this section and invoice
        final invoiceCode = 'INV-2026-03-30-0002';
        _sectionInvoiceItems[_currentSectionIndex] ??= {};
        _invoiceExpectedCounts[_currentSectionIndex] ??= {};
        _invoiceSizeExpectedCounts[_currentSectionIndex] ??= {};
        _invoiceSizeActualCounts[_currentSectionIndex] ??= {};

        _invoiceExpectedCounts[_currentSectionIndex]![invoiceCode] = 3;
        _invoiceSizeExpectedCounts[_currentSectionIndex]![invoiceCode] = {
          'B': 1,
          'S': 1,
          'K': 1,
        };
        _invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode] = {
          'B': 0,
          'S': 0,
          'K': 0,
        };

        // Add all sample items
        for (final item in sampleItems) {
          _scannedItems.add(item);
          _tempScannedItems.add(item);

          // Add to section invoice items
          _sectionInvoiceItems[_currentSectionIndex]![invoiceCode] = [
            ...(_sectionInvoiceItems[_currentSectionIndex]![invoiceCode] ?? []),
            item,
          ];

          // Increment size count
          final itemSize = item['item_size']!;
          _invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode]![itemSize] =
              (_invoiceSizeActualCounts[_currentSectionIndex]![invoiceCode]![itemSize] ??
                  0) +
              1;
        }
      });

      _showTopMessage(
        '✓ Debug: Added 3 items for INV-2026-03-30-0002',
        Colors.blue,
      );
      _audioPlayer.play(AssetSource('sounds/success.mp3'));
      Vibration.vibrate(duration: 100);
    } else if (category == 'Toko') {
      _expectedTokoItems = [
        {
          'invoice_code': 'INV-2026-03-30-0002',
          'route_code': _currentRouteCode ?? '',
          'drop_point_code': _currentDropPoint!['code'],
          'num_of_items': '3',
          'item_size': 'B',
          'num_of_items_per_size': '1',
          'index': '00001',
          'full_code':
              'INV-2026-03-30-0002|${_currentRouteCode ?? ''}|${_currentDropPoint!['code']}|3|1|1|00001',
        },
        {
          'invoice_code': 'INV-2026-03-30-0002',
          'route_code': _currentRouteCode ?? '',
          'drop_point_code': _currentDropPoint!['code'],
          'num_of_items': '3',
          'item_size': 'S',
          'num_of_items_per_size': '1',
          'index': '00002',
          'full_code':
              'INV-2026-03-30-0002|${_currentRouteCode ?? ''}|${_currentDropPoint!['code']}|3|2|1|00002',
        },
        {
          'invoice_code': 'INV-2026-03-30-0002',
          'route_code': _currentRouteCode ?? '',
          'drop_point_code': _currentDropPoint!['code'],
          'num_of_items': '3',
          'item_size': 'K',
          'num_of_items_per_size': '1',
          'index': '00003',
          'full_code':
              'INV-2026-03-30-0002|${_currentRouteCode ?? ''}|${_currentDropPoint!['code']}|3|3|1|00003',
        },
      ];

      // Auto-add all expected items for Toko category
      if (_expectedTokoItems.isEmpty) {
        _showTopMessage('No expected items for this Toko', Colors.orange);
        return;
      }

      setState(() {
        for (final expectedItem in _expectedTokoItems) {
          // Check if not already scanned
          final alreadyScanned = _scannedItems.any(
            (item) => item['full_code'] == expectedItem['full_code'],
          );

          if (!alreadyScanned) {
            _scannedItems.add(expectedItem);
            _tempScannedItems.add(expectedItem);
          }
        }
      });

      _showTopMessage(
        '✓ Debug: Added ${_expectedTokoItems.length} items',
        Colors.blue,
      );
      _audioPlayer.play(AssetSource('sounds/success.mp3'));
      Vibration.vibrate(duration: 100);
    }
  }

  Widget _buildDropPointConfirmation() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _pendingDropPoint!['category'] == 'Kendaraan'
                  ? Icons.local_shipping
                  : Icons.store,
              size: 120,
              color: Colors.blue,
            ),
            const SizedBox(height: 32),
            Text(
              _pendingDropPoint!['code'],
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              _pendingDropPoint!['category'],
              style: TextStyle(fontSize: 20, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
            const Text(
              'Confirm this drop point?',
              style: TextStyle(fontSize: 18, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: MobileScanner(
              controller: _scannerController,
              onDetect: _handleBarcode,
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              decoration: const BoxDecoration(color: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.grey.shade100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.fromTracking)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.navigation,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Tracking Mode: ${widget.dropPointCode}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_currentDropPoint == null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Scan Drop Point (Kendaraan/Toko)',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  // Debug button to select category
                                  if (_debugMode)
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      child: PopupMenuButton<String>(
                                        icon: const Icon(
                                          Icons.bug_report,
                                          color: Colors.orange,
                                        ),
                                        tooltip: 'Debug: Select Category',
                                        onSelected: (String category) {
                                          setState(() {
                                            _debugSelectedCategory = category;
                                          });
                                          // Use default codes for debug testing
                                          final code = category == 'Kendaraan'
                                              ? 'K-001'
                                              : 'T-001';
                                          final dropPoint = {
                                            'code': code,
                                            'category': category,
                                          };
                                          // For Toko category, check if there are items
                                          if (category == 'Toko') {
                                            final itemsForToko =
                                                _scannedItemsController
                                                    .masterItemsList
                                                    .where(
                                                      (item) =>
                                                          item['drop_point_code'] ==
                                                          code,
                                                    )
                                                    .toList();

                                            if (itemsForToko.isEmpty) {
                                              _showTopMessage(
                                                '✗ No items found for $code. Please scan Kendaraan first.',
                                                Colors.red,
                                              );
                                              return;
                                            }
                                          }

                                          setState(() {
                                            _pendingDropPoint = dropPoint;
                                          });
                                          _audioPlayer.play(
                                            AssetSource('sounds/success.mp3'),
                                          );
                                          Vibration.vibrate(duration: 100);
                                        },
                                        itemBuilder: (BuildContext context) => [
                                          const PopupMenuItem<String>(
                                            value: 'Kendaraan',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.local_shipping,
                                                  color: Colors.blue,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Kendaraan'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem<String>(
                                            value: 'Toko',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.store,
                                                  color: Colors.green,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Toko'),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Obx(
                                    () =>
                                        _scannedItemsController
                                                .totalItemsCount >
                                            0
                                        ? TextButton.icon(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (BuildContext context) {
                                                  return AlertDialog(
                                                    title: const Row(
                                                      children: [
                                                        Icon(
                                                          Icons.warning,
                                                          color: Colors.orange,
                                                          size: 28,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text('Clear All Items'),
                                                      ],
                                                    ),
                                                    content: Text(
                                                      'Are you sure you want to clear all ${_scannedItemsController.totalItemsCount} scanned items? This action cannot be undone.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () {
                                                          Navigator.of(
                                                            context,
                                                          ).pop();
                                                        },
                                                        child: const Text(
                                                          'Cancel',
                                                        ),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () {
                                                          _scannedItemsController
                                                              .clearAll();
                                                          Navigator.of(
                                                            context,
                                                          ).pop();
                                                          _showTopMessage(
                                                            'All scanned items cleared',
                                                            Colors.orange,
                                                          );
                                                        },
                                                        style:
                                                            ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors.red,
                                                              foregroundColor:
                                                                  Colors.white,
                                                            ),
                                                        child: const Text(
                                                          'Clear All',
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.delete_sweep,
                                              size: 20,
                                            ),
                                            label: Text(
                                              'Clear All (${_scannedItemsController.totalItemsCount})',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _currentDropPoint!['category'] ==
                                              'Kendaraan'
                                          ? 'Scan barang untuk dimasukkan ke Kendaraan ${_currentDropPoint!['code']}${_currentRouteName != null ? ' - $_currentRouteName' : ''}'
                                          : 'Scan barang untuk diturunkan ke Toko - ${_currentDropPoint!['code']}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _debugAutoAddItems,
                                    icon: const Icon(
                                      Icons.bug_report,
                                      color: Colors.purple,
                                    ),
                                    tooltip: 'Debug: Auto-add items',
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.purple
                                          .withOpacity(0.1),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_currentDropPoint!['category'] ==
                                      'Kendaraan' &&
                                  _routePoints.isNotEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Section ${_currentSectionIndex + 1}/${_routePoints.length}: ${_routePoints[_currentSectionIndex]['drop_point_code']}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              if (_currentDropPoint!['category'] == 'Toko' &&
                                  _expectedTokoItems.isNotEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                _scannedItems.length >=
                                                    _expectedTokoItems.length
                                                ? Colors.green
                                                : Colors.orange,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            'Progress: ${_scannedItems.length}/${_expectedTokoItems.length} items',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _pendingDropPoint != null
                        ? _buildDropPointConfirmation()
                        : _currentDropPoint == null
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.qr_code_scanner,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Arahkan kamera ke QR Drop Point',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : (_currentDropPoint!['category'] == 'Kendaraan' &&
                              _routePoints.isNotEmpty)
                        ? ListView(
                            children: [
                              // Show all sections with their items
                              for (int i = 0; i < _routePoints.length; i++)
                                ExpansionTile(
                                  key: ValueKey(
                                    'section_$i\_$_currentSectionIndex',
                                  ),
                                  initiallyExpanded: i == _expandedSectionIndex,
                                  onExpansionChanged: (expanded) {
                                    setState(() {
                                      _expandedSectionIndex = expanded
                                          ? i
                                          : null;
                                    });
                                  },
                                  title: Text(
                                    'Section ${i + 1}: ${_routePoints[i]['drop_point_code']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: i == _currentSectionIndex
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                  ),
                                  subtitle: () {
                                    final invoices =
                                        _sectionInvoiceItems[i] ?? {};
                                    final totalItems = invoices.values
                                        .fold<int>(
                                          0,
                                          (sum, items) => sum + items.length,
                                        );
                                    return Row(
                                      children: [
                                        Text(
                                          'Total items: $totalItems | Invoices: ${invoices.length}' +
                                              (i == _currentSectionIndex
                                                  ? ' (Current)'
                                                  : i < _currentSectionIndex
                                                  ? ' '
                                                  : ' (Pending)'),
                                        ),
                                        if (i < _currentSectionIndex)
                                          const Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 16,
                                          ),
                                      ],
                                    );
                                  }(),
                                  children: [
                                    // Show items grouped by invoice
                                    if ((_sectionInvoiceItems[i] ?? {}).isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: Text(
                                          'No items scanned yet',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      )
                                    else
                                      ...(_sectionInvoiceItems[i] ?? {}).entries.map((
                                        invoiceEntry,
                                      ) {
                                        final invoiceCode = invoiceEntry.key;
                                        final invoiceItems = invoiceEntry.value;
                                        final expectedCount =
                                            _invoiceExpectedCounts[i]?[invoiceCode] ??
                                            0;
                                        final sizeExpected =
                                            _invoiceSizeExpectedCounts[i]?[invoiceCode] ??
                                            {};
                                        final sizeActual =
                                            _invoiceSizeActualCounts[i]?[invoiceCode] ??
                                            {};

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Invoice header
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              color: Colors.blue.shade50,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.receipt_long,
                                                    size: 18,
                                                    color: Colors.blue.shade700,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Invoice: $invoiceCode',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                      color:
                                                          Colors.blue.shade900,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          invoiceItems.length >=
                                                              expectedCount
                                                          ? Colors.green
                                                          : Colors.orange,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '${invoiceItems.length}/$expectedCount',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Size summary for this invoice
                                            if (sizeExpected.isNotEmpty)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16.0,
                                                      vertical: 8.0,
                                                    ),
                                                child: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  children: sizeExpected.entries.map((
                                                    entry,
                                                  ) {
                                                    final size = entry.key;
                                                    final expected =
                                                        entry.value;
                                                    final actual =
                                                        sizeActual[size] ?? 0;
                                                    final isComplete =
                                                        actual >= expected;

                                                    return Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: isComplete
                                                            ? Colors.green
                                                                  .withOpacity(
                                                                    0.2,
                                                                  )
                                                            : Colors.orange
                                                                  .withOpacity(
                                                                    0.2,
                                                                  ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: isComplete
                                                              ? Colors.green
                                                              : Colors.orange,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        'Size $size: $actual/$expected',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: isComplete
                                                              ? Colors
                                                                    .green
                                                                    .shade800
                                                              : Colors
                                                                    .orange
                                                                    .shade800,
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                            // Invoice items
                                            ...invoiceItems.map((item) {
                                              return ListTile(
                                                dense: true,
                                                leading: const Icon(
                                                  Icons
                                                      .keyboard_double_arrow_right,
                                                  color: Colors.green,
                                                  size: 30,
                                                ),
                                                title: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        '${item['invoice_code']}-${item['index']}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      'Size: ${item['item_size']}',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                // subtitle:
                                              );
                                            }).toList(),
                                            const Divider(height: 1),
                                          ],
                                        );
                                      }).toList(),
                                  ],
                                ),
                            ],
                          )
                        : _currentDropPoint!['category'] == 'Toko'
                        ? ListView(
                            children: [
                              // Group items by invoice
                              ...() {
                                // Group expected items by invoice
                                final Map<String, List<Map<String, String>>>
                                invoiceGroups = {};
                                for (final item in _expectedTokoItems) {
                                  final invoiceCode =
                                      item['invoice_code'] ?? '';
                                  invoiceGroups[invoiceCode] ??= [];
                                  invoiceGroups[invoiceCode]!.add(item);
                                }

                                // Get expected counts and sizes per invoice
                                final Map<String, int> invoiceExpectedCounts =
                                    {};
                                final Map<String, Map<String, int>>
                                invoiceSizeExpected = {};

                                for (final entry in invoiceGroups.entries) {
                                  final invoiceCode = entry.key;
                                  final items = entry.value;

                                  if (items.isNotEmpty) {
                                    invoiceExpectedCounts[invoiceCode] =
                                        int.tryParse(
                                          items[0]['num_of_items'] ?? '0',
                                        ) ??
                                        0;

                                    invoiceSizeExpected[invoiceCode] = {};
                                    for (final item in items) {
                                      final size = item['item_size'] ?? '';
                                      final count =
                                          int.tryParse(
                                            item['num_of_items_per_size'] ??
                                                '0',
                                          ) ??
                                          0;
                                      invoiceSizeExpected[invoiceCode]![size] =
                                          count;
                                    }
                                  }
                                }

                                // Get scanned counts per invoice
                                final Map<String, List<Map<String, String>>>
                                scannedByInvoice = {};
                                final Map<String, Map<String, int>>
                                invoiceSizeActual = {};

                                for (final item in _scannedItems) {
                                  final invoiceCode =
                                      item['invoice_code'] ?? '';
                                  scannedByInvoice[invoiceCode] ??= [];
                                  scannedByInvoice[invoiceCode]!.add(item);

                                  final size = item['item_size'] ?? '';
                                  invoiceSizeActual[invoiceCode] ??= {};
                                  invoiceSizeActual[invoiceCode]![size] =
                                      (invoiceSizeActual[invoiceCode]![size] ??
                                          0) +
                                      1;
                                }

                                return invoiceGroups.entries.map((entry) {
                                  final invoiceCode = entry.key;
                                  final expectedItems = entry.value;
                                  final scannedItems =
                                      scannedByInvoice[invoiceCode] ?? [];
                                  final expectedCount =
                                      invoiceExpectedCounts[invoiceCode] ?? 0;
                                  final sizeExpected =
                                      invoiceSizeExpected[invoiceCode] ?? {};
                                  final sizeActual =
                                      invoiceSizeActual[invoiceCode] ?? {};

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Invoice header
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        color: Colors.blue.shade50,
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.receipt_long,
                                              size: 18,
                                              color: Colors.blue.shade700,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Invoice: $invoiceCode',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.blue.shade900,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    scannedItems.length >=
                                                        expectedCount
                                                    ? Colors.green
                                                    : Colors.orange,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '${scannedItems.length}/$expectedCount',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Size summary for this invoice
                                      if (sizeExpected.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0,
                                            vertical: 8.0,
                                          ),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: sizeExpected.entries.map((
                                              e,
                                            ) {
                                              final size = e.key;
                                              final expected = e.value;
                                              final actual =
                                                  sizeActual[size] ?? 0;
                                              final isComplete =
                                                  actual >= expected;

                                              return Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isComplete
                                                      ? Colors.green
                                                            .withOpacity(0.2)
                                                      : Colors.orange
                                                            .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: isComplete
                                                        ? Colors.green
                                                        : Colors.orange,
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Text(
                                                  'Size $size: $actual/$expected',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: isComplete
                                                        ? Colors.green.shade800
                                                        : Colors
                                                              .orange
                                                              .shade800,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      // Expected items
                                      ...expectedItems.map((expectedItem) {
                                        final isScanned = scannedItems.any(
                                          (item) =>
                                              item['full_code'] ==
                                              expectedItem['full_code'],
                                        );

                                        return ListTile(
                                          dense: true,
                                          leading: Icon(
                                            isScanned
                                                ? Icons.check_circle
                                                : Icons.radio_button_unchecked,
                                            color: isScanned
                                                ? Colors.green
                                                : Colors.grey,
                                            size: 30,
                                          ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${expectedItem['invoice_code']}-${expectedItem['index']}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 13,
                                                    decoration: isScanned
                                                        ? TextDecoration
                                                              .lineThrough
                                                        : null,
                                                    color: isScanned
                                                        ? Colors.grey
                                                        : Colors.black,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                'Size: ${expectedItem['item_size']}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isScanned
                                                      ? Colors.grey
                                                      : Colors.black,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      const Divider(height: 1),
                                    ],
                                  );
                                }).toList();
                              }(),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _scannedItems.length,
                            itemBuilder: (context, index) {
                              final item = _scannedItems[index];
                              return ListTile(
                                leading: const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                ),
                                title: Text(
                                  '${item['invoice_code']}-${item['index']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  'Route: ${item['route_code']} | Drop: ${item['drop_point_code']} | Size: ${item['item_size']} | Jumlah: ${item['num_of_items']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            },
                          ),
                  ),
                  if (_pendingDropPoint != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(0, -3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _pendingDropPoint = null;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _currentDropPoint = _pendingDropPoint;
                                  _pendingDropPoint = null;
                                  _scannedItems.clear();
                                  _currentRouteCode = null;
                                  _currentRouteName = null;
                                  _routePoints = [];
                                  _currentSectionIndex = 0;
                                  _sectionInvoiceItems = {};
                                  _invoiceExpectedCounts = {};
                                  _invoiceSizeExpectedCounts = {};
                                  _invoiceSizeActualCounts = {};
                                  _expandedSectionIndex = 0;

                                  // For Toko, load expected items
                                  if (_currentDropPoint!['category'] ==
                                      'Toko') {
                                    _expectedTokoItems = _scannedItemsController
                                        .masterItemsList
                                        .where(
                                          (item) =>
                                              item['drop_point_code'] ==
                                              _currentDropPoint!['code'],
                                        )
                                        .toList();
                                  } else {
                                    _expectedTokoItems = [];
                                  }
                                });

                                // Show feedback
                                _showTopMessage(
                                  '✓ Drop point confirmed: ${_currentDropPoint!['code']}',
                                  Colors.green,
                                );

                                // Play success sound
                                _audioPlayer.play(
                                  AssetSource('sounds/success.mp3'),
                                );

                                // Vibrate
                                Vibration.vibrate(duration: 100);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: const Text('Confirm'),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_currentDropPoint != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(0, -3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _cancelScanning,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _clearItems,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                foregroundColor: Colors.orange,
                              ),
                              child: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _canConfirm() ? _confirmItems : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey,
                                disabledForegroundColor: Colors.white70,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: Text(
                                _currentDropPoint!['category'] == 'Kendaraan' &&
                                        _routePoints.isNotEmpty &&
                                        (_sectionInvoiceItems[_currentSectionIndex] ??
                                                {})
                                            .isEmpty
                                    ? 'Skip'
                                    : 'Confirm',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
