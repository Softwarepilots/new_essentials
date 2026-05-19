import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/accountant_bills_service.dart';
import '../services/budget_management_service.dart';
import '../services/cache_service.dart';
import '../services/construction_service.dart';
import '../utils/smooth_animations.dart';
import 'site_engineer_material_screen.dart';

class AdminBudgetManagementScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const AdminBudgetManagementScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<AdminBudgetManagementScreen> createState() => _AdminBudgetManagementScreenState();
}

class _AdminBudgetManagementScreenState extends State<AdminBudgetManagementScreen>
    with TickerProviderStateMixin {
  final _budgetService = BudgetManagementService();
  late TabController _tabController;
  
  // Background refresh timer
  Timer? _refreshTimer;

  // Budget allocation data
  Map<String, dynamic>? _budgetAllocation;
  bool _isLoadingBudget = false;

  // Utilization data
  Map<String, dynamic>? _utilization;
  bool _isLoadingUtilization = false;
  
  // Date filter for utilization
  DateTime? _selectedFilterDate;
  bool _isFilterActive = false;
  
  // Cost type filter for utilization
  String? _selectedCostFilter; // 'material', 'labour', 'other', or null for all

  // Client requirements data
  List<Map<String, dynamic>> _clientRequirements = [];
  bool _isLoadingRequirements = false;
  bool _requirementsExpanded = false;
  
  // Phase payments data
  Map<String, dynamic>? _phasePayments;
  bool _isLoadingPhases = false;
  
  // Cache flags to prevent redundant loading
  bool _budgetLoaded = false;
  bool _utilizationLoaded = false;
  bool _requirementsLoaded = false;

  // Excel export state
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    // Add listener to load utilization only on first access
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {}); // Rebuild to update FAB visibility
        if (_tabController.index == 1) {
          // Load utilization only if not already loaded
          if (!_utilizationLoaded) {
            _loadUtilization();
          }
        }
      }
    });
    _loadBudgetAllocation();
    _loadClientRequirements();
    _loadPhasePayments();
    _startBackgroundRefresh();
  }

  @override
  void dispose() {
    _stopBackgroundRefresh();
    _tabController.dispose();
    super.dispose();
  }
  
  void _startBackgroundRefresh() {
    // Refresh budget data every 90 seconds (only when not actively updating)
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 90),
      (timer) {
        if (mounted && !_isLoadingBudget && !_isLoadingPhases) {
          // Silently refresh current tab data (don't force, use cache if available)
          if (_tabController.index == 0) {
            _loadBudgetAllocation();
            _loadClientRequirements();
            _loadPhasePayments();
          } else if (_tabController.index == 1) {
            _loadUtilization();
          }
          // Tab index 2 is Updates (photos) - no auto-refresh needed
        }
      },
    );
  }
  
  void _stopBackgroundRefresh() {
    _refreshTimer?.cancel();
  }

  Future<void> _loadBudgetAllocation({bool forceRefresh = false}) async {
    // If forcing refresh, clear cache FIRST before loading
    if (forceRefresh) {
      print('🗑️ [BUDGET] Clearing cache before refresh');
      await CacheService.clearBudgetAllocation(widget.siteId);
      _budgetLoaded = false;
    }
    
    // Load from persistent cache first (instant display)
    if (!forceRefresh && !_budgetLoaded) {
      final cached = await CacheService.loadBudgetAllocation(widget.siteId);
      if (cached != null && mounted) {
        setState(() {
          _budgetAllocation = cached;
          _budgetLoaded = true;
        });
        print('✅ [BUDGET] Loaded allocation from persistent cache');
      }
    }
    
    // Skip if already loaded and not forcing refresh
    if (_budgetLoaded && !forceRefresh) return;
    
    setState(() => _isLoadingBudget = true);
    final budget = await _budgetService.getBudgetAllocation(widget.siteId);
    
    if (budget != null) {
      // Save to persistent cache
      await CacheService.saveBudgetAllocation(widget.siteId, budget);
    }
    
    if (mounted) {
      setState(() {
        _budgetAllocation = budget;
        _isLoadingBudget = false;
        _budgetLoaded = true;
      });
      print('✅ [BUDGET] Loaded allocation from API and saved to cache');
    }
  }

  Future<void> _loadClientRequirements({bool forceRefresh = false}) async {
    // Skip if already loaded and not forcing refresh
    if (_requirementsLoaded && !forceRefresh) return;
    
    print('🔍 Loading client requirements for site: ${widget.siteId}');
    setState(() => _isLoadingRequirements = true);
    final requirements = await _budgetService.getClientRequirements(widget.siteId);
    print('📦 Received ${requirements.length} requirements');
    if (mounted) {
      setState(() {
        _clientRequirements = requirements;
        _isLoadingRequirements = false;
        _requirementsLoaded = true;
      });
    }
  }

  Future<void> _loadPhasePayments({bool forceRefresh = false}) async {
    print('🔄 [PHASES] Loading phase payments...');
    setState(() => _isLoadingPhases = true);
    final phases = await _budgetService.getPhasePayments(widget.siteId);
    print('📦 [PHASES] Received data: $phases');
    if (mounted) {
      setState(() {
        _phasePayments = phases;
        _isLoadingPhases = false;
      });
      print('✅ [PHASES] State updated, should rebuild now');
    }
  }

  Future<void> _loadUtilization({bool forceRefresh = false}) async {
    // If forcing refresh, clear cache FIRST before loading
    if (forceRefresh) {
      print('🗑️ [BUDGET] Clearing utilization cache before refresh');
      await CacheService.clearBudgetUtilization(widget.siteId);
      _utilizationLoaded = false;
    }
    
    // Load from persistent cache first (instant display)
    if (!forceRefresh && !_utilizationLoaded && !_isFilterActive && _selectedCostFilter == null) {
      final cached = await CacheService.loadBudgetUtilization(widget.siteId);
      if (cached != null && mounted) {
        setState(() {
          _utilization = cached;
          _utilizationLoaded = true;
        });
        print('✅ [BUDGET] Loaded utilization from persistent cache');
      }
    }
    
    // Skip if already loaded and not forcing refresh
    if (_utilizationLoaded && !forceRefresh && !_isFilterActive && _selectedCostFilter == null) return;
    
    setState(() => _isLoadingUtilization = true);
    
    // Format date for API if filter is active
    String? filterDate;
    if (_isFilterActive && _selectedFilterDate != null) {
      filterDate = '${_selectedFilterDate!.year}-${_selectedFilterDate!.month.toString().padLeft(2, '0')}-${_selectedFilterDate!.day.toString().padLeft(2, '0')}';
    }
    
    final utilization = await _budgetService.getBudgetUtilization(
      widget.siteId, 
      filterDate: filterDate,
      filterType: _selectedCostFilter,
    );
    
    if (utilization != null && !_isFilterActive && _selectedCostFilter == null) {
      // Save to persistent cache only if not filtering
      await CacheService.saveBudgetUtilization(widget.siteId, utilization);
    }
    
    if (mounted) {
      setState(() {
        _utilization = utilization;
        _isLoadingUtilization = false;
        if (!_isFilterActive && _selectedCostFilter == null) {
          _utilizationLoaded = true;
        }
      });
      print('✅ [BUDGET] Loaded utilization from API${_isFilterActive || _selectedCostFilter != null ? ' (filtered)' : ' and saved to cache'}');
    }
  }

  String _formatCurrency(dynamic amount) {
    if (amount == null) return '₹0';
    double value = amount is String ? double.tryParse(amount) ?? 0 : amount.toDouble();

    if (value >= 10000000) {
      return '₹${(value / 10000000).toStringAsFixed(2)} Cr';
    } else if (value >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(2)} L';
    } else if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(2)} K';
    }
    return '₹${value.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Budget - ${widget.siteName}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          tabs: const [
            Tab(text: 'Allocation'),
            Tab(text: 'Utilization'),
            Tab(text: 'Updates'),
            Tab(text: 'Inventory'),
            Tab(text: 'Document'),
            Tab(text: 'Requirement'),
            Tab(text:'Bills')
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllocationTab(),
          _buildUtilizationTab(),
          PhotoTabsSection(siteId: widget.siteId),
          _buildInventoryTab(),
          _buildDocumentTab(),
          _buildRequirementTab(),
          _buildBillsTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              onPressed: _showAddCostDialog,
              backgroundColor: const Color(0xFF1A1A2E),
              child: const Icon(Icons.add, color: Colors.white),
              tooltip: 'Add Cost',
            )
          : null,
    );
  }

  Widget _buildAllocationTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadBudgetAllocation(forceRefresh: true);
        await _loadPhasePayments(forceRefresh: true);
      },
      color: const Color(0xFF1A1A2E),
      child: _isLoadingBudget
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_budgetAllocation != null) ...[
                    _buildBudgetCard(
                      'Total Budget',
                      _formatCurrency(_budgetAllocation!['total_budget']),
                      Icons.account_balance_wallet,
                      Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    // Client Balance Card
                    _buildBudgetCard(
                      'Client Balance',
                      _formatCurrency(_phasePayments?['client_balance'] ?? _budgetAllocation!['total_budget']),
                      Icons.account_balance,
                      Colors.green,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Details',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            _buildDetailRow('Allocated By', _budgetAllocation!['allocated_by'] ?? 'N/A'),
                            _buildDetailRow('Date', _budgetAllocation!['allocated_date']?.substring(0, 10) ?? 'N/A'),
                            _buildDetailRow('Status', _budgetAllocation!['status'] ?? 'N/A'),
                            if (_budgetAllocation!['notes'] != null && _budgetAllocation!['notes'].toString().isNotEmpty)
                              _buildDetailRow('Notes', _budgetAllocation!['notes']),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No budget allocated yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAllocateBudgetDialog(),
                    icon: const Icon(Icons.add),
                    label: Text(_budgetAllocation == null ? 'Allocate Budget' : 'Update Budget'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Phase Payments Section
                  if (_budgetAllocation != null) _buildPhasePaymentsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildPhasePaymentsSection() {
    if (_phasePayments == null || _isLoadingPhases) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    
    final phases = List<Map<String, dynamic>>.from(_phasePayments!['phases'] ?? []);
    final clientBalance = _phasePayments!['client_balance'] ?? 0;
    final totalReceived = _phasePayments!['total_received'] ?? 0;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments, color: Color(0xFF1A1A2E)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Phase Payments',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Received: ${_formatCurrency(totalReceived)}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Show all 10 phases
            for (int i = 1; i <= 10; i++) ...[
              _buildPhaseRow(i, phases, clientBalance),
              if (i < 10) const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseRow(int phaseNumber, List<Map<String, dynamic>> phases, double clientBalance) {
    final phase = phases.firstWhere(
      (p) => p['phase_number'] == phaseNumber,
      orElse: () => {},
    );
    
    final isPaid = phase.isNotEmpty;
    final amount = isPaid ? phase['phase_amount'] : 0.0;
    
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: isPaid ? Colors.green : Colors.grey[300],
          child: Text(
            '$phaseNumber',
            style: TextStyle(
              color: isPaid ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phase $phaseNumber',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isPaid) ...[
                const SizedBox(height: 4),
                Text(
                  'Paid: ${_formatCurrency(amount)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                if (phase['payment_date'] != null)
                  Text(
                    'Date: ${phase['payment_date'].toString().substring(0, 10)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
              ] else
                Text(
                  'Not paid yet',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
            ],
          ),
        ),
        if (isPaid) ...[
          const Icon(Icons.check_circle, color: Colors.green, size: 28),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showEditPhaseDialog(phaseNumber, amount, phase),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Edit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ] else
          ElevatedButton.icon(
            onPressed: () => _showRecordPhasePaymentDialog(phaseNumber, clientBalance),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Record'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A2E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
      ],
    );
  }

  void _showRecordPhasePaymentDialog(int phaseNumber, double clientBalance) {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool isSubmitting = false; // Track submission state
    final outerSetState = setState; // capture outer widget's setState before dialog shadows it

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Record Phase $phaseNumber Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Client Balance',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              _formatCurrency(clientBalance),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount *',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                    hintText: 'Enter payment amount',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                  trailing: const Icon(Icons.calendar_today),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Add any notes about this payment',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                // Disable button immediately
                setState(() => isSubmitting = true);
                
                if (amountController.text.isEmpty) {
                  setState(() => isSubmitting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter amount')),
                  );
                  return;
                }

                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  setState(() => isSubmitting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }

                if (amount > clientBalance) {
                  setState(() => isSubmitting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Amount exceeds client balance (${_formatCurrency(clientBalance)})'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Close dialog immediately
                if (context.mounted) {
                  Navigator.pop(context);
                }

                // Optimistically update UI immediately (before API call)
                if (mounted) {
                  outerSetState(() {
                    // Update phase payments optimistically
                    if (_phasePayments != null) {
                      final phases = List<Map<String, dynamic>>.from(_phasePayments!['phases'] ?? []);
                      phases.add({
                        'phase_number': phaseNumber,
                        'phase_amount': amount,
                        'payment_date': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                      });
                      _phasePayments!['phases'] = phases;

                      // Update client balance
                      final currentBalance = _phasePayments!['client_balance'] ?? 0.0;
                      _phasePayments!['client_balance'] = currentBalance - amount;

                      // Update total received
                      final currentReceived = _phasePayments!['total_received'] ?? 0.0;
                      _phasePayments!['total_received'] = currentReceived + amount;
                    }
                  });
                }

                // Show brief loading message (500ms)
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Recording payment...'),
                      duration: Duration(milliseconds: 500),
                    ),
                  );
                }

                // Call API in background with 2-second timeout
                try {
                  final result = await _budgetService.recordPhasePayment(
                    siteId: widget.siteId,
                    phaseNumber: phaseNumber,
                    phaseAmount: amount,
                    paymentDate: '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                    notes: notesController.text.isEmpty ? null : notesController.text,
                  ).timeout(
                    const Duration(seconds: 2),
                    onTimeout: () {
                      print('⚠️ [PAYMENT] API timeout after 2s, optimistic update shown');
                      // Return success on timeout - optimistic update already shown
                      return {'success': true, 'message': 'Payment queued'};
                    },
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    
                    if (result['success'] == true) {
                      // Success - refresh in background to sync with server
                      _loadPhasePayments(forceRefresh: true);
                      _loadBudgetAllocation(forceRefresh: true);
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ Payment recorded'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    } else {
                      // Failed - revert optimistic update
                      _loadPhasePayments(forceRefresh: true);
                      _loadBudgetAllocation(forceRefresh: true);
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result['error'] ?? 'Failed to record payment'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  print('❌ [PAYMENT] Error: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Network error, please check connection'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    // Revert optimistic update
                    _loadPhasePayments(forceRefresh: true);
                    _loadBudgetAllocation(forceRefresh: true);
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A2E)),
              child: isSubmitting 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Record Payment'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPhaseDialog(int phaseNumber, double currentAmount, Map<String, dynamic> phase) {
    final amountController = TextEditingController(text: currentAmount.toString());
    final notesController = TextEditingController(text: phase['notes'] ?? '');
    DateTime selectedDate = phase['payment_date'] != null
        ? DateTime.parse(phase['payment_date'])
        : DateTime.now();
    bool isSubmitting = false;
    final outerSetState = setState;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit Phase $phaseNumber Amount'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Amount',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              _formatCurrency(currentAmount),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'New Amount *',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                    hintText: 'Enter new amount',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                  trailing: const Icon(Icons.calendar_today),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Add any notes about this payment',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                setState(() => isSubmitting = true);

                if (amountController.text.isEmpty) {
                  setState(() => isSubmitting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter amount')),
                  );
                  return;
                }

                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  setState(() => isSubmitting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }

                if (context.mounted) {
                  Navigator.pop(context);
                }

                // Optimistically update UI
                if (mounted) {
                  outerSetState(() {
                    if (_phasePayments != null) {
                      final phases = List<Map<String, dynamic>>.from(_phasePayments!['phases'] ?? []);
                      final phaseIndex = phases.indexWhere((p) => p['phase_number'] == phaseNumber);
                      if (phaseIndex != -1) {
                        final diff = amount - currentAmount;
                        phases[phaseIndex]['phase_amount'] = amount;
                        phases[phaseIndex]['payment_date'] =
                          '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                        _phasePayments!['phases'] = phases;

                        final currentBalance = _phasePayments!['client_balance'] ?? 0.0;
                        _phasePayments!['client_balance'] = currentBalance - diff;

                        final currentReceived = _phasePayments!['total_received'] ?? 0.0;
                        _phasePayments!['total_received'] = currentReceived + diff;
                      }
                    }
                  });
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Updating amount...'),
                      duration: Duration(milliseconds: 500),
                    ),
                  );
                }

                try {
                  final result = await _budgetService.updatePhasePayment(
                    siteId: widget.siteId,
                    phaseNumber: phaseNumber,
                    phaseAmount: amount,
                    paymentDate: '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                    notes: notesController.text.isEmpty ? null : notesController.text,
                  ).timeout(
                    const Duration(seconds: 2),
                    onTimeout: () => {'success': true, 'message': 'Update queued'},
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();

                    if (result['success'] == true) {
                      _loadPhasePayments(forceRefresh: true);
                      _loadBudgetAllocation(forceRefresh: true);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ Amount updated'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    } else {
                      _loadPhasePayments(forceRefresh: true);
                      _loadBudgetAllocation(forceRefresh: true);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result['error'] ?? 'Failed to update amount'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  print('❌ [PHASE UPDATE] Error: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Network error, please check connection'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    _loadPhasePayments(forceRefresh: true);
                    _loadBudgetAllocation(forceRefresh: true);
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Update Amount'),
            ),
          ],
        ),
      ),
    );
  }

Widget _buildBillsTab() {
  return _AdminBillsTab(siteId: widget.siteId, siteName: widget.siteName);
}

  Widget _buildRecentUpdatesDropdown() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() => _requirementsExpanded = !_requirementsExpanded);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withValues(alpha: 0.1),
                borderRadius: _requirementsExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(4))
                    : BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.update, color: const Color(0xFF1A1A2E), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Recent Updates',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '4',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _requirementsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF1A1A2E),
                  ),
                ],
              ),
            ),
          ),
          if (_requirementsExpanded) ...[
            const Divider(height: 1),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _clientRequirements.length,
              itemBuilder: (context, index) {
                final req = _clientRequirements[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A2E).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              req['category'] ?? 'General',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            req['date'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        req['requirement'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUtilizationTab() {
    return RefreshIndicator(
      onRefresh: () => _loadUtilization(forceRefresh: true),
      color: const Color(0xFF1A1A2E),
      child: _isLoadingUtilization
          ? const Center(child: CircularProgressIndicator())
          : _utilization == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pie_chart_outline, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No utilization data available', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Download Excel Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportToExcel,
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download_rounded,
                                  color: Colors.white),
                          label: Text(
                            _isExporting
                                ? 'Generating Excel...'
                                : 'Download Expense Report (Excel)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Date Filter Card
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              // Date filter row
                              Row(
                                children: [
                                  Icon(
                                    _isFilterActive ? Icons.filter_alt : Icons.filter_alt_outlined,
                                    color: _isFilterActive ? const Color(0xFF1A1A2E) : Colors.grey,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _isFilterActive && _selectedFilterDate != null
                                          ? 'Date: ${_selectedFilterDate!.day}/${_selectedFilterDate!.month}/${_selectedFilterDate!.year}'
                                          : 'All Dates',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _isFilterActive ? const Color(0xFF1A1A2E) : Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                  if (_isFilterActive)
                                    IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        setState(() {
                                          _isFilterActive = false;
                                          _selectedFilterDate = null;
                                        });
                                        _loadUtilization(forceRefresh: true);
                                      },
                                      tooltip: 'Clear date filter',
                                      color: Colors.red,
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.calendar_today, size: 20),
                                    onPressed: _showDateFilterPicker,
                                    tooltip: 'Filter by date',
                                    color: const Color(0xFF1A1A2E),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              // Cost type filter row
                              Row(
                                children: [
                                  const Icon(Icons.category, color: Colors.grey),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButton<String>(
                                      value: _selectedCostFilter,
                                      hint: const Text('All Costs'),
                                      isExpanded: true,
                                      underline: Container(),
                                      items: const [
                                        DropdownMenuItem(value: null, child: Text('All Costs')),
                                        DropdownMenuItem(value: 'material', child: Text('Material Only')),
                                        DropdownMenuItem(value: 'labour', child: Text('Labour Only')),
                                        DropdownMenuItem(value: 'other', child: Text('Other Only')),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedCostFilter = value;
                                        });
                                        _loadUtilization(forceRefresh: true);
                                      },
                                    ),
                                  ),
                                  if (_selectedCostFilter != null)
                                    IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        setState(() {
                                          _selectedCostFilter = null;
                                        });
                                        _loadUtilization(forceRefresh: true);
                                      },
                                      tooltip: 'Clear cost filter',
                                      color: Colors.red,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Summary Card
                      Card(
                        color: _getStatusColor(_utilization!['summary']['status']),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                _formatCurrency(_utilization!['summary']['total_spent']),
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                _isFilterActive ? 'Spent on Selected Date' : 'Total Spent',
                                style: const TextStyle(fontSize: 16, color: Colors.white70),
                              ),
                              const SizedBox(height: 16),
                              LinearProgressIndicator(
                                value: (_utilization!['summary']['utilization_percentage'] ?? 0) / 100,
                                backgroundColor: Colors.white30,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                minHeight: 10,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_utilization!['summary']['utilization_percentage'] ?? 0).toStringAsFixed(1)}% Utilized',
                                style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Budget Overview
                      Row(
                        children: [
                          Expanded(
                            child: _buildSmallCard('Total Budget', _formatCurrency(_utilization!['summary']['total_budget']), Colors.blue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSmallCard('Remaining', _formatCurrency(_utilization!['summary']['remaining_budget']), Colors.green),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSmallCard('Material', _formatCurrency(_utilization!['summary']['total_material_cost']), Colors.brown),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSmallCard('Labour', _formatCurrency(_utilization!['summary']['total_labour_cost']), const Color(0xFF1A1A2E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Material Breakdown
                      if ((List<Map<String, dynamic>>.from(_utilization!['material_breakdown'] ?? [])).isNotEmpty) ...[
                        const Text('Material Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...(List<Map<String, dynamic>>.from(_utilization!['material_breakdown'] ?? [])).map((m) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.inventory_2, color: Colors.brown),
                                title: Text(m['material_type'] ?? 'Unknown'),
                                subtitle: Text('${m['total_quantity']} ${m['unit']}'),
                                trailing: Text(_formatCurrency(m['total_cost']), style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            )),
                        const SizedBox(height: 16),
                      ],

                      // Labour Breakdown
                      if ((List<Map<String, dynamic>>.from(_utilization!['labour_breakdown'] ?? [])).isNotEmpty) ...[
                        const Text('Labour Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...(List<Map<String, dynamic>>.from(_utilization!['labour_breakdown'] ?? [])).map((l) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.people, color: Color(0xFF1A1A2E)),
                                title: Text(l['labour_type'] ?? 'Unknown'),
                      subtitle: Text('${l['total_count']} workers × ${_formatCurrency(l['avg_rate'])}/day'),
                      trailing: Text(_formatCurrency(l['total_cost']), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )),
                        const SizedBox(height: 16),
            ],
            
                      // Other Costs Breakdown
                      if ((List<Map<String, dynamic>>.from(_utilization!['other_breakdown'] ?? [])).isNotEmpty) ...[
                        const Text('Other Costs Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...(List<Map<String, dynamic>>.from(_utilization!['other_breakdown'] ?? [])).map((o) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.attach_money, color: Colors.purple),
                                title: Text(o['service_type'] ?? 'Unknown'),
                                subtitle: Text(o['vendor_type'] ?? ''),
                                trailing: Text(_formatCurrency(o['total_cost']), style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            )),
                      ],
          ],
        ),
      ),
    );
  }
  
  // ── Excel Export ─────────────────────────────────────────────────────────
  // Layout matches reference: each labour type = one column,
  // LABOUR COUNT row + SALARY row, TOTAL AMOUNT in last column.

  Future<void> _exportToExcel() async {
    if (_utilization == null || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      final excelFile = Excel.createExcel();
      const sheetName = 'Salary Sheet';
      final Sheet sheet = excelFile[sheetName];
      if (excelFile.sheets.containsKey('Sheet1')) excelFile.delete('Sheet1');

      final summary =
          Map<String, dynamic>.from(_utilization!['summary'] ?? {});
      final labourBreakdown = List<Map<String, dynamic>>.from(
          _utilization!['labour_breakdown'] ?? []);
      final materialBreakdown = List<Map<String, dynamic>>.from(
          _utilization!['material_breakdown'] ?? []);
      final otherBreakdown = List<Map<String, dynamic>>.from(
          _utilization!['other_breakdown'] ?? []);

      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

      // ── Calculate column layout ────────────────────────────────────────
      // Col 0        : SITE NAME / row label
      // Col 1..N     : one per labour type
      // Col N+1      : MATERIAL (if any material data)
      // Col N+2      : MISCELLANEOUS (if any other data)
      // Last col     : TOTAL AMOUNT
      final labourTypes = labourBreakdown
          .map((l) => (l['labour_type'] as String? ?? 'Unknown').toUpperCase())
          .toList();
      final hasMaterial = materialBreakdown.isNotEmpty;
      final hasOther = otherBreakdown.isNotEmpty;

      const int labelCol = 0;
      const int labourStart = 1;
      final int labourEnd = labourStart + labourTypes.length - 1;
      int nextCol = labourEnd + 1;
      final int? materialCol = hasMaterial ? nextCol++ : null;
      final int? otherCol = hasOther ? nextCol++ : null;
      final int totalCol = nextCol;
      final int numCols = totalCol + 1;

      int row = 0;

      // ── Title row ─────────────────────────────────────────────────────
      _xlBand(sheet, row, 'ESSENTIAL HOMES — SALARY SHEET', 'FF1A1A2E', 14, numCols);
      row++;

      _xlBand(sheet, row,
          'Site: ${widget.siteName}   |   Generated: $dateStr', 'FF2E7D32', 11, numCols);
      row++;
      row++; // blank

      // ── Column headers (matches reference: black bg, white text) ───────
      final hdrStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#FF000000'),
      );
      _xlStyled(sheet, labelCol, row, 'SITE NAME', hdrStyle);
      for (int i = 0; i < labourTypes.length; i++) {
        _xlStyled(sheet, labourStart + i, row, labourTypes[i], hdrStyle);
      }
      if (materialCol != null) _xlStyled(sheet, materialCol, row, 'MATERIAL', hdrStyle);
      if (otherCol != null) _xlStyled(sheet, otherCol, row, 'MISCELLANEOUS', hdrStyle);
      _xlStyled(sheet, totalCol, row, 'TOTAL AMOUNT', hdrStyle);
      row++;

      // ── Site name row (just the site name in col 0) ───────────────────
      final siteStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FF1A1A2E'),
      );
      _xlStyled(sheet, labelCol, row, widget.siteName, siteStyle);
      for (int c = 1; c < numCols; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .value = TextCellValue('');
      }
      row++;

      // ── LABOUR COUNT row (dark navy bg, green text — like reference) ───
      final countLabelStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FF00DD00'),
        backgroundColorHex: ExcelColor.fromHexString('#FF1A1A2E'),
      );
      final countValStyle = CellStyle(
        fontColorHex: ExcelColor.fromHexString('#FF000000'),
        backgroundColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      );
      _xlStyled(sheet, labelCol, row, 'LABOUR COUNT', countLabelStyle);
      int totalCount = 0;
      for (int i = 0; i < labourBreakdown.length; i++) {
        final cnt = (labourBreakdown[i]['total_count'] as num?)?.toInt() ?? 0;
        _xlStyled(sheet, labourStart + i, row, cnt.toString(), countValStyle);
        totalCount += cnt;
      }
      if (materialCol != null) _xlStyled(sheet, materialCol, row, '-', countValStyle);
      if (otherCol != null) _xlStyled(sheet, otherCol, row, '-', countValStyle);
      _xlStyled(sheet, totalCol, row, totalCount.toString(),
          CellStyle(
            bold: true,
            fontColorHex: ExcelColor.fromHexString('#FF1A1A2E'),
            backgroundColorHex: ExcelColor.fromHexString('#FFE8F5E9'),
          ));
      row++;

      // ── SALARY row (black bg, yellow text — like reference) ───────────
      final salaryLabelStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF00'),
        backgroundColorHex: ExcelColor.fromHexString('#FF000000'),
      );
      final salaryValStyle = CellStyle(
        fontColorHex: ExcelColor.fromHexString('#FF000000'),
        backgroundColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      );
      _xlStyled(sheet, labelCol, row, 'SALARY', salaryLabelStyle);

      double totalLabour = 0;
      for (int i = 0; i < labourBreakdown.length; i++) {
        final cost = _toDouble(labourBreakdown[i]['total_cost']);
        _xlStyled(sheet, labourStart + i, row, _excelAmount(cost), salaryValStyle);
        totalLabour += cost;
      }

      final materialTotal =
          materialBreakdown.fold<double>(0, (s, m) => s + _toDouble(m['total_cost']));
      if (materialCol != null) {
        _xlStyled(sheet, materialCol, row, _excelAmount(materialTotal), salaryValStyle);
      }

      final otherTotal =
          otherBreakdown.fold<double>(0, (s, o) => s + _toDouble(o['total_cost']));
      if (otherCol != null) {
        _xlStyled(sheet, otherCol, row, _excelAmount(otherTotal), salaryValStyle);
      }

      final grandTotal = totalLabour + materialTotal + otherTotal;
      _xlStyled(sheet, totalCol, row, _excelAmount(grandTotal),
          CellStyle(
            bold: true,
            fontSize: 11,
            fontColorHex: ExcelColor.fromHexString('#FFCC0000'),
            backgroundColorHex: ExcelColor.fromHexString('#FFFFF8DC'),
          ));
      row++;
      row++; // blank

      // ── Financial summary block ────────────────────────────────────────
      _xlBand(sheet, row, 'FINANCIAL SUMMARY', 'FF37474F', 11, numCols);
      row++;

      final sumHdrStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#FF455A64'),
      );
      for (final h in ['Field', 'Value', 'Field', 'Value']) {
        final c = ['Field', 'Value', 'Field', 'Value'].indexOf(h);
        _xlStyled(sheet, c, row, h, sumHdrStyle);
      }
      row++;

      _xlText(sheet, 0, row, 'Total Budget', bold: true);
      _xlText(sheet, 1, row, _excelAmount(summary['total_budget']), fgHex: 'FF1565C0');
      _xlText(sheet, 2, row, 'Total Spent', bold: true);
      _xlText(sheet, 3, row, _excelAmount(summary['total_spent']), bold: true, fgHex: 'FFCC0000');
      row++;

      _xlText(sheet, 0, row, 'Total Labour Cost', bold: true);
      _xlText(sheet, 1, row, _excelAmount(summary['total_labour_cost']), fgHex: 'FF1A1A2E');
      _xlText(sheet, 2, row, 'Total Material Cost', bold: true);
      _xlText(sheet, 3, row, _excelAmount(summary['total_material_cost']), fgHex: 'FF4E342E');
      row++;

      _xlText(sheet, 0, row, 'Remaining Budget', bold: true);
      _xlText(sheet, 1, row, _excelAmount(summary['remaining_budget']), fgHex: 'FF1B5E20');
      _xlText(sheet, 2, row, 'Utilization %', bold: true);
      _xlText(sheet, 3, row,
          '${((summary['utilization_percentage'] ?? 0) as num).toStringAsFixed(1)}%');
      row++;
      row++; // blank

      // ── Labour detail table ───────────────────────────────────────────
      _xlBand(sheet, row, 'LABOUR DETAILS (BY TYPE)', 'FF1A1A2E', 11, numCols);
      row++;

      final detailHdrStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#FF37474F'),
      );
      for (final pair in {
        0: 'Labour Type',
        1: 'Workers Count',
        2: 'Rate / Day (₹)',
        3: 'Total Cost (₹)'
      }.entries) {
        _xlStyled(sheet, pair.key, row, pair.value, detailHdrStyle);
      }
      for (int c = 4; c < numCols; c++) {
        _xlStyled(sheet, c, row, '', detailHdrStyle);
      }
      row++;

      for (final l in labourBreakdown) {
        _xlText(sheet, 0, row, l['labour_type'] as String? ?? '');
        _xlText(sheet, 1, row,
            ((l['total_count'] as num?)?.toInt() ?? 0).toString());
        _xlText(sheet, 2, row, _excelAmount(l['avg_rate']));
        _xlText(sheet, 3, row, _excelAmount(l['total_cost']), bold: true);
        row++;
      }
      if (labourBreakdown.isEmpty) {
        _xlText(sheet, 0, row, 'No labour data recorded', fgHex: 'FF999999');
        row++;
      }

      // ── Material detail table (if any) ────────────────────────────────
      if (hasMaterial) {
        row++;
        _xlBand(sheet, row, 'MATERIAL DETAILS', 'FF4E342E', 11, numCols);
        row++;

        for (final pair in {
          0: 'Material Type',
          1: 'Quantity',
          2: 'Unit',
          3: 'Total Cost (₹)'
        }.entries) {
          _xlStyled(sheet, pair.key, row, pair.value, detailHdrStyle);
        }
        for (int c = 4; c < numCols; c++) {
          _xlStyled(sheet, c, row, '', detailHdrStyle);
        }
        row++;

        for (final m in materialBreakdown) {
          _xlText(sheet, 0, row, m['material_type'] as String? ?? '');
          _xlText(sheet, 1, row,
              ((m['total_quantity'] as num?)?.toStringAsFixed(2)) ?? '0');
          _xlText(sheet, 2, row, m['unit'] as String? ?? '');
          _xlText(sheet, 3, row, _excelAmount(m['total_cost']), bold: true);
          row++;
        }
      }

      // ── Column widths ─────────────────────────────────────────────────
      sheet.setColumnWidth(labelCol, 22.0);
      for (int i = 0; i < labourTypes.length; i++) {
        // Wider for long names (e.g. TILE LAYER HELPER)
        final len = labourTypes[i].length.toDouble();
        sheet.setColumnWidth(labourStart + i, (len < 10 ? 14.0 : len * 1.1).clamp(14.0, 22.0));
      }
      if (materialCol != null) sheet.setColumnWidth(materialCol, 18.0);
      if (otherCol != null) sheet.setColumnWidth(otherCol, 18.0);
      sheet.setColumnWidth(totalCol, 20.0);

      // ── Save & open ───────────────────────────────────────────────────
      final dir = await getTemporaryDirectory();
      final safeName = widget.siteName.replaceAll(RegExp(r'[^\w]'), '_');
      final fileName =
          '${safeName}_salary_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(excelFile.encode()!);

      if (mounted) {
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('File saved: ${file.path}'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── Excel cell helpers ────────────────────────────────────────────────

  /// Set a cell with pre-built CellStyle.
  void _xlStyled(Sheet s, int col, int row, String text, CellStyle style) {
    final cell =
        s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(text);
    cell.cellStyle = style;
  }

  /// Plain text cell with optional bold / colour.
  void _xlText(Sheet s, int col, int row, String text,
      {bool bold = false, String fgHex = 'FF000000'}) {
    final cell =
        s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(text);
    if (bold || fgHex != 'FF000000') {
      cell.cellStyle = CellStyle(
        bold: bold,
        fontColorHex: ExcelColor.fromHexString('#$fgHex'),
      );
    }
  }

  /// Full-width merged coloured header band spanning [numCols] columns.
  void _xlBand(Sheet s, int row, String title, String bgHex, int fontSize, int numCols) {
    final style = CellStyle(
      bold: true,
      fontSize: fontSize,
      fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#$bgHex'),
    );
    for (int c = 0; c < numCols; c++) {
      final cell =
          s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = c == 0 ? TextCellValue(title) : TextCellValue('');
      cell.cellStyle = style;
    }
    if (numCols > 1) {
      s.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: numCols - 1, rowIndex: row),
      );
    }
  }

  String _excelAmount(dynamic value) {
    final d = _toDouble(value);
    return '₹${NumberFormat('#,##0.00', 'en_IN').format(d)}';
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────

  void _showDateFilterPicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedFilterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A1A2E),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1A1A2E),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _selectedFilterDate = picked;
        _isFilterActive = true;
      });
      _loadUtilization(forceRefresh: true);
    }
  }
  
  Widget _buildInventoryTab() {
    // Reuse the Site Engineer Material Screen for inventory management
    return SiteEngineerMaterialScreen(
      siteId: widget.siteId,
      siteName: widget.siteName,
    );
  }

  Widget _buildDocumentTab() {
    return _AdminDocumentTab(siteId: widget.siteId);
  }

  Widget _buildRequirementTab() {
    return RefreshIndicator(
      onRefresh: () => _loadClientRequirements(forceRefresh: true),
      color: const Color(0xFF1A1A2E),
      child: _isLoadingRequirements
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A1A2E)))
          : _clientRequirements.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_outlined,
                          size: 72,
                          color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text(
                        'No requirements yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Supervisor or Site Engineer can add\nclient requirements from their Reports tab.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _clientRequirements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final req = _clientRequirements[index];
                    final description = req['description'] as String? ?? '';
                    final amount = req['amount'];
                    final status = req['status'] as String? ?? 'Pending';
                    final addedBy = req['added_by_name'] as String? ?? 'Unknown';
                    final addedDate = req['added_date'] as String? ?? '';
                    final formattedDate = addedDate.length >= 10
                        ? addedDate.substring(0, 10)
                        : addedDate;

                    final amountDouble = amount is num
                        ? amount.toDouble()
                        : double.tryParse(amount?.toString() ?? '0') ?? 0.0;

                    Color statusColor;
                    switch (status.toLowerCase()) {
                      case 'approved':
                        statusColor = Colors.green;
                        break;
                      case 'rejected':
                        statusColor = Colors.red;
                        break;
                      default:
                        statusColor = Colors.orange;
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1A1A2E).withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: statusColor.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A2E),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '₹${amountDouble >= 100000 ? '${(amountDouble / 100000).toStringAsFixed(2)} L' : amountDouble >= 1000 ? '${(amountDouble / 1000).toStringAsFixed(1)} K' : amountDouble.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              description,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF1A1A2E),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.person_outline,
                                    size: 14, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  addedBy,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade600),
                                ),
                                const SizedBox(width: 16),
                                Icon(Icons.calendar_today_outlined,
                                    size: 14, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  formattedDate,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
  
  void _showAddCostDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Cost'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2, color: Colors.brown),
              title: const Text('Add Material Cost'),
              subtitle: const Text('Add material purchase cost'),
              onTap: () {
                Navigator.pop(context);
                _showAddMaterialCostDialog();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.attach_money, color: Colors.purple),
              title: const Text('Add Other Cost'),
              subtitle: const Text('Add transport, services, etc.'),
              onTap: () {
                Navigator.pop(context);
                _showAddOtherCostDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
  
  void _showAddMaterialCostDialog() async {
    try {
      // Show loading dialog first
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Load materials from backend
      final materials = await _budgetService.getMaterials();
      
      // Close loading dialog
      if (context.mounted) {
        Navigator.pop(context);
      }
      
      if (!context.mounted) return;
      
      String? selectedMaterial = 'Other';
      final customMaterialController = TextEditingController();
      final quantityController = TextEditingController();
      String selectedUnit = 'bags';
      final unitCostController = TextEditingController();
      final totalCostController = TextEditingController();
      final notesController = TextEditingController();
      DateTime selectedDate = DateTime.now();
      bool showCustomInput = true; // Start with custom input shown since "Other" is default

      void calculateTotal() {
        final qty = double.tryParse(quantityController.text) ?? 0;
        final cost = double.tryParse(unitCostController.text) ?? 0;
        totalCostController.text = (qty * cost).toStringAsFixed(2);
      }

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Add Material Cost'),
            content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Material Type Dropdown
                DropdownButtonFormField<String>(
                  value: selectedMaterial,
                  decoration: const InputDecoration(
                    labelText: 'Material Type *',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'Other', child: Text('Other (Custom)')),
                    ...materials.map((material) => DropdownMenuItem(
                      value: material['name'],
                      child: Text(material['name']),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedMaterial = value;
                      showCustomInput = value == 'Other';
                      if (value != 'Other') {
                        customMaterialController.clear();
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Custom Material Input (shown only when "Other" is selected)
                if (showCustomInput)
                  TextField(
                    controller: customMaterialController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Material Name *',
                      hintText: 'e.g., Cement, Steel, Bricks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (showCustomInput) const SizedBox(height: 12),
                TextField(
                  controller: quantityController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => calculateTotal()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unit *',
                    border: OutlineInputBorder(),
                  ),
                  items: ['bags', 'tons', 'cubic meters', 'pieces', 'kg', 'liters', 'sq ft', 'sq meters']
                      .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                      .toList(),
                  onChanged: (value) => setState(() => selectedUnit = value ?? 'bags'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitCostController,
                  decoration: const InputDecoration(
                    labelText: 'Unit Cost *',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => calculateTotal()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: totalCostController,
                  decoration: const InputDecoration(
                    labelText: 'Total Cost',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                  trailing: const Icon(Icons.calendar_today),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Determine final material type
                String finalMaterialType;
                if (selectedMaterial == 'Other') {
                  if (customMaterialController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter custom material name')),
                    );
                    return;
                  }
                  finalMaterialType = customMaterialController.text;
                } else {
                  finalMaterialType = selectedMaterial ?? '';
                }
                
                if (finalMaterialType.isEmpty ||
                    quantityController.text.isEmpty ||
                    unitCostController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required fields')),
                  );
                  return;
                }

                final result = await _budgetService.addMaterialCost(
                  siteId: widget.siteId,
                  materialType: finalMaterialType,
                  quantity: double.parse(quantityController.text),
                  unit: selectedUnit,
                  unitCost: double.parse(unitCostController.text),
                  totalCost: double.parse(totalCostController.text),
                  entryDate: '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  notes: notesController.text.isEmpty ? null : notesController.text,
                );

                if (context.mounted) {
                  Navigator.pop(context);
                  if (result['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result['message'] ?? 'Material cost added')),
                    );
                    _loadUtilization(forceRefresh: true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result['error'] ?? 'Failed to add material cost')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A2E)),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    } catch (e) {
      // Close loading dialog if it's still open
      if (context.mounted) {
        Navigator.pop(context);
      }
      print('❌ Error in material dialog: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading materials: $e')),
        );
      }
    }
  }
  
  void _showAddOtherCostDialog() {
    String selectedCostType = 'Transport';
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Other Cost'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedCostType,
                  decoration: const InputDecoration(
                    labelText: 'Cost Type *',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Transport', 'Equipment Rental', 'Services', 'Utilities', 'Miscellaneous', 'Other']
                      .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (value) => setState(() => selectedCostType = value ?? 'Transport'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Brief description of the cost',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount *',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                  trailing: const Icon(Icons.calendar_today),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (amountController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter amount')),
                  );
                  return;
                }

                final result = await _budgetService.addOtherCost(
                  siteId: widget.siteId,
                  costType: selectedCostType,
                  description: descriptionController.text.isEmpty ? null : descriptionController.text,
                  amount: double.parse(amountController.text),
                  entryDate: '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  notes: notesController.text.isEmpty ? null : notesController.text,
                );

                if (context.mounted) {
                  Navigator.pop(context);
                  if (result['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result['message'] ?? 'Other cost added')),
                    );
                    _loadUtilization(forceRefresh: true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result['error'] ?? 'Failed to add other cost')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A2E)),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallCard(String title, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'ACTIVE':
        return Colors.green;
      case 'EXCEEDED':
        return Colors.red;
      case 'COMPLETED':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _showAllocateBudgetDialog() {
    final totalController = TextEditingController(
      text: _budgetAllocation?['total_budget']?.toString() ?? '',
    );
    final clientBalanceController = TextEditingController(
      text: (_phasePayments?['client_balance'] ?? _budgetAllocation?['total_budget'])?.toString() ?? '',
    );
    final notesController = TextEditingController(
      text: _budgetAllocation?['notes']?.toString() ?? '',
    );
    bool isSubmitting = false; // Track submission state

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(_budgetAllocation == null ? 'Allocate Budget' : 'Update Budget'),
          content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: totalController,
                decoration: const InputDecoration(
                  labelText: 'Total Budget *',
                  prefixText: '₹ ',
                  hintText: 'Enter total project budget',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: clientBalanceController,
                decoration: const InputDecoration(
                  labelText: 'Client Balance *',
                  prefixText: '₹ ',
                  hintText: 'Enter current client balance',
                  border: OutlineInputBorder(),
                  helperText: 'Amount remaining from client',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Add any notes about this budget',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: isSubmitting ? null : () async {
              // Disable button immediately
              setState(() => isSubmitting = true);
              
              final total = double.tryParse(totalController.text);
              final clientBalance = double.tryParse(clientBalanceController.text);
              
              if (total == null || total <= 0) {
                setState(() => isSubmitting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter valid total budget')),
                );
                return;
              }
              
              if (clientBalance == null || clientBalance < 0) {
                setState(() => isSubmitting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter valid client balance')),
                );
                return;
              }
              
              if (clientBalance > total) {
                setState(() => isSubmitting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Client balance cannot exceed total budget')),
                );
                return;
              }

              // Close dialog immediately
              if (context.mounted) {
                Navigator.pop(context);
              }

              // Optimistically update UI immediately (before API call)
              if (mounted) {
                setState(() {
                  if (_budgetAllocation != null) {
                    _budgetAllocation!['total_budget'] = total;
                  }
                  if (_phasePayments != null) {
                    _phasePayments!['client_balance'] = clientBalance;
                  }
                });
              }

              // Show brief loading message (500ms)
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Updating...'),
                    duration: Duration(milliseconds: 500),
                  ),
                );
              }

              // Call API in background with 2-second timeout
              try {
                final result = await _budgetService.allocateBudget(
                  siteId: widget.siteId,
                  totalBudget: total,
                  clientBalance: clientBalance,
                  notes: notesController.text.isEmpty ? null : notesController.text,
                ).timeout(
                  const Duration(seconds: 2),
                  onTimeout: () {
                    print('⚠️ [BUDGET] API timeout after 2s, optimistic update shown');
                    // Return success on timeout - optimistic update already shown
                    return {'message': 'Update queued'};
                  },
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  
                  if (result != null) {
                    // Success - refresh in background to sync with server
                    _loadBudgetAllocation(forceRefresh: true);
                    _loadPhasePayments(forceRefresh: true);
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✓ Budget updated'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  } else {
                    // Failed - revert optimistic update
                    _loadBudgetAllocation(forceRefresh: true);
                    _loadPhasePayments(forceRefresh: true);
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Update failed, please try again'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                }
              } catch (e) {
                print('❌ [BUDGET] Error: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Network error, please check connection'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  // Revert optimistic update
                  _loadBudgetAllocation(forceRefresh: true);
                  _loadPhasePayments(forceRefresh: true);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A2E)),
            child: isSubmitting 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
}

// Separate widget for photo tabs with its own TabController
class PhotoTabsSection extends StatefulWidget {
  final String siteId;

  const PhotoTabsSection({super.key, required this.siteId});

  @override
  State<PhotoTabsSection> createState() => _PhotoTabsSectionState();
}

class _PhotoTabsSectionState extends State<PhotoTabsSection>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _constructionService = ConstructionService();
  
  List<Map<String, dynamic>> _supervisorPhotos = [];
  List<Map<String, dynamic>> _engineerPhotos = [];
  bool _isLoadingSupervisor = false;
  bool _isLoadingEngineer = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPhotos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _isLoadingSupervisor = true;
      _isLoadingEngineer = true;
    });

    // Load supervisor photos (from site_photos table via supervisor-photos-for-accountant)
    // and site engineer photos (from work_updates table via accountant/all-photos)
    final supervisorResult = await _constructionService.getSupervisorPhotosForAccountant(
      siteId: widget.siteId,
    );
    final engineerResult = await _constructionService.getAccountantPhotos(
      siteId: widget.siteId,
    );

    if (mounted) {
      setState(() {
        // Supervisor photos from site_photos table
        _supervisorPhotos = List<Map<String, dynamic>>.from(
          supervisorResult['photos'] ?? [],
        );

        // Site engineer photos from work_updates table
        final allEngineerPhotos = List<Map<String, dynamic>>.from(
          engineerResult['photos'] ?? [],
        );
        _engineerPhotos = allEngineerPhotos.where((photo) {
          final role = (photo['uploaded_by_role'] as String? ?? '').toLowerCase();
          return role == 'site engineer' || role == 'siteengineer';
        }).toList();

        _isLoadingSupervisor = false;
        _isLoadingEngineer = false;
      });

      print('📸 Loaded ${_supervisorPhotos.length} supervisor photos');
      print('📸 Loaded ${_engineerPhotos.length} engineer photos');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.grey[100],
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1A1A2E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF1A1A2E),
            indicatorWeight: 3,
            tabs: [
              Tab(
                icon: const Icon(Icons.photo_camera, size: 20),
                text: 'Supervisor Photos (${_supervisorPhotos.length})',
              ),
              Tab(
                icon: const Icon(Icons.engineering, size: 20),
                text: 'Site Engineer Photos (${_engineerPhotos.length})',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSupervisorPhotosTab(),
              _buildSiteEngineerPhotosTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSupervisorPhotosTab() {
    if (_isLoadingSupervisor) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_supervisorPhotos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No supervisor photos yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _supervisorPhotos.length,
        itemBuilder: (context, index) {
          final photo = _supervisorPhotos[index];
          return _buildPhotoCard(photo, isSupervisor: true);
        },
      ),
    );
  }

  Widget _buildSiteEngineerPhotosTab() {
    if (_isLoadingEngineer) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_engineerPhotos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.engineering_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No site engineer photos yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _engineerPhotos.length,
        itemBuilder: (context, index) {
          final photo = _engineerPhotos[index];
          return _buildPhotoCard(photo, isSupervisor: false);
        },
      ),
    );
  }

  Widget _buildPhotoCard(Map<String, dynamic> photo, {required bool isSupervisor}) {
    final rawUrl = photo['image_url'] as String? ?? '';
    // Build full URL — relative paths need the VPS base URL prepended
    final imageUrl = rawUrl.startsWith('http')
        ? rawUrl
        : rawUrl.isNotEmpty
            ? 'http://187.127.164.22$rawUrl'
            : '';
    final uploadDate = photo['upload_date'] ?? photo['update_date'] ?? '';
    final timeOfDay = photo['time_of_day'] ?? '';
    final updateType = photo['update_type'] ?? '';
    final description = photo['description'] ?? '';
    final uploadedBy = isSupervisor 
        ? (photo['supervisor_name'] ?? photo['uploaded_by'] ?? 'Unknown')
        : (photo['uploaded_by'] ?? 'Unknown');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _openPhotoViewer(imageUrl, photo),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey[300],
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey[300],
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
              ),
              const SizedBox(width: 12),
              // Photo details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Update type or time of day
                    if (updateType.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getUpdateTypeColor(updateType),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          updateType,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else if (timeOfDay.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: timeOfDay == 'MORNING' ? Colors.orange : Colors.indigo,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          timeOfDay,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    // Uploaded by
                    Text(
                      'Uploaded by $uploadedBy',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Date
                    Text(
                      uploadDate,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    // Description
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Open icon
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: () => _openPhotoViewer(imageUrl, photo),
                color: const Color(0xFF1A1A2E),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getUpdateTypeColor(String updateType) {
    switch (updateType.toUpperCase()) {
      case 'STARTED':
        return Colors.green;
      case 'FINISHED':
        return Colors.blue;
      case 'PROGRESS':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _openPhotoViewer(String imageUrl, Map<String, dynamic> photo) {
    if (imageUrl.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, size: 80, color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ── Admin Document Tab ─────────────────────────────────────────────────────
class _AdminDocumentTab extends StatefulWidget {
  final String siteId;
  const _AdminDocumentTab({required this.siteId});

  @override
  State<_AdminDocumentTab> createState() => _AdminDocumentTabState();
}

class _AdminDocumentTabState extends State<_AdminDocumentTab> {
  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      // Use the all-documents endpoint which combines architect + site engineer docs
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/construction/all-documents/?site_id=${widget.siteId}&role=all'),
        headers: {'Authorization': 'Bearer ${token ?? ''}'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Combine architect and site engineer documents
        final archDocs = List<Map<String, dynamic>>.from(data['architect_documents'] ?? []);
        final engDocs = List<Map<String, dynamic>>.from(data['site_engineer_documents'] ?? []);
        final all = [...archDocs, ...engDocs];
        // Sort by upload date descending
        all.sort((a, b) {
          final da = a['upload_date'] as String? ?? '';
          final db = b['upload_date'] as String? ?? '';
          return db.compareTo(da);
        });
        setState(() {
          _documents = all;
          _isLoading = false;
        });
      } else {
        setState(() { _error = 'Failed to load documents'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _openDocument(String fileUrl) async {
    final url = fileUrl.startsWith('http')
        ? fileUrl
        : 'http://187.127.164.22$fileUrl';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
              onPressed: _loadDocuments,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No documents uploaded yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Text('Documents uploaded by site engineers\nwill appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadDocuments,
      color: const Color(0xFF1A1A2E),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _documents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final doc = _documents[index];
          final title = doc['title'] as String? ?? doc['document_type'] as String? ?? 'Document';
          final docType = doc['document_type'] as String? ?? '';
          final uploadedBy = doc['uploaded_by'] as String? ?? doc['engineer_name'] as String? ?? doc['architect_name'] as String? ?? 'Unknown';
          final role = doc['role'] as String? ?? '';
          final uploadDate = (doc['upload_date'] as String? ?? doc['uploaded_at'] as String? ?? '');
          final dateStr = uploadDate.length >= 10 ? uploadDate.substring(0, 10) : uploadDate;
          final fileUrl = doc['file_url'] as String? ?? '';

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A1A2E).withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.insert_drive_file,
                        color: Color(0xFF1A1A2E), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A2E))),
                        if (docType.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(docType,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(uploadedBy,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                            const SizedBox(width: 12),
                            Icon(Icons.calendar_today_outlined,
                                size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(dateStr,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (fileUrl.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.open_in_new,
                          color: Color(0xFF1A1A2E), size: 22),
                      onPressed: () => _openDocument(fileUrl),
                      tooltip: 'Open document',
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// Admin Bills Tab  – Material Bills / Vendor Bills / Agreements
// ============================================================

class _AdminBillsTab extends StatefulWidget {
  final String siteId;
  final String siteName;
  const _AdminBillsTab({required this.siteId, required this.siteName});

  @override
  State<_AdminBillsTab> createState() => _AdminBillsTabState();
}

class _AdminBillsTabState extends State<_AdminBillsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _billsService = AccountantBillsService();

  List<Map<String, dynamic>> _materialBills = [];
  List<Map<String, dynamic>> _vendorBills = [];
  List<Map<String, dynamic>> _agreements = [];

  bool _isLoadingMaterial = false;
  bool _isLoadingVendor = false;
  bool _isLoadingAgreements = false;

  static const _navy = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadAll() {
    _loadMaterialBills();
    _loadVendorBills();
    _loadAgreements();
  }

  Future<void> _loadMaterialBills() async {
    setState(() => _isLoadingMaterial = true);
    final result = await _billsService.getMaterialBills(siteId: widget.siteId);
    if (mounted) {
      setState(() {
        if (result['success'] == true) _materialBills = List<Map<String, dynamic>>.from(result['bills'] ?? []);
        _isLoadingMaterial = false;
      });
    }
  }

  Future<void> _loadVendorBills() async {
    setState(() => _isLoadingVendor = true);
    final result = await _billsService.getVendorBills(siteId: widget.siteId);
    if (mounted) {
      setState(() {
        if (result['success'] == true) _vendorBills = List<Map<String, dynamic>>.from(result['bills'] ?? []);
        _isLoadingVendor = false;
      });
    }
  }

  Future<void> _loadAgreements() async {
    setState(() => _isLoadingAgreements = true);
    final result = await _billsService.getSiteAgreements(siteId: widget.siteId);
    if (mounted) {
      setState(() {
        if (result['success'] == true) _agreements = List<Map<String, dynamic>>.from(result['agreements'] ?? []);
        _isLoadingAgreements = false;
      });
    }
  }

  Future<void> _openDocument(String? fileUrl) async {
    if (fileUrl == null || fileUrl.isEmpty) return;
    final url = fileUrl.startsWith('http') ? fileUrl : 'http://187.127.164.22$fileUrl';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open document')),
      );
    }
  }

  void _showUploadDialog() {
    final tab = _tabController.index;
    if (tab == 0) {
      _showMaterialBillDialog();
    } else if (tab == 1) {
      _showVendorBillDialog();
    } else {
      _showAgreementDialog();
    }
  }

  void _showMaterialBillDialog() {
    showDialog(
      context: context,
      builder: (_) => _MaterialBillDialog(
        siteId: widget.siteId,
        siteName: widget.siteName,
        billsService: _billsService,
        onSuccess: _loadMaterialBills,
      ),
    );
  }

  void _showVendorBillDialog() {
    showDialog(
      context: context,
      builder: (_) => _VendorBillDialog(
        siteId: widget.siteId,
        siteName: widget.siteName,
        billsService: _billsService,
        onSuccess: _loadVendorBills,
      ),
    );
  }

  void _showAgreementDialog() {
    showDialog(
      context: context,
      builder: (_) => _AgreementDialog(
        siteId: widget.siteId,
        siteName: widget.siteName,
        billsService: _billsService,
        onSuccess: _loadAgreements,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Container(
            color: _navy.withValues(alpha: 0.05),
            child: TabBar(
              controller: _tabController,
              labelColor: _navy,
              unselectedLabelColor: Colors.grey,
              indicatorColor: _navy,
              indicatorWeight: 3,
              tabs: [
                Tab(text: 'Material Bills (${_materialBills.length})'),
                Tab(text: 'Vendor Bills (${_vendorBills.length})'),
                Tab(text: 'Agreements (${_agreements.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMaterialBillsList(),
                _buildVendorBillsList(),
                _buildAgreementsList(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showUploadDialog,
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload'),
      ),
    );
  }

  Widget _buildMaterialBillsList() {
    if (_isLoadingMaterial) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }
    if (_materialBills.isEmpty) {
      return _emptyState(
        icon: Icons.receipt_long,
        title: 'No Material Bills',
        subtitle: 'Tap Upload to add a material bill',
        onTap: _showMaterialBillDialog,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMaterialBills,
      color: _navy,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _materialBills.length,
        itemBuilder: (_, i) => _MaterialBillCard(
          bill: _materialBills[i],
          onOpen: () => _openDocument(_materialBills[i]['file_url'] as String?),
        ),
      ),
    );
  }

  Widget _buildVendorBillsList() {
    if (_isLoadingVendor) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }
    if (_vendorBills.isEmpty) {
      return _emptyState(
        icon: Icons.business_center,
        title: 'No Vendor Bills',
        subtitle: 'Tap Upload to add a vendor bill',
        onTap: _showVendorBillDialog,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadVendorBills,
      color: _navy,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vendorBills.length,
        itemBuilder: (_, i) => _VendorBillCard(
          bill: _vendorBills[i],
          onOpen: () => _openDocument(_vendorBills[i]['file_url'] as String?),
        ),
      ),
    );
  }

  Widget _buildAgreementsList() {
    if (_isLoadingAgreements) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }
    if (_agreements.isEmpty) {
      return _emptyState(
        icon: Icons.description,
        title: 'No Agreements',
        subtitle: 'Tap Upload to add an agreement',
        onTap: _showAgreementDialog,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAgreements,
      color: _navy,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _agreements.length,
        itemBuilder: (_, i) => _AgreementCard(
          agreement: _agreements[i],
          onOpen: () => _openDocument(_agreements[i]['file_url'] as String?),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _navy)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bill / Agreement card widgets ─────────────────────────────

class _MaterialBillCard extends StatelessWidget {
  final Map<String, dynamic> bill;
  final VoidCallback onOpen;
  const _MaterialBillCard({required this.bill, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1A1A2E);
    final status = bill['payment_status'] as String? ?? 'PENDING';
    final statusColor = status == 'PAID'
        ? Colors.green
        : status == 'PARTIAL'
            ? Colors.orange
            : Colors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: navy.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.receipt_long, color: navy, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bill['vendor_name'] as String? ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: navy)),
                    const SizedBox(height: 2),
                    Text(
                      '${bill['material_type'] ?? ''} • Bill #${bill['bill_number'] ?? ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${(bill['final_amount'] ?? 0).toStringAsFixed(2)}  •  ${(bill['bill_date'] as String? ?? '').substring(0, 10 < (bill['bill_date'] as String? ?? '').length ? 10 : (bill['bill_date'] as String? ?? '').length)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: navy),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(status,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor)),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.open_in_new, size: 18, color: navy),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VendorBillCard extends StatelessWidget {
  final Map<String, dynamic> bill;
  final VoidCallback onOpen;
  const _VendorBillCard({required this.bill, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1A1A2E);
    final status = bill['payment_status'] as String? ?? 'PENDING';
    final statusColor = status == 'PAID'
        ? Colors.green
        : status == 'PARTIAL'
            ? Colors.orange
            : Colors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: navy.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.business_center, color: navy, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bill['vendor_name'] as String? ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: navy)),
                    const SizedBox(height: 2),
                    Text(
                      '${bill['service_type'] ?? ''} • Bill #${bill['bill_number'] ?? ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${(bill['final_amount'] ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: navy),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(status,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor)),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.open_in_new, size: 18, color: navy),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementCard extends StatelessWidget {
  final Map<String, dynamic> agreement;
  final VoidCallback onOpen;
  const _AgreementCard({required this.agreement, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1A1A2E);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: navy.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.description, color: navy, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agreement['title'] as String? ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: navy)),
                    const SizedBox(height: 2),
                    Text(
                      '${agreement['agreement_type'] ?? ''} • ${agreement['party_name'] ?? ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    if ((agreement['contract_value'] as num?) != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '₹${(agreement['contract_value'] as num).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: navy),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 18, color: navy),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Upload dialogs ────────────────────────────────────────────

class _MaterialBillDialog extends StatefulWidget {
  final String siteId;
  final String siteName;
  final AccountantBillsService billsService;
  final VoidCallback onSuccess;
  const _MaterialBillDialog({
    required this.siteId,
    required this.siteName,
    required this.billsService,
    required this.onSuccess,
  });

  @override
  State<_MaterialBillDialog> createState() => _MaterialBillDialogState();
}

class _MaterialBillDialogState extends State<_MaterialBillDialog> {
  final _billNumberCtrl = TextEditingController();
  final _vendorNameCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _unitPriceCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  String _vendorType = 'Tiles Shop';
  String _materialType = 'Tiles';
  String _unit = 'sqft';
  String _paymentStatus = 'PENDING';
  String? _paymentMode;
  DateTime _billDate = DateTime.now();
  DateTime? _paymentDate;
  File? _selectedFile;
  bool _isUploading = false;

  static const _navy = Color(0xFF1A1A2E);

  final _vendorTypes = ['Tiles Shop', 'Cement Supplier', 'Steel Supplier', 'Hardware Store', 'Paint Shop', 'Electrical Shop', 'Plumbing Shop', 'Other'];
  final _materialTypes = ['Tiles', 'Cement', 'Steel', 'Sand', 'Bricks', 'Paint', 'Electrical', 'Plumbing', 'Other'];
  final _units = ['nos', 'bags', 'kg', 'tons', 'sqft', 'boxes', 'pieces'];
  final _paymentStatuses = ['PENDING', 'PARTIAL', 'PAID'];
  final _paymentModes = ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Credit'];

  @override
  void dispose() {
    _billNumberCtrl.dispose();
    _vendorNameCtrl.dispose();
    _quantityCtrl.dispose();
    _unitPriceCtrl.dispose();
    _taxCtrl.dispose();
    _discountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _totalAmount {
    final qty = double.tryParse(_quantityCtrl.text) ?? 0;
    final price = double.tryParse(_unitPriceCtrl.text) ?? 0;
    return qty * price;
  }

  double get _finalAmount =>
      _totalAmount + (double.tryParse(_taxCtrl.text) ?? 0) - (double.tryParse(_discountCtrl.text) ?? 0);

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      setState(() => _selectedFile = File(result.files.single.path!));
    }
  }

  Future<void> _upload() async {
    if (_billNumberCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter bill number')));
      return;
    }
    if (_vendorNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter vendor name')));
      return;
    }
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a PDF file')));
      return;
    }
    setState(() => _isUploading = true);
    final result = await widget.billsService.uploadMaterialBill(
      siteId: widget.siteId,
      billNumber: _billNumberCtrl.text.trim(),
      billDate: DateFormat('yyyy-MM-dd').format(_billDate),
      vendorName: _vendorNameCtrl.text.trim(),
      vendorType: _vendorType,
      materialType: _materialType,
      quantity: double.tryParse(_quantityCtrl.text) ?? 0,
      unit: _unit,
      unitPrice: double.tryParse(_unitPriceCtrl.text) ?? 0,
      totalAmount: _totalAmount,
      taxAmount: double.tryParse(_taxCtrl.text) ?? 0,
      discountAmount: double.tryParse(_discountCtrl.text) ?? 0,
      finalAmount: _finalAmount,
      paymentStatus: _paymentStatus,
      paymentMode: _paymentMode,
      paymentDate: _paymentDate != null ? DateFormat('yyyy-MM-dd').format(_paymentDate!) : null,
      notes: _notesCtrl.text,
      file: _selectedFile!,
    );
    if (mounted) {
      setState(() => _isUploading = false);
      if (result['success'] == true) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Material bill uploaded successfully'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Upload failed'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Upload Material Bill',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
              Text(widget.siteName,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 20),
              TextField(
                controller: _billNumberCtrl,
                decoration: const InputDecoration(
                    labelText: 'Bill Number *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.numbers)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vendorNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Vendor Name *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.store)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _dropdown('Vendor Type', _vendorTypes, _vendorType, (v) => setState(() => _vendorType = v!))),
                const SizedBox(width: 12),
                Expanded(child: _dropdown('Material Type', _materialTypes, _materialType, (v) => setState(() => _materialType = v!))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _quantityCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Qty', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _dropdown('Unit', _units, _unit, (v) => setState(() => _unit = v!))),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _unitPriceCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Unit Price', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _taxCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Tax ₹', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _discountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Discount ₹', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Final: ₹${_finalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 14)),
              const SizedBox(height: 12),
              _dropdown('Payment Status', _paymentStatuses, _paymentStatus, (v) => setState(() => _paymentStatus = v!)),
              const SizedBox(height: 12),
              _dropdown('Payment Mode (optional)', _paymentModes, _paymentMode ?? _paymentModes.first,
                  (v) => setState(() => _paymentMode = v)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(_selectedFile != null
                    ? _selectedFile!.path.split(Platform.pathSeparator).last
                    : 'Select PDF File *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isUploading ? null : _upload,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _navy, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                child: _isUploading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Upload Bill'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, List<String> items, String value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}

// ── Vendor Bill Dialog ────────────────────────────────────────

class _VendorBillDialog extends StatefulWidget {
  final String siteId;
  final String siteName;
  final AccountantBillsService billsService;
  final VoidCallback onSuccess;
  const _VendorBillDialog({
    required this.siteId,
    required this.siteName,
    required this.billsService,
    required this.onSuccess,
  });

  @override
  State<_VendorBillDialog> createState() => _VendorBillDialogState();
}

class _VendorBillDialogState extends State<_VendorBillDialog> {
  final _billNumberCtrl = TextEditingController();
  final _vendorNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');
  final _serviceDescCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _vendorType = 'Contractor';
  String _serviceType = 'Labour';
  String _paymentStatus = 'PENDING';
  String? _paymentMode;
  DateTime _billDate = DateTime.now();
  File? _selectedFile;
  bool _isUploading = false;

  static const _navy = Color(0xFF1A1A2E);

  final _vendorTypes = ['Contractor', 'Sub-contractor', 'Equipment Supplier', 'Transport', 'Other'];
  final _serviceTypes = ['Labour', 'Equipment Rental', 'Transport', 'Consultation', 'Other'];
  final _paymentStatuses = ['PENDING', 'PARTIAL', 'PAID'];
  final _paymentModes = ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Credit'];

  @override
  void dispose() {
    _billNumberCtrl.dispose();
    _vendorNameCtrl.dispose();
    _amountCtrl.dispose();
    _taxCtrl.dispose();
    _discountCtrl.dispose();
    _serviceDescCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _finalAmount =>
      (double.tryParse(_amountCtrl.text) ?? 0) +
      (double.tryParse(_taxCtrl.text) ?? 0) -
      (double.tryParse(_discountCtrl.text) ?? 0);

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      setState(() => _selectedFile = File(result.files.single.path!));
    }
  }

  Future<void> _upload() async {
    if (_billNumberCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter bill number')));
      return;
    }
    if (_vendorNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter vendor name')));
      return;
    }
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a PDF file')));
      return;
    }
    setState(() => _isUploading = true);
    final result = await widget.billsService.uploadVendorBill(
      siteId: widget.siteId,
      billNumber: _billNumberCtrl.text.trim(),
      billDate: DateFormat('yyyy-MM-dd').format(_billDate),
      vendorName: _vendorNameCtrl.text.trim(),
      vendorType: _vendorType,
      serviceType: _serviceType,
      serviceDescription: _serviceDescCtrl.text,
      amount: double.tryParse(_amountCtrl.text) ?? 0,
      taxAmount: double.tryParse(_taxCtrl.text) ?? 0,
      discountAmount: double.tryParse(_discountCtrl.text) ?? 0,
      finalAmount: _finalAmount,
      paymentStatus: _paymentStatus,
      paymentMode: _paymentMode,
      notes: _notesCtrl.text,
      file: _selectedFile!,
    );
    if (mounted) {
      setState(() => _isUploading = false);
      if (result['success'] == true) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vendor bill uploaded successfully'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Upload failed'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxHeight: 600),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Upload Vendor Bill',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
              Text(widget.siteName, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 20),
              TextField(
                controller: _billNumberCtrl,
                decoration: const InputDecoration(
                    labelText: 'Bill Number *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.numbers)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vendorNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Vendor Name *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _dropdown('Vendor Type', _vendorTypes, _vendorType, (v) => setState(() => _vendorType = v!))),
                const SizedBox(width: 12),
                Expanded(child: _dropdown('Service Type', _serviceTypes, _serviceType, (v) => setState(() => _serviceType = v!))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _serviceDescCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Service Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Amount ₹ *', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _taxCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Tax ₹', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _discountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Discount ₹', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Final: ₹${_finalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 14)),
              const SizedBox(height: 12),
              _dropdown('Payment Status', _paymentStatuses, _paymentStatus, (v) => setState(() => _paymentStatus = v!)),
              const SizedBox(height: 12),
              _dropdown('Payment Mode (optional)', _paymentModes, _paymentMode ?? _paymentModes.first,
                  (v) => setState(() => _paymentMode = v)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(_selectedFile != null
                    ? _selectedFile!.path.split(Platform.pathSeparator).last
                    : 'Select PDF File *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isUploading ? null : _upload,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _navy, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                child: _isUploading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Upload Bill'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, List<String> items, String value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}

// ── Agreement Dialog ──────────────────────────────────────────

class _AgreementDialog extends StatefulWidget {
  final String siteId;
  final String siteName;
  final AccountantBillsService billsService;
  final VoidCallback onSuccess;
  const _AgreementDialog({
    required this.siteId,
    required this.siteName,
    required this.billsService,
    required this.onSuccess,
  });

  @override
  State<_AgreementDialog> createState() => _AgreementDialogState();
}

class _AgreementDialogState extends State<_AgreementDialog> {
  final _titleCtrl = TextEditingController();
  final _agreementNumberCtrl = TextEditingController();
  final _partyNameCtrl = TextEditingController();
  final _contractValueCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _agreementType = 'Construction';
  String _partyType = 'Contractor';
  DateTime _agreementDate = DateTime.now();
  File? _selectedFile;
  bool _isUploading = false;

  static const _navy = Color(0xFF1A1A2E);

  final _agreementTypes = ['Construction', 'Labour', 'Material Supply', 'Equipment Rental', 'Consultation', 'Other'];
  final _partyTypes = ['Contractor', 'Sub-contractor', 'Supplier', 'Consultant', 'Client', 'Other'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _agreementNumberCtrl.dispose();
    _partyNameCtrl.dispose();
    _contractValueCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      setState(() => _selectedFile = File(result.files.single.path!));
    }
  }

  Future<void> _upload() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter agreement title')));
      return;
    }
    if (_partyNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter party name')));
      return;
    }
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a PDF file')));
      return;
    }
    setState(() => _isUploading = true);
    final result = await widget.billsService.uploadSiteAgreement(
      siteId: widget.siteId,
      agreementType: _agreementType,
      agreementNumber: _agreementNumberCtrl.text.trim().isEmpty ? null : _agreementNumberCtrl.text.trim(),
      agreementDate: DateFormat('yyyy-MM-dd').format(_agreementDate),
      partyName: _partyNameCtrl.text.trim(),
      partyType: _partyType,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text,
      contractValue: double.tryParse(_contractValueCtrl.text),
      notes: _notesCtrl.text,
      file: _selectedFile!,
    );
    if (mounted) {
      setState(() => _isUploading = false);
      if (result['success'] == true) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agreement uploaded successfully'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Upload failed'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxHeight: 600),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Upload Agreement',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
              Text(widget.siteName, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 20),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Agreement Title *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.title)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _agreementNumberCtrl,
                decoration: const InputDecoration(
                    labelText: 'Agreement Number (optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.numbers)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _dropdown('Agreement Type', _agreementTypes, _agreementType, (v) => setState(() => _agreementType = v!))),
                const SizedBox(width: 12),
                Expanded(child: _dropdown('Party Type', _partyTypes, _partyType, (v) => setState(() => _partyType = v!))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _partyNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Party Name *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contractValueCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Contract Value ₹ (optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.currency_rupee)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(_selectedFile != null
                    ? _selectedFile!.path.split(Platform.pathSeparator).last
                    : 'Select PDF File *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isUploading ? null : _upload,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _navy, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                child: _isUploading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Upload Agreement'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, List<String> items, String value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}
