import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Service to sync truck location with Firebase Realtime Database
class FirebaseLocationService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Unique truck/driver ID (should be retrieved from authentication in production)
  String? _truckId;

  /// Initialize the service with a truck ID
  void initialize(String truckId) {
    _truckId = truckId;
  }

  /// Save truck location to Firebase
  Future<void> saveLocation({
    required LatLng position,
    required String routeCode,
    int? segmentIndex,
    double? bearing,
    bool isSimulation = false,
  }) async {
    if (_truckId == null) {
      throw Exception('Truck ID not initialized. Call initialize() first.');
    }

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

      // Save to trucks/{truckId}/currentLocation
      await _database
          .child('trucks')
          .child(_truckId!)
          .child('currentLocation')
          .set(locationData);

      // Also save to location history with timestamp
      await _database
          .child('trucks')
          .child(_truckId!)
          .child('locationHistory')
          .push()
          .set(locationData);
    } catch (e) {
      throw Exception('Failed to save location to Firebase: $e');
    }
  }

  /// Save route information to Firebase
  Future<void> saveRouteInfo({
    required String routeCode,
    required String routeName,
    required List<Map<String, dynamic>> routePoints,
  }) async {
    if (_truckId == null) {
      throw Exception('Truck ID not initialized. Call initialize() first.');
    }

    try {
      final routeData = {
        'routeCode': routeCode,
        'routeName': routeName,
        'routePoints': routePoints,
        'startTime': ServerValue.timestamp,
        'status': 'active',
      };

      await _database
          .child('trucks')
          .child(_truckId!)
          .child('activeRoute')
          .set(routeData);
    } catch (e) {
      throw Exception('Failed to save route info to Firebase: $e');
    }
  }

  /// Update truck status
  Future<void> updateTruckStatus({
    required String status,
    Map<String, dynamic>? additionalData,
  }) async {
    if (_truckId == null) {
      throw Exception('Truck ID not initialized. Call initialize() first.');
    }

    try {
      final statusData = {
        'status': status,
        'timestamp': ServerValue.timestamp,
        ...?additionalData,
      };

      await _database
          .child('trucks')
          .child(_truckId!)
          .child('status')
          .set(statusData);
    } catch (e) {
      throw Exception('Failed to update truck status: $e');
    }
  }

  /// Listen to location updates for a specific truck
  Stream<Map<String, dynamic>> listenToTruckLocation(String truckId) {
    final controller = StreamController<Map<String, dynamic>>();

    _database
        .child('trucks')
        .child(truckId)
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

  /// Get current location for a specific truck
  Future<Map<String, dynamic>?> getTruckLocation(String truckId) async {
    try {
      final snapshot = await _database
          .child('trucks')
          .child(truckId)
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

  /// Get location history for a specific truck
  Future<List<Map<String, dynamic>>> getLocationHistory(
    String truckId, {
    int? limit,
  }) async {
    try {
      Query query = _database
          .child('trucks')
          .child(truckId)
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

        // Sort by timestamp descending
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

  /// Clear location history for the current truck
  Future<void> clearLocationHistory() async {
    if (_truckId == null) {
      throw Exception('Truck ID not initialized. Call initialize() first.');
    }

    try {
      await _database
          .child('trucks')
          .child(_truckId!)
          .child('locationHistory')
          .remove();
    } catch (e) {
      throw Exception('Failed to clear location history: $e');
    }
  }

  /// Mark delivery as completed at a drop point
  Future<void> markDeliveryCompleted({
    required String dropPointCode,
    required LatLng location,
    List<String>? invoiceNumbers,
  }) async {
    if (_truckId == null) {
      throw Exception('Truck ID not initialized. Call initialize() first.');
    }

    try {
      final deliveryData = {
        'dropPointCode': dropPointCode,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'invoiceNumbers': invoiceNumbers ?? [],
        'timestamp': ServerValue.timestamp,
      };

      await _database
          .child('trucks')
          .child(_truckId!)
          .child('completedDeliveries')
          .push()
          .set(deliveryData);
    } catch (e) {
      throw Exception('Failed to mark delivery as completed: $e');
    }
  }

  /// End the current route
  Future<void> endRoute() async {
    if (_truckId == null) {
      throw Exception('Truck ID not initialized. Call initialize() first.');
    }

    try {
      // Update route status
      await _database
          .child('trucks')
          .child(_truckId!)
          .child('activeRoute')
          .child('status')
          .set('completed');

      await _database
          .child('trucks')
          .child(_truckId!)
          .child('activeRoute')
          .child('endTime')
          .set(ServerValue.timestamp);

      // Update truck status
      await updateTruckStatus(status: 'idle');
    } catch (e) {
      throw Exception('Failed to end route: $e');
    }
  }
}
