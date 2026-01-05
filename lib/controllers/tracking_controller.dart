import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TrackingController extends GetxController {
  // Selected route data
  final Rx<Map<String, dynamic>?> selectedRoute = Rx<Map<String, dynamic>?>(
    null,
  );
  final RxString selectedRouteCode = ''.obs;

  // Current segment index
  final RxInt currentSegmentIndex = 0.obs;

  // Truck position and state
  final Rx<LatLng?> truckPosition = Rx<LatLng?>(null);
  final RxDouble truckRotation = 0.0.obs;

  // Animation state
  final RxBool isAnimating = false.obs;
  final RxBool isSimulationMode = false.obs;

  // Route coordinates
  final RxList<LatLng> currentSegmentCoordinates = <LatLng>[].obs;

  // Methods to update state
  void setSelectedRoute(String? routeCode, Map<String, dynamic>? route) {
    selectedRouteCode.value = routeCode ?? '';
    selectedRoute.value = route;
  }

  void setCurrentSegmentIndex(int index) {
    currentSegmentIndex.value = index;
  }

  void setTruckPosition(LatLng? position) {
    truckPosition.value = position;
  }

  void setTruckRotation(double rotation) {
    truckRotation.value = rotation;
  }

  void setAnimatingState(bool animating) {
    isAnimating.value = animating;
  }

  void setSimulationMode(bool simulation) {
    isSimulationMode.value = simulation;
  }

  void setCurrentSegmentCoordinates(List<LatLng> coordinates) {
    currentSegmentCoordinates.value = coordinates;
  }

  void resetTracking() {
    selectedRoute.value = null;
    selectedRouteCode.value = '';
    currentSegmentIndex.value = 0;
    truckPosition.value = null;
    truckRotation.value = 0.0;
    isAnimating.value = false;
    currentSegmentCoordinates.clear();
  }

  void incrementSegment() {
    currentSegmentIndex.value++;
  }
}
