import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../services/construction_service.dart';
import '../providers/accountant_entries_provider.dart';
import '../utils/app_colors.dart';
import 'accountant_approved_entries_screen.dart';

class AccountantCompareScreen extends StatefulWidget {
  const AccountantCompareScreen({super.key});

  @override
  State<AccountantCompareScreen> createState() => _AccountantCompareScreenState();
}

class _AccountantCompareScreenState extends State<AccountantCompareScreen> {
  final _constructionService = ConstructionService();

  // Track expanded sites (local UI state only)
  Set<String> _expandedSites = {};

  @override
  void initState() {
    super.initState();
    _loadComparisonData();
  }

  Future<void> _loadComparisonData() async {
    final provider = context.read<AccountantEntriesProvider>();
    provider.setIsLoading(true);
    provider.setError(null);
    provider.setLockStatus(false, null);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(provider.selectedDate);

      // Fetch all three roles in parallel
      final results = await Future.wait([
        _constructionService.getEntriesByDateAndRole(dateStr, 'Supervisor'),
        _constructionService.getEntriesByDateAndRole(dateStr, 'Site Engineer'),
        _constructionService.getEntriesByDateAndRole(dateStr, 'Accountant'),
      ]);

      if (mounted) {
        provider.setSupervisorEntries(results[0]);
        provider.setEngineerEntries(results[1]);
        provider.setAccountantEntries(results[2]);
        provider.setIsLoading(false);
      }
    } catch (e) {
      print('❌ [COMPARE] Error: $e');
      if (mounted) {
        provider.setError(e.toString());
        provider.setIsLoading(false);
      }
    }
  }

