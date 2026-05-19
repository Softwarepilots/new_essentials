import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/construction_service.dart';
import '../services/notification_service.dart';
import '../services/cache_service.dart';
import '../utils/smooth_animations.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_screen.dart';
import 'admin_labour_rates_screen.dart';
import 'admin_material_requirements_screen.dart';
import 'admin_budget_management_screen.dart';
import 'admin_client_complaints_screen.dart';
import 'admin_manage_users_screen.dart';
import 'admin_all_working_sites_screen.dart';
import 'admin_manage_materials_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _authService = AuthService();
  final _notificationService = NotificationService();
  int _selectedIndex = 0;
  
  // Background refresh timers
  Timer? _notificationsRefreshTimer;
  Timer? _sitesRefreshTimer;

  // Profile state
  Map<String, dynamic>? _currentAdminUser;
  String _profileName = 'Admin';
  String _profilePhone = '';

  // Sites tab state
  static const String _sitesBaseUrl = 'http://187.127.164.22/api';
  List<String> _areas = [];
  List<String> _streets = [];
  List<Map<String, dynamic>> _sites = [];
  String? _selectedArea;
  String? _selectedStreet;
  bool _sitesLoading = false;
  
  // Cache for streets and sites
  final Map<String, List<String>> _streetsCache = {};
  final Map<String, List<Map<String, dynamic>>> _sitesCache = {};

  // Notifications state
  List<Map<String, dynamic>> _notifications = [];
  bool _notificationsLoading = false;
  int _unreadCount = 0;
  bool _notificationsLoaded = false; // Cache flag

  // Guest visitors state
  List<Map<String, dynamic>> _guestVisitors = [];
  bool _guestVisitorsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAdminUser();
    _loadData();
    _loadAreas();
    _startBackgroundRefresh();
  }
  
  @override
  void dispose() {
    _stopBackgroundRefresh();
    super.dispose();
  }
  
  void _startBackgroundRefresh() {
    // Refresh notifications + guest visitors every 30 seconds
    _notificationsRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) {
        if (_selectedIndex == 2 && mounted) {
          _loadNotifications(forceRefresh: true);
          _loadGuestVisitors();
        }
      },
    );

    // Refresh sites data every 60 seconds
    _sitesRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (timer) {
        if (_selectedIndex == 1 && mounted) {
          // Silently refresh areas
          _loadAreas();
        }
      },
    );
  }
  
  void _stopBackgroundRefresh() {
    _notificationsRefreshTimer?.cancel();
    _sitesRefreshTimer?.cancel();
  }

  Future<void> _loadAdminUser() async {
    final user = await _authService.getCurrentUser();
    if (user != null && mounted) {
      setState(() {
        _currentAdminUser = user;
        _profileName = user['full_name'] ?? user['username'] ?? 'Admin';
        _profilePhone = user['phone'] ?? '';
      });
    }
  }
  
  void _loadData() {
    if (_selectedIndex == 2) {
      // Notifications tab — also refresh guests
      _loadNotifications();
      _loadGuestVisitors();
    }
  }

  static const _kGuestKey = 'guest_visitors_local';

  Future<void> _loadGuestVisitors() async {
    if (_guestVisitorsLoading) return;
    setState(() => _guestVisitorsLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kGuestKey);
      if (raw != null) {
        final list = List<Map<String, dynamic>>.from(
            (json.decode(raw) as List)
                .map((e) => Map<String, dynamic>.from(e as Map)));
        if (mounted) setState(() => _guestVisitors = list);
      }
    } catch (e) {
      debugPrint('Guest load error: $e');
    }
    if (mounted) setState(() => _guestVisitorsLoading = false);
  }

  Future<void> _clearGuestVisitors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGuestKey);
    if (mounted) setState(() => _guestVisitors = []);
  }

  Future<void> _loadNotifications({bool forceRefresh = false}) async {
    // Load from persistent cache first (instant display)
    if (!forceRefresh && !_notificationsLoaded) {
      final cached = await CacheService.loadNotifications();
      if (cached != null && mounted) {
        setState(() {
          _notifications = cached['notifications'];
          _unreadCount = cached['unread_count'];
          _notificationsLoaded = true;
        });
        print('✅ [NOTIFICATIONS] Loaded ${_notifications.length} from persistent cache');
      }
    }
    
    // Skip API call if already loaded and not forcing refresh
    if (_notificationsLoaded && !forceRefresh) return;
    
    setState(() => _notificationsLoading = true);

    try {
      print('🔍 [NOTIFICATIONS] Loading notifications from API...');
      final result = await _notificationService.getNotifications();
      
      print('🔍 [NOTIFICATIONS] Result: ${result['success']}');
      print('🔍 [NOTIFICATIONS] Notifications count: ${result['notifications']?.length ?? 0}');
      print('🔍 [NOTIFICATIONS] Unread count: ${result['unread_count']}');
      
      if (result['success'] == true && mounted) {
        final notifications = List<Map<String, dynamic>>.from(result['notifications'] ?? []);
        final unreadCount = result['unread_count'] ?? 0;
        
        // Save to persistent cache
        await CacheService.saveNotifications(notifications, unreadCount);
        
        setState(() {
          _notifications = notifications;
          _unreadCount = unreadCount;
          _notificationsLoaded = true;
        });
        
        print('✅ [NOTIFICATIONS] Loaded ${_notifications.length} notifications and saved to cache');
      } else {
        print('❌ [NOTIFICATIONS] Error: ${result['error']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['error'] ?? 'Failed to load notifications'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [NOTIFICATIONS] Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading notifications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _notificationsLoading = false);
      }
    }
  }

  Future<void> _markNotificationAsRead(String notificationId) async {
    try {
      final result = await _notificationService.markAsRead(notificationId);
      
      if (result['success'] == true) {
        _loadNotifications(forceRefresh: true); // Refresh list
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllNotificationsAsRead() async {
    try {
      final result = await _notificationService.markAllAsRead();
      
      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read'),
            backgroundColor: Colors.green,
          ),
        );
        _loadNotifications(forceRefresh: true); // Refresh list
      }
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Sign Out',
          style: TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: const Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF44336),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          _getAppBarTitle(),
          style: const TextStyle(
            color:  Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Color(0xFF16213E),
        elevation: 0,
        // actions: [
        //   // Notification badge
        //   IconButton(
        //     icon: const Icon(Icons.notifications_outlined, color: const Color(0xFF1A1A2E)),
        //     onPressed: () {
        //       setState(() => _selectedIndex = 1);
        //     },
        //   ),
        //   // Logout button
        //   IconButton(
        //     icon: const Icon(Icons.logout, color: const Color(0xFF1A1A2E)),
        //     onPressed: _logout,
        //     tooltip: 'Sign Out',
        //   ),
        // ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    const items = [
      _NavItem(Icons.auto_stories_outlined, Icons.auto_stories, 'Story'),
      _NavItem(Icons.location_city_outlined, Icons.location_city, 'Sites'),
      _NavItem(Icons.notifications_outlined, Icons.notifications, 'Alerts'),
      _NavItem(Icons.report_problem_outlined, Icons.report_problem, 'Issues'),
      _NavItem(Icons.person_outline, Icons.person, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final selected = _selectedIndex == i;
              final item = items[i];
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedIndex = i;
                  _loadData();
                }),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.symmetric(
                    horizontal: selected ? 18 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: selected ? LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF1A1A2E).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Badge dot for Alerts tab
                      Icon(
                        selected ? item.activeIcon : item.icon,
                        color: selected ? Colors.white : const Color(0xFF6B7280),
                        size: 22,
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return ' Site Story';
      case 1:
        return 'Site Management';
      case 2:
        return 'Notifications';
      case 3:
        return 'Client Issues';
      case 4:
        return 'Profile';
      default:
        return 'Admin Dashboard';
    }
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        const _AdminStoryTab(),
        _buildSitesTab(),
        _buildNotificationsTab(),
        const AdminClientComplaintsScreen(),
        _buildProfileTab(),
      ],
    );
  }

  Future<void> _loadAreas() async {
    setState(() => _sitesLoading = true);
    try {
      final token = await _authService.getToken();
      print('🔍 Loading areas from: $_sitesBaseUrl/construction/areas/');
      final res = await http.get(
        Uri.parse('$_sitesBaseUrl/construction/areas/'),
        headers: {'Authorization': 'Bearer ${token ?? ''}'},
      );
      print('🔍 Areas response status: ${res.statusCode}');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        print('🔍 Areas data: $data');
        if (mounted) {
          setState(() {
            _areas = List<String>.from(data['areas'] ?? []);
          });
        }
        print('🔍 Loaded ${_areas.length} areas');
      } else {
        print('❌ Failed to load areas: ${res.statusCode} - ${res.body}');
      }
    } catch (e) {
      print('❌ Error loading areas: $e');
    }
    if (mounted) setState(() => _sitesLoading = false);
  }

  Future<void> _loadStreets(String area) async {
    // Always clear sites and selected street when area changes
    setState(() {
      _sites = [];
      _selectedStreet = null;
    });
    
    // Check cache first
    if (_streetsCache.containsKey(area)) {
      setState(() {
        _streets = _streetsCache[area]!;
      });
      return;
    }
    
    setState(() {
      _sitesLoading = true;
      _streets = [];
    });
    try {
      final token = await _authService.getToken();
      final res = await http.get(
        Uri.parse('$_sitesBaseUrl/construction/streets/${Uri.encodeComponent(area)}/'),
        headers: {'Authorization': 'Bearer ${token ?? ''}'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final streets = List<String>.from(data['streets'] ?? []);
        // Cache the streets
        _streetsCache[area] = streets;
        if (mounted) {
          setState(() {
            _streets = streets;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading streets: $e');
    }
    if (mounted) setState(() => _sitesLoading = false);
  }

  Future<void> _loadSites(String area, String street) async {
    // Create cache key
    final cacheKey = '$area|$street';
    
    // Check cache first
    if (_sitesCache.containsKey(cacheKey)) {
      setState(() {
        _sites = _sitesCache[cacheKey]!;
      });
      return;
    }
    
    setState(() {
      _sitesLoading = true;
      _sites = [];
    });
    try {
      final token = await _authService.getToken();
      final res = await http.get(
        Uri.parse(
            '$_sitesBaseUrl/construction/sites/?area=${Uri.encodeComponent(area)}&street=${Uri.encodeComponent(street)}'),
        headers: {'Authorization': 'Bearer ${token ?? ''}'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final sites = List<Map<String, dynamic>>.from(data['sites'] ?? []);
        // Cache the sites
        _sitesCache[cacheKey] = sites;
        if (mounted) {
          setState(() {
            _sites = sites;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading sites: $e');
    }
    if (mounted) setState(() => _sitesLoading = false);
  }

  Widget _buildGridCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.82)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSitesTab() {
    return SingleChildScrollView(
      physics: const SmoothScrollPhysics(),
      child: Column(
        children: [
        // 2×2 Quick Action Grid
        Container(
        
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              _buildGridCard(
                label: 'Labour Rates',
                subtitle: 'Set default rates',
                icon: Icons.currency_rupee,
                color: const Color(0xFF1A1A2E),
                onTap: () => Navigator.push(
                  context,
                  SmoothPageRoute(page: const AdminLabourRatesScreen()),
                ),
              ),
              _buildGridCard(
                label: 'Material\nRequirements',
                subtitle: 'Supervisor requests',
                icon: Icons.inventory_2,
                color: const Color(0xFF1E3A8A),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminMaterialRequirementsScreen()),
                ),
              ),
              _buildGridCard(
                label: 'All Working\nSites',
                subtitle: 'Accountant updates',
                icon: Icons.construction,
                color: const Color(0xFF059669),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminAllWorkingSitesScreen()),
                ),
              ),
              _buildGridCard(
                label: 'Manage\nMaterials',
                subtitle: 'Add & edit materials',
                icon: Icons.category,
                color: const Color(0xFFD97706),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminManageMaterialsScreen()),
                ),
              ),
            ],
          ),
        ),
        // Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Site Budget Management',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E))),
              const SizedBox(height: 12),
              // Area dropdown
              DropdownButtonFormField<String>(
                value: _selectedArea,
                decoration: InputDecoration(
                  labelText: 'Select Area',
                  prefixIcon: const Icon(Icons.location_city,
                      color: const Color(0xFF1A1A2E), size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                items: _areas
                    .map((a) =>
                        DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedArea = val);
                    _loadStreets(val);
                  }
                },
                hint: const Text('Choose area'),
              ),
              if (_streets.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedStreet,
                  decoration: InputDecoration(
                    labelText: 'Select Street',
                    prefixIcon: const Icon(Icons.streetview,
                        color: const Color(0xFF1A1A2E), size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: _streets
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null && _selectedArea != null) {
                      setState(() => _selectedStreet = val);
                      _loadSites(_selectedArea!, val);
                    }
                  },
                  hint: const Text('Choose street'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        // Site list
        if (_sitesLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF1A1A2E)),
            ),
          )
        else if (_selectedArea == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_outlined,
                    size: 60,
                    color: const Color(0xFF6B7280).withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text('Select an area to view sites',
                    style: TextStyle(color: const Color(0xFF6B7280), fontSize: 14)),
              ],
            ),
          )
        else if (_selectedStreet == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text('Select a street to view sites',
                style: TextStyle(color: const Color(0xFF6B7280), fontSize: 14)),
          )
        else if (_sites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text('No sites found',
                style: TextStyle(color: const Color(0xFF6B7280), fontSize: 14)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            itemCount: _sites.length,
            itemBuilder: (context, i) {
              return AnimatedListItem(
                index: i,
                child: _buildSiteManagementCard(_sites[i], i),
              );
            },
          ),
        ],
      ),
    );
  }

  static const _cardColors = [
    Color(0xFF1A1A2E),
    Color(0xFF1E3A8A),
    Color(0xFF059669),
    Color(0xFFD97706),
  ];

  Widget _buildSiteManagementCard(Map<String, dynamic> site, int index) {
    final siteId = site['id']?.toString() ?? '';
    final siteName = site['display_name'] as String? ??
        site['site_name'] as String? ??
        'Site ${index + 1}';
    final clientName = site['client_name'] as String? ?? '';
    final area = site['area'] as String? ?? _selectedArea ?? '';
    final street = site['street'] as String? ?? _selectedStreet ?? '';
    final color = _cardColors[index % _cardColors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Gradient header (matches grid cards above)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.82)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.apartment,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (clientName.isNotEmpty) ...[
                            const Icon(Icons.person_outline,
                                size: 12, color: Colors.white70),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                clientName,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (area.isNotEmpty) ...[
                            const Icon(Icons.location_on_outlined,
                                size: 12, color: Colors.white70),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                street.isNotEmpty ? '$area · $street' : area,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Budget Management action row
          Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                SmoothPageRoute(
                  page: AdminBudgetManagementScreen(
                    siteId: siteId,
                    siteName: siteName,
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 13, horizontal: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.10),
                      color.withValues(alpha: 0.04),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: color.withValues(alpha: 0.20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                          Icons.account_balance_wallet_outlined,
                          color: color,
                          size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Budget Management',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Allocation · Utilization · Bills',
                            style: TextStyle(
                              color: color.withValues(alpha: 0.65),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 14, color: color.withValues(alpha: 0.45)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab() {
    // Split notifications: Labour vs Photos+Material vs Site Requirements
    final labourNotifications = _notifications.where((n) =>
      n['entry_type'] == 'labour'
    ).toList();

    final photosAndMaterialNotifications = _notifications.where((n) =>
      n['entry_type'] == 'morning_photo' ||
      n['entry_type'] == 'evening_photo' ||
      n['entry_type'] == 'material'
    ).toList();

    final siteRequirementNotifications = _notifications.where((n) =>
      n['entry_type'] == 'Site Requirement'
    ).toList();

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          // Header with actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                if (_unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    _loadNotifications(forceRefresh: true);
                    _loadGuestVisitors();
                  },
                  tooltip: 'Refresh',
                ),
                if (_unreadCount > 0)
                  TextButton.icon(
                    onPressed: _markAllNotificationsAsRead,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Mark all read'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A2E),
                    ),
                  ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: const Color(0xFF1A1A2E),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF1A1A2E),
              indicatorWeight: 3,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.people, size: 18),
                      const SizedBox(width: 6),
                      Text('Labour (${labourNotifications.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.photo_camera, size: 18),
                      const SizedBox(width: 6),
                      Text('Photos (${photosAndMaterialNotifications.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.assignment, size: 18),
                      const SizedBox(width: 6),
                      Text('Requirements (${siteRequirementNotifications.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.person_add_alt_1, size: 18),
                      const SizedBox(width: 6),
                      Text('Guests (${_guestVisitors.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: _notificationsLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF1A1A2E)),
                  )
                : TabBarView(
                    children: [
                      _buildNotificationsList(labourNotifications, 'labour'),
                      _buildNotificationsList(photosAndMaterialNotifications, 'photos_material'),
                      _buildNotificationsList(siteRequirementNotifications, 'site_requirement'),
                      _buildGuestVisitorsList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestVisitorsList() {
    if (_guestVisitorsLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A1A2E)));
    }

    if (_guestVisitors.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadGuestVisitors,
        color: const Color(0xFF1A1A2E),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: 300,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_alt_1,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text('No guest check-ins yet',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E))),
                const SizedBox(height: 8),
                Text('Guests who check in will appear here.',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ),
      );
    }

    final visitors = _guestVisitors;
    final newCount = visitors.where((v) => v['is_new'] == true).length;

    return RefreshIndicator(
      onRefresh: _loadGuestVisitors,
      color: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          // ── Header bar with new-badge and clear button ──────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.person_add_alt_1,
                    size: 18, color: Color(0xFF1A1A2E)),
                const SizedBox(width: 8),
                Text('${visitors.length} visitor${visitors.length == 1 ? '' : 's'} today',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1A1A2E))),
                if (newCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('$newCount NEW',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: _clearGuestVisitors,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Clear all'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      textStyle: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          // ── List ─────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: visitors.length,
              itemBuilder: (context, i) {
                final v = visitors[i];
          final name = v['name'] as String? ?? 'Guest';
          final phone = v['phone'] as String? ?? '—';
          final purpose = v['purpose'] as String? ?? '';
          final visitTime = v['visit_time'] as String? ??
              v['created_at'] as String? ?? '';
          final timeStr = visitTime.length >= 16
              ? visitTime.substring(0, 16).replaceAll('T', '  ')
              : visitTime;
          final ref = v['ref'] as String? ?? 'GV${(1000 + i)}';
          final isNew = v['is_new'] == true;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A1A2E).withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A1A2E), Color(0xFF3B82F6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'G',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF1A1A2E))),
                            ),
                            if (isNew)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Text('NEW',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(ref,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF059669))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined,
                                size: 13, color: Color(0xFF6B7280)),
                            const SizedBox(width: 4),
                            Text(phone,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF6B7280))),
                          ],
                        ),
                        if (purpose.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.notes_outlined,
                                  size: 13, color: Color(0xFF6B7280)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(purpose,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ],
                        if (timeStr.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 13, color: Color(0xFF6B7280)),
                              const SizedBox(width: 4),
                              Text(timeStr,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF6B7280))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList(List<Map<String, dynamic>> notifications, String type) {
    if (notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadNotifications(forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - 300,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          type == 'labour' ? Colors.blue : type == 'site_requirement' ? Colors.purple : Colors.orange,
                          type == 'labour' ? Colors.blue.shade700 : type == 'site_requirement' ? Colors.purple.shade700 : Colors.orange.shade700,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      type == 'labour' ? Icons.people : type == 'site_requirement' ? Icons.assignment : Icons.photo_camera,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    type == 'labour' ? 'No Labour Notifications' : type == 'site_requirement' ? 'No Site Requirement Notifications' : 'No Photo or Material Notifications',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    type == 'labour'
                        ? 'Labour entry notifications\nwill appear here'
                        : type == 'site_requirement'
                        ? 'Site requirement notifications\nwill appear here'
                        : 'Photo and material balance\nnotifications will appear here',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadNotifications(forceRefresh: true),
      color: const Color(0xFF1A1A2E),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return AnimatedListItem(
            index: index,
            child: _buildNotificationCard(notification),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['is_read'] == true;
    final message = notification['message'] ?? 'No message';
    final createdAt = notification['created_at'] ?? '';
    final siteName = notification['site_name'] ?? 'Unknown Site';
    final supervisorName = notification['supervisor_name'] ?? 'Unknown Supervisor';
    final entryType = notification['entry_type'] ?? '';
    final actualTime = notification['actual_time'] ?? '';
    
    // Parse entry type for display
    String entryTypeDisplay = '';
    IconData entryIcon = Icons.warning;
    Color entryColor = Colors.orange;
    
    switch (entryType) {
      case 'labour':
        entryTypeDisplay = 'Labour Entry';
        entryIcon = Icons.people;
        entryColor = Colors.blue;
        break;
      case 'material':
        entryTypeDisplay = 'Material Balance';
        entryIcon = Icons.inventory_2;
        entryColor = Colors.green;
        break;
      case 'morning_photo':
        entryTypeDisplay = 'Morning Photo';
        entryIcon = Icons.wb_sunny;
        entryColor = Colors.amber;
        break;
      case 'evening_photo':
        entryTypeDisplay = 'Evening Photo';
        entryIcon = Icons.nights_stay;
        entryColor = Colors.indigo;
        break;
      case 'Site Requirement':
        entryTypeDisplay = 'Site Requirement';
        entryIcon = Icons.assignment;
        entryColor = Colors.purple;
        break;
      default:
        entryTypeDisplay = 'Late Entry';
        entryIcon = Icons.access_time;
        entryColor = Colors.red;
    }

    // Parse timestamp
    String timeAgo = '';
    try {
      final timestamp = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(timestamp);
      
      if (difference.inMinutes < 1) {
        timeAgo = 'Just now';
      } else if (difference.inMinutes < 60) {
        timeAgo = '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        timeAgo = '${difference.inHours}h ago';
      } else {
        timeAgo = '${difference.inDays}d ago';
      }
    } catch (e) {
      timeAgo = createdAt;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isRead ? 0 : 2,
      color: isRead ? const Color(0xFFF8F9FA) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRead ? Colors.transparent : entryColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (!isRead) {
            _markNotificationAsRead(notification['id'].toString());
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: entryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      entryIcon,
                      color: entryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              entryTypeDisplay,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: entryColor,
                              ),
                            ),
                            if (!isRead) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeAgo,
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      siteName,
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 16,
                    color: const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      supervisorName,
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ),
              if (actualTime.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: const Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Submitted at: $actualTime',
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PROFILE TAB
  // ============================================================

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── Avatar + name ──
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A1A2E).withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _profileName.isNotEmpty
                          ? _profileName.substring(0, 1).toUpperCase()
                          : 'A',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _profileName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'ADMIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildProfileInfoRow(Icons.email_outlined,
                    _currentAdminUser?['email'] ?? 'N/A'),
                const SizedBox(height: 8),
                _buildProfileInfoRow(Icons.phone_outlined,
                    _profilePhone.isNotEmpty ? _profilePhone : 'N/A'),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Account Settings ──
          _buildSectionHeader('Account'),
          _buildProfileActionTile(
            icon: Icons.edit_outlined,
            color: const Color(0xFF1A1A2E),
            title: 'Edit Profile',
            subtitle: 'Update name and phone',
            onTap: _showEditProfileDialog,
          ),

          const SizedBox(height: 20),

          // ── Management ──
          _buildSectionHeader('Management'),
          _buildProfileActionTile(
            icon: Icons.people_outline,
            color: const Color(0xFF4CAF50),
            title: 'Manage Users',
            subtitle: 'View all users and pending requests',
            onTap: _showManageUsersScreen,
          ),
          _buildProfileActionTile(
            icon: Icons.add_location_alt_outlined,
            color: const Color(0xFF1A1A2E),
            title: 'Create Site',
            subtitle: 'Add new area, street, and site',
            onTap: _showCreateSiteDialog,
          ),
          _buildProfileActionTile(
            icon: Icons.person_add_outlined,
            color: const Color(0xFF2196F3),
            title: 'Create User',
            subtitle: 'Add Supervisor, Engineer, Accountant etc.',
            onTap: _showCreateUserDialog,
          ),
          _buildProfileActionTile(
            icon: Icons.admin_panel_settings_outlined,
            color: const Color(0xFF1A1A2E),
            title: 'Create Admin',
            subtitle: 'Add another admin account',
            onTap: _showCreateAdminDialog,
          ),
          _buildProfileActionTile(
            icon: Icons.badge_outlined,
            color: const Color(0xFF9C27B0),
            title: 'Create Role',
            subtitle: 'Add a new custom role',
            onTap: _showCreateRoleDialog,
          ),

          const SizedBox(height: 20),

          // ── Logout ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF44336),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF6B7280),
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoRow(IconData icon, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(fontSize: 14, color: const Color(0xFF6B7280))),
      ],
    );
  }

  Widget _buildProfileActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A1A2E).withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: const Color(0xFF6B7280))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: const Color(0xFF6B7280), size: 16),
          ],
        ),
      ),
    );
  }

  // ── Edit Profile ──────────────────────────────────────────

  Future<void> _showEditProfileDialog() async {
    final nameCtrl = TextEditingController(text: _profileName);
    final phoneCtrl = TextEditingController(text: _profilePhone);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Profile',
              style: TextStyle(
                  color: const Color(0xFF1A1A2E), fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: const Icon(Icons.person_outline,
                        color: const Color(0xFF1A1A2E)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: const Color(0xFF1A1A2E), width: 2),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    counterText: '',
                    prefixIcon: const Icon(Icons.phone_outlined,
                        color: const Color(0xFF1A1A2E)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: const Color(0xFF1A1A2E), width: 2),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Phone is required';
                    if (v.trim().length != 10)
                      return 'Must be exactly 10 digits';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: const Color(0xFF6B7280))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDS(() => isSaving = true);
                      final newName = nameCtrl.text.trim();
                      final newPhone = phoneCtrl.text.trim();
                      final result = await ConstructionService().updateProfile(
                          fullName: newName, phone: newPhone);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (result['success'] == true) {
                        setState(() {
                          _profileName =
                              newName.isNotEmpty ? newName : _profileName;
                          _profilePhone =
                              newPhone.isNotEmpty ? newPhone : _profilePhone;
                        });
                      }
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(result['success'] == true
                            ? 'Profile updated!'
                            : result['error'] ?? 'Update failed'),
                        backgroundColor: result['success'] == true
                            ? const Color(0xFF4CAF50)
                            : Colors.red,
                      ));
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

  // ── Manage Users ──────────────────────────────────────────

  void _showManageUsersScreen() {
    Navigator.push(
      context,
      SmoothPageRoute(
        page: const AdminManageUsersScreen(),
      ),
    );
  }

  // ── Create Site ───────────────────────────────────────────

  Future<void> _showCreateSiteDialog() async {
    final customerNameCtrl = TextEditingController();
    final siteNameCtrl = TextEditingController();
    final newAreaCtrl = TextEditingController();
    final newStreetCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    
    String? selectedArea;
    String? selectedStreet;
    bool isCreatingNewArea = false;
    bool isCreatingNewStreet = false;
    List<String> availableStreets = [];

    // Load existing areas
    await _loadAreas();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Create Site',
              style: TextStyle(
                  color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer Name
                    _dialogField(customerNameCtrl, 'Customer Name', Icons.person,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null),
                    const SizedBox(height: 12),
                    
                    // Site Name
                    _dialogField(siteNameCtrl, 'Site Name', Icons.apartment,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null),
                    const SizedBox(height: 12),
                    
                    // Area Dropdown or Text Field
                    const Text('Area', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (!isCreatingNewArea)
                      DropdownButtonFormField<String>(
                        value: selectedArea,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.location_city),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          ..._areas.map((area) => DropdownMenuItem(
                                value: area,
                                child: Text(area),
                              )),
                          const DropdownMenuItem(
                            value: '__CREATE_NEW__',
                            child: Row(
                              children: [
                                Icon(Icons.add_circle, color: Color(0xFF4CAF50), size: 20),
                                SizedBox(width: 8),
                                Text('Create New Area', style: TextStyle(color: Color(0xFF4CAF50))),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value == '__CREATE_NEW__') {
                            setDS(() {
                              isCreatingNewArea = true;
                              selectedArea = null;
                            });
                          } else {
                            setDS(() {
                              selectedArea = value;
                              selectedStreet = null;
                              isCreatingNewStreet = false;
                            });
                            // Load streets for selected area
                            if (value != null) {
                              final token = await _authService.getToken();
                              final res = await http.get(
                                Uri.parse('$_sitesBaseUrl/construction/streets/${Uri.encodeComponent(value)}/'),
                                headers: {'Authorization': 'Bearer ${token ?? ''}'},
                              );
                              if (res.statusCode == 200) {
                                final data = json.decode(res.body);
                                setDS(() {
                                  availableStreets = List<String>.from(data['streets'] ?? []);
                                });
                              }
                            }
                          }
                        },
                        validator: (v) => v == null ? 'Please select an area' : null,
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _dialogField(newAreaCtrl, 'New Area Name', Icons.location_city,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setDS(() {
                                isCreatingNewArea = false;
                                newAreaCtrl.clear();
                              });
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    
                    // Street Dropdown or Text Field
                    const Text('Street', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (!isCreatingNewStreet)
                      DropdownButtonFormField<String>(
                        value: selectedStreet,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.streetview),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          ...availableStreets.map((street) => DropdownMenuItem(
                                value: street,
                                child: Text(street),
                              )),
                          const DropdownMenuItem(
                            value: '__CREATE_NEW__',
                            child: Row(
                              children: [
                                Icon(Icons.add_circle, color: Color(0xFF4CAF50), size: 20),
                                SizedBox(width: 8),
                                Text('Create New Street', style: TextStyle(color: Color(0xFF4CAF50))),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == '__CREATE_NEW__') {
                            setDS(() {
                              isCreatingNewStreet = true;
                              selectedStreet = null;
                            });
                          } else {
                            setDS(() => selectedStreet = value);
                          }
                        },
                        validator: (v) => v == null ? 'Please select a street' : null,
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _dialogField(newStreetCtrl, 'New Street Name', Icons.streetview,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setDS(() {
                                isCreatingNewStreet = false;
                                newStreetCtrl.clear();
                              });
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      
                      // Determine final area and street values
                      final finalArea = isCreatingNewArea ? newAreaCtrl.text.trim() : selectedArea;
                      final finalStreet = isCreatingNewStreet ? newStreetCtrl.text.trim() : selectedStreet;
                      
                      if (finalArea == null || finalArea.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Please select or create an area')),
                        );
                        return;
                      }
                      
                      if (finalStreet == null || finalStreet.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Please select or create a street')),
                        );
                        return;
                      }
                      
                      setDS(() => isSaving = true);
                      
                      try {
                        final token = await _authService.getToken();
                        final response = await http.post(
                          Uri.parse('$_sitesBaseUrl/construction/create-site/'),
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer ${token ?? ''}',
                          },
                          body: json.encode({
                            'customer_name': customerNameCtrl.text.trim(),
                            'site_name': siteNameCtrl.text.trim(),
                            'area': finalArea,
                            'street': finalStreet,
                          }),
                        );

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);

                        if (response.statusCode == 201) {
                          final responseData = json.decode(response.body);
                          
                          // Clear all caches
                          await CacheService.clearSites();
                          _streetsCache.clear();
                          _sitesCache.clear();
                          
                          // Reload areas first
                          await _loadAreas();
                          
                          // Auto-select the area and load streets
                          setState(() {
                            _selectedArea = finalArea;
                            _selectedStreet = null;
                            _streets = [];
                            _sites = [];
                          });
                          
                          // Load streets for the area
                          await _loadStreets(finalArea);
                          
                          // Auto-select the street and load sites
                          setState(() {
                            _selectedStreet = finalStreet;
                          });
                          
                          // Load sites for the area/street
                          await _loadSites(finalArea, finalStreet);
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Site created successfully! ${responseData['site']['display_name']}'),
                              backgroundColor: const Color(0xFF4CAF50),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        } else {
                          final error = json.decode(response.body);
                          throw Exception(error['error'] ?? 'Failed to create site');
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDS(() => isSaving = false);
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
    customerNameCtrl.dispose();
    siteNameCtrl.dispose();
    newAreaCtrl.dispose();
    newStreetCtrl.dispose();
  }

  // ── Create User ───────────────────────────────────────────

  Future<void> _showCreateUserDialog() async {
    final nameCtrl     = TextEditingController();
    final usernameCtrl = TextEditingController();
    final emailCtrl    = TextEditingController();
    final phoneCtrl    = TextEditingController();
    final passCtrl     = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedRole;
    List<String> roles = [];
    List<Map<String, dynamic>> allSites = [];
    Set<String> selectedSiteIds = {};
    bool isSaving = false;
    bool loadingRoles = true;
    bool loadingSites = false;

    // Load roles
    try {
      final token = await _authService.getToken();
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/admin/roles/'),
        headers: {'Authorization': 'Bearer ${token ?? ''}'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        roles = List<Map<String, dynamic>>.from(data['roles'])
            .map((r) => r['role_name'] as String)
            .where((r) => r != 'Admin')
            .toList();
      }
    } catch (_) {}

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing while saving
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {
          if (loadingRoles) {
            loadingRoles = false;
            if (roles.isNotEmpty) selectedRole = roles.first;
          }
          
          // Check if Client role is selected
          final isClientRole = selectedRole?.toLowerCase() == 'client';
          
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Create User',
                style: TextStyle(
                    color: Color(0xFF2196F3),
                    fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogField(nameCtrl, 'Full Name', Icons.person_outline,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null),
                    const SizedBox(height: 12),
                    _dialogField(usernameCtrl, 'Username', Icons.alternate_email,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null),
                    const SizedBox(height: 12),
                    _dialogField(emailCtrl, 'Email', Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Valid email required'
                            : null),
                    const SizedBox(height: 12),
                    _dialogField(phoneCtrl, 'Phone', Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: (v) => (v == null || v.trim().length != 10)
                            ? '10 digits required'
                            : null),
                    const SizedBox(height: 12),
                    _dialogField(passCtrl, 'Password', Icons.lock_outline,
                        obscureText: true,
                        validator: (v) =>
                            (v == null || v.length < 6)
                                ? 'Min 6 characters'
                                : null),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: InputDecoration(
                        labelText: 'Role',
                        prefixIcon: const Icon(Icons.badge_outlined,
                            color: Color(0xFF2196F3)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                      items: roles
                          .map((r) => DropdownMenuItem(
                              value: r, child: Text(r)))
                          .toList(),
                      onChanged: (v) async {
                        print('🎯 ROLE CHANGED TO: $v');
                        setDS(() => selectedRole = v);
                        
                        // Load sites if Client role is selected
                        final isClient = v?.toLowerCase() == 'client';
                        print('🎯 Is client role: $isClient');
                        print('🎯 All sites count: ${allSites.length}');
                        print('🎯 Loading sites: $loadingSites');
                        
                        if (isClient && allSites.isEmpty) {
                          print('🎯 Starting to load sites...');
                          setDS(() => loadingSites = true);
                          try {
                            final token = await _authService.getToken();
                            final url = '${AuthService.baseUrl}/construction/all-sites/';
                            print('🎯 Fetching from: $url');
                            
                            final res = await http.get(
                              Uri.parse(url),
                              headers: {
                                'Authorization': 'Bearer ${token ?? ''}',
                                'Content-Type': 'application/json',
                              },
                            );
                            
                            print('🎯 Response: ${res.statusCode}');
                            
                            if (res.statusCode == 200) {
                              final data = json.decode(res.body);
                              final sites = List<Map<String, dynamic>>.from(data['sites'] ?? []);
                              print('🎯 ✅ Loaded ${sites.length} sites');
                              
                              setDS(() {
                                allSites = sites;
                                loadingSites = false;
                              });
                              print('🎯 State updated - allSites now has ${allSites.length} items');
                            } else {
                              print('🎯 ❌ Failed: ${res.statusCode}');
                              setDS(() => loadingSites = false);
                            }
                          } catch (e) {
                            print('🎯 ❌ Error: $e');
                            setDS(() => loadingSites = false);
                          }
                        }
                      },
                      validator: (v) =>
                          v == null ? 'Select a role' : null,
                    ),
                    
                    // Show site selection for Client role
                    if (isClientRole) ...[
                      Builder(
                        builder: (context) {
                          print('🎯 RENDERING SITE SELECTION UI');
                          print('🎯 isClientRole: $isClientRole');
                          print('🎯 loadingSites: $loadingSites');
                          print('🎯 allSites.length: ${allSites.length}');
                          return Column(
                            children: [
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.location_city, color: Color(0xFF2196F3), size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Assign Site(s)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2196F3),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Client will only see assigned site(s)',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              
                              if (loadingSites)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (allSites.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text('No sites available', style: TextStyle(color: Colors.grey)),
                                )
                              else
                                Container(
                                  constraints: const BoxConstraints(maxHeight: 200),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: allSites.length,
                                    itemBuilder: (context, index) {
                                      final site = allSites[index];
                                      final siteId = site['id'].toString();
                                      final isSelected = selectedSiteIds.contains(siteId);
                                      
                                      return CheckboxListTile(
                                        dense: true,
                                        value: isSelected,
                                        onChanged: (value) {
                                          setDS(() {
                                            if (value == true) {
                                              selectedSiteIds.add(siteId);
                                            } else {
                                              selectedSiteIds.remove(siteId);
                                            }
                                          });
                                        },
                                        title: Text(
                                          site['display_name'] ?? site['site_name'] ?? 'Site',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        controlAffinity: ListTileControlAffinity.leading,
                                      );
                                    },
                                  ),
                                ),
                              
                              if (isClientRole && selectedSiteIds.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    '⚠️ Please select at least one site',
                                    style: TextStyle(color: Colors.orange, fontSize: 12),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ), // Column
              ), // Form
            ), // SingleChildScrollView
            ), // SizedBox
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text('Cancel',
                    style:
                        TextStyle(color: const Color(0xFF6B7280))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        
                        // Validate site selection for Client role
                        if (isClientRole && selectedSiteIds.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select at least one site for the client'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        
                        setDS(() => isSaving = true);
                        try {
                          final token = await _authService.getToken();
                          final Map<String, dynamic> body = {
                            'full_name': nameCtrl.text.trim(),
                            'username': usernameCtrl.text.trim(),
                            'email': emailCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                            'password': passCtrl.text,
                            'role': selectedRole,
                          };
                          
                          // Add site_ids for Client role
                          if (isClientRole) {
                            body['site_ids'] = selectedSiteIds.toList();
                          }
                          
                          final res = await http.post(
                            Uri.parse(
                                '${AuthService.baseUrl}/admin/create-user/'),
                            headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer ${token ?? ''}',
                            },
                            body: json.encode(body),
                          );
                          
                          final data = json.decode(res.body);
                          final success = res.statusCode == 201;
                          final message = success 
                              ? (data['message'] ?? 'User created!')
                              : (data['error'] ?? 'Failed');
                          
                          if (!ctx.mounted) return;
                          
                          // Close dialog first
                          Navigator.pop(ctx);
                          
                          // Then show snackbar
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(success ? '✅ $message' : '❌ $message'),
                              backgroundColor: success
                                  ? const Color(0xFF4CAF50)
                                  : Colors.red,
                            ));
                          }
                        } catch (e) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ));
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
    nameCtrl.dispose();
    usernameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    passCtrl.dispose();
  }

  // ── Create Admin ──────────────────────────────────────────

  Future<void> _showCreateAdminDialog() async {
    final nameCtrl     = TextEditingController();
    final usernameCtrl = TextEditingController();
    final emailCtrl    = TextEditingController();
    final phoneCtrl    = TextEditingController();
    final passCtrl     = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Create Admin',
              style: TextStyle(
                  color: const Color(0xFF1A1A2E),
                  fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(nameCtrl, 'Full Name', Icons.person_outline,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 12),
                  _dialogField(
                      usernameCtrl, 'Username', Icons.alternate_email,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 12),
                  _dialogField(emailCtrl, 'Email', Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Valid email required'
                          : null),
                  const SizedBox(height: 12),
                  _dialogField(phoneCtrl, 'Phone', Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      validator: (v) =>
                          (v == null || v.trim().length != 10)
                              ? '10 digits required'
                              : null),
                  const SizedBox(height: 12),
                  _dialogField(passCtrl, 'Password', Icons.lock_outline,
                      obscureText: true,
                      validator: (v) =>
                          (v == null || v.length < 6)
                              ? 'Min 6 characters'
                              : null),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: const Color(0xFF6B7280))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDS(() => isSaving = true);
                      try {
                        final token = await _authService.getToken();
                        final res = await http.post(
                          Uri.parse(
                              '${AuthService.baseUrl}/admin/create-admin/'),
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer ${token ?? ''}',
                          },
                          body: json.encode({
                            'full_name': nameCtrl.text.trim(),
                            'username': usernameCtrl.text.trim(),
                            'email': emailCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                            'password': passCtrl.text,
                          }),
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        final data = json.decode(res.body);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(res.statusCode == 201
                              ? data['message'] ?? 'Admin created!'
                              : data['error'] ?? 'Failed'),
                          backgroundColor: res.statusCode == 201
                              ? const Color(0xFF4CAF50)
                              : Colors.red,
                        ));
                      } catch (e) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    usernameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    passCtrl.dispose();
  }

  // ── Create Role ───────────────────────────────────────────

  Future<void> _showCreateRoleDialog() async {
    final roleCtrl = TextEditingController();
    final formKey  = GlobalKey<FormState>();
    bool isSaving  = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Create Role',
              style: TextStyle(
                  color: Color(0xFF9C27B0),
                  fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: roleCtrl,
              decoration: InputDecoration(
                labelText: 'Role Name',
                hintText: 'e.g. Quality Inspector',
                prefixIcon: const Icon(Icons.badge_outlined,
                    color: Color(0xFF9C27B0)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF9C27B0), width: 2),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Role name is required'
                  : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: const Color(0xFF6B7280))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9C27B0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDS(() => isSaving = true);
                      try {
                        final token = await _authService.getToken();
                        final res = await http.post(
                          Uri.parse(
                              '${AuthService.baseUrl}/admin/create-role/'),
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer ${token ?? ''}',
                          },
                          body: json.encode(
                              {'role_name': roleCtrl.text.trim()}),
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        final data = json.decode(res.body);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(res.statusCode == 201
                              ? data['message'] ?? 'Role created!'
                              : data['error'] ?? 'Failed'),
                          backgroundColor: res.statusCode == 201
                              ? const Color(0xFF4CAF50)
                              : Colors.red,
                        ));
                      } catch (e) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
    roleCtrl.dispose();
  }

  // ── Shared dialog field builder ───────────────────────────

  Widget _dialogField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        counterText: maxLength != null ? '' : null,
        prefixIcon: Icon(icon, color: const Color(0xFF1A1A2E)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: const Color(0xFF1A1A2E), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      validator: validator,
    );
  }

  // Removed unused user card methods - Users tab removed from bottom navigation
  // User management now accessed via Profile → Manage Users button
  // Methods removed: _buildPendingUserCard, _buildExistingUserCard, 
  // _buildInstagramDetailRow, _buildActionPillButton, _formatDate

  // Removed user management dialog methods - use Manage Users screen instead
  // void _showApproveDialog(...) { ... }
  // void _showRejectDialog(...) { ... }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

