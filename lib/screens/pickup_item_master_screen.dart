import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../services/fcm_service.dart';
import '../services/settings_service.dart';

/// PickupItemMasterScreen with QR code scanning and invoice list
class PickupItemMasterScreen extends StatefulWidget {
  const PickupItemMasterScreen({super.key});

  @override
  State<PickupItemMasterScreen> createState() => _PickupItemMasterScreenState();
}

class _PickupItemMasterScreenState extends State<PickupItemMasterScreen> {
  // Invoice list
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Scanner controller
  MobileScannerController? _scannerController;
  bool _isScannerActive = false;

  // Scanning cooldown to prevent rapid scans
  bool _isScanCooldown = false;

  // Current selected invoice for scanning
  Map<String, dynamic>? _selectedInvoice;
  List<Map<String, dynamic>> _scannedItems = [];

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();

  // API endpoint with sales_id parameter
  String get _apiEndpoint =>
      '${SettingsService.instance.baseUrl}/api/sell/pickup-items';

  @override
  void initState() {
    super.initState();
    _setupFCMCallback();
    _fetchInvoices();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _audioPlayer.dispose();
    // Clear callback when leaving screen
    FCMService.instance.onInvoiceDataReceived = null;
    super.dispose();
  }

  /// Setup FCM callback for this screen
  void _setupFCMCallback() {
    // Set callback for when new data is received
    FCMService.instance.onInvoiceDataReceived = (data) {
      log('Received invoice data from FCM: $data');
      // Refresh invoice list when FCM notification is received
      _fetchInvoices();
    };
  }

