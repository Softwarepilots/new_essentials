import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// A photo picked on the device, waiting to be uploaded.
class CatalogueImageUpload {
  final Uint8List bytes;
  final String name;
  const CatalogueImageUpload(this.bytes, this.name);
}

/// Admin management of the guest catalogue (shown in the guest app after
/// check-in). Backend: api/views_catalogue.py
class CatalogueService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeader() async {
    final token = await _authService.getToken();
    return {'Authorization': 'Bearer ${token ?? ''}'};
  }

  Future<List<Map<String, dynamic>>> getItems() async {
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/admin/catalogue/'),
      headers: await _authHeader(),
    );
    final data = _decode(response);
    return List<Map<String, dynamic>>.from(
      (data['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  /// Creates an item, or updates [id] when given.
  ///
  /// Photos end up as [keptImageUrls] (existing image URLs, in order) followed
  /// by [newImages]; the first one is the cover. Max 10 per item.
  Future<Map<String, dynamic>> saveItem({
    String? id,
    required String name,
    required String description,
    required String price,
    required bool isActive,
    List<String> keptImageUrls = const [],
    List<CatalogueImageUpload> newImages = const [],
  }) async {
    final request = http.MultipartRequest(
      id == null ? 'POST' : 'PUT',
      Uri.parse(
        id == null
            ? '${AuthService.baseUrl}/admin/catalogue/'
            : '${AuthService.baseUrl}/admin/catalogue/$id/',
      ),
    );
    request.headers.addAll(await _authHeader());
    request.fields['name'] = name;
    request.fields['description'] = description;
    request.fields['price'] = price;
    request.fields['is_active'] = isActive.toString();
    if (id != null) request.fields['keep_images'] = json.encode(keptImageUrls);
    for (final image in newImages) {
      request.files.add(
        http.MultipartFile.fromBytes('images', image.bytes, filename: image.name),
      );
    }

    final response = await http.Response.fromStream(await request.send());
    final data = _decode(response);
    return Map<String, dynamic>.from(data['item'] as Map);
  }

  Future<void> setActive(String id, bool isActive) async {
    final request = http.MultipartRequest(
      'PATCH',
      Uri.parse('${AuthService.baseUrl}/admin/catalogue/$id/'),
    );
    request.headers.addAll(await _authHeader());
    request.fields['is_active'] = isActive.toString();
    _decode(await http.Response.fromStream(await request.send()));
  }

  Future<void> deleteItem(String id) async {
    final response = await http.delete(
      Uri.parse('${AuthService.baseUrl}/admin/catalogue/$id/'),
      headers: await _authHeader(),
    );
    _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Server error (${response.statusCode})');
    }
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? data['detail'] ?? 'Request failed');
    }
    return data;
  }
}
