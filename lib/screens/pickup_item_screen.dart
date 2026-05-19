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

  // Whether to show the initial mode selection screen
  bool _showInitialButtons = true;

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

  // Admin: list of all invoices (admin-only view)
  bool _showAdminList = false;
  int _adminSelectedTab = 0;
  List<Map<String, dynamic>> _adminInvoiceList = [];

  // Allow programmatic pop after confirmation
  bool _canPop = false;

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
    // Fire-and-forget cancel if we leave mid-session
    if (_currentInvoice != null) {
      _cancelPickupItems();
    }
    super.dispose();
  }

  /// Cancel pickup — revert item statuses on the server
  Future<void> _cancelPickupItems() async {
    if (_currentInvoice == null) return;

    try {
      final String baseUrl = SettingsService.instance.baseUrl;
      final String iduser = SettingsService.instance.iduser;
      final String cancelEndpoint = '$baseUrl/api/sell/cancel-pickup-items';
      final listBarang = _currentInvoice!['list_barang'] as List<dynamic>;

      final requestBody = {
        'qr_code': _invoiceQrCode,
        'items': listBarang.map((item) {
          return {'nobd': item['nobd']};
        }).toList(),
        'iduser': iduser,
      };

      log('Cancelling pickup: $cancelEndpoint');
      log('Cancel body: ${json.encode(requestBody)}');

      await http.put(
        Uri.parse(cancelEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );
    } catch (e) {
      log('Error cancelling pickup: $e');
    }
  }

  /// Confirm cancellation when items have already been scanned, then navigate back
  Future<void> _handleBack() async {
    if (_showAdminList) {
      setState(() {
        _showAdminList = false;
        _showInitialButtons = true;
      });
      return;
    }
    if (!_showInitialButtons && _currentInvoice == null) {
      // In scan-QR mode before any invoice is loaded — go back to mode selection
      setState(() {
        _showInitialButtons = true;
        _currentScanMode = ScanMode.invoice;
      });
      return;
    }
    if (_currentInvoice != null) {
      _scannerController?.stop();
      final confirmed = await Get.dialog<bool>(
        AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
              SizedBox(width: 12),
              Text('Cancel Pickup?'),
            ],
          ),
          content: const Text(
            'You have scanned items. Leaving now will cancel this pickup session and revert item statuses.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Get.back(result: false);
                _scannerController?.start();
              },
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () {
                Get.back(result: true);
              },
              child: const Text(
                'Cancel Pickup',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      await _resetToInitialState();
      return;
    }
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.back();
    });
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
  Future<void> _resetToInitialState() async {
    await _cancelPickupItems();
    setState(() {
      _showInitialButtons = true;
      _showAdminList = false;
      _adminInvoiceList = [];
      _currentScanMode = ScanMode.invoice;
      _currentInvoice = null;
      _invoiceQrCode = null;
      _activeLocator = null;
      _scannedItems = [];
      _errorMessage = null;
    });
  }

  /// Fetch all pending orders for admin (no floor filter)
  Future<void> _fetchAdminOrderList({String status = 'pending'}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final String baseUrl = SettingsService.instance.baseUrl;
      final String iduser = SettingsService.instance.iduser;
      final uri = Uri.parse(
        '$baseUrl/api/sell/pickup-items?iduser=${Uri.encodeQueryComponent(iduser)}&status_pickup=${Uri.encodeQueryComponent(status)}',
      );
      log('Fetching admin order list: $uri');
      final response = await http.get(uri);
      log('API Response: ${response.statusCode} - ${response.body}');
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['success'] == true) {
          final data = jsonResponse['data'];
          if (data == null || (data is List && data.isEmpty)) {
            setState(() {
              _adminInvoiceList = [];
              _adminSelectedTab = status == 'selesai' ? 1 : 0;
              _showInitialButtons = false;
              _showAdminList = true;
              _errorMessage = null;
              _isLoading = false;
            });
            return;
          }
          final List<dynamic> invoices = data is List ? data : [data];
          setState(() {
            _adminInvoiceList = invoices.map<Map<String, dynamic>>((inv) {
              final rawBarang = inv['list_barang'];
              final List<dynamic> listBarang = rawBarang == null
                  ? []
                  : rawBarang is List
                  ? rawBarang
                  : (rawBarang as Map).values.toList();
              return {
                'nojual': inv['nojual'] ?? '',
                'no_qr': inv['no_qr'],
                'status_pickup': inv['status_pickup'] ?? 'pending',
                'list_barang': listBarang,
              };
            }).toList();
            _showInitialButtons = false;
            _showAdminList = true;
            _adminSelectedTab = status == 'selesai' ? 1 : 0;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = jsonResponse['message'] ?? 'Failed to load orders';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to load orders (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      log('Error fetching admin order list: $e');
    }
  }

  /// Process a selected admin invoice and start the pickup workflow
  void _startPickupFromAdminInvoice(Map<String, dynamic> invoice) {
    final rawBarang = invoice['list_barang'] as List<dynamic>;
    final List<Map<String, dynamic>> processedBarang = rawBarang.map((barang) {
      final jumlahStr = (barang['jumlah'] ?? '') as String;
      final parts = jumlahStr.trim().split(' ');
      String qty = '0';
      String unit = '';
      if (parts.isNotEmpty) {
        qty = parts[0].replaceAll(RegExp(r'[^0-9.]'), '');
        if (parts.length > 1) unit = parts.sublist(1).join(' ');
      }
      return {
        'no': barang['no'],
        'nojual': invoice['nojual'] ?? '',
        'barang_id': barang['barang_id'] ?? '',
        'nama_barang': barang['nama_barang'] ?? 'Unknown',
        'kategori': barang['kategori'] ?? '',
        'locator': barang['locator'] ?? '',
        'jlh': qty,
        'satuan': unit,
        'no_batch': barang['no_batch'] ?? '',
        'nobd': barang['nobd'] ?? '',
        'expired': barang['expired'] ?? '',
      };
    }).toList();
    setState(() {
      _currentInvoice = {
        'nojual': invoice['nojual'] ?? 'Admin Order',
        'kategori': '',
        'lantai': '',
        'list_barang': processedBarang,
      };
      _invoiceQrCode = (invoice['no_qr'] ?? invoice['nojual']) as String?;
      _showAdminList = false;
      _showInitialButtons = false;
      _currentScanMode = ScanMode.locator;
    });
  }

  /// Show invoice detail in a bottom sheet
  void _showAdminInvoiceDetail(Map<String, dynamic> invoice) {
    final items = invoice['list_barang'] as List<dynamic>;

    // Group items by lantai
    final Map<String, List<dynamic>> byFloor = {};
    for (final item in items) {
      final floor = (item['lantai'] ?? '-').toString();
      byFloor.putIfAbsent(floor, () => []).add(item);
    }
    final floors = byFloor.keys.toList();

    // Build flat list: alternating floor-header rows and item rows
    final List<Map<String, dynamic>> rows = [];
    for (final floor in floors) {
      rows.add({'type': 'header', 'floor': floor});
      final floorItems = byFloor[floor]!;
      for (int i = 0; i < floorItems.length; i++) {
        rows.add({'type': 'item', 'item': floorItems[i], 'indexInGroup': i});
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          invoice['nojual'] as String,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${items.length} item${items.length != 1 ? 's' : ''}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row['type'] == 'header') {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: Colors.blueAccent.withOpacity(0.1),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.layers,
                                size: 16,
                                color: Colors.blueAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Lantai ${row['floor']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(${byFloor[row['floor']]!.length} item${byFloor[row['floor']]!.length != 1 ? 's' : ''})',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final item = row['item'] as Map<String, dynamic>;
                      final itemIndex = row['indexInGroup'] as int;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${itemIndex + 1}',
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['nama_barang'] as String? ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Locator: ${item['locator'] ?? '-'}  |  Qty: ${item['jumlah'] ?? '-'}',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if ((item['no_batch'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Text(
                                          'Batch: ${item['no_batch']}  |  Exp: ${item['expired'] ?? '-'}',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Builder(
                                        builder: (context) {
                                          final diambil =
                                              (item['diambil'] ?? 'N')
                                                  .toString();
                                          if (diambil == 'Y') {
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _statusChip(
                                                  'Diambil',
                                                  Colors.green,
                                                ),
                                                if ((item['waktu_ambil'] ?? '')
                                                    .toString()
                                                    .isNotEmpty)
                                                  Text(
                                                    'Waktu Ambil: ${item['waktu_ambil']}',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                if ((item['iduser_ambil'] ?? '')
                                                    .toString()
                                                    .isNotEmpty)
                                                  Text(
                                                    'User: ${item['iduser_ambil']}',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                              ],
                                            );
                                          } else if (diambil == 'P') {
                                            return _statusChip(
                                              'Diproses',
                                              Colors.blue,
                                            );
                                          } else {
                                            return _statusChip(
                                              'Belum diambil',
                                              Colors.grey,
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _adminTabButton(String label, int tabIndex, String status) {
    final selected = _adminSelectedTab == tabIndex;
    return GestureDetector(
      onTap: () => _fetchAdminOrderList(status: status),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color == Colors.grey ? Colors.grey.shade700 : color,
        ),
      ),
    );
  }

  /// Build admin invoice list screen
  Widget _buildAdminInvoiceListScreen() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.blueAccent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  '${_adminInvoiceList.length} Order${_adminInvoiceList.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(child: _adminTabButton('Pending', 0, 'pending')),
                  Expanded(child: _adminTabButton('Complete', 1, 'selesai')),
                ],
              ),
            ],
          ),
        ),
        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: Colors.red.shade700,
                  onPressed: () => setState(() => _errorMessage = null),
                ),
              ],
            ),
          ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _adminInvoiceList.isEmpty
              ? const Center(
                  child: Text(
                    'No data',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _adminInvoiceList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final invoice = _adminInvoiceList[index];
                    final itemCount = (invoice['list_barang'] as List).length;
                    final status =
                        (invoice['status_pickup'] ?? 'pending') as String;
                    final isSelesai = status == 'selesai';
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSelesai
                                ? Colors.green.shade100
                                : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.receipt_long,
                            color: isSelesai
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                        title: Text(
                          invoice['nojual'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              '$itemCount item${itemCount != 1 ? 's' : ''}',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSelesai
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelesai
                                        ? Icons.check_circle_outline
                                        : Icons.hourglass_empty,
                                    size: 11,
                                    color: isSelesai
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    isSelesai ? 'Selesai' : 'Pending',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isSelesai
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showAdminInvoiceDetail(invoice),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Fetch new order items from API using sales_id and assigned_floor
  Future<void> _fetchNewOrderData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final String baseUrl = SettingsService.instance.baseUrl;
      final String iduser = SettingsService.instance.iduser;
      final List<String> assignedFloors =
          SettingsService.instance.assignedFloor;

      final queryParts = [
        'iduser=${Uri.encodeQueryComponent(iduser)}',
        ...assignedFloors.map(
          (f) => 'assigned_floor[]=${Uri.encodeQueryComponent(f)}',
        ),
      ];
      final uriWithParams = Uri.parse(
        '$baseUrl/api/sell/pickup-items?${queryParts.join('&')}',
      );

      log('Fetching new order data from: $uriWithParams');

      final response = await http.get(uriWithParams);
      debugPrint('API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        if (jsonResponse['success'] == true) {
          try {
            final data = jsonResponse['data'];

            if (data == null || (data is List && data.isEmpty)) {
              setState(() => _isLoading = false);
              Get.dialog(
                AlertDialog(
                  title: const Text('No Orders'),
                  content: const Text(
                    'No pending orders found for the selected floor(s).',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
              return;
            }

            // data is a List of invoices — flatten all items across all invoices
            final List<dynamic> invoices = data is List ? data : [data];

            _invoiceQrCode = invoices[0]['no_qr'];

            final List<Map<String, dynamic>> processedBarang = [];

            for (final invoice in invoices) {
              final rawBarang = invoice['list_barang'];
              if (rawBarang == null) continue;

              final List<dynamic> listBarang = rawBarang is List
                  ? rawBarang
                  : (rawBarang as Map).values.toList();

              for (final barang in listBarang) {
                final jumlahStr = (barang['jumlah'] ?? '') as String;
                final parts = jumlahStr.trim().split(' ');
                String qty = '0';
                String unit = '';

                if (parts.isNotEmpty) {
                  qty = parts[0].replaceAll(RegExp(r'[^0-9.]'), '');
                  if (parts.length > 1) {
                    unit = parts.sublist(1).join(' ');
                  }
                }

                processedBarang.add({
                  'no': barang['no'],
                  'nojual': invoice['nojual'] ?? '',
                  'barang_id': barang['barang_id'] ?? '',
                  'nama_barang': barang['nama_barang'] ?? 'Unknown',
                  'kategori': barang['kategori'] ?? invoice['kategori'] ?? '',
                  'locator': barang['locator'] ?? '',
                  'jlh': qty,
                  'satuan': unit,
                  'no_batch': barang['no_batch'] ?? '',
                  'nobd': barang['nobd'] ?? '',
                  'expired': barang['expired'] ?? '',
                });
              }
            }

            if (processedBarang.isEmpty) {
              setState(() => _isLoading = false);
              Get.dialog(
                AlertDialog(
                  title: const Text('No Items'),
                  content: const Text('No items found in the order data.'),
                  actions: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
              return;
            }

            // Use a combined label when there are multiple invoices
            final invoiceLabel = invoices.length == 1
                ? (invoices.first['nojual'] ?? 'New Order')
                : '${invoices.length} invoices';

            setState(() {
              _currentInvoice = {
                'nojual': invoiceLabel,
                'kategori': '',
                'lantai': assignedFloors.join(', '),
                'list_barang': processedBarang,
              };
              _showInitialButtons = false;
              _currentScanMode = ScanMode.locator;
              _isLoading = false;
            });

            Get.snackbar(
              'Order Loaded',
              '${processedBarang.length} items to pick up',
              snackPosition: SnackPosition.TOP,
              backgroundColor: Colors.green,
              colorText: Colors.white,
              duration: const Duration(seconds: 2),
            );

            log(
              'New order loaded: $invoiceLabel (${processedBarang.length} items)',
            );
          } catch (e) {
            setState(() {
              _errorMessage = 'Error processing order data: ${e.toString()}';
              _isLoading = false;
            });
            log('Error processing new order data: $e');
          }
        } else {
          setState(() {
            _errorMessage =
                jsonResponse['message'] ?? 'Failed to load new order';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to load new order (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      log('Error fetching new order: $e');
    }
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
              setState(() => _isLoading = false);
              log('Error: Response data is null');
              Get.dialog(
                AlertDialog(
                  title: const Text('No Data'),
                  content: const Text(
                    'No invoice data returned from the server.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
              return;
            }

            // Check if list_barang exists and is not null
            if (data['list_barang'] == null) {
              setState(() => _isLoading = false);
              log('Error: list_barang is null');
              Get.dialog(
                AlertDialog(
                  title: const Text('No Items'),
                  content: const Text('No items found for this invoice.'),
                  actions: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
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
                'nobd': barang['nobd'] ?? '',
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
          return {'nobd': item['nobd'], 'waktu_ambil': timestamp};
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
                      // Reset to initial state for next scan (no cancel — items already submitted)
                      setState(() {
                        _showInitialButtons = true;
                        _currentScanMode = ScanMode.invoice;
                        _currentInvoice = null;
                        _invoiceQrCode = null;
                        _activeLocator = null;
                        _scannedItems = [];
                        _errorMessage = null;
                      });
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
        if (_scannedItems.length == listBarang.length) {
          // All invoice items complete — rebuild to show confirm button
          setState(() {});
        } else {
          // Auto-advance to next locator after a brief delay
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() {
                _activeLocator = null;
                _currentScanMode = ScanMode.locator;
              });
              Get.snackbar(
                'Locator Complete',
                'All items scanned. Scan next locator.',
                snackPosition: SnackPosition.TOP,
                backgroundColor: Colors.blue,
                colorText: Colors.white,
                duration: const Duration(seconds: 2),
              );
            }
          });
        }
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
    print(listBarang);

    var id = code.split('|')[0];
    var nobd = code.split('|')[1];
    final matchingItem = listBarang.firstWhereOrNull(
      (item) =>
          item['barang_id'] == id &&
          item['nobd'] == nobd &&
          item['locator'] == _activeLocator,
    );

    if (matchingItem != null) {
      // Check if already scanned
      final alreadyScanned = _scannedItems.any(
        (item) => item['barang_id'] == id && item['nobd'] == nobd,
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

  /// Build initial mode selection screen with 'New Order' and 'Scan QR' buttons
  Widget _buildInitialButtonsScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueAccent, Colors.lightBlue],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Loading order...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 80,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Pickup Items',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose how to start your pickup session',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              color: Colors.red.shade700,
                              onPressed: () =>
                                  setState(() => _errorMessage = null),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    // New Order button
                    if (SettingsService.instance.iduser != 'admin')
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _fetchNewOrderData,
                          icon: const Icon(Icons.add_shopping_cart, size: 24),
                          label: const Text(
                            'New Order',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    if (SettingsService.instance.iduser != 'admin')
                      const SizedBox(height: 16),
                    // Scan QR button
                    if (SettingsService.instance.iduser != 'admin')
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _showInitialButtons = false;
                              _currentScanMode = ScanMode.invoice;
                            });
                          },
                          icon: const Icon(Icons.qr_code_scanner, size: 24),
                          label: const Text(
                            'Scan QR',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    // Admin buttons
                    if (SettingsService.instance.iduser == 'admin') ...[
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _fetchNewOrderData,
                          icon: const Icon(Icons.add_shopping_cart, size: 24),
                          label: const Text(
                            'New Order',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () => setState(() {
                            _showInitialButtons = false;
                            _currentScanMode = ScanMode.invoice;
                          }),
                          icon: const Icon(Icons.qr_code_scanner, size: 24),
                          label: const Text(
                            'Scan QR',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _fetchAdminOrderList,
                          icon: const Icon(Icons.list_alt, size: 24),
                          label: const Text(
                            'All Orders',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Pickup Items',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.blueAccent,
          elevation: 0,
          leading: (_showInitialButtons)
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _handleBack,
                ),
          automaticallyImplyLeading: false,
          actions: [
            if (!_showInitialButtons)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _resetToInitialState,
                tooltip: 'Reset',
              ),
          ],
        ),
        body: _showInitialButtons
            ? _buildInitialButtonsScreen()
            : _showAdminList
            ? _buildAdminInvoiceListScreen()
            : Column(
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
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        // Scanner overlay
                        Center(
                          child: Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _getScanModeColor(),
                                width: 3,
                              ),
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
                            onPressed: () =>
                                setState(() => _errorMessage = null),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                              (_currentInvoice!['list_barang']
                                                      as List)
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

                            // Confirm button — shown only when all invoice items are scanned
                            if (_currentInvoice != null &&
                                _scannedItems.length ==
                                    (_currentInvoice!['list_barang'] as List)
                                        .length)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: () => _updatePickupStatus(
                                    _currentInvoice!['nojual'],
                                  ),
                                  icon: const Icon(Icons.check_circle),
                                  label: Text(
                                    'Confirm All (${_scannedItems.length}/${(_currentInvoice!['list_barang'] as List).length})',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  // Initial state in scan QR workflow - prompt to scan invoice
                  if (_currentInvoice == null &&
                      !_isLoading &&
                      _errorMessage == null)
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
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
