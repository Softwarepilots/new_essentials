import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class MaterialService {
  static final MaterialService _instance = MaterialService._internal();
  factory MaterialService() => _instance;
  MaterialService._internal();

  final _authService = AuthService();
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  // ============================================
  // SITE ENGINEER: Add/Update Material Stock
  // ============================================
  
  Future<Map<String, dynamic>> addMaterialStock({
    required String siteId,
    required String materialType,
    required double quantity,
    required String unit,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/material/add-stock/'),
        headers: await _getHeaders(),
        body: json.encode({
          'site_id': siteId,
          'material_type': materialType,
          'quantity': quantity,
          'unit': unit,
          'notes': notes ?? '',
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'],
          'stock_id': data['stock_id'],
        };
      } else {
        return {
          'success': false,
          'error': data['message'] ?? 'Failed to add stock',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET MATERIAL STOCK (Initial stock added by Site Engineer)
  // ============================================
  
  Future<Map<String, dynamic>> getMaterialStock(String siteId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/material/stock/?site_id=$siteId'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'stock': List<Map<String, dynamic>>.from(data['stock'] ?? []),
        };
      } else {
        return {'success': false, 'error': 'Failed to load stock'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET MATERIAL BALANCE (Stock - Usage)
  // ============================================
  
  Future<Map<String, dynamic>> getMaterialBalance(String siteId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/material/balance/?site_id=$siteId'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'balance': List<Map<String, dynamic>>.from(data['balance'] ?? []),
        };
      } else {
        return {'success': false, 'error': 'Failed to load balance'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // SUPERVISOR: Record Material Usage
  // ============================================
  
  Future<Map<String, dynamic>> recordMaterialUsage({
    required String siteId,
    required String materialType,
    required double quantityUsed,
    required String unit,
    String? usageDate,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/material/record-usage/'),
        headers: await _getHeaders(),
        body: json.encode({
          'site_id': siteId,
          'material_type': materialType,
          'quantity_used': quantityUsed,
          'unit': unit,
          'usage_date': usageDate ?? DateTime.now().toIso8601String().split('T')[0],
          'notes': notes ?? '',
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'],
          'usage_id': data['usage_id'],
          'warning': data['warning'] ?? false,
        };
      } else {
        return {
          'success': false,
          'error': data['message'] ?? 'Failed to record usage',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET MATERIAL USAGE HISTORY
  // ============================================
  
  Future<Map<String, dynamic>> getMaterialUsageHistory({
    required String siteId,
    String? materialType,
  }) async {
    try {
      String url = '$baseUrl/material/usage-history/?site_id=$siteId';
      if (materialType != null && materialType.isNotEmpty) {
        url += '&material_type=$materialType';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'usage_history': List<Map<String, dynamic>>.from(data['usage_history'] ?? []),
        };
      } else {
        return {'success': false, 'error': 'Failed to load usage history'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET TODAY'S MATERIAL USAGE (for Site Engineer)
  // ============================================
  
  Future<Map<String, dynamic>> getTodayMaterialUsage(String siteId) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final response = await http.get(
        Uri.parse('$baseUrl/material/usage-history/?site_id=$siteId'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final allUsage = List<Map<String, dynamic>>.from(data['usage_history'] ?? []);
        
        // Filter for today's usage
        final todayUsage = allUsage.where((usage) {
          final usageDate = usage['usage_date']?.toString().split('T')[0];
          return usageDate == today;
        }).toList();

        // Group by material type and sum quantities
        final Map<String, double> todayUsageByMaterial = {};
        final Map<String, String> unitByMaterial = {};
        
        for (var usage in todayUsage) {
          final materialType = usage['material_type'] as String;
          final quantity = (usage['quantity_used'] as num).toDouble();
          final unit = usage['unit'] as String;
          
          todayUsageByMaterial[materialType] = 
              (todayUsageByMaterial[materialType] ?? 0) + quantity;
          unitByMaterial[materialType] = unit;
        }

        return {
          'success': true,
          'today_usage': todayUsage,
          'today_usage_summary': todayUsageByMaterial.entries.map((e) => {
            'material_type': e.key,
            'total_used_today': e.value,
            'unit': unitByMaterial[e.key],
          }).toList(),
        };
      } else {
        return {'success': false, 'error': 'Failed to load today\'s usage'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET LOW STOCK ALERTS
  // ============================================
  
  Future<Map<String, dynamic>> getLowStockAlerts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/material/low-stock-alerts/'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'alerts': List<Map<String, dynamic>>.from(data['alerts'] ?? []),
          'count': data['count'] ?? 0,
        };
      } else {
        return {'success': false, 'error': 'Failed to load alerts'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // GET MATERIAL TYPES
  // ============================================
  
  Future<Map<String, dynamic>> getMaterialTypes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/material/types/'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'material_types': List<String>.from(data['material_types'] ?? []),
        };
      } else {
        return {'success': false, 'error': 'Failed to load material types'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }
}
