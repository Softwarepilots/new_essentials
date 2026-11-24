import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/construction_service.dart';
import '../services/document_service.dart';
import '../services/labor_mismatch_service.dart';
import '../services/cache_service.dart';
import '../providers/construction_provider.dart';
import '../providers/change_request_provider.dart';
import '../utils/app_colors.dart';
import 'login_screen.dart';

class AccountantEntryScreen extends StatefulWidget {
  const AccountantEntryScreen({super.key});

  @override
  State<AccountantEntryScreen> createState() => _AccountantEntryScreenState();
}

class _AccountantEntryScreenState extends State<AccountantEntryScreen> {
  final _authService = AuthService();
  final _mismatchService = LaborMismatchService();
  
  Map<String, dynamic>? _currentUser;
  
  // Dropdown state
  String? _selectedArea;
  String? _selectedStreet;
  String? _selectedSite;
  
  // Data lists
  List<String> _areas = [];
  List<String> _streets = [];
  List<Map<String, dynamic>> _sites = [];
  
  // Loading states
  bool _isLoadingAreas = false;
  bool _isLoadingStreets = false;
  bool _isLoadingSites = false;
  
  // Mismatch detection
  Map<String, dynamic> _mismatchData = {};
  int _totalMismatches = 0;
  
  // Filter chip state (replaces tab controllers)
  String _selectedRole = 'Supervisor'; // Supervisor | Site Engineer | Architect
  String _selectedSupervisorTab = 'Labour'; // Labour | Materials
  String _selectedSiteEngineerTab = 'Photos'; // Photos | Labor | Materials | Documents
  final Set<String> _expandedDates = {};
  
  // Background refresh timers for site-specific data
  Timer? _labourRefreshTimer;
  Timer? _materialsRefreshTimer;
  Timer? _requestsRefreshTimer;
  Timer? _photosRefreshTimer;
  
