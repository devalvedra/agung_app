# Google Maps API Setup Guide

This guide will help you set up Google Maps API for the Delivery App tracking feature.

## Prerequisites

- Google Cloud Platform account
- Flutter project setup

## Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click on the project dropdown at the top
3. Click "New Project"
4. Enter a project name (e.g., "Delivery App")
5. Click "Create"

## Step 2: Enable Google Maps APIs

1. In the Google Cloud Console, go to "APIs & Services" > "Library"
2. Search for and enable the following APIs:
   - **Maps SDK for Android**
   - **Maps SDK for iOS**
   - **Maps JavaScript API** (optional, for web)
   - **Directions API** (for route directions)
   - **Places API** (optional, for location search)

## Step 3: Create API Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "API Key"
3. Copy the generated API key
4. Click "Restrict Key" to add restrictions:
   - For Android: Add your app's SHA-1 fingerprint and package name
   - For iOS: Add your app's bundle identifier
   - For API restrictions: Select the APIs you enabled

## Step 4: Get SHA-1 Fingerprint (Android)

### For Debug Build:

```bash
cd android
./gradlew signingReport
```

Look for the SHA-1 under "Variant: debug" and "Config: debug"

### For Release Build:

```bash
keytool -list -v -keystore your-release-key.keystore -alias your-key-alias
```

## Step 5: Configure Android

1. Open `android/app/src/main/AndroidManifest.xml`
2. Add the following inside the `<application>` tag:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_API_KEY_HERE"/>
```

## Step 6: Configure iOS

1. Open `ios/Runner/AppDelegate.swift`
2. Import GoogleMaps:

```swift
import GoogleMaps
```

3. Add the following in `application(_:didFinishLaunchingWithOptions:)`:

```swift
GMSServices.provideAPIKey("YOUR_API_KEY_HERE")
```

4. Open `ios/Podfile` and ensure minimum iOS version is 13.0 or higher:

```ruby
platform :ios, '13.0'
```

## Step 7: Update pubspec.yaml

Add the Google Maps Flutter package:

```yaml
dependencies:
  google_maps_flutter: ^2.14.0
```

Then run:

```bash
flutter pub get
```

## Step 8: Add Permissions

### Android (`android/app/src/main/AndroidManifest.xml`):

Add before the `<application>` tag:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS (`ios/Runner/Info.plist`):

Add the following keys:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs access to location for tracking delivery.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>This app needs access to location for tracking delivery.</string>
```

## Step 9: Test the Setup

Run your Flutter app and verify that the map loads correctly.

## Troubleshooting

### Map shows blank or gray screen

- Verify API key is correctly added
- Check if Maps SDK is enabled in Google Cloud Console
- Ensure billing is enabled on your Google Cloud project
- Check SHA-1 fingerprint matches your app

### "API key not valid" error

- Make sure API restrictions match your app's package name/bundle ID
- Verify the API key has Maps SDK enabled
- Check if billing is enabled

### iOS map not loading

- Ensure `GMSServices.provideAPIKey()` is called before map initialization
- Check Info.plist has location permissions
- Run `pod install` in the ios folder

## Cost Considerations

Google Maps has a free tier with $200 monthly credit. Monitor your usage in the Google Cloud Console to avoid unexpected charges.

For more details, visit:

- [Google Maps Platform Documentation](https://developers.google.com/maps/documentation)
- [Flutter Google Maps Plugin](https://pub.dev/packages/google_maps_flutter)

## Security Best Practices

1. **Never commit API keys to version control**
2. Use environment variables or secure storage
3. Implement API key restrictions
4. Monitor API usage regularly
5. Consider using separate keys for development and production
