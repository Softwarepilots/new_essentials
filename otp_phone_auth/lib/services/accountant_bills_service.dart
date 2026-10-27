import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class AccountantBillsService {
  static final AccountantBillsService _instance = AccountantBillsService._internal();
  factory AccountantBillsService() => _instance;
  AccountantBillsService._internal();

  final _authService = AuthService();
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getToken();
    return {
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  // ============================================
  // MATERIAL BILLS
  // ============================================
  
  Future<Map<String, dynamic>> uploadMaterialBill({
    required String siteId,
    required String billNumber,
    required String billDate,
    required String vendorName,
    required String vendorType,
    required String materialType,
    required double quantity,
    required String unit,
    required double unitPrice,
    required double totalAmount,
    double taxAmount = 0,
    double discountAmount = 0,
    required double finalAmount,
    String paymentStatus = 'PENDING',
    String? paymentMode,
    String? paymentDate,
    String? notes,
    String? description,
    required File file,
  }) async {
    try {
      final token = await _authService.getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/construction/upload-material-bill/'),
      );
      
      request.headers['Authorization'] = 'Bearer ${token ?? ''}';
      
      request.fields['site_id'] = siteId;
      request.fields['bill_number'] = billNumber;
      request.fields['bill_date'] = billDate;
      request.fields['vendor_name'] = vendorName;
      request.fields['vendor_type'] = vendorType;
      request.fields['material_type'] = materialType;
      request.fields['quantity'] = quantity.toString();
      request.fields['unit'] = unit;
      request.fields['unit_price'] = unitPrice.toString();
      request.fields['total_amount'] = totalAmount.toString();
      request.fields['tax_amount'] = taxAmount.toString();
      request.fields['discount_amount'] = discountAmount.toString();
      request.fields['final_amount'] = finalAmount.toString();
      request.fields['payment_status'] = paymentStatus;
      
      if (paymentMode != null) request.fields['payment_mode'] = paymentMode;
      if (paymentDate != null) request.fields['payment_date'] = paymentDate;
      if (notes != null && notes.isNotEmpty) request.fields['notes'] = notes;
      if (description != null && description.isNotEmpty) request.fields['description'] = description;
      
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final data = json.decode(responseData);
      
      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'],
          'bill_id': data['bill_id'],
          'file_url': data['file_url'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to upload material bill',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> getMaterialBills({
    String? siteId,
    String? vendorType,
    String? materialType,
    String? paymentStatus,
  }) async {
    try {
      String url = '$baseUrl/construction/material-bills/';
      List<String> params = [];
      
      if (siteId != null && siteId.isNotEmpty) params.add('site_id=$siteId');
      if (vendorType != null && vendorType.isNotEmpty) params.add('vendor_type=$vendorType');
      if (materialType != null && materialType.isNotEmpty) params.add('material_type=$materialType');
      if (paymentStatus != null && paymentStatus.isNotEmpty) params.add('payment_status=$paymentStatus');
      
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'bills': List<Map<String, dynamic>>.from(data['bills'] ?? []),
          'total': data['total'] ?? 0,
        };
      } else {
        return {'success': false, 'error': 'Failed to load material bills'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // VENDOR BILLS
  // ============================================
  
  Future<Map<String, dynamic>> uploadVendorBill({
    required String siteId,
    required String billNumber,
    required String billDate,
    required String vendorName,
    required String vendorType,
    required String serviceType,
    String? serviceDescription,
    required double amount,
    double taxAmount = 0,
    double discountAmount = 0,
    required double finalAmount,
    String paymentStatus = 'PENDING',
    String? paymentMode,
    String? paymentDate,
    String? notes,
    required File file,
  }) async {
    try {
      final token = await _authService.getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/construction/upload-vendor-bill/'),
      );
      
      request.headers['Authorization'] = 'Bearer ${token ?? ''}';
      
      request.fields['site_id'] = siteId;
      request.fields['bill_number'] = billNumber;
      request.fields['bill_date'] = billDate;
      request.fields['vendor_name'] = vendorName;
      request.fields['vendor_type'] = vendorType;
      request.fields['service_type'] = serviceType;
      if (serviceDescription != null && serviceDescription.isNotEmpty) {
        request.fields['service_description'] = serviceDescription;
      }
      request.fields['amount'] = amount.toString();
      request.fields['tax_amount'] = taxAmount.toString();
      request.fields['discount_amount'] = discountAmount.toString();
      request.fields['final_amount'] = finalAmount.toString();
      request.fields['payment_status'] = paymentStatus;
      
      if (paymentMode != null) request.fields['payment_mode'] = paymentMode;
      if (paymentDate != null) request.fields['payment_date'] = paymentDate;
      if (notes != null && notes.isNotEmpty) request.fields['notes'] = notes;
      
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final data = json.decode(responseData);
      
      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'],
          'bill_id': data['bill_id'],
          'file_url': data['file_url'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to upload vendor bill',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> getVendorBills({
    String? siteId,
    String? vendorType,
    String? paymentStatus,
  }) async {
    try {
      String url = '$baseUrl/construction/vendor-bills/';
      List<String> params = [];
      
      if (siteId != null && siteId.isNotEmpty) params.add('site_id=$siteId');
      if (vendorType != null && vendorType.isNotEmpty) params.add('vendor_type=$vendorType');
      if (paymentStatus != null && paymentStatus.isNotEmpty) params.add('payment_status=$paymentStatus');
      
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'bills': List<Map<String, dynamic>>.from(data['bills'] ?? []),
          'total': data['total'] ?? 0,
        };
      } else {
        return {'success': false, 'error': 'Failed to load vendor bills'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================
  // SITE AGREEMENTS
  // ============================================
  
  Future<Map<String, dynamic>> uploadSiteAgreement({
    required String siteId,
    required String agreementType,
    String? agreementNumber,
    required String agreementDate,
    required String partyName,
    required String partyType,
    required String title,
    String? description,
    double? contractValue,
    String? startDate,
    String? endDate,
    String? notes,
    required File file,
  }) async {
    try {
      final token = await _authService.getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/construction/upload-site-agreement/'),
      );
      
      request.headers['Authorization'] = 'Bearer ${token ?? ''}';
      
      request.fields['site_id'] = siteId;
      request.fields['agreement_type'] = agreementType;
      if (agreementNumber != null && agreementNumber.isNotEmpty) {
        request.fields['agreement_number'] = agreementNumber;
      }
      request.fields['agreement_date'] = agreementDate;
      request.fields['party_name'] = partyName;
      request.fields['party_type'] = partyType;
      request.fields['title'] = title;
      
      if (description != null && description.isNotEmpty) request.fields['description'] = description;
      if (contractValue != null) request.fields['contract_value'] = contractValue.toString();
      if (startDate != null) request.fields['start_date'] = startDate;
      if (endDate != null) request.fields['end_date'] = endDate;
      if (notes != null && notes.isNotEmpty) request.fields['notes'] = notes;
      
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final data = json.decode(responseData);
      
      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'],
          'agreement_id': data['agreement_id'],
          'file_url': data['file_url'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to upload site agreement',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> getSiteAgreements({
    String? siteId,
    String? agreementType,
    String? status,
  }) async {
    try {
      String url = '$baseUrl/construction/site-agreements/';
      List<String> params = [];
      
      if (siteId != null && siteId.isNotEmpty) params.add('site_id=$siteId');
      if (agreementType != null && agreementType.isNotEmpty) params.add('agreement_type=$agreementType');
      if (status != null && status.isNotEmpty) params.add('status=$status');
      
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'agreements': List<Map<String, dynamic>>.from(data['agreements'] ?? []),
          'total': data['total'] ?? 0,
        };
      } else {
        return {'success': false, 'error': 'Failed to load site agreements'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }
}
