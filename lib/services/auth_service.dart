import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'database_helper.dart';
import 'settings_service.dart';

/// Service to manage authentication (login/logout/token) via Laravel Sanctum
class AuthService {
  static final AuthService instance = AuthService._init();

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user_json';

  String? _cachedToken;
  Map<String, dynamic>? _cachedUser;

  AuthService._init();

  /// Initialize – load token and user from local DB on app start
  Future<void> initialize() async {
    _cachedToken = await DatabaseHelper.instance.getSetting(_tokenKey);
    final userJson = await DatabaseHelper.instance.getSetting(_userKey);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        _cachedUser = jsonDecode(userJson) as Map<String, dynamic>;
      } catch (_) {
        _cachedUser = null;
      }
    }

    // Keep SettingsService.iduser in sync so existing API calls keep working
    if (_cachedUser != null) {
      final userId =
          _cachedUser!['iduser']?.toString() ??
          _cachedUser!['name']?.toString() ??
          '';
      if (userId.isNotEmpty) {
        SettingsService.instance.syncIduser(userId);
      }
    }
  }

  // ────────────────── Getters ──────────────────

  bool get isLoggedIn => _cachedToken != null && _cachedToken!.isNotEmpty;

  String? get token => _cachedToken;

  Map<String, dynamic>? get user => _cachedUser;

  String get iduser =>
      _cachedUser?['iduser']?.toString() ??
      _cachedUser?['name']?.toString() ??
      '';

  String get role => _cachedUser?['role']?.toString() ?? '';

  bool get isAdmin => role == 'admin';

  /// Headers including Bearer token for authenticated requests
  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_cachedToken != null) 'Authorization': 'Bearer $_cachedToken',
  };

  // ────────────────── Auth operations ──────────────────

  /// Login with [iduser] and [password] against [baseUrl]/auth/login
  /// Throws [Exception] with a human-readable message on failure.
  Future<void> login(String baseUrl, String iduser, String password) async {
    final uri = Uri.parse('$baseUrl/api/auth/login');

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'iduser': iduser, 'pass': password}),
        )
        .timeout(const Duration(seconds: 30));

    debugPrint('Login response ${response.statusCode}: ${response.body}');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] as Map<String, dynamic>?) ?? body;
      final token = data['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Invalid server response: missing token');
      }

      _cachedToken = token;
      _cachedUser = data['user'] as Map<String, dynamic>?;

      // Persist token
      await DatabaseHelper.instance.insertOrUpdateSetting(_tokenKey, token);

      // Persist user JSON
      if (_cachedUser != null) {
        await DatabaseHelper.instance.insertOrUpdateSetting(
          _userKey,
          jsonEncode(_cachedUser),
        );
      }

      // Sync iduser to SettingsService so existing code keeps working
      final userId =
          _cachedUser?['iduser']?.toString() ??
          _cachedUser?['name']?.toString() ??
          iduser;
      await SettingsService.instance.setIduser(userId);
    } else if (response.statusCode == 401 || response.statusCode == 422) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'Invalid credentials');
    } else {
      throw Exception('Server error (${response.statusCode})');
    }
  }

  /// Logout – calls API then clears local state regardless of API result
  Future<void> logout(String baseUrl) async {
    if (_cachedToken != null) {
      try {
        await http
            .post(Uri.parse('$baseUrl/auth/logout'), headers: authHeaders)
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Logout API call failed (ignored): $e');
      }
    }

    await _clearLocalSession();
  }

  /// Fetch current user from [baseUrl]/auth/me using stored token.
  /// Returns the user map or null on failure.
  Future<Map<String, dynamic>?> fetchMe(String baseUrl) async {
    if (_cachedToken == null) return null;

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/auth/me'), headers: authHeaders)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _cachedUser = data;
        await DatabaseHelper.instance.insertOrUpdateSetting(
          _userKey,
          jsonEncode(_cachedUser),
        );
        return _cachedUser;
      } else if (response.statusCode == 401) {
        // Token expired – clear session
        await _clearLocalSession();
      }
    } catch (e) {
      debugPrint('fetchMe error: $e');
    }
    return null;
  }

  // ────────────────── Internals ──────────────────

  Future<void> _clearLocalSession() async {
    _cachedToken = null;
    _cachedUser = null;
    await DatabaseHelper.instance.deleteSetting(_tokenKey);
    await DatabaseHelper.instance.deleteSetting(_userKey);
  }
}
