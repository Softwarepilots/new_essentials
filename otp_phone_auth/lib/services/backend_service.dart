import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackendService {
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();

  // Django backend URL - change this to your computer's IP for physical device
  // For emulator: http://10.0.2.2:8000/api
  // For physical device: http://YOUR_COMPUTER_IP:8000/api
  static const String baseUrl = 'http://192.168.1.6:8001/api';
  
  String? _jwtToken;
  
  // Get stored JWT token
  Future<String?> getJwtToken() async {
    if (_jwtToken != null) return _jwtToken;
    
    final prefs = await SharedPreferences.getInstance();
    _jwtToken = prefs.getString('jwt_token');
    return _jwtToken;
  }
  
  // Store JWT token
  Future<void> _storeJwtToken(String token) async {
    _jwtToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }
  
  // Clear JWT token
  Future<void> clearJwtToken() async {
    _jwtToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }
  
  // Sign in with Firebase token and get JWT
  Future<Map<String, dynamic>?> signIn() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No Firebase user found');
        return null;
      }
      
      // Get Firebase ID token
      final firebaseToken = await user.getIdToken();
      if (firebaseToken == null) {
        print('Could not get Firebase ID token');
        return null;
      }
      
      print('Signing in to Django backend...');
      print('Firebase token: ${firebaseToken.substring(0, 20)}...');
      
      final response = await http.post(
        Uri.parse('$baseUrl/auth/signin/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'firebase_id_token': firebaseToken,
        }),
      );
      
      print('Backend response status: ${response.statusCode}');
      print('Backend response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Store JWT token
        if (data['access_token'] != null) {
          await _storeJwtToken(data['access_token']);
          print('✅ JWT token stored successfully');
        }
        
        return data;
      } else {
        print('❌ Backend signin failed: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Error signing in to backend: $e');
      return null;
    }
  }
  
  // Get user profile from backend
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final token = await getJwtToken();
      if (token == null) {
        print('No JWT token found, signing in...');
        final signInResult = await signIn();
        if (signInResult == null) return null;
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/user/profile/'),
        headers: {
          'Authorization': 'Bearer ${await getJwtToken()}',
          'Content-Type': 'application/json',
        },
      );
      
      print('Get profile response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        // Token expired, try to sign in again
        print('Token expired, signing in again...');
        await clearJwtToken();
        final signInResult = await signIn();
        if (signInResult != null) {
          return getUserProfile(); // Retry
        }
      }
      
      print('❌ Failed to get profile: ${response.body}');
      return null;
    } catch (e) {
      print('❌ Error getting profile: $e');
      return null;
    }
  }
  
  // Update user profile
  Future<bool> updateProfile({
    String? fullName,
    String? phone,
  }) async {
    try {
      final token = await getJwtToken();
      if (token == null) {
        print('No JWT token found');
        return false;
      }
      
      final Map<String, dynamic> data = {};
      if (fullName != null) data['full_name'] = fullName;
      if (phone != null) data['phone'] = phone;
      
      if (data.isEmpty) {
        print('No data to update');
        return false;
      }
      
      print('Updating profile: $data');
      
      final response = await http.put(
        Uri.parse('$baseUrl/user/profile/update/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );
      
      print('Update profile response: ${response.statusCode}');
      print('Update profile body: ${response.body}');
      
      if (response.statusCode == 200) {
        print('✅ Profile updated successfully');
        return true;
      } else if (response.statusCode == 401) {
        // Token expired
        print('Token expired, please sign in again');
        await clearJwtToken();
        return false;
      }
      
      print('❌ Failed to update profile: ${response.body}');
      return false;
    } catch (e) {
      print('❌ Error updating profile: $e');
      return false;
    }
  }
  
  // Test backend connection
  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      print('Backend health check: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Backend connection failed: $e');
      return false;
    }
  }
}
