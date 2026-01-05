import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Implementation of Mobile Scanner example with multiple code scanning
class MultipleCodeScanner extends StatefulWidget {
  /// Constructor for multiple code scanner example
  const MultipleCodeScanner({super.key});

  @override
  State<MultipleCodeScanner> createState() => _MultipleCodeScannerState();
}

class _MultipleCodeScannerState extends State<MultipleCodeScanner> {
  // Static list of codes that need to be scanned
  final List<String> _requiredCodes = [
    'K-101-1',
    'K-101-2',
    'B-101-1',
    'B-101-2',
  ];

  // Track which codes have been scanned
  final Set<String> _scannedCodesSet = {};

  void _handleBarcode(BarcodeCapture barcodes) {
    if (!mounted) return;

    for (final barcode in barcodes.barcodes) {
      final code = barcode.displayValue ?? barcode.rawValue;

      if (code != null &&
          code.isNotEmpty &&
          _requiredCodes.contains(code) &&
          !_scannedCodesSet.contains(code)) {
        setState(() {
          _scannedCodesSet.add(code);
        });
        // Show feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Scanned: $code'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _handleQRcode(BarcodeCapture barcodes) {
    if (!mounted) return;

    for (final barcode in barcodes.barcodes) {
      final code = barcode.displayValue ?? barcode.rawValue;
      if (code != null &&
          code.isNotEmpty &&
          _requiredCodes.contains(code) &&
          !_scannedCodesSet.contains(code)) {
        setState(() {
          _scannedCodesSet.add(code);
        });
        // Show feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Scanned: $code'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _clearScannedCodes() {
    setState(() {
      _scannedCodesSet.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('All checkmarks cleared')));
  }

  int get _scannedCount => _scannedCodesSet.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multiple Code Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scannedCodesSet.isEmpty ? null : _clearScannedCodes,
            tooltip: 'Reset all',
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(flex: 1, child: MobileScanner(onDetect: _handleBarcode)),
          Expanded(
            flex: 1,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Required Codes',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _scannedCount == _requiredCodes.length
                                ? Colors.green
                                : Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_scannedCount/${_requiredCodes.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _requiredCodes.length,
                      itemBuilder: (context, index) {
                        final code = _requiredCodes[index];
                        final isScanned = _scannedCodesSet.contains(code);
                        return ListTile(
                          leading: Checkbox(
                            value: isScanned,
                            onChanged: null,
                            activeColor: Colors.green,
                          ),
                          title: Text(
                            code,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              decoration: isScanned
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isScanned ? Colors.grey : Colors.black,
                            ),
                          ),
                          trailing: isScanned
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : const Icon(
                                  Icons.qr_code_scanner,
                                  color: Colors.grey,
                                ),
                          tileColor: isScanned
                              ? Colors.green.withOpacity(0.1)
                              : null,
                        );
                      },
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