// ═══════════════════════════════════════════════════════════════
// ADMIN STORY TAB  – Instagram-style site stories
// ═══════════════════════════════════════════════════════════════

class _AdminStoryTab extends StatefulWidget {
  const _AdminStoryTab();

  @override
  State<_AdminStoryTab> createState() => _AdminStoryTabState();
}

class _AdminStoryTabState extends State<_AdminStoryTab> {
  final _service = ConstructionService();
  static const _baseUrl = 'http://187.127.164.22';
  static const _kViewedKey = 'story_viewed_timestamps'; // SharedPreferences key

  // All photos grouped by site
  Map<String, List<Map<String, dynamic>>> _storiesBySite = {};
  bool _isLoading = true;
  String? _error;

  // siteId → ISO date string of the latest photo at the time admin last viewed it
  // Persisted in SharedPreferences so it survives app restarts
  Map<String, String> _viewedTimestamps = {};

  @override
  void initState() {
    super.initState();
    _loadViewedTimestamps().then((_) => _load());
  }

  Future<void> _loadViewedTimestamps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kViewedKey);
      if (raw != null) {
        _viewedTimestamps = Map<String, String>.from(json.decode(raw) as Map);
      }
    } catch (_) {}
  }

  Future<void> _saveViewedTimestamp(String siteId, String latestDate) async {
    _viewedTimestamps[siteId] = latestDate;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kViewedKey, json.encode(_viewedTimestamps));
    } catch (_) {}
  }

  // A site is "viewed" only if the admin saw it at or after its latest photo date
  bool _isViewed(String siteId) {
    final lastSeen = _viewedTimestamps[siteId];
    if (lastSeen == null) return false;
    final photos = _storiesBySite[siteId];
    if (photos == null || photos.isEmpty) return true;
    final latestPhotoDate =
        (photos.first['update_date'] ?? photos.first['upload_date']) as String? ?? '';
    return lastSeen.compareTo(latestPhotoDate) >= 0;
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // Step 1 — get all site IDs and accountant photos in parallel
      final baseResults = await Future.wait([
        _service.getAllSites(),
        _service.getAccountantPhotos(),
      ]);

      final allSites = List<Map<String, dynamic>>.from(
          (baseResults[0] as Map)['sites'] ?? []);
      final rawAccountant = List<Map<String, dynamic>>.from(
          (baseResults[1] as Map)['photos'] ?? []);

      // Step 2 — fetch supervisor photos for every site in parallel
      // (backend requires site_id, so we must call once per site)
      // Build id→site lookup for enriching supervisor photos with site name
      final siteById = <String, Map<String, dynamic>>{
        for (final s in allSites)
          if ((s['id']?.toString() ?? '').isNotEmpty) s['id'].toString(): s,
      };
      final siteIds = siteById.keys.toList();

      final supervisorResults = await Future.wait(
        siteIds.map((id) => _service.getSupervisorPhotosForAccountant(siteId: id)),
      );

      // Step 3 — flatten and normalize supervisor photos
      final rawSupervisor = <Map<String, dynamic>>[];
      for (int i = 0; i < supervisorResults.length; i++) {
        final photos = List<Map<String, dynamic>>.from(
            supervisorResults[i]['photos'] ?? []);
        final site = siteById[siteIds[i]] ?? {};
        for (final p in photos) {
          final tod = (p['time_of_day'] as String? ?? '').toLowerCase();
          rawSupervisor.add({
            ...p,
            'update_date': p['update_date'] ?? p['upload_date'] ?? '',
            'update_type': tod == 'morning' ? 'STARTED' : 'FINISHED',
            'uploaded_by': p['supervisor_name'] ?? p['uploaded_by'] ?? 'Supervisor',
            'full_site_name': p['full_site_name'] ?? p['site_name'] ??
                site['display_name'] ?? site['site_name'] ?? '',
            'site_id': p['site_id'] ?? site['id'],
            '_source': 'supervisor',
          });
        }
      }

      // Step 4 — combine, sort newest-first, group by site
      final allPhotos = [...rawSupervisor, ...rawAccountant];
      allPhotos.sort((a, b) {
        final da = (a['update_date'] as String?) ?? '';
        final db = (b['update_date'] as String?) ?? '';
        return db.compareTo(da);
      });

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final p in allPhotos) {
        final key = p['site_id']?.toString() ?? 'unknown';
        grouped.putIfAbsent(key, () => []).add(p);
      }

      if (mounted) {
        setState(() {
          _storiesBySite = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  String _fullUrl(String? rel) {
    if (rel == null || rel.isEmpty) return '';
    return rel.startsWith('http') ? rel : '$_baseUrl$rel';
  }

  String _siteLabel(List<Map<String, dynamic>> photos) =>
      photos.first['full_site_name'] as String? ??
      photos.first['site_name'] as String? ??
      'Site';

  String _latestDate(List<Map<String, dynamic>> photos) {
    final raw = (photos.first['update_date'] ?? photos.first['upload_date']) as String? ?? '';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A1A2E)));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E), foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_storiesBySite.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No stories yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Text('Supervisor site photos will appear here.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    final siteIds = _storiesBySite.keys.toList();
    // Unviewed sites first
    siteIds.sort((a, b) {
      final av = _isViewed(a) ? 1 : 0;
      final bv = _isViewed(b) ? 1 : 0;
      return av.compareTo(bv);
    });

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF1A1A2E),
      child: CustomScrollView(
        slivers: [
          // ── Story bubbles row ─────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Essential Story',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: siteIds.length,
                      itemBuilder: (context, i) {
                        final id = siteIds[i];
                        final photos = _storiesBySite[id]!;
                        final viewed = _isViewed(id);
                        return _StoryBubble(
                          label: _siteLabel(photos),
                          imageUrl: _fullUrl(photos.first['image_url'] as String?),
                          viewed: viewed,
                          onTap: () => _openStory(id, photos),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(
            child: Divider(height: 1),
          ),

          // ── Photo grid ────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final id = siteIds[i];
                  final photos = _storiesBySite[id]!;
                  return _SiteStoryRow(
                    siteLabel: _siteLabel(photos),
                    latestDate: _latestDate(photos),
                    photoCount: photos.length,
                    photos: photos,
                    fullUrl: _fullUrl,
                    viewed: _isViewed(id),
                    onTapPhoto: (startIndex) => _openStory(id, photos, startIndex: startIndex),
                  );
                },
                childCount: siteIds.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openStory(String siteId, List<Map<String, dynamic>> photos, {int startIndex = 0}) {
    // Record the latest photo date for this site so the highlight only returns
    // when a newer photo is uploaded
    final latestDate =
        (photos.first['update_date'] ?? photos.first['upload_date']) as String? ?? '';
    _saveViewedTimestamp(siteId, latestDate);
    setState(() {});
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _StoryViewer(
          photos: photos,
          startIndex: startIndex,
          fullUrl: _fullUrl,
        ),
      ),
    );
  }
}

