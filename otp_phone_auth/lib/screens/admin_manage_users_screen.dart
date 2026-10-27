import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../utils/smooth_animations.dart';

class AdminManageUsersScreen extends StatefulWidget {
  const AdminManageUsersScreen({Key? key}) : super(key: key);

  @override
  State<AdminManageUsersScreen> createState() => _AdminManageUsersScreenState();
}

class _AdminManageUsersScreenState extends State<AdminManageUsersScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  late TabController _tabController;
  
  // Background refresh timer
  Timer? _refreshTimer;

  // New Users (Pending) state
  List<Map<String, dynamic>> _pendingUsers = [];
  bool _isLoadingPending = false;
  bool _pendingLoaded = false;

  // Tracks which user card is currently being approved/rejected
  String? _processingUserId;

  // All Users state
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoadingAll = false;
  bool _allLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        if (_tabController.index == 0 && !_pendingLoaded) {
          _loadPendingUsers();
        } else if (_tabController.index == 1 && !_allLoaded) {
          _loadAllUsers();
        }
      }
    });
    _loadPendingUsers();
    _startBackgroundRefresh();
  }

  @override
  void dispose() {
    _stopBackgroundRefresh();
    _tabController.dispose();
    super.dispose();
  }

  void _startBackgroundRefresh() {
    // Refresh every 60 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (timer) {
        if (mounted) {
          if (_tabController.index == 0) {
            _loadPendingUsers(forceRefresh: true);
          } else {
            _loadAllUsers(forceRefresh: true);
          }
        }
      },
    );
  }

  void _stopBackgroundRefresh() {
    _refreshTimer?.cancel();
  }

  Future<void> _loadPendingUsers({bool forceRefresh = false}) async {
    // Load from persistent cache first
    if (!forceRefresh && !_pendingLoaded) {
      final cached = await CacheService.loadPendingUsers();
      if (cached != null && mounted) {
        setState(() {
          _pendingUsers = cached;
          _pendingLoaded = true;
        });
        print('✅ [USERS] Loaded ${_pendingUsers.length} pending users from cache');
      }
    }

    // Skip if already loaded and not forcing refresh
    if (_pendingLoaded && !forceRefresh) return;

    setState(() => _isLoadingPending = true);

    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse('http://192.168.1.6:8001/api/admin/pending-users/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final users = List<Map<String, dynamic>>.from(data['users']);
        
        // Save to persistent cache
        await CacheService.savePendingUsers(users);
        
        if (mounted) {
          setState(() {
            _pendingUsers = users;
            _pendingLoaded = true;
          });
        }
        print('✅ [USERS] Loaded ${_pendingUsers.length} pending users from API');
      }
    } catch (e) {
      print('Error loading pending users: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingPending = false);
      }
    }
  }

  Future<void> _loadAllUsers({bool forceRefresh = false}) async {
    // Load from persistent cache first
    if (!forceRefresh && !_allLoaded) {
      final cached = await CacheService.loadAllUsers();
      if (cached != null && mounted) {
        setState(() {
          _allUsers = cached;
          _allLoaded = true;
        });
        print('✅ [USERS] Loaded ${_allUsers.length} all users from cache');
      }
    }

    // Skip if already loaded and not forcing refresh
    if (_allLoaded && !forceRefresh) return;

    setState(() => _isLoadingAll = true);

    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse('http://192.168.1.6:8001/api/admin/all-users/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final users = List<Map<String, dynamic>>.from(data['users']);
        
        // Save to persistent cache
        await CacheService.saveAllUsers(users);
        
        if (mounted) {
          setState(() {
            _allUsers = users;
            _allLoaded = true;
          });
        }
        print('✅ [USERS] Loaded ${_allUsers.length} all users from API');
      }
    } catch (e) {
      print('Error loading all users: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingAll = false);
      }
    }
  }

  Future<void> _approveUser(String userId, String username) async {
    setState(() => _processingUserId = userId);
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('http://192.168.1.6:8001/api/admin/approve-user/$userId/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User $username approved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadPendingUsers(forceRefresh: true);
        _loadAllUsers(forceRefresh: true);
      } else {
        throw Exception('Failed to approve user');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processingUserId = null);
    }
  }

  Future<void> _rejectUser(String userId, String username) async {
    setState(() => _processingUserId = userId);
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('http://192.168.1.6:8001/api/admin/reject-user/$userId/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User $username rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadPendingUsers(forceRefresh: true);
      } else {
        throw Exception('Failed to reject user');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Manage Users',
          style: TextStyle(
            color: const Color(0xFF1A1A2E),
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4CAF50),
          labelColor: const Color(0xFF4CAF50),
          unselectedLabelColor: const Color(0xFF6B7280),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('New Users'),
                  if (_pendingUsers.isNotEmpty) ...[
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        '${_pendingUsers.length}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'All Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewUsersTab(),
          _buildAllUsersTab(),
        ],
      ),
    );
  }

  Widget _buildNewUsersTab() {
    return RefreshIndicator(
      onRefresh: () => _loadPendingUsers(forceRefresh: true),
      color: const Color(0xFF4CAF50),
      child: _isLoadingPending && _pendingUsers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _pendingUsers.isEmpty
              ? _buildEmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'All Caught Up!',
                  subtitle: 'No pending user approvals',
                )
              : ListView.builder(
                  physics: const SmoothScrollPhysics(),
                              padding: EdgeInsets.all(16.r),
                  itemCount: _pendingUsers.length,
                  itemBuilder: (context, index) {
                    final user = _pendingUsers[index];
                    return AnimatedListItem(
                      index: index,
                      child: _buildPendingUserCard(user),
                    );
                  },
                ),
    );
  }

  Widget _buildAllUsersTab() {
    return RefreshIndicator(
      onRefresh: () => _loadAllUsers(forceRefresh: true),
      color: const Color(0xFF4CAF50),
      child: _isLoadingAll && _allUsers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _allUsers.isEmpty
              ? _buildEmptyState(
                  icon: Icons.people_outline,
                  title: 'No Users Found',
                  subtitle: 'No users in the system',
                )
              : ListView.builder(
                  physics: const SmoothScrollPhysics(),
                              padding: EdgeInsets.all(16.r),
                  itemCount: _allUsers.length,
                  itemBuilder: (context, index) {
                    final user = _allUsers[index];
                    return AnimatedListItem(
                      index: index,
                      child: _buildUserCard(user),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120.w,
            height: 120.h,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 60.sp, color: Colors.white),
          ),
          SizedBox(height: 24.h),
          Text(
            title,
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 16.sp,
              color: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingUserCard(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final username = user['username'] ?? 'Unknown';
    final fullName = user['full_name'] ?? 'N/A';
    final email = user['email'] ?? 'N/A';
    final phone = user['phone'] ?? 'N/A';
    final role = user['role'] ?? 'N/A';

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
            ),
            child: Row(
              children: [
                Container(
                  width: 50.w,
                  height: 50.h,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '@$username',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14.sp,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    role,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: EdgeInsets.all(16.r),
            child: Column(
              children: [
                _buildInfoRow(Icons.email_outlined, email),
                SizedBox(height: 8.h),
                _buildInfoRow(Icons.phone_outlined, phone),
                SizedBox(height: 16.h),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _processingUserId != null
                            ? null
                            : () => _approveUser(userId, username),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.6),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: _processingUserId == userId
                            ? SizedBox(
                                width: 20.w,
                                height: 20.h,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle, size: 20.sp),
                                  SizedBox(width: 6.w),
                                  const Text('Approve'),
                                ],
                              ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _processingUserId != null
                            ? null
                            : () => _rejectUser(userId, username),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(
                            color: _processingUserId != null
                                ? Colors.red.withValues(alpha: 0.4)
                                : Colors.red,
                          ),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: _processingUserId == userId
                            ? SizedBox(
                                width: 20.w,
                                height: 20.h,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cancel, size: 20.sp),
                                  SizedBox(width: 6.w),
                                  const Text('Reject'),
                                ],
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
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final username = user['username'] ?? 'Unknown';
    final fullName = user['full_name'] ?? 'N/A';
    final email = user['email'] ?? 'N/A';
    final phone = user['phone'] ?? 'N/A';
    final role = user['role'] ?? 'N/A';
    final isActive = user['is_active'] ?? false;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.all(16.r),
        leading: Container(
          width: 50.w,
          height: 50.h,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          fullName,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4.h),
            Text('@$username', style: TextStyle(fontSize: 13.sp)),
            SizedBox(height: 2.h),
            Text(email, style: TextStyle(fontSize: 12.sp)),
            SizedBox(height: 2.h),
            Text(phone, style: TextStyle(fontSize: 12.sp)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                role,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF4CAF50),
                ),
              ),
            ),
            SizedBox(height: 4.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: isActive ? Colors.green : Colors.grey,
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Text(
                isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 10.sp,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
      ],
    );
  }
}
