import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../services/settings_service.dart';

/// Scan mode enum to track current scanning state
enum ScanMode {
  invoice, // Scanning QR code to fetch invoice/items list
  locator, // Scanning locator QR code
  item, // Scanning item QR codes
}

/// PickupItemScreen with QR code scanning workflow
class PickupItemScreen extends StatefulWidget {
  const PickupItemScreen({super.key});

  @override
  State<PickupItemScreen> createState() => _PickupItemScreenState();
}

class _PickupItemScreenState extends State<PickupItemScreen> {
  // Loading and error states
  bool _isLoading = false;
  String? _errorMessage;

  // Scanner controller
  MobileScannerController? _scannerController;

  // Scanning cooldown to prevent rapid scans
  bool _isScanCooldown = false;

  // Current scan mode
  ScanMode _currentScanMode = ScanMode.invoice;

  // Current invoice data after fetching
  Map<String, dynamic>? _currentInvoice;

  // Original QR code string from invoice scan
  String? _invoiceQrCode;

  // Active locator for item scanning
  String? _activeLocator;

  // Scanned items list
  List<Map<String, dynamic>> _scannedItems = [];

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Initialize scanner when screen opens
  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  /// Reset to initial state
  void _resetToInitialState() {
    setState(() {
      _currentScanMode = ScanMode.invoice;
      _currentInvoice = null;
      _invoiceQrCode = null;
      _activeLocator = null;
      _scannedItems = [];
      _errorMessage = null;
    });
  }

  /// Fetch invoice data from API using scanned QR code
  Future<void> _fetchInvoiceData(String qrCodeString) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final String baseUrl = SettingsService.instance.baseUrl;
      final String endpoint = '$baseUrl/api/sell/pickup-items/$qrCodeString';

      log('Fetching invoice data from: $endpoint');