// ── Story bubble (circle) ─────────────────────────────────────

class _StoryBubble extends StatelessWidget {
  final String label;
  final String imageUrl;
  final bool viewed;
  final VoidCallback onTap;

  const _StoryBubble({
    required this.label,
    required this.imageUrl,
    required this.viewed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          children: [
            // Ring
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: viewed
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF1A1A2E), Color(0xFF3B82F6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: viewed ? Colors.grey.shade300 : null,
              ),
              padding: const EdgeInsets.all(2.5),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: 60,
                          height: 60,
                          placeholder: (_, __) => Container(color: const Color(0xFF1A1A2E).withValues(alpha: 0.1)),
                          errorWidget: (_, __, ___) => const Icon(Icons.apartment, color: Color(0xFF1A1A2E), size: 28),
                        )
                      : const Icon(Icons.apartment, color: Color(0xFF1A1A2E), size: 28),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: viewed ? FontWeight.normal : FontWeight.bold,
                color: viewed ? Colors.grey : const Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Site story row (expandable photo strip) ───────────────────

class _SiteStoryRow extends StatelessWidget {
  final String siteLabel;
  final String latestDate;
  final int photoCount;
  final List<Map<String, dynamic>> photos;
  final String Function(String?) fullUrl;
  final bool viewed;
  final void Function(int startIndex) onTapPhoto;

  const _SiteStoryRow({
    required this.siteLabel,
    required this.latestDate,
    required this.photoCount,
    required this.photos,
    required this.fullUrl,
    required this.viewed,
    required this.onTapPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: viewed
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF1A1A2E), Color(0xFF3B82F6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: viewed ? Colors.grey.shade300 : null,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: photos.isNotEmpty && (photos.first['image_url'] as String? ?? '').isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: fullUrl(photos.first['image_url'] as String?),
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: Colors.grey.shade200),
                              errorWidget: (_, __, ___) => const Icon(Icons.apartment, size: 16),
                            )
                          : const Icon(Icons.apartment, size: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(siteLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1A1A2E))),
                      Text('$photoCount photos · $latestDate',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => onTapPhoto(0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('View All',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A2E))),
                  ),
                ),
              ],
            ),
          ),

          // Horizontal photo strip
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final p = photos[i];
                final url = fullUrl(p['image_url'] as String?);
                final isMorning = (p['update_type'] as String? ?? '') == 'STARTED' ||
                    (p['time_of_day'] as String? ?? '').toLowerCase() == 'morning';
                return GestureDetector(
                  onTap: () => onTapPhoto(i),
                  child: Container(
                    width: 110,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey.shade100,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: url.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: url,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: Colors.grey.shade200),
                                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                                )
                              : const Icon(Icons.broken_image),
                        ),
                        // Morning / Evening badge
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isMorning
                                  ? Colors.orange.withValues(alpha: 0.9)
                                  : Colors.indigo.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isMorning ? '🌅 AM' : '🌆 PM',
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// FULL-SCREEN STORY VIEWER  – Instagram-style
// ═══════════════════════════════════════════════════════════════

