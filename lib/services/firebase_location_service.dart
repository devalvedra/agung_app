import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Service to sync truck location and delivery data with Firebase Realtime Database.
///
/// Firebase structure:
/// ```
/// trucks/{vehicleNo}/
///   currentLocation/   ← real-time position (always latest)
///   status/            ← current tracking status
///   activeRoute/       ← route info for the day
///   locationHistory/   ← push-keyed GPS updates
///
/// deliveries/{invoiceNo}/
///   vehicleNo: string
///   driverId: string
///   status: string
///   dropPointCode: string
///   latitude: double
///   longitude: double
///   items: array
///   timestamp: ServerTimestamp
/// ```
class FirebaseLocationService extends GetxService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  String? _vehicleNo;
  String? _driverId;

  /// Invoice numbers that have been fully delivered this session.
  /// Used to skip overwriting 'delivered' status during location syncs.
  final Set<String> _deliveredInvoices = {};

  /// Reference to the vehicle node under trucks/.
  DatabaseReference get _vehicleRef =>
      _database.child('trucks').child(_vehicleNo!);

  /// Reference to the real-time current-location node (always overwritten).
  DatabaseReference get _currentLocationRef =>
      _vehicleRef.child('currentLocation');

  /// Initialize the service with the vehicle number and optional driver ID.
  void initialize(String vehicleNo, {String? driverId}) {
    _vehicleNo = vehicleNo;
    _driverId = driverId;
    _deliveredInvoices.clear();
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
  /// - Appends to location history under trucks/{vehicleNo}/locationHistory.
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

      // Location history under the vehicle node
      await _vehicleRef.child('locationHistory').push().set(locationData);
    } catch (e) {
      throw Exception('Failed to save location to Firebase: $e');
    }
  }

  /// Save route information under trucks/{vehicleNo}/activeRoute.
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

      await _vehicleRef.child('activeRoute').set(routeData);
    } catch (e) {
      throw Exception('Failed to save route info to Firebase: $e');
    }
  }

  /// Update tracking status under trucks/{vehicleNo}/status.
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

      await _vehicleRef.child('status').set(statusData);
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

  /// Get location history for a specific vehicle.
  Future<List<Map<String, dynamic>>> getLocationHistory(
    String vehicleNo, {
    int? limit,
  }) async {
    try {
      Query query = _database
          .child('trucks')
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

  /// Clear location history for the current vehicle.
  Future<void> clearLocationHistory() async {
    _assertInitialized();

    try {
      await _vehicleRef.child('locationHistory').remove();
    } catch (e) {
      throw Exception('Failed to clear location history: $e');
    }
  }

  /// Record a completed delivery under deliveries/{invoiceNo}/.
  /// Writes one record per invoice number.
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
      final invoices = invoiceNumbers ?? [];
      _deliveredInvoices.addAll(invoices);

      for (final invoiceNo in invoices) {
        final items =
            scannedItems
                ?.where((item) => item['invoice_code'] == invoiceNo)
                .toList() ??
            [];

        final deliveryData = {
          'vehicleNo': _vehicleNo,
          if (_driverId != null) 'driverId': _driverId,
          'status': 'delivered',
          'dropPointCode': dropPointCode,
          'latitude': location.latitude,
          'longitude': location.longitude,
          'items': items,
          'timestamp': ServerValue.timestamp,
        };

        await _database
            .child('deliveries')
            .child(invoiceNo)
            .update(deliveryData);
      }
    } catch (e) {
      throw Exception('Failed to mark delivery as completed: $e');
    }
  }

  /// Update location and set status to 'on-delivery' for all active (not yet
  /// delivered) invoices. Uses update() so it will not overwrite the 'delivered'
  /// status written by markDeliveryCompleted.
  Future<void> updateDeliveryLocations({
    required LatLng position,
    required List<String> invoiceNumbers,
  }) async {
    _assertInitialized();

    if (invoiceNumbers.isEmpty) return;

    try {
      for (final invoiceNo in invoiceNumbers) {
        // Skip invoices already confirmed as delivered this session
        if (_deliveredInvoices.contains(invoiceNo)) continue;

        await _database.child('deliveries').child(invoiceNo).update({
          'vehicleNo': _vehicleNo,
          if (_driverId != null) 'driverId': _driverId,
          'status': 'on-delivery',
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': ServerValue.timestamp,
        });
      }
    } catch (e) {
      throw Exception('Failed to update delivery locations: $e');
    }
  }

  /// Get all deliveries for a specific vehicle by querying deliveries/{invoiceNo}/vehicleNo.
  /// Requires a Firebase index on the vehicleNo field.
  Future<List<Map<String, dynamic>>> getCompletedDeliveries(
    String vehicleNo,
  ) async {
    try {
      final snapshot = await _database
          .child('deliveries')
          .orderByChild('vehicleNo')
          .equalTo(vehicleNo)
          .get();

      if (snapshot.exists) {
        final List<Map<String, dynamic>> deliveries = [];
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        data.forEach((key, value) {
          final record = Map<String, dynamic>.from(value as Map);
          record['invoiceNo'] = key;
          deliveries.add(record);
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

  /// Mark the current route as finished.
  Future<void> endRoute() async {
    _assertInitialized();

    try {
      await _vehicleRef.child('activeRoute').update({
        'status': 'completed',
        'endTime': ServerValue.timestamp,
      });

      await updateTruckStatus(status: 'idle');
    } catch (e) {
      throw Exception('Failed to end route: $e');
    }
  }
}
