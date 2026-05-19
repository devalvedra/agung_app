import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'database_helper.dart';

/// Service to manage application settings including API base URL and user ID
class SettingsService {
  static final SettingsService instance = SettingsService._init();
  static const String _baseUrlKey = 'api_base_url';
  static const String _iduserKey = 'iduser';
  static const String _assignedFloorKey = 'assigned_floor';
  static const String _defaultBaseUrl = 'http://192.168.1.102:8000';
  static const String _defaultIduser = 'aling';

  String? _cachedBaseUrl;
  String? _cachedIduser;
  List<String>? _cachedAssignedFloor;

  SettingsService._init();

  /// Initialize settings service - load base URL and iduser from database
  Future<void> initialize() async {
    _cachedBaseUrl = await _loadBaseUrl();
    _cachedIduser = await _loadIduser();
    _cachedAssignedFloor = await _loadAssignedFloor();
  }

  /// Load base URL from database, fallback to .env, then default
  Future<String> _loadBaseUrl() async {
    try {
      // Try to get from database first
      final dbValue = await DatabaseHelper.instance.getSetting(_baseUrlKey);
      if (dbValue != null && dbValue.isNotEmpty) {
        return dbValue;
      }

      // Fallback to .env file
      final envValue = dotenv.env['API_BASE_URL'];
      if (envValue != null && envValue.isNotEmpty) {
        return envValue;
      }

      // Final fallback to default
      return _defaultBaseUrl;
    } catch (e) {
      // If any error, return default
      return _defaultBaseUrl;
    }
  }

  /// Get the current base URL (synchronously from cache or return default)
  String get baseUrl {
    return _cachedBaseUrl ?? _defaultBaseUrl;
  }

  /// Get the current base URL (asynchronously - ensures fresh data)
  Future<String> getBaseUrl() async {
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }
    _cachedBaseUrl = await _loadBaseUrl();
    return _cachedBaseUrl!;
  }

  /// Get the default base URL from .env or constant
  String getDefaultBaseUrl() {
    return dotenv.env['API_BASE_URL'] ?? _defaultBaseUrl;
  }

  /// Update the base URL and save to database
  Future<void> setBaseUrl(String newBaseUrl) async {
    if (newBaseUrl.isEmpty) {
      throw ArgumentError('Base URL cannot be empty');
    }

    // Remove trailing slash if present
    String cleanUrl = newBaseUrl.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }

    // Save to database
    await DatabaseHelper.instance.insertOrUpdateSetting(_baseUrlKey, cleanUrl);

    // Update cache
    _cachedBaseUrl = cleanUrl;
  }

  /// Reset base URL to default value
  Future<void> resetToDefault() async {
    final defaultUrl = getDefaultBaseUrl();
    await setBaseUrl(defaultUrl);
  }

  /// Clear cached base URL and reload from database
  Future<void> reload() async {
    _cachedBaseUrl = await _loadBaseUrl();
    _cachedIduser = await _loadIduser();
    _cachedAssignedFloor = await _loadAssignedFloor();
  }

  // ==================== IDUSER MANAGEMENT ====================

  /// Load iduser from database
  Future<String> _loadIduser() async {
    try {
      final dbValue = await DatabaseHelper.instance.getSetting(_iduserKey);
      if (dbValue != null && dbValue.isNotEmpty) {
        return dbValue;
      }
      return _defaultIduser;
    } catch (e) {
      return _defaultIduser;
    }
  }

  /// Get the current iduser (synchronously from cache)
  String get iduser {
    return _cachedIduser ?? _defaultIduser;
  }

  /// Get the current iduser (asynchronously - ensures fresh data)
  Future<String?> getIduser() async {
    if (_cachedIduser != null) {
      return _cachedIduser;
    }
    _cachedIduser = await _loadIduser();
    return _cachedIduser;
  }

  /// Update the iduser and save to database
  Future<void> setIduser(String newIduser) async {
    if (newIduser.isEmpty) {
      throw ArgumentError('User ID cannot be empty');
    }

    final cleanIduser = newIduser.trim();

    // Save to database
    await DatabaseHelper.instance.insertOrUpdateSetting(
      _iduserKey,
      cleanIduser,
    );

    // Update cache
    _cachedIduser = cleanIduser;
  }

  /// Sync iduser from an external source (e.g. AuthService) without saving to DB
  void syncIduser(String iduser) {
    _cachedIduser = iduser;
  }

  /// Clear iduser from database and cache
  Future<void> clearIduser() async {
    await DatabaseHelper.instance.deleteSetting(_iduserKey);
    _cachedIduser = null;
  }

  // ==================== ASSIGNED FLOOR MANAGEMENT ====================

  /// Load assigned floors from database (stored as comma-separated string)
  Future<List<String>> _loadAssignedFloor() async {
    try {
      final dbValue = await DatabaseHelper.instance.getSetting(
        _assignedFloorKey,
      );
      if (dbValue != null && dbValue.isNotEmpty) {
        return dbValue
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get the current assigned floors (synchronously from cache)
  List<String> get assignedFloor {
    return _cachedAssignedFloor ?? [];
  }

  /// Get the current assigned floors (asynchronously - ensures fresh data)
  Future<List<String>> getAssignedFloor() async {
    if (_cachedAssignedFloor != null) {
      return _cachedAssignedFloor!;
    }
    _cachedAssignedFloor = await _loadAssignedFloor();
    return _cachedAssignedFloor!;
  }

  /// Update the assigned floors and save to database as comma-separated string
  Future<void> setAssignedFloor(List<String> floors) async {
    final value = floors
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(',');
    await DatabaseHelper.instance.insertOrUpdateSetting(
      _assignedFloorKey,
      value,
    );
    _cachedAssignedFloor = floors.where((s) => s.trim().isNotEmpty).toList();
  }
}
