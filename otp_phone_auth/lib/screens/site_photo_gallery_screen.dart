import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SitePhotoGalleryScreen extends StatefulWidget {
  final Map<String, dynamic> site;

  const SitePhotoGalleryScreen({super.key, required this.site});

  @override
  State<SitePhotoGalleryScreen> createState() => _SitePhotoGalleryScreenState();
}

class _SitePhotoGalleryScreenState extends State<SitePhotoGalleryScreen> {
  final _authService = AuthService();
  List<Map<String, dynamic>> _photos = [];
  bool _isLoading = true;
  String _filterType = 'ALL'; // ALL, STARTED, FINISHED

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);

    try {
      final token = await _authService.getToken();

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/construction/site-photos/${widget.site['id']}/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _photos = List<Map<String, dynamic>>.from(data['photos']);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load photos: ${response.body}'),
              backgroundColor: AppColors.statusOverdue,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading photos: $e'),
            backgroundColor: AppColors.statusOverdue,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredPhotos {
    if (_filterType == 'ALL') return _photos;
    return _photos.where((p) => p['update_type'] == _filterType).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightSlate,
      appBar: AppBar(
        title: Text(
          'Photo Gallery',
          style: TextStyle(color: AppColors.deepNavy, fontSize: 18.sp, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.cleanWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.deepNavy),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPhotos,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Site Info
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.r),
            color: AppColors.cleanWhite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.site['display_name'] ?? widget.site['site_name'] ?? 'Unknown Site',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: AppColors.deepNavy),
                ),
                SizedBox(height: 4.h),
                Text(
                  '${widget.site['area'] ?? ''}, ${widget.site['street'] ?? ''}',
                  style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // Filter Chips
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            color: AppColors.cleanWhite,
            child: Row(
              children: [
                _buildFilterChip('ALL', 'All Photos'),
                SizedBox(width: 8.w),
                _buildFilterChip('STARTED', '🌅 Morning'),
                SizedBox(width: 8.w),
                _buildFilterChip('FINISHED', '🌆 Evening'),
              ],
            ),
          ),

          // Photos Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.deepNavy))
                : _filteredPhotos.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadPhotos,
                        color: AppColors.deepNavy,
                        child: GridView.builder(
                          padding: EdgeInsets.all(16.r),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: _filteredPhotos.length,
                          itemBuilder: (context, index) => _buildPhotoCard(_filteredPhotos[index], index),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterType == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterType = value),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.deepNavy : AppColors.lightSlate,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected ? AppColors.deepNavy : AppColors.deepNavy.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppColors.deepNavy,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoCard(Map<String, dynamic> photo, int index) {
    final isMorning = photo['update_type'] == 'STARTED';
    // Construct full image URL
    final imageUrl = photo['image_url'].toString().startsWith('http')
        ? photo['image_url']
        : 'http://187.127.164.22${photo['image_url']}';

    return GestureDetector(
      onTap: () => _openFullScreen(index),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cleanWhite,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [AppColors.cardShadow],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (context, url) => Container(
                    color: AppColors.lightSlate,
                    child: const Center(
                      child: CircularProgressIndicator(color: AppColors.deepNavy, strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: AppColors.lightSlate,
                    child: Icon(Icons.broken_image, size: 48.sp, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),

            // Info
            Padding(
              padding: EdgeInsets.all(12.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isMorning ? '🌅' : '🌆',
                        style: TextStyle(fontSize: 16.sp),
                      ),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          isMorning ? 'Morning' : 'Evening',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.deepNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    _formatDate(photo['update_date']),
                    style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                  ),
                  if (photo['description'] != null && photo['description'].toString().isNotEmpty) ...[
                    SizedBox(height: 6.h),
                    Text(
                      photo['description'],
                      style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  SizedBox(height: 6.h),
                  Row(
                    children: [
                      Icon(Icons.person, size: 12.sp, color: AppColors.textSecondary),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: Text(
                          photo['uploaded_by'] ?? 'Unknown',
                          style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library, size: 80.sp, color: AppColors.textSecondary.withValues(alpha: 0.5)),
          SizedBox(height: 16.h),
          Text(
            'No Photos Yet',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: AppColors.deepNavy),
          ),
          SizedBox(height: 8.h),
          Text(
            _filterType == 'ALL'
                ? 'Photos will appear here when uploaded'
                : 'No ${_filterType == "STARTED" ? "morning" : "evening"} photos yet',
            style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _openFullScreen(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullScreenGallery(
          photos: _filteredPhotos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown date';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final photoDate = DateTime(date.year, date.month, date.day);

      if (photoDate == today) {
        return 'Today';
      } else if (photoDate == today.subtract(const Duration(days: 1))) {
        return 'Yesterday';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateStr;
    }
  }
}

// Full Screen Photo Viewer
class _FullScreenGallery extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;

  const _FullScreenGallery({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    final isMorning = photo['update_type'] == 'STARTED';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: TextStyle(color: Colors.white, fontSize: 16.sp),
        ),
      ),
      body: Stack(
        children: [
          // Photo Viewer
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              // Construct full image URL
              final imageUrl = widget.photos[index]['image_url'].toString().startsWith('http')
                  ? widget.photos[index]['image_url']
                  : 'http://187.127.164.22${widget.photos[index]['image_url']}';

              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => Center(
                      child: Icon(Icons.broken_image, size: 64.sp, color: Colors.white54),
                    ),
                  ),
                ),
              );
            },
          ),

          // Photo Info Overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: EdgeInsets.all(24.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        isMorning ? '🌅' : '🌆',
                        style: TextStyle(fontSize: 24.sp),
                      ),
                      SizedBox(width: 12.w),
                      Text(
                        isMorning ? 'Morning - Work Started' : 'Evening - Work Completed',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14.sp, color: Colors.white70),
                      SizedBox(width: 6.w),
                      Text(
                        _formatDateTime(photo['created_at']),
                        style: TextStyle(fontSize: 13.sp, color: Colors.white70),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Icon(Icons.person, size: 14.sp, color: Colors.white70),
                      SizedBox(width: 6.w),
                      Text(
                        '${photo['uploaded_by']} (${photo['uploaded_by_role']})',
                        style: TextStyle(fontSize: 13.sp, color: Colors.white70),
                      ),
                    ],
                  ),
                  if (photo['description'] != null && photo['description'].toString().isNotEmpty) ...[
                    SizedBox(height: 12.h),
                    Text(
                      photo['description'],
                      style: TextStyle(fontSize: 14.sp, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      final period = date.hour >= 12 ? 'PM' : 'AM';
      return '${date.day}/${date.month}/${date.year} at $hour:${date.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return dateStr;
    }
  }
}
