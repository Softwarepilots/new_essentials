import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class BudgetManagementService {
  static final BudgetManagementService _instance = BudgetManagementService._internal();
  factory BudgetManagementService() => _instance;
  BudgetManagementService._internal();

  final _authService = AuthService();
  static const String baseUrl = 'http://187.127.164.22/api';

  // Cache for global labour rates — loaded once, cleared when admin updates a rate
  static List<Map<String, dynamic>>? _globalRatesCache;

  /// Allocate budget for a site
  Future<Map<String, dynamic>?> allocateBudget({
    required String siteId,
    required double totalBudget,
    double? materialBudget,
    double? labourBudget,
    double? otherBudget,
    double? clientBalance,
    String? notes,
  }) async {
    try {
      print('🔄 [SERVICE] allocateBudget called');
      print('   siteId: $siteId');
      print('   totalBudget: $totalBudget');
      print('   clientBalance: $clientBalance');
      
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ [SERVICE] No auth token');
        return null;
      }

      final body = {
        'site_id': siteId,
        'total_budget': totalBudget,
        if (materialBudget != null) 'material_budget': materialBudget,
        if (labourBudget != null) 'labour_budget': labourBudget,
        if (otherBudget != null) 'other_budget': otherBudget,
        if (clientBalance != null) 'client_balance': clientBalance,
        if (notes != null) 'notes': notes,
      };
      
      print('📤 [SERVICE] Request body: $body');

      // Use the smart endpoint that handles both create and update
      final response = await http.post(
        Uri.parse('$baseUrl/budget/allocate-or-update/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );

      print('📡 [SERVICE] Response status: ${response.statusCode}');
      print('📦 [SERVICE] Response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ [SERVICE] Budget allocated/updated successfully');
        return json.decode(response.body);
      }
      
      print('❌ [SERVICE] Failed with status ${response.statusCode}');
      return null;
    } catch (e) {
      print('❌ [SERVICE] Exception: $e');
      return null;
    }
  }

  /// Get budget allocation for a site
  Future<Map<String, dynamic>?> getBudgetAllocation(String siteId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$baseUrl/budget/allocation/$siteId/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['budget'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Set labour rate for a site
  Future<Map<String, dynamic>?> setLabourRate({
    required String siteId,
    required String labourType,
    required double dailyRate,
    String? effectiveFrom,
    String? notes,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('$baseUrl/budget/labour-rate/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'site_id': siteId,
          'labour_type': labourType,
          'daily_rate': dailyRate,
          if (effectiveFrom != null) 'effective_from': effectiveFrom,
          if (notes != null) 'notes': notes,
        }),
      );

      if (response.statusCode == 201) {
        clearRatesCache(); // Force fresh fetch next time rates are needed
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get labour rates. For 'global', returns cached result after first load.
  Future<List<Map<String, dynamic>>> getLabourRates(String siteId) async {
    // Return cache for global rates — avoids repeated API calls on every sheet open
    if (siteId == 'global' && _globalRatesCache != null) {
      return _globalRatesCache!;
    }
    try {
      final token = await _authService.getToken();
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('$baseUrl/budget/labour-rates/$siteId/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rates = List<Map<String, dynamic>>.from(data['rates'] ?? []);
        if (siteId == 'global') _globalRatesCache = rates;
        return rates;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Clears the global rates cache — call after admin updates a rate
  static void clearRatesCache() => _globalRatesCache = null;

  /// Delete a labour type (only custom types, not canonical defaults)
  Future<Map<String, dynamic>> deleteLabourType(String labourType) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/budget/delete-labour-type/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'labour_type': labourType,
        }),
      );

      if (response.statusCode == 200) {
        clearRatesCache(); // Force fresh fetch next time
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Labour type deleted successfully',
        };
      }
      
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Failed to delete labour type',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get budget utilization for a site
  Future<Map<String, dynamic>?> getBudgetUtilization(String siteId, {String? filterDate, String? filterType}) async {
    try {
      final token = await _authService.getToken();
      if (token == null) return null;

      // Build URL with optional filters
      String url = '$baseUrl/budget/utilization/$siteId/';
      List<String> params = [];
      
      if (filterDate != null && filterDate.isNotEmpty) {
        params.add('date=$filterDate');
      }
      
      if (filterType != null && filterType.isNotEmpty) {
        params.add('filter=$filterType');
      }
      
      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get labour cost details for a site
  Future<List<Map<String, dynamic>>> getLabourCostDetails(String siteId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('$baseUrl/budget/labour-costs/$siteId/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['costs'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get client requirements for a site
  Future<List<Map<String, dynamic>>> getClientRequirements(String siteId) async {
    try {
      print('🔍 Fetching client requirements for site: $siteId');
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ No auth token available');
        return [];
      }

      final url = '$baseUrl/admin/client-requirements/?site_id=$siteId';
      print('🌐 API URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('📡 Response status: ${response.statusCode}');
      print('📦 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final requirements = List<Map<String, dynamic>>.from(data['requirements'] ?? []);
        print('✅ Found ${requirements.length} requirements');
        return requirements;
      }
      print('❌ Failed with status: ${response.statusCode}');
      return [];
    } catch (e) {
      print('❌ Error fetching client requirements: $e');
      return [];
    }
  }

  /// Get local labour rates for a specific area
  Future<Map<String, dynamic>> getLocalLabourRates(String area) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/budget/local-labour-rates/$area/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'rates': List<Map<String, dynamic>>.from(data['rates'] ?? []),
        };
      }
      
      return {
        'success': false,
        'error': 'Failed to load local rates',
      };
    } catch (e) {
      print('❌ Error fetching local labour rates: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Set local labour rate for a specific area
  Future<Map<String, dynamic>> setLocalLabourRate({
    required String area,
    required String labourType,
    required double rate,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/budget/local-labour-rate/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'area': area,
          'labour_type': labourType,
          'daily_rate': rate,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Local rate set successfully',
        };
      }
      
      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Failed to set local rate',
      };
    } catch (e) {
      print('❌ Error setting local labour rate: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Add material cost entry
  Future<Map<String, dynamic>> addMaterialCost({
    required String siteId,
    required String materialType,
    required double quantity,
    required String unit,
    required double unitCost,
    required double totalCost,
    String? entryDate,
    String? notes,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/budget/add-material-cost/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'site_id': siteId,
          'material_type': materialType,
          'quantity': quantity,
          'unit': unit,
          'unit_cost': unitCost,
          'total_cost': totalCost,
          'entry_date': entryDate ?? DateTime.now().toIso8601String().split('T')[0],
          'notes': notes ?? '',
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Material cost added successfully',
          'cost_id': data['cost_id'],
        };
      }

      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Failed to add material cost',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Add other cost entry
  Future<Map<String, dynamic>> addOtherCost({
    required String siteId,
    required String costType,
    String? description,
    required double amount,
    String? entryDate,
    String? notes,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/budget/add-other-cost/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'site_id': siteId,
          'cost_type': costType,
          'description': description ?? '',
          'amount': amount,
          'entry_date': entryDate ?? DateTime.now().toIso8601String().split('T')[0],
          'notes': notes ?? '',
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Other cost added successfully',
          'bill_id': data['bill_id'],
        };
      }

      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Failed to add other cost',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Record phase payment from client
  Future<Map<String, dynamic>> recordPhasePayment({
    required String siteId,
    required int phaseNumber,
    required double phaseAmount,
    String? paymentDate,
    String? notes,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/budget/record-phase-payment/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'site_id': siteId,
          'phase_number': phaseNumber,
          'phase_amount': phaseAmount,
          'payment_date': paymentDate ?? DateTime.now().toIso8601String().split('T')[0],
          'notes': notes ?? '',
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Phase payment recorded successfully',
          'payment_id': data['payment_id'],
          'new_balance': data['new_balance'],
        };
      }

      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Failed to record phase payment',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get phase payments for a site
  Future<Map<String, dynamic>?> getPhasePayments(String siteId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$baseUrl/budget/phase-payments/$siteId/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update phase payment amount
  Future<Map<String, dynamic>> updatePhasePayment({
    required String siteId,
    required int phaseNumber,
    required double phaseAmount,
    String? paymentDate,
    String? notes,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http.put(
        Uri.parse('$baseUrl/budget/update-phase-payment/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'site_id': siteId,
          'phase_number': phaseNumber,
          'phase_amount': phaseAmount,
          'payment_date': paymentDate,
          'notes': notes,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Phase payment updated successfully',
          'new_balance': data['new_balance'],
        };
      }

      final error = json.decode(response.body);
      return {
        'success': false,
        'error': error['error'] ?? 'Failed to update phase payment',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get all materials from material_master table
  Future<List<Map<String, dynamic>>> getMaterials() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ [MATERIALS] No auth token');
        return [];
      }

      print('🔍 [MATERIALS] Fetching from: $baseUrl/construction/materials/');
      final response = await http.get(
        Uri.parse('$baseUrl/construction/materials/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('📡 [MATERIALS] Response status: ${response.statusCode}');
      print('📦 [MATERIALS] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final materials = List<Map<String, dynamic>>.from(data['materials'] ?? []);
        print('✅ [MATERIALS] Loaded ${materials.length} materials');
        return materials;
      }
      
      print('❌ [MATERIALS] Failed with status ${response.statusCode}');
      return [];
    } catch (e) {
      print('❌ [MATERIALS] Exception: $e');
      return [];
    }
  }
}
