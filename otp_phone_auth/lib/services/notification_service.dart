import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _authService = AuthService();
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  /// Send notification to admin about late entry
  Future<Map<String, dynamic>> sendLateEntryNotification({
    required String siteId,
    required String entryType, // 'labour', 'material', 'morning_photo', 'evening_photo'
    required String message,
    required DateTime actualTime,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/late-entry/'),
        headers: await _getHeaders(),
        body: json.encode({
          'site_id': siteId,
          'entry_type': entryType,
          'message': message,
          'actual_time': actualTime.toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return {'success': true, 'data': data};
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'error': data['error'] ?? 'Failed to send notification'};
      }
    } catch (e) {
      print('Error sending late entry notification: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get all notifications for admin
  Future<Map<String, dynamic>> getNotifications({
    bool? unreadOnly,
    int? limit,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (unreadOnly != null) queryParams['is_read'] = (!unreadOnly).toString();
      if (limit != null) queryParams['limit'] = limit.toString();

      final uri = Uri.parse('$baseUrl/notifications/').replace(queryParameters: queryParams);
      
      print('🔍 [NOTIFICATION_SERVICE] GET $uri');
      
      final response = await http.get(
        uri,
        headers: await _getHeaders(),
      );

      print('🔍 [NOTIFICATION_SERVICE] Status: ${response.statusCode}');
      print('🔍 [NOTIFICATION_SERVICE] Response: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'notifications': data['notifications'] ?? [],
          'total': data['total'] ?? 0,
          'unread_count': data['unread_count'] ?? 0,
        };
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'error': data['error'] ?? 'Failed to fetch notifications'};
      }
    } catch (e) {
      print('❌ [NOTIFICATION_SERVICE] Error fetching notifications: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Mark notification as read
  Future<Map<String, dynamic>> markAsRead(String notificationId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/$notificationId/read/'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'message': data['message']};
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'error': data['error'] ?? 'Failed to mark as read'};
      }
    } catch (e) {
      print('Error marking notification as read: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Register this device's FCM token with the backend so the server can
  /// send push notifications to the admin.
  Future<void> registerFcmToken(String token) async {
    try {
      final platform = Platform.isAndroid ? 'android' : 'ios';
      await http.post(
        Uri.parse('$baseUrl/notifications/register-device/'),
        headers: await _getHeaders(),
        body: json.encode({'fcm_token': token, 'platform': platform}),
      );
      debugPrint('[FCM] token registered with backend');
    } catch (e) {
      debugPrint('[FCM] token registration error: $e');
    }
  }

  /// Mark all notifications as read
  Future<Map<String, dynamic>> markAllAsRead() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/mark-all-read/'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'message': data['message']};
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'error': data['error'] ?? 'Failed to mark all as read'};
      }
    } catch (e) {
      print('Error marking all notifications as read: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