Future<void> _selectDate() async {
    final provider = context.read<AccountantEntriesProvider>();
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.deepNavy,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.deepNavy,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != provider.selectedDate) {
      provider.setSelectedDate(picked);
      _loadComparisonData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccountantEntriesProvider>();

    return Scaffold(
      backgroundColor: AppColors.accountantBackground,
      appBar: AppBar(
        title: Text(
          'Compare Entries',
          style: TextStyle(
            color: AppColors.deepNavy,
            fontWeight: FontWeight.bold,
            fontSize: 18.sp,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.deepNavy),
        actions: [
          // View Approved Entries button
          TextButton.icon(
            icon: const Icon(Icons.check_circle, color: AppColors.deepNavy),
            label: Text(
              'Approved',
              style: TextStyle(color: AppColors.deepNavy, fontSize: 12.sp),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccountantApprovedEntriesScreen(
                  initialDate: provider.selectedDate,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Select Date',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadComparisonData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date selector card
          Container(
            margin: EdgeInsets.all(16.r),
            padding: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10.r),
                      decoration: BoxDecoration(
                        color: AppColors.deepNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(
                        Icons.compare_arrows,
                        color: AppColors.deepNavy,
                        size: 24.sp,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Comparing Entries For',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            DateFormat('EEEE, MMM d, yyyy').format(provider.selectedDate),
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: AppColors.deepNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_calendar),
                      onPressed: _selectDate,
                      color: AppColors.deepNavy,
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),
                // Sites display text (no longer a filter dropdown)
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: AppColors.textSecondary,
                      size: 20.sp,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Sites:',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        '${provider.supervisorEntries.length + provider.engineerEntries.length} entries',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.deepNavy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: provider.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accountantAccent,
                    ),
                  )
                : provider.error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64.sp,
                              color: AppColors.accountantError,
                            ),
                            SizedBox(height: 16.h),
                            Text(
                              'Error: ${provider.error}',
                              style: const TextStyle(color: AppColors.accountantError),
                            ),
                            SizedBox(height: 16.h),
                            ElevatedButton(
                              onPressed: _loadComparisonData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _buildComparisonView(provider),
          ),

          // Confirm button at bottom — hidden when site is already locked
          if (provider.selectedEntryId != null && !provider.isLockedForSite)
            Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: provider.isConfirming ? null : _confirmSelection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accountantSuccess,
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: provider.isConfirming
                      ? SizedBox(
                          width: 20.w,
                          height: 20.h,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Confirm Selection',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComparisonView(AccountantEntriesProvider provider) {
    if (provider.supervisorEntries.isEmpty && provider.engineerEntries.isEmpty && provider.accountantEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100.w,
              height: 100.h,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.deepNavy, AppColors.deepNavyDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: 50.sp,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              'No Entries Found',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'No labour entries for this date',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // Group entries by site
    final Map<String, dynamic> siteMap = {};
    for (final entry in provider.supervisorEntries) {
      final siteId = entry['site_id'] ?? 'unknown';
      if (!siteMap.containsKey(siteId)) {
        siteMap[siteId] = {
          'site_name': entry['site_name'] ?? 'Unknown',
          'supervisor_entries': [],
          'engineer_entries': [],
          'accountant_entries': [],
        };
      }
      siteMap[siteId]['supervisor_entries'].add(entry);
    }

    for (final entry in provider.engineerEntries) {
      final siteId = entry['site_id'] ?? 'unknown';
      if (!siteMap.containsKey(siteId)) {
        siteMap[siteId] = {
          'site_name': entry['site_name'] ?? 'Unknown',
          'supervisor_entries': [],
          'engineer_entries': [],
          'accountant_entries': [],
        };
      }
      siteMap[siteId]['engineer_entries'].add(entry);
    }

    for (final entry in provider.accountantEntries) {
      final siteId = entry['site_id'] ?? 'unknown';
      if (!siteMap.containsKey(siteId)) {
        siteMap[siteId] = {
          'site_name': entry['site_name'] ?? 'Unknown',
          'supervisor_entries': [],
          'engineer_entries': [],
          'accountant_entries': [],
        };
      }
      siteMap[siteId]['accountant_entries'].add(entry);
    }

    return ListView(
      padding: EdgeInsets.all(16.r),
      children: [
        // Lock banner — shown when this site+date is already confirmed
        if (provider.isLockedForSite && provider.lockInfo != null) ...[
          Container(
            margin: EdgeInsets.only(bottom: 16.h),
            padding: EdgeInsets.all(14.r),
            decoration: BoxDecoration(
              color: AppColors.accountantSuccess.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.accountantSuccess, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.lock, color: AppColors.accountantSuccess, size: 22.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Entry Confirmed — Read Only',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accountantSuccess,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'Confirmed by ${provider.lockInfo!['accountant_name'] ?? 'an accountant'} '
                        '· Source: ${(provider.lockInfo!['source_type'] as String? ?? '').replaceAll('_', ' ').toUpperCase()}',
                        style: TextStyle(fontSize: 12.sp, color: AppColors.accountantSuccess),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Display sites as expandable items
        ...siteMap.entries.map((entry) => _buildSiteCard(
          entry.key,
          entry.value['site_name'] as String,
          List<Map<String, dynamic>>.from(entry.value['supervisor_entries'] as List),
          List<Map<String, dynamic>>.from(entry.value['engineer_entries'] as List),
          List<Map<String, dynamic>>.from(entry.value['accountant_entries'] as List),
        )),
      ],
    );
  }

  Widget _buildSiteCard(
    String siteId,
    String siteName,
    List<Map<String, dynamic>> supervisorEntries,
    List<Map<String, dynamic>> engineerEntries,
    List<Map<String, dynamic>> accountantEntries,
  ) {
    final isExpanded = _expandedSites.contains(siteId);

    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>(siteId),
          title: Text(
            siteName,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.deepNavy,
            ),
          ),
          trailing: Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            color: AppColors.deepNavy,
          ),
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedSites.add(siteId);
              } else {
                _expandedSites.remove(siteId);
              }
            });
          },
          children: [
            Padding(
              padding: EdgeInsets.all(12.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Supervisor Entries
                  if (supervisorEntries.isNotEmpty) ...[
                    Text(
                      'Supervisor Entries (${supervisorEntries.length})',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accountantSuccess,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    ...supervisorEntries.map((entry) => _buildEntryCard(entry, true)),
                    SizedBox(height: 16.h),
                  ],

                  // Site Engineer Entries
                  if (engineerEntries.isNotEmpty) ...[
                    Text(
                      'Site Engineer Entries (${engineerEntries.length})',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accountantAccent,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    ...engineerEntries.map((entry) => _buildEntryCard(entry, false)),
                    SizedBox(height: 16.h),
                  ],

                  // Accountant Entries
                  if (accountantEntries.isNotEmpty) ...[
                    Text(
                      'Accountant Entries (${accountantEntries.length})',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accountantWarning,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    ...accountantEntries.map((entry) => _buildEntryCard(entry)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.r),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, color: Colors.white, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              '$count ${count == 1 ? 'Entry' : 'Entries'}',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry, [bool? isSupervisor]) {
    final provider = context.read<AccountantEntriesProvider>();
    final siteName = entry['site_name'] ?? 'Unknown Site';
    final siteId = entry['site_id'] ?? '';
    final labourEntries = entry['labour_entries'] as List? ?? [];
    final submittedBy = entry['submitted_by'] ?? 'Unknown';
    final isLocked = provider.isLockedForSite; // read-only when site is confirmed
    final submittedAt = entry['submitted_at'] as String?;

    final color = isSupervisor == true
        ? AppColors.accountantSuccess
        : isSupervisor == false
            ? AppColors.accountantAccent
            : AppColors.accountantWarning;
    final entryType = isSupervisor == true
        ? 'supervisor'
        : isSupervisor == false
            ? 'site_engineer'
            : 'accountant';
    final isSelected = provider.selectedEntryId == siteId && provider.selectedEntryType == entryType;

    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(
          color: isSelected ? color : color.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Selection checkbox row — hidden when site is locked (already confirmed)
          if (!isLocked)
          InkWell(
            onTap: () {
              if (isSelected) {
                provider.clearSelection();
              } else {
                provider.selectEntry(siteId, entryType);
              }
            },
            child: Container(
              padding: EdgeInsets.all(12.r),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12.r),
                  topRight: Radius.circular(12.r),
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      if (value == true) {
                        provider.selectEntry(siteId, entryType);
                        // Immediately confirm and navigate to Approved Entries
                        _confirmAndNavigate(entry, entryType);
                      } else {
                        provider.clearSelection();
                      }
                    },
                    activeColor: color,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      isSelected ? 'Selected for confirmation' : 'Tap to select this entry',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? color : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Existing expansion tile
          ExpansionTile(
            leading: Container(
              padding: EdgeInsets.all(8.r),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(
                isSupervisor == true
                    ? Icons.engineering
                    : isSupervisor == false
                        ? Icons.construction
                        : Icons.person,
                color: color,
                size: 20.sp,
              ),
            ),
            title: Text(
              siteName,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.deepNavy,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4.h),
                Text(
                  'By: $submittedBy',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (submittedAt != null)
                  Text(
                    'At: ${_formatTime(submittedAt)}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
            children: [
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.all(16.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Labour Details',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    ...labourEntries.map((labour) => _buildLabourRow(labour)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLabourRow(Map<String, dynamic> labour) {
    final labourType = labour['labour_type'] ?? 'Unknown';
    final count = labour['labour_count'] ?? 0;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        children: [
          Container(
            width: 6.w,
            height: 6.h,
            decoration: const BoxDecoration(
              color: AppColors.deepNavy,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              labourType,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.deepNavy,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String dateTimeStr) {
    try {
      final dt = DateTime.parse(dateTimeStr);
      return DateFormat('h:mm a').format(dt);
    } catch (e) {
      return dateTimeStr;
    }
  }


  Future<void> _confirmSelection() async {
    final provider = context.read<AccountantEntriesProvider>();
    if (provider.selectedEntryId == null || provider.selectedEntryType == null) return;

    provider.setIsConfirming(true);

    try {
      // Find the selected entry
      final entries = provider.selectedEntryType == 'supervisor' ? provider.supervisorEntries : provider.engineerEntries;
      final selectedEntry = entries.firstWhere((e) => e['site_id'] == provider.selectedEntryId);

      final labourEntries = selectedEntry['labour_entries'] as List;
      final dateStr = DateFormat('yyyy-MM-dd').format(provider.selectedDate);

      // Fetch labour rates once for all labour types
      final ratesResponse = await _constructionService.getLabourRates('global');
      final rates = ratesResponse['rates'] as List? ?? [];

      final labourEntriesWithRates = labourEntries.map((labour) {
        final labourType = labour['labour_type'];
        final rateData = rates.firstWhere(
          (r) => r['labour_type'] == labourType,
          orElse: () => {'daily_rate': 600.0},
        );
        return {
          'labour_type': labourType,
          'labour_count': labour['labour_count'],
          'daily_rate': (rateData['daily_rate'] as num).toDouble(),
        };
      }).toList();

      // Call confirm cash entry API
      final result = await _constructionService.confirmCashEntry(
        siteId: provider.selectedEntryId!,
        entryDate: dateStr,
        sourceType: provider.selectedEntryType!,
        sourceEntryId: null, // We don't have individual entry IDs in the grouped data
        labourEntries: labourEntriesWithRates,
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Entry confirmed successfully'),
              backgroundColor: AppColors.accountantSuccess,
            ),
          );

          provider.clearSelection();

          // Reload data
          _loadComparisonData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to confirm entry'),
              backgroundColor: AppColors.accountantError,
            ),
          );
        }

        // Refresh data after confirmation
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _loadComparisonData();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.accountantError,
          ),
        );
      }
    } finally {
      if (mounted) {
        provider.setIsConfirming(false);
      }
    }
  }

  Future<void> _confirmAndNavigate(Map<String, dynamic> entry, String entryType) async {
    try {
      final provider = context.read<AccountantEntriesProvider>();
      final siteId = entry['site_id'] as String;
      final labourEntries = entry['labour_entries'] as List;
      final dateStr = DateFormat('yyyy-MM-dd').format(provider.selectedDate);

      // Fetch labour rates once for all labour types
      final ratesResponse = await _constructionService.getLabourRates('global');
      final rates = ratesResponse['rates'] as List? ?? [];

      final labourEntriesWithRates = labourEntries.map((labour) {
        final labourType = labour['labour_type'];
        final rateData = rates.firstWhere(
          (r) => r['labour_type'] == labourType,
          orElse: () => {'daily_rate': 600.0},
        );
        return {
          'labour_type': labourType,
          'labour_count': labour['labour_count'],
          'daily_rate': (rateData['daily_rate'] as num).toDouble(),
        };
      }).toList();

      // Confirm the entry
      final result = await _constructionService.confirmCashEntry(
        siteId: siteId,
        entryDate: dateStr,
        sourceType: entryType,
        sourceEntryId: null,
        labourEntries: labourEntriesWithRates,
      );

      print('✅ [CONFIRM] API Response: $result');

      if (mounted) {
        if (result['success'] == true) {
          print('✅ [CONFIRM] Confirmation succeeded!');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Entry confirmed! Moving to Approved Entries...'),
              backgroundColor: Color(0xFF059669),
            ),
          );

          // Refresh compare screen data
          print('✅ [CONFIRM] Refreshing comparison data...');
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            _loadComparisonData();
          }

          // Navigate to Approved Entries after a delay
          print('✅ [CONFIRM] Navigating to Approved Entries screen...');
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccountantApprovedEntriesScreen(
                  initialDate: provider.selectedDate,
                ),
              ),
            );
          }
        } else {
          print('❌ [CONFIRM] Confirmation failed: ${result['error']}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to confirm entry'),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [CONFIRM] Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

}
