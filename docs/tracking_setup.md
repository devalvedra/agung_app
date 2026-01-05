# Package Tracking Setup

This document explains how to set up and use the package tracking feature.

## Features

- **Real-time Route Visualization**: Display delivery routes on Google Maps
- **Animated Tracking**: Watch the delivery truck move through route points
- **Multiple Routes**: Switch between different delivery routes
- **Route Information**: View progress and stop details

## Setup Instructions

### 1. Google Maps API Setup

Follow the [Google Maps API Setup Guide](./google_maps_api_setup.md) to configure Google Maps for your app.

### 2. Add Truck Icon Asset

Create a truck icon image and place it in the `assets/images/` folder:

**Option A: Download a free icon**

1. Visit [Flaticon](https://www.flaticon.com/) or [Icons8](https://icons8.com/)
2. Search for "delivery truck icon"
3. Download as PNG (recommended size: 96x96 or 128x128 pixels)
4. Save as `assets/images/truck_icon.png`

**Option B: Create your own**

1. Use any image editor to create a simple truck icon
2. Export as PNG with transparent background
3. Recommended size: 96x96 to 128x128 pixels
4. Save as `assets/images/truck_icon.png`

**Option C: Use Material Icons (fallback)**
The app will automatically use a default blue marker if the custom icon is not found.

### 3. Create Assets Directory

```bash
mkdir -p assets/images
```

Then add your `truck_icon.png` file to this directory.

### 4. Install Dependencies

Run the following command to install the Google Maps package:

```bash
flutter pub get
```

### 5. Configure Route Data

The app loads routes from `lib/constants/dummy_data.json`. Each route point should include:

```json
{
  "drop_point_code": "T-001",
  "sequence": 2,
  "lat": "0.3643",
  "lng": "108.9549"
}
```

**Required fields:**

- `drop_point_code`: Unique identifier for the location
- `sequence`: Order of the stop in the route
- `lat`: Latitude coordinate (as string)
- `lng`: Longitude coordinate (as string)

## Usage

### Basic Usage

1. Open the app and navigate to the **Tracking** screen
2. Select a route from the dropdown menu
3. Watch the truck icon animate through the route points
4. Tap on markers to see location details

### Controls

- **Route Dropdown**: Select which delivery route to track
- **Restart Button**: Reset and replay the route animation
- **Map Controls**: Zoom, pan, and interact with the map
- **Markers**: Tap to view stop information

### Map Legend

- 🟢 **Green Marker**: Starting point (Home Office)
- 🔵 **Truck Icon**: Current delivery position
- 🟠 **Orange Markers**: Intermediate stops
- 🔴 **Red Marker**: Final destination

## Customization

### Animation Speed

To change how fast the truck moves between points, edit the timer duration in `tracking_screen.dart`:

```dart
_animationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
  // Change 'seconds: 3' to your preferred speed
```

### Map Style

You can change the map type by modifying:

```dart
GoogleMap(
  mapType: MapType.normal, // Options: normal, satellite, hybrid, terrain
  ...
)
```

### Marker Icons

Customize marker colors by changing the hue values:

```dart
BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen) // Start
BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange) // Stops
BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed) // End
```

### Polyline Style

Customize the route line by modifying the polyline properties:

```dart
Polyline(
  color: Colors.blue, // Change line color
  width: 5, // Change line thickness
  patterns: [PatternItem.dash(20), PatternItem.gap(10)], // Dash pattern
)
```

## Troubleshooting

### Map not showing

- Verify Google Maps API key is correctly configured
- Check that Maps SDK is enabled in Google Cloud Console
- Ensure billing is enabled on your Google Cloud project

### Truck icon not appearing

- Verify `truck_icon.png` exists in `assets/images/`
- Check that `assets/images/` is listed in `pubspec.yaml`
- Run `flutter clean` and `flutter pub get`

### Route not displaying

- Verify route data has valid lat/lng coordinates
- Check that coordinates are within valid ranges (-90 to 90 for lat, -180 to 180 for lng)
- Ensure route points are properly formatted in dummy_data.json

### Animation not working

- Check browser console for errors (if running on web)
- Verify route has at least 2 points with coordinates
- Ensure the selected route exists in dummy_data.json

## Adding More Routes

To add new routes, edit `lib/constants/dummy_data.json`:

```json
{
  "code": "C",
  "name": "Rute C",
  "route_points": [
    {
      "drop_point_code": "HO",
      "sequence": 1,
      "lat": "0.0263",
      "lng": "109.3425"
    },
    {
      "drop_point_code": "T-005",
      "sequence": 2,
      "lat": "0.4523",
      "lng": "109.2341"
    }
  ]
}
```

## Performance Tips

1. **Limit markers**: Too many markers can slow down the map
2. **Optimize icon size**: Use appropriately sized images (96x96 to 128x128)
3. **Reduce animation frequency**: Increase timer duration for smoother performance
4. **Cache icons**: Icons are loaded once and reused throughout the session

## Future Enhancements

Potential features to add:

- Real-time GPS tracking
- Delivery status updates
- Estimated time of arrival (ETA)
- Driver information
- Push notifications for delivery updates
- Route optimization
- Traffic data integration
