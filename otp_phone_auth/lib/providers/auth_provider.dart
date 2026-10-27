import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  
  Map<String, dynamic>? _currentUser;
  bool _isLoading = false;
  String? _error;

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  
  // Convenience getters
  String? get userId => _currentUser?['id'];
  String? get username => _currentUser?['username'];
  String? get email => _currentUser?['email'];
  String? get fullName => _currentUser?['full_name'];
  String? get role => _currentUser?['role'];
  String? get phone => _currentUser?['phone'];
  bool? get isApproved => _currentUser?['is_approved'];

  // Initialize - check if user is already logged in
  Future<void> initialize() async {
    _isLoading = true;
    // Defer first notification — initialize() is called from initState
    // which runs during build; calling notifyListeners() synchronously here
    // triggers "setState() called during build".
    Future.microtask(notifyListeners);

    try {
      final userData = await _authService.getCurrentUser();
      if (userData != null) {
        _currentUser = userData;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Login
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _authService.login(
        username: username,
        password: password,
      );

      if (result['success'] == true) {
        _currentUser = result['user'];
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = result['error'];
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Register
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String phone,
    required String password,
    required String fullName,
    required String role,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _authService.register(
        username: username,
        email: email,
        phone: phone,
        password: password,
        fullName: fullName,
        role: role,
      );

      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return {'success': false, 'error': e.toString()};
    }
  }

  // Logout
  Future<void> logout() async {
    await _authService.logout();
    _currentUser = null;
    _error = null;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