  /// Fetch invoices from API
  Future<void> _fetchInvoices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse(_apiEndpoint));
      debugPrint('API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        if (jsonResponse['success'] == true) {
          final List<dynamic> data = jsonResponse['data'];

          // Convert to invoice format
          setState(() {
            _invoices = data.map((item) {
              // Process list_barang to parse jumlah field
              final List<dynamic> listBarang = item['list_barang'];
              final processedBarang = listBarang.map((barang) {
                // Parse jumlah field (e.g., "-2 BOX" -> jlh: 2, satuan: BOX)
                final jumlahStr = barang['jumlah'] as String;
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
                  'barang_id': barang['barang_id'],
                  'nama_barang': barang['nama_barang'],
                  'kategori': barang['kategori'],
                  'locator': barang['locator'],
                  'jlh': qty,
                  'satuan': unit,
                };
              }).toList();

              return {
                'nojual': item['nojual'],
                'kategori': item['kategori'],
                'lantai': item['lantai'],
                'list_barang': processedBarang,
              };
            }).toList();
            _isLoading = false;
          });

          log('Fetched ${_invoices.length} invoices');
        } else {
          setState(() {
            _errorMessage =
                jsonResponse['message'] ?? 'Failed to load invoices';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to load invoices (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      log('Error fetching invoices: $e');
    }
  }

  /// Toggle QR scanner for a specific invoice
  void _toggleScanner(Map<String, dynamic>? invoice) {
    setState(() {
      _isScannerActive = !_isScannerActive;
      _selectedInvoice = invoice;

      if (_isScannerActive) {
        _scannedItems = [];
        _scannerController = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: false,
        );
      } else {
        _scannerController?.dispose();
        _scannerController = null;
        _selectedInvoice = null;
      }
    });
  }

  /// Handle barcode detection
  void _onBarcodeDetect(BarcodeCapture capture) {
    // Skip if in cooldown period
    if (_isScanCooldown) {
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
    try {
      // // Show a loading dialog while updating
      // Get.dialog(
      //   AlertDialog(
      //     title: const Row(
      //       children: [
      //         CircularProgressIndicator(),
      //         SizedBox(width: 16),
      //         Text('Updating Status...'),
      //       ],
      //     ),
      //     content: const Text('Please wait while we update the pickup status.'),
      //   ),
      //   barrierDismissible: false,
      // );

      // // Small delay to ensure dialog is closed before opening the next one
      // await Future.delayed(const Duration(milliseconds: 200));

      // Close loading dialog
      Get.back();

      // Get current timestamp in format: yyyy-MM-dd HH:mm:ss
      final now = DateTime.now();
      final timestamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      // Build API endpoint
      final String baseUrl = SettingsService.instance.baseUrl;
      final String updateEndpoint =
          '$baseUrl/api/sell/update-pickup-items/$invoiceNumber';

      // Get iduser from settings
      final String? iduser = SettingsService.instance.iduser;

      // Create request body with items array from scanned items
      final requestBody = {
        'items': _scannedItems.map((item) {
          return {'no': item['no'], 'waktu_ambil': timestamp};
        }).toList(),
        if (iduser != null && iduser.isNotEmpty) 'iduser': iduser,
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
                    onPressed: () async {
                      Get.back();
                      // Close scanner
                      _toggleScanner(null);

                      // Refresh invoice list
                      await _fetchInvoices();
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else {
            // API returned success=false
            // Close loading dialog
            Get.back();

            _showUpdateError(
              invoiceNumber,
              jsonResponse['message'] ?? 'Failed to update pickup status',
            );
          }
        } catch (e) {
          log('Error parsing response: $e');

          // Close loading dialog
          Get.back();

          _showUpdateError(invoiceNumber, 'Invalid response from server');
        }
      } else {
        // HTTP error
        // Close loading dialog
        Get.back();

        _showUpdateError(invoiceNumber, 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      log('Error updating pickup status: $e');
      // Close loading dialog
      Get.back();
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
              _toggleScanner(null);
            },
            child: const Text('Close Scanner'),
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

  /// Debug: Manually add next unscanned item
  void _debugAddNextItem() async {
    if (_selectedInvoice == null) {
      log('No invoice selected for debug add');
      return;
    }

    final listBarang = _selectedInvoice!['list_barang'] as List<dynamic>;

    // Find the next unscanned item
    final nextUnscanned = listBarang.firstWhereOrNull(
      (item) => !_scannedItems.any(
        (scanned) =>
            scanned['barang_id'] == item['barang_id'] &&
            scanned['locator'] == item['locator'],
      ),
    );

    if (nextUnscanned == null) {
      Get.snackbar(
        'Debug',
        'All items already scanned',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.blue,
        colorText: Colors.white,
        duration: const Duration(seconds: 1),
      );
      return;
    }

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
      _scannedItems.add(nextUnscanned);
    });

    // Show success message
    Get.snackbar(
      '🐛 Debug: Item Added',
      '${nextUnscanned['nama_barang']} (${_scannedItems.length}/${listBarang.length})',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.purple,
      colorText: Colors.white,
      duration: const Duration(seconds: 1),
    );

    // Check if all items scanned
    if (_scannedItems.length == listBarang.length) {
      final invoiceNumber = _selectedInvoice!['nojual'];
      await _updatePickupStatus(invoiceNumber);
    }
  }

  /// Process scanned QR code
  void _processScannedCode(String code) async {
    log('Scanned code: $code');

    // Set cooldown flag immediately
    setState(() {
      _isScanCooldown = true;
    });

    // Reset cooldown after 2 second
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isScanCooldown = false;
        });
      }
    });

    if (_selectedInvoice == null) {
      log('No invoice selected');
      return;
    }

    // Parse QR code format: {barang_id}|{locator}
    final parts = code.split('|');
    if (parts.length != 2) {
      // Invalid format
      Get.snackbar(
        'Invalid QR Code',
        'QR code format should be: barang_id|locator',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    final scannedBarangId = parts[0];
    final scannedLocator = parts[1];

    // Check if item exists in the invoice's list_barang
    final listBarang = _selectedInvoice!['list_barang'] as List<dynamic>;
    final matchingItem = listBarang.firstWhereOrNull(
      (item) =>
          item['barang_id'] == scannedBarangId &&
          item['locator'] == scannedLocator,
    );

    if (matchingItem != null) {
      // Check if already scanned
      final alreadyScanned = _scannedItems.any(
        (item) =>
            item['barang_id'] == scannedBarangId &&
            item['locator'] == scannedLocator,
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

        // Check if all items scanned
        if (_scannedItems.length == listBarang.length) {
          final invoiceNumber = _selectedInvoice!['nojual'];
          await _updatePickupStatus(invoiceNumber);
        }
      }
    } else {
      // Item not found in this invoice
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 500, amplitude: 255);
      }
      Get.dialog(
        AlertDialog(
          title: const Text('Item Not Found'),
          content: Text(
            'Item "$scannedBarangId" at location "$scannedLocator" is not part of this invoice.',
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: const Text('OK')),
          ],
        ),
      );
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
        automaticallyImplyLeading: false,
        actions: [
          if (_isScannerActive)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _toggleScanner(null),
              tooltip: 'Close Scanner',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchInvoices,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // QR Scanner Section
          if (_isScannerActive)
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
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: _onBarcodeDetect,
                  ),
                  // Scanner overlay
                  Center(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // Debug button
                  Positioned(
                    top: 20,
                    right: 20,
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.purple,
                      onPressed: _debugAddNextItem,
                      tooltip: 'Debug: Add Next Item',
                      child: const Icon(
                        Icons.bug_report,
                        color: Colors.white,
                        size: 20,
                      ),
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
                          Text(
                            'Scanning for: ${_selectedInvoice?['nojual'] ?? 'Unknown'}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Scanned: ${_scannedItems.length}/${(_selectedInvoice?['list_barang'] as List?)?.length ?? 0}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Items list when scanner is active
          if (_isScannerActive && _selectedInvoice != null)
            Expanded(
              child: Container(
                color: Colors.grey[100],
                child: Column(
                  children: [
                    // Header section
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
                          Text(
                            'Items to Scan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  _scannedItems.length ==
                                      (_selectedInvoice!['list_barang'] as List)
                                          .length
                                  ? Colors.green
                                  : Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_scannedItems.length}/${(_selectedInvoice!['list_barang'] as List).length}',
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
                    // Items list
                    Expanded(
                      child: ListView.builder(
                        itemCount:
                            (_selectedInvoice!['list_barang'] as List).length,
                        itemBuilder: (context, index) {
                          final item =
                              (_selectedInvoice!['list_barang'] as List)[index];
                          final isScanned = _scannedItems.any(
                            (scanned) =>
                                scanned['barang_id'] == item['barang_id'] &&
                                scanned['locator'] == item['locator'],
                          );
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isScanned
                                  ? Colors.green[50]
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isScanned
                                    ? Colors.green[300]!
                                    : Colors.grey[300]!,
                                width: isScanned ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                isScanned
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isScanned ? Colors.green : Colors.grey,
                                size: 28,
                              ),
                              title: Text(
                                item['barang_id'],
                                style: TextStyle(
                                  fontWeight: isScanned
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: 13,
                                  color: isScanned
                                      ? Colors.green[900]
                                      : Colors.black87,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['nama_barang'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[100],
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Qty: ${item['jlh']} ${item['satuan']}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blue[900],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.purple[100],
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.location_on,
                                                size: 12,
                                                color: Colors.purple[900],
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                item['locator'],
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.purple[900],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Invoice List Section
          if (!_isScannerActive)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blueAccent, Colors.lightBlue],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 60,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchInvoices,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _invoices.isEmpty
                    ? const Center(
                        child: Text(
                          'No invoices found',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchInvoices,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _invoices.length,
                          itemBuilder: (context, index) {
                            final invoice = _invoices[index];
                            return _buildInvoiceCard(invoice);
                          },
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// Show invoice details dialog
  void _showInvoiceDetails(Map<String, dynamic> invoice) {
    final List<dynamic> listBarang = invoice['list_barang'];

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            invoice['nojual'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Category: ${invoice['kategori']} | Floor: ${invoice['lantai']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
              ),
              // Items list
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: listBarang.length,
                  itemBuilder: (context, index) {
                    final item = listBarang[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
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
                                  item['barang_id'],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[900],
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 12,
                                      color: Colors.purple[900],
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      item['locator'],
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple[900],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['nama_barang'] ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Quantity: ${item['jlh']} ${item['satuan']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Start scanning button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Get.back();
                      _toggleScanner(invoice);
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text('Start Scanning (${listBarang.length} items)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build invoice card widget
  Widget _buildInvoiceCard(Map<String, dynamic> invoice) {
    final int itemCount = (invoice['list_barang'] as List).length;

    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          // Show invoice details
          _showInvoiceDetails(invoice);
        },
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon indicator
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shopping_bag,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              // Invoice details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice['nojual'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Category: ${invoice['kategori']}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.layers, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Floor: ${invoice['lantai']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.inventory_2,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$itemCount items',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Arrow icon
              Icon(Icons.arrow_forward_ios, size: 20, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
