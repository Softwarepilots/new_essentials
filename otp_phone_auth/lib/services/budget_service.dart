import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class BudgetService {
  static final BudgetService _instance = BudgetService._internal();
  factory BudgetService() => _instance;
  BudgetService._internal();

  final _authService = AuthService();
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  /// Set budget for a site
  Future<Map<String, dynamic>?> setBudget(String siteId, double budgetAmount) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('No token found');
        return null;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/admin/sites/budget/set/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'site_id': siteId,
          'budget_amount': budgetAmount,
        }),
      );

      print('Set budget response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        print('Error setting budget: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error in setBudget: $e');
      return null;
    }
  }

  /// Get budget for a specific site
  Future<Map<String, dynamic>?> getSiteBudget(String siteId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('No token found');
        return null;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/admin/sites/$siteId/budget/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get budget response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['budget'];
      } else if (response.statusCode == 404) {
        print('No budget found for site');
        return null;
      } else {
        print('Error getting budget: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error in getSiteBudget: $e');
      return null;
    }
  }

  /// Get budget utilization for a site
  Future<Map<String, dynamic>?> getBudgetUtilization(String siteId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('No token found');
        return null;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/admin/sites/$siteId/budget/utilization/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get utilization response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Error getting utilization: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error in getBudgetUtilization: $e');
      return null;
    }
  }

  /// Get budgets for all sites
  Future<List<Map<String, dynamic>>> getAllSitesBudgets() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('No token found');
        return [];
      }

      final response = await http.get(
        Uri.parse('$baseUrl/admin/budgets/all/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get all budgets response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['budgets'] ?? []);
      } else {
        print('Error getting all budgets: ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error in getAllSitesBudgets: $e');
      return [];
    }
  }

  /// Get real-time updates
  Future<List<Map<String, dynamic>>> getRealTimeUpdates({
    String? lastSync,
    String? siteId,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('No token found');
        return [];
      }

      var url = '$baseUrl/admin/realtime-updates/';
      final queryParams = <String, String>{};
      
      if (lastSync != null) {
        queryParams['last_sync'] = lastSync;
      }
      if (siteId != null) {
        queryParams['site_id'] = siteId;
      }

      if (queryParams.isNotEmpty) {
        url += '?' + queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get updates response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['updates'] ?? []);
      } else {
        print('Error getting updates: ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error in getRealTimeUpdates: $e');
      return [];
    }
  }

  /// Get audit trail for a site
  Future<Map<String, dynamic>?> getAuditTrail(
    String siteId, {
    String? tableName,
    String? changedBy,
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('No token found');
        return null;
      }

      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };

      if (tableName != null) queryParams['table_name'] = tableName;
      if (changedBy != null) queryParams['changed_by'] = changedBy;
      if (dateFrom != null) queryParams['date_from'] = dateFrom;
      if (dateTo != null) queryParams['date_to'] = dateTo;

      final url = '$baseUrl/admin/sites/$siteId/audit-trail/?' +
          queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get audit trail response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Error getting audit trail: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error in getAuditTrail: $e');
      return null;
    }
  }
}
