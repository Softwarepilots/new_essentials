import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/construction_service.dart';
import '../services/auth_service.dart';
import '../utils/performance_config.dart';

class ConstructionProvider with ChangeNotifier {
  final ConstructionService _constructionService = ConstructionService();
  final SimpleCache _cache = SimpleCache();

  // Loading states
  bool _isLoadingHistory = false;
  bool _isLoadingAccountantData = false;
  bool _isLoadingAccountantPhotos = false;
  bool _isLoadingSupervisorPhotos = false;
  bool _isLoadingArchitectData = false;
  bool _isSubmitting = false;

  // Data loaded flags
  bool _historyLoaded = false;
  bool _accountantDataLoaded = false;
  bool _accountantPhotosLoaded = false;
  bool _supervisorPhotosLoaded = false;
  bool _architectDataLoaded = false;
  bool _sitesLoaded = false;
  bool _areasLoaded = false;
  
  // Track current site to detect changes
  String? _currentSiteId;

  // Data
  List<Map<String, dynamic>> _labourEntries = [];
  List<Map<String, dynamic>> _materialEntries = [];
  List<Map<String, dynamic>> _accountantLabourEntries = [];
  List<Map<String, dynamic>> _accountantMaterialEntries = [];
  List<Map<String, dynamic>> _accountantExtraCosts = [];
  List<Map<String, dynamic>> _accountantPhotos = [];
  List<Map<String, dynamic>> _supervisorPhotos = [];
  List<Map<String, dynamic>> _architectDocuments = [];
  List<Map<String, dynamic>> _architectComplaints = [];
  List<Map<String, dynamic>> _sites = [];
  List<String> _areas = [];
  Map<String, List<String>> _streetsByArea = {};

  // Error
  String? _error;

  // Getters
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isLoadingAccountantData => _isLoadingAccountantData;
  bool get isLoadingAccountantPhotos => _isLoadingAccountantPhotos;
  bool get isLoadingSupervisorPhotos => _isLoadingSupervisorPhotos;
  bool get isLoadingArchitectData => _isLoadingArchitectData;
  bool get isSubmitting => _isSubmitting;
  List<Map<String, dynamic>> get labourEntries => _labourEntries;
  List<Map<String, dynamic>> get materialEntries => _materialEntries;
  List<Map<String, dynamic>> get accountantLabourEntries => _accountantLabourEntries;
  List<Map<String, dynamic>> get accountantMaterialEntries => _accountantMaterialEntries;
  List<Map<String, dynamic>> get accountantExtraCosts => _accountantExtraCosts;
  List<Map<String, dynamic>> get accountantPhotos => _accountantPhotos;
  List<Map<String, dynamic>> get supervisorPhotos => _supervisorPhotos;
  List<Map<String, dynamic>> get architectDocuments => _architectDocuments;
  List<Map<String, dynamic>> get architectComplaints => _architectComplaints;
  List<Map<String, dynamic>> get sites => _sites;
  List<String> get areas => _areas;
  String? get error => _error;

  // Get streets for an area
  List<String> getStreetsForArea(String area) {
    return _streetsByArea[area] ?? [];
  }

