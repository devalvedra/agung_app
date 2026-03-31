# Firebase Location Tracking - Quick Start

## Overview

The delivery app now includes Firebase Realtime Database integration to save and sync truck locations in real-time. This enables remote monitoring and tracking of delivery vehicles.

## Features

✅ **Real-time Location Sync**: Truck location is automatically synced to Firebase every 5 seconds  
✅ **Location History**: All location updates are stored with timestamps  
✅ **Route Tracking**: Active route information is saved to Firebase  
✅ **Delivery Logging**: Completed deliveries are tracked with location and timestamp  
✅ **Status Updates**: Truck status (tracking, stopped, simulating) is monitored  
✅ **Automatic Sync**: Works with both GPS tracking and simulation mode

## Setup Instructions

### 1. Install Dependencies (Already Done ✓)

The following Firebase packages have been added to `pubspec.yaml`:

- `firebase_core: ^3.8.1`
- `firebase_database: ^11.3.4`

Run `flutter pub get` to install (already completed).

### 2. Configure Firebase Project

Follow the detailed setup guide in [docs/firebase_setup.md](firebase_setup.md).

**Quick Steps:**

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable Firebase Realtime Database
3. Download configuration files:
   - Android: `google-services.json` → place in `android/app/`
   - iOS: `GoogleService-Info.plist` → add to `ios/Runner/` via Xcode

### 3. Firebase Database Rules

For development, use test mode rules:

```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

⚠️ **Important**: Update rules for production (see [firebase_setup.md](firebase_setup.md) for secure rules).

## How It Works

### Automatic Location Sync

The app automatically syncs location data when:

- **Route Selected**: Route information is saved to Firebase
- **Tracking Started**: Location updates every 5 seconds (GPS or simulation mode)
- **Tracking Stopped**: Firebase sync is paused
- **Delivery Completed**: Delivery is logged with location and timestamp
- **Route Finished**: Route status is updated to "completed"

### Code Integration Points

1. **Firebase Service** (`lib/services/firebase_location_service.dart`)

   - Handles all Firebase operations
   - Provides methods for location sync, route tracking, and delivery logging

2. **Tracking Screen** (`lib/screens/tracking_screen.dart`)

   - Integrates Firebase service
   - Syncs location automatically during tracking
   - Logs deliveries and route completion

3. **Main App** (`lib/main.dart`)
   - Initializes Firebase on app startup

## Firebase Data Structure

```
firebase-root/
  └── trucks/
      └── {truckId}/          // e.g., "truck_001"
          ├── currentLocation/
          │   ├── latitude: -1.234
          │   ├── longitude: 109.345
          │   ├── routeCode: "A"
          │   ├── segmentIndex: 2
          │   ├── bearing: 45.0
          │   ├── isSimulation: false
          │   └── timestamp: 1705492800000
          ├── locationHistory/
          │   └── {pushId}/
          │       └── [same fields as currentLocation]
          ├── activeRoute/
          │   ├── routeCode: "A"
          │   ├── routeName: "Route A"
          │   ├── routePoints: [...]
          │   ├── startTime: 1705492800000
          │   └── status: "active"
          ├── status/
          │   ├── status: "tracking"
          │   ├── timestamp: 1705492800000
          │   └── routeCode: "A"
          └── completedDeliveries/
              └── {pushId}/
                  ├── dropPointCode: "T-001"
                  ├── latitude: -1.234
                  ├── longitude: 109.345
                  └── timestamp: 1705492800000
