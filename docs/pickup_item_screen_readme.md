# Pickup Item Screen Implementation

## Overview

This document describes the implementation of the **PickupItemScreen** feature with QR code scanning functionality and Firebase Cloud Messaging (FCM) integration.

## Files Created/Modified

### New Files:

1. **lib/screens/pickup_item_screen.dart** - Main screen with QR scanning and invoice list
2. **lib/services/fcm_service.dart** - FCM service for handling push notifications
3. **docs/pickup_item_screen_readme.md** - This documentation file

### Modified Files:

1. **lib/main.dart** - Added route and FCM initialization
2. **lib/screens/home_screen.dart** - Added navigation item for PickupItemScreen
3. **pubspec.yaml** - Added dependencies (firebase_messaging, http)

## Features

### 1. QR Code Scanning

- **Toggle Scanner**: Tap the QR code icon in the app bar to open/close the scanner
- **Visual Feedback**:
  - Sound effect on successful scan
  - Vibration feedback
  - Visual overlay with scanning frame
- **Invoice Matching**: Scans QR codes and matches them against the invoice list
- **Result Display**: Shows matched invoice details in a dialog

### 2. Invoice List

- **API Integration**: Fetches invoices from a dummy API endpoint
- **Display Format**: Shows invoice details including:
  - Invoice number (e.g., INV-00001)
  - Title
  - Status (Pending/Ready)
  - Number of items
  - Date
- **Pull to Refresh**: Swipe down to refresh the invoice list
- **Tap for Details**: Tap any invoice card to view full details

### 3. Firebase Cloud Messaging (FCM)

- **Auto-Refresh**: Automatically refreshes invoice list when FCM notification is received
- **Topic Subscription**: Subscribes to "invoice_updates" topic
- **Foreground Notifications**: Shows in-app snackbar when notification is received
- **Background Handling**: Processes notifications even when app is in background
- **Deep Linking**: Opens PickupItemScreen when notification is tapped (for type: invoice_update)

## Usage

### Accessing the Screen

1. From Home Screen: Tap on "Pickup Items" card
2. Direct Navigation: `Get.toNamed('/pickup')`

### Scanning QR Codes

1. Tap the QR code scanner icon in the app bar
2. Point camera at QR code
3. Wait for automatic detection
4. View matched invoice details or error message
5. Scanner closes automatically after successful scan

### Refreshing Invoices

- **Manual**: Tap the refresh icon in app bar or pull down to refresh
- **Automatic**: Triggered when FCM notification is received

## API Integration

### Current Implementation (Dummy Data)

```dart
final String _apiEndpoint = 'https://jsonplaceholder.typicode.com/posts';
```

### Production Setup

Replace the `_apiEndpoint` with your actual API:

```dart
final String _apiEndpoint = 'https://your-api.com/api/invoices';
```

Expected API Response Format:

```json
[
  {
    "id": "1",
    "invoice_number": "INV-00001",
    "title": "Invoice Title",
    "status": "Ready",
    "items": 5,
    "date": "2026-02-22"
  }
]
```

## FCM Setup

### 1. Firebase Console Configuration

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to Cloud Messaging
4. Add your app (Android/iOS)
5. Download and add configuration files:
   - Android: `google-services.json` → `android/app/`
   - iOS: `GoogleService-Info.plist` → `ios/Runner/`

### 2. Android Configuration

Add to `android/app/build.gradle`:

```gradle
dependencies {
    implementation 'com.google.firebase:firebase-messaging:23.4.0'
}
```

### 3. iOS Configuration

Add to `ios/Runner/Info.plist`:

```xml
<key>FirebaseMessagingAutoInitEnabled</key>
<true/>
```

### 4. Sending Test Notifications

#### Using Firebase Console:

1. Go to Cloud Messaging → New Campaign
2. Select "Firebase Notification messages"
3. Add notification title and body
4. Target: Select your app
5. Additional options:
   - Custom data: Add key-value pairs
   - Example: `type: invoice_update`

