import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../services/construction_service.dart';
import '../services/material_service.dart';
import '../services/budget_management_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import '../utils/time_validator.dart';
import 'supervisor_history_screen.dart';
import 'supervisor_photo_upload_screen.dart';
import 'site_engineer_material_screen.dart';
import 'site_extra_cost_screen.dart';

enum _SiteEntryStatus {
  none, // no entries today — FAB opens locked quick actions
  dailyComplete, // labour + material + photo all done — FAB green, unlocked view
  lockedByOther, // another supervisor entered today — FAB locked (grey lock)
}

/// Entry session management for workflow lock
class EntrySession extends ChangeNotifier {
  bool isActive = false;
  String? sessionId;
  DateTime? startTime;
  final List<String> completedSteps = [];

  static const Duration timeout = Duration(hours: 2);

  bool get isLabourComplete => completedSteps.contains('labour');
  bool get isMaterialComplete => completedSteps.contains('material');
  bool get isPhotoComplete => completedSteps.contains('photo');

  bool get isExpired {
    if (startTime == null) return false;
    return DateTime.now().difference(startTime!) > timeout;
  }

  bool get canExit => (isLabourComplete && isPhotoComplete) || isExpired;

  void start() {
    isActive = true;
    sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    startTime = DateTime.now();
    completedSteps.clear();
    notifyListeners();
  }

  void markComplete(String step) {
    if (!completedSteps.contains(step)) {
      completedSteps.add(step);
      notifyListeners();
    }
  }

  void end() {
    isActive = false;
    sessionId = null;
    startTime = null;
    completedSteps.clear();
    notifyListeners();
  }
}

class SiteDetailScreen extends StatefulWidget {
  final Map<String, dynamic> site;

  const SiteDetailScreen({super.key, required this.site});

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen> {
  final _constructionService = ConstructionService();
  final _authService = AuthService();
  final EntrySession _entrySession = EntrySession(); // Entry session management

  // Cache for site-specific data
  static final Map<String, Map<String, dynamic>?> _siteDataCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(
    minutes: 5,
  ); // Cache expires after 5 minutes

  Map<String, dynamic>? _todayEntries;
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();
  String? _userId; // Store user ID for cache key
  String get _siteId => widget.site['id'].toString();
  String get _cacheKey =>
      '${_siteId}_${_selectedDate.toIso8601String().split('T')[0]}';

  // Dropdown functionality
  final Set<String> _expandedDates = {};

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _loadTodayEntriesWithCache();
  }

  Future<void> _loadUserId() async {
    try {
      final user = await _authService.getCurrentUser();
      setState(() {
        _userId = user?['id']?.toString();
      });
      print('🔑 [SITE_DETAIL] User ID loaded: $_userId');
    } catch (e) {
      print('❌ [SITE_DETAIL] Error loading user ID: $e');
    }
  }

  Future<void> _loadTodayEntriesWithCache() async {
    print(
      '🏗️ [SITE_DETAIL] Loading entries for site: $_siteId, date: $_selectedDate',
    );

    // Check if we have valid cached data
    if (_siteDataCache.containsKey(_cacheKey) &&
        _cacheTimestamps.containsKey(_cacheKey)) {
      final cacheTime = _cacheTimestamps[_cacheKey]!;
      final now = DateTime.now();

      if (now.difference(cacheTime) < _cacheExpiry) {
        print('🎯 [SITE_DETAIL] Using cached data for $_cacheKey');
        setState(() {
          _todayEntries = _siteDataCache[_cacheKey];
          _isLoading = false;
        });
        return;
      } else {
        print('⏰ [SITE_DETAIL] Cache expired for $_cacheKey, refreshing...');
      }
    }

    // Load fresh data
    await _loadTodayEntries();
  }

  Future<void> _loadTodayEntries() async {
    print(
      '🔄 [SITE_DETAIL] Loading fresh data for site: $_siteId, date: $_selectedDate',
    );
    setState(() => _isLoading = true);

    try {
      final entries = await _constructionService.getEntriesByDate(
        widget.site['id'],
        _selectedDate,
      );

      // Cache the data (handle null case)
      if (entries != null) {
        _siteDataCache[_cacheKey] = entries;
        _cacheTimestamps[_cacheKey] = DateTime.now();
        print('💾 [SITE_DETAIL] Cached data for $_cacheKey');
      }

      setState(() {
        _todayEntries = entries;
        _isLoading = false;
      });

      // Sync session marks whenever fresh data arrives — fixes the race where
      // the sheet opened before _todayEntries was populated (labour stays unmarked).
      if (_entrySession.isActive && entries != null) {
        final labourList = List<Map<String, dynamic>>.from(
          entries['labour_entries'] ?? [],
        );
        final photoCount = (entries['photo_count'] as num?)?.toInt() ?? 0;
        if (labourList.isNotEmpty) _entrySession.markComplete('labour');
        if (photoCount > 0) _entrySession.markComplete('photo');
      }
    } catch (e) {
      print('❌ [SITE_DETAIL] Error loading entries: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.deepNavy,
              onPrimary: Colors.white,
              onSurface: AppColors.deepNavy,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      // Use cached loading when date changes
      _loadTodayEntriesWithCache();
    }
  }

  void _showQuickActions() {
    // Pre-populate session from already-submitted data for today FIRST
    final labourEntries = List<Map<String, dynamic>>.from(
      _todayEntries?['labour_entries'] ?? [],
    );
    final photoCount = (_todayEntries?['photo_count'] as num?)?.toInt() ?? 0;
    final materialSubmittedToday =
        _todayEntries?['material_submitted_today'] == true;

    // Start session when quick actions opens (or reuse existing)
    if (!_entrySession.isActive) {
      _entrySession.start();
      print('✅ [ENTRY_SESSION] Session started from quick actions');
    }

    // Mark steps complete based on server data (ALWAYS, to ensure UI updates)
    if (labourEntries.isNotEmpty) {
      _entrySession.markComplete('labour');
      print('✅ [ENTRY_SESSION] Labour marked complete from server data');
    }
    if (photoCount > 0) {
      _entrySession.markComplete('photo');
      print(
        '✅ [ENTRY_SESSION] Photo marked complete from server data (count: $photoCount)',
      );
    }

    // Combine server data with live session so the sheet is unlocked immediately
    // after submission even if the subsequent reload didn't return the entry yet.
    final labourDone =
        labourEntries.isNotEmpty || _entrySession.isLabourComplete;
    final photoDone = photoCount > 0 || _entrySession.isPhotoComplete;
    final isMorningComplete = labourDone && photoDone && materialSubmittedToday;
    print(
      '🔓 [QUICK_ACTIONS] Morning complete: $isMorningComplete '
      '(labour: server=${labourEntries.isNotEmpty} session=${_entrySession.isLabourComplete}, '
      'photos: server=${photoCount > 0} session=${_entrySession.isPhotoComplete}, '
      'material: $materialSubmittedToday)',
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: isMorningComplete, // UNLOCKED if morning data complete
      enableDrag: isMorningComplete, // UNLOCKED if morning data complete
      builder: (context) => PopScope(
        // Already complete → freely dismissible. Incomplete → intercept to warn.
        canPop: isMorningComplete,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            // Only fires when canPop: false (incomplete day)
            if (_entrySession.canExit) {
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Complete Labour, Photo & Material to exit. '
                    '(${_entrySession.isLabourComplete ? "✅" : "⬜"} Labour  '
                    '${_entrySession.isPhotoComplete ? "✅" : "⬜"} Photo  '
                    '${materialSubmittedToday ? "✅" : "⬜"} Material)',
                  ),
                  backgroundColor: Colors.orange.shade700,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        },
        child: _QuickActionsSheet(
          entrySession: _entrySession,
          materialSubmittedToday: materialSubmittedToday,
          hasLabourData: labourDone,
          hasPhotoData: photoDone,
          onLabourTap: () {
            final hasLabourEntries =
                (_todayEntries?['labour_entries'] as List?)?.isNotEmpty ==
                    true ||
                _entrySession.isLabourComplete;
            // Pop QA first (same pattern as photo) so the labour form doesn't
            // stack on top of it — avoids the stale-locked-sheet bug.
            Navigator.pop(context);
            _showLabourEntry(
              startAtEvening: hasLabourEntries,
              reopenQA: true,
            );
          },
          onMaterialTap: () {
            _showMaterialEntry();
          },
          onPhotoTap: () {
            final hasMorningPhoto =
                ((_todayEntries?['photo_count'] as num?)?.toInt() ?? 0) > 0 ||
                _entrySession.isPhotoComplete;
            Navigator.pop(context);
            _showPhotoUpload(defaultToEvening: hasMorningPhoto);
          },
          onHistoryTap: () {
            Navigator.pop(context);
            _openHistory();
          },
          onMaterialRequirementTap: () {
            _showMaterialRequirementDialog();
          },
          onAllComplete: () {
            Navigator.pop(context);
            print('✅ [ENTRY_SESSION] Quick actions closed — labour+photo complete');
          },
        ),
      ),
    );
  }

