import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/construction_service.dart';
import '../utils/app_colors.dart';
import '../providers/accountant_entries_provider.dart';

class AccountantApprovedEntriesScreen extends StatefulWidget {
  final DateTime initialDate;

  const AccountantApprovedEntriesScreen({
    super.key,
    required this.initialDate,
  });

  @override
  State<AccountantApprovedEntriesScreen> createState() =>
      _AccountantApprovedEntriesScreenState();
}

class _AccountantApprovedEntriesScreenState
    extends State<AccountantApprovedEntriesScreen> {
  final _constructionService = ConstructionService();

  @override
  void initState() {
    super.initState();
    print('🔴 [APPROVED SCREEN] initState called');
    final provider = context.read<AccountantEntriesProvider>();
    print('🔴 [APPROVED SCREEN] Initial date from widget: ${widget.initialDate}');
    provider.setSelectedDate(widget.initialDate);
    print('🔴 [APPROVED SCREEN] Provider date set, calling _loadAreas()');
    _loadAreas();
    print('🔴 [APPROVED SCREEN] Calling _loadApprovedEntries()');
    _loadApprovedEntries();
  }

  Future<void> _loadAreas() async {
    try {
      final provider = context.read<AccountantEntriesProvider>();
      final areas = await _constructionService.getAreas();
      if (mounted) {
        provider.setAreas(areas);
      }
    } catch (e) {
      print('Error loading areas: $e');
    }
  }

  Future<void> _loadStreets(String area) async {
    try {
      final provider = context.read<AccountantEntriesProvider>();
      final streets = await _constructionService.getStreets(area);
      if (mounted) {
        provider.setStreets(streets);
      }
    } catch (e) {
      print('Error loading streets: $e');
    }
  }

  List<Map<String, dynamic>> _applyFilters(
      List<Map<String, dynamic>> entries, AccountantEntriesProvider provider) {
    return entries.where((entry) {
      final entryArea = (entry['area'] as String?) ?? '';
      final entryStreet = (entry['street'] as String?) ?? '';
      if (provider.selectedArea != null && provider.selectedArea!.isNotEmpty) {
        if (entryArea != provider.selectedArea) return false;
      }
      if (provider.selectedStreet != null && provider.selectedStreet!.isNotEmpty) {
        if (entryStreet != provider.selectedStreet) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _loadApprovedEntries() async {
    final provider = context.read<AccountantEntriesProvider>();
    final dateStr = DateFormat('yyyy-MM-dd').format(provider.selectedDate);
    final cacheKey = 'approved_entries_$dateStr';

    // Show cached data immediately (no loading spinner)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw != null) {
        final cached = List<Map<String, dynamic>>.from(
            (json.decode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)));
        if (mounted) provider.setApprovedEntries(_applyFilters(cached, provider));
      }
    } catch (_) {}

    // Fetch fresh data in background
    provider.setIsLoading(provider.approvedEntries.isEmpty);
    try {
      final allEntries = await _constructionService.getApprovedEntries(dateStr);

      // Persist to cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, json.encode(allEntries));

      if (mounted) {
        provider.setApprovedEntries(_applyFilters(allEntries, provider));
        provider.setIsLoading(false);
      }
    } catch (e) {
      if (mounted) provider.setIsLoading(false);
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
      provider.setSelectedArea(null); // Reset filters when date changes
      provider.setSelectedStreet(null);
      _loadApprovedEntries();
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccountantEntriesProvider>();

    return Scaffold(
      backgroundColor: AppColors.accountantBackground,
      appBar: AppBar(
        title: Text(
          'Approved Entries',
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
          IconButton(
            icon: const Icon(Icons.calendar_today, color: AppColors.deepNavy),
            onPressed: _selectDate,
            tooltip: 'Select Date',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.deepNavy),
            onPressed: _loadApprovedEntries,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter section
          Container(
            color: Colors.white,
            padding: EdgeInsets.all(16.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.deepNavy.withValues(alpha: 0.2),
                              ),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: DropdownButton<String>(
                              value: provider.selectedArea,
                              isExpanded: true,
                              underline: SizedBox(),
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 8.h,
                              ),
                              dropdownColor: Colors.white,
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Areas'),
                                ),
                                ...provider.areas.map((area) {
                                  return DropdownMenuItem<String>(
                                    value: area,
                                    child: Text(area),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                provider.setSelectedArea(value);
                                if (value != null) {
                                  _loadStreets(value);
                                }
                                _loadApprovedEntries(); // Re-filter when area changes
                              },
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
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.deepNavy.withValues(alpha: 0.2),
                              ),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: DropdownButton<String>(
                              value: provider.selectedStreet,
                              isExpanded: true,
                              underline: SizedBox(),
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 8.h,
                              ),
                              dropdownColor: Colors.white,
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Streets'),
                                ),
                                ...provider.streets.map((street) {
                                  return DropdownMenuItem<String>(
                                    value: street,
                                    child: Text(street),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                provider.setSelectedStreet(value);
                                _loadApprovedEntries(); // Re-filter when street changes
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Approved entries list
          Expanded(
            child: provider.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accountantAccent,
                    ),
                  )
                : provider.approvedEntries.isEmpty
                    ? _buildEmptyState(provider)
                    : _buildApprovedEntriesList(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AccountantEntriesProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 72.sp,
            color: AppColors.textSecondary.withValues(alpha: 0.3),
          ),
          SizedBox(height: 16.h),
          Text(
            'No Approved Entries',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.deepNavy,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'No entries approved for ${DateFormat('dd MMM yyyy').format(provider.selectedDate)}',
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedEntriesList(AccountantEntriesProvider provider) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Text(
              '${provider.approvedEntries.length} approved ${provider.approvedEntries.length == 1 ? 'entry' : 'entries'}',
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ...provider.approvedEntries.map((entry) => _buildApprovedEntryCard(entry)),
        ],
      ),
    );
  }

  Widget _buildApprovedEntryCard(Map<String, dynamic> entry) {
    final siteName = entry['site_name'] as String? ?? 'Unknown Site';
    final sourceType = entry['source_type'] as String? ?? '';
    final supervisorEntries = List<Map<String, dynamic>>.from(
        entry['supervisor_entries'] as List? ?? []);
    final engineerEntries = List<Map<String, dynamic>>.from(
        entry['site_engineer_entries'] as List? ?? []);
    final accountantEntries = List<Map<String, dynamic>>.from(
        entry['accountant_entries'] as List? ?? []);
    final approvedBy = entry['approved_by'] as String? ?? 'Unknown';
    final entryDate = entry['entry_date'] as String? ?? '';

    final isSourceSupervisor = sourceType.toLowerCase() == 'supervisor';
    final isSourceAccountant = sourceType.toLowerCase().contains('accountant');

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Site name and date header
            Row(
              children: [
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        _formatDate(entryDate),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'Selected: ${isSourceAccountant ? '👤 Accountant' : isSourceSupervisor ? '👤 Supervisor' : '🔧 Site Engineer'}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.deepNavy,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 16.h),

            // Supervisor entries
            if (supervisorEntries.isNotEmpty) ...[
              _buildRoleSection(
                'Supervisor Entries',
                supervisorEntries,
                isSourceSupervisor,
              ),
              SizedBox(height: 12.h),
            ],

            // Site Engineer entries
            if (engineerEntries.isNotEmpty) ...[
              _buildRoleSection(
                'Site Engineer Entries',
                engineerEntries,
                !isSourceSupervisor && !isSourceAccountant,
              ),
              SizedBox(height: 12.h),
            ],

            // Accountant entries
            if (accountantEntries.isNotEmpty) ...[
              _buildRoleSection(
                'Accountant Entries',
                accountantEntries,
                isSourceAccountant,
              ),
              SizedBox(height: 12.h),
            ],

            // Approved by info
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.deepNavy.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                'Approved by: $approvedBy',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSection(
    String roleTitle,
    List<Map<String, dynamic>> entries,
    bool isSelected,
  ) {
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.accountantAccent.withValues(alpha: 0.05)
            : AppColors.accountantBackground,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: isSelected
              ? AppColors.accountantAccent.withValues(alpha: 0.3)
              : AppColors.deepNavy.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roleTitle,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.deepNavy,
            ),
          ),
          SizedBox(height: 8.h),
          ...entries.map((labour) {
            final labourType = labour['labour_type'] as String? ?? 'Unknown';
            final count = labour['labour_count'] as int? ?? 0;
            final rate = labour['daily_rate'] as num?;
            final totalCost = labour['total_cost'] as num?;

            return Padding(
              padding: EdgeInsets.only(bottom: 6.h),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labourType,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColors.deepNavy,
                          ),
                        ),
                        if (rate != null)
                          Text(
                            '$count worker${count == 1 ? '' : 's'} × ₹${rate.toStringAsFixed(0)}/day',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (totalCost != null)
                    Text(
                      '₹${totalCost.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accountantSuccess,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
