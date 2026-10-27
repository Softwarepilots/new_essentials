import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class DocumentService {
  static final DocumentService _instance = DocumentService._internal();
  factory DocumentService() => _instance;
  DocumentService._internal();

  final _authService = AuthService();
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getToken();
    return {
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  // ============================================
  // SITE ENGINEER: Upload Document
  // ============================================
  
  Future<Map<String, dynamic>> uploadSiteEngineerDocument({
    required String siteId,
    required String documentType,
    required String title,
    String? description,
    required File file,
  }) async {
    try {
      final token = await _authService.getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/construction/upload-site-engineer-document/'),
      );
      
      request.headers['Authorization'] = 'Bearer ${token ?? ''}';
      
      request.fields['site_id'] = siteId;
      request.fields['document_type'] = documentType;
      request.fields['title'] = title;
      if (description != null && description.isNotEmpty) {
        request.fields['description'] = description;
      }
      
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final data = json.decode(responseData);
      
      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'],
          'document_id': data['document_id'],
          'file_url': data['file_url'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to upload document',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET SITE ENGINEER DOCUMENTS
  // ============================================
  
  Future<Map<String, dynamic>> getSiteEngineerDocuments({
    String? siteId,
    String? documentType,
  }) async {
    try {
      String url = '$baseUrl/construction/site-engineer-documents/';
      List<String> params = [];
      
      if (siteId != null && siteId.isNotEmpty) {
        params.add('site_id=$siteId');
      }
      if (documentType != null && documentType.isNotEmpty) {
        params.add('document_type=$documentType');
      }
      
      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'documents': List<Map<String, dynamic>>.from(data['documents'] ?? []),
          'total': data['total_documents'] ?? 0,
        };
      } else {
        return {'success': false, 'error': 'Failed to load documents'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET ARCHITECT DOCUMENTS
  // ============================================
  
  Future<Map<String, dynamic>> getArchitectDocuments({
    String? siteId,
    String? documentType,
  }) async {
    try {
      String url = '$baseUrl/construction/architect-documents/';
      List<String> params = [];
      
      if (siteId != null && siteId.isNotEmpty) {
        params.add('site_id=$siteId');
      }
      if (documentType != null && documentType.isNotEmpty) {
        params.add('document_type=$documentType');
      }
      
      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'documents': List<Map<String, dynamic>>.from(data['documents'] ?? []),
          'total': data['total_documents'] ?? 0,
        };
      } else {
        return {'success': false, 'error': 'Failed to load documents'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET ALL DOCUMENTS (for Accountant)
  // ============================================
  
  Future<Map<String, dynamic>> getAllDocuments({
    required String siteId,
    String role = 'all', // 'site_engineer', 'architect', 'all'
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/construction/all-documents/?site_id=$siteId&role=$role'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'site_engineer_documents': List<Map<String, dynamic>>.from(data['site_engineer_documents'] ?? []),
          'architect_documents': List<Map<String, dynamic>>.from(data['architect_documents'] ?? []),
          'total': data['total_documents'] ?? 0,
        };
      } else {
        return {'success': false, 'error': 'Failed to load documents'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }
}
