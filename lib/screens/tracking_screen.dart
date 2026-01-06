import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' show cos, sqrt, asin, sin, atan2;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../constants/app_constants.dart';
import '../controllers/tracking_controller.dart';
import 'delivery_scanner.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final TrackingController _trackingController = Get.put(TrackingController());
  GoogleMapController? _mapController;
  List<Map<String, dynamic>> _routes = [];
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isLoading = true;
  int _currentPointIndex = 0;
  BitmapDescriptor? _truckIcon;
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

  @override
  void initState() {
    super.initState();
    _loadTruckIcon();
    _checkGpsAndInitialize();
    _restoreStateFromController();
  }

  void _restoreStateFromController() {
    // Restore state from controller if available
    if (_trackingController.selectedRoute.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _onRouteSelected(_trackingController.selectedRouteCode.value);
        });
      });
    }
  }

  Future<void> _checkGpsAndInitialize() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && mounted) {
      // GPS is not enabled, show alert
      _showGpsDisabledAlert();
    } else {
      // GPS is enabled, proceed with initialization
      _getCurrentLocation();
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
    _mapController?.dispose();
    super.dispose();
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
      _truckIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(24, 24)),
        'assets/images/truck_icon.png',
      );
    } catch (e) {
      _truckIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueBlue,
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _loadRoutesWithoutLocation();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _loadRoutesWithoutLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _loadRoutesWithoutLocation();
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition();
      await _loadRoutes();
    } catch (e) {
      await _loadRoutesWithoutLocation();
    }
  }

  Future<void> _loadRoutesWithoutLocation() async {
    await _loadRoutes();
    if (_routes.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location not available. Please select a route manually.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'lib/constants/dummy_data.json',
      );
      final Map<String, dynamic> data = json.decode(jsonString);
      setState(() {
        _routes = List<Map<String, dynamic>>.from(data['route'] ?? []);
        _isLoading = false;
      });

      // Auto-select closest route if location is available
      if (_currentPosition != null && _routes.isNotEmpty) {
        _selectClosestRoute();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading routes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  void _selectClosestRoute() {
    if (_currentPosition == null || _routes.isEmpty) return;

    double minDistance = double.infinity;
    String? closestRouteCode;

    for (final route in _routes) {
      final routePoints = List<Map<String, dynamic>>.from(
        route['route_points'] ?? [],
      );

      if (routePoints.isEmpty) continue;

      final firstPoint = routePoints.firstWhere(
        (point) => point['lat'] != null && point['lng'] != null,
        orElse: () => {},
      );

      if (firstPoint.isEmpty) continue;

      final lat = double.tryParse(firstPoint['lat'].toString());
      final lng = double.tryParse(firstPoint['lng'].toString());

      if (lat == null || lng == null) continue;

      final distance = _calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestRouteCode = route['code'];
      }
    }

    if (closestRouteCode != null) {
      _onRouteSelected(closestRouteCode);
    }
  }

  void _onRouteSelected(String? routeCode) {
    if (routeCode == null) return;

    final route = _routes.firstWhere(
      (r) => r['code'] == routeCode,
      orElse: () => {},
    );

    if (route.isEmpty) return;

    setState(() {
      _trackingController.setSelectedRoute(routeCode, route);
      _currentPointIndex = 0;
      _trackingController.setCurrentSegmentIndex(0);
      // Clear everything before building new route
      _markers.clear();
      _polylines.clear();
      _routeCoordinates.clear();
    });

    // Fetch and display the new route
    _loadRoute();

    // Initialize truck at current GPS location
    if (_currentPosition != null) {
      _trackingController.setTruckPosition(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      );
      _buildMarkersAndPolylines();
    }
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

      // Draw segment polyline
      if (_trackingController.currentSegmentCoordinates.isNotEmpty) {
        if (_trackingController.isAnimating.value &&
            _trackingController.truckPosition.value != null) {
          // During animation, show polyline from truck to destination
          int truckIndex = 0;
          double minDistance = double.infinity;

          for (
            int i = 0;
            i < _trackingController.currentSegmentCoordinates.length;
            i++
          ) {
            final coord = _trackingController.currentSegmentCoordinates[i];
            final distance = _calculateDistance(
              _trackingController.truckPosition.value!.latitude,
              _trackingController.truckPosition.value!.longitude,
              coord.latitude,
              coord.longitude,
            );
            if (distance < minDistance) {
              minDistance = distance;
              truckIndex = i;
            }
          }

          List<LatLng> remainingRoute = [
            _trackingController.truckPosition.value!,
            ..._trackingController.currentSegmentCoordinates.sublist(
              truckIndex + 1,
            ),
          ];

          if (remainingRoute.length >= 2) {
            _polylines.add(
              Polyline(
                polylineId: PolylineId('truck_to_destination'),
                points: remainingRoute,
                color: Colors.blue,
                width: 5,
              ),
            );
          }
        } else {
          // When not animating, show full segment polyline
          _polylines.add(
            Polyline(
              polylineId: PolylineId('current_segment'),
              points: _trackingController.currentSegmentCoordinates.toList(),
              color: Colors.blue,
              width: 5,
            ),
          );
        }
      }
    }

    // Add truck marker if position is available
    if (_trackingController.truckPosition.value != null && _truckIcon != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('truck'),
          position: _trackingController.truckPosition.value!,
          icon: _truckIcon!,
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
    if (_trackingController.selectedRoute.value == null) return;

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

    // Focus camera on the current segment
    _updateCameraForCurrentSegment(allValidPoints);
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
      _buildMarkersAndPolylines();
    });

    const lerpSteps = 20;
    _animationTimer = Timer.periodic(
      Duration(
        milliseconds:
            (AppConstants.truckAnimationIntervalMs ~/
                    (lerpSteps * AppConstants.animationSpeedMultiplier))
                .toInt(),
      ),
      (timer) {
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

            _buildMarkersAndPolylines();
            _updateCameraFollowTruck();
          });
        } else {
          setState(() {
            _trackingController.setAnimatingState(false);
          });
          timer.cancel();
        }
      },
    );
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
  }

  void _startGpsTracking() {
    if (_trackingController.currentSegmentCoordinates.isEmpty) return;

    setState(() {
      _trackingController.setAnimatingState(true);
    });

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
            }

            _buildMarkersAndPolylines();
            _updateCameraFollowTruck();
          });
        });
  }

  void _startSimulation() {
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
        _mapController == null)
      return;

    // Center camera on truck position with appropriate zoom level
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _trackingController.truckPosition.value!,
          zoom: 17.0,
          bearing: _trackingController.truckRotation.value,
        ),
      ),
    );
  }

  void _showArrivalAlert() {
    if (_trackingController.selectedRoute.value == null) return;

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
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();

                if (isHeadOffice) {
                  // Skip scanning for Head Office, proceed directly to next segment
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
                  if (result == true) {
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

  @override
  Widget build(BuildContext context) {
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
                      IconButton(
                        icon: Icon(
                          _trackingController.isAnimating.value
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        onPressed: _toggleTracking,
                        tooltip: _trackingController.isAnimating.value
                            ? 'Stop Tracking'
                            : (_trackingController.isSimulationMode.value
                                  ? 'Start Simulation'
                                  : 'Start GPS Tracking'),
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
                // Route Selector
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey.shade100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Route:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value:
                            _trackingController.selectedRouteCode.value.isEmpty
                            ? null
                            : _trackingController.selectedRouteCode.value,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        hint: const Text('Choose a route'),
                        items: _routes.map((route) {
                          return DropdownMenuItem<String>(
                            value: route['code'],
                            child: Text(
                              '${route['code']} - ${route['name']}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: _onRouteSelected,
                      ),
                      Obx(
                        () => _trackingController.selectedRoute.value != null
                            ? Column(
                                children: [
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Segment: ${_trackingController.currentSegmentIndex.value + 1} / ${(_trackingController.selectedRoute.value!['route_points'] as List).where((p) => p['lat'] != null).length - 1}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              _trackingController
                                                  .isSimulationMode
                                                  .value
                                              ? Colors.orange
                                              : Colors.blue,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _trackingController
                                                      .isSimulationMode
                                                      .value
                                                  ? Icons.directions_car
                                                  : Icons.gps_fixed,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _trackingController
                                                      .isSimulationMode
                                                      .value
                                                  ? 'Simulation'
                                                  : 'GPS',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
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
                                  Icons.local_shipping,
                                  size: 80,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Select a route to track',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GoogleMap(
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
                            myLocationButtonEnabled: true,
                            myLocationEnabled: true,
                            mapType: MapType.normal,
                            zoomControlsEnabled: true,
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
                                  Icon(
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
                                  Icon(
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
                // Next Point Button
                // if (_selectedRoute != null)
                //   Container(
                //     width: double.infinity,
                //     padding: const EdgeInsets.all(16),
                //     child: ElevatedButton(
                //       onPressed: () {
                //         final routePoints = List<Map<String, dynamic>>.from(
                //           _selectedRoute!['route_points'] ?? [],
                //         );
                //         final validPoints = routePoints.where((point) {
                //           return point['lat'] != null && point['lng'] != null;
                //         }).toList();

                //         if (_currentSegmentIndex + 2 < validPoints.length) {
                //           _proceedToNextSegment(validPoints);
                //         } else {
                //           ScaffoldMessenger.of(context).showSnackBar(
                //             const SnackBar(
                //               content: Text('Route completed!'),
                //               backgroundColor: Colors.blue,
                //             ),
                //           );
                //         }
                //       },
                //       style: ElevatedButton.styleFrom(
                //         backgroundColor: Colors.green,
                //         foregroundColor: Colors.white,
                //         padding: const EdgeInsets.symmetric(vertical: 16),
                //       ),
                //       child: Text(
                //         _currentSegmentIndex + 2 <
                //                 ((_selectedRoute!['route_points'] as List)
                //                     .where((p) => p['lat'] != null)
                //                     .length)
                //             ? 'Next Point'
                //             : 'Complete Route',
                //         style: const TextStyle(fontSize: 16),
                //       ),
                //     ),
                //   ),
              ],
            ),
    );
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