      final response = await http.get(Uri.parse(endpoint));
      debugPrint('API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        if (jsonResponse['success'] == true) {
          try {
            final data = jsonResponse['data'];

            // Check if data is null
            if (data == null) {
              setState(() {
                _errorMessage = 'Invalid response: data is empty';
                _isLoading = false;
              });
              log('Error: Response data is null');
              return;
            }

            // Check if list_barang exists and is not null
            if (data['list_barang'] == null) {
              setState(() {
                _errorMessage = 'Invalid response: no items found';
                _isLoading = false;
              });
              log('Error: list_barang is null');
              return;
            }

            // Store the original QR code string
            _invoiceQrCode = qrCodeString;

            // Process list_barang to parse jumlah field
            final List<dynamic> listBarang = data['list_barang'];
            final processedBarang = listBarang.map((barang) {
              // Parse jumlah field (e.g., "-2 BOX" -> jlh: 2, satuan: BOX)
              final jumlahStr = (barang['jumlah'] ?? '') as String;
              final parts = jumlahStr.trim().split(' ');
              String qty = '0';
              String unit = '';

              if (parts.isNotEmpty) {
                qty = parts[0].replaceAll(
                  RegExp(r'[^0-9.]'),
                  '',
                ); // Remove non-numeric except decimal
                if (parts.length > 1) {
                  unit = parts.sublist(1).join(' ');
                }
              }

              return {
                'no': barang['no'],
                'barang_id': barang['barang_id'] ?? '',
                'nama_barang': barang['nama_barang'] ?? 'Unknown',
                'kategori': barang['kategori'] ?? '',
                'locator': barang['locator'] ?? '',
                'jlh': qty,
                'satuan': unit,
                'no_batch': barang['no_batch'] ?? '',
                'expired': barang['expired'] ?? '',
              };
            }).toList();

            setState(() {
              _currentInvoice = {
                'nojual': data['nojual'] ?? 'Unknown',
                'kategori': data['kategori'] ?? '',
                'lantai': data['lantai'] ?? '',
                'list_barang': processedBarang,
              };
              _currentScanMode = ScanMode.locator;
              _isLoading = false;
            });

            Get.snackbar(
              'Invoice Loaded',
              'Invoice ${data['nojual']} - ${processedBarang.length} items',
              snackPosition: SnackPosition.TOP,
              backgroundColor: Colors.green,
              colorText: Colors.white,
              duration: const Duration(seconds: 2),
            );

            log('Invoice loaded: ${data['nojual']}');
          } catch (e) {
            setState(() {
              _errorMessage = 'Error processing invoice data: ${e.toString()}';
              _isLoading = false;
            });
            log('Error processing invoice data: $e');
          }
        } else {
          setState(() {
            _errorMessage = jsonResponse['message'] ?? 'Failed to load invoice';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to load invoice (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      log('Error fetching invoice: $e');
    }
  }

  /// Handle barcode detection
  void _onBarcodeDetect(BarcodeCapture capture) {
    // Skip if in cooldown period or loading
    if (_isScanCooldown || _isLoading) {
      return;
    }

    final List<Barcode> barcodes = capture.barcodes;

    for (final barcode in barcodes) {
      final String? code = barcode.rawValue;

      if (code != null && code.isNotEmpty) {
        _processScannedCode(code);
        break; // Process only the first barcode
      }
    }
  }

  /// Update pickup status for completed scanning
  Future<void> _updatePickupStatus(String invoiceNumber) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current timestamp in format: yyyy-MM-dd HH:mm:ss
      final now = DateTime.now();
      final timestamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      // Build API endpoint
      final String baseUrl = SettingsService.instance.baseUrl;
      final String updateEndpoint = '$baseUrl/api/sell/update-pickup-items';

      // Get iduser from settings
      final String iduser = SettingsService.instance.iduser;

      // Create request body with items array from scanned items
      final requestBody = {
        'qr_code': _invoiceQrCode,
        'items': _scannedItems.map((item) {
          return {'no': item['no'], 'waktu_ambil': timestamp};
        }).toList(),
        'iduser': iduser,
      };

      log('Updating pickup status: $updateEndpoint');
      log('Request body: ${json.encode(requestBody)}');

      // Make PUT request
      final response = await http.put(
        Uri.parse(updateEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      log('Update response: ${response.statusCode} - ${response.body}');

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200) {
        try {
          final jsonResponse = json.decode(response.body);

          if (jsonResponse['success'] == true) {
            // Show success dialog
            Get.dialog(
              AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 32),
                    SizedBox(width: 12),
                    Text('Success!'),
                  ],
                ),
                content: Text(
                  'All items for invoice $invoiceNumber have been picked up and status updated.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Get.back();
                      // Reset to initial state for next scan
                      _resetToInitialState();
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else {
            _showUpdateError(
              invoiceNumber,
              jsonResponse['message'] ?? 'Failed to update pickup status',
            );
          }
        } catch (e) {
          log('Error parsing response: $e');
          _showUpdateError(invoiceNumber, 'Invalid response from server');
        }
      } else {
        _showUpdateError(invoiceNumber, 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      log('Error updating pickup status: $e');
      setState(() {
        _isLoading = false;
      });
      _showUpdateError(invoiceNumber, 'Network error: $e');
    }
  }

  /// Show error dialog for update failure
  void _showUpdateError(String invoiceNumber, String errorMessage) {
    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Text('Update Failed'),
          ],
        ),
        content: Text(
          'Failed to update pickup status for invoice $invoiceNumber.\n\nError: $errorMessage',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              _resetToInitialState();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              _updatePickupStatus(invoiceNumber);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Debug: Manually add next unscanned item for active locator
  void _debugAddNextItem() {
    if (_currentInvoice == null || _activeLocator == null) {
      log('No invoice or locator active for debug add');
      return;
    }

    final TextEditingController controller = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text('🐛 Debug: Enter Item Code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter item QR code',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            Get.back();
            if (value.isNotEmpty) {
              _processItemScan(value);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              Get.back();
              if (value.isNotEmpty) {
                _processItemScan(value);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Debug: Fill invoice QR code with test data
  void _debugFillInvoiceQR() {
    Get.dialog(
      AlertDialog(
        title: const Text('🐛 Debug: Enter Invoice Code'),
        content: SingleChildScrollView(
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter invoice QR code string',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              Get.back();
              if (value.isNotEmpty) {
                _fetchInvoiceData(value);
              }
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Get.back();
              // Use a default test invoice code
              _fetchInvoiceData('1-SPB-P-0725-000001');
            },
            child: const Text('Use Default'),
          ),
        ],
      ),
    );
  }

  /// Debug: Manually enter a locator code
  void _debugSelectLocator() {
    if (_currentInvoice == null) {
      Get.snackbar(
        'Debug',
        'No invoice loaded',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final TextEditingController controller = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text('🐛 Debug: Enter Locator Code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter locator code',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            Get.back();
            if (value.isNotEmpty) {
              _processLocatorScan(value);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              Get.back();
              if (value.isNotEmpty) {
                _processLocatorScan(value);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Check if all items for the active locator have been scanned
  void _checkLocatorCompletion() {
    if (_currentInvoice == null) return;

    final listBarang = _currentInvoice!['list_barang'] as List<dynamic>;

    // Check if all items for current locator are scanned
    if (_activeLocator != null) {
      final locatorItems = listBarang
          .where((item) => item['locator'] == _activeLocator)
          .toList();
      final scannedLocatorItems = _scannedItems
          .where((item) => item['locator'] == _activeLocator)
          .toList();

      if (scannedLocatorItems.length == locatorItems.length) {
        // All items for this locator are scanned — user must press Confirm
        setState(() {}); // rebuild to enable confirm button
      }
    }
  }

  /// Process scanned QR code based on current scan mode
  void _processScannedCode(String code) async {
    log('Scanned code: $code (Mode: $_currentScanMode)');

    // Set cooldown flag immediately
    setState(() {
      _isScanCooldown = true;
    });

    // Reset cooldown after 1 second
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isScanCooldown = false;
        });
      }
    });

    switch (_currentScanMode) {
      case ScanMode.invoice:
        // Fetch invoice data with the scanned QR code
        await _fetchInvoiceData(code);
        break;

      case ScanMode.locator:
        // Process locator scan
        _processLocatorScan(code);
        break;

      case ScanMode.item:
        // Process item scan
        await _processItemScan(code);
        break;
    }
  }

  /// Process locator QR code scan
  void _processLocatorScan(String locatorCode) {
    if (_currentInvoice == null) return;

    final listBarang = _currentInvoice!['list_barang'] as List<dynamic>;

    // Check if this locator exists in the invoice
    final locatorExists = listBarang.any(
      (item) => item['locator'] == locatorCode,
    );

    if (locatorExists) {
      // Check if all items for this locator are already scanned
      final locatorItems = listBarang
          .where((item) => item['locator'] == locatorCode)
          .toList();
      final scannedLocatorItems = _scannedItems
          .where((item) => item['locator'] == locatorCode)
          .toList();

      if (scannedLocatorItems.length == locatorItems.length) {
        // All items for this locator already scanned
        if (Vibration.hasVibrator() != null) {
          Vibration.vibrate(duration: 300, amplitude: 128);
        }
        Get.snackbar(
          'Locator Complete',
          'All items for locator $locatorCode have already been scanned',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      // Activate this locator
      setState(() {
        _activeLocator = locatorCode;
        _currentScanMode = ScanMode.item;
      });

      // Play sound
      try {
        _audioPlayer.play(AssetSource('sounds/success.mp3'));
      } catch (e) {
        log('Error playing sound: $e');
      }

      // Vibrate
      if (Vibration.hasVibrator() != null) {
        Vibration.vibrate(duration: 200);
      }

      final remainingItems = locatorItems.length - scannedLocatorItems.length;
      Get.snackbar(
        'Locator Active',
        'Locator $locatorCode - $remainingItems items to scan',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } else {
      // Locator not found in this invoice
      if (Vibration.hasVibrator() != null) {
        Vibration.vibrate(duration: 500, amplitude: 255);
      }
      Get.snackbar(
        'Invalid Locator',
        'Locator $locatorCode is not part of this invoice',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Process item QR code scan
  Future<void> _processItemScan(String code) async {
    if (_currentInvoice == null || _activeLocator == null) {
      log('No invoice or locator active');
      return;
    }

    final listBarang = _currentInvoice!['list_barang'] as List<dynamic>;

    // Find matching item with the active locator

    var id = code.split('|')[0];
    var locator = code.split('|')[1];
    final matchingItem = listBarang.firstWhereOrNull(
      (item) => item['barang_id'] == id && item['locator'] == locator,
    );

    if (matchingItem != null) {
      // Check if already scanned
      final alreadyScanned = _scannedItems.any(
        (item) => item['barang_id'] == id && item['locator'] == locator,
      );

      if (alreadyScanned) {
        // Already scanned
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 500, amplitude: 255);
        }
        Get.snackbar(
          'Already Scanned',
          'Item ${matchingItem['nama_barang']} has already been scanned',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      } else {
        // Play success sound
        try {
          await _audioPlayer.play(AssetSource('sounds/success.mp3'));
        } catch (e) {
          log('Error playing sound: $e');
        }

        // Vibrate
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 200);
        }

        // Add to scanned items
        setState(() {
          _scannedItems.add(matchingItem);
        });

        // Show success message
        Get.snackbar(
          'Item Scanned',
          '${matchingItem['nama_barang']} (${_scannedItems.length}/${listBarang.length})',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 1),
        );

        // Check if locator is complete or all items are done
        _checkLocatorCompletion();
      }
    } else {
      // Check if item exists but with different locator
      final itemWithDifferentLocator = listBarang.firstWhereOrNull(
        (item) => item['barang_id'] == id,
      );

      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 500, amplitude: 255);
      }

      if (itemWithDifferentLocator != null) {
        // Item exists but not at this locator
        Get.snackbar(
          'Wrong Locator',
          'Item $id belongs to locator ${itemWithDifferentLocator['locator']}, not $_activeLocator',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      } else {
        // Item not found in this invoice at all
        Get.snackbar(
          'Item Not Found',
          'Item $id  is not part of this invoice',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  /// Confirm completion of current locator and return to locator scanning mode
  void _confirmLocatorDone() {
    if (_currentInvoice == null) return;

    final listBarang = _currentInvoice!['list_barang'] as List<dynamic>;

    // If all invoice items are scanned, submit the pickup status
    if (_scannedItems.length == listBarang.length) {
      final invoiceNumber = _currentInvoice!['nojual'];
      _updatePickupStatus(invoiceNumber);
      return;
    }

    // Otherwise go back to locator scanning mode
    setState(() {
      _activeLocator = null;
      _currentScanMode = ScanMode.locator;
    });
    Get.snackbar(
      'Locator Complete',
      'All items for this location scanned. Scan next locator.',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.blue,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  /// Get scan mode display text
  String _getScanModeText() {
    switch (_currentScanMode) {
      case ScanMode.invoice:
        return 'Scan Invoice QR Code';
      case ScanMode.locator:
        return 'Scan Locator QR Code';
      case ScanMode.item:
        return 'Scan Item: $_activeLocator';
    }
  }

  /// Get scan mode color
  Color _getScanModeColor() {
    switch (_currentScanMode) {
      case ScanMode.invoice:
        return Colors.blue;
      case ScanMode.locator:
        return Colors.purple;
      case ScanMode.item:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pickup Items',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
        actions: [
          if (_currentInvoice != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetToInitialState,
              tooltip: 'Reset',
            ),
        ],
      ),
      body: Column(
        children: [
          // QR Scanner Section
          Container(
            height: 300,
            decoration: const BoxDecoration(
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              children: [
                if (_scannerController != null)
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: _onBarcodeDetect,
                  ),
                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                // Scanner overlay
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: _getScanModeColor(), width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                // Debug buttons based on current scan mode
                Positioned(
                  top: 20,
                  right: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Debug button for Invoice mode
                      if (_currentScanMode == ScanMode.invoice)
                        FloatingActionButton(
                          mini: true,
                          heroTag: 'debug_invoice',
                          backgroundColor: Colors.blue,
                          onPressed: _debugFillInvoiceQR,
                          tooltip: 'Debug: Fill Invoice QR',
                          child: const Icon(
                            Icons.receipt_long,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      // Debug button for Locator mode
                      if (_currentScanMode == ScanMode.locator)
                        FloatingActionButton(
                          mini: true,
                          heroTag: 'debug_locator',
                          backgroundColor: Colors.purple,
                          onPressed: _debugSelectLocator,
                          tooltip: 'Debug: Select Locator',
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      // Debug button for Item mode
                      if (_currentScanMode == ScanMode.item &&
                          _activeLocator != null)
                        FloatingActionButton(
                          mini: true,
                          heroTag: 'debug_item',
                          backgroundColor: Colors.green,
                          onPressed: _debugAddNextItem,
                          tooltip: 'Debug: Add Next Item',
                          child: const Icon(
                            Icons.add_box,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ),
                // Scanner instructions
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    color: Colors.black54,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _getScanModeColor(),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _getScanModeText(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_currentInvoice != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Invoice: ${_currentInvoice!['nojual']} | Scanned: ${_scannedItems.length}/${(_currentInvoice!['list_barang'] as List).length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red[100],
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _errorMessage = null),
                  ),
                ],
              ),
            ),

          // Items list when invoice is loaded
          if (_currentInvoice != null)
            Expanded(
              child: Container(
                color: Colors.grey[100],
                child: Column(
                  children: [
                    // Header section with locator info
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.blue.shade50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.inventory_2,
                            size: 20,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Items to Scan',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                                if (_activeLocator != null)
                                  Text(
                                    'Active Locator: $_activeLocator',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.purple.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  _scannedItems.length ==
                                      (_currentInvoice!['list_barang'] as List)
                                          .length
                                  ? Colors.green
                                  : Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_scannedItems.length}/${(_currentInvoice!['list_barang'] as List).length}',
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

                    // Items list grouped by locator
                    Expanded(child: _buildItemsList()),

                    // Confirm button in item scan mode
                    if (_currentScanMode == ScanMode.item &&
                        _activeLocator != null)
                      Builder(
                        builder: (context) {
                          final listBarang =
                              _currentInvoice!['list_barang'] as List<dynamic>;
                          final locatorItems = listBarang
                              .where(
                                (item) => item['locator'] == _activeLocator,
                              )
                              .toList();
                          final scannedCount = _scannedItems
                              .where(
                                (item) => item['locator'] == _activeLocator,
                              )
                              .length;
                          final allScanned =
                              scannedCount == locatorItems.length;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ElevatedButton.icon(
                              onPressed: allScanned
                                  ? _confirmLocatorDone
                                  : null,
                              icon: const Icon(Icons.check_circle),
                              label: Text(
                                'Confirm ($scannedCount/${locatorItems.length})',
                              ),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey[300],
                                disabledForegroundColor: Colors.grey[600],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),

          // Initial state - prompt to scan invoice
          if (_currentInvoice == null && !_isLoading && _errorMessage == null)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blueAccent, Colors.lightBlue],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 80,
                        color: Colors.white,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Scan Invoice QR Code',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Point your camera at the invoice QR code to start',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build items list grouped by locator
  Widget _buildItemsList() {
    final listBarang = _currentInvoice!['list_barang'] as List<dynamic>;

    // Group items by locator
    final Map<String, List<dynamic>> groupedItems = {};
    for (final item in listBarang) {
      final locator = item['locator'] as String;
      groupedItems.putIfAbsent(locator, () => []);
      groupedItems[locator]!.add(item);
    }

    // Sort locators
    final sortedLocators = groupedItems.keys.toList()..sort();

    return ListView.builder(
      itemCount: sortedLocators.length,
      itemBuilder: (context, locatorIndex) {
        final locator = sortedLocators[locatorIndex];
        final items = groupedItems[locator]!;
        final isActiveLocator = _activeLocator == locator;
        final scannedCount = items
            .where(
              (item) => _scannedItems.any(
                (scanned) =>
                    scanned['barang_id'] == item['barang_id'] &&
                    scanned['locator'] == item['locator'],
              ),
            )
            .length;
        final isComplete = scannedCount == items.length;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActiveLocator
                ? Colors.purple[50]
                : isComplete
                ? Colors.green[50]
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActiveLocator
                  ? Colors.purple[300]!
                  : isComplete
                  ? Colors.green[300]!
                  : Colors.grey[300]!,
              width: isActiveLocator ? 2 : 1,
            ),
          ),
          child: ExpansionTile(
            key: ValueKey('${locator}_$isActiveLocator'),
            initiallyExpanded: isActiveLocator,
            leading: Icon(
              isComplete
                  ? Icons.check_circle
                  : isActiveLocator
                  ? Icons.location_on
                  : Icons.radio_button_unchecked,
              color: isComplete
                  ? Colors.green
                  : isActiveLocator
                  ? Colors.purple
                  : Colors.grey,
            ),
            title: Text(
              'Locator: $locator',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isActiveLocator
                    ? Colors.purple[900]
                    : isComplete
                    ? Colors.green[900]
                    : Colors.black87,
              ),
            ),
            subtitle: Text(
              'Scanned: $scannedCount/${items.length}',
              style: TextStyle(
                fontSize: 12,
                color: isComplete ? Colors.green : Colors.grey[600],
              ),
            ),
            children: items.map((item) {
              final isScanned = _scannedItems.any(
                (scanned) =>
                    scanned['barang_id'] == item['barang_id'] &&
                    scanned['locator'] == item['locator'],
              );
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isScanned ? Colors.green[100] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      isScanned
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isScanned ? Colors.green : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['nama_barang'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            "${item['barang_id']} | ${item['no_batch']} | ${item['expired']}",
                            style: TextStyle(
                              fontSize: 12,
                              color: isScanned
                                  ? Colors.green[900]
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${item['jlh']} ${item['satuan']}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