  /// Show dialog when entry is locked by another supervisor
  void _showEntryLockedDialog({
    required String lockedBy,
    required String lockedAt,
    required List<Map<String, dynamic>> entries,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Text('Entry Locked'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Data has already been entered by:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 18,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          lockedBy,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 18,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'at $lockedAt',
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Entered data:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              ...entries.map((entry) => _buildReadOnlyEntryRow(entry)).toList(),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          if (entries.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openHistory();
              },
              icon: const Icon(Icons.history, size: 16),
              label: const Text('View History'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyEntryRow(Map<String, dynamic> entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            entry['labour_type'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${entry['labour_count']} workers',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  /// Show warning when trying to exit during active entry session
  void _showSessionLockWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red.shade600, size: 28),
            const SizedBox(width: 12),
            const Text('Entry In Progress'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You have started the daily entry process. Please complete:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildRequirementRow(
              'Labour Count',
              _entrySession.isLabourComplete,
            ),
            _buildRequirementRow(
              'Material Updates',
              _entrySession.isMaterialComplete,
            ),
            _buildRequirementRow('Site Photo', _entrySession.isPhotoComplete),
            if (_entrySession.isExpired) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, size: 16, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Session expired. You can exit now.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_entrySession.isExpired)
            TextButton(
              onPressed: () {
                _entrySession.end();
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Exit screen
              },
              child: const Text('Exit Anyway'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: AppColors.deepNavy),
            child: const Text('Continue Entry'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementRow(
    String title,
    bool isComplete, {
    bool optional = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isComplete
                ? Colors.green
                : (optional ? Colors.grey : Colors.orange),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: isComplete ? FontWeight.bold : FontWeight.normal,
                color: isComplete ? Colors.green.shade700 : Colors.black87,
              ),
            ),
          ),
          if (optional)
            Text(
              'Optional',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  // reopenQA: true when called from inside Quick Actions (QA was popped before
  // opening the form). The sheet will reopen QA on both success and cancel so
  // the user never ends up stranded on the bare site-detail screen mid-session.
  void _showLabourEntry({bool startAtEvening = false, bool reopenQA = false}) {
    bool _submitted = false;

    // True if this supervisor already has a morning entry for today
    final morningAlreadySubmitted = _isToday() &&
        _userId != null &&
        (_todayEntries?['labour_entries'] as List?)?.any(
              (e) =>
                  e['supervisor_id']?.toString() == _userId &&
                  (e['entry_type'] ?? 'morning') == 'morning',
            ) ==
            true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.3),
      enableDrag: true,
      isDismissible: true,
      builder: (context) => _LabourEntrySheet(
        siteId: widget.site['id'],
        defaultToEvening: startAtEvening,
        morningAlreadySubmitted: morningAlreadySubmitted,
        onSuccess: () {
          _submitted = true;
          _entrySession.markComplete('labour');
          _invalidateCache();
          _loadTodayEntries().then((_) {
            if (mounted && _entrySession.isActive) _showQuickActions();
          });
          SupervisorHistoryScreen.invalidateCache(widget.site['id']);
        },
      ),
    ).whenComplete(() {
      // If the user cancelled without submitting and a QA was open before,
      // reopen it so they can continue their session.
      if (!_submitted && reopenQA && mounted && _entrySession.isActive) {
        _showQuickActions();
      }
    });
  }

  /// Silently re-open quick actions so supervisor can pick the next step (kept for reference)
  // ignore: unused_element
  void _promptNextStep() => _showQuickActions();

  void _showMaterialEntry() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.3),
      enableDrag: true,
      isDismissible: true,
      builder: (context) => _MaterialEntrySheet(
        siteId: widget.site['id'],
        onSuccess: () {
          // Entry sheet already called Navigator.pop before this callback.
          // Reload data and reopen Quick Actions with fresh material status
          _entrySession.markComplete('material');
          print('✅ [ENTRY_SESSION] Material marked complete');
          _invalidateCache();
          _loadTodayEntries().then((_) {
            // After data loads, reopen Quick Actions with fresh state
            if (mounted) {
              _showQuickActions();
            }
          });
          SupervisorHistoryScreen.invalidateCache(widget.site['id']);
        },
        onMaterialUpdated: () {
          _loadTodayEntries();
        },
      ),
    );
  }

  void _invalidateCache() {
    print('🗑️ [SITE_DETAIL] Invalidating cache for site: $_siteId');
    // Remove all cache entries for this site
    _siteDataCache.removeWhere((key, value) => key.startsWith(_siteId));
    _cacheTimestamps.removeWhere((key, value) => key.startsWith(_siteId));
  }

  void _expandAllDates() {
    setState(() {
      // Get all dates from entries
      final allDates = <String>{};

      if (_todayEntries?['labour_entries'] != null) {
        for (var entry in _todayEntries!['labour_entries']) {
          final date = entry['entry_date'] ?? _formatSelectedDate();
          allDates.add(date);
        }
      }

      if (_todayEntries?['material_entries'] != null) {
        for (var entry in _todayEntries!['material_entries']) {
          final date = entry['entry_date'] ?? _formatSelectedDate();
          allDates.add(date);
        }
      }

      _expandedDates.addAll(allDates);
    });
  }

  void _collapseAllDates() {
    setState(() {
      _expandedDates.clear();
    });
  }

  @override
  void dispose() {
    // Optional: Clear cache for this site when screen is disposed
    // Uncomment if you want to clear cache on dispose
    // _invalidateCache();
    super.dispose();
  }

  // Method to force refresh data
  Future<void> _forceRefresh() async {
    _invalidateCache();
    await _loadTodayEntries();
  }

  void _showPhotoUpload({bool defaultToEvening = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupervisorPhotoUploadScreen(
          site: widget.site,
          defaultToEvening: defaultToEvening,
        ),
      ),
    ).then((_) {
      // Reload entries to get updated photo_count from server
      _loadTodayEntries().then((_) {
        if (!mounted) return;

        // Only mark photo complete if photos were actually uploaded
        final photoCount =
            (_todayEntries?['photo_count'] as num?)?.toInt() ?? 0;
        if (_entrySession.isActive &&
            photoCount > 0 &&
            !_entrySession.isPhotoComplete) {
          _entrySession.markComplete('photo');
          print('✅ [ENTRY_SESSION] Photo marked complete (count: $photoCount)');
        } else if (_entrySession.isActive && photoCount == 0) {
          print(
            '⚠️ [ENTRY_SESSION] No photos uploaded, photo NOT marked complete',
          );
        }

        // Always re-open quick actions after returning from photo upload
        // Sheet will be unlocked if labour+photo are done
        if (_entrySession.isActive) {
          _showQuickActions();
        } else {
          setState(() {}); // rebuild FAB
        }
      });
    });
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupervisorHistoryScreen(
          siteId: widget.site['id'],
          siteName:
              widget.site['display_name'] ?? widget.site['site_name'] ?? 'Site',
          showRequestButton:
              true, // Enable request button in site-specific history
        ),
      ),
    );
  }

  void _openMaterialInventory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SiteEngineerMaterialScreen(
          siteId: widget.site['id'],
          siteName: widget.site['display_name'] ?? widget.site['site_name'] ?? 'Site',
        ),
      ),
    ).then((_) {
      // Reload today's entries when returning from inventory
      _loadTodayEntries();
    });
  }

  void _showMaterialRequirementDialog() {
    final materialNameController = TextEditingController();
    final quantityController = TextEditingController();
    final unitController = TextEditingController();
    final notesController = TextEditingController();
    String selectedPriority = 'normal';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Material Requirement'),
          contentPadding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 0),
          content: SingleChildScrollView(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: materialNameController,
                    decoration: const InputDecoration(
                      labelText: 'Material Name *',
                      hintText: 'e.g., Cement, Steel, Bricks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantity *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: TextField(
                          controller: unitController,
                          decoration: const InputDecoration(
                            labelText: 'Unit *',
                            hintText: 'bags, tons',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  DropdownButtonFormField<String>(
                    value: selectedPriority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'urgent',
                        child: Text('🔴 Urgent'),
                      ),
                      DropdownMenuItem(
                        value: 'normal',
                        child: Text('🟡 Normal'),
                      ),
                      DropdownMenuItem(value: 'low', child: Text('🟢 Low')),
                    ],
                    onChanged: (value) {
                      setState(() => selectedPriority = value ?? 'normal');
                    },
                  ),
                  SizedBox(height: 16.h),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      hintText: 'Additional details...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (materialNameController.text.isEmpty ||
                    quantityController.text.isEmpty ||
                    unitController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all required fields'),
                    ),
                  );
                  return;
                }

                final result = await _constructionService
                    .submitMaterialRequirement(
                      siteId: widget.site['id'],
                      materialName: materialNameController.text,
                      quantity: double.parse(quantityController.text),
                      unit: unitController.text,
                      priority: selectedPriority,
                      notes: notesController.text,
                    );

                if (mounted) {
                  Navigator.pop(context);
                  if (result['success']) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result['message'] ?? 'Material requirement submitted',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result['error'] ??
                              'Failed to submit. Backend not ready yet.',
                        ),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _openExtraCostScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SiteExtraCostScreen(site: widget.site),
      ),
    );
  }

  bool _isToday() {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  _SiteEntryStatus get _todayEntryStatus {
    if (!_isToday()) return _SiteEntryStatus.none;

    final labourEntries = List<Map<String, dynamic>>.from(
      _todayEntries?['labour_entries'] ?? [],
    );
    final photoCount = (_todayEntries?['photo_count'] as num?)?.toInt() ?? 0;

    // No labour at all → not started
    if (labourEntries.isEmpty) return _SiteEntryStatus.none;

    // Check if locked by another supervisor
    if (_userId != null) {
      final hasOther = labourEntries.any((e) {
        final sid = (e['supervisor_id'] ?? e['user_id'])?.toString();
        return sid != null && sid != _userId;
      });
      if (hasOther) return _SiteEntryStatus.lockedByOther;
    }

    // All three required for display: labour + photo (material is one-time but optional for unlock)
    final hasLabour = labourEntries.isNotEmpty;
    final hasPhoto = photoCount > 0;

    if (hasLabour && hasPhoto) {
      return _SiteEntryStatus.dailyComplete;
    }

    // Partially done — still needs more entries
    return _SiteEntryStatus.none;
  }

  String _formatSelectedDate() {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Check if entry session is active and not complete
        if (_entrySession.isActive && !_entrySession.canExit) {
          _showSessionLockWarning();
          return false; // Block navigation
        }
        return true; // Allow navigation
      },
      child: Scaffold(
        backgroundColor: AppColors.lightSlate,
        body: RefreshIndicator(
          onRefresh: _forceRefresh,
          color: AppColors.safetyOrange,
          child: CustomScrollView(
            slivers: [
              // Site Header
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: AppColors.deepNavy,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.calendar_today, color: Colors.white),
                    onPressed: _selectDate,
                    tooltip: 'Select Date',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: (value) {
                      if (value == 'expand_all') {
                        _expandAllDates();
                      } else if (value == 'collapse_all') {
                        _collapseAllDates();
                      } else if (value == 'refresh') {
                        _forceRefresh();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'expand_all',
                        child: Row(
                          children: [
                            Icon(Icons.expand_more, size: 20),
                            SizedBox(width: 12),
                            Text('Expand All'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'collapse_all',
                        child: Row(
                          children: [
                            Icon(Icons.expand_less, size: 20),
                            SizedBox(width: 12),
                            Text('Collapse All'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'refresh',
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 20),
                            SizedBox(width: 12),
                            Text('Refresh Data'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.white),
                    onPressed: () => _openHistory(),
                    tooltip: 'View History',
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.lightSlate,
                              AppColors.deepNavy.withValues(alpha: 0.9),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.construction,
                            size: 100.sp,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.site['display_name'] ?? 'Site',
                              style: TextStyle(
                                fontSize: 28.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 16.sp,
                                  color: Colors.white70,
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  '${widget.site['area']} - ${widget.site['street']}',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12.h),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4.r),
                              child: LinearProgressIndicator(
                                value: 0.65,
                                minHeight: 8,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.3,
                                ),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.safetyOrange,
                                ),
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              '65% Complete',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Today's Entries with Dropdown
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _isToday()
                                  ? "Today's Entries"
                                  : "Entries for ${_formatSelectedDate()}",
                              style: TextStyle(
                                fontSize: 20.sp,
                                fontWeight: FontWeight.bold,
                                color: AppColors.deepNavy,
                              ),
                            ),
                          ),
                          // Inventory Button
                          ElevatedButton.icon(
                            onPressed: () => _openMaterialInventory(),
                            icon: Icon(Icons.inventory_2, size: 18.sp),
                            label: Text(
                              'Inventory',
                              style: TextStyle(fontSize: 13.sp),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.statusCompleted,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 8.h,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                            ),
                          ),
                          // Container(
                          //   decoration: BoxDecoration(
                          //     color: AppColors.deepNavy.withValues(alpha: 0.1),
                          //     borderRadius: BorderRadius.circular(12.r),
                          //   ),
                          //   child: Material(
                          //     color: Colors.transparent,
                          //     child: InkWell(
                          //       onTap: _selectDate,
                          //       borderRadius: BorderRadius.circular(12.r),
                          //       child: Padding(
                          //         padding: EdgeInsets.symmetric(
                          //           horizontal: 12.w,
                          //           vertical: 8.h,
                          //         ),
                          //         child: Row(
                          //           mainAxisSize: MainAxisSize.min,
                          //           children: [
                          //             Icon(
                          //               Icons.calendar_today,
                          //               size: 16.sp,
                          //               color: AppColors.deepNavy,
                          //             ),
                          //             SizedBox(width: 6.w),
                          //             Text(
                          //               _formatShortDate(),
                          //               style: TextStyle(
                          //                 fontSize: 13.sp,
                          //                 fontWeight: FontWeight.bold,
                          //                 color: AppColors.deepNavy,
                          //               ),
                          //             ),
                          //           ],
                          //         ),
                          //       ),
                          //     ),
                          //   ),
                          // ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      // Extra Cost Button
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () => _openExtraCostScreen(),
                          icon: Icon(Icons.attach_money, size: 18.sp),
                          label: Text(
                            'Extra Cost',
                            style: TextStyle(fontSize: 13.sp),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 8.h,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      // IST Time Display
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 8.h,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.statusCompleted.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(
                            color: AppColors.statusCompleted.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14.sp,
                              color: AppColors.statusCompleted,
                            ),
                            SizedBox(width: 6.w),
                            Text(
                              'IST: ${TimeValidator.formatISTTime(TimeValidator.getISTTime())}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: AppColors.statusCompleted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16.h),
                      if (_isToday()) _buildEntryStatusBanner(),
                      if (_isToday()) SizedBox(height: 12.h),
                      if (_isLoading)
                        const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.safetyOrange,
                          ),
                        )
                      else if (_todayEntries == null ||
                          (_todayEntries!['labour_entries']?.isEmpty ?? true) &&
                              (_todayEntries!['material_entries']?.isEmpty ??
                                  true))
                        _buildEmptyState()
                      else
                        _buildEntriesWithDropdown(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _buildCentralFAB(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildEntryStatusBanner() {
    final status = _todayEntryStatus;
    final labourEntries = List<Map<String, dynamic>>.from(
      _todayEntries?['labour_entries'] ?? [],
    );
    final photoCount = (_todayEntries?['photo_count'] as num?)?.toInt() ?? 0;
    final materialSubmitted =
        _todayEntries?['material_submitted_today'] == true;

    switch (status) {
      case _SiteEntryStatus.dailyComplete:
        return _statusBanner(
          icon: Icons.check_circle,
          label:
              'Day complete — Labour & Photo submitted ✓${materialSubmitted ? "  Material ✓" : ""}',
          color: Colors.green.shade600,
          bgColor: Colors.green.shade50,
        );
      case _SiteEntryStatus.lockedByOther:
        return _statusBanner(
          icon: Icons.lock,
          label: 'Locked — Another supervisor submitted today',
          color: Colors.grey.shade700,
          bgColor: Colors.grey.shade100,
        );
      default:
        if (labourEntries.isNotEmpty || photoCount > 0) {
          final parts = <String>[];
          if (labourEntries.isNotEmpty) parts.add('Labour ✓');
          if (materialSubmitted) parts.add('Material ✓');
          if (photoCount > 0) parts.add('Photo ✓');
          return _statusBanner(
            icon: Icons.pending_outlined,
            label: 'In progress: ${parts.join(', ')} — Tap + to complete',
            color: Colors.orange.shade700,
            bgColor: Colors.orange.shade50,
          );
        }
        return _statusBanner(
          icon: Icons.add_circle_outline,
          label: 'No entries yet — Tap + to start daily entry',
          color: AppColors.deepNavy,
          bgColor: AppColors.deepNavy.withValues(alpha: 0.05),
        );
    }
  }

  Widget _statusBanner({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18.sp, color: color),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: EdgeInsets.all(32.r),
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        children: [
          Container(
            width: 80.w,
            height: 80.h,
            decoration: BoxDecoration(
              color: AppColors.lightSlate,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_circle_outline,
              size: 40.sp,
              color: AppColors.deepNavy,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            _isToday() ? 'No entries yet today' : 'No entries for this date',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.deepNavy,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            _isToday()
                ? 'Tap the + button to add labour or materials'
                : 'No data was recorded on this date',
            style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesWithDropdown() {
    // Group entries by date and type
    final Map<String, Map<String, List<Map<String, dynamic>>>> groupedEntries =
        {};

    // Process labour entries
    if (_todayEntries?['labour_entries'] != null) {
      for (var entry in _todayEntries!['labour_entries']) {
        final date = entry['entry_date'] ?? _formatSelectedDate();
        if (!groupedEntries.containsKey(date)) {
          groupedEntries[date] = {'labour': [], 'material': []};
        }
        groupedEntries[date]!['labour']!.add(entry);
      }
    }

    // Process material entries
    if (_todayEntries?['material_entries'] != null) {
      for (var entry in _todayEntries!['material_entries']) {
        final date = entry['entry_date'] ?? _formatSelectedDate();
        if (!groupedEntries.containsKey(date)) {
          groupedEntries[date] = {'labour': [], 'material': []};
        }
        groupedEntries[date]!['material']!.add(entry);
      }
    }

    // If no entries, show empty state
    if (groupedEntries.isEmpty) {
      return _buildEmptyState();
    }

    // Sort dates (most recent first)
    final sortedDates = groupedEntries.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      children: sortedDates.map((date) {
        final dateEntries = groupedEntries[date]!;
        final labourEntries = dateEntries['labour']!;
        final materialEntries = dateEntries['material']!;

        if (labourEntries.isEmpty && materialEntries.isEmpty)
          return const SizedBox.shrink();

        return _buildDateDropdownCard(date, labourEntries, materialEntries);
      }).toList(),
    );
  }

  Widget _buildDateDropdownCard(
    String date,
    List<Map<String, dynamic>> labourEntries,
    List<Map<String, dynamic>> materialEntries,
  ) {
    final isExpanded = _expandedDates.contains(date);
    final formattedDate = _formatDateForDropdown(date);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [AppColors.cardShadow],
      ),
      child: Column(
        children: [
          // Dropdown Header - Always visible
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
                  color: isExpanded
                      ? AppColors.deepNavy.withValues(alpha: 0.05)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: isExpanded
                        ? AppColors.deepNavy.withValues(alpha: 0.2)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Calendar Icon
                    Container(
                      padding: EdgeInsets.all(10.r),
                      decoration: BoxDecoration(
                        gradient: isExpanded ? AppColors.navyGradient : null,
                        color: isExpanded
                            ? null
                            : AppColors.deepNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(
                        Icons.calendar_today,
                        color: isExpanded ? Colors.white : AppColors.deepNavy,
                        size: 20.sp,
                      ),
                    ),
                    SizedBox(width: 16.w),

                    // Date and Entry Count
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
                          Row(
                            children: [
                              if (labourEntries.isNotEmpty) ...[
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 4.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.safetyOrange.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Text(
                                    '${labourEntries.length} labour',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.safetyOrange,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8.w),
                              ],
                              if (materialEntries.isNotEmpty) ...[
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 4.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusCompleted.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Text(
                                    '${materialEntries.length} material',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.statusCompleted,
                                    ),
                                  ),
                                ),
                              ],
                              if (isExpanded) ...[
                                SizedBox(width: 8.w),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.deepNavy.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(6.r),
                                  ),
                                  child: Text(
                                    'EXPANDED',
                                    style: TextStyle(
                                      fontSize: 10.sp,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.deepNavy,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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

          // Expandable Content
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: isExpanded ? null : 0,
            child: isExpanded
                ? Container(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                    child: Column(
                      children: [
                        const Divider(color: AppColors.lightSlate, height: 1),
                        SizedBox(height: 16.h),
                        // Labour entries
                        ...labourEntries.map(
                          (entry) => _buildLabourCard(entry),
                        ),
                        // Material entries
                        ...materialEntries.map(
                          (entry) => _buildMaterialCard(entry),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  String _formatDateForDropdown(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final entryDate = DateTime(date.year, date.month, date.day);

      if (entryDate == today) {
        return 'Today • ${_formatDateWithDay(date)}';
      } else if (entryDate == yesterday) {
        return 'Yesterday • ${_formatDateWithDay(date)}';
      } else {
        return _formatDateWithDay(date);
      }
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDateWithDay(DateTime date) {
    final days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dayName = days[date.weekday % 7];
    return '$dayName, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildLabourCard(Map<String, dynamic> entry) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: AppColors.safetyOrange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColors.safetyOrange.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.h,
            decoration: BoxDecoration(
              gradient: AppColors.orangeGradient,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.people, color: Colors.white, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['labour_type'] ?? 'General',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepNavy,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  '${entry['labour_count']} workers',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (entry['entry_time'] != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    'Time: ${entry['entry_time']}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              gradient: AppColors.orangeGradient,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              '${entry['labour_count']}',
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

  Widget _buildMaterialCard(Map<String, dynamic> entry) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: AppColors.statusCompleted.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColors.statusCompleted.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.h,
            decoration: BoxDecoration(
              gradient: AppColors.greenGradient,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.inventory_2, color: Colors.white, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['material_type'] ?? 'Material',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepNavy,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  '${entry['quantity']} ${entry['unit'] ?? 'units'}',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (entry['entry_time'] != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    'Time: ${entry['entry_time']}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${entry['quantity']?.toString() ?? '0'}',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.statusCompleted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCentralFAB() {
    // While reloading after a submission, trust the local session state so the
    // FAB never flashes back to the "not started" orange + before data arrives.
    if (_isLoading &&
        _entrySession.isActive &&
        _entrySession.isLabourComplete &&
        _entrySession.isPhotoComplete) {
      return GestureDetector(
        onTap: () => _handleFABTap(),
        child: Container(
          width: 64.w,
          height: 64.h,
          decoration: BoxDecoration(
            color: Colors.green.shade600,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.check_circle, size: 30, color: Colors.white),
        ),
      );
    }

    final status = _todayEntryStatus;

    // Locked by another supervisor — tap opens read-only history
    if (status == _SiteEntryStatus.lockedByOther) {
      return GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Entry already submitted by another supervisor. Opening history…',
              ),
              backgroundColor: Colors.grey.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          );
          _openHistory();
        },
        child: Container(
          width: 64.w,
          height: 64.h,
          decoration: BoxDecoration(
            color: Colors.grey.shade500,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.lock, size: 30, color: Colors.white),
        ),
      );
    }

    // Day complete — green check, tapping navigates to evening update
    if (status == _SiteEntryStatus.dailyComplete) {
      return GestureDetector(
        onTap: () => _handleFABTap(),
        child: Container(
          width: 64.w,
          height: 64.h,
          decoration: BoxDecoration(
            color: Colors.green.shade600,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.check_circle, size: 30, color: Colors.white),
        ),
      );
    }

    // Default — needs entries, check lock before opening
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: AppColors.orangeGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.safetyOrange.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleFABTap(),
          borderRadius: BorderRadius.circular(32),
          child: const Icon(Icons.add, size: 32, color: Colors.white),
        ),
      ),
    );
  }

  /// Handle FAB tap with proper lock checking and navigation logic
  Future<void> _handleFABTap() async {
    if (!_isToday()) {
      // Not today - just show quick actions for viewing
      _showQuickActions();
      return;
    }

    // Wait for data to finish loading — avoids opening a locked sheet because
    // _todayEntries is still null right after login/page open.
    if (_isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading site data...'),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    final status = _todayEntryStatus;
    final labourEntries = List<Map<String, dynamic>>.from(
      _todayEntries?['labour_entries'] ?? [],
    );
    final photoCount = (_todayEntries?['photo_count'] as num?)?.toInt() ?? 0;

    // Another supervisor owns today's entries — read-only history only
    if (status == _SiteEntryStatus.lockedByOther) {
      _openHistory();
      return;
    }

    // Morning complete — open unlocked Quick Actions so supervisor can
    // freely view, add evening entries, or close without restriction.
    if (status == _SiteEntryStatus.dailyComplete ||
        (_entrySession.isLabourComplete && _entrySession.isPhotoComplete)) {
      print('✅ [FAB] Morning complete, opening unlocked quick actions');
      _showQuickActions();
      return;
    }

    // If no entries yet, check lock before opening quick actions
    if (labourEntries.isEmpty && photoCount == 0) {
      print('🔍 [FAB] No entries yet, checking lock...');
      await _checkEntryLockAndShowQuickActions();
      return;
    }

    // If entries exist but not complete, show quick actions
    print('📋 [FAB] Entries in progress, showing quick actions');
    _showQuickActions();
  }

  /// Check entry lock and then show quick actions (not labour entry directly)
  Future<void> _checkEntryLockAndShowQuickActions() async {
    final now = DateTime.now();
    final entryDate = DateFormat('yyyy-MM-dd').format(now);

    print('🔍 [ENTRY_LOCK] Checking lock before opening quick actions...');

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final result = await _constructionService.checkEntryLock(
      siteId: widget.site['id'].toString(),
      entryDate: entryDate,
    );

    // Close loading indicator
    if (mounted) Navigator.pop(context);

    if (!result['success']) {
      // Network error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check entry status: ${result['error']}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
      return;
    }

    if (result['is_locked'] == true) {
      // Site is locked by another supervisor
      _showEntryLockedDialog(
        lockedBy: result['locked_by'] ?? 'Another supervisor',
        lockedAt: result['locked_at'] ?? 'earlier',
        entries: List<Map<String, dynamic>>.from(result['entries'] ?? []),
      );
      return;
    }

    // Site is available — ensure today's data is loaded so the sheet can
    // correctly reflect labour+photo done state after a re-login.
    print('✅ [ENTRY_LOCK] Site available, opening quick actions');
    if (_todayEntries == null && !_isLoading) {
      await _loadTodayEntries();
    }
    if (mounted) _showQuickActions();
  }
}

// Quick Actions Sheet — locked until labour + photo are done
class _QuickActionsSheet extends StatefulWidget {
  final EntrySession entrySession;
  final bool materialSubmittedToday;
  final bool hasLabourData; // From server
  final bool hasPhotoData; // From server
  final VoidCallback onLabourTap;
  final VoidCallback onMaterialTap;
  final VoidCallback onPhotoTap;
  final VoidCallback onHistoryTap;
  final VoidCallback onMaterialRequirementTap;
  final VoidCallback onAllComplete;

  const _QuickActionsSheet({
    required this.entrySession,
    required this.materialSubmittedToday,
    required this.hasLabourData,
    required this.hasPhotoData,
    required this.onLabourTap,
    required this.onMaterialTap,
    required this.onPhotoTap,
    required this.onHistoryTap,
    required this.onMaterialRequirementTap,
    required this.onAllComplete,
  });

  @override
  State<_QuickActionsSheet> createState() => _QuickActionsSheetState();
}

class _QuickActionsSheetState extends State<_QuickActionsSheet> {
  @override
  void initState() {
    super.initState();
    // Listen to session changes so the sheet rebuilds when steps complete
    widget.entrySession.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.entrySession.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {}); // rebuild when session state changes
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.entrySession;
    final materialDone = widget.materialSubmittedToday;
    // Combine server data with live session state so the sheet updates immediately
    // after submission without needing a full data reload.
    final labourDone = widget.hasLabourData || session.isLabourComplete;
    final photoDone = widget.hasPhotoData || session.isPhotoComplete;
    final allDone = labourDone && photoDone && materialDone;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No drag handle — sheet is locked
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.deepNavy,
                ),
              ),
              const SizedBox(width: 8),
              if (!allDone)
                Icon(Icons.lock, size: 16, color: Colors.grey.shade500),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            allDone
                ? 'Labour, Photo & Material done — you can go back anytime'
                : 'Complete Labour, Photo & Material to go back',
            style: TextStyle(
              fontSize: 12,
              color: allDone ? Colors.green.shade600 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 20),
          // Labour — required (can reopen for evening update after completion)
          _buildActionCard(
            icon: Icons.people_outline,
            title: 'Labour Count',
            subtitle: labourDone
                ? 'Tap to add evening update'
                : 'Add workers by type',
            color: AppColors.deepNavy,
            isDone: labourDone,
            isLocked: false, // Allow reopening for evening update
            onTap: widget.onLabourTap, // Always allow tap
          ),
          const SizedBox(height: 12),
          // Material — one-time per site per day (required for unlock)
          _buildActionCard(
            icon: Icons.inventory_2_outlined,
            title: 'Material Balance',
            subtitle: materialDone
                ? 'Completed ✓'
                : 'Update materials — required to continue',
            color: AppColors.statusCompleted,
            isDone: materialDone,
            isLocked: materialDone,
            onTap: materialDone ? null : widget.onMaterialTap,
          ),
          const SizedBox(height: 12),
          // Photo — can add more photos for evening
          _buildActionCard(
            icon: Icons.add_a_photo_outlined,
            title: 'Add Photo',
            subtitle: photoDone
                ? 'Tap to add evening photos'
                : 'Upload site progress pictures',
            color: AppColors.safetyOrange,
            isDone: photoDone,
            isLocked: false, // Always allow adding more photos
            onTap: widget.onPhotoTap, // Always tappable
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.add_shopping_cart_outlined,
            title: 'Material Requirement',
            subtitle: 'Request materials needed',
            color: const Color(0xFF1E3A8A),
            isDone: false,
            isLocked: false,
            onTap: widget.onMaterialRequirementTap,
          ),
          const SizedBox(height: 20),
          // Done button — enabled when labour + photo complete
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: allDone ? widget.onAllComplete : null,
              icon: Icon(allDone ? Icons.check_circle : Icons.lock, size: 20),
              label: Text(
                allDone ? 'Done' : 'Complete Labour, Photo & Material to go back',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: allDone
                    ? Colors.green.shade600
                    : Colors.grey.shade300,
                foregroundColor: allDone ? Colors.white : Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDone,
    required bool isLocked,
    required VoidCallback? onTap,
  }) {
    // isLocked = greyed out, one-time submitted (material)
    final effectiveColor = isDone
        ? Colors.green.shade600
        : isLocked
        ? Colors.grey.shade400
        : color;
    return Material(
      color: isDone
          ? Colors.green.withValues(alpha: 0.08)
          : isLocked
          ? Colors.grey.withValues(alpha: 0.06)
          : effectiveColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDone
                      ? Colors.green.withValues(alpha: 0.2)
                      : isLocked
                      ? Colors.grey.withValues(alpha: 0.12)
                      : effectiveColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isDone
                      ? Icons.check_circle
                      : isLocked
                      ? Icons.lock_outline
                      : icon,
                  color: effectiveColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: effectiveColor,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDone ? 'Completed ✓' : subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDone
                            ? Colors.green.shade600
                            : isLocked
                            ? Colors.grey.shade400
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isDone)
                Icon(Icons.arrow_forward_ios, size: 16, color: effectiveColor),
            ],
          ),
        ),
      ),
    );
  }
}

// Labour Entry Sheet with Multiple Types
class _LabourEntrySheet extends StatefulWidget {
  final String siteId;
  final VoidCallback onSuccess;
  final bool defaultToEvening;
  final bool morningAlreadySubmitted;

  const _LabourEntrySheet({
    required this.siteId,
    required this.onSuccess,
    this.defaultToEvening = false,
    this.morningAlreadySubmitted = false,
  });

  @override
  State<_LabourEntrySheet> createState() => _LabourEntrySheetState();
}

class _LabourEntrySheetState extends State<_LabourEntrySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _constructionService = ConstructionService();
  final _budgetService = BudgetManagementService();

  // Dynamic labour counts for morning and evening
  Map<String, int> _morningLabourCounts = {};
  Map<String, int> _eveningLabourCounts = {};

  // Morning data for evening display
  Map<String, dynamic>? _morningData;
  bool _isLoadingMorningData = false;

  // Evening history data
  List<Map<String, dynamic>> _eveningHistoryData = [];
  bool _isLoadingEveningData = false;

  // Default salary rates (used if admin hasn't set custom rates)
  // Rates loaded from admin global rates (single source of truth)
  Map<String, double> _rates = {};
  bool _isLoadingRates = true;

  bool _isSubmitting = false;
  late DateTime _morningSelectedDateTime;
  late DateTime _eveningSelectedDateTime;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.defaultToEvening ? 1 : 0,
    );
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        // Load both morning data and evening history when evening tab is opened
        if (_eveningHistoryData.isEmpty) {
          _loadEveningHistory();
        }
        _loadMorningData();
      }
    });
    _morningSelectedDateTime = DateTime.now();
    _eveningSelectedDateTime = DateTime.now();
    _fetchRates();
    // If opening directly at evening tab, pre-load morning/evening data
    if (widget.defaultToEvening) {
      _loadMorningData();
      _loadEveningHistory();
    }
  }

  Future<void> _loadMorningData() async {
    setState(() => _isLoadingMorningData = true);
    try {
      print('🔍 Loading morning data for site: ${widget.siteId}');
      final response = await _constructionService.getHistoryByDay(
        siteId: widget.siteId,
      );

      if (response['success']) {
        final data = response['data'] as Map<String, dynamic>;
        final labourByDay =
            data['labour_by_day'] as Map<String, dynamic>? ?? {};

        // Get today's day of week (e.g., "Tuesday")
        final today = DateTime.now();
        final dayNames = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];
        final todayDayName = dayNames[today.weekday - 1];

        // Get today's date in YYYY-MM-DD format for filtering
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        print('📅 Today is: $todayDayName ($todayStr)');
        print('📦 Available days in response: ${labourByDay.keys.toList()}');

        // Get entries for today's day of week, then filter by actual date
        List<Map<String, dynamic>> todayEntries = [];

        if (labourByDay.containsKey(todayDayName)) {
          final dayEntries = labourByDay[todayDayName] as List;
          print('✅ Found ${dayEntries.length} entries for $todayDayName');

          for (var entry in dayEntries) {
            final entryDate = entry['entry_date'] as String?;
            print(
              '  - Checking entry: ${entry['labour_type']} on date $entryDate',
            );

            // Only include entries from today's actual date
            if (entryDate != null && entryDate.startsWith(todayStr)) {
              todayEntries.add(Map<String, dynamic>.from(entry));
              print(
                '    ✅ Added: ${entry['labour_type']}: ${entry['labour_count']} workers',
              );
            } else {
              print('    ❌ Skipped: date $entryDate does not match $todayStr');
            }
          }
        } else {
          print('❌ No entries found for $todayDayName');
        }

        print('✅ Total entries loaded for today: ${todayEntries.length}');

        setState(() {
          _morningData = todayEntries.isNotEmpty
              ? {'entries': todayEntries}
              : null;
        });
      } else {
        print('❌ Failed to load morning data: ${response['error']}');
      }
    } catch (e) {
      print('❌ Error loading morning data: $e');
      print('Stack trace: ${StackTrace.current}');
    } finally {
      setState(() => _isLoadingMorningData = false);
    }
  }

  Future<void> _loadEveningHistory() async {
    setState(() => _isLoadingEveningData = true);
    try {
      print('🔍 Loading evening history for site: ${widget.siteId}');
      final response = await _constructionService.getHistoryByDay(
        siteId: widget.siteId,
      );

      if (response['success']) {
        final data = response['data'] as Map<String, dynamic>;
        final labourByDay =
            data['labour_by_day'] as Map<String, dynamic>? ?? {};

        // Get today's date in YYYY-MM-DD format
        final today = DateTime.now();
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        // Filter entries to only include today's data
        List<Map<String, dynamic>> todayEntries = [];
        labourByDay.forEach((day, entries) {
          if (entries is List && day == todayStr) {
            todayEntries.addAll(List<Map<String, dynamic>>.from(entries));
          }
        });

        print(
          '✅ Loaded ${todayEntries.length} evening labour entries for today ($todayStr)',
        );

        setState(() {
          _eveningHistoryData = todayEntries;
        });
      } else {
        print('❌ Failed to load evening history: ${response['error']}');
      }
    } catch (e) {
      print('❌ Error loading evening history: $e');
    } finally {
      setState(() => _isLoadingEveningData = false);
    }
  }

  Future<void> _fetchRates() async {
    setState(() => _isLoadingRates = true);

    final rates = await _budgetService.getLabourRates('global');
    if (rates.isNotEmpty && mounted) {
      final Map<String, double> loaded = {};
      final Map<String, int> morningCounts = {};
      final Map<String, int> eveningCounts = {};

      for (final r in rates) {
        final type = r['labour_type'] as String?;
        final rate = (r['daily_rate'] as num?)?.toDouble();
        if (type != null && rate != null) {
          loaded[type] = rate;
          // Initialize counts to 0 for each labour type
          morningCounts[type] = 0;
          eveningCounts[type] = 0;
        }
      }

      setState(() {
        _rates = loaded;
        _morningLabourCounts = morningCounts;
        _eveningLabourCounts = eveningCounts;
        _isLoadingRates = false;
      });

      print('✅ Loaded ${loaded.length} labour types from admin');
    } else {
      setState(() => _isLoadingRates = false);
    }
  }

  // Get current tab's labour counts
  Map<String, int> get _currentLabourCounts =>
      _tabController.index == 0 ? _morningLabourCounts : _eveningLabourCounts;

  int get _totalCount =>
      _currentLabourCounts.values.fold(0, (sum, count) => sum + count);

  double get _totalSalary => _currentLabourCounts.entries.fold(
    0,
    (sum, e) => sum + e.value * (_rates[e.key] ?? 0),
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTime = TimeValidator.isLabourEntryOnTime();
    final isMorningTab = _tabController.index == 0;
    return WillPopScope(
      onWillPop: () async {
        // STRICT LOCK: Block back navigation completely if any entries started
        final hasEntries = _currentLabourCounts.values.any(
          (count) => count > 0,
        );

        if (hasEntries) {
          // Show warning message - DO NOT allow back
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '⚠️ Please complete and submit labour entries, material updates, and photos before going back.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          // BLOCK back navigation
          return false;
        }

        // No entries started, allow back navigation
        return true;
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // Title + date
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.deepNavy,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.groups_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Labour count',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.deepNavy,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, d MMM').format(DateTime.now()),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Status + entry time
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoChip(
                    icon: onTime ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    label: onTime
                        ? 'On time · before 12:00 PM'
                        : 'Late entry · admin will be notified',
                    color: onTime ? const Color(0xFF15803D) : const Color(0xFFC2410C),
                  ),
                  if (isMorningTab && !widget.morningAlreadySubmitted)
                    _infoChip(
                      icon: Icons.access_time_rounded,
                      label: '${_formatTime(_morningSelectedDateTime)} · Change',
                      color: AppColors.deepNavy,
                      onTap: () => _selectTime(true),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Morning / Evening segmented control
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 46,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9ECF2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabController,
                  onTap: (index) {
                    // Morning tab is blocked once morning entry is submitted
                    if (index == 0 && widget.morningAlreadySubmitted) {
                      _tabController.animateTo(1);
                      return;
                    }
                    setState(() {});
                  },
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  labelColor: AppColors.deepNavy,
                  unselectedLabelColor: Colors.grey.shade600,
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  unselectedLabelStyle:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  tabs: [
                    Tab(
                      child: Opacity(
                        opacity: widget.morningAlreadySubmitted ? 0.45 : 1.0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.morningAlreadySubmitted
                                  ? Icons.lock_rounded
                                  : Icons.wb_sunny_rounded,
                              size: 17,
                            ),
                            const SizedBox(width: 6),
                            const Text('Morning'),
                          ],
                        ),
                      ),
                    ),
                    const Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nights_stay_rounded, size: 17),
                          SizedBox(width: 6),
                          Text('Evening'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                // Disable swipe to morning when morning is already submitted
                physics: widget.morningAlreadySubmitted
                    ? const NeverScrollableScrollPhysics()
                    : null,
                children: [
                  _buildTabContent(true), // Morning
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildTabContent(false), // Evening
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static final _rupees = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  Widget _buildTabContent(bool isMorning) {
    // Show loading indicator while rates are being fetched
    if (_isLoadingRates) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading labour types...',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Show message if no labour types are available
    if (_morningLabourCounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No Labour Types Available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Admin needs to add labour types first',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // For evening tab, show morning data in read-only format
    if (!isMorning) {
      return _buildEveningDisplayContent();
    }

    // Morning tab - editable form
    final labourCounts = _morningLabourCounts;
    final morningLocked = widget.morningAlreadySubmitted;
    final types = labourCounts.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Locked banner — shown when this supervisor already submitted morning
        if (morningLocked)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Morning labour already submitted for today',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            'Tap + / − or tap a number to type it',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            itemCount: types.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildLabourTypeRow(types[i], isMorning),
          ),
        ),

        _buildSubmitBar(isMorning),
      ],
    );
  }

  /// Sticky bottom bar: running totals + submit.
  Widget _buildSubmitBar(bool isMorning) {
    final enabled = _totalCount > 0 &&
        !_isSubmitting &&
        !(isMorning && widget.morningAlreadySubmitted);
    final typesSelected = _currentLabourCounts.values.where((c) => c > 0).length;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _totalCount == 1 ? '1 worker' : '$_totalCount workers',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepNavy,
                  ),
                ),
                Text(
                  _totalCount == 0
                      ? 'Add workers to submit'
                      : '${_rupees.format(_totalSalary)} · $typesSelected type${typesSelected == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _totalCount == 0
                        ? Colors.grey.shade500
                        : const Color(0xFF15803D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: enabled ? () => _submit(isMorning) : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.safetyOrange,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.check_rounded, color: Colors.white),
              label: Text(
                _isSubmitting ? 'Submitting…' : 'Submit',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEveningDisplayContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Today's Labour Entries Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade600, Colors.orange.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.wb_sunny, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Today\'s Labour Entries',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _isLoadingMorningData
                            ? 'Loading...'
                            : _morningData != null
                            ? '${(_morningData!['entries'] as List).length} entries found'
                            : 'No entries yet',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingMorningData)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Display morning entries
          if (_isLoadingMorningData)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.safetyOrange),
              ),
            )
          else if (_morningData != null && _morningData!['entries'] != null)
            ..._buildMorningEntriesDisplay(
              _morningData!['entries'] as List<Map<String, dynamic>>,
            )
          else
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.wb_sunny_outlined,
                    size: 48,
                    color: Colors.orange.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No labour entries found for today',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 32),

          // Evening History Section
          if (_isLoadingEveningData)
            const Center(
              child: CircularProgressIndicator(color: AppColors.safetyOrange),
            )
          else if (_eveningHistoryData.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.nightlight_outlined,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Evening History Found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No evening labour entries have been submitted yet',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._buildEveningHistoryDisplay(),
        ],
      ),
    );
  }

  List<Widget> _buildMorningEntriesDisplay(List<Map<String, dynamic>> entries) {
    // Calculate totals
    int totalWorkers = 0;
    double totalSalary = 0.0;
    double totalExtraCost = 0.0;

    for (final entry in entries) {
      totalWorkers += (entry['labour_count'] as num?)?.toInt() ?? 0;
      final labourType = entry['labour_type'] as String? ?? 'General';
      final count = (entry['labour_count'] as num?)?.toInt() ?? 0;
      final rate = _rates[labourType] ?? 600;
      totalSalary += count * rate;
      totalExtraCost += (entry['extra_cost'] as num?)?.toDouble() ?? 0.0;
    }

    return [
      // Summary card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text(
                  '$totalWorkers',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
                Text(
                  'Workers',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            Container(width: 1, height: 40, color: Colors.orange.shade300),
            Column(
              children: [
                Text(
                  '₹${totalSalary.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                Text(
                  'Total Cost',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            if (totalExtraCost > 0) ...[
              Container(width: 1, height: 40, color: Colors.orange.shade300),
              Column(
                children: [
                  Text(
                    '₹${totalExtraCost.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  Text(
                    'Extra Cost',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),

      // Labour entries
      ...entries.map((entry) {
        final labourType = entry['labour_type'] as String? ?? 'General';
        final count = (entry['labour_count'] as num?)?.toInt() ?? 0;
        final entryTime = entry['entry_time'] as String?;
        final notes = entry['notes'] as String?;
        final extraCost = (entry['extra_cost'] as num?)?.toDouble() ?? 0.0;
        final extraCostNotes = entry['extra_cost_notes'] as String?;

        return _buildHistoryLabourRow(
          labourType,
          count,
          entryTime,
          notes,
          extraCost,
          extraCostNotes,
        );
      }).toList(),
    ];
  }

  List<Widget> _buildEveningHistoryDisplay() {
    // Group entries by date for better display
    final entriesByDate = <String, List<Map<String, dynamic>>>{};
    for (final entry in _eveningHistoryData) {
      final date = entry['entry_date'] as String? ?? 'Unknown';
      if (!entriesByDate.containsKey(date)) {
        entriesByDate[date] = [];
      }
      entriesByDate[date]!.add(entry);
    }

    // Sort dates in descending order (most recent first)
    final sortedDates = entriesByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return [
      // Header
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo.shade700, Colors.indigo.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.nightlight, color: Colors.white, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Evening History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${_eveningHistoryData.length} entries found',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // Display entries grouped by date
      ...sortedDates.map((date) {
        final entries = entriesByDate[date]!;

        // Calculate totals for this date
        int totalWorkers = 0;
        double totalSalary = 0.0;

        for (final entry in entries) {
          totalWorkers += (entry['labour_count'] as num?)?.toInt() ?? 0;
          // Calculate salary based on labour type and count
          final labourType = entry['labour_type'] as String? ?? 'General';
          final count = (entry['labour_count'] as num?)?.toInt() ?? 0;
          final rate = _rates[labourType] ?? 600;
          totalSalary += count * rate;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.deepNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: AppColors.deepNavy,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(date),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.deepNavy,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$totalWorkers workers • ₹${totalSalary.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Labour entries for this date
            ...entries.map((entry) {
              final labourType = entry['labour_type'] as String? ?? 'General';
              final count = (entry['labour_count'] as num?)?.toInt() ?? 0;
              final entryTime = entry['entry_time'] as String?;
              final notes = entry['notes'] as String?;
              final extraCost =
                  (entry['extra_cost'] as num?)?.toDouble() ?? 0.0;
              final extraCostNotes = entry['extra_cost_notes'] as String?;

              return _buildHistoryLabourRow(
                labourType,
                count,
                entryTime,
                notes,
                extraCost,
                extraCostNotes,
              );
            }),

            const SizedBox(height: 24),
          ],
        );
      }).toList(),
    ];
  }

  Widget _buildHistoryLabourRow(
    String type,
    int count,
    String? entryTime,
    String? notes,
    double extraCost,
    String? extraCostNotes,
  ) {
    final icon = _getLabourIcon(type);
    final rate = _rates[type] ?? 600;
    final rowTotal = count * rate;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.deepNavy.withValues(alpha: 0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.deepNavy,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    if (entryTime != null)
                      Text(
                        'Time: ${_formatTimeFromString(entryTime)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$count workers',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.deepNavy,
                    ),
                  ),
                  Text(
                    '₹${rowTotal.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Notes
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.note, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      notes,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Extra cost
          if (extraCost > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.attach_money,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Extra Cost: ₹${extraCost.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  if (extraCostNotes != null && extraCostNotes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      extraCostNotes,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTimeFromString(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return isoTime;
    }
  }

  static const _maxPerType = 50;

  Widget _buildLabourTypeRow(String type, bool isMorning) {
    final labourCounts = isMorning
        ? _morningLabourCounts
        : _eveningLabourCounts;
    final count = labourCounts[type]!;
    final active = count > 0;
    final rate = _rates[type] ?? 0;
    final locked = isMorning && widget.morningAlreadySubmitted;

    void setCount(int value) =>
        setState(() => labourCounts[type] = value.clamp(0, _maxPerType));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: active ? AppColors.deepNavy.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.deepNavy.withValues(alpha: 0.35)
              : const Color(0xFFE5E7EB),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: active ? AppColors.deepNavy : const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getLabourIcon(type),
              size: 21,
              color: active ? Colors.white : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? AppColors.deepNavy : const Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  active
                      ? '${_rupees.format(rate)} × $count = ${_rupees.format(rate * count)}'
                      : '${_rupees.format(rate)} / day',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: active ? const Color(0xFF15803D) : Colors.grey.shade500,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Stepper: − [count] +   (tap the count to type it)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stepperButton(
                  icon: Icons.remove_rounded,
                  onTap: !locked && count > 0 ? () => setCount(count - 1) : null,
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: locked ? null : () => _typeCount(type, count, setCount),
                  child: SizedBox(
                    width: 38,
                    height: 40,
                    child: Center(
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: active ? AppColors.deepNavy : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                ),
                _stepperButton(
                  icon: Icons.add_rounded,
                  filled: true,
                  onTap: !locked && count < _maxPerType ? () => setCount(count + 1) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: filled && enabled ? AppColors.deepNavy : Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              size: 20,
              color: !enabled
                  ? Colors.grey.shade400
                  : filled
                      ? Colors.white
                      : AppColors.deepNavy,
            ),
          ),
        ),
      ),
    );
  }

  /// Type a count directly instead of tapping + many times.
  Future<void> _typeCount(
    String type,
    int current,
    void Function(int) setCount,
  ) async {
    final controller = TextEditingController(text: current > 0 ? '$current' : '');
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(type),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Number of workers',
              helperText: '0 – $_maxPerType',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim()) ?? 0;
              return n > _maxPerType ? 'Maximum is $_maxPerType' : null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, int.tryParse(controller.text.trim()) ?? 0);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, int.tryParse(controller.text.trim()) ?? 0);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) setCount(value);
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

  Future<void> _submit(bool isMorning) async {
    final labourCounts = isMorning
        ? _morningLabourCounts
        : _eveningLabourCounts;
    final selectedDateTime = isMorning
        ? _morningSelectedDateTime
        : _eveningSelectedDateTime;

    // Check if labour entry is on time
    final isOnTime = TimeValidator.isLabourEntryOnTime();

    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmationDialog(
        title: 'Confirm ${isMorning ? "Morning" : "Evening"} Labour Entry',
        entries: labourCounts.entries
            .where((e) => e.value > 0)
            .map((e) => {'type': e.key, 'count': e.value})
            .toList(),
        totalCount: _totalCount,
        isLabour: true,
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    // Submit all labour types at once (each is its own entry, and the backend's
    // unique lock guards duplicates), instead of waiting for them one by one.
    final toSubmit = labourCounts.entries.where((e) => e.value > 0).toList();
    final results = await Future.wait(
      toSubmit.map(
        (entry) => _constructionService
            .submitLabourCount(
              siteId: widget.siteId,
              labourCount: entry.value,
              labourType: entry.key,
              customDateTime: selectedDateTime,
            )
            .catchError((Object e) => <String, dynamic>{'success': false, 'error': '$e'}),
      ),
    );

    final errors = <String>[];
    int successCount = 0;
    for (var i = 0; i < toSubmit.length; i++) {
      if (results[i]['success'] == true) {
        successCount++;
      } else {
        errors.add('${toSubmit[i].key}: ${results[i]['error'] ?? 'Failed'}');
      }
    }

    // Tell admin about a late entry — in the background, don't make the
    // supervisor wait for it.
    if (!isOnTime && successCount > 0) {
      NotificationService()
          .sendLateEntryNotification(
            siteId: widget.siteId,
            entryType: 'labour',
            message: TimeValidator.getLabourLateMessage(),
            actualTime: TimeValidator.getISTTime(),
          )
          .catchError((Object e) {
        debugPrint('Late entry notification failed: $e');
        return <String, dynamic>{};
      });
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (errors.isEmpty) {
      Navigator.pop(context);
      widget.onSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isOnTime
                ? '$successCount labour types submitted successfully!'
                : '⚠️ $successCount labour types submitted (Late entry - Admin notified)',
          ),
          backgroundColor: isOnTime ? AppColors.statusCompleted : Colors.orange,
          duration: Duration(seconds: isOnTime ? 2 : 4),
        ),
      );
    } else if (successCount > 0) {
      Navigator.pop(context);
      widget.onSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount submitted. Errors: ${errors.join(', ')}'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: ${errors.first}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Future<void> _selectTime(bool isMorning) async {
    final selectedDateTime = isMorning
        ? _morningSelectedDateTime
        : _eveningSelectedDateTime;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.deepNavy,
              onPrimary: Colors.white,
              onSurface: AppColors.deepNavy,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isMorning) {
          _morningSelectedDateTime = DateTime(
            selectedDateTime.year,
            selectedDateTime.month,
            selectedDateTime.day,
            picked.hour,
            picked.minute,
          );
        } else {
          _eveningSelectedDateTime = DateTime(
            selectedDateTime.year,
            selectedDateTime.month,
            selectedDateTime.day,
            picked.hour,
            picked.minute,
          );
        }
      });
      print(
        '🕒 [LABOUR] ${isMorning ? "Morning" : "Evening"} time changed to: ${isMorning ? _morningSelectedDateTime : _eveningSelectedDateTime}',
      );
    }
  }
}

// Material Entry Sheet with Multiple Types
class _MaterialEntrySheet extends StatefulWidget {
  final String siteId;
  final VoidCallback onSuccess;
  final VoidCallback? onMaterialUpdated;

  const _MaterialEntrySheet({
    required this.siteId,
    required this.onSuccess,
    this.onMaterialUpdated,
  });

  @override
  State<_MaterialEntrySheet> createState() => _MaterialEntrySheetState();
}

class _MaterialEntrySheetState extends State<_MaterialEntrySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _constructionService = ConstructionService();
  final _materialService = MaterialService();
  Map<String, double> _materialQuantities = {};
  List<Map<String, dynamic>> _availableMaterials = [];
  bool _isLoadingMaterials = false;
  bool _isSubmitting = false;
  late DateTime _selectedDateTime;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Initialize with current local time
    _selectedDateTime = DateTime.now();
    print('🕒 [MATERIAL] Initialized with local time: $_selectedDateTime');

    // Load materials from inventory
    _loadAvailableMaterials();
  }

  Future<void> _loadAvailableMaterials() async {
    setState(() => _isLoadingMaterials = true);

    try {
      final result = await _materialService.getMaterialBalance(widget.siteId);

      if (result['success'] == true) {
        final materials = List<Map<String, dynamic>>.from(
          result['balance'] ?? [],
        );
        setState(() {
          _availableMaterials = materials;
          // "Stocks left" starts at the current stock, so a material the
          // supervisor doesn't touch is recorded as 0 used (not as all used).
          _materialQuantities = {
            for (var material in materials)
              material['material_type'] as String:
                  (material['current_balance'] as num?)?.toDouble() ?? 0.0,
          };
        });
      }
    } catch (e) {
      print('Error loading materials: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMaterials = false);
    }
  }

  Map<String, dynamic> _materialData(String type) => _availableMaterials
      .firstWhere((m) => m['material_type'] == type, orElse: () => {});

  double _balanceOf(String type) =>
      (_materialData(type)['current_balance'] as num?)?.toDouble() ?? 0.0;

  String _unitOf(String type) =>
      _materialData(type)['unit'] as String? ?? 'units';

  double _usedOf(String type) =>
      (_balanceOf(type) - (_materialQuantities[type] ?? 0)).clamp(0.0, double.infinity);

  /// Materials the supervisor recorded usage for
  int get _totalItems =>
      _materialQuantities.keys.where((type) => _usedOf(type) > 0).length;

  static String _qty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTime = TimeValidator.isMaterialEntryOnTime();
    return WillPopScope(
      onWillPop: () async {
        // STRICT LOCK: Block back navigation completely if any entries started
        final hasEntries = _totalItems > 0;

        if (hasEntries) {
          // Show warning message - DO NOT allow back
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '⚠️ Please complete and submit material updates before going back.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          // BLOCK back navigation
          return false;
        }

        // No entries started, allow back navigation
        return true;
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // Title + date
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.statusCompleted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Material balance',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.deepNavy,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, d MMM').format(DateTime.now()),
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Status + entry date/time
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _materialChip(
                    icon: onTime ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    label: onTime
                        ? 'On time · ${TimeValidator.getMaterialTimeWindow()}'
                        : 'Outside time window · admin will be notified',
                    color: onTime ? const Color(0xFF15803D) : const Color(0xFFC2410C),
                  ),
                  if (_tabController.index == 0) ...[
                    _materialChip(
                      icon: Icons.calendar_today_rounded,
                      label: _formatDate(_selectedDateTime),
                      color: AppColors.deepNavy,
                      onTap: _selectDate,
                    ),
                    _materialChip(
                      icon: Icons.access_time_rounded,
                      label: '${_formatTime(_selectedDateTime)} · Change',
                      color: AppColors.deepNavy,
                      onTap: _selectTime,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Update / Stock segmented control
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 46,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9ECF2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabController,
                  onTap: (_) => setState(() {}),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  labelColor: AppColors.deepNavy,
                  unselectedLabelColor: Colors.grey.shade600,
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  unselectedLabelStyle:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note_rounded, size: 18),
                          SizedBox(width: 6),
                          Text('Update'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_rounded, size: 17),
                          SizedBox(width: 6),
                          Text('Stock'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildUpdateTab(), _buildAvailableTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _materialChip({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyMaterials() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No materials available',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The site engineer needs to add materials to the inventory first.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // Update Tab - record what's left at the end of the day
  Widget _buildUpdateTab() {
    if (_isLoadingMaterials) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_materialQuantities.isEmpty) return _emptyMaterials();
    final types = _materialQuantities.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            'Enter how much is left now · tap a number to type it',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            itemCount: types.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildMaterialTypeRow(types[i]),
          ),
        ),
        _buildMaterialSubmitBar(),
      ],
    );
  }

  Widget _buildMaterialSubmitBar() {
    final used = _totalItems;
    final unchanged = _materialQuantities.length - used;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  used == 0
                      ? 'Nothing used yet'
                      : '$used material${used == 1 ? '' : 's'} used',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepNavy,
                  ),
                ),
                Text(
                  '$unchanged unchanged',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: !_isSubmitting && !_isLoadingMaterials ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.statusCompleted,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Icon(Icons.check_rounded, color: Colors.white),
              label: Text(
                _isSubmitting ? 'Submitting…' : 'Submit',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Stock Tab - current balance of each material
  Widget _buildAvailableTab() {
    if (_isLoadingMaterials) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_availableMaterials.isEmpty) return _emptyMaterials();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: _availableMaterials.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildAvailableMaterialCard(_availableMaterials[i]),
    );
  }

  Widget _buildAvailableMaterialCard(Map<String, dynamic> material) {
    final materialType = material['material_type'] as String;
    final currentBalance = (material['current_balance'] as num?)?.toDouble() ?? 0.0;
    final totalUsed = (material['total_used'] as num?)?.toDouble() ?? 0.0;
    final unit = material['unit'] as String? ?? 'units';
    final total = currentBalance + totalUsed;
    final usedShare = total > 0 ? totalUsed / total : 0.0;
    final low = total > 0 && currentBalance / total < 0.2;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.statusCompleted.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getMaterialIcon(materialType),
                  size: 21,
                  color: AppColors.statusCompleted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  materialType,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy,
                  ),
                ),
              ),
              if (low)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Low stock',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: usedShare,
              minHeight: 8,
              backgroundColor: AppColors.statusCompleted.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(AppColors.safetyOrange),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'In stock ${_qty(currentBalance)} $unit',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.statusCompleted,
                ),
              ),
              const Spacer(),
              Text(
                'Used ${_qty(totalUsed)} $unit',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.safetyOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialTypeRow(String type) {
    final left = _materialQuantities[type]!;
    final balance = _balanceOf(type);
    final unit = _unitOf(type);
    final used = _usedOf(type);
    final active = used > 0;

    void setLeft(double value) =>
        setState(() => _materialQuantities[type] = value.clamp(0.0, balance));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: active ? AppColors.safetyOrange.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.safetyOrange.withValues(alpha: 0.45)
              : const Color(0xFFE5E7EB),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: active ? AppColors.safetyOrange : const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getMaterialIcon(type),
              size: 21,
              color: active ? Colors.white : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? AppColors.deepNavy : const Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  active
                      ? 'Used today: ${_qty(used)} $unit'
                      : 'In stock ${_qty(balance)} $unit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: active ? const Color(0xFFC2410C) : Colors.grey.shade500,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Stepper for "stocks left": − [left] +   (tap the number to type)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _materialStepperButton(
                      icon: Icons.remove_rounded,
                      onTap: left > 0 ? () => setLeft(left - 1) : null,
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _typeStockLeft(type, left, balance, unit, setLeft),
                      child: SizedBox(
                        width: 46,
                        height: 40,
                        child: Center(
                          child: FittedBox(
                            child: Text(
                              _qty(left),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: active ? AppColors.deepNavy : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _materialStepperButton(
                      icon: Icons.add_rounded,
                      filled: true,
                      onTap: left < balance ? () => setLeft(left + 1) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'left',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _materialStepperButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: filled && enabled ? AppColors.statusCompleted : Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 19,
              color: !enabled
                  ? Colors.grey.shade400
                  : filled
                      ? Colors.white
                      : AppColors.deepNavy,
            ),
          ),
        ),
      ),
    );
  }

  /// Type the stock left directly (decimals allowed, e.g. 2.5 tons).
  Future<void> _typeStockLeft(
    String type,
    double current,
    double balance,
    String unit,
    void Function(double) setLeft,
  ) async {
    final controller = TextEditingController(text: _qty(current));
    final formKey = GlobalKey<FormState>();
    double? parse(String? v) => double.tryParse((v ?? '').trim());
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(type),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(
              labelText: 'Stock left ($unit)',
              helperText: 'In stock: ${_qty(balance)} $unit',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) {
              final n = parse(v);
              if (n == null) return 'Enter a number';
              if (n > balance) return 'Can\'t be more than ${_qty(balance)} in stock';
              return null;
            },
            onFieldSubmitted: (v) {
              if (formKey.currentState!.validate()) Navigator.pop(context, parse(v));
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, parse(controller.text));
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) setLeft(value);
  }

  IconData _getMaterialIcon(String type) {
    // Generic icon mapping based on common material types
    final typeLower = type.toLowerCase();

    if (typeLower.contains('brick')) return Icons.grid_4x4;
    if (typeLower.contains('sand')) return Icons.landscape;
    if (typeLower.contains('cement')) return Icons.inventory;
    if (typeLower.contains('steel') ||
        typeLower.contains('rod') ||
        typeLower.contains('bar'))
      return Icons.hardware;
    if (typeLower.contains('jelly') || typeLower.contains('water'))
      return Icons.water_drop;
    if (typeLower.contains('putty') || typeLower.contains('paint'))
      return Icons.format_paint;
    if (typeLower.contains('stone') || typeLower.contains('aggregate'))
      return Icons.terrain;
    if (typeLower.contains('wood') || typeLower.contains('timber'))
      return Icons.carpenter;
    if (typeLower.contains('wire') || typeLower.contains('cable'))
      return Icons.cable;
    if (typeLower.contains('pipe')) return Icons.plumbing;

    return Icons.inventory_2; // Default icon
  }

  Future<void> _submit() async {
    // Check if material entry is on time
    final isOnTime = TimeValidator.isMaterialEntryOnTime();
    final currentIST = TimeValidator.getISTTime();

    // Convert "stocks left" into quantity used for every material
    // (untouched materials report 0 used)
    final materials = <Map<String, dynamic>>[
      for (final type in _materialQuantities.keys)
        if (_materialData(type).isNotEmpty)
          {
            'material_type': type,
            'quantity': _usedOf(type),
            'unit': _unitOf(type),
          },
    ];

    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No materials to submit'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmationDialog(
        title: 'Confirm Material Entry',
        entries: materials,
        totalCount: materials.length,
        isLabour: false,
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final result = await _constructionService.submitMaterialBalance(
      siteId: widget.siteId,
      materials: materials,
      customDateTime: _selectedDateTime, // Pass the selected local time
    );
    final success = result['success'] == true;

    // Tell admin about a late entry — in the background, don't make the
    // supervisor wait for it.
    if (!isOnTime && success) {
      NotificationService()
          .sendLateEntryNotification(
            siteId: widget.siteId,
            entryType: 'material',
            message: TimeValidator.getMaterialLateMessage(),
            actualTime: currentIST,
          )
          .catchError((Object e) {
        debugPrint('Late entry notification failed: $e');
        return <String, dynamic>{};
      });
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!success) {
      // Keep the sheet open so nothing the supervisor entered is lost
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${result['error'] ?? 'Could not submit. Please try again.'}'),
          backgroundColor: AppColors.statusOverdue,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    widget.onMaterialUpdated?.call();
    Navigator.pop(context);
    widget.onSuccess();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isOnTime
              ? '✅ Materials updated!'
              : '⚠️ Materials updated (Late entry - Admin notified)',
        ),
        backgroundColor: isOnTime ? AppColors.statusCompleted : Colors.orange,
        duration: Duration(seconds: isOnTime ? 2 : 4),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.statusCompleted,
              onPrimary: Colors.white,
              onSurface: AppColors.statusCompleted,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
      });
      print('🕒 [MATERIAL] Date changed to: $_selectedDateTime');
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.statusCompleted,
              onPrimary: Colors.white,
              onSurface: AppColors.statusCompleted,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
      });
      print('🕒 [MATERIAL] Time changed to: $_selectedDateTime');
    }
  }
}

