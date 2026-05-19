import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/construction_provider.dart';
import '../utils/app_colors.dart';
import 'assign_working_sites_screen.dart';

class AccountantReportsScreen extends StatefulWidget {
  const AccountantReportsScreen({super.key});

  @override
  State<AccountantReportsScreen> createState() => _AccountantReportsScreenState();
}

class _AccountantReportsScreenState extends State<AccountantReportsScreen> {
  DateTime? _selectedDate; // null = All dates (no filter)
  String? _selectedRole; // null = All
  String? _selectedSiteId; // null = All sites
  String? _selectedEntryType; // null = All, 'labour', 'material', 'extra_cost'

  static const _roles = ['Supervisor', 'Site Engineer'];

  String get _selectedDateStr =>
      _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : '';

  List<Map<String, dynamic>> _filterEntries(List<Map<String, dynamic>> entries) {
    return entries.where((e) {
      // Date filter — only apply if a date is selected
      if (_selectedDate != null) {
        final d = e['entry_date'] as String? ?? '';
        if (!d.startsWith(_selectedDateStr)) return false;
      }
      if (_selectedRole != null) {
        // Use submitted_by_role from cash_entries (source_type: 'Supervisor' or 'Site Engineer')
        final role = (e['submitted_by_role'] as String? ?? '').toLowerCase();
        if (role != _selectedRole!.toLowerCase()) return false;
      }
      if (_selectedSiteId != null) {
        final siteId = e['site_id'] as String? ?? '';
        if (siteId != _selectedSiteId) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.deepNavy,
            onPrimary: Colors.white,
            onSurface: AppColors.deepNavy,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  String _friendlyDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final check = DateTime(d.year, d.month, d.day);
    if (check == today) return 'Today';
    if (check == yesterday) return 'Yesterday';
    return DateFormat('EEE, MMM d, yyyy').format(d);
  }

  void _showClientRequirementDialog() async {
    final provider = Provider.of<ConstructionProvider>(context, listen: false);
    
    // Get all unique sites from accountant data
    final Map<String, Map<String, dynamic>> sitesMap = {};
    
    for (final entry in provider.accountantLabourEntries) {
      final siteId = entry['site_id'] as String?;
      if (siteId != null && !sitesMap.containsKey(siteId)) {
        sitesMap[siteId] = {
          'site_id': siteId,
          'site_name': entry['site_name'] ?? 'Unknown',
          'customer_name': entry['customer_name'] ?? '',
          'full_name': '${entry['customer_name'] ?? ''} ${entry['site_name'] ?? ''}'.trim(),
        };
      }
    }
    
    for (final entry in provider.accountantMaterialEntries) {
      final siteId = entry['site_id'] as String?;
      if (siteId != null && !sitesMap.containsKey(siteId)) {
        sitesMap[siteId] = {
          'site_id': siteId,
          'site_name': entry['site_name'] ?? 'Unknown',
          'customer_name': entry['customer_name'] ?? '',
          'full_name': '${entry['customer_name'] ?? ''} ${entry['site_name'] ?? ''}'.trim(),
        };
      }
    }
    
    final sites = sitesMap.values.toList();
    
    if (sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sites available. Please load site data first.')),
      );
      return;
    }
    
    String? selectedSiteId;
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Client Extra Requirement',
            style: TextStyle(
              color: AppColors.deepNavy,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select site and add extra requirement details',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                
                // Site Dropdown
                DropdownButtonFormField<String>(
                  value: selectedSiteId,
                  decoration: const InputDecoration(
                    labelText: 'Select Site *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on, color: AppColors.deepNavy),
                  ),
                  items: sites.map((site) {
                    return DropdownMenuItem<String>(
                      value: site['site_id'] as String,
                      child: Text(
                        site['full_name'] as String,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedSiteId = value);
                  },
                ),
                const SizedBox(height: 16),
                
                // Description
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description *',
                    hintText: 'Enter requirement description',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description, color: AppColors.deepNavy),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                
                // Amount
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount *',
                    hintText: 'Enter amount',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.currency_rupee, color: AppColors.deepNavy),
                    prefixText: '₹ ',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedSiteId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a site')),
                  );
                  return;
                }
                
                final description = descriptionController.text.trim();
                final amountText = amountController.text.trim();

                if (description.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter description')),
                  );
                  return;
                }

                final amount = double.tryParse(amountText);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter valid amount')),
                  );
                  return;
                }

                final success = await provider.addClientRequirement(selectedSiteId!, description, amount);

                if (context.mounted) {
                  Navigator.pop(context);
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Client requirement added successfully'),
                        backgroundColor: AppColors.statusCompleted,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to add requirement'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConstructionProvider>(
      builder: (context, provider, child) {
        final labourEntries = _filterEntries(provider.accountantLabourEntries);
        final materialEntries = _filterEntries(provider.accountantMaterialEntries);
        final extraCosts = _filterEntries(provider.accountantExtraCosts);
        final isLoading = provider.isLoadingAccountantData;
        final totalSalary = labourEntries.fold<double>(
          0,
          (sum, e) => sum + ((e['total_cost'] as double?) ?? 0),
        );
        final totalExtraCosts = extraCosts.fold<double>(
          0,
          (sum, e) => sum + ((e['amount'] as double?) ?? 0),
        );

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(
              'Reports',
              style: TextStyle(
                color: AppColors.deepNavy,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppColors.deepNavy),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppColors.deepNavy),
                tooltip: 'Assign Working Sites',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AssignWorkingSitesScreen(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.deepNavy),
                onPressed: () async {
                  provider.clearAccountantCache();
                  await provider.loadAccountantData(forceRefresh: true);
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // ── Date picker bar ──────────────────────────────
              Container(
                color: AppColors.cleanWhite,
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Date',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        // Prev day (only when a date is selected)
                        _ArrowBtn(
                          icon: Icons.chevron_left,
                          disabled: _selectedDate == null,
                          onTap: () => setState(() => _selectedDate =
                              _selectedDate!.subtract(const Duration(days: 1))),
                        ),
                        SizedBox(width: 8.w),
                        // Date display — tap to open picker
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDate,
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
                              decoration: BoxDecoration(
                                color: AppColors.deepNavy,
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.calendar_today, color: Colors.white, size: 18.sp),
                                  SizedBox(width: 10.w),
                                  Text(
                                    _selectedDate != null
                                        ? _friendlyDate(_selectedDate!)
                                        : 'All Dates',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_selectedDate != null) ...[
                                    SizedBox(width: 8.w),
                                    GestureDetector(
                                      onTap: () => setState(() => _selectedDate = null),
                                      child: Icon(Icons.close, color: Colors.white70, size: 16.sp),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        // Next day (disabled if today or no date selected)
                        _ArrowBtn(
                          icon: Icons.chevron_right,
                          disabled: _selectedDate == null ||
                              DateTime(_selectedDate!.year, _selectedDate!.month,
                                      _selectedDate!.day) ==
                                  DateTime(DateTime.now().year, DateTime.now().month,
                                      DateTime.now().day),
                          onTap: () => setState(() =>
                              _selectedDate = _selectedDate!.add(const Duration(days: 1))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Role filter chips ─────────────────────────────
              Container(
                color: Colors.white,
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1, color: Colors.white),
                    SizedBox(height: 10.h),
                    Text(
                      'Filter by Role',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // "All" chip
                          _RoleChip(
                            label: 'All',
                            selected: _selectedRole == null,
                            onTap: () => setState(() => _selectedRole = null),
                          ),
                          SizedBox(width: 8.w),
                          ..._roles.map((role) => Padding(
                                padding: EdgeInsets.only(right: 8.w),
                                child: _RoleChip(
                                  label: role,
                                  selected: _selectedRole == role,
                                  onTap: () => setState(() =>
                                      _selectedRole =
                                          _selectedRole == role ? null : role),
                                ),
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Site filter dropdown ─────────────────────────────
              Consumer<ConstructionProvider>(
                builder: (context, provider, _) {
                  // Get unique sites from entries
                  final Map<String, Map<String, dynamic>> sitesMap = {};
                  
                  for (final entry in provider.accountantLabourEntries) {
                    final siteId = entry['site_id'] as String?;
                    if (siteId != null && !sitesMap.containsKey(siteId)) {
                      sitesMap[siteId] = {
                        'site_id': siteId,
                        'site_name': entry['site_name'] ?? 'Unknown',
                      };
                    }
                  }
                  
                  for (final entry in provider.accountantMaterialEntries) {
                    final siteId = entry['site_id'] as String?;
                    if (siteId != null && !sitesMap.containsKey(siteId)) {
                      sitesMap[siteId] = {
                        'site_id': siteId,
                        'site_name': entry['site_name'] ?? 'Unknown',
                      };
                    }
                  }
                  
                  final sites = sitesMap.values.toList();
                  
                  if (sites.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  
                  return Container(
                    color: Colors.white,
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1, color: Colors.white),
                        SizedBox(height: 10.h),
                        Text(
                          'Filter by Site',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        DropdownButtonFormField<String?>(
                          value: _selectedSiteId,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.location_on, color: AppColors.deepNavy, size: 20.sp),
                            filled: true,
                            fillColor: AppColors.lightSlate,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(
                                color: AppColors.deepNavy.withValues(alpha: 0.1),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: const BorderSide(
                                color: AppColors.deepNavy,
                                width: 2,
                              ),
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                          ),
                          isExpanded: true,
                          items: [
                            // "All Sites" option
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'All Sites',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.deepNavy,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // Individual sites
                            ...sites.map((site) {
                              return DropdownMenuItem<String?>(
                                value: site['site_id'] as String,
                                child: Text(
                                  site['site_name'] as String,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.deepNavy,
                                  ),
                                ),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedSiteId = value);
                          },
                          icon: const Icon(Icons.arrow_drop_down, color: AppColors.deepNavy),
                          dropdownColor: AppColors.cleanWhite,
                        ),
                      ],
                    ),
                  );
                },
              ),

              // ── Summary row ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _SummaryChip(
                      icon: Icons.people,
                      label: 'Labour',
                      count: labourEntries.length,
                      color: AppColors.statusCompleted,
                    ),
                    const SizedBox(width: 8),
                    _SummaryChip(
                      icon: Icons.inventory_2,
                      label: 'Material',
                      count: materialEntries.length,
                      color: AppColors.deepNavy,
                    ),
                    const SizedBox(width: 8),
                    _SalarySummaryChip(totalSalary: totalSalary),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 12),

              // ── Entry Type filter chips ──────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter by Entry Type',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // "All" chip
                        SizedBox(
                          width: (MediaQuery.of(context).size.width - 48) / 2,
                          child: _EntryTypeChip(
                            label: 'All',
                            icon: Icons.list_alt,
                            selected: _selectedEntryType == null,
                            onTap: () => setState(() => _selectedEntryType = null),
                          ),
                        ),
                        // "Labour" chip
                        SizedBox(
                          width: (MediaQuery.of(context).size.width - 48) / 2,
                          child: _EntryTypeChip(
                            label: 'Labour',
                            icon: Icons.people,
                            selected: _selectedEntryType == 'labour',
                            onTap: () => setState(() =>
                                _selectedEntryType = _selectedEntryType == 'labour' ? null : 'labour'),
                          ),
                        ),
                        // "Material" chip
                        SizedBox(
                          width: (MediaQuery.of(context).size.width - 48) / 2,
                          child: _EntryTypeChip(
                            label: 'Material',
                            icon: Icons.inventory_2,
                            selected: _selectedEntryType == 'material',
                            onTap: () => setState(() =>
                                _selectedEntryType = _selectedEntryType == 'material' ? null : 'material'),
                          ),
                        ),
                        // "Extra Cost" chip
                        SizedBox(
                          width: (MediaQuery.of(context).size.width - 48) / 2,
                          child: _EntryTypeChip(
                            label: 'Extra Cost',
                            icon: Icons.attach_money,
                            selected: _selectedEntryType == 'extra_cost',
                            onTap: () => setState(() =>
                                _selectedEntryType = _selectedEntryType == 'extra_cost' ? null : 'extra_cost'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Entries list ─────────────────────────────────
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.deepNavy))
                    : RefreshIndicator(
                        onRefresh: () async {
                          provider.clearAccountantCache();
                          await provider.loadAccountantData(forceRefresh: true);
                        },
                        color: AppColors.deepNavy,
                        child: _buildList(labourEntries, materialEntries, extraCosts),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(
      List<Map<String, dynamic>> labour,
      List<Map<String, dynamic>> material,
      List<Map<String, dynamic>> extraCosts) {
    // Apply entry type filter
    final filteredLabour = _selectedEntryType == 'material' || _selectedEntryType == 'extra_cost'
        ? <Map<String, dynamic>>[]
        : labour;
    final filteredMaterial = _selectedEntryType == 'labour' || _selectedEntryType == 'extra_cost'
        ? <Map<String, dynamic>>[]
        : material;
    final filteredExtraCosts = _selectedEntryType == 'labour' || _selectedEntryType == 'material'
        ? <Map<String, dynamic>>[]
        : extraCosts;

    if (filteredLabour.isEmpty && filteredMaterial.isEmpty && filteredExtraCosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy,
                size: 72,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              _selectedDate != null
                  ? 'No entries on ${_friendlyDate(_selectedDate!)}'
                  : 'No entries found',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedRole != null
                  ? 'No $_selectedRole entries for the selected filters'
                  : 'Try a different date or role filter',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Group labour by type
    final Map<String, Map<String, dynamic>> labourGroups = {};
    for (final e in filteredLabour) {
      final type = e['labour_type'] as String? ?? 'General';
      if (!labourGroups.containsKey(type)) {
        labourGroups[type] = {'count': 0, 'total_cost': 0.0, 'unit': ''};
      }
      labourGroups[type]!['count'] =
          (labourGroups[type]!['count'] as int) + ((e['labour_count'] as int?) ?? 0);
      labourGroups[type]!['total_cost'] =
          (labourGroups[type]!['total_cost'] as double) +
              ((e['total_cost'] as double?) ?? 0.0);
    }

    // Group material by type
    final Map<String, Map<String, dynamic>> materialGroups = {};
    for (final e in filteredMaterial) {
      final type = e['material_type'] as String? ?? 'Unknown';
      final unit = e['unit'] as String? ?? '';
      if (!materialGroups.containsKey(type)) {
        materialGroups[type] = {'quantity': 0.0, 'unit': unit};
      }
      materialGroups[type]!['quantity'] =
          (materialGroups[type]!['quantity'] as double) +
              ((e['quantity'] as num?)?.toDouble() ?? 0.0);
    }

    final totalWorkers = labourGroups.values
        .fold<int>(0, (s, v) => s + (v['count'] as int));
    final totalCost = labourGroups.values
        .fold<double>(0, (s, v) => s + (v['total_cost'] as double));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepNavy.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card header ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.deepNavy,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.summarize_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Daily Summary',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (totalCost > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '₹${totalCost.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Labour section ───────────────────────────────
            if (labourGroups.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.statusCompleted.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.engineering,
                          color: AppColors.statusCompleted, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Labour',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.statusCompleted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$totalWorkers workers',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              ...labourGroups.entries.map((entry) => _buildLabourRow(
                  entry.key, entry.value['count'] as int, entry.value['total_cost'] as double)),
              const SizedBox(height: 4),
            ],

            // ── Divider ──────────────────────────────────────
            if (labourGroups.isNotEmpty && materialGroups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: Colors.white, thickness: 1.5),
              ),

            // ── Material section ─────────────────────────────
            if (materialGroups.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.deepNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.inventory_2,
                          color: AppColors.deepNavy, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Materials',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.deepNavy,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${materialGroups.length} type${materialGroups.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              ...materialGroups.entries.map((entry) => _buildMaterialRow(
                  entry.key,
                  entry.value['quantity'] as double,
                  entry.value['unit'] as String)),
              const SizedBox(height: 4),
            ],

            // ── Divider ──────────────────────────────────────
            if ((labourGroups.isNotEmpty || materialGroups.isNotEmpty) && filteredExtraCosts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: Colors.white, thickness: 1.5),
              ),

            // ── Extra Costs section ──────────────────────────
            if (filteredExtraCosts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.attach_money,
                          color: Colors.orange, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Extra Costs',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${filteredExtraCosts.length} item${filteredExtraCosts.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              ...filteredExtraCosts.map((cost) => _buildExtraCostRow(
                  cost['description'] as String? ?? 'Unknown',
                  cost['amount'] as double? ?? 0,
                  cost['submitted_by_role'] as String? ?? '')),
              const SizedBox(height: 4),
            ],

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildLabourRow(String type, int count, double cost) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              type,
              style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.deepNavy,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '$count workers',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cost > 0
                  ? AppColors.statusCompleted.withValues(alpha: 0.1)
                  : AppColors.lightSlate,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              cost > 0 ? '₹${cost.toStringAsFixed(0)}' : '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: cost > 0 ? AppColors.statusCompleted : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialRow(String type, double quantity, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              type,
              style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.deepNavy,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${quantity % 1 == 0 ? quantity.toInt() : quantity.toStringAsFixed(2)} $unit',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraCostRow(String description, double amount, String role) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.deepNavy,
                      fontWeight: FontWeight.w500),
                ),
                if (role.isNotEmpty)
                  Text(
                    'by $role',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '₹${amount.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool disabled;

  const _ArrowBtn({required this.icon, required this.onTap, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 40,
        height: 44,
        decoration: BoxDecoration(
          color: disabled
              ? AppColors.lightSlate
              : AppColors.deepNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.deepNavy.withValues(alpha: disabled ? 0.1 : 0.2),
          ),
        ),
        child: Icon(
          icon,
          color: disabled
              ? AppColors.textSecondary.withValues(alpha: 0.4)
              : AppColors.deepNavy,
          size: 22,
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : AppColors.lightSlate,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.deepNavy : AppColors.deepNavy.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: AppColors.deepNavy,
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _SummaryChip(
      {required this.icon,
      required this.label,
      required this.count,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepNavy.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SalarySummaryChip extends StatelessWidget {
  final double totalSalary;
  const _SalarySummaryChip({required this.totalSalary});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF1A1A2E); // purple
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepNavy.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.currency_rupee, color: color, size: 18),
            const SizedBox(width: 4),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    totalSalary > 0
                        ? '₹${totalSalary.toStringAsFixed(0)}'
                        : '—',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Salary',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _EntryTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : AppColors.cleanWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.deepNavy : AppColors.deepNavy.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.deepNavy.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? AppColors.deepNavy : AppColors.deepNavy,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? AppColors.deepNavy : AppColors.deepNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
