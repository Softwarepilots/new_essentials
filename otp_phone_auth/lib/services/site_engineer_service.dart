import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class SiteEngineerService {
  final String baseUrl = 'http://192.168.1.6:8001/api';
  final AuthService _authService = AuthService();

  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Get assigned sites
  Future<List<Map<String, dynamic>>> getAssignedSites() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/engineer/sites/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['sites'] ?? []);
      } else {
        throw Exception('Failed to load sites: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading sites: $e');
    }
  }

  // Get daily status
  Future<Map<String, dynamic>> getDailyStatus(String siteId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/engineer/daily-status/$siteId/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load daily status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading daily status: $e');
    }
  }

  // Get complaints
  Future<List<Map<String, dynamic>>> getComplaints(String siteId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/engineer/complaints/$siteId/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['complaints'] ?? []);
      } else {
        throw Exception('Failed to load complaints: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading complaints: $e');
    }
  }

  // Get project files
  Future<List<Map<String, dynamic>>> getProjectFiles(String siteId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/engineer/project-files/$siteId/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['files'] ?? []);
      } else {
        throw Exception('Failed to load project files: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading project files: $e');
    }
  }

  // Upload work activity
  Future<Map<String, dynamic>> uploadWorkActivity({
    required String siteId,
    required String activityType,
    required String imagePath,
    String? notes,
  }) async {
    try {
      final headers = await _getHeaders();
      headers.remove('Content-Type'); // Let multipart set its own content type

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/engineer/work-activity/'),
      );

      request.headers.addAll(headers);
      request.fields['site_id'] = siteId;
      request.fields['activity_type'] = activityType;
      if (notes != null) request.fields['notes'] = notes;

      // Add image file
      final file = await http.MultipartFile.fromPath('image', imagePath);
      request.files.add(file);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to upload work activity: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error uploading work activity: $e');
    }
  }

  // Upload complaint rectification
  Future<Map<String, dynamic>> uploadComplaintRectification({
    required String complaintId,
    required String imagePath,
    String? notes,
  }) async {
    try {
      final headers = await _getHeaders();
      headers.remove('Content-Type');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/engineer/complaint-action/'),
      );

      request.headers.addAll(headers);
      request.fields['complaint_id'] = complaintId;
      if (notes != null) request.fields['notes'] = notes;

      // Add image file
      final file = await http.MultipartFile.fromPath('image', imagePath);
      request.files.add(file);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to upload rectification: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error uploading rectification: $e');
    }
  }

  // Submit extra work
  Future<Map<String, dynamic>> submitExtraWork({
    required String siteId,
    required String description,
    required double amount,
    int? labourCount,
  }) async {
    try {
      final headers = await _getHeaders();
      final body = {
        'site_id': siteId,
        'description': description,
        'amount': amount,
        if (labourCount != null) 'labour_count': labourCount,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/engineer/extra-work/'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to submit extra work: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error submitting extra work: $e');
    }
  }

  // Download project file
  Future<String> downloadProjectFile(String fileUrl, String fileName) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(fileUrl),
        headers: headers,
      );

      if (response.statusCode == 200) {
        // Save file to downloads directory
        final directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        return filePath;
      } else {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error downloading file: $e');
    }
  }
}