// Confirmation Dialog
class _ConfirmationDialog extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> entries;
  final int totalCount;
  final bool isLabour;

  const _ConfirmationDialog({
    required this.title,
    required this.entries,
    required this.totalCount,
    required this.isLabour,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cleanWhite,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: isLabour
                    ? AppColors.navyGradient
                    : AppColors.greenGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLabour ? Icons.people : Icons.inventory_2,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please review your entries',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Entries List
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  children: entries.map((entry) {
                    if (isLabour) {
                      return _buildLabourRow(entry['type'], entry['count']);
                    } else {
                      return _buildMaterialRow(
                        entry['material_type'],
                        entry['quantity'],
                        entry['unit'],
                      );
                    }
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Total Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: isLabour
                    ? AppColors.orangeGradient
                    : AppColors.greenGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    isLabour
                        ? 'Total: $totalCount Workers'
                        : 'Total: $totalCount Items',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.textSecondary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLabour
                          ? AppColors.safetyOrange
                          : AppColors.statusCompleted,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabourRow(String type, int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightSlate,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_getLabourIcon(type), color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              type,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.deepNavy,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppColors.orangeGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialRow(String type, double quantity, String unit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightSlate,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.statusCompleted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_getMaterialIcon(type), color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              type,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.deepNavy,
              ),
            ),
          ),
          Text(
            '${quantity.toInt()} $unit',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.statusCompleted,
            ),
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

  IconData _getMaterialIcon(String type) {
    switch (type) {
      case 'Bricks':
        return Icons.grid_4x4;
      case 'M Sand':
        return Icons.landscape;
      case 'P Sand':
        return Icons.terrain;
      case 'Cement':
        return Icons.inventory;
      case 'Steel':
        return Icons.hardware;
      case 'Jelly':
        return Icons.water_drop;
      case 'Putty':
        return Icons.format_paint;
      default:
        return Icons.inventory_2;
    }
  }
}
