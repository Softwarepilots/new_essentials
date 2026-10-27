import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:io';
import '../services/construction_service.dart';
import '../services/notification_service.dart';
import '../utils/app_colors.dart';
import '../utils/time_validator.dart';

class SupervisorPhotoUploadScreen extends StatefulWidget {
  final Map<String, dynamic> site;
  final bool defaultToEvening;

  const SupervisorPhotoUploadScreen({
    super.key,
    required this.site,
    this.defaultToEvening = false,
  });

  @override
  State<SupervisorPhotoUploadScreen> createState() => _SupervisorPhotoUploadScreenState();
}

class _SupervisorPhotoUploadScreenState extends State<SupervisorPhotoUploadScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _constructionService = ConstructionService();
  final ImagePicker _picker = ImagePicker();
  
  // Morning photos (new uploads)
  List<XFile> _morningPhotos = [];
  bool _isUploadingMorning = false;
  
  // Evening photos (new uploads)
  List<XFile> _eveningPhotos = [];
  bool _isUploadingEvening = false;
  
  // Uploaded photos from server
  List<Map<String, dynamic>> _uploadedMorningPhotos = [];
  List<Map<String, dynamic>> _uploadedEveningPhotos = [];
  bool _isLoadingPhotos = false;
  
  // Date filter
  Map<String, List<Map<String, dynamic>>> _photosByDate = {};
  Set<String> _expandedDates = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.defaultToEvening ? 1 : 0,
    );
    _loadUploadedPhotos();
  }

  Future<void> _loadUploadedPhotos() async {
    print('🖼️ [SCREEN] Loading uploaded photos...');
    setState(() => _isLoadingPhotos = true);
    
    try {
      final result = await _constructionService.getSupervisorUploadedPhotos(
        siteId: widget.site['id'],
      );
      
      print('🖼️ [SCREEN] Result: $result');
      
      if (result['success'] && mounted) {
        final photos = result['photos'] as List<Map<String, dynamic>>? ?? [];
        
        print('🖼️ [SCREEN] Total photos: ${photos.length}');
        
        // Group photos by date
        _photosByDate.clear();
        for (var photo in photos) {
          final date = photo['upload_date'] ?? '';
          if (!_photosByDate.containsKey(date)) {
            _photosByDate[date] = [];
          }
          _photosByDate[date]!.add(photo);
        }
        
        final morningPhotos = photos.where((p) => p['time_of_day'] == 'morning').toList();
        final eveningPhotos = photos.where((p) => p['time_of_day'] == 'evening').toList();
        
        print('🖼️ [SCREEN] Morning photos: ${morningPhotos.length}');
        print('🖼️ [SCREEN] Evening photos: ${eveningPhotos.length}');
        print('🖼️ [SCREEN] Dates with photos: ${_photosByDate.keys.length}');
        
        setState(() {
          _uploadedMorningPhotos = morningPhotos;
          _uploadedEveningPhotos = eveningPhotos;
          _isLoadingPhotos = false;
        });
      } else {
        print('🖼️ [SCREEN] Failed to load photos: ${result['error']}');
        if (mounted) {
          setState(() => _isLoadingPhotos = false);
        }
      }
    } catch (e) {
      print('🖼️ [SCREEN] Exception loading photos: $e');
      if (mounted) {
        setState(() => _isLoadingPhotos = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickImages(bool isMorning) async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      
      if (images.isNotEmpty) {
        setState(() {
          if (isMorning) {
            _morningPhotos.addAll(images);
          } else {
            _eveningPhotos.addAll(images);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking images: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _takePhoto(bool isMorning) async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      
      if (photo != null) {
        setState(() {
          if (isMorning) {
            _morningPhotos.add(photo);
          } else {
            _eveningPhotos.add(photo);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error taking photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removePhoto(int index, bool isMorning) {
    setState(() {
      if (isMorning) {
        _morningPhotos.removeAt(index);
      } else {
        _eveningPhotos.removeAt(index);
      }
    });
  }

  Future<void> _uploadPhotos(bool isMorning) async {
    final photos = isMorning ? _morningPhotos : _eveningPhotos;
    
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one photo'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if photo upload is on time
    final isOnTime = isMorning 
      ? TimeValidator.isMorningPhotoOnTime() 
      : TimeValidator.isEveningPhotoOnTime();

    setState(() {
      if (isMorning) {
        _isUploadingMorning = true;
      } else {
        _isUploadingEvening = true;
      }
    });

    try {
      print('🕒 [PHOTO] Uploading ${isMorning ? "morning" : "evening"} photos');
      print('🕒 [PHOTO] Current IST time: ${TimeValidator.getISTTime()}');
      print('🕒 [PHOTO] Is on time: $isOnTime');
      
      final result = await _constructionService.uploadSupervisorPhotos(
        siteId: widget.site['id'],
        photos: photos,
        timeOfDay: isMorning ? 'morning' : 'evening',
      );

      // Send notification to admin if upload is late
      if (!isOnTime && result['success']) {
        final notificationService = NotificationService();
        await notificationService.sendLateEntryNotification(
          siteId: widget.site['id'],
          entryType: isMorning ? 'morning_photo' : 'evening_photo',
          message: isMorning 
            ? TimeValidator.getMorningPhotoLateMessage()
            : TimeValidator.getEveningPhotoLateMessage(),
          actualTime: TimeValidator.getISTTime(),
        );
      }

      if (mounted) {
        setState(() {
          if (isMorning) {
            _isUploadingMorning = false;
            if (result['success']) {
              _morningPhotos.clear();
            }
          } else {
            _isUploadingEvening = false;
            if (result['success']) {
              _eveningPhotos.clear();
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['success'] 
                ? (isOnTime 
                    ? '✅ Photos uploaded successfully!' 
                    : '⚠️ Photos uploaded (Late upload - Admin notified)')
                : '❌ ${result['error']}'
            ),
            backgroundColor: result['success'] 
              ? (isOnTime ? AppColors.statusCompleted : Colors.orange)
              : Colors.red,
            duration: Duration(seconds: result['success'] && !isOnTime ? 4 : 2),
          ),
        );

        if (result['success']) {
          // Reload uploaded photos to show the new uploads
          _loadUploadedPhotos();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isMorning) {
            _isUploadingMorning = false;
          } else {
            _isUploadingEvening = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading photos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightSlate,
      appBar: AppBar(
        title: const Text('Upload Site Photos'),
        backgroundColor: AppColors.deepNavy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Site Info Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              gradient: AppColors.navyGradient,
              boxShadow: [AppColors.cardShadow],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.site['display_name'] ?? 'Site',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14.sp, color: Colors.white70),
                    SizedBox(width: 4.w),
                    Text(
                      '${widget.site['area']} - ${widget.site['street']}',
                      style: TextStyle(fontSize: 13.sp, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            margin: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              color: AppColors.lightSlate,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: AppColors.orangeGradient,
                borderRadius: BorderRadius.circular(12.r),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
              unselectedLabelStyle: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: '🌅 Morning'),
                Tab(text: '🌆 Evening'),
              ],
            ),
          ),
          
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPhotoTab(true),  // Morning
                _buildPhotoTab(false), // Evening
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoTab(bool isMorning) {
    final photos = isMorning ? _morningPhotos : _eveningPhotos;
    final uploadedPhotos = isMorning ? _uploadedMorningPhotos : _uploadedEveningPhotos;
    final isUploading = isMorning ? _isUploadingMorning : _isUploadingEvening;
    final timeLabel = isMorning ? 'Morning' : 'Evening';
    final timeEmoji = isMorning ? '🌅' : '🌆';

    return Padding(
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            '$timeEmoji $timeLabel Photos',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.deepNavy,
            ),
          ),
          SizedBox(height: 16.h),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isUploading ? null : () => _takePhoto(isMorning),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.deepNavy,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isUploading ? null : () => _pickImages(isMorning),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Choose Photos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusCompleted,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),

          // New Photos to Upload Section
          if (photos.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.upload_file, size: 18.sp, color: AppColors.safetyOrange),
                SizedBox(width: 8.w),
                Text(
                  'Ready to Upload (${photos.length})',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.safetyOrange,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            SizedBox(
              height: 120.h,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: _buildPhotoThumbnail(photos[index], index, isMorning),
                  );
                },
              ),
            ),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: isUploading ? null : () => _uploadPhotos(isMorning),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.safetyOrange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: isUploading
                  ? SizedBox(
                      height: 20.h,
                      width: 20.w,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Upload ${photos.length} Photo${photos.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            SizedBox(height: 24.h),
          ],

          // Uploaded Photos Section
          Row(
            children: [
              Icon(Icons.cloud_done, size: 18.sp, color: AppColors.statusCompleted),
              SizedBox(width: 8.w),
              Text(
                'Uploaded Photos (${uploadedPhotos.length})',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.statusCompleted,
                ),
              ),
              const Spacer(),
              if (_isLoadingPhotos)
                SizedBox(
                  width: 16.w,
                  height: 16.h,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          SizedBox(height: 12.h),
          
          // Uploaded Photos by Date (Expandable)
          Expanded(
            child: uploadedPhotos.isEmpty
                ? _buildEmptyUploadedState(timeLabel)
                : _buildPhotosByDate(uploadedPhotos),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyUploadedState(String timeLabel) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 60.sp,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 16.h),
            Text(
              'No Uploaded $timeLabel Photos',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Upload photos to see them here',
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoThumbnail(XFile photo, int index, bool isMorning) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: Image.file(
            File(photo.path),
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removePhoto(index, isMorning),
            child: Container(
              padding: EdgeInsets.all(4.r),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                Icons.close,
                color: Colors.white,
                size: 16.sp,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadedPhotoThumbnail(Map<String, dynamic> photo) {
    final imageUrl = photo['image_url'].toString().startsWith('http')
        ? photo['image_url']
        : 'http://192.168.1.6:8001${photo['image_url']}';
    
    final uploadDate = photo['upload_date'] ?? '';
    
    return GestureDetector(
      onTap: () => _showFullImage(imageUrl),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: AppColors.lightSlate,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: AppColors.lightSlate,
                  child: const Icon(
                    Icons.broken_image,
                    color: AppColors.textSecondary,
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 6.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12.r),
                  bottomRight: Radius.circular(12.r),
                ),
              ),
              child: Text(
                uploadDate,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 30.sp),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosByDate(List<Map<String, dynamic>> photos) {
    // Group photos by date
    final photosByDate = <String, List<Map<String, dynamic>>>{};
    for (var photo in photos) {
      final date = photo['upload_date'] ?? '';
      if (!photosByDate.containsKey(date)) {
        photosByDate[date] = [];
      }
      photosByDate[date]!.add(photo);
    }
    
    // Sort dates (most recent first)
    final sortedDates = photosByDate.keys.toList()..sort((a, b) => b.compareTo(a));
    
    return ListView.builder(
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final datePhotos = photosByDate[date]!;
        return _buildDatePhotoCard(date, datePhotos);
      },
    );
  }

  Widget _buildDatePhotoCard(String date, List<Map<String, dynamic>> photos) {
    final isExpanded = _expandedDates.contains(date);
    final formattedDate = _formatDateForCard(date);
    
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [AppColors.cardShadow],
      ),
      child: Column(
        children: [
          // Date Header - Clickable
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
              borderRadius: BorderRadius.circular(16.r),
              child: Container(
                padding: EdgeInsets.all(16.r),
                decoration: BoxDecoration(
                  color: isExpanded ? AppColors.statusCompleted.withValues(alpha: 0.05) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: isExpanded ? AppColors.statusCompleted.withValues(alpha: 0.2) : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Calendar Icon
                    Container(
                      padding: EdgeInsets.all(10.r),
                      decoration: BoxDecoration(
                        gradient: isExpanded ? AppColors.greenGradient : null,
                        color: isExpanded ? null : AppColors.statusCompleted.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(
                        Icons.calendar_today,
                        color: isExpanded ? Colors.white : AppColors.statusCompleted,
                        size: 20.sp,
                      ),
                    ),
                    SizedBox(width: 16.w),

                    // Date and Photo Count
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: AppColors.deepNavy,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: AppColors.statusCompleted.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              '${photos.length} photo${photos.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: AppColors.statusCompleted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Dropdown Arrow
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.deepNavy,
                        size: 24.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Expandable Photo Grid
          if (isExpanded)
            Padding(
              padding: EdgeInsets.all(16.r),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  return _buildUploadedPhotoThumbnail(photos[index]);
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateForCard(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final photoDate = DateTime(date.year, date.month, date.day);
      
      if (photoDate == today) {
        return 'Today • ${_formatDateWithDay(date)}';
      } else if (photoDate == yesterday) {
        return 'Yesterday • ${_formatDateWithDay(date)}';
      } else {
        return _formatDateWithDay(date);
      }
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDateWithDay(DateTime date) {
    final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dayName = days[date.weekday % 7];
    return '$dayName, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