```

## Truck ID Configuration

Currently using a default truck ID: `truck_001`

**To customize:**

1. Open `lib/screens/tracking_screen.dart`
2. Find the `_initializeFirebaseService()` method
3. Replace `'truck_001'` with your truck identifier

**For production:**

- Get truck ID from user authentication
- Use driver ID or device ID
- Store in user profile or device storage

## Monitoring Locations

### In Firebase Console

1. Go to Firebase Console → Realtime Database
2. Navigate to `trucks/{truckId}/currentLocation`
3. See real-time updates as the truck moves

### Example Data

```json
{
  "currentLocation": {
    "latitude": -1.234567,
    "longitude": 109.345678,
    "routeCode": "A",
    "segmentIndex": 2,
    "bearing": 45.0,
    "isSimulation": false,
    "timestamp": 1705492800000
  }
}
```

## Testing

### 1. Test with Simulation Mode

1. Open the app and go to Tracking screen
2. Select a route
3. Enable Simulation Mode (car icon in app bar)
4. Start tracking
5. Open Firebase Console and watch `currentLocation` update every 5 seconds

### 2. Test with GPS Tracking

1. Ensure GPS is enabled on device
2. Select a route
3. Disable Simulation Mode (GPS icon)
4. Start tracking
5. Move physically or use location simulation
6. Monitor Firebase Console for updates

### 3. Test Delivery Completion

1. Start tracking a route
2. Arrive at a drop point
3. Complete the delivery (scan items)
4. Check `completedDeliveries` in Firebase Console

## Troubleshooting

### Firebase Not Initialized

- Check that `google-services.json` or `GoogleService-Info.plist` is in the correct location
- Verify Firebase is initialized in `main.dart`
- Check device logs for initialization errors

### Location Not Syncing

- Ensure internet connection is available
- Check Firebase Console database rules
- Verify truck ID is initialized
- Check device logs for error messages

### Permission Denied

- Update Firebase database rules
- Check that `.read` and `.write` are set to `true` for development

## API Methods

### FirebaseLocationService Methods

```dart
// Initialize service
_firebaseLocationService.initialize('truck_001');

// Save current location
await _firebaseLocationService.saveLocation(
  position: LatLng(lat, lng),
  routeCode: 'A',
  segmentIndex: 1,
  bearing: 45.0,
  isSimulation: false,
);

// Save route info
await _firebaseLocationService.saveRouteInfo(
  routeCode: 'A',
  routeName: 'Route A',
  routePoints: [...],
);

// Update truck status
await _firebaseLocationService.updateTruckStatus(
  status: 'tracking',
  additionalData: {...},
);

// Mark delivery completed
await _firebaseLocationService.markDeliveryCompleted(
  dropPointCode: 'T-001',
  location: LatLng(lat, lng),
  invoiceNumbers: ['INV001', 'INV002'],
);

// End route
await _firebaseLocationService.endRoute();

// Get truck location
final location = await _firebaseLocationService.getTruckLocation('truck_001');

// Get location history
final history = await _firebaseLocationService.getLocationHistory(
  'truck_001',
  limit: 100,
);

// Listen to location updates
_firebaseLocationService.listenToTruckLocation('truck_001').listen((data) {
  print('Truck moved to: ${data['latitude']}, ${data['longitude']}');
});
```

## Next Steps

1. **Add Firebase Configuration Files**

   - Download `google-services.json` and `GoogleService-Info.plist`
   - Place in correct directories

2. **Test the Integration**

   - Run the app and test location sync
   - Monitor Firebase Console

3. **Build Monitoring Dashboard** (Optional)

   - Create a web dashboard to monitor all trucks
   - Use Firebase SDK for web
   - Display real-time locations on a map

4. **Implement Authentication** (Recommended)
   - Add Firebase Authentication
   - Use authenticated user ID as truck ID
   - Update database rules for security

## Security Notes

⚠️ **Before Production:**

1. Implement proper authentication
2. Update Firebase database rules to restrict access
3. Protect API keys and configuration files
4. Implement rate limiting
5. Monitor usage and costs

## Support

For detailed setup instructions, see [docs/firebase_setup.md](firebase_setup.md)

For Firebase issues, check:

- [Firebase Documentation](https://firebase.google.com/docs)
- [FlutterFire Documentation](https://firebase.flutter.dev/)
