import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/home_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/tracking_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/pickup_item_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/main_navigation_screen.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('Environment variables loaded successfully');
  } catch (e) {
    debugPrint('Error loading .env file: $e');
  }

  // Initialize Settings Service
  try {
    await SettingsService.instance.initialize();
    debugPrint('Settings Service initialized successfully');
    debugPrint('Base URL: ${SettingsService.instance.baseUrl}');
  } catch (e) {
    debugPrint('Error initializing Settings Service: $e');
  }

  // Initialize Auth Service
  try {
    await AuthService.instance.initialize();
    debugPrint(
      'Auth Service initialized – logged in: ${AuthService.instance.isLoggedIn}',
    );
  } catch (e) {
    debugPrint('Error initializing Auth Service: $e');
  }

  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized successfully');

    // Initialize FCM Service globally
    final fcmService = FCMService.instance;
    await fcmService.initialize();
    debugPrint('FCM Service initialized successfully');
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');
    // Continue even if Firebase fails to allow app to work offline
  }

  runApp(
    MainApp(initialRoute: AuthService.instance.isLoggedIn ? '/' : '/login'),
  );
}

class MainApp extends StatelessWidget {
  final String initialRoute;

  const MainApp({super.key, this.initialRoute = '/login'});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Agung App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      initialRoute: initialRoute,
      getPages: [
        GetPage(name: '/login', page: () => const LoginScreen()),
        GetPage(
          name: '/',
          page: () {
            final args = Get.arguments as Map<String, dynamic>?;
            final initialIndex = args?['initialIndex'] as int? ?? 0;
            return MainNavigationScreen(initialIndex: initialIndex);
          },
        ),
        GetPage(name: '/pickup', page: () => const PickupItemScreen()),
        GetPage(name: '/home', page: () => const HomeScreen()),
        GetPage(name: '/orders', page: () => const OrdersScreen()),
        GetPage(name: '/tracking', page: () => const TrackingScreen()),
        GetPage(name: '/profile', page: () => const ProfileScreen()),
      ],
    );
  }
}
