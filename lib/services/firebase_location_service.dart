import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Service to sync truck location and delivery data with Firebase Realtime Database.
///
/// Firebase structure:
/// ```
/// trucks/{vehicleNo}/currentLocation/   ← real-time position (always latest)
///
/// deliveries/{date}/{vehicleNo}/
///   driverId: "aling"
///   activeRoute/      ← route info for the day
///   status/           ← current tracking status
///   locationHistory/  ← push-keyed GPS updates for the day
///   completedDeliveries/ ← push-keyed records of each confirmed drop-point delivery
/// ```
class FirebaseLocationService extends GetxService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  String? _vehicleNo;
  String? _driverId;

  /// Returns today's date string in "yyyy-MM-dd" format.
  String get _todayDate {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Reference to the real-time current-location node (no date, always overwritten).
  DatabaseReference get _currentLocationRef =>
      _database.child('trucks').child(_vehicleNo!).child('currentLocation');

  /// Reference to today's delivery node for this vehicle.
  DatabaseReference get _todayRef =>
      _database.child('deliveries').child(_todayDate).child(_vehicleNo!);

  /// Initialize the service with the vehicle number and optional driver ID.
  void initialize(String vehicleNo, {String? driverId}) {
    _vehicleNo = vehicleNo;
    _driverId = driverId;
  }

  void _assertInitialized() {
    if (_vehicleNo == null) {
      throw Exception(
        'FirebaseLocationService not initialized. Call initialize() first.',
      );
    }
  }

  /// Save truck location to Firebase.
  /// - Updates real-time current location under trucks/{vehicleNo}/currentLocation.
  /// - Appends to today's location history under deliveries/{date}/{vehicleNo}/locationHistory.
  Future<void> saveLocation({
    required LatLng position,
    required String routeCode,
    int? segmentIndex,
    double? bearing,
    bool isSimulation = false,
  }) async {
    _assertInitialized();

    try {
      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'routeCode': routeCode,
        'segmentIndex': segmentIndex,
        'bearing': bearing,
        'isSimulation': isSimulation,
        'timestamp': ServerValue.timestamp,
      };

      // Real-time position for live tracking (always overwritten)
      await _currentLocationRef.set(locationData);

      // Daily history entry
      await _todayRef.child('locationHistory').push().set(locationData);
    } catch (e) {
      throw Exception('Failed to save location to Firebase: $e');
    }
  }

  /// Save route information for today under deliveries/{date}/{vehicleNo}/activeRoute.
  Future<void> saveRouteInfo({
    required String routeCode,
    required String routeName,
    required List<Map<String, dynamic>> routePoints,
  }) async {
    _assertInitialized();

    try {
      final routeData = {
        'routeCode': routeCode,
        'routeName': routeName,
        'routePoints': routePoints,
        'startTime': ServerValue.timestamp,
        'status': 'active',
        if (_driverId != null) 'driverId': _driverId,
      };

      await _todayRef.child('activeRoute').set(routeData);
    } catch (e) {
      throw Exception('Failed to save route info to Firebase: $e');
    }
  }

  /// Update tracking status under deliveries/{date}/{vehicleNo}/status.
  Future<void> updateTruckStatus({
    required String status,
    Map<String, dynamic>? additionalData,
  }) async {
    _assertInitialized();

    try {
      final statusData = {
        'status': status,
        'timestamp': ServerValue.timestamp,
        if (_driverId != null) 'driverId': _driverId,
        ...?additionalData,
      };

      await _todayRef.child('status').set(statusData);
    } catch (e) {
      throw Exception('Failed to update truck status: $e');
    }
  }

  /// Listen to real-time location updates for a specific vehicle.
  Stream<Map<String, dynamic>> listenToTruckLocation(String vehicleNo) {
    final controller = StreamController<Map<String, dynamic>>();

    _database
        .child('trucks')
        .child(vehicleNo)
        .child('currentLocation')
        .onValue
        .listen((event) {
          if (event.snapshot.value != null) {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            controller.add(data);
          }
        });

    return controller.stream;
  }

  /// Get current real-time location for a specific vehicle.
  Future<Map<String, dynamic>?> getTruckLocation(String vehicleNo) async {
    try {
      final snapshot = await _database
          .child('trucks')
          .child(vehicleNo)
          .child('currentLocation')
          .get();

      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get truck location: $e');
    }
  }

  /// Get today's location history for a specific vehicle.
  Future<List<Map<String, dynamic>>> getLocationHistory(
    String vehicleNo, {
    String? date,
    int? limit,
  }) async {
    try {
      final dateKey = date ?? _todayDate;
      Query query = _database
          .child('deliveries')
          .child(dateKey)
          .child(vehicleNo)
          .child('locationHistory')
          .orderByChild('timestamp');

      if (limit != null) {
        query = query.limitToLast(limit);
      }

      final snapshot = await query.get();

      if (snapshot.exists) {
        final List<Map<String, dynamic>> history = [];
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        data.forEach((key, value) {
          history.add(Map<String, dynamic>.from(value as Map));
        });

        history.sort(
          (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0),
        );

        return history;
      }
      return [];
    } catch (e) {
      throw Exception('Failed to get location history: $e');
    }
  }

  /// Clear today's location history for the current vehicle.
  Future<void> clearLocationHistory() async {
    _assertInitialized();

    try {
      await _todayRef.child('locationHistory').remove();
    } catch (e) {
      throw Exception('Failed to clear location history: $e');
    }
  }

  /// Record a completed drop-point delivery under
  /// deliveries/{date}/{vehicleNo}/completedDeliveries/{pushId}.
  ///
  /// [scannedItems] is the list of item maps from the delivery scanner.
  Future<void> markDeliveryCompleted({
    required String dropPointCode,
    required LatLng location,
    List<String>? invoiceNumbers,
    List<Map<String, String>>? scannedItems,
  }) async {
    _assertInitialized();

    try {
      final deliveryData = {
        'dropPointCode': dropPointCode,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'invoiceNumbers': invoiceNumbers ?? [],
        'itemCount': scannedItems?.length ?? 0,
        'scannedItems': scannedItems ?? [],
        if (_driverId != null) 'driverId': _driverId,
        'timestamp': ServerValue.timestamp,
      };

      await _todayRef.child('completedDeliveries').push().set(deliveryData);
    } catch (e) {
      throw Exception('Failed to mark delivery as completed: $e');
    }
  }

  /// Get all completed deliveries for a vehicle on a given date (defaults to today).
  Future<List<Map<String, dynamic>>> getCompletedDeliveries(
    String vehicleNo, {
    String? date,
  }) async {
    try {
      final dateKey = date ?? _todayDate;
      final snapshot = await _database
          .child('deliveries')
          .child(dateKey)
          .child(vehicleNo)
          .child('completedDeliveries')
          .orderByChild('timestamp')
          .get();

      if (snapshot.exists) {
        final List<Map<String, dynamic>> deliveries = [];
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        data.forEach((key, value) {
          deliveries.add(Map<String, dynamic>.from(value as Map));
        });

        deliveries.sort(
          (a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0),
        );

        return deliveries;
      }
      return [];
    } catch (e) {
      throw Exception('Failed to get completed deliveries: $e');
    }
  }

  /// Mark the current route as finished for the day.
  Future<void> endRoute() async {
    _assertInitialized();

    try {
      await _todayRef.child('activeRoute').update({
        'status': 'completed',
        'endTime': ServerValue.timestamp,
      });

      await updateTruckStatus(status: 'idle');
    } catch (e) {
      throw Exception('Failed to end route: $e');
    }
  }
}
