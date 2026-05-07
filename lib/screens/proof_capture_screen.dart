import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../controllers/database_helper.dart';

/// Screen to capture proof image after dropping items at a drop point
class ProofCaptureScreen extends StatefulWidget {
  final String dropPointCode;
  final List<String> invoiceNumbers;

  const ProofCaptureScreen({
    super.key,
    required this.dropPointCode,
    required this.invoiceNumbers,
  });

  @override
  State<ProofCaptureScreen> createState() => _ProofCaptureScreenState();
}

class _ProofCaptureScreenState extends State<ProofCaptureScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  String? _capturedImagePath;
  bool _isSaving = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _getCurrentLocation();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _cameraController!.initialize();

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {}
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile image = await _cameraController!.takePicture();
      setState(() {
        _capturedImagePath = image.path;
        _isCapturing = false;
      });
    } catch (e) {
      setState(() {
        _isCapturing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _retakeImage() {
    // Delete the captured image file
    if (_capturedImagePath != null) {
      final file = File(_capturedImagePath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }

    setState(() {
      _capturedImagePath = null;
    });
  }

  Future<void> _confirmAndSave() async {
    if (_capturedImagePath == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Get app documents directory for permanent storage
      final appDir = await getApplicationDocumentsDirectory();
      final proofDir = Directory(path.join(appDir.path, 'proof_images'));

      // Create directory if it doesn't exist
      if (!await proofDir.exists()) {
        await proofDir.create(recursive: true);
      }

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'proof_${widget.dropPointCode}_$timestamp.jpg';
      final newPath = path.join(proofDir.path, fileName);

      // Copy the image to permanent storage
      final originalFile = File(_capturedImagePath!);
      await originalFile.copy(newPath);

      // Delete the temporary file
      if (originalFile.existsSync()) {
        await originalFile.delete();
      }

      // Upload to Firebase Storage
      String? downloadUrl;
      try {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('proof_images')
            .child(fileName);
        await storageRef.putFile(File(newPath));
        downloadUrl = await storageRef.getDownloadURL();

        // Store the download URL in the Realtime Database for each invoice
        final db = FirebaseDatabase.instance.ref();
        for (final invoiceNo in widget.invoiceNumbers) {
          await db.child('deliveries').child(invoiceNo).update({
            'proofImageUrl': downloadUrl,
            'proofTimestamp': ServerValue.timestamp,
            if (_currentPosition != null) ...{
              'proofLatitude': _currentPosition!.latitude,
              'proofLongitude': _currentPosition!.longitude,
            },
          });
        }
      } catch (_) {
        // Firebase upload failure is non-fatal — local copy is still saved
      }

      // Save to local database for each invoice
      final dbHelper = DatabaseHelper();
      for (final invoiceNumber in widget.invoiceNumbers) {
        await dbHelper.insertTracking(
          inv: invoiceNumber,
          imagePath: newPath,
          dropPointCode: widget.dropPointCode,
          lat: _currentPosition?.latitude,
          lng: _currentPosition?.longitude,
        );
      }

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proof image saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Return to previous screen with success result
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save proof image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Capture Proof'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Drop Point: ${widget.dropPointCode}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Invoices: ${widget.invoiceNumbers.join(", ")}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please take a picture of the delivered items as proof.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          // Camera preview or captured image
          Expanded(
            child: _capturedImagePath != null
                ? _buildImagePreview()
                : _buildCameraPreview(),
          ),

          // Bottom controls
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black,
            child: _capturedImagePath != null
                ? _buildConfirmationButtons()
                : _buildCaptureButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Initializing camera...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    return CameraPreview(_cameraController!);
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        Center(
          child: Image.file(File(_capturedImagePath!), fit: BoxFit.contain),
        ),
        // Overlay with location info
        if (_currentPosition != null)
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCaptureButton() {
    return Center(
      child: GestureDetector(
        onTap: _isCapturing ? null : _captureImage,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isCapturing ? Colors.grey : Colors.white,
              ),
              child: _isCapturing
                  ? const Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.black,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmationButtons() {
    return Row(
      children: [
        // Retake button
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _retakeImage,
            icon: const Icon(Icons.refresh),
            label: const Text('Retake'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Confirm button
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _confirmAndSave,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(_isSaving ? 'Saving...' : 'Confirm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}