  // Get areas
  Future<Map<String, dynamic>> getAreas() async {
    try {
      final areas = await _constructionService.getAreas();
      return {'success': true, 'areas': areas};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get streets by area
  Future<Map<String, dynamic>> getStreets(String area) async {
    try {
      final streets = await _constructionService.getStreets(area);
      return {'success': true, 'streets': streets};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get sites by area and street
  Future<Map<String, dynamic>> getSitesByAreaStreet(String area, String street) async {
    try {
      final sites = await _constructionService.getSites(area: area, street: street);
      return {'success': true, 'sites': sites};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Load areas
  Future<void> loadAreas() async {
    // Check cache first
    final cachedAreas = _cache.get<List<String>>(PerformanceConfig.areasCache);
    if (cachedAreas != null && cachedAreas.isNotEmpty) {
      _areas = cachedAreas;
      _areasLoaded = true;
      notifyListeners();
      return;
    }
    
    // Only load if not already loaded
    if (_areasLoaded && _areas.isNotEmpty) return;
    
    try {
      _areas = await _constructionService.getAreas();
      _areasLoaded = true;
      
      // Cache the result
      _cache.set(PerformanceConfig.areasCache, _areas, 
        duration: PerformanceConfig.longCacheDuration);
      
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Load streets for area
  Future<void> loadStreetsForArea(String area) async {
    // Check cache first
    final cacheKey = '${PerformanceConfig.streetsCache}_$area';
    final cachedStreets = _cache.get<List<String>>(cacheKey);
    if (cachedStreets != null) {
      _streetsByArea[area] = cachedStreets;
      notifyListeners();
      return;
    }
    
    // Only load if not already cached
    if (_streetsByArea.containsKey(area)) return;
    
    try {
      final streets = await _constructionService.getStreets(area);
      _streetsByArea[area] = streets;
      
      // Cache the result
      _cache.set(cacheKey, streets, 
        duration: PerformanceConfig.longCacheDuration);
      
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Load sites
  Future<void> loadSites({String? area, String? street, bool forceRefresh = false}) async {
    // Check cache first (only if no filters and not forcing refresh)
    if (!forceRefresh && area == null && street == null) {
      final cachedSites = _cache.get<List<Map<String, dynamic>>>(PerformanceConfig.sitesCache);
      if (cachedSites != null && cachedSites.isNotEmpty) {
        _sites = cachedSites;
        _sitesLoaded = true;
        notifyListeners();
        return;
      }
    }
    
    // Only load if not already loaded or force refresh
    if (_sitesLoaded && !forceRefresh) return;
    
    try {
      _sites = await _constructionService.getSites(area: area, street: street);
      _sitesLoaded = true;
      
      // Cache the result (only if no filters)
      if (area == null && street == null) {
        _cache.set(PerformanceConfig.sitesCache, _sites, 
          duration: PerformanceConfig.mediumCacheDuration);
      }
      
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Clear history cache
  void clearHistoryCache() {
    print('🗑️ [PROVIDER] Clearing history cache...');
    _historyLoaded = false;
    _currentSiteId = null;
    _labourEntries.clear();
    _materialEntries.clear();
    notifyListeners();
  }

  Future<void> loadSupervisorHistory({bool forceRefresh = false, String? siteId}) async {
    print('🔍 PROVIDER: loadSupervisorHistory called (forceRefresh: $forceRefresh, siteId: $siteId)');
    print('🔍 PROVIDER: _historyLoaded = $_historyLoaded, _currentSiteId = $_currentSiteId');
    
    // Debug: Check current user
    try {
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      print('👤 [PROVIDER] Current user: ${currentUser?['username']} (${currentUser?['full_name']}) - Role: ${currentUser?['role']}');
      print('🆔 [PROVIDER] User ID: ${currentUser?['id']}');
    } catch (e) {
      print('❌ [PROVIDER] Error getting current user: $e');
    }
    
    // Force refresh if site changed
    bool siteChanged = _currentSiteId != siteId;
    if (siteChanged) {
      print('🔍 PROVIDER: Site changed from $_currentSiteId to $siteId - forcing refresh');
      forceRefresh = true;
      _currentSiteId = siteId;
    }
    
    // Only load if not already loaded or force refresh
    if (_historyLoaded && !forceRefresh) {
      print('🔍 PROVIDER: Skipping load - already loaded and not forcing refresh');
      return;
    }
    
    _isLoadingHistory = true;
    _error = null;
    notifyListeners();

    try {
      print('🔍 PROVIDER: Calling construction service...');
      final result = await _constructionService.getSupervisorHistory(siteId: siteId);
      print('🔍 PROVIDER: Service returned: ${result.keys}');
      
      _labourEntries = List<Map<String, dynamic>>.from(result['labour_entries'] ?? []);
      _materialEntries = List<Map<String, dynamic>>.from(result['material_entries'] ?? []);
      
      print('🔍 PROVIDER: Loaded ${_labourEntries.length} labour entries');
      print('🔍 PROVIDER: Loaded ${_materialEntries.length} material entries');
      print('🏗️ PROVIDER: Site filter applied: ${result['site_filter'] ?? 'None'}');
      
      // Debug: Print all entry dates
      for (var entry in _labourEntries) {
        print('📅 [PROVIDER] Labour entry date: ${entry['entry_date']}, type: ${entry['labour_type']}');
      }
      for (var entry in _materialEntries) {
        print('📅 [PROVIDER] Material entry date: ${entry['entry_date']}, type: ${entry['material_type']}');
      }
      
      _historyLoaded = true;
    } catch (e) {
      print('❌ PROVIDER: Error loading history: $e');
      _error = e.toString();
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
      print('🔍 PROVIDER: loadSupervisorHistory completed');
    }
  }

  // Load accountant data
  Future<void> loadAccountantData({bool forceRefresh = false}) async {
    print('🔍 [ACCOUNTANT PROVIDER] loadAccountantData called (forceRefresh: $forceRefresh)');
    print('🔍 [ACCOUNTANT PROVIDER] _accountantDataLoaded = $_accountantDataLoaded');
    
    // Only load if not already loaded or force refresh
    if (_accountantDataLoaded && !forceRefresh) {
      print('🔍 [ACCOUNTANT PROVIDER] Skipping load - already loaded and not forcing refresh');
      return;
    }
    
    _isLoadingAccountantData = true;
    _error = null;
    notifyListeners();

    try {
      print('🔍 [ACCOUNTANT PROVIDER] Calling construction service...');
      final result = await _constructionService.getAccountantEntries();
      
      _accountantLabourEntries = List<Map<String, dynamic>>.from(result['labour_entries'] ?? []);
      _accountantMaterialEntries = List<Map<String, dynamic>>.from(result['material_entries'] ?? []);
      _accountantExtraCosts = List<Map<String, dynamic>>.from(result['extra_costs'] ?? []);

      print('🔍 [ACCOUNTANT PROVIDER] Loaded ${_accountantLabourEntries.length} labour entries');
      print('🔍 [ACCOUNTANT PROVIDER] Loaded ${_accountantMaterialEntries.length} material entries');
      print('🔍 [ACCOUNTANT PROVIDER] Loaded ${_accountantExtraCosts.length} extra costs');
      
      // Debug: Check for Lakshmi data specifically
      final lakshmiLabour = _accountantLabourEntries.where((entry) => 
        entry['customer_name']?.toString().toLowerCase().contains('lakshmi') == true).toList();
      final lakshmiMaterial = _accountantMaterialEntries.where((entry) => 
        entry['customer_name']?.toString().toLowerCase().contains('lakshmi') == true).toList();
      
      print('📅 [ACCOUNTANT PROVIDER] Lakshmi labour entries: ${lakshmiLabour.length}');
      print('📅 [ACCOUNTANT PROVIDER] Lakshmi material entries: ${lakshmiMaterial.length}');
      
      if (lakshmiLabour.isNotEmpty) {
        print('📝 [ACCOUNTANT PROVIDER] Sample Lakshmi labour: ${lakshmiLabour[0]['customer_name']} ${lakshmiLabour[0]['site_name']}');
      }
      
      _accountantDataLoaded = true;
    } catch (e) {
      print('❌ [ACCOUNTANT PROVIDER] Error loading data: $e');
      _error = e.toString();
    } finally {
      _isLoadingAccountantData = false;
      notifyListeners();
      print('🔍 [ACCOUNTANT PROVIDER] loadAccountantData completed');
    }
  }

  // Load architect data
  Future<void> loadArchitectData({bool forceRefresh = false, String? siteId}) async {
    print('🔍 [ARCHITECT PROVIDER] loadArchitectData called (forceRefresh: $forceRefresh, siteId: $siteId)');
    print('🔍 [ARCHITECT PROVIDER] _architectDataLoaded = $_architectDataLoaded');
    
    // Only load if not already loaded or force refresh
    if (_architectDataLoaded && !forceRefresh) {
      print('🔍 [ARCHITECT PROVIDER] Skipping load - already loaded and not forcing refresh');
      return;
    }
    
    _isLoadingArchitectData = true;
    _error = null;
    notifyListeners();

    try {
      print('🔍 [ARCHITECT PROVIDER] Calling construction service...');
      final result = await _constructionService.getArchitectHistory(siteId: siteId);
      
      _architectDocuments = List<Map<String, dynamic>>.from(result['documents'] ?? []);
      _architectComplaints = List<Map<String, dynamic>>.from(result['complaints'] ?? []);
      
      print('🔍 [ARCHITECT PROVIDER] Loaded ${_architectDocuments.length} documents');
      print('🔍 [ARCHITECT PROVIDER] Loaded ${_architectComplaints.length} complaints');
      
      if (_architectDocuments.isNotEmpty) {
        print('📝 [ARCHITECT PROVIDER] Sample document: ${_architectDocuments[0]['title']} - ${_architectDocuments[0]['document_type']}');
      }
      
      if (_architectComplaints.isNotEmpty) {
        print('📝 [ARCHITECT PROVIDER] Sample complaint: ${_architectComplaints[0]['title']} - ${_architectComplaints[0]['priority']}');
      }
      
      _architectDataLoaded = true;
    } catch (e) {
      print('❌ [ARCHITECT PROVIDER] Error loading data: $e');
      _error = e.toString();
    } finally {
      _isLoadingArchitectData = false;
      notifyListeners();
      print('🔍 [ARCHITECT PROVIDER] loadArchitectData completed');
    }
  }

  // Clear architect data cache
  void clearArchitectCache() {
    print('🗑️ [ARCHITECT PROVIDER] Clearing architect cache...');
    _architectDataLoaded = false;
    _architectDocuments.clear();
    _architectComplaints.clear();
    notifyListeners();
  }

  // Clear accountant data cache
  void clearAccountantCache() {
    print('🗑️ [ACCOUNTANT PROVIDER] Clearing accountant cache...');
    _accountantDataLoaded = false;
    _accountantPhotosLoaded = false;
    _supervisorPhotosLoaded = false;
    _accountantLabourEntries.clear();
    _accountantMaterialEntries.clear();
    _accountantExtraCosts.clear();
    _accountantPhotos.clear();
    _supervisorPhotos.clear();
    notifyListeners();
  }

  // Load accountant photos
  Future<void> loadAccountantPhotos({
    bool forceRefresh = false,
    String? siteId,
    String? updateType,
    String? dateFrom,
    String? dateTo,
  }) async {
    print('🔍 [ACCOUNTANT PHOTOS PROVIDER] loadAccountantPhotos called (forceRefresh: $forceRefresh)');
    print('🔍 [ACCOUNTANT PHOTOS PROVIDER] _accountantPhotosLoaded = $_accountantPhotosLoaded');
    
    // Only load if not already loaded or force refresh
    if (_accountantPhotosLoaded && !forceRefresh) {
      print('🔍 [ACCOUNTANT PHOTOS PROVIDER] Skipping load - already loaded and not forcing refresh');
      return;
    }
    
    _isLoadingAccountantPhotos = true;
    _error = null;
    notifyListeners();

    try {
      print('🔍 [ACCOUNTANT PHOTOS PROVIDER] Calling construction service...');
      final result = await _constructionService.getAccountantPhotos(
        siteId: siteId,
        updateType: updateType,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      
      _accountantPhotos = List<Map<String, dynamic>>.from(result['photos'] ?? []);
      
      print('🔍 [ACCOUNTANT PHOTOS PROVIDER] Loaded ${_accountantPhotos.length} photos');
      
      // Debug: Check photo types
      final morningPhotos = _accountantPhotos.where((photo) => 
        photo['update_type']?.toString() == 'STARTED').toList();
      final eveningPhotos = _accountantPhotos.where((photo) => 
        photo['update_type']?.toString() == 'FINISHED').toList();
      
      print('📸 [ACCOUNTANT PHOTOS PROVIDER] Morning photos: ${morningPhotos.length}');
      print('📸 [ACCOUNTANT PHOTOS PROVIDER] Evening photos: ${eveningPhotos.length}');
      
      if (_accountantPhotos.isNotEmpty) {
        print('📝 [ACCOUNTANT PHOTOS PROVIDER] Sample photo: ${_accountantPhotos[0]['full_site_name']} - ${_accountantPhotos[0]['update_type']}');
      }
      
      _accountantPhotosLoaded = true;
    } catch (e) {
      print('❌ [ACCOUNTANT PHOTOS PROVIDER] Error loading photos: $e');
      _error = e.toString();
    } finally {
      _isLoadingAccountantPhotos = false;
      notifyListeners();
      print('🔍 [ACCOUNTANT PHOTOS PROVIDER] loadAccountantPhotos completed');
    }
  }

  // Load supervisor photos for accountant
  Future<void> loadSupervisorPhotos({
    bool forceRefresh = false,
    String? siteId,
  }) async {
    print('🔍 [SUPERVISOR PHOTOS PROVIDER] loadSupervisorPhotos called (forceRefresh: $forceRefresh, siteId: $siteId)');
    print('🔍 [SUPERVISOR PHOTOS PROVIDER] _supervisorPhotosLoaded = $_supervisorPhotosLoaded');
    
    // Only load if not already loaded or force refresh
    if (_supervisorPhotosLoaded && !forceRefresh) {
      print('🔍 [SUPERVISOR PHOTOS PROVIDER] Skipping load - already loaded and not forcing refresh');
      return;
    }
    
    _isLoadingSupervisorPhotos = true;
    _error = null;
    notifyListeners();

    try {
      print('🔍 [SUPERVISOR PHOTOS PROVIDER] Fetching from API...');
      final authService = AuthService();
      final token = await authService.getToken();
      
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/construction/supervisor-photos-for-accountant/?site_id=$siteId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        _supervisorPhotos = List<Map<String, dynamic>>.from(result['photos'] ?? []);
        
        print('🔍 [SUPERVISOR PHOTOS PROVIDER] Loaded ${_supervisorPhotos.length} photos');
        
        // Debug: Check photo types
        final morningPhotos = _supervisorPhotos.where((photo) => 
          (photo['time_of_day'] as String? ?? '').toLowerCase() == 'morning').toList();
        final eveningPhotos = _supervisorPhotos.where((photo) => 
          (photo['time_of_day'] as String? ?? '').toLowerCase() == 'evening').toList();
        
        print('📸 [SUPERVISOR PHOTOS PROVIDER] Morning photos: ${morningPhotos.length}');
        print('📸 [SUPERVISOR PHOTOS PROVIDER] Evening photos: ${eveningPhotos.length}');
        
        if (_supervisorPhotos.isNotEmpty) {
          print('📝 [SUPERVISOR PHOTOS PROVIDER] Sample photo: ${_supervisorPhotos[0]['supervisor_name']} - ${_supervisorPhotos[0]['time_of_day']}');
        }
        
        _supervisorPhotosLoaded = true;
      } else {
        throw Exception('Failed to load photos: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [SUPERVISOR PHOTOS PROVIDER] Error loading photos: $e');
      _error = e.toString();
    } finally {
      _isLoadingSupervisorPhotos = false;
      notifyListeners();
      print('🔍 [SUPERVISOR PHOTOS PROVIDER] loadSupervisorPhotos completed');
    }
  }

  // Submit labour count
  Future<Map<String, dynamic>> submitLabourCount({
    required String siteId,
    required int labourCount,
    String? labourType,
    String? notes,
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _constructionService.submitLabourCount(
        siteId: siteId,
        labourCount: labourCount,
        labourType: labourType,
        notes: notes,
      );

      if (result['success'] == true) {
        // Reload history after successful submission (force refresh)
        await loadSupervisorHistory(forceRefresh: true);
      }

      return result;
    } catch (e) {
      _error = e.toString();
      return {'success': false, 'error': e.toString()};
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  // Submit material balance
  Future<Map<String, dynamic>> submitMaterialBalance({
    required String siteId,
    required List<Map<String, dynamic>> materials,
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _constructionService.submitMaterialBalance(
        siteId: siteId,
        materials: materials,
      );

      if (result['success'] == true) {
        // Reload history after successful submission (force refresh)
        await loadSupervisorHistory(forceRefresh: true);
      }

      return result;
    } catch (e) {
      _error = e.toString();
      return {'success': false, 'error': e.toString()};
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Clear all data (on logout)
  void clearData() {
    _labourEntries = [];
    _materialEntries = [];
    _accountantLabourEntries = [];
    _accountantMaterialEntries = [];
    _accountantExtraCosts = [];
    _accountantPhotos = [];
    _supervisorPhotos = [];
    _architectDocuments = [];
    _architectComplaints = [];
    _sites = [];
    _areas = [];
    _streetsByArea = {};
    _error = null;
    _historyLoaded = false;
    _accountantDataLoaded = false;
    _accountantPhotosLoaded = false;
    _supervisorPhotosLoaded = false;
    _architectDataLoaded = false;
    _sitesLoaded = false;
    _areasLoaded = false;
    
    // Clear cache
    _cache.clear();
    
    notifyListeners();
  }

  // Add client requirement
  Future<bool> addClientRequirement(String siteId, String description, double amount) async {
    try {
      _isSubmitting = true;
      notifyListeners();

      final result = await _constructionService.addClientRequirement(siteId, description, amount);
      
      _isSubmitting = false;
      notifyListeners();
      
      return result;
    } catch (e) {
      _error = e.toString();
      _isSubmitting = false;
      notifyListeners();
      return false;
    }
  }
}
