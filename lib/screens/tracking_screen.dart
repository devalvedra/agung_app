import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' show cos, sqrt, asin, sin, atan2;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import '../constants/app_constants.dart';
import '../controllers/tracking_controller.dart';
import '../services/firebase_location_service.dart';
import '../services/settings_service.dart';
import 'delivery_scanner.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final TrackingController _trackingController = Get.put(TrackingController());
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isLoading = false;
  int _currentPointIndex = 0;

  // QR scanner state
  bool _showScanner = true;
  bool _isFetchingRoute = false;
  bool _isRouteLoading = false;
  String? _vehicleNo;
  bool _debugMode = true; // Set to false to disable debug button
  static const String _debugVehicleNo = 'K-001'; // Debug vehicle number
  MobileScannerController? _qrScannerController;
  bool _qrCanScan = true;
  BitmapDescriptor? _truckIcon;
  bool _followTruck = true;
  bool _isProgrammaticMove = false;
  Timer? _animationTimer;
  LatLng? _targetPosition;
  double _lerpProgress = 0.0;
  int _currentRouteCoordinateIndex = 0;
  PolylinePoints polylinePoints = PolylinePoints(
    apiKey: AppConstants.googleMapsApiKey,
  );
  List<LatLng> _routeCoordinates = [];
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  final FirebaseLocationService _firebaseLocationService =
      FirebaseLocationService();
  Timer? _firebaseSyncTimer;
  bool _nearingDestinationNotified = false;
  bool _isNearingDialogOpen = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadTruckIcon();
    _initQrScanner();
    // Restore if route was already selected
    if (_trackingController.selectedRoute.value != null) {
      _showScanner = false;
      _vehicleNo = _trackingController.selectedRouteCode.value;
      _checkGpsAndInitialize();
    }
  }

  void _initQrScanner() {
    _qrScannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showScanner) {
        _qrScannerController?.start();
      }
    });
  }

  Future<void> _checkGpsAndInitialize() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && mounted) {
      _showGpsDisabledAlert();
    } else {
      await _getCurrentLocation();
    }
  }

  void _showGpsDisabledAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_off, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('GPS Disabled'),
            ],
          ),
          content: const Text(
            'GPS is currently disabled on your device. Please enable GPS to track your delivery in real-time.\n\nYou can still use Simulation Mode to preview routes.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Enable simulation mode by default when GPS is off
                _trackingController.setSimulationMode(true);
                _getCurrentLocation();
              },
              child: const Text('Use Simulation Mode'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Try to open location settings
                await Geolocator.openLocationSettings();
                // Recheck after a delay
                Future.delayed(const Duration(seconds: 2), () {
                  _checkGpsAndInitialize();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Enable GPS'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _firebaseSyncTimer?.cancel();
    _mapController?.dispose();
    _qrScannerController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playApproachSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/success.mp3'));
    } catch (e) {
      // ignore sound errors
    }
  }

  void _showNearingNotification(String dropPointName) {
    if (!mounted) return;
    _isNearingDialogOpen = true;
    _playApproachSound();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.orange[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.orange[800]!, width: 2),
          ),
          title: Row(
            children: [
              Icon(
                Icons.notifications_active,
                color: Colors.orange[800],
                size: 32,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Approaching Destination',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.orange[900],
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        dropPointName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange[700],
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'You are approaching your destination. Please prepare to stop.',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Distance threshold: ${(AppConstants.proximityNotificationThresholdKm * 1000).toInt()}m',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                _isNearingDialogOpen = false;
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text(
                'Acknowledged',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        );
      },
    );
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * 0.017453292519943295;
    final lat2 = end.latitude * 0.017453292519943295;
    final dLon = (end.longitude - start.longitude) * 0.017453292519943295;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearing = atan2(y, x) * 57.29577951308232;
    return bearing;
  }

  LatLng _lerpLatLng(LatLng start, LatLng end, double t) {
    return LatLng(
      start.latitude + (end.latitude - start.latitude) * t,
      start.longitude + (end.longitude - start.longitude) * t,
    );
  }

  Future<void> _loadTruckIcon() async {
    try {
      _truckIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/images/truck_icon.png',
      );
    } catch (e) {
      _truckIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueBlue,
      );
    }
    // Rebuild markers now that the icon is ready
    if (mounted) setState(() => _buildMarkersAndPolylines());
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

      _currentPosition = await Geolocator.getCurrentPosition();
    } catch (_) {}
  }

  void _handleVehicleQrScan(BarcodeCapture capture) {
    if (!mounted || !_qrCanScan || _isFetchingRoute) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.displayValue ?? barcode.rawValue;
      if (code == null || code.isEmpty) continue;

      _qrCanScan = false;
      _qrScannerController?.stop();
      _fetchRouteForVehicle(code);
      break;
    }
  }

  Future<void> _fetchRouteForVehicle(String vehicleNo) async {
    setState(() {
      _isFetchingRoute = true;
    });

    try {
      final baseUrl = SettingsService.instance.baseUrl;
      final uri = Uri.parse(
        '$baseUrl/api/delivery/get-delivery-route/$vehicleNo',
      );
      print('Uri data: $uri');

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        // API should return a route object compatible with the existing structure
        // Expected: { "code": "...", "name": "...", "route_points": [...] }
        print('Route data: $data');
        final route = data['data'] ?? data;

        setState(() {
          _vehicleNo = vehicleNo;
          _showScanner = false;
          _isFetchingRoute = false;
          _isLoading = false;
        });

        // Initialize GPS now that we have a vehicle
        await _checkGpsAndInitialize();

        // Initialize Firebase service with vehicle/driver info now that we have vehicleNo
        _initializeFirebaseService();

        // Select the fetched route
        _onRouteSelected(route);
      } else {
        setState(() {
          _isFetchingRoute = false;
          _qrCanScan = true;
        });
        _qrScannerController?.start();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No route found for vehicle "$vehicleNo" (${response.statusCode})',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingRoute = false;
        _qrCanScan = true;
      });
      _qrScannerController?.start();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch route: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _rescanVehicle() {
    setState(() {
      _showScanner = true;
      _vehicleNo = null;
      _qrCanScan = true;
      _followTruck = true;
      _isProgrammaticMove = false;
      _trackingController.resetTracking();
      _markers.clear();
      _polylines.clear();
      _routeCoordinates.clear();
      _currentPointIndex = 0;
      _currentRouteCoordinateIndex = 0;
      _animationTimer?.cancel();
      _positionStreamSubscription?.cancel();
      _stopFirebaseSync();
    });
    _qrScannerController?.start();
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  void _onRouteSelected(Map<String, dynamic> route) {
    final routeCode = route['code']?.toString() ?? '';

    // Extract invoice numbers from route_point[].invoices[].no_invoice.
    final Set<String> invoices = {};
    final routePoints = route['route_points'];
    if (routePoints is List) {
      for (final point in routePoints) {
        if (point is Map) {
          final pointInvoices = point['invoices'];
          if (pointInvoices is List) {
            for (final inv in pointInvoices) {
              if (inv is Map) {
                final no = inv['no_invoice']?.toString();
                if (no != null && no.isNotEmpty) invoices.add(no);
              }
            }
          }
        }
      }
    }

    setState(() {
      _trackingController.setSelectedRoute(routeCode, route);
      _trackingController.setVehicleInvoices(invoices.toList());
      _currentPointIndex = 0;
      _trackingController.setCurrentSegmentIndex(0);
      _markers.clear();
      _polylines.clear();
      _routeCoordinates.clear();
      _isRouteLoading = false;
    });

    // Route loading is triggered by onMapCreated once the map is ready.
    // Starting it here causes simulation to fire before the native map exists,
    // which overwhelms the UI thread and causes the app to become unresponsive.
  }

  void _buildMarkersAndPolylines() {
    // Clear all markers and polylines first
    if (_markers.isNotEmpty) {
      _markers.clear();
    }
    if (_polylines.isNotEmpty) {
      _polylines.clear();
    }

    // Only build if we have a selected route
    if (_trackingController.selectedRoute.value == null) return;

    final routePoints = List<Map<String, dynamic>>.from(
      _trackingController.selectedRoute.value!['route_points'] ?? [],
    );

    // Filter points that have lat/lng
    final validPoints = routePoints.where((point) {
      return point['lat'] != null && point['lng'] != null;
    }).toList();

    if (validPoints.isEmpty) return;

    // Create markers for the current segment
    if (_trackingController.currentSegmentIndex.value <
        validPoints.length - 1) {
      // Start point of current segment
      final startPoint =
          validPoints[_trackingController.currentSegmentIndex.value];
      final startLat = double.tryParse(startPoint['lat'].toString());
      final startLng = double.tryParse(startPoint['lng'].toString());

      if (startLat != null && startLng != null) {
        _markers.add(
          Marker(
            markerId: MarkerId('segment_start'),
            position: LatLng(startLat, startLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: startPoint['drop_point_code'] ?? 'Start',
              snippet:
                  'Segment ${_trackingController.currentSegmentIndex.value + 1} Start - Sequence ${startPoint['sequence']}',
            ),
          ),
        );
      }

      // End point (destination) marker
      final endPoint =
          validPoints[_trackingController.currentSegmentIndex.value + 1];
      final endLat = double.tryParse(endPoint['lat'].toString());
      final endLng = double.tryParse(endPoint['lng'].toString());

      if (endLat != null && endLng != null) {
        _markers.add(
          Marker(
            markerId: MarkerId('segment_end'),
            position: LatLng(endLat, endLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: endPoint['drop_point_code'] ?? 'Destination',
              snippet:
                  'Segment ${_trackingController.currentSegmentIndex.value + 1} End - Sequence ${endPoint['sequence']}',
            ),
          ),
        );
      }

      // Draw segment polyline — always from truck's position to destination
      if (_trackingController.currentSegmentCoordinates.isNotEmpty) {
        if (_trackingController.truckPosition.value != null) {
          // Use the already-tracked coordinate index to avoid an O(n) search.
          final int truckIndex = _currentRouteCoordinateIndex;

          final List<LatLng> remainingRoute = [
            _trackingController.truckPosition.value!,
            ..._trackingController.currentSegmentCoordinates.sublist(
              truckIndex + 1,
            ),
          ];

          if (remainingRoute.length >= 2) {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('truck_to_destination'),
                points: remainingRoute,
                color: Colors.blue,
                width: 5,
              ),
            );
          }
        } else {
          // No truck position yet — show full segment so the route is visible
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('current_segment'),
              points: _trackingController.currentSegmentCoordinates.toList(),
              color: Colors.blue,
              width: 5,
            ),
          );
        }
      }
    }

    // Add truck marker if position is available
    if (_trackingController.truckPosition.value != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('truck'),
          position: _trackingController.truckPosition.value!,
          icon:
              _truckIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          anchor: const Offset(0.5, 0.5),
          rotation: _trackingController.truckRotation.value,
          infoWindow: InfoWindow(
            title: 'Delivery Truck',
            snippet: _trackingController.isSimulationMode.value
                ? 'Simulating'
                : (_trackingController.isAnimating.value
                      ? 'Tracking'
                      : 'Ready'),
          ),
        ),
      );
    }
  }

  Future<void> _loadRoute() async {
    if (_isRouteLoading) return;
    if (_trackingController.selectedRoute.value == null) return;
    _isRouteLoading = true;

    final routePoints = List<Map<String, dynamic>>.from(
      _trackingController.selectedRoute.value!['route_points'] ?? [],
    );

    final allValidPoints = routePoints.where((point) {
      return point['lat'] != null && point['lng'] != null;
    }).toList();

    if (allValidPoints.isEmpty) return;

    // Only fetch route for the current segment
    if (_trackingController.currentSegmentIndex.value >=
        allValidPoints.length - 1)
      return;

    final currentSegmentPoints = [
      allValidPoints[_trackingController.currentSegmentIndex.value],
      allValidPoints[_trackingController.currentSegmentIndex.value + 1],
    ];

    log('Current segment points: $currentSegmentPoints');

    // Fetch real route using Directions API (only for current segment)
    await _fetchRealRoute(currentSegmentPoints);
    _isRouteLoading = false;

    // Only proceed (and notify backend) if the route was actually fetched
    if (_routeCoordinates.isEmpty) return;

    // Notify backend that all invoices in this vehicle are now in transit
    if (_vehicleNo != null) {
      _updateStatusByVehicle(_vehicleNo!);
    }

    // Focus camera on the current segment
    _updateCameraForCurrentSegment(allValidPoints);

    // Auto-start tracking once the route is ready
    if (mounted && !_trackingController.isAnimating.value) {
      if (_trackingController.isSimulationMode.value) {
        _startSimulation();
      } else {
        _startGpsTracking();
      }
    }
  }

  Future<void> _fetchRealRoute(List<Map<String, dynamic>> points) async {
    _routeCoordinates.clear();

    if (points.isEmpty || points.length < 2) return;

    // Get route between each consecutive waypoint
    for (int i = 0; i < points.length - 1; i++) {
      final startLat = double.parse(points[i]['lat'].toString());
      final startLng = double.parse(points[i]['lng'].toString());
      final endLat = double.parse(points[i + 1]['lat'].toString());
      final endLng = double.parse(points[i + 1]['lng'].toString());

      // Retry logic
      const maxRetries = 3;
      bool routeFetched = false;

      for (int retry = 0; retry < maxRetries && !routeFetched; retry++) {
        try {
          PolylineResult result = await polylinePoints
              .getRouteBetweenCoordinates(
                request: PolylineRequest(
                  origin: PointLatLng(startLat, startLng),
                  destination: PointLatLng(endLat, endLng),
                  mode: TravelMode.driving,
                ),
              );

          print(
            'polyline result: ${result.status}, error: ${result.errorMessage}',
          );

          if (result.points.isNotEmpty) {
            // Only add the first point if this is the first segment or if it's different from the last point
            if (_routeCoordinates.isEmpty) {
              _routeCoordinates.add(
                LatLng(
                  result.points.first.latitude,
                  result.points.first.longitude,
                ),
              );
            }

            // Add remaining points from this segment (skip first to avoid duplicates)
            for (int j = 1; j < result.points.length; j++) {
              final point = result.points[j];
              final newPoint = LatLng(point.latitude, point.longitude);

              // Avoid adding duplicate consecutive points
              if (_routeCoordinates.isEmpty ||
                  _routeCoordinates.last.latitude != newPoint.latitude ||
                  _routeCoordinates.last.longitude != newPoint.longitude) {
                _routeCoordinates.add(newPoint);
              }
            }
            routeFetched = true;
          } else {
            // Empty result, retry
            if (retry < maxRetries - 1) {
              await Future.delayed(Duration(seconds: retry + 1));
            }
          }
        } catch (e) {
          // On error, retry
          print('error $e');
          if (retry < maxRetries - 1) {
            await Future.delayed(Duration(seconds: retry + 1));
          }
        }
      }

      // If all retries failed, show alert
      if (!routeFetched && mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 28),
                  SizedBox(width: 8),
                  Text('Route Fetch Failed'),
                ],
              ),
              content: const Text(
                'Failed to fetch route from Google Maps after multiple attempts. Please check your internet connection and try again.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return; // Stop processing further segments
      }
    }

    // Extract current segment coordinates
    _extractCurrentSegmentCoordinates(points);
  }

  void _extractCurrentSegmentCoordinates(List<Map<String, dynamic>> points) {
    List<LatLng> tempCoordinates = [];

    if (_routeCoordinates.isEmpty) {
      return;
    }

    // Since we only fetch the current segment in _fetchRealRoute,
    // _routeCoordinates already contains only the current segment
    // So just copy all coordinates to _currentSegmentCoordinates
    tempCoordinates.addAll(_routeCoordinates);
    _trackingController.setCurrentSegmentCoordinates(tempCoordinates);
  }

  void _updateCameraForCurrentSegment(List<Map<String, dynamic>> validPoints) {
    if (_trackingController.currentSegmentCoordinates.isEmpty ||
        validPoints.length < 2 ||
        _trackingController.currentSegmentIndex.value >=
            validPoints.length - 1) {
      return;
    }

    setState(() {
      _buildMarkersAndPolylines();
    });

    // Get start and end points for camera bounds
    final startLat = double.parse(
      validPoints[_trackingController.currentSegmentIndex.value]['lat']
          .toString(),
    );
    final startLng = double.parse(
      validPoints[_trackingController.currentSegmentIndex.value]['lng']
          .toString(),
    );
    final endLat = double.parse(
      validPoints[_trackingController.currentSegmentIndex.value + 1]['lat']
          .toString(),
    );
    final endLng = double.parse(
      validPoints[_trackingController.currentSegmentIndex.value + 1]['lng']
          .toString(),
    );

    // Focus camera on current segment
    final bounds = LatLngBounds(
      southwest: LatLng(
        startLat < endLat ? startLat : endLat,
        startLng < endLng ? startLng : endLng,
      ),
      northeast: LatLng(
        startLat > endLat ? startLat : endLat,
        startLng > endLng ? startLng : endLng,
      ),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  void _startTruckAnimation() {
    if (_trackingController.currentSegmentCoordinates.isEmpty) return;

    _animationTimer?.cancel();
    _currentRouteCoordinateIndex = 0;
    _lerpProgress = 0.0;

    setState(() {
      _trackingController.setTruckPosition(
        _trackingController.currentSegmentCoordinates.first,
      );
      _targetPosition = _trackingController.currentSegmentCoordinates.length > 1
          ? _trackingController.currentSegmentCoordinates[1]
          : _trackingController.currentSegmentCoordinates.first;
      if (_trackingController.currentSegmentCoordinates.length > 1) {
        _trackingController.setTruckRotation(
          _calculateBearing(
            _trackingController.truckPosition.value!,
            _targetPosition!,
          ),
        );
      }
      _trackingController.setAnimatingState(true);
      _nearingDestinationNotified = false;
      _buildMarkersAndPolylines();
    });

    const lerpSteps = 20;
    // Clamp to ≥16 ms so we never fire setState faster than 60 fps,
    // which would overwhelm the UI thread during map rendering.
    final int frameIntervalMs =
        (AppConstants.truckAnimationIntervalMs /
                (lerpSteps * AppConstants.animationSpeedMultiplier))
            .round()
            .clamp(16, 500);
    _animationTimer = Timer.periodic(Duration(milliseconds: frameIntervalMs), (
      timer,
    ) {
      if (!_trackingController.isAnimating.value) {
        timer.cancel();
        return;
      }

      if (_currentRouteCoordinateIndex <
          _trackingController.currentSegmentCoordinates.length - 1) {
        setState(() {
          _lerpProgress += 1.0 / lerpSteps;

          if (_lerpProgress >= 1.0) {
            _currentRouteCoordinateIndex++;
            _lerpProgress = 0.0;

            if (_currentRouteCoordinateIndex <
                _trackingController.currentSegmentCoordinates.length - 1) {
              _trackingController.setTruckPosition(
                _trackingController
                    .currentSegmentCoordinates[_currentRouteCoordinateIndex],
              );
              _targetPosition = _trackingController
                  .currentSegmentCoordinates[_currentRouteCoordinateIndex + 1];
              _trackingController.setTruckRotation(
                _calculateBearing(
                  _trackingController.truckPosition.value!,
                  _targetPosition!,
                ),
              );
            } else {
              _trackingController.setTruckPosition(
                _trackingController.currentSegmentCoordinates.last,
              );
              _trackingController.setAnimatingState(false);
              timer.cancel();
              // Show alert after the frame is rendered
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showArrivalAlert();
              });
            }
          } else {
            final start = _trackingController
                .currentSegmentCoordinates[_currentRouteCoordinateIndex];
            final end = _trackingController
                .currentSegmentCoordinates[_currentRouteCoordinateIndex + 1];
            _trackingController.setTruckPosition(
              _lerpLatLng(start, end, _lerpProgress),
            );
          }

          // Proximity notification
          if (!_nearingDestinationNotified &&
              _trackingController.truckPosition.value != null) {
            final dest = _trackingController.currentSegmentCoordinates.last;
            final dist = _calculateDistance(
              _trackingController.truckPosition.value!.latitude,
              _trackingController.truckPosition.value!.longitude,
              dest.latitude,
              dest.longitude,
            );
            if (dist < AppConstants.proximityNotificationThresholdKm) {
              _nearingDestinationNotified = true;
              final routePoints = List<Map<String, dynamic>>.from(
                _trackingController.selectedRoute.value!['route_points'] ?? [],
              );
              final validPoints = routePoints
                  .where((p) => p['lat'] != null && p['lng'] != null)
                  .toList();
              final nextPoint =
                  validPoints[_trackingController.currentSegmentIndex.value +
                      1];
              final dpName =
                  nextPoint['drop_point_name']?.toString() ??
                  nextPoint['drop_point_code']?.toString() ??
                  'destination';
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showNearingNotification(dpName);
              });
            }
          }

          _buildMarkersAndPolylines();
          _updateCameraFollowTruck();
        });
      } else {
        setState(() {
          _trackingController.setAnimatingState(false);
        });
        timer.cancel();
      }
    });
  }

  void _toggleTracking() {
    if (_trackingController.isAnimating.value) {
      _stopTracking();
    } else {
      if (_trackingController.isSimulationMode.value) {
        _startSimulation();
      } else {
        _startGpsTracking();
      }
    }
  }

  void _stopTracking() {
    setState(() {
      _trackingController.setAnimatingState(false);
      _animationTimer?.cancel();
      _positionStreamSubscription?.cancel();
    });

    // Stop Firebase sync
    _stopFirebaseSync();
    _updateFirebaseTruckStatus('stopped');
  }

  void _startGpsTracking() {
    if (_trackingController.currentSegmentCoordinates.isEmpty) return;

    setState(() {
      _nearingDestinationNotified = false;
      _trackingController.setAnimatingState(true);
      // Place the truck icon immediately so it's visible before the first GPS event
      final initialPosition = _currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : _trackingController.currentSegmentCoordinates.first;
      _trackingController.setTruckPosition(initialPosition);
      if (_trackingController.currentSegmentCoordinates.length > 1) {
        _trackingController.setTruckRotation(
          _calculateBearing(
            initialPosition,
            _trackingController.currentSegmentCoordinates[1],
          ),
        );
      }
      _buildMarkersAndPolylines();
    });

    // Start Firebase sync
    _startFirebaseSync();
    _updateFirebaseTruckStatus('tracking');

    // Start listening to GPS position updates
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // Update every 5 meters
          ),
        ).listen((Position position) {
          if (!_trackingController.isAnimating.value ||
              _trackingController.isSimulationMode.value)
            return;

          setState(() {
            _trackingController.setTruckPosition(
              LatLng(position.latitude, position.longitude),
            );

            // Calculate bearing to next point
            if (_currentRouteCoordinateIndex <
                _trackingController.currentSegmentCoordinates.length - 1) {
              _trackingController.setTruckRotation(
                _calculateBearing(
                  _trackingController.truckPosition.value!,
                  _trackingController
                      .currentSegmentCoordinates[_currentRouteCoordinateIndex +
                      1],
                ),
              );
            }

            // Check if reached destination
            final destination =
                _trackingController.currentSegmentCoordinates.last;
            final distanceToDestination = _calculateDistance(
              position.latitude,
              position.longitude,
              destination.latitude,
              destination.longitude,
            );

            // If within 20 meters of destination, consider arrived
            if (distanceToDestination < 0.01) {
              _trackingController.setAnimatingState(false);
              _positionStreamSubscription?.cancel();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showArrivalAlert();
              });
            } else if (!_nearingDestinationNotified &&
                distanceToDestination <
                    AppConstants.proximityNotificationThresholdKm) {
              // Within threshold distance — notify driver
              _nearingDestinationNotified = true;
              final routePoints = List<Map<String, dynamic>>.from(
                _trackingController.selectedRoute.value!['route_points'] ?? [],
              );
              final validPoints = routePoints
                  .where((p) => p['lat'] != null && p['lng'] != null)
                  .toList();
              final nextPoint =
                  validPoints[_trackingController.currentSegmentIndex.value +
                      1];
              final dpName =
                  nextPoint['drop_point_name']?.toString() ??
                  nextPoint['drop_point_code']?.toString() ??
                  'destination';
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showNearingNotification(dpName);
              });
            }

            _buildMarkersAndPolylines();
            _updateCameraFollowTruck();
          });
        });
  }

  void _startSimulation() {
    // Start Firebase sync for simulation mode
    _startFirebaseSync();
    _updateFirebaseTruckStatus('simulating');

    _startTruckAnimation();
  }

  void _toggleSimulationMode() {
    setState(() {
      _trackingController.setSimulationMode(
        !_trackingController.isSimulationMode.value,
      );
      if (_trackingController.isAnimating.value) {
        _stopTracking();
      }
    });
  }

  void _updateCameraFollowTruck() {
    if (_trackingController.truckPosition.value == null ||
        !_trackingController.isAnimating.value ||
        _mapController == null ||
        !_followTruck)
      return;

    // Move camera to truck position without changing zoom or bearing
    _isProgrammaticMove = true;
    _mapController!.animateCamera(
      CameraUpdate.newLatLng(_trackingController.truckPosition.value!),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      _isProgrammaticMove = false;
    });
  }

  void _onUserCameraMove() {
    if (!_isProgrammaticMove && _followTruck) {
      setState(() => _followTruck = false);
    }
  }

  void _refocusOnTruck() {
    setState(() => _followTruck = true);
    _updateCameraFollowTruck();
  }

  /// Initialize Firebase location service with the current vehicle number and driver ID.
  void _initializeFirebaseService() {
    final vehicleNo = _vehicleNo ?? 'unknown';
    final driverId = SettingsService.instance.iduser;
    _firebaseLocationService.initialize(vehicleNo, driverId: driverId);
    // Register with GetX so other screens (e.g. DeliveryScanner) can access it.
    if (!Get.isRegistered<FirebaseLocationService>()) {
      Get.put(_firebaseLocationService);
    }
  }

  /// Start syncing location to Firebase periodically
  void _startFirebaseSync() {
    // Cancel existing timer if any
    _firebaseSyncTimer?.cancel();

    // Initialize Firebase service
    _initializeFirebaseService();

    // Sync location every 5 seconds
    _firebaseSyncTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _syncLocationToFirebase();
    });

    // Also sync immediately
    _syncLocationToFirebase();
  }

  /// Stop syncing location to Firebase
  void _stopFirebaseSync() {
    _firebaseSyncTimer?.cancel();
  }

  /// Sync current location to Firebase
  Future<void> _syncLocationToFirebase() async {
    if (_trackingController.truckPosition.value == null ||
        _trackingController.selectedRoute.value == null) {
      return;
    }

    try {
      final position = _trackingController.truckPosition.value!;

      await _firebaseLocationService.saveLocation(
        position: position,
        routeCode: _trackingController.selectedRouteCode.value,
        segmentIndex: _trackingController.currentSegmentIndex.value,
        bearing: _trackingController.truckRotation.value,
        isSimulation: _trackingController.isSimulationMode.value,
      );

      // Update location for all known invoices (not yet delivered)
      final invoiceNumbers = _trackingController.vehicleInvoices.toList();

      if (invoiceNumbers.isNotEmpty) {
        await _firebaseLocationService.updateDeliveryLocations(
          position: position,
          invoiceNumbers: invoiceNumbers,
        );
      }
    } catch (_) {}
  }

  /// Save route info to Firebase when route is selected
  Future<void> _saveRouteToFirebase() async {
    if (_trackingController.selectedRoute.value == null) return;

    try {
      final route = _trackingController.selectedRoute.value!;
      final routePoints = List<Map<String, dynamic>>.from(
        route['route_points'] ?? [],
      );

      await _firebaseLocationService.saveRouteInfo(
        routeCode: route['code'] ?? '',
        routeName: route['name'] ?? '',
        routePoints: routePoints,
      );
    } catch (_) {}
  }

  /// Update delivery status via API when vehicle QR is scanned
  Future<void> _updateStatusByVehicle(String vehicleNo) async {
    try {
      final baseUrl = SettingsService.instance.baseUrl;
      final uri = Uri.parse('$baseUrl/api/delivery/update-status-by-vehicle');

      final body = <String, dynamic>{
        'status': 'SEDANG_DIKIRIM',
        'username': SettingsService.instance.iduser,
        'vehicle_no': vehicleNo,
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Update truck status in Firebase
  Future<void> _updateFirebaseTruckStatus(String status) async {
    try {
      await _firebaseLocationService.updateTruckStatus(
        status: status,
        additionalData: {
          'routeCode': _trackingController.selectedRouteCode.value,
          'segmentIndex': _trackingController.currentSegmentIndex.value,
        },
      );
    } catch (_) {}
  }

  void _showArrivalAlert() {
    if (_trackingController.selectedRoute.value == null) return;

    // Dismiss the nearing notification dialog if it is still open
    if (_isNearingDialogOpen && mounted) {
      _isNearingDialogOpen = false;
      Navigator.of(context).pop();
    }

    final routePoints = List<Map<String, dynamic>>.from(
      _trackingController.selectedRoute.value!['route_points'] ?? [],
    );
    final validPoints = routePoints.where((point) {
      return point['lat'] != null && point['lng'] != null;
    }).toList();

    // Show arrival alert for current segment
    final currentPoint =
        validPoints[_trackingController.currentSegmentIndex.value + 1];
    final dropPointCode =
        currentPoint['drop_point_code']?.toString() ?? 'Destination';
    final dropPointName =
        currentPoint['drop_point_name']?.toString() ?? dropPointCode;

    // Check if destination is Head Office
    final isHeadOffice =
        dropPointCode == 'HO' || dropPointName == 'Head Office';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue, size: 28),
              const SizedBox(width: 8),
              const Text('Arrived!'),
            ],
          ),
          content: Text(
            isHeadOffice
                ? 'You have arrived at $dropPointName.'
                : 'You have arrived at $dropPointName.\n\nPlease scan the drop point code and items to complete this delivery.',
          ),
          actions: [
            if (!isHeadOffice)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _stopFirebaseSync();
                  _proceedToNextSegment(validPoints);
                },
                child: const Text('Skip'),
              ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();

                if (isHeadOffice) {
                  // Skip scanning for Head Office, proceed directly to next segment
                  _stopFirebaseSync();
                  _proceedToNextSegment(validPoints);
                } else {
                  // Navigate to DeliveryScanner for other drop points
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => DeliveryScanner(
                        fromTracking: true,
                        dropPointCode: dropPointCode,
                        currentPoint: currentPoint,
                      ),
                    ),
                  );

                  // After returning from scanning, proceed to next segment
                  // Invoice status (Sampai Tujuan) is updated by DeliveryScanner
                  if (result == true) {
                    _stopFirebaseSync();
                    _proceedToNextSegment(validPoints);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text(isHeadOffice ? 'Continue' : 'Drop Items'),
            ),
          ],
        );
      },
    );
  }

  void _proceedToNextSegment(List<Map<String, dynamic>> validPoints) {
    // Move to next segment
    _trackingController.incrementSegment();
    _currentPointIndex = _trackingController.currentSegmentIndex.value;

    if (_trackingController.currentSegmentIndex.value >=
        validPoints.length - 1) {
      // All segments finished - show finish alert and clear route
      _showFinishAlert();
      return;
    }

    setState(() {
      _trackingController.setAnimatingState(false);
      _animationTimer?.cancel();
      _trackingController.setTruckPosition(null);
    });

    // Fetch and prepare the next segment
    final nextSegmentPoints = [
      validPoints[_trackingController.currentSegmentIndex.value],
      validPoints[_trackingController.currentSegmentIndex.value + 1],
    ];

    _fetchRealRoute(nextSegmentPoints).then((_) {
      _updateCameraForCurrentSegment(validPoints);
    });
  }

  void _showFinishAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Route Completed!'),
            ],
          ),
          content: Text(
            'Congratulations! You have completed all deliveries for route ${_trackingController.selectedRouteCode.value}.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // End route in Firebase
                _firebaseLocationService.endRoute();
                _stopFirebaseSync();
                // Clear the selected route and reset state
                setState(() {
                  _trackingController.resetTracking();
                  _markers.clear();
                  _polylines.clear();
                  _routeCoordinates.clear();
                  _currentPointIndex = 0;
                  _currentRouteCoordinateIndex = 0;
                  _animationTimer?.cancel();
                  _positionStreamSubscription?.cancel();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Finish'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQrScannerView() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Vehicle QR Code'),
        backgroundColor: Colors.green,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _qrScannerController!,
            onDetect: _handleVehicleQrScan,
          ),
          // Overlay instructions
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Point camera at vehicle QR code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The vehicle number will be used to load\nyour delivery route automatically.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_debugMode) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _isFetchingRoute
                          ? null
                          : () {
                              _qrCanScan = false;
                              _qrScannerController?.stop();
                              _fetchRouteForVehicle(_debugVehicleNo);
                            },
                      icon: const Icon(Icons.bug_report, color: Colors.yellow),
                      label: Text(
                        'Debug: Use "$_debugVehicleNo"',
                        style: const TextStyle(color: Colors.yellow),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.yellow),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Loading overlay when fetching route
          if (_isFetchingRoute)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(color: Colors.green),
                      SizedBox(height: 16),
                      Text(
                        'Loading delivery route...',
                        style: TextStyle(fontSize: 16),
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

  Widget _buildTrackingView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Package Tracking'),
        backgroundColor: Colors.green,
        actions: [
          Obx(
            () =>
                _trackingController.selectedRoute.value != null &&
                    _trackingController.currentSegmentCoordinates.isNotEmpty
                ? Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _trackingController.isSimulationMode.value
                              ? Icons.directions_car
                              : Icons.gps_fixed,
                        ),
                        onPressed: _toggleSimulationMode,
                        tooltip: _trackingController.isSimulationMode.value
                            ? 'GPS Mode'
                            : 'Simulation Mode',
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Vehicle info banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: Colors.grey.shade100,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vehicle: ${_vehicleNo ?? '-'}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Obx(
                              () =>
                                  _trackingController.selectedRoute.value !=
                                      null
                                  ? Text(
                                      'Route: ${_trackingController.selectedRoute.value!['name'] ?? _trackingController.selectedRouteCode.value}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      Obx(
                        () => _trackingController.selectedRoute.value != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      _trackingController.isSimulationMode.value
                                      ? Colors.orange
                                      : Colors.blue,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _trackingController.isSimulationMode.value
                                          ? Icons.directions_car
                                          : Icons.gps_fixed,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _trackingController.isSimulationMode.value
                                          ? 'Simulation'
                                          : 'GPS',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _rescanVehicle,
                        icon: const Icon(Icons.qr_code_scanner, size: 16),
                        label: const Text('Rescan'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Segment info
                Obx(
                  () => _trackingController.selectedRoute.value != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          color: Colors.grey.shade50,
                          child: Row(
                            children: [
                              Text(
                                'Segment: ${_trackingController.currentSegmentIndex.value + 1} / ${(_trackingController.selectedRoute.value!['route_points'] as List).where((p) => p['lat'] != null).length - 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // Map
                Expanded(
                  child: Obx(
                    () => _trackingController.selectedRoute.value == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.map_outlined,
                                  size: 80,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading route...',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Stack(
                            children: [
                              GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: const LatLng(0.0263, 109.3425),
                                  zoom: AppConstants.routeZoomLevel,
                                ),
                                markers: _markers,
                                polylines: _polylines,
                                onMapCreated: (controller) {
                                  _mapController = controller;
                                  if (_trackingController.selectedRoute.value !=
                                      null) {
                                    _loadRoute();
                                  }
                                },
                                onCameraMoveStarted: _onUserCameraMove,
                                myLocationButtonEnabled: false,
                                myLocationEnabled: false,
                                mapType: MapType.normal,
                                zoomControlsEnabled: false,
                              ),
                              if (!_followTruck)
                                Positioned(
                                  bottom: 16,
                                  right: 16,
                                  child: FloatingActionButton.small(
                                    onPressed: _refocusOnTruck,
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.blue,
                                    tooltip: 'Re-focus on truck',
                                    child: const Icon(Icons.my_location),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                // Current Segment Tracking
                Obx(
                  () => _trackingController.selectedRoute.value != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                blurRadius: 5,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Segment ${_trackingController.currentSegmentIndex.value + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _getCurrentSegmentLabel(),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.trip_origin,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _getCurrentSegmentLocation(true),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.red,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _getCurrentSegmentLocation(false),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showScanner) {
      return _buildQrScannerView();
    }
    return _buildTrackingView();
  }

  String _getCurrentSegmentLabel() {
    if (_trackingController.selectedRoute.value == null) return '';

    final routePoints = List<Map<String, dynamic>>.from(
      _trackingController.selectedRoute.value!['route_points'] ?? [],
    );

    final validPoints = routePoints.where((point) {
      return point['lat'] != null && point['lng'] != null;
    }).toList();

    if (validPoints.isEmpty ||
        _trackingController.currentSegmentIndex.value >= validPoints.length - 1)
      return '';

    final fromPoint =
        validPoints[_trackingController
                .currentSegmentIndex
                .value]['drop_point_code']
            ?.toString() ??
        'Unknown';
    final toPoint =
        validPoints[_trackingController.currentSegmentIndex.value +
                1]['drop_point_code']
            ?.toString() ??
        'Unknown';

    return '$fromPoint → $toPoint';
  }

  String _getCurrentSegmentLocation(bool isFrom) {
    if (_trackingController.selectedRoute.value == null) return '';

    final routePoints = List<Map<String, dynamic>>.from(
      _trackingController.selectedRoute.value!['route_points'] ?? [],
    );

    final validPoints = routePoints.where((point) {
      return point['lat'] != null && point['lng'] != null;
    }).toList();

    if (validPoints.isEmpty ||
        _trackingController.currentSegmentIndex.value >= validPoints.length - 1)
      return '';

    final point = isFrom
        ? validPoints[_trackingController.currentSegmentIndex.value]
        : validPoints[_trackingController.currentSegmentIndex.value + 1];

    final dropPointCode = point['drop_point_code']?.toString() ?? 'Unknown';
    final lat =
        double.tryParse(point['lat'].toString())?.toStringAsFixed(4) ?? '';
    final lng =
        double.tryParse(point['lng'].toString())?.toStringAsFixed(4) ?? '';

    return '$dropPointCode ($lat, $lng)';
  }
}