  // Site-specific data cache (role + tab combinations)
  final Map<String, List<Map<String, dynamic>>> _siteDataCache = {};


  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAreas();
  }
  
  @override
  void dispose() {
    _labourRefreshTimer?.cancel();
    _materialsRefreshTimer?.cancel();
    _requestsRefreshTimer?.cancel();
    _photosRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = await _authService.getCurrentUser();
    setState(() => _currentUser = user);
  }

  Future<void> _loadAreas() async {
    // Load from cache FIRST (instant - 0ms)
    final cachedAreas = await CacheService.loadAreas();
    if (cachedAreas != null && cachedAreas.isNotEmpty) {
      setState(() {
        _areas = cachedAreas;
        _isLoadingAreas = false;
      });
    } else {
      setState(() => _isLoadingAreas = true);
    }
    
    // Refresh from API in background
    try {
      final provider = context.read<ConstructionProvider>();
      final response = await provider.getAreas();
      if (response['success']) {
        final newAreas = List<String>.from(response['areas']);
        await CacheService.saveAreas(newAreas);
        setState(() {
          _areas = newAreas;
        });
      }
    } catch (e) {
      print('Error loading areas: $e');
    } finally {
      setState(() => _isLoadingAreas = false);
    }
  }

  Future<void> _loadStreets(String area) async {
    // Load from cache FIRST (instant - 0ms)
    final cachedStreets = await CacheService.loadStreets(area);
    if (cachedStreets != null && cachedStreets.isNotEmpty) {
      setState(() {
        _streets = cachedStreets;
        _isLoadingStreets = false;
      });
    } else {
      setState(() {
        _isLoadingStreets = true;
        _selectedStreet = null;
        _selectedSite = null;
        _streets = [];
        _sites = [];
      });
    }
    
    // Refresh from API in background
    try {
      final provider = context.read<ConstructionProvider>();
      final response = await provider.getStreets(area);
      if (response['success']) {
        final newStreets = List<String>.from(response['streets']);
        await CacheService.saveStreets(area, newStreets);
        setState(() {
          _streets = newStreets;
        });
      }
    } catch (e) {
      print('Error loading streets: $e');
    } finally {
      setState(() => _isLoadingStreets = false);
    }
  }

  Future<void> _loadSites(String area, String street) async {
    // Load from cache FIRST (instant - 0ms)
    final cachedSites = await CacheService.loadDropdownSites(area, street);
    if (cachedSites != null && cachedSites.isNotEmpty) {
      setState(() {
        _sites = cachedSites;
        _isLoadingSites = false;
      });
    } else {
      setState(() {
        _isLoadingSites = true;
        _selectedSite = null;
        _sites = [];
      });
    }
    
    // Refresh from API in background
    try {
      final provider = context.read<ConstructionProvider>();
      final response = await provider.getSitesByAreaStreet(area, street);
      if (response['success']) {
        final newSites = List<Map<String, dynamic>>.from(response['sites']);
        await CacheService.saveDropdownSites(area, street, newSites);
        setState(() {
          _sites = newSites;
        });
      }
    } catch (e) {
      print('Error loading sites: $e');
    } finally {
      setState(() => _isLoadingSites = false);
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _onAreaChanged(String? area) {
    setState(() {
      _selectedArea = area;
      _selectedStreet = null;
      _selectedSite = null;
      _streets = [];
      _sites = [];
    });
    
    if (area != null) {
      _loadStreets(area);
    }
  }

  void _onStreetChanged(String? street) {
    setState(() {
      _selectedStreet = street;
      _selectedSite = null;
      _sites = [];
    });
    
    if (street != null && _selectedArea != null) {
      _loadSites(_selectedArea!, street);
    }
  }

  void _onSiteChanged(String? siteId) {
    print('🔍 [SITE_CHANGED] Site changed to: $siteId');
    setState(() => _selectedSite = siteId);
    
    if (siteId != null) {
      // Load all role+tab combinations from cache and start background refresh
      _loadAllSiteDataWithCache(siteId);
    }
  }
  
  // Load all 12 combinations (3 roles × 4 tabs) from cache
  Future<void> _loadAllSiteDataWithCache(String siteId) async {
    print('🏗️ [SITE_VIEW] Loading all data for site: $siteId');
    
    final roles = ['Supervisor', 'Site Engineer', 'Architect'];
    
    // Load all combinations from cache first (instant)
    for (final role in roles) {
      await Future.wait([
        _loadLabourDataWithCache(siteId, role),
        _loadMaterialsDataWithCache(siteId, role),
        _loadRequestsDataWithCache(siteId, role),
        _loadPhotosDataWithCache(siteId, role),
      ]);
    }
    
    // Start background refresh for current role
    _startBackgroundRefresh(siteId, _selectedRole);
    
    // Load mismatch data
    _loadMismatchData();
  }
  
  Future<void> _loadLabourDataWithCache(String siteId, String role) async {
    final cacheKey = '${siteId}_${role.toLowerCase()}_labour';
    
    // Load from cache FIRST (instant - 0ms)
    final cachedData = await CacheService.loadSiteLabourData(siteId, role);
    if (cachedData != null && cachedData.isNotEmpty) {
      setState(() {
        _siteDataCache[cacheKey] = cachedData;
      });
      print('✅ [SITE_VIEW] Loaded labour from cache: $role');
    }
    
    // Refresh from API in background (silent)
    _refreshLabourDataInBackground(siteId, role);
  }
  
  Future<void> _loadMaterialsDataWithCache(String siteId, String role) async {
    final cacheKey = '${siteId}_${role.toLowerCase()}_materials';
    
    // Load from cache FIRST (instant - 0ms)
    final cachedData = await CacheService.loadSiteMaterialsData(siteId, role);
    if (cachedData != null && cachedData.isNotEmpty) {
      setState(() {
        _siteDataCache[cacheKey] = cachedData;
      });
      print('✅ [SITE_VIEW] Loaded materials from cache: $role');
    }
    
    // Refresh from API in background (silent)
    _refreshMaterialsDataInBackground(siteId, role);
  }
  
  Future<void> _loadRequestsDataWithCache(String siteId, String role) async {
    final cacheKey = '${siteId}_${role.toLowerCase()}_requests';
    
    // Load from cache FIRST (instant - 0ms)
    final cachedData = await CacheService.loadSiteRequestsData(siteId, role);
    if (cachedData != null && cachedData.isNotEmpty) {
      setState(() {
        _siteDataCache[cacheKey] = cachedData;
      });
      print('✅ [SITE_VIEW] Loaded requests from cache: $role');
    }
    
    // Refresh from API in background (silent)
    _refreshRequestsDataInBackground(siteId, role);
  }
  
  Future<void> _loadPhotosDataWithCache(String siteId, String role) async {
    final cacheKey = '${siteId}_${role.toLowerCase()}_photos';
    
    // Load from cache FIRST (instant - 0ms)
    final cachedData = await CacheService.loadSitePhotosData(siteId, role);
    if (cachedData != null && cachedData.isNotEmpty) {
      setState(() {
        _siteDataCache[cacheKey] = cachedData;
      });
      print('✅ [SITE_VIEW] Loaded photos from cache: $role');
    }
    
    // Refresh from API in background (silent)
    _refreshPhotosDataInBackground(siteId, role);
  }
  
  void _startBackgroundRefresh(String siteId, String role) {
    // Cancel existing timers
    _labourRefreshTimer?.cancel();
    _materialsRefreshTimer?.cancel();
    _requestsRefreshTimer?.cancel();
    _photosRefreshTimer?.cancel();
    
    // Refresh labour data every 60 seconds
    _labourRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshLabourDataInBackground(siteId, role),
    );
    
    // Refresh materials data every 60 seconds
    _materialsRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshMaterialsDataInBackground(siteId, role),
    );
    
    // Refresh requests data every 90 seconds
    _requestsRefreshTimer = Timer.periodic(
      const Duration(seconds: 90),
      (_) => _refreshRequestsDataInBackground(siteId, role),
    );
    
    // Refresh photos data every 120 seconds
    _photosRefreshTimer = Timer.periodic(
      const Duration(seconds: 120),
      (_) => _refreshPhotosDataInBackground(siteId, role),
    );
    
    print('🔄 [SITE_VIEW] Background refresh started for: $role');
  }
  
  Future<void> _refreshLabourDataInBackground(String siteId, String role) async {
    try {
      final provider = context.read<ConstructionProvider>();
      await provider.loadSupervisorHistory(siteId: siteId, forceRefresh: true);
      
      final newData = List<Map<String, dynamic>>.from(provider.labourEntries);
      await CacheService.saveSiteLabourData(siteId, role, newData);
      
      if (mounted) {
        final cacheKey = '${siteId}_${role.toLowerCase()}_labour';
        setState(() {
          _siteDataCache[cacheKey] = newData;
        });
      }
      print('✅ [SITE_VIEW] Labour data refreshed: $role');
    } catch (e) {
      print('⚠️ [SITE_VIEW] Background refresh failed for labour: $e');
    }
  }
  
  Future<void> _refreshMaterialsDataInBackground(String siteId, String role) async {
    try {
      final provider = context.read<ConstructionProvider>();
      await provider.loadSupervisorHistory(siteId: siteId, forceRefresh: true);
      
      final newData = List<Map<String, dynamic>>.from(provider.materialEntries);
      await CacheService.saveSiteMaterialsData(siteId, role, newData);
      
      if (mounted) {
        final cacheKey = '${siteId}_${role.toLowerCase()}_materials';
        setState(() {
          _siteDataCache[cacheKey] = newData;
        });
      }
      print('✅ [SITE_VIEW] Materials data refreshed: $role');
    } catch (e) {
      print('⚠️ [SITE_VIEW] Background refresh failed for materials: $e');
    }
  }
  
  Future<void> _refreshRequestsDataInBackground(String siteId, String role) async {
    try {
      final changeProvider = context.read<ChangeRequestProvider>();
      await changeProvider.loadMyChangeRequests();
      
      final newData = List<Map<String, dynamic>>.from(changeProvider.myChangeRequests);
      await CacheService.saveSiteRequestsData(siteId, role, newData);
      
      if (mounted) {
        final cacheKey = '${siteId}_${role.toLowerCase()}_requests';
        setState(() {
          _siteDataCache[cacheKey] = newData;
        });
      }
      print('✅ [SITE_VIEW] Requests data refreshed: $role');
    } catch (e) {
      print('⚠️ [SITE_VIEW] Background refresh failed for requests: $e');
    }
  }
  
  Future<void> _refreshPhotosDataInBackground(String siteId, String role) async {
    try {
      final provider = context.read<ConstructionProvider>();
      await provider.loadAccountantPhotos(forceRefresh: true, siteId: siteId);
      
      final newData = List<Map<String, dynamic>>.from(provider.accountantPhotos);
      await CacheService.saveSitePhotosData(siteId, role, newData);
      
      if (mounted) {
        final cacheKey = '${siteId}_${role.toLowerCase()}_photos';
        setState(() {
          _siteDataCache[cacheKey] = newData;
        });
      }
      print('✅ [SITE_VIEW] Photos data refreshed: $role');
    } catch (e) {
      print('⚠️ [SITE_VIEW] Background refresh failed for photos: $e');
    }
  }

  void _loadRoleSpecificData() {
    if (_selectedSite == null) return;
    
    // Data already loaded from cache, just restart timers for new role
    _startBackgroundRefresh(_selectedSite!, _selectedRole);
    _loadMismatchData();
  }

  Future<void> _loadMismatchData() async {
    print('🔍 [MISMATCH] _loadMismatchData called, _selectedSite: $_selectedSite');
    if (_selectedSite == null) {
      print('⚠️ [MISMATCH] No site selected, skipping mismatch detection');
      return;
    }
    
    print('🔍 [MISMATCH] Fetching mismatches for site: $_selectedSite');
    try {
      final result = await _mismatchService.detectLaborMismatches(
        siteId: _selectedSite,
        days: 7,
      );
      
      print('🔍 [MISMATCH] API response: ${result['success']}, total: ${result['total_mismatches']}');
      
      if (result['success'] == true) {
        setState(() {
          _mismatchData = result;
          _totalMismatches = result['total_mismatches'] ?? 0;
        });
        print('✅ [MISMATCH] Loaded $_totalMismatches mismatches');
      } else {
        print('⚠️ [MISMATCH] API returned success=false: ${result['error']}');
      }
    } catch (e) {
      print('❌ [MISMATCH] Error loading mismatch data: $e');
    }
  }

  Widget _buildPhotoCard(Map<String, dynamic> photo) {
    final updateType = photo['update_type'] as String;
    final isMorning = updateType == 'STARTED';
    final photoTypeLabel = isMorning ? 'Morning' : 'Evening';
    final photoIcon = isMorning ? '🌅' : '🌆';
    final photoColor = isMorning ? AppColors.textSecondary : AppColors.deepNavy;

    return GestureDetector(
      onTap: () => _showPhotoDetail(photo),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepNavy.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                  child: Image.network(
                    ConstructionService.getFullImageUrl(photo['image_url']),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.white,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.image_not_supported,
                              size: 40.sp,
                              color: AppColors.textSecondary.withValues(alpha: 0.5),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Image not available',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.white,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.deepNavy,
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Photo Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.all(12.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photo Type Badge
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: photoColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(photoIcon, style: TextStyle(fontSize: 12.sp)),
                          SizedBox(width: 4.w),
                          Text(
                            photoTypeLabel,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.bold,
                              color: photoColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 8.h),

                    // Upload Info
                    Text(
                      'By ${photo['uploaded_by'] ?? 'Unknown'}',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4.h),

                    // Date
                    Text(
                      _formatPhotoDate(photo['update_date']),
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoDetail(Map<String, dynamic> photo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(16.r),
                decoration: BoxDecoration(
                  color: AppColors.deepNavy,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Site Photo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Photo
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.r),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: Image.network(
                      ConstructionService.getFullImageUrl(photo['image_url']),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 200.h,
                          color: Colors.white,
                          child: const Center(
                            child: Text('Image not available'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Details
              Container(
                padding: EdgeInsets.all(16.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhotoDetailRow('Type', photo['update_type'] == 'STARTED' ? 'Morning Photo' : 'Evening Photo'),
                    _buildPhotoDetailRow('Uploaded by', photo['uploaded_by'] ?? 'Unknown'),
                    _buildPhotoDetailRow('Role', photo['uploaded_by_role'] ?? 'Unknown'),
                    _buildPhotoDetailRow('Date', _formatPhotoDate(photo['update_date'])),
                    if (photo['description'] != null && photo['description'].toString().isNotEmpty)
                      _buildPhotoDetailRow('Description', photo['description']),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100.w,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.deepNavy,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPhotoDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    // If no site is selected, show dropdown selection screen
    if (_selectedSite == null) {
      return _buildSiteSelectionScreen();
    }
    
    // If site is selected, show role-based content
    return _buildSiteContentScreen();
  }

  Widget _buildSiteSelectionScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Select Site',
          style: TextStyle(
            color: AppColors.deepNavy,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.deepNavy),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20.r),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50.w,
                    height: 50.h,
                    decoration: BoxDecoration(
                      gradient: AppColors.navyGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (_currentUser?['full_name'] ?? 'A').substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20.sp,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentUser?['full_name'] ?? 'Accountant',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.deepNavy,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Select site to view entries',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 24.h),

            // Dropdown Selection Card
            Container(
              padding: EdgeInsets.all(24.r),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Site Selection',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.deepNavy,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Choose area, street, and site to view entries',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 24.h),

                  // Area Dropdown
                  _buildDropdownSection(
                    title: 'Area',
                    icon: Icons.location_city,
                    value: _selectedArea,
                    items: _areas,
                    onChanged: _onAreaChanged,
                    isLoading: _isLoadingAreas,
                    hint: 'Select an area',
                  ),

                  SizedBox(height: 20.h),

                  // Street Dropdown
                  _buildDropdownSection(
                    title: 'Street',
                    icon: Icons.route,
                    value: _selectedStreet,
                    items: _streets,
                    onChanged: _onStreetChanged,
                    isLoading: _isLoadingStreets,
                    hint: 'Select a street',
                    enabled: _selectedArea != null,
                  ),

                  SizedBox(height: 20.h),

                  // Site Dropdown
                  _buildSiteDropdownSection(),
                ],
              ),
            ),

            SizedBox(height: 20.h),

            // Instructions
            Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                color: AppColors.lightBackground,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: AppColors.deepNavy.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.deepNavy,
                    size: 20.sp,
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      'Select all three dropdowns to automatically enter the site and view role-based entries.',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSiteContentScreen() {
    final site = _sites.firstWhere((s) => s['id'] == _selectedSite);
    final siteName = site['display_name'] ?? site['site_name'] ?? 'Site';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 70,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              siteName,
              style: TextStyle(
                color: AppColors.deepNavy,
                fontWeight: FontWeight.bold,
                fontSize: 18.sp,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              'Accountant View',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.deepNavy),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _selectedSite = null;
              _selectedArea = null;
              _selectedStreet = null;
              _streets.clear();
              _sites.clear();
            });
          },
        ),
        actions: [
          // Mismatch Warning Icon
          if (_totalMismatches > 0)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28.sp),
                    tooltip: 'Labor Entry Mismatches',
                    onPressed: () {
                      print('🔍 [BUTTON] Warning icon clicked!');
                      _showMismatchDialog();
                    },
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      child: Container(
                        padding: EdgeInsets.all(4.r),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 18.w,
                          minHeight: 18.h,
                        ),
                        child: Text(
                          '$_totalMismatches',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // IconButton(
          //   icon: const Icon(Icons.receipt_long),
          //   tooltip: 'Bills & Agreements',
          //   onPressed: () {
          //     Navigator.push(
          //       context,
          //       MaterialPageRoute(
          //         builder: (context) => AccountantBillsScreen(
          //           siteId: _selectedSite!,
          //           siteName: siteName,
          //         ),
          //       ),
          //     );
          //   },
          // ),
          // IconButton(
          //   icon: const Icon(Icons.logout_rounded),
          //   style: IconButton.styleFrom(
          //     backgroundColor: Colors.transparent,
          //   ),
          //   onPressed: _logout,
          // ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Supervisor', 'Site Engineer', 'Architect'].map((role) {
                  final selected = _selectedRole == role;
                  return Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedRole = role);
                        _loadRoleSpecificData();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.deepNavy : AppColors.lightSlate,
                          borderRadius: BorderRadius.circular(20.r),
                          border: Border.all(
                            color: selected ? AppColors.deepNavy : AppColors.deepNavy.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          role,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            color: selected ? Colors.white : AppColors.deepNavy,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
      body: _selectedRole == 'Supervisor'
          ? _buildSupervisorContent()
          : _selectedRole == 'Site Engineer'
              ? _buildSiteEngineerContent()
              : _buildArchitectContent(),
    );
  }

  Widget _buildSupervisorContent() {
    return Consumer2<ConstructionProvider, ChangeRequestProvider>(
      builder: (context, provider, changeProvider, child) {
        return Column(
          children: [
            // Sub-filter chips: Labour | Materials | Requests | Photos
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 10.h),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['Labour', 'Materials'].map((tab) {
                    final selected = _selectedSupervisorTab == tab;
                    return Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedSupervisorTab = tab),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF1A1A2E) : AppColors.lightSlate,
                            borderRadius: BorderRadius.circular(20.r),
                            border: Border.all(
                              color: selected ? AppColors.deepNavy : AppColors.deepNavy.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            tab,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              color: selected ? Colors.white : AppColors.deepNavy,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _selectedSupervisorTab == 'Labour'
                  ? _buildHistoryList(
                      provider.labourEntries.where((e) {
                        final role = (e['submitted_by_role'] as String? ?? e['user_role'] as String? ?? '').toLowerCase();
                        return role == 'supervisor';
                      }).toList(),
                      _getPendingRequestIds(changeProvider),
                      true,
                    )
                  : _buildHistoryList(
                      provider.materialEntries.where((e) {
                        final role = (e['submitted_by_role'] as String? ?? e['user_role'] as String? ?? '').toLowerCase();
                        return role == 'supervisor';
                      }).toList(),
                      _getPendingRequestIds(changeProvider),
                      false,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSiteEngineerContent() {
    return Consumer<ConstructionProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            // Sub-filter chips: Photos | Labor | Materials | Documents
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 10.h),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [ 'Labor', 'Materials',].map((tab) {
                    final selected = _selectedSiteEngineerTab == tab;
                    return Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedSiteEngineerTab = tab),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.deepNavy : AppColors.lightSlate,
                            borderRadius: BorderRadius.circular(20.r),
                            border: Border.all(
                              color: selected ? AppColors.deepNavy : AppColors.deepNavy.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            tab,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              color: selected ? Colors.white : AppColors.deepNavy,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _selectedSiteEngineerTab == 'Photos'
                  ? _buildSiteEngineerPhotosTab(provider)
                  : _selectedSiteEngineerTab == 'Labor'
                      ? _buildSiteEngineerLaborTab(provider)
                      : _selectedSiteEngineerTab == 'Materials'
                          ? _buildSiteEngineerMaterialsTab(provider)
                          : _buildSiteEngineerDocumentsTab(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSiteEngineerPhotosTab(ConstructionProvider provider) {
    final photos = provider.accountantPhotos;
    final isLoading = provider.isLoadingAccountantPhotos;
    
    // Filter photos for the selected site
    final sitePhotos = photos.where((photo) => 
      photo['site_id'] == _selectedSite).toList();
    
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.deepNavy),
            SizedBox(height: 16.h),
            Text(
              'Loading site photos...',
              style: TextStyle(
                fontSize: 16.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (sitePhotos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 80.sp,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 16.h),
            Text(
              'No Photos Found',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Site Engineer photos will appear here',
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 20.h),
            ElevatedButton.icon(
              onPressed: () async {
                await provider.loadAccountantPhotos(
                  forceRefresh: true,
                  siteId: _selectedSite,
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Photos'),
              style: ElevatedButton.styleFrom(
                backgroundColor:AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadAccountantPhotos(
          forceRefresh: true,
          siteId: _selectedSite,
        );
      },
      child: _buildPhotosWithDropdown(sitePhotos),
    );
  }

  Widget _buildSiteEngineerLaborTab(ConstructionProvider provider) {
    // Filter only Site Engineer labour entries
    final labourEntries = provider.labourEntries.where((e) {
      final role = (e['user_role'] as String? ?? '').toLowerCase().replaceAll('_', ' ');
      return role == 'site engineer';
    }).toList();

    if (labourEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 72.sp,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            SizedBox(height: 16.h),
            Text(
              'No Entries Added',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'No labour entries added by Site Engineer',
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadSupervisorHistory(
          siteId: _selectedSite,
          forceRefresh: true,
        );
      },
      child: _buildHistoryList(labourEntries, <String>{}, true),
    );
  }

  Widget _buildSiteEngineerMaterialsTab(ConstructionProvider provider) {
    // Filter only Site Engineer material entries
    final materialEntries = provider.materialEntries.where((e) {
      final role = (e['user_role'] as String? ?? '').toLowerCase().replaceAll('_', ' ');
      return role == 'site engineer';
    }).toList();

    if (materialEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 72,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Entries Added',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No material entries added by Site Engineer',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                await provider.loadSupervisorHistory(
                  siteId: _selectedSite,
                  forceRefresh: true,
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Materials'),
              style: ElevatedButton.styleFrom(
                backgroundColor:AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadSupervisorHistory(
          siteId: _selectedSite,
          forceRefresh: true,
        );
      },
      child: _buildHistoryList(materialEntries, <String>{}, false),
    );
  }

  Widget _buildArchitectContent() {
    return Consumer<ConstructionProvider>(
      builder: (context, provider, child) {
        final documents = provider.architectDocuments;
        final complaints = provider.architectComplaints;
        final isLoading = provider.isLoadingArchitectData;
        
        // Filter documents and complaints for the selected site
        final siteDocuments = documents.where((doc) => 
          doc['site_id'] == _selectedSite).toList();
        final siteComplaints = complaints.where((complaint) => 
          complaint['site_id'] == _selectedSite).toList();
        
        if (isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.deepNavy),
                SizedBox(height: 16),
                Text(
                  'Loading architect data...',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        
        if (siteDocuments.isEmpty && siteComplaints.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.architecture,
                  size: 80,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Architect Data Found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Architect documents and complaints will appear here',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () async {
                    await provider.loadArchitectData(
                      forceRefresh: true,
                      siteId: _selectedSite,
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Data'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:AppColors.deepNavy,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }
        
        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadArchitectData(
              forceRefresh: true,
              siteId: _selectedSite,
            );
          },
          child: _buildArchitectDataWithDropdown(siteDocuments, siteComplaints),
        );
      },
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> document) {
    final documentType = document['document_type'] as String;
    final title = document['title'] as String;
    final description = document['description'] as String?;
    final uploadDate = document['upload_date'] as String?;
    final architectName = document['architect_name'] as String?;

    IconData documentIcon;
    Color documentColor;
    
    switch (documentType) {
      case 'Floor Plan':
        documentIcon = Icons.architecture;
        documentColor = AppColors.deepNavy;
        break;
      case 'Elevation':
        documentIcon = Icons.apartment;
        documentColor = AppColors.textSecondary;
        break;
      case 'Structure Drawing':
        documentIcon = Icons.foundation;
        documentColor = AppColors.textPrimary;
        break;
      case 'Design':
        documentIcon = Icons.design_services;
        documentColor = AppColors.deepNavy;
        break;
      default:
        documentIcon = Icons.description;
        documentColor = AppColors.textSecondary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: documentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(documentIcon, color: documentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: documentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        documentType,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: documentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'By ${architectName ?? 'Unknown'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                _formatDate(uploadDate),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComplaintCard(Map<String, dynamic> complaint) {
    final title = complaint['title'] as String;
    final description = complaint['description'] as String;
    final priority = complaint['priority'] as String;
    final status = complaint['status'] as String;
    final uploadDate = complaint['upload_date'] as String?;
    final architectName = complaint['architect_name'] as String?;

    Color priorityColor;
    switch (priority) {
      case 'URGENT':
        priorityColor = AppColors.deepNavy;
        break;
      case 'HIGH':
        priorityColor = AppColors.textPrimary;
        break;
      case 'MEDIUM':
        priorityColor = AppColors.textSecondary;
        break;
      default:
        priorityColor = AppColors.textTertiary;
    }

    Color statusColor;
    switch (status) {
      case 'RESOLVED':
        statusColor = AppColors.textSecondary;
        break;
      case 'IN_PROGRESS':
        statusColor = AppColors.deepNavy;
        break;
      case 'CLOSED':
        statusColor = AppColors.textTertiary;
        break;
      default:
        statusColor = AppColors.textPrimary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: priorityColor.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.report_problem, color: priorityColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: priorityColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            priority,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: priorityColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'By ${architectName ?? 'Unknown'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                _formatDate(uploadDate),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  Set<String> _getPendingRequestIds(ChangeRequestProvider changeProvider) {
    final pendingRequestIds = <String>{};
    for (var request in changeProvider.myChangeRequests) {
      if (request['status'] == 'PENDING') {
        pendingRequestIds.add(request['entry_id'].toString());
      }
    }
    return pendingRequestIds;
  }

  Widget _buildHistoryList(List<Map<String, dynamic>> entries, Set<String> pendingRequestIds, bool isLabour) {
    if (entries.isEmpty) {
      return _buildEmptyState(
        'No ${isLabour ? 'labour' : 'material'} history found',
        isLabour ? Icons.people_outline : Icons.inventory_2_outlined,
      );
    }

    // Group entries by date
    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var entry in entries) {
      final date = entry['entry_date'] ?? 'Unknown';
      if (!groupedByDate.containsKey(date)) {
        groupedByDate[date] = [];
      }
      groupedByDate[date]!.add(entry);
    }

    // Sort dates in descending order
    final sortedDates = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: () async {
        await context.read<ConstructionProvider>().loadSupervisorHistory(forceRefresh: true, siteId: _selectedSite);
        await context.read<ChangeRequestProvider>().loadMyChangeRequests(forceRefresh: true);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedDates.length,
        itemBuilder: (context, index) {
          final date = sortedDates[index];
          final dateEntries = groupedByDate[date]!;
          final isExpanded = _expandedDates.contains(date);

          return _buildDateCard(date, dateEntries, isExpanded, isLabour, pendingRequestIds);
        },
      ),
    );
  }

  Widget _buildDropdownSection({
    required String title,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required bool isLoading,
    required String hint,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.deepNavy),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: enabled ? AppColors.lightBackground : AppColors.lightBackground.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? AppColors.deepNavy.withValues(alpha: 0.3) : AppColors.textSecondary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Loading...',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: value,
                    hint: Text(
                      enabled ? hint : 'Select ${title.toLowerCase()} first',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    isExpanded: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: enabled ? AppColors.deepNavy : AppColors.textSecondary,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.deepNavy,
                      fontWeight: FontWeight.w600,
                    ),
                    items: enabled
                        ? items.map((item) {
                            return DropdownMenuItem<String>(
                              value: item,
                              child: Text(item),
                            );
                          }).toList()
                        : null,
                    onChanged: enabled ? onChanged : null,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSiteDropdownSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.business, size: 18, color: AppColors.deepNavy),
            const SizedBox(width: 8),
            const Text(
              'Site',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: _selectedStreet != null ? AppColors.lightBackground : AppColors.lightBackground.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _selectedStreet != null ? AppColors.deepNavy.withValues(alpha: 0.3) : AppColors.textSecondary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: _isLoadingSites
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Loading sites...',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedSite,
                    hint: Text(
                      _selectedStreet != null ? 'Select a site' : 'Select street first',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    isExpanded: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: _selectedStreet != null ? AppColors.deepNavy : AppColors.textSecondary,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.deepNavy,
                      fontWeight: FontWeight.w600,
                    ),
                    items: _selectedStreet != null
                        ? _sites.map((site) {
                            return DropdownMenuItem<String>(
                              value: site['id'],
                              child: Text(site['display_name'] ?? site['site_name'] ?? 'Site'),
                            );
                          }).toList()
                        : null,
                    onChanged: _selectedStreet != null ? _onSiteChanged : null,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: AppColors.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard(String date, List<Map<String, dynamic>> entries, bool isExpanded, bool isLabour, Set<String> pendingRequestIds) {
    final totalEntries = entries.length;
    final formattedDate = _formatHistoryDate(date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Date Header - Always visible
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDates.remove(date);
                  } else {
                    _expandedDates.add(date);
                  }
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.deepNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.calendar_today,
                        color: AppColors.deepNavy,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$totalEntries ${isLabour ? 'labour' : 'material'} ${totalEntries == 1 ? 'entry' : 'entries'}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.deepNavy,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded Details
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: entries.map((entry) {
                  return _buildEntryDetail(entry, isLabour, pendingRequestIds);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryDetail(Map<String, dynamic> entry, bool isLabour, Set<String> pendingRequestIds) {
    final entryId = entry['id']?.toString() ?? '';
    final hasPendingRequest = pendingRequestIds.contains(entryId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasPendingRequest ? AppColors.safetyOrange.withValues(alpha: 0.3) : AppColors.borderColor,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLabour) ..._buildLabourDetails(entry, hasPendingRequest)
          else ..._buildMaterialDetails(entry, hasPendingRequest),
        ],
      ),
    );
  }

  List<Widget> _buildLabourDetails(Map<String, dynamic> entry, bool hasPendingRequest) {
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              entry['labour_type'] ?? 'N/A',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
          ),
          if (hasPendingRequest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.safetyOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Change Pending',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.safetyOrange,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _buildDetailRow(Icons.people, 'Workers', entry['labour_count']?.toString() ?? '0'),
      _buildDetailRow(Icons.access_time, 'Time', _formatTime(entry['entry_time'])),
      if (entry['notes'] != null && entry['notes'].toString().isNotEmpty)
        _buildDetailRow(Icons.note, 'Notes', entry['notes']),
      // Admin-set daily rate
      if (entry['daily_rate'] != null) ...[
        const SizedBox(height: 8),
        _buildRateBadge(
          count: entry['labour_count'] as int? ?? 0,
          dailyRate: (entry['daily_rate'] as num).toDouble(),
          totalCost: (entry['total_cost'] as num?)?.toDouble(),
        ),
      ],
    ];
  }

  Widget _buildRateBadge({required int count, required double dailyRate, double? totalCost}) {
    final total = totalCost ?? dailyRate * count;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.statusCompleted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.statusCompleted.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.currency_rupee, size: 14, color: AppColors.statusCompleted),
          const SizedBox(width: 4),
          Text(
            '₹${dailyRate.toStringAsFixed(0)}/day × $count = ₹${total.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.statusCompleted,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMaterialDetails(Map<String, dynamic> entry, bool hasPendingRequest) {
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              entry['material_type'] ?? 'N/A',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
          ),
          if (hasPendingRequest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.safetyOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Change Pending',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.safetyOrange,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _buildDetailRow(Icons.inventory_2, 'Quantity', '${entry['quantity'] ?? '0'} ${entry['unit'] ?? ''}'),
      _buildDetailRow(Icons.access_time, 'Time', _formatTime(entry['timestamp'])),
      if (entry['notes'] != null && entry['notes'].toString().isNotEmpty)
        _buildDetailRow(Icons.note, 'Notes', entry['notes']),
    ];
  }

  Widget _buildDetailRow(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatHistoryDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final dateOnly = DateTime(date.year, date.month, date.day);

      if (dateOnly == today) {
        return 'Today, ${DateFormat('MMM d, yyyy').format(date)}';
      } else if (dateOnly == yesterday) {
        return 'Yesterday, ${DateFormat('MMM d, yyyy').format(date)}';
      } else {
        return DateFormat('EEEE, MMM d, yyyy').format(date);
      }
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('h:mm a').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  // New method for photos with dropdown organization
  Widget _buildPhotosWithDropdown(List<Map<String, dynamic>> photos) {
    // Group photos by date
    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var photo in photos) {
      final date = photo['update_date'] ?? 'Unknown';
      final dateOnly = date.split('T')[0]; // Extract date part only
      if (!groupedByDate.containsKey(dateOnly)) {
        groupedByDate[dateOnly] = [];
      }
      groupedByDate[dateOnly]!.add(photo);
    }

    // Sort dates in descending order
    final sortedDates = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final datePhotos = groupedByDate[date]!;
        final isExpanded = _expandedDates.contains('photos_$date');

        return _buildPhotoDateCard(date, datePhotos, isExpanded);
      },
    );
  }

  Widget _buildPhotoDateCard(String date, List<Map<String, dynamic>> photos, bool isExpanded) {
    final totalPhotos = photos.length;
    final formattedDate = _formatHistoryDate(date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Date Header - Always visible
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDates.remove('photos_$date');
                  } else {
                    _expandedDates.add('photos_$date');
                  }
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.photo_camera,
                        color: AppColors.textSecondary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$totalPhotos ${totalPhotos == 1 ? 'photo' : 'photos'}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.deepNavy,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded Photos Grid
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemCount: photos.length,
                itemBuilder: (context, index) => _buildPhotoCard(photos[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // New method for architect data with dropdown organization
  Widget _buildArchitectDataWithDropdown(List<Map<String, dynamic>> documents, List<Map<String, dynamic>> complaints) {
    // Combine documents and complaints with type indicator
    final List<Map<String, dynamic>> allItems = [];
    
    for (var doc in documents) {
      allItems.add({...doc, 'item_type': 'document'});
    }
    
    for (var complaint in complaints) {
      allItems.add({...complaint, 'item_type': 'complaint'});
    }

    // Group by date
    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var item in allItems) {
      final date = item['upload_date'] ?? 'Unknown';
      final dateOnly = date.split('T')[0]; // Extract date part only
      if (!groupedByDate.containsKey(dateOnly)) {
        groupedByDate[dateOnly] = [];
      }
      groupedByDate[dateOnly]!.add(item);
    }

    // Sort dates in descending order
    final sortedDates = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final dateItems = groupedByDate[date]!;
        final isExpanded = _expandedDates.contains('architect_$date');

        return _buildArchitectDateCard(date, dateItems, isExpanded);
      },
    );
  }

  Widget _buildArchitectDateCard(String date, List<Map<String, dynamic>> items, bool isExpanded) {
    final documentsCount = items.where((item) => item['item_type'] == 'document').length;
    final complaintsCount = items.where((item) => item['item_type'] == 'complaint').length;
    final formattedDate = _formatHistoryDate(date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Date Header - Always visible
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDates.remove('architect_$date');
                  } else {
                    _expandedDates.add('architect_$date');
                  }
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.deepNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.architecture,
                        color: AppColors.deepNavy,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$documentsCount ${documentsCount == 1 ? 'document' : 'documents'}, $complaintsCount ${complaintsCount == 1 ? 'complaint' : 'complaints'}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.deepNavy,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded Items
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: items.map((item) {
                  if (item['item_type'] == 'document') {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDocumentCard(item),
                    );
                  } else {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildComplaintCard(item),
                    );
                  }
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSiteEngineerDocumentsTab() {
    return _AccountantDocumentsView(siteId: _selectedSite);
  }

  void _showMismatchDialog() {
    print('🔍 [MISMATCH DIALOG] _showMismatchDialog called');
    print('🔍 [MISMATCH DIALOG] _totalMismatches: $_totalMismatches');
    print('🔍 [MISMATCH DIALOG] _mismatchData keys: ${_mismatchData.keys}');
    
    final mismatches = _mismatchData['mismatches'] as List<Map<String, dynamic>>? ?? [];
    print('🔍 [MISMATCH DIALOG] mismatches count: ${mismatches.length}');
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxHeight: 600, maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Labor Entry Mismatches',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Found $_totalMismatches mismatches between Supervisor and Site Engineer entries',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: mismatches.length,
                  itemBuilder: (context, index) {
                    final mismatch = mismatches[index];
                    return _buildMismatchCard(mismatch);
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor:AppColors.deepNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMismatchCard(Map<String, dynamic> mismatch) {
    final mismatchType = mismatch['mismatch_type'] as String;
    final labourType = mismatch['labour_type'] as String;
    final entryDate = mismatch['entry_date'] as String;
    final supervisorCount = mismatch['supervisor_count'] as int;
    final engineerCount = mismatch['engineer_count'] as int;
    final difference = mismatch['difference'] as int;
    
    Color mismatchColor;
    IconData mismatchIcon;
    String mismatchTitle;
    
    switch (mismatchType) {
      case 'COUNT_DIFFERENCE':
        mismatchColor = Colors.orange;
        mismatchIcon = Icons.compare_arrows;
        mismatchTitle = 'Count Mismatch';
        break;
      case 'MISSING_ENGINEER_ENTRY':
        mismatchColor = Colors.red;
        mismatchIcon = Icons.person_off;
        mismatchTitle = 'Missing Site Engineer Entry';
        break;
      case 'MISSING_SUPERVISOR_ENTRY':
        mismatchColor = Colors.red;
        mismatchIcon = Icons.person_off_outlined;
        mismatchTitle = 'Missing Supervisor Entry';
        break;
      default:
        mismatchColor = Colors.grey;
        mismatchIcon = Icons.error_outline;
        mismatchTitle = 'Unknown Mismatch';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mismatchColor.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: mismatchColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: mismatchColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(mismatchIcon, color: mismatchColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mismatchTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: mismatchColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labourType,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: mismatchColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Δ $difference',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: mismatchColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supervisor',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$supervisorCount workers',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    if (mismatch['supervisor_name'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        mismatch['supervisor_name'],
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Site Engineer',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$engineerCount workers',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    if (mismatch['engineer_name'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        mismatch['engineer_name'],
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                entryDate,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Accountant Documents View Widget
class _AccountantDocumentsView extends StatefulWidget {
  final String? siteId;

  const _AccountantDocumentsView({required this.siteId});

  @override
  State<_AccountantDocumentsView> createState() => _AccountantDocumentsViewState();
}

class _AccountantDocumentsViewState extends State<_AccountantDocumentsView> with SingleTickerProviderStateMixin {
  late TabController _docTabController;
  List<Map<String, dynamic>> _siteEngineerDocs = [];
  List<Map<String, dynamic>> _architectDocs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _docTabController = TabController(length: 2, vsync: this);
    if (widget.siteId != null) {
      _loadDocuments();
    }
  }

  @override
  void didUpdateWidget(_AccountantDocumentsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.siteId != oldWidget.siteId && widget.siteId != null) {
      _loadDocuments();
    }
  }

  @override
  void dispose() {
    _docTabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    if (widget.siteId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final documentService = DocumentService();
      final result = await documentService.getAllDocuments(siteId: widget.siteId!);
      
      if (result['success'] == true) {
        setState(() {
          _siteEngineerDocs = result['site_engineer_documents'];
          _architectDocs = result['architect_documents'];
        });
      }
    } catch (e) {
      print('Error loading documents: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openDocument(String fileUrl) async {
    final url = 'http://187.127.164.22$fileUrl';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open document')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.siteId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 80, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'Select a Site',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Choose a site to view documents',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _docTabController,
            labelColor: AppColors.deepNavy,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.deepNavy,
            tabs: [
              Tab(text: 'Site Engineer (${_siteEngineerDocs.length})'),
              Tab(text: 'Architect (${_architectDocs.length})'),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: AppColors.deepNavy))
              : TabBarView(
                  controller: _docTabController,
                  children: [
                    _buildDocumentList(_siteEngineerDocs, 'Site Engineer'),
                    _buildDocumentList(_architectDocs, 'Architect'),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDocumentList(List<Map<String, dynamic>> documents, String role) {
    if (documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 80, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'No Documents',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '$role has not uploaded any documents yet',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadDocuments,
              icon: Icon(Icons.refresh),
              label: Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor:AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDocuments,
      color: AppColors.deepNavy,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: documents.length,
        itemBuilder: (context, index) {
          final doc = documents[index];
          return _buildDocumentCard(doc);
        },
      ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> doc) {
    final fileSize = doc['file_size'] != null 
        ? '${(doc['file_size'] / 1024 / 1024).toStringAsFixed(2)} MB'
        : 'Unknown size';
    
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [AppColors.cardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openDocument(doc['file_url']),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.picture_as_pdf, color: Colors.red, size: 30),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc['title'] ?? 'Untitled',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.deepNavy.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              doc['document_type'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.deepNavy,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.safetyOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              doc['role'] ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.safetyOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Uploaded: ${doc['upload_date'] ?? ''}',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Text(
                        'By: ${doc['uploaded_by'] ?? 'Unknown'} • $fileSize',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
