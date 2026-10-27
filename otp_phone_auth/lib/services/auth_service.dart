import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'location_tracking_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Django backend URL
  static const String baseUrl = 'http://192.168.1.6:8001/api';
  // Login does a password hash check plus several DB round trips to Supabase,
  // which can exceed 10 s on a busy machine.
  static const Duration requestTimeout = Duration(seconds: 30);

  String? _token;
  Map<String, dynamic>? _currentUser;

  // Get stored token
  Future<String?> getToken() async {
    if (_token != null) return _token;

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    return _token;
  }

  // Get current user data
  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (_currentUser != null) return _currentUser;

    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('current_user');
    if (userJson != null) {
      _currentUser = json.decode(userJson);
    }
    return _currentUser;
  }

  // Store token and user data
  Future<void> _storeAuthData(String token, Map<String, dynamic> user) async {
    _token = token;
    _currentUser = user;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('current_user', json.encode(user));
  }

  // Clear auth data
  Future<void> clearAuthData() async {
    _token = null;
    _currentUser = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('current_user');
  }

  // Register new user
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String phone,
    required String password,
    required String fullName,
    required String role,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'username': username,
              'email': email,
              'phone': phone,
              'password': password,
              'full_name': fullName,
              'role': role,
            }),
          )
          .timeout(requestTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'],
          'user_id': data['user_id'],
          'status': data['status'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Registration failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString().contains('TimeoutException')
            ? 'Connection timeout - please check your internet'
            : 'Network error: $e',
      };
    }
  }

  // Login
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(requestTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // Store token and user data
        await _storeAuthData(data['access_token'], data['user']);

        return {'success': true, 'user': data['user']};
      } else if (response.statusCode == 403) {
        // Pending or rejected
        return {
          'success': false,
          'error': data['error'],
          'status': data['status'],
        };
      } else {
        return {'success': false, 'error': data['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString().contains('TimeoutException')
            ? 'Connection timeout - please check your internet'
            : 'Network error: $e',
      };
    }
  }

  // Check approval status
  Future<Map<String, dynamic>> checkApprovalStatus(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/status/?username=$username'),
        headers: {'Content-Type': 'application/json'},
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'status': data['status'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to check status',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // Get available roles
  Future<List<String>> getRoles() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/roles/'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<String>.from(data['roles']);
      }
      return [
        'Supervisor',
        'Site Engineer',
        'Accountant',
        'Architect',
        'Owner',
      ];
    } catch (e) {
      return [
        'Supervisor',
        'Site Engineer',
        'Accountant',
        'Architect',
        'Owner',
      ];
    }
  }

  // Update user profile
  Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String phone,
  }) async {
    try {
      final token = await getToken();
      final body = <String, dynamic>{
        if (name.isNotEmpty) 'full_name': name,
        if (phone.isNotEmpty) 'phone': phone,
      };
      final response = await http
          .put(
            Uri.parse('$baseUrl/user/profile/update/'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode(body),
          )
          .timeout(requestTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // Update locally cached user data
        if (_currentUser != null) {
          _currentUser = {
            ..._currentUser!,
            if (name.isNotEmpty) 'full_name': name,
            if (phone.isNotEmpty) 'phone': phone,
          };
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('current_user', json.encode(_currentUser));
        }
        return {'success': true};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? data['detail'] ?? 'Update failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString().contains('TimeoutException')
            ? 'Connection timeout - please check your internet'
            : 'Network error: $e',
      };
    }
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  // Logout (clear token only, no server call - one-time login)
  Future<void> logout() async {
    await LocationTrackingService.reportLogout(); // before the token is cleared
    await clearAuthData();
    // Supervisor location sharing ends with the session
    await LocationTrackingService.stop();
  }
}
