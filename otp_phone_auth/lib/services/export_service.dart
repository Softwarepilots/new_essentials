import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'auth_service.dart';

class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  final _authService = AuthService();
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getToken();
    return {
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  Future<String> _getDownloadPath() async {
    try {
      if (Platform.isAndroid) {
        // For Android, try to use public Downloads directory
        final directory = Directory('/storage/emulated/0/Download');
        if (await directory.exists()) {
          return directory.path;
        }
        
        // Fallback to external storage Downloads
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final downloadsDir = Directory('${externalDir.path}/Download');
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
          return downloadsDir.path;
        }
      }
      
      // Final fallback
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    } catch (e) {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    }
  }

  Future<Map<String, dynamic>> _downloadAndSaveFile(String url, String defaultFilename) async {
    try {
      print('Starting download from: $url');
      
      // Download file
      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      print('Download response status: ${response.statusCode}');
      print('Response body length: ${response.bodyBytes.length}');

      if (response.statusCode == 200) {
        // Get download path
        final downloadPath = await _getDownloadPath();
        print('Download path: $downloadPath');
        
        // Extract filename from Content-Disposition header
        String filename = defaultFilename;
        final contentDisposition = response.headers['content-disposition'];
        if (contentDisposition != null) {
          final filenameMatch = RegExp(r'filename="(.+)"').firstMatch(contentDisposition);
          if (filenameMatch != null) {
            filename = filenameMatch.group(1)!;
          }
        }
        print('Filename: $filename');

        // Save file
        final file = File('$downloadPath/$filename');
        await file.writeAsBytes(response.bodyBytes);
        
        // Verify file was saved
        final fileExists = await file.exists();
        final fileSize = await file.length();
        print('File saved: $fileExists, Size: $fileSize bytes, Path: ${file.path}');

        if (!fileExists || fileSize == 0) {
          return {
            'success': false,
            'error': 'File was not saved correctly',
          };
        }

        return {
          'success': true,
          'message': 'File downloaded successfully',
          'filePath': file.path,
          'filename': filename,
          'fileSize': fileSize,
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to download: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('Download error: $e');
      return {
        'success': false,
        'error': 'Download error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> _openFile(String filePath) async {
    try {
      // Verify file exists before trying to open
      final file = File(filePath);
      final exists = await file.exists();
      
      print('Attempting to open file: $filePath');
      print('File exists: $exists');
      
      if (!exists) {
        return {
          'opened': false,
          'message': 'File not found at path: $filePath',
        };
      }
      
      final fileSize = await file.length();
      print('File size: $fileSize bytes');
      
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      
      print('OpenFilex result type: ${result.type}');
      print('OpenFilex result message: ${result.message}');
      
      return {
        'opened': result.type == ResultType.done,
        'message': result.message,
        'resultType': result.type.toString(),
      };
    } catch (e) {
      print('Error opening file: $e');
      return {
        'opened': false,
        'message': 'Error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> exportLabourEntries(String siteId) async {
    final result = await _downloadAndSaveFile(
      '$baseUrl/export/labour-entries/$siteId/',
      'Labour_Entries_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    
    if (result['success'] == true) {
      // Try to open the file
      final openResult = await _openFile(result['filePath']);
      result['fileOpened'] = openResult['opened'];
      result['openMessage'] = openResult['message'];
    }
    
    return result;
  }

  Future<Map<String, dynamic>> exportMaterialEntries(String siteId) async {
    final result = await _downloadAndSaveFile(
      '$baseUrl/export/material-entries/$siteId/',
      'Material_Entries_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    
    if (result['success'] == true) {
      final openResult = await _openFile(result['filePath']);
      result['fileOpened'] = openResult['opened'];
      result['openMessage'] = openResult['message'];
    }
    
    return result;
  }

  Future<Map<String, dynamic>> exportBudgetUtilization(String siteId) async {
    final result = await _downloadAndSaveFile(
      '$baseUrl/export/budget-utilization/$siteId/',
      'Budget_Utilization_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    
    if (result['success'] == true) {
      final openResult = await _openFile(result['filePath']);
      result['fileOpened'] = openResult['opened'];
      result['openMessage'] = openResult['message'];
    }
    
    return result;
  }

  Future<Map<String, dynamic>> exportBills(String siteId) async {
    final result = await _downloadAndSaveFile(
      '$baseUrl/export/bills/$siteId/',
      'Bills_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    
    if (result['success'] == true) {
      final openResult = await _openFile(result['filePath']);
      result['fileOpened'] = openResult['opened'];
      result['openMessage'] = openResult['message'];
    }
    
    return result;
  }
}