class _StoryViewer extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int startIndex;
  final String Function(String?) fullUrl;

  const _StoryViewer({
    required this.photos,
    required this.startIndex,
    required this.fullUrl,
  });

  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late AnimationController _progressCtrl;
  static const _storyDuration = Duration(seconds: 5);

  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _progressCtrl = AnimationController(vsync: this, duration: _storyDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    _startProgress();
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _startProgress() {
    _progressCtrl.forward(from: 0);
  }

  void _next() {
    if (_currentIndex < widget.photos.length - 1) {
      _goTo(_currentIndex + 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      _goTo(_currentIndex - 1);
    } else {
      _startProgress();
    }
  }

  void _goTo(int index) {
    setState(() => _currentIndex = index);
    _pageController?.jumpToPage(index);
    _startProgress();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    final url = widget.fullUrl(photo['image_url'] as String?);
    final updateType = (photo['update_type'] as String? ?? '');
    final timeOfDay = (photo['time_of_day'] as String? ?? '').toLowerCase();
    final isMorning = updateType == 'STARTED' || timeOfDay == 'morning';
    final siteName = photo['full_site_name'] as String? ??
        photo['site_name'] as String? ?? 'Site';
    final uploadedBy = photo['supervisor_name'] as String? ??
        photo['uploaded_by'] as String? ?? '';
    final dateRaw = (photo['update_date'] ?? photo['upload_date']) as String? ?? '';
    final dateStr = dateRaw.length >= 10 ? dateRaw.substring(0, 10) : dateRaw;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx < w / 3) {
            _prev();
          } else if (d.globalPosition.dx > w * 2 / 3) {
            _next();
          }
        },
        onLongPressStart: (_) => _progressCtrl.stop(),
        onLongPressEnd: (_) => _progressCtrl.forward(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Photo ─────────────────────────────────────────
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.photos.length,
              itemBuilder: (_, i) {
                final u = widget.fullUrl(widget.photos[i]['image_url'] as String?);
                return u.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: u,
                        fit: BoxFit.contain,
                        placeholder: (_, __) =>
                            const Center(child: CircularProgressIndicator(color: Colors.white)),
                        errorWidget: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image, color: Colors.white, size: 60)),
                      )
                    : const Center(child: Icon(Icons.broken_image, color: Colors.white, size: 60));
              },
            ),

            // ── Gradient overlays ──────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Progress bars ──────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(widget.photos.length, (i) {
                  return Expanded(
                    child: Container(
                      height: 2.5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: i < _currentIndex
                            ? Container(color: Colors.white)
                            : i == _currentIndex
                                ? AnimatedBuilder(
                                    animation: _progressCtrl,
                                    builder: (_, __) => LinearProgressIndicator(
                                      value: _progressCtrl.value,
                                      backgroundColor: Colors.transparent,
                                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── Top bar: site name + close ─────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  ClipOval(
                    child: Container(
                      width: 38,
                      height: 38,
                      color: const Color(0xFF1A1A2E),
                      child: const Icon(Icons.apartment, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(siteName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text(
                          '${isMorning ? '🌅 Morning' : '🌆 Evening'} · $dateStr',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                ],
              ),
            ),

            // ── Bottom info ────────────────────────────────────
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isMorning
                              ? Colors.orange.withValues(alpha: 0.9)
                              : Colors.indigo.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isMorning ? '🌅 Morning Shot' : '🌆 Evening Shot',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_currentIndex + 1} / ${widget.photos.length}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                      ),
                    ],
                  ),
                  if (uploadedBy.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(uploadedBy,
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(siteName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Tap zones (left / right) ───────────────────────
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onTap: _prev,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(flex: 1, child: const SizedBox.shrink()),
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onTap: _next,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
