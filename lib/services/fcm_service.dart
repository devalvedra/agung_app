import 'dart:developer';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

/// Background message handler
/// Must be a top-level function or static function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('Handling background message: ${message.messageId}');
  log('Message data: ${message.data}');
  log('Message notification: ${message.notification?.title}');

  // Show notification in background
  await FCMService.instance.showNotification(
    title: message.notification?.title ?? 'New Notification',
    body: message.notification?.body ?? 'You have a new update',
    payload: message.data['type'] ?? 'default',
  );
}

/// FCM Service to handle Firebase Cloud Messaging (Singleton)
class FCMService {
  // Singleton pattern
  static final FCMService _instance = FCMService._internal();
  static FCMService get instance => _instance;

  factory FCMService() {
    return _instance;
  }

  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Callback for when new invoice data is received
  Function(Map<String, dynamic>)? onInvoiceDataReceived;

  bool _isInitialized = false;

  /// Initialize FCM and Local Notifications
  Future<void> initialize() async {
    if (_isInitialized) {
      log('FCM Service already initialized');
      return;
    }

    try {
      // Initialize local notifications
      await _initializeLocalNotifications();

      // Request permission for iOS
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      log('User granted permission: ${settings.authorizationStatus}');

      // Get FCM token
      String? token = await _firebaseMessaging.getToken();
      log('FCM Token: $token');

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification tap when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Check if app was opened from a notification
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // Subscribe to invoice updates topic by default
      await subscribeToTopic('invoice_updates');

      _isInitialized = true;
      log('FCM Service initialized successfully');
    } catch (e) {
      log('Error initializing FCM: $e');
    }
  }

  /// Initialize Flutter Local Notifications
  Future<void> _initializeLocalNotifications() async {
    // Android initialization settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    // Combined initialization settings
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Initialize with callback for notification taps
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'agung_app_channel', // id
      'Delivery Notifications', // name
      description: 'Notifications for delivery app updates',
      importance: Importance.high,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    log('Local notifications initialized');
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    log('Notification tapped with payload: ${response.payload}');

    // Navigate to MainNavigationScreen with Pickup tab (index 1)
    if (response.payload == 'invoice_update' || response.payload == 'default') {
      // Use a slight delay to ensure navigation context is ready
      Future.delayed(const Duration(milliseconds: 100), () {
        Get.offAllNamed('/', arguments: {'initialIndex': 1});
      });
    }
  }

  /// Show local notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'agung_app_channel',
          'Delivery Notifications',
          channelDescription: 'Notifications for delivery app updates',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: payload ?? 'default',
    );

    log('Notification shown: $title');
  }

  /// Handle foreground message
  void _handleForegroundMessage(RemoteMessage message) {
    log('Received foreground message: ${message.messageId}');
    log('Message data: ${message.data}');

    // Show system notification even when app is in foreground
    showNotification(
      title: message.notification?.title ?? 'New Notification',
      body: message.notification?.body ?? 'You have a new update',
      payload: message.data['type'] ?? 'default',
    );

    // Also show in-app snackbar
    if (message.notification != null) {
      Get.snackbar(
        message.notification!.title ?? 'New Notification',
        message.notification!.body ?? '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(10),
        borderRadius: 8,
        onTap: (_) {
          Get.offAllNamed('/', arguments: {'initialIndex': 1});
        },
      );
    }

    // Process the data
    _processInvoiceData(message.data);
  }

  /// Handle message when app is opened from notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    log('App opened from notification: ${message.messageId}');
    log('Message data: ${message.data}');

    // Navigate to MainNavigationScreen with Pickup tab (index 1)
    if (message.data['type'] == 'invoice_update') {
      Get.offAllNamed('/', arguments: {'initialIndex': 1});
    }

    // Process the data
    _processInvoiceData(message.data);
  }

  /// Process invoice data from FCM
  void _processInvoiceData(Map<String, dynamic> data) {
    if (data.isEmpty) return;

    log('Processing invoice data: $data');

    // Trigger callback if set
    if (onInvoiceDataReceived != null) {
      onInvoiceDataReceived!(data);
    }
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      log('Subscribed to topic: $topic');
    } catch (e) {
      log('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      log('Unsubscribed from topic: $topic');
    } catch (e) {
      log('Error unsubscribing from topic: $e');
    }
  }

  /// Get FCM token
  Future<String?> getToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      log('Error getting FCM token: $e');
      return null;
    }
  }
}
