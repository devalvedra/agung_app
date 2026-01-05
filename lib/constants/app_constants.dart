/// Application-wide constants
class AppConstants {
  /// Google Maps API Key - Replace with your actual API key
  /// See docs/google_maps_api_setup.md for setup instructions
  static const String googleMapsApiKey =
      'AIzaSyBYNZhw1sqO7e5vRfOGBQ3NuLFThVvj5LM';

  /// Animation duration for truck movement between points (in seconds)
  static const int routeAnimationDurationSeconds = 10;

  /// Zoom level for route view (higher = more zoomed in, shows smaller area around truck)
  /// Recommended: 15-17 for street level, 18-20 for building level
  static const double routeZoomLevel = 12.0;

  /// Truck animation update interval in milliseconds (higher = slower movement)
  /// Recommended: 300-500 for realistic speed, 100-200 for faster animation
  static const int truckAnimationIntervalMs = 200;

  /// Animation speed multiplier (higher = faster animation, lower = slower)
  /// Default: 1.0 for normal speed, 2.0 for double speed, 0.5 for half speed
  static const double animationSpeedMultiplier = 2.0;

  /// Padding for map bounds (higher = more zoomed out to fit content)
  static const double mapBoundsPadding = 100.0;
}
