# Firebase Setup for Delivery App

## Firebase Realtime Database Setup

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project"
3. Follow the wizard to create your project
4. Enable Google Analytics (optional)

### 2. Add Firebase to Flutter App

#### Android Setup

1. In Firebase Console, click "Add app" and select Android
2. Enter your Android package name (found in `android/app/build.gradle.kts`)
3. Download the `google-services.json` file
4. Place it in `android/app/` directory
5. Add the following to `android/build.gradle.kts`:

```kotlin
plugins {
    // ... existing plugins
    id("com.google.gms.google-services") version "4.4.0" apply false
}
```

6. Add to `android/app/build.gradle.kts`:

```kotlin
plugins {
    // ... existing plugins
    id("com.google.gms.google-services")
}

dependencies {
    // ... existing dependencies
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
}
```

#### iOS Setup

1. In Firebase Console, click "Add app" and select iOS
2. Enter your iOS bundle ID (found in `ios/Runner.xcodeproj/project.pbxproj`)
3. Download the `GoogleService-Info.plist` file
4. Open `ios/Runner.xcworkspace` in Xcode
5. Drag the `GoogleService-Info.plist` file into the Runner folder
6. Ensure "Copy items if needed" is checked

### 3. Enable Firebase Realtime Database

1. In Firebase Console, go to "Build" > "Realtime Database"
2. Click "Create Database"
3. Choose a location (e.g., us-central1)
4. Start in **test mode** for development (remember to update rules for production)

### 4. Firebase Database Rules

For development, you can use test mode rules:

```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

**⚠️ IMPORTANT: For production, use proper security rules:**

```json
{
  "rules": {
    "trucks": {
      "$truckId": {
        ".read": true,
        ".write": "auth != null && auth.uid == $truckId",
        "currentLocation": {
          ".validate": "newData.hasChildren(['latitude', 'longitude', 'routeCode', 'timestamp'])"
        },
        "locationHistory": {
          ".indexOn": ["timestamp"]
        }
      }
    }
  }
}
```

### 5. Database Structure

The app saves data in the following structure:

```
firebase-root/
  └── trucks/
      └── {truckId}/
          ├── currentLocation/
          │   ├── latitude: number
          │   ├── longitude: number
          │   ├── routeCode: string
          │   ├── segmentIndex: number
          │   ├── bearing: number
          │   ├── isSimulation: boolean
          │   └── timestamp: number
          ├── locationHistory/
          │   └── {pushId}/
          │       ├── latitude: number
          │       ├── longitude: number
          │       ├── routeCode: string
          │       ├── segmentIndex: number
          │       ├── bearing: number
          │       ├── isSimulation: boolean
          │       └── timestamp: number
          ├── activeRoute/
          │   ├── routeCode: string
          │   ├── routeName: string
          │   ├── routePoints: array
          │   ├── startTime: number
          │   ├── endTime: number (optional)
          │   └── status: "active" | "completed"
          ├── status/
          │   ├── status: string ("idle", "tracking", "stopped", "simulating")
          │   ├── timestamp: number
          │   ├── routeCode: string (optional)
          │   └── segmentIndex: number (optional)
          └── completedDeliveries/
              └── {pushId}/
                  ├── dropPointCode: string
                  ├── latitude: number
                  ├── longitude: number
                  ├── invoiceNumbers: array
                  └── timestamp: number
```

### 6. Initialize Firebase in Your App

Update your `lib/main.dart` to initialize Firebase:

```dart
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    print('Firebase initialized successfully');
  } catch (e) {
    print('Error initializing Firebase: $e');
  }

  runApp(const MyApp());
}
```

### 7. Testing Firebase Connection

After setup, run your app and check:

1. Firebase Console > Realtime Database - you should see data being written
2. Check device logs for "Firebase initialized successfully"
3. Monitor the location updates in real-time in the Firebase Console

### 8. Features Implemented

- **Real-time Location Tracking**: Truck location is synced every 5 seconds
- **Location History**: All location updates are stored with timestamps
- **Route Information**: Active route details are saved
- **Delivery Tracking**: Completed deliveries are logged with location
- **Status Updates**: Truck status (tracking, stopped, simulating) is tracked
- **Automatic Sync**: Location syncs automatically during GPS tracking or simulation

### 9. Usage in App

The Firebase integration is automatic:

- When you select a route, it's saved to Firebase
- When you start tracking (GPS or Simulation), location updates every 5 seconds
- When you complete a delivery, it's marked in Firebase
- When you finish a route, the route status is updated to "completed"

### 10. Monitoring

To monitor truck locations in real-time:

1. Go to Firebase Console > Realtime Database
2. Navigate to `trucks/{truckId}/currentLocation`
3. You'll see real-time updates as the truck moves

### 11. Querying Data

To retrieve location history or analyze routes, you can:

- Use Firebase Console to browse data
- Export data as JSON
- Use Firebase REST API
- Build a web dashboard using Firebase SDK

## Security Considerations

1. **Authentication**: Implement proper authentication before production
2. **Database Rules**: Update security rules to restrict access
3. **Data Privacy**: Ensure compliance with data protection regulations
4. **API Keys**: Protect your Firebase API keys
5. **Rate Limiting**: Monitor usage to prevent abuse

## Troubleshooting

### "Firebase not initialized" error

- Ensure `Firebase.initializeApp()` is called in `main()`
- Check that `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) is in the correct location

### Data not appearing in Firebase

- Check Firebase Console for database rules
- Ensure internet connection is available
- Check device logs for error messages
- Verify database URL in Firebase config

### Permission denied errors

- Update database rules to allow read/write access
- Implement authentication if using production rules

## Cost Monitoring

Firebase Realtime Database has a free tier:

- 1 GB stored data
- 10 GB/month downloaded
- 100 simultaneous connections

Monitor usage in Firebase Console > Usage tab to avoid unexpected charges.
