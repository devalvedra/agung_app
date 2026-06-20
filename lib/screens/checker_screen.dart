import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/settings_service.dart';

class CheckerScreen extends StatefulWidget {
  const CheckerScreen({super.key});

  @override
  State<CheckerScreen> createState() => _CheckerScreenState();
}

class _CheckerScreenState extends State<CheckerScreen> {
  MobileScannerController? _scannerController;
  bool _isScanCooldown = false;
  bool _isLoading = false;
  String? _lastScannedCode;
  String? _successMessage;
  String? _errorMessage;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _manualInputController = TextEditingController();

  // Set to false to hide debug button in production
  bool _debugMode = true;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _audioPlayer.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  Future<void> _playBeep() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
    } catch (_) {}
  }

  Future<void> _vibrate() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 100);
      }
    } catch (_) {}
  }

  void _showManualInputDialog() {
    _manualInputController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual QR Input'),
        content: TextField(
          controller: _manualInputController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. SPB-P-0725-000003',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            Navigator.of(ctx).pop();
            _triggerManualCheck(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _triggerManualCheck(_manualInputController.text);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerManualCheck(String qrCode) async {
    qrCode = qrCode.trim();
    if (qrCode.isEmpty || _isLoading) return;

    setState(() {
      _isScanCooldown = true;
      _isLoading = true;
      _lastScannedCode = qrCode;
      _successMessage = null;
      _errorMessage = null;
    });

    try {
      await _checkInvoice(qrCode);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isScanCooldown = false;
        });
      }
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isScanCooldown || _isLoading) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final qrCode = barcode.rawValue!;
    if (qrCode.isEmpty) return;

    setState(() {
      _isScanCooldown = true;
      _isLoading = true;
      _lastScannedCode = qrCode;
      _successMessage = null;
      _errorMessage = null;
    });

    await _playBeep();
    await _vibrate();

    try {
      await _checkInvoice(qrCode);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      // Release cooldown after a short delay to allow re-scanning
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _isScanCooldown = false;
        });
      }
    }
  }

  Future<void> _checkInvoice(String qrCode) async {
    final String baseUrl = SettingsService.instance.baseUrl;
    final String iduser = AuthService.instance.iduser;

    final uri = Uri.parse('$baseUrl/api/sell/checking-invoice');
    final body = jsonEncode({'qr_code': qrCode, 'iduser': iduser});

    try {
      final response = await http
          .post(uri, headers: AuthService.instance.authHeaders, body: body)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        Map<String, dynamic>? data;
        try {
          data = jsonDecode(response.body) as Map<String, dynamic>?;
        } catch (_) {}

        final message =
            data?['message']?.toString() ??
            data?['msg']?.toString() ??
            'Invoice checked successfully.';

        setState(() {
          _successMessage = message;
          _errorMessage = null;
        });
      } else {
        Map<String, dynamic>? data;
        try {
          data = jsonDecode(response.body) as Map<String, dynamic>?;
        } catch (_) {}

        final message =
            data?['message']?.toString() ??
            data?['error']?.toString() ??
            'Request failed (${response.statusCode}).';

        setState(() {
          _errorMessage = message;
          _successMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Network error: $e';
        _successMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checker'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_debugMode)
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: 'Debug: Manual Input',
              onPressed: _showManualInputDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          // QR Scanner
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                ),
                // Overlay frame
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // Result panel
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_lastScannedCode != null) ...[
                    Text(
                      'Scanned:',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _lastScannedCode!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_successMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_successMessage == null &&
                      _errorMessage == null &&
                      _lastScannedCode == null)
                    Column(
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Point the camera at a QR code\nto check an invoice.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
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