#### Using FCM API:

```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: Bearer YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "/topics/invoice_updates",
    "notification": {
      "title": "New Invoice Update",
      "body": "Invoice list has been updated"
    },
    "data": {
      "type": "invoice_update"
    }
  }'
```

### 5. Topic Subscription

The app automatically subscribes to the "invoice_updates" topic on initialization:

```dart
await _fcmService.subscribeToTopic('invoice_updates');
```

## Code Structure

### PickupItemScreen

```dart
class PickupItemScreen extends StatefulWidget
├── State Management
│   ├── _invoices: List<Map<String, dynamic>>
│   ├── _isLoading: bool
│   ├── _isScannerActive: bool
│   └── _scannerController: MobileScannerController
├── FCM Integration
│   ├── _initializeFCM()
│   └── onInvoiceDataReceived callback
├── API Integration
│   └── _fetchInvoices()
├── Scanner Functions
│   ├── _toggleScanner()
│   ├── _onBarcodeDetect()
│   └── _processScannedCode()
└── UI Components
    ├── Scanner Section
    ├── Invoice List
    └── Invoice Cards
```

### FCM Service

```dart
class FCMService
├── Initialization
│   ├── initialize()
│   └── requestPermission()
├── Message Handlers
│   ├── _handleForegroundMessage()
│   └── _handleMessageOpenedApp()
├── Topic Management
│   ├── subscribeToTopic()
│   └── unsubscribeFromTopic()
└── Callbacks
    └── onInvoiceDataReceived: Function(Map<String, dynamic>)?
```

## Testing

### Manual Testing

1. **QR Scanner**:
   - Open scanner
   - Scan valid invoice QR code
   - Verify sound and vibration
   - Check invoice details dialog

2. **Invoice List**:
   - Verify list loads on screen open
   - Test pull-to-refresh
   - Tap invoice to view details
   - Check status badges

3. **FCM**:
   - Send test notification from Firebase Console
   - Verify notification appears
   - Check if list refreshes automatically
   - Test app in foreground and background

### QR Code Testing

Generate test QR codes with invoice numbers:

- INV-00001
- INV-00002
- etc.

Use online QR code generators:

- https://www.qr-code-generator.com/
- https://www.the-qrcode-generator.com/

## Dependencies

```yaml
dependencies:
  mobile_scanner: ^7.1.4 # QR code scanning
  firebase_messaging: ^16.1.0 # Push notifications
  http: ^1.2.2 # HTTP requests
  audioplayers: ^6.5.1 # Sound effects
  vibration: ^3.1.5 # Haptic feedback
  get: ^4.7.3 # State management & navigation
  firebase_core: ^4.3.0 # Firebase initialization
```

## Troubleshooting

### Issue: Scanner not working

**Solution**: Check camera permissions in device settings

### Issue: Invoices not loading

**Solution**:

1. Check internet connection
2. Verify API endpoint is accessible
3. Check console for error messages

### Issue: FCM notifications not received

**Solution**:

1. Verify Firebase configuration files are in place
2. Check FCM token is generated (see logs)
3. Ensure app has notification permissions
4. Verify topic subscription is successful

### Issue: Sound not playing

**Solution**:

1. Check if sound file exists: `assets/sounds/success.mp3`
2. Verify assets are declared in `pubspec.yaml`
3. Check device volume settings

## Future Enhancements

1. Offline support with local database
2. Barcode format validation
3. Batch scanning multiple QR codes
4. Export invoice list to PDF/Excel
5. Filter and search functionality
6. Custom notification sounds per invoice status
7. Real-time invoice status updates via WebSocket

## Notes

- The current implementation uses a dummy API endpoint for demonstration
- Replace with actual production API endpoint before deployment
- FCM token should be sent to your backend for targeted notifications
- Consider implementing proper error handling and retry logic for production use
