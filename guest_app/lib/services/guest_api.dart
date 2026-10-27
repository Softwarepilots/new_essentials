import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the Essential Homes backend. Guests are not logged in, so the
/// check-in endpoint is unauthenticated; the backend stores the visit and
/// pushes a notification to admin devices.
class GuestApi {
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  static Future<void> checkIn({
    required String name,
    required String phone,
    required String purpose,
    required String ref,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/notifications/guest-checkin/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'guest_name': name,
            'guest_phone': phone,
            'purpose': purpose,
            'ref': ref,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Check-in failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Active items of the catalogue the admin manages in the staff app.
  /// Each item: id, name, description, price (num or null), image_url.
  static Future<List<Map<String, dynamic>>> fetchCatalogue() async {
    final response = await http
        .get(Uri.parse('$baseUrl/catalogue/'))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Catalogue failed: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return (data['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
