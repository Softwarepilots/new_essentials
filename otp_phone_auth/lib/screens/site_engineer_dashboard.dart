import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../providers/construction_provider.dart';
import '../services/auth_service.dart';
import '../services/construction_service.dart';
import '../services/budget_management_service.dart';
import '../utils/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../models/user_model.dart';
import 'login_screen.dart';
import 'site_engineer_site_detail_screen.dart';
import 'site_engineer_reports_screen.dart';
import 'edit_profile_screen.dart';
import '../widgets/walkie_talkie_button.dart';

class SiteEngineerDashboard extends StatefulWidget {
  final UserModel user;

  const SiteEngineerDashboard({super.key, required this.user});

  @override
  State<SiteEngineerDashboard> createState() => _SiteEngineerDashboardState();
}

class _SiteEngineerDashboardState extends State<SiteEngineerDashboard> {
  final _authService = AuthService();
  int _currentBottomIndex =
      0; // 0=Dashboard, 1=Sites, 2=Reports, 3=Notifications, 4=Profile
  late UserModel _user;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Filter state
  String? _selectedArea;
  String? _selectedStreet;

  final Map<String, Map<String, bool>> _uploadStatus =
      {}; // site_id -> {morning: bool, evening: bool}

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    await context.read<ConstructionProvider>().loadSites();
    await _loadUploadStatuses();
  }

  Future<void> _loadUploadStatuses() async {
    final sites = context.read<ConstructionProvider>().sites;
    for (var site in sites) {
      await _loadSiteUploadStatus(site['id']);
    }
  }

  Future<void> _loadSiteUploadStatus(String siteId) async {
    try {
      final token = await _authService.getToken();

      final response = await http.get(
        Uri.parse(
          '${AuthService.baseUrl}/construction/today-upload-status/$siteId/',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _uploadStatus[siteId] = {
            'morning': data['morning_uploaded'] ?? false,
            'evening': data['evening_uploaded'] ?? false,
          };
        });
      }
    } catch (e) {
      // Silently fail - status will show as not uploaded
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          'Sign Out',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.deepNavy,
          ),
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusOverdue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            child: Text(
              'Sign Out',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.logout();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConstructionProvider>(
      builder: (context, provider, child) {
        Widget currentScreen;
        switch (_currentBottomIndex) {
          case 0: // Dashboard
            currentScreen = _buildDashboardTab(provider);
            break;
          case 1: // Sites
            currentScreen = _buildSitesTab(provider);
            break;
          case 2: // Reports
            currentScreen = const SiteEngineerReportsScreen();
            break;

          case 3: // Profile
            currentScreen = _buildProfileTab();
            break;
          default:
            currentScreen = _buildDashboardTab(provider);
        }

        return Scaffold(
          backgroundColor: AppColors.lightSlate,
          appBar: CommonWidgets.buildAppBar(
            context,
            title: _getAppBarTitle(),
            actions: [
              const WalkieTalkieButton(isAdmin: false, iconColor: AppColors.deepNavy),
              IconButton(
                icon: const Icon(Icons.logout, color: AppColors.deepNavy),
                onPressed: _logout,
                tooltip: 'Sign Out',
              ),
            ],
          ),
          body: currentScreen,
          bottomNavigationBar: CommonWidgets.buildBottomNavigationBar(
            context,
            currentIndex: _currentBottomIndex,
            onTap: (index) => setState(() => _currentBottomIndex = index),
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.dashboard),
                activeIcon: Icon(Icons.dashboard, size: 28.sp),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.location_city),
                activeIcon: Icon(Icons.location_city, size: 28.sp),
                label: 'Sites',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.bar_chart),
                activeIcon: Icon(Icons.bar_chart, size: 28.sp),
                label: 'Reports',
              ),

              BottomNavigationBarItem(
                icon: const Icon(Icons.person),
                activeIcon: Icon(Icons.person, size: 28.sp),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }

  String _getAppBarTitle() {
    switch (_currentBottomIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Sites';
      case 2:
        return 'Reports';
      case 3:
        return 'Notifications';
      case 4:
        return 'Profile';
      default:
        return 'Site Engineer';
    }
  }

  // Dashboard Tab - Overview
  Widget _buildDashboardTab(ConstructionProvider provider) {
    final sites = provider.sites;
    final totalSites = sites.length;

    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadSites(forceRefresh: true);
        await _loadUploadStatuses();
      },
      color: AppColors.deepNavy,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Card
            Container(
              padding: EdgeInsets.all(20.r),
              decoration: BoxDecoration(
                gradient: AppColors.navyGradient,
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 60.w,
                    height: 60.h,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.engineering,
                      color: Colors.white,
                      size: 30.sp,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, ${_user.name ?? "Engineer"}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Site Engineer Dashboard',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24.h),

            // Summary Cards
            Text(
              'Today\'s Overview',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: SummaryCard(
                title: 'Total Sites',
                value: '$totalSites',
                icon: Icons.location_city,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 24.h),

            // Quick Actions
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    'View Sites',
                    Icons.location_city,
                    () => setState(() => _currentBottomIndex = 1),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildQuickActionButton(
                    'Budget',
                    Icons.account_balance_wallet,
                    _openBudget,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        decoration: BoxDecoration(
          color: AppColors.cleanWhite,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.deepNavy.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.deepNavy, size: 20.sp),
            SizedBox(width: 8.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Sites Tab - Dropdown Selection instead of Cards
  Widget _buildSitesTab(ConstructionProvider provider) {
    final sites = provider.sites;

    // Extract unique areas and streets
    final uniqueAreas = sites
        .map((s) => s['area'] as String? ?? '')
        .where((a) => a.isNotEmpty)
        .toSet()
        .toList()
        ..sort();
    final uniqueStreets = sites
        .map((s) => s['street'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
        ..sort();

    print('🔍 [SITES TAB] Sites count: ${sites.length}');
    if (sites.isNotEmpty) {
      print('🔍 [SITES TAB] First site data: ${sites[0]}');
      print('🔍 [SITES TAB] Site keys: ${sites[0].keys.toList()}');
    }
    print('🔍 [SITES TAB] Unique Areas: $uniqueAreas');
    print('🔍 [SITES TAB] Unique Streets: $uniqueStreets');
    print('🔍 [SITES TAB] Selected Area: $_selectedArea, Selected Street: $_selectedStreet');

    // Apply filters
    final filteredSites = sites.where((site) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final name = (site['display_name'] ?? site['site_name'] ?? '')
            .toString()
            .toLowerCase();
        final area = (site['area'] ?? '').toString().toLowerCase();
        final street = (site['street'] ?? '').toString().toLowerCase();
        final customer = (site['customer_name'] ?? '')
            .toString()
            .toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!(name.contains(query) ||
            area.contains(query) ||
            street.contains(query) ||
            customer.contains(query))) {
          return false;
        }
      }

      // Area filter
      if (_selectedArea != null && _selectedArea!.isNotEmpty) {
        if (site['area'] != _selectedArea) {
          return false;
        }
      }

      // Street filter
      if (_selectedStreet != null && _selectedStreet!.isNotEmpty) {
        if (site['street'] != _selectedStreet) {
          return false;
        }
      }

      return true;
    }).toList();

    final isLoading = sites.isEmpty && _uploadStatus.isEmpty;

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.deepNavy),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadSites(forceRefresh: true);
        await _loadUploadStatuses();
      },
      color: AppColors.deepNavy,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Select Site',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Choose a site to view details and upload photos',
              style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
            ),
            SizedBox(height: 24.h),

            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: AppColors.cleanWhite,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search sites by name, area, or customer...',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.deepNavy,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          }),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 16.h,
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            SizedBox(height: 16.h),

            // Filter Dropdowns
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Area',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Material(
                        child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.deepNavy.withValues(alpha: 0.2),
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedArea,
                          isExpanded: true,
                          underline: SizedBox(),
                          padding: EdgeInsets.symmetric(
                            horizontal: 12.w,
                            vertical: 8.h,
                          ),
                          dropdownColor: AppColors.cleanWhite,
                          items: [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                'All Areas',
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ),
                            ...uniqueAreas.map((area) {
                              return DropdownMenuItem<String>(
                                value: area,
                                child: Text(area, style: TextStyle(fontSize: 13.sp)),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            print('📍 Area selected: $value');
                            setState(() => _selectedArea = value);
                          },
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Street',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Material(
                        child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.deepNavy.withValues(alpha: 0.2),
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedStreet,
                          isExpanded: true,
                          underline: SizedBox(),
                          padding: EdgeInsets.symmetric(
                            horizontal: 12.w,
                            vertical: 8.h,
                          ),
                          dropdownColor: AppColors.cleanWhite,
                          items: [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                'All Streets',
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ),
                            ...uniqueStreets.map((street) {
                              return DropdownMenuItem<String>(
                                value: street,
                                child: Text(street, style: TextStyle(fontSize: 13.sp)),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            print('🛣️ Street selected: $value');
                            setState(() => _selectedStreet = value);
                          },
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),

            // Results count
            Padding(
              padding: EdgeInsets.only(bottom: 16.h),
              child: Text(
                'Found ${filteredSites.length} site(s)',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.deepNavy,
                ),
              ),
            ),

            // Sites Dropdown List
            if (filteredSites.isEmpty)
              CommonWidgets.buildEmptyState(
                context,
                message: 'No Sites Assigned',
                icon: Icons.location_city,
                actionText: 'Refresh',
                onAction: () async {
                  await provider.loadSites(forceRefresh: true);
                  await _loadUploadStatuses();
                },
              )
            else
              ...filteredSites
                  .map((site) => _buildSiteDropdownItem(site))
                  .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSiteDropdownItem(Map<String, dynamic> site) {
    final siteId = site['id'].toString();
    final status =
        _uploadStatus[siteId] ?? {'morning': false, 'evening': false};
    final siteName =
        site['display_name'] ?? site['site_name'] ?? 'Unknown Site';
    final location = '${site['area'] ?? ''}, ${site['street'] ?? ''}';

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColors.deepNavy.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _openSiteDetail(site),
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.all(16.r),
          child: Row(
            children: [
              // Site Icon
              Container(
                width: 48.w,
                height: 48.h,
                decoration: BoxDecoration(
                  gradient: AppColors.navyGradient,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.location_city,
                  color: Colors.white,
                  size: 24.sp,
                ),
              ),
              SizedBox(width: 16.w),

              // Site Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      siteName,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14.sp,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Text(
                            location,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),

                    // Photo Status Row
                    Row(
                      children: [
                        _buildCompactStatusChip(
                          '🌅',
                          'Morning',
                          status['morning'] ?? false,
                        ),
                        SizedBox(width: 8.w),
                        _buildCompactStatusChip(
                          '🌆',
                          'Evening',
                          status['evening'] ?? false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow Icon
              Container(
                padding: EdgeInsets.all(8.r),
                decoration: BoxDecoration(
                  color: AppColors.deepNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 16.sp,
                  color: AppColors.deepNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStatusChip(String icon, String label, bool uploaded) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: uploaded
            ? AppColors.statusCompleted.withValues(alpha: 0.1)
            : AppColors.statusOverdue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(
          color: uploaded ? AppColors.statusCompleted : AppColors.statusOverdue,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: TextStyle(fontSize: 12.sp)),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: uploaded
                  ? AppColors.statusCompleted
                  : AppColors.statusOverdue,
            ),
          ),
          SizedBox(width: 4.w),
          Icon(
            uploaded ? Icons.check_circle : Icons.pending,
            size: 12.sp,
            color: uploaded
                ? AppColors.statusCompleted
                : AppColors.statusOverdue,
          ),
        ],
      ),
    );
  }

  // Profile Tab
  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.r),
      child: Column(
        children: [
          SizedBox(height: 20.h),
          // Profile Avatar
          Container(
            width: 100.w,
            height: 100.h,
            decoration: BoxDecoration(
              gradient: AppColors.navyGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, size: 50.sp, color: Colors.white),
          ),
          SizedBox(height: 16.h),
          Text(
            _user.name ?? 'Site Engineer',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.deepNavy,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            _user.email ?? '',
            style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
          ),
          SizedBox(height: 8.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              'Site Engineer',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
          ),
          SizedBox(height: 32.h),

          // Profile Options
          _buildProfileOption(
            Icons.person_outline,
            'Edit Profile',
            _openEditProfile,
          ),
          _buildProfileOption(Icons.lock_outline, 'Change Password', () {}),
          _buildProfileOption(Icons.settings_outlined, 'Settings', () {}),
          _buildProfileOption(Icons.help_outline, 'Help & Support', () {}),
          _buildProfileOption(Icons.info_outline, 'About', () {}),
          SizedBox(height: 16.h),
          _buildProfileOption(
            Icons.logout,
            'Sign Out',
            _logout,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileOption(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isDestructive ? AppColors.statusOverdue : AppColors.deepNavy,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: isDestructive ? AppColors.statusOverdue : AppColors.deepNavy,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16.sp,
          color: isDestructive
              ? AppColors.statusOverdue
              : AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }

  void _openEditProfile() async {
    final updated = await Navigator.push<UserModel>(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(
          user: _user,
          accentColor: AppColors.deepNavy,
          roleLabel: 'Site Engineer',
        ),
      ),
    );
    if (updated != null) {
      setState(() => _user = updated);
    }
  }

  void _openSiteDetail(Map<String, dynamic> site) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SiteEngineerSiteDetailScreen(site: site, user: widget.user),
      ),
    );

    // Reload status if returned from detail screen
    if (result == true) {
      await _loadSiteUploadStatus(site['id']);
    }
  }

  void _openBudget() {
    final sites = context.read<ConstructionProvider>().sites;

    if (sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No sites available. Please add sites first.'),
          backgroundColor: AppColors.statusOverdue,
        ),
      );
      return;
    }

    // Show site selection dialog for budget view
    _showSiteSelectionDialog(
      title: 'Select Site to View Budget',
      onSiteSelected: (site) {
        _showBudgetDetails(site);
      },
    );
  }

  Future<void> _showBudgetDetails(Map<String, dynamic> site) async {
    final siteId = site['id'].toString();
    final siteName =
        site['display_name'] ?? site['site_name'] ?? 'Unknown Site';

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.deepNavy),
      ),
    );

    // Fetch budget data
    final budgetService = BudgetManagementService();
    final budget = await budgetService.getBudgetAllocation(siteId);

    // Close loading dialog
    if (mounted) Navigator.pop(context);

    if (budget == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No budget allocated for this site yet'),
            backgroundColor: AppColors.statusOverdue,
          ),
        );
      }
      return;
    }

    // Show budget details dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.cleanWhite,
          title: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: AppColors.deepNavy,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  siteName,
                  style: TextStyle(
                    color: AppColors.deepNavy,
                    fontWeight: FontWeight.bold,
                    fontSize: 18.sp,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Total Budget Card
                Container(
                  padding: EdgeInsets.all(16.r),
                  decoration: BoxDecoration(
                    gradient: AppColors.navyGradient,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Project Budget',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14.sp,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        _formatCurrency(budget['total_budget']),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16.h),

                // Budget Details
                Text(
                  'Budget Details',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepNavy,
                  ),
                ),
                SizedBox(height: 12.h),

                _buildBudgetDetailRow(
                  'Allocated By',
                  budget['allocated_by'] ?? 'N/A',
                ),
                _buildBudgetDetailRow(
                  'Date',
                  budget['allocated_date']?.substring(0, 10) ?? 'N/A',
                ),
                _buildBudgetDetailRow('Status', budget['status'] ?? 'N/A'),

                if (budget['notes'] != null &&
                    budget['notes'].toString().isNotEmpty) ...[
                  SizedBox(height: 12.h),
                  Text(
                    'Notes',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.deepNavy,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    budget['notes'],
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: TextStyle(
                  color: AppColors.deepNavy,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildBudgetDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.deepNavy,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(dynamic amount) {
    if (amount == null) return '₹0';
    double value = amount is String
        ? double.tryParse(amount) ?? 0
        : amount.toDouble();

    if (value >= 10000000) {
      return '₹${(value / 10000000).toStringAsFixed(2)} Cr';
    } else if (value >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(2)} L';
    } else if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(2)} K';
    }
    return '₹${value.toStringAsFixed(0)}';
  }

  void _showSiteSelectionDialog({
    required String title,
    required Function(Map<String, dynamic>) onSiteSelected,
  }) {
    final sites = context.read<ConstructionProvider>().sites;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cleanWhite,
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.deepNavy,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sites.length,
            itemBuilder: (context, index) {
              final site = sites[index];
              final siteName =
                  site['display_name'] ?? site['site_name'] ?? 'Unknown Site';
              final location = '${site['area'] ?? ''}, ${site['street'] ?? ''}';

              return ListTile(
                leading: Container(
                  width: 40.w,
                  height: 40.h,
                  decoration: BoxDecoration(
                    gradient: AppColors.navyGradient,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(
                    Icons.location_city,
                    color: Colors.white,
                    size: 20.sp,
                  ),
                ),
                title: Text(
                  siteName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepNavy,
                  ),
                ),
                subtitle: Text(
                  location,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onSiteSelected(site);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

}

// Labor Entry Sheet for Site Engineer
class _LaborEntrySheet extends StatefulWidget {
  final String siteId;
  final String siteName;
  final VoidCallback onSuccess;

  const _LaborEntrySheet({
    required this.siteId,
    required this.siteName,
    required this.onSuccess,
  });

  @override
  State<_LaborEntrySheet> createState() => _LaborEntrySheetState();
}

class _LaborEntrySheetState extends State<_LaborEntrySheet> {
  final _constructionService = ConstructionService();
  final _budgetService = BudgetManagementService();
  final Map<String, int> _labourCounts = {
    'Carpenter': 0,
    'Mason': 0,
    'Electrician': 0,
    'Plumber': 0,
    'Painter': 0,
    'Helper': 0,
    'General': 0,
    'Tile Layer': 0,
    'Tile Layerhelper': 0,
    'Kambi Fitter': 0,
    'Concrete Kot': 0,
    'Pile Labour': 0,
  };

  // Rates loaded from admin global rates (single source of truth)
  Map<String, double> _rates = {};

  final _extraCostController = TextEditingController();
  final _extraCostNotesController = TextEditingController();
  bool _isSubmitting = false;
  late DateTime _selectedDateTime;

  @override
  void initState() {
    super.initState();
    _selectedDateTime = DateTime.now();
    _fetchRates();
  }

  Future<void> _fetchRates() async {
    final rates = await _budgetService.getLabourRates('global');
    if (rates.isNotEmpty && mounted) {
      final Map<String, double> loaded = {};
      for (final r in rates) {
        final type = r['labour_type'] as String?;
        final rate = (r['daily_rate'] as num?)?.toDouble();
        if (type != null && rate != null) loaded[type] = rate;
      }
      setState(() => _rates = loaded);
    }
  }

  int get _totalCount =>
      _labourCounts.values.fold(0, (sum, count) => sum + count);

  double get _totalSalary => _labourCounts.entries.fold(
    0,
    (sum, e) => sum + e.value * (_rates[e.key] ?? 0),
  );

  @override
  void dispose() {
    _extraCostController.dispose();
    _extraCostNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.r)),
      ),
      padding: EdgeInsets.only(
        left: 24.w,
        right: 24.w,
        top: 24.h,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '👷 Labor Entry',
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.deepNavy,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.orangeGradient,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Text(
                      'Workers: $_totalCount',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Text(
                      '₹${_totalSalary.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            widget.siteName,
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 16.h),

          SizedBox(
            height: 300.h,
            child: ListView(
              children: _labourCounts.keys
                  .map((type) => _buildLabourTypeRow(type))
                  .toList(),
            ),
          ),
          SizedBox(height: 16.h),

          // Extra Cost Section
          Container(
            padding: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.attach_money,
                      size: 20.sp,
                      color: Colors.orange.shade700,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Extra Cost (Optional)',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: _extraCostController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Enter amount (₹)',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: Colors.orange.shade200),
                    ),
                    prefixIcon: Icon(
                      Icons.currency_rupee,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                TextField(
                  controller: _extraCostNotesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Notes (e.g., transport, tools)',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: Colors.orange.shade200),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: _totalCount > 0 && !_isSubmitting ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.safetyOrange,
              padding: EdgeInsets.symmetric(vertical: 16.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            child: _isSubmitting
                ? SizedBox(
                    height: 20.h,
                    width: 20.w,
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Submit Labor Entry',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabourTypeRow(String type) {
    final count = _labourCounts[type]!;
    final icon = _getLabourIcon(type);
    final rate = _rates[type] ?? 0;
    final rowTotal = count * rate;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: count > 0
            ? AppColors.deepNavy.withValues(alpha: 0.05)
            : AppColors.lightSlate,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: count > 0
              ? AppColors.deepNavy.withValues(alpha: 0.2)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.h,
            decoration: BoxDecoration(
              color: count > 0 ? AppColors.deepNavy : AppColors.textSecondary,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: Colors.white, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: count > 0 ? FontWeight.bold : FontWeight.w500,
                    color: count > 0
                        ? AppColors.deepNavy
                        : AppColors.textSecondary,
                  ),
                ),
                Text(
                  count > 0
                      ? '₹${rate.toStringAsFixed(0)}/day × $count = ₹${rowTotal.toStringAsFixed(0)}'
                      : '₹${rate.toStringAsFixed(0)}/day',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: count > 0
                        ? Colors.green.shade700
                        : AppColors.textSecondary,
                    fontWeight: count > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _labourCounts[type] = (count - 1).clamp(0, 50),
                ),
                icon: Icon(Icons.remove_circle_outline, size: 32.sp),
                color: count > 0
                    ? AppColors.safetyOrange
                    : AppColors.textSecondary,
              ),
              Container(
                width: 50.w,
                height: 40.h,
                decoration: BoxDecoration(
                  gradient: count > 0 ? AppColors.orangeGradient : null,
                  color: count == 0 ? AppColors.lightSlate : null,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: count > 0 ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => _labourCounts[type] = (count + 1).clamp(0, 50),
                ),
                icon: Icon(Icons.add_circle_outline, size: 32.sp),
                color: AppColors.safetyOrange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getLabourIcon(String type) {
    switch (type) {
      case 'Carpenter':
        return Icons.carpenter;
      case 'Mason':
        return Icons.construction;
      case 'Electrician':
        return Icons.electrical_services;
      case 'Plumber':
        return Icons.plumbing;
      case 'Painter':
        return Icons.format_paint;
      case 'Helper':
        return Icons.handyman;
      case 'Tile Layer':
        return Icons.layers;
      case 'Tile Layerhelper':
        return Icons.layers_outlined;
      case 'Kambi Fitter':
        return Icons.build;
      case 'Concrete Kot':
        return Icons.foundation;
      case 'Pile Labour':
        return Icons.vertical_align_bottom;
      default:
        return Icons.person;
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    final extraCost = double.tryParse(_extraCostController.text.trim()) ?? 0;
    final extraCostNotes = _extraCostNotesController.text.trim();

    // Submit each labour type with count > 0
    for (final entry in _labourCounts.entries) {
      if (entry.value > 0) {
        await _constructionService.submitLabourCount(
          siteId: widget.siteId,
          labourCount: entry.value,
          labourType: entry.key,
          extraCost: extraCost > 0 ? extraCost : null,
          extraCostNotes: extraCostNotes.isNotEmpty ? extraCostNotes : null,
          customDateTime: _selectedDateTime,
        );
      }
    }

    setState(() => _isSubmitting = false);

    if (mounted) {
      Navigator.pop(context);
      widget.onSuccess();
    }
  }
}

// Summary Card Widget
class SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48.w,
            height: 48.h,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24.sp),
          ),
          SizedBox(height: 12.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            title,
            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
