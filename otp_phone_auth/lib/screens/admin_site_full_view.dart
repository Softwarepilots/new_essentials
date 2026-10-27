import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/export_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:open_filex/open_filex.dart';
import 'admin_budget_management_screen.dart';

class AdminSiteFullView extends StatefulWidget {
  final String siteId;
  final String siteName;

  const AdminSiteFullView({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<AdminSiteFullView> createState() => _AdminSiteFullViewState();
}

class _AdminSiteFullViewState extends State<AdminSiteFullView>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _exportService = ExportService();
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  late TabController _tabController;

  // Dashboard data
  Map<String, dynamic>? _dashboardData;
  bool _isLoadingDashboard = false;

  // Labour data
  List<Map<String, dynamic>> _labourEntries = [];
  bool _isLoadingLabour = false;

  // Material data
  List<Map<String, dynamic>> _materialBalances = [];
  bool _isLoadingMaterial = false;

  // Photos data
  List<Map<String, dynamic>> _photos = [];
  bool _isLoadingPhotos = false;

  // Documents data
  List<Map<String, dynamic>> _documents = [];
  bool _isLoadingDocuments = false;

  // Bills data
  List<Map<String, dynamic>> _bills = [];
  bool _isLoadingBills = false;

  // Expanded dates tracking
  final Set<String> _expandedDates = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _loadTabData(_tabController.index);
      }
    });
    _loadDashboardData();
    _loadLabourEntries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadTabData(int index) {
    switch (index) {
      case 0: // Dashboard
        _loadDashboardData();
        break;
      case 1: // Budget
        // Budget screen handles its own loading
        break;
      case 2: // Labour
        _loadLabourEntries();
        break;
      case 3: // Material
        _loadMaterialBalances();
        break;
      case 4: // Bills
        _loadBills();
        break;
      case 5: // Photos
        _loadPhotos();
        break;
      case 6: // Documents
        _loadDocuments();
        break;
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoadingDashboard = true);

    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/admin/sites/${widget.siteId}/dashboard/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => _dashboardData = data);
      }
    } catch (e) {
      print('Error loading dashboard: $e');
    } finally {
      setState(() => _isLoadingDashboard = false);
    }
  }

  Future<void> _loadLabourEntries() async {
    setState(() => _isLoadingLabour = true);

    try {
      final token = await _authService.getToken();
      // Use accountant endpoint to see modified/verified data
      final response = await http.get(
        Uri.parse('$baseUrl/construction/accountant/all-entries/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      print('Labour API Status: ${response.statusCode}');
      print('Labour API Body length: ${response.body.length}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);

          // The API returns 'labour_entries', not 'entries'
          if (data.containsKey('labour_entries')) {
            final allEntries = List<Map<String, dynamic>>.from(
              data['labour_entries'] ?? [],
            );

            // Filter for this site
            final siteIdStr = widget.siteId.toString();
            final filtered = allEntries.where((entry) {
              final entrySiteId = entry['site_id']?.toString() ?? '';
              return entrySiteId == siteIdStr;
            }).toList();

            setState(() {
              _labourEntries = filtered;
            });
          }
        } catch (e) {
          print('ERROR parsing JSON: $e');
        }
      }
    } catch (e) {
      print('Error loading labour: $e');
    } finally {
      setState(() => _isLoadingLabour = false);
    }
  }

  Future<void> _loadMaterialBalances() async {
    setState(() => _isLoadingMaterial = true);

    try {
      final token = await _authService.getToken();

      // Use the accountant all-entries endpoint which returns material_entries
      final response = await http.get(
        Uri.parse('$baseUrl/construction/accountant/all-entries/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // The API returns 'material_entries'
        if (data.containsKey('material_entries')) {
          final allEntries = List<Map<String, dynamic>>.from(
            data['material_entries'] ?? [],
          );

          // Filter for this site
          final siteIdStr = widget.siteId.toString();
          final filtered = allEntries.where((entry) {
            final entrySiteId = entry['site_id']?.toString() ?? '';
            return entrySiteId == siteIdStr;
          }).toList();

          setState(() {
            _materialBalances = filtered;
          });
        }
      }
    } catch (e) {
      print('Error loading materials: $e');
    } finally {
      setState(() => _isLoadingMaterial = false);
    }
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoadingPhotos = true);

    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse(
          '$baseUrl/construction/accountant/all-photos/?site_id=${widget.siteId}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _photos = List<Map<String, dynamic>>.from(data['photos'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading photos: $e');
    } finally {
      setState(() => _isLoadingPhotos = false);
    }
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoadingDocuments = true);

    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse(
          '$baseUrl/construction/all-documents/?site_id=${widget.siteId}&role=all',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Combine both site engineer and architect documents
        final siteEngineerDocs = List<Map<String, dynamic>>.from(
          data['site_engineer_documents'] ?? [],
        );
        final architectDocs = List<Map<String, dynamic>>.from(
          data['architect_documents'] ?? [],
        );

        setState(() {
          _documents = [...siteEngineerDocs, ...architectDocs];
          // Sort by upload date (most recent first)
          _documents.sort((a, b) {
            final dateA = a['uploaded_at'] ?? a['upload_date'] ?? '';
            final dateB = b['uploaded_at'] ?? b['upload_date'] ?? '';
            return dateB.compareTo(dateA);
          });
        });
      }
    } catch (e) {
      print('Error loading documents: $e');
    } finally {
      setState(() => _isLoadingDocuments = false);
    }
  }

  Future<void> _loadBills() async {
    setState(() => _isLoadingBills = true);

    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/admin/sites/${widget.siteId}/bills/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _bills = List<Map<String, dynamic>>.from(data['bills'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading bills: $e');
    } finally {
      setState(() => _isLoadingBills = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.siteName),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          // Export Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Export Reports',
            onSelected: (value) => _handleExport(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'labour',
                child: Row(
                  children: [
                    Icon(Icons.people, size: 20),
                    SizedBox(width: 8),
                    Text('Export Labour Entries'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'material',
                child: Row(
                  children: [
                    Icon(Icons.inventory_2, size: 20),
                    SizedBox(width: 8),
                    Text('Export Material Entries'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'budget',
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet, size: 20),
                    SizedBox(width: 8),
                    Text('Export Budget Utilization'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'bills',
                child: Row(
                  children: [
                    Icon(Icons.receipt_long, size: 20),
                    SizedBox(width: 8),
                    Text('Export Bills'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Budget'),
            Tab(text: 'Labour'),
            Tab(text: 'Material'),
            Tab(text: 'Bills'),
            Tab(text: 'Photos'),
            Tab(text: 'Documents'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(),
          _buildBudgetTab(),
          _buildLabourTab(),
          _buildMaterialTab(),
          _buildBillsTab(),
          _buildPhotosTab(),
          _buildDocumentsTab(),
        ],
      ),
    );
  }

  Future<void> _handleExport(String type) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Downloading file...'),
              ],
            ),
          ),
        ),
      ),
    );

    Map<String, dynamic> result;

    switch (type) {
      case 'labour':
        result = await _exportService.exportLabourEntries(widget.siteId);
        break;
      case 'material':
        result = await _exportService.exportMaterialEntries(widget.siteId);
        break;
      case 'budget':
        result = await _exportService.exportBudgetUtilization(widget.siteId);
        break;
      case 'bills':
        result = await _exportService.exportBills(widget.siteId);
        break;
      default:
        result = {'success': false, 'error': 'Unknown export type'};
    }

    // Close loading dialog
    if (mounted) Navigator.pop(context);

    // Show result
    if (mounted) {
      if (result['success'] == true) {
        final filePath = result['filePath'] as String;
        final filename = result['filename'] as String;
        final fileOpened = result['fileOpened'] as bool? ?? false;
        final fileSize = result['fileSize'] as int? ?? 0;
        final openMessage = result['openMessage'] as String? ?? '';

        // Debug logging
        print('=== EXPORT RESULT ===');
        print('File path: $filePath');
        print('Filename: $filename');
        print('File size: $fileSize bytes');
        print('File opened: $fileOpened');
        print('Open message: $openMessage');

        // Show success dialog with Open button
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text('Download Complete'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileOpened
                      ? 'File opened successfully!'
                      : 'Your file has been downloaded!',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.insert_drive_file,
                            size: 20,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              filename,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.folder,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Downloads folder (${(fileSize / 1024).toStringAsFixed(1)} KB)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        filePath,
                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!fileOpened) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'File could not open automatically',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (openMessage.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Reason: $openMessage',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  fileOpened
                      ? 'You can also find this file in your Downloads folder'
                      : 'Tap "Open File" below or use your file manager to open the file',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  // Try to open the file with explicit MIME type
                  try {
                    print('Manual open attempt for: $filePath');
                    final openResult = await OpenFilex.open(
                      filePath,
                      type:
                          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                    );
                    print(
                      'Manual open result: ${openResult.type}, ${openResult.message}',
                    );

                    if (mounted) {
                      if (openResult.type == ResultType.done) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('File opened successfully!'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      } else if (openResult.type == ResultType.noAppToOpen) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'No app found to open Excel files.\n'
                              'Please install Google Sheets or Microsoft Excel from Play Store.',
                            ),
                            duration: const Duration(seconds: 6),
                            action: SnackBarAction(
                              label: 'OK',
                              onPressed: () {},
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not open file: ${openResult.message}\n'
                              'File location: /storage/emulated/0/Download/$filename',
                            ),
                            duration: const Duration(seconds: 6),
                            action: SnackBarAction(
                              label: 'OK',
                              onPressed: () {},
                            ),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    print('Manual open error: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Error: $e\n'
                            'Please open file manager and navigate to Downloads folder.',
                          ),
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Export failed'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildDashboardTab() {
    if (_isLoadingDashboard) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Budget Allocation Card (NEW)
          if (_dashboardData?['allocated_budget'] != null) ...[
            Card(
              elevation: 3,
              color: Colors.blue.shade50,
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
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Budget Allocation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Budget',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _formatCurrency(
                                _dashboardData?['allocated_budget'],
                              ),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Utilized',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              '${(_dashboardData?['utilization_percentage'] ?? 0).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Budget Card
          _buildDashboardCard(
            'Budget',
            _formatCurrency(_dashboardData?['budget'] ?? 0),
            Icons.account_balance_wallet,
            Colors.blue,
          ),
          const SizedBox(height: 12),

          // Workers Card
          _buildDashboardCard(
            'Total Workers',
            '${_dashboardData?['total_workers'] ?? 0}',
            Icons.people,
            const Color(0xFF1A1A2E),
          ),
          const SizedBox(height: 12),

          // Bills Card
          _buildDashboardCard(
            'Total Bills',
            '${_dashboardData?['total_bills'] ?? 0}',
            Icons.receipt_long,
            Colors.purple,
          ),
          const SizedBox(height: 12),

          // Utilization Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Budget Utilization',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value:
                        (_dashboardData?['utilization_percentage'] ?? 0) / 100,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      (_dashboardData?['utilization_percentage'] ?? 0) > 90
                          ? Colors.red
                          : (_dashboardData?['utilization_percentage'] ?? 0) >
                                75
                          ? Colors.orange
                          : Colors.green,
                    ),
                    minHeight: 10,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_dashboardData?['utilization_percentage'] ?? 0).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabourTab() {
    if (_isLoadingLabour) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_labourEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No labour entries found',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLabourEntries,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _buildLabourEntriesWithDropdown(),
      ),
    );
  }

  List<Widget> _buildLabourEntriesWithDropdown() {
    // Group entries by date
    final Map<String, List<Map<String, dynamic>>> groupedEntries = {};
    for (var entry in _labourEntries) {
      final date = entry['entry_date'] ?? 'Unknown Date';
      if (!groupedEntries.containsKey(date)) {
        groupedEntries[date] = [];
      }
      groupedEntries[date]!.add(entry);
    }

    // Sort dates (most recent first)
    final sortedDates = groupedEntries.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return sortedDates.map((date) {
      final dateEntries = groupedEntries[date]!;
      return _buildDateDropdown(date, dateEntries, true);
    }).toList();
  }

  Widget _buildDateDropdown(
    String date,
    List<Map<String, dynamic>> entries,
    bool isLabour,
  ) {
    final dateKey = '${isLabour ? 'labour' : 'material'}_$date';
    final isExpanded = _expandedDates.contains(dateKey);
    final formattedDate = _formatDateForDropdown(date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Dropdown Header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDates.remove(dateKey);
                  } else {
                    _expandedDates.add(dateKey);
                  }
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLabour
                            ? const Color(0xFF1A1A2E).withValues(alpha: 0.1)
                            : Colors.brown.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isLabour ? Icons.people : Icons.inventory_2,
                        color: isLabour
                            ? const Color(0xFF1A1A2E)
                            : Colors.brown,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${entries.length} ${isLabour ? 'labour' : 'material'} ${entries.length == 1 ? 'entry' : 'entries'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expandable Content
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: entries.map((entry) {
                  if (isLabour) {
                    return _buildLabourEntryCard(entry);
                  } else {
                    return _buildMaterialEntryCard(entry);
                  }
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLabourEntryCard(Map<String, dynamic> entry) {
    final isModified = entry['is_modified'] == true;
    final modificationReason = entry['modification_reason'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isModified
                      ? Colors.orange
                      : const Color(0xFF1A1A2E),
                  child: Text(
                    '${entry['labour_count'] ?? 0}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry['labour_type'] ?? 'General',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        entry['day_of_week'] ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                if (isModified)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.edit, size: 14, color: Colors.orange),
                        SizedBox(width: 4),
                        Text(
                          'Modified',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (isModified && modificationReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reason: $modificationReason',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (entry['notes'] != null &&
                entry['notes'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Notes: ${entry['notes']}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'By: ${entry['supervisor_name'] ?? 'Unknown'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const Spacer(),
                Text(
                  'Time: ${entry['entry_time']?.substring(0, 5) ?? 'N/A'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: const Color(0xFF1A1A2E),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF1A1A2E),
              tabs: [
                Tab(text: 'Entries'),
                Tab(text: 'Manage'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildMaterialEntriesView(),
                _buildMaterialManageView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialEntriesView() {
    if (_isLoadingMaterial) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_materialBalances.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No material balances found',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMaterialBalances,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _buildMaterialEntriesWithDropdown(),
      ),
    );
  }

  Widget _buildMaterialManageView() {
    if (_isLoadingMaterial) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_materialBalances.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No material data available',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Group materials by type for management view
    final Map<String, List<Map<String, dynamic>>> groupedByType = {};
    for (var material in _materialBalances) {
      final type = material['material_type'] ?? 'Unknown';
      if (!groupedByType.containsKey(type)) {
        groupedByType[type] = [];
      }
      groupedByType[type]!.add(material);
    }

    return RefreshIndicator(
      onRefresh: _loadMaterialBalances,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary Cards
          Card(
            color: Colors.brown.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Material Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        'Types',
                        groupedByType.length.toString(),
                        Icons.category,
                        Colors.brown,
                      ),
                      _buildSummaryItem(
                        'Entries',
                        _materialBalances.length.toString(),
                        Icons.list_alt,
                        Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Material Type Cards
          ...groupedByType.entries.map((entry) {
            final materialType = entry.key;
            final materials = entry.value;

            // Calculate totals
            double totalQuantity = 0;
            String unit = '';
            for (var m in materials) {
              totalQuantity += (m['quantity'] ?? 0);
              if (unit.isEmpty) unit = m['unit'] ?? '';
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.brown.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2, color: Colors.brown),
                ),
                title: Text(
                  materialType,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Total: ${totalQuantity.toStringAsFixed(1)} $unit • ${materials.length} entries',
                  style: const TextStyle(fontSize: 12),
                ),
                children: materials.map((m) {
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.brown.withValues(alpha: 0.2),
                      child: Text(
                        '${m['quantity'] ?? 0}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      '${m['quantity'] ?? 0} ${m['unit'] ?? ''}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      'Date: ${m['entry_date'] ?? 'N/A'} • By: ${m['supervisor_name'] ?? 'Unknown'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: m['extra_cost'] != null && m['extra_cost'] > 0
                        ? Chip(
                            label: Text(
                              _formatCurrency(m['extra_cost']),
                              style: const TextStyle(fontSize: 10),
                            ),
                            backgroundColor: Colors.orange.withValues(
                              alpha: 0.2,
                            ),
                          )
                        : null,
                  );
                }).toList(),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  List<Widget> _buildMaterialEntriesWithDropdown() {
    // Group entries by date
    final Map<String, List<Map<String, dynamic>>> groupedEntries = {};
    for (var entry in _materialBalances) {
      final date = entry['entry_date'] ?? 'Unknown Date';
      if (!groupedEntries.containsKey(date)) {
        groupedEntries[date] = [];
      }
      groupedEntries[date]!.add(entry);
    }

    // Sort dates (most recent first)
    final sortedDates = groupedEntries.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return sortedDates.map((date) {
      final dateEntries = groupedEntries[date]!;
      return _buildDateDropdown(date, dateEntries, false);
    }).toList();
  }

  Widget _buildMaterialEntryCard(Map<String, dynamic> material) {
    final createdAt = material['created_at'] ?? material['usage_date'];
    String timeDisplay = 'N/A';

    if (createdAt != null) {
      try {
        final dateTime = DateTime.parse(createdAt.toString());
        timeDisplay =
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        timeDisplay = 'N/A';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.brown,
                  child: Icon(Icons.inventory_2, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        material['material_type'] ?? 'Unknown',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Quantity: ${material['quantity_used'] ?? material['quantity'] ?? material['current_balance'] ?? 0} ${material['unit'] ?? ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'By: ${material['supervisor_name'] ?? 'Unknown'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const Spacer(),
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Time: $timeDisplay',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
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
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
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

    final dayName = days[date.weekday - 1];
    final monthName = months[date.month - 1];

    return '$dayName, $monthName ${date.day}, ${date.year}';
  }

  Widget _buildBillsTab() {
    if (_isLoadingBills) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bills.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No bills found',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBills,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _bills.length,
        itemBuilder: (context, index) => _buildBillCard(_bills[index]),
      ),
    );
  }

  Widget _buildBillCard(Map<String, dynamic> bill) {
    final isVerified = bill['verified'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt, color: Color(0xFF1A1A2E), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill['material_name'] ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bill['report_date'] ?? 'N/A',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isVerified
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVerified ? Icons.check_circle : Icons.pending,
                        size: 14,
                        color: isVerified ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isVerified ? 'Verified' : 'Pending',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isVerified ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Amount', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(height: 2),
                    Text(
                      '₹${bill['bill_amount'] ?? '0.00'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Uploaded by', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(height: 2),
                    Text(
                      bill['uploaded_by'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetTab() {
    return AdminBudgetManagementScreen(
      siteId: widget.siteId,
      siteName: widget.siteName,
    );
  }

  Widget _buildPhotosTab() {
    if (_isLoadingPhotos) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No photos found',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _buildPhotosWithDropdown(),
      ),
    );
  }

  List<Widget> _buildPhotosWithDropdown() {
    // Group photos by date
    final Map<String, List<Map<String, dynamic>>> groupedPhotos = {};
    for (var photo in _photos) {
      final date =
          photo['upload_date'] ?? photo['update_date'] ?? 'Unknown Date';
      if (!groupedPhotos.containsKey(date)) {
        groupedPhotos[date] = [];
      }
      groupedPhotos[date]!.add(photo);
    }

    // Sort dates (most recent first)
    final sortedDates = groupedPhotos.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return sortedDates.map((date) {
      final datePhotos = groupedPhotos[date]!;
      return _buildPhotoDateDropdown(date, datePhotos);
    }).toList();
  }

  Widget _buildPhotoDateDropdown(
    String date,
    List<Map<String, dynamic>> photos,
  ) {
    final dateKey = 'photos_$date';
    final isExpanded = _expandedDates.contains(dateKey);
    final formattedDate = _formatDateForDropdown(date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Dropdown Header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDates.remove(dateKey);
                  } else {
                    _expandedDates.add(dateKey);
                  }
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.photo_camera,
                        color: Colors.purple,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expandable Content
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return _buildPhotoCard(photo);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoCard(Map<String, dynamic> photo) {
    final imageUrl = 'http://192.168.1.6:8001${photo['image_url']}';
    final uploadDate =
        photo['upload_date'] ?? photo['update_date'] ?? photo['created_at'];
    String timeDisplay = '';

    if (uploadDate != null) {
      try {
        final dateTime = DateTime.parse(uploadDate.toString());
        timeDisplay =
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        timeDisplay = '';
      }
    }

    return GestureDetector(
      onTap: () => _showPhotoDialog(imageUrl, photo),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image, size: 50),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          photo['update_type'] ??
                              photo['upload_type'] ??
                              'Photo',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeDisplay.isNotEmpty) ...[
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 2),
                        Text(
                          timeDisplay,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (photo['description'] != null &&
                      photo['description'].toString().isNotEmpty)
                    Text(
                      photo['description'],
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (photo['supervisor_name'] != null)
                    Text(
                      'By: ${photo['supervisor_name']}',
                      style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoDialog(String imageUrl, Map<String, dynamic> photo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(photo['update_type'] ?? 'Photo'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(50),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 50,
                            color: Colors.red,
                          ),
                          SizedBox(height: 16),
                          Text('Could not load image'),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            if (photo['description'] != null &&
                photo['description'].toString().isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                color: Colors.grey[100],
                child: Text(
                  photo['description'],
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsTab() {
    if (_isLoadingDocuments) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No documents found',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Documents uploaded by Site Engineers and Architects will appear here',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDocuments,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _buildDocumentsWithDropdown(),
      ),
    );
  }

  List<Widget> _buildDocumentsWithDropdown() {
    // Group documents by date
    final Map<String, List<Map<String, dynamic>>> groupedDocuments = {};
    for (var doc in _documents) {
      final date =
          doc['upload_date'] ??
          doc['uploaded_at']?.substring(0, 10) ??
          'Unknown Date';
      if (!groupedDocuments.containsKey(date)) {
        groupedDocuments[date] = [];
      }
      groupedDocuments[date]!.add(doc);
    }

    // Sort dates (most recent first)
    final sortedDates = groupedDocuments.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return sortedDates.map((date) {
      final dateDocs = groupedDocuments[date]!;
      return _buildDocumentDateDropdown(date, dateDocs);
    }).toList();
  }

  Widget _buildDocumentDateDropdown(
    String date,
    List<Map<String, dynamic>> documents,
  ) {
    final dateKey = 'documents_$date';
    final isExpanded = _expandedDates.contains(dateKey);
    final formattedDate = _formatDateForDropdown(date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Dropdown Header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDates.remove(dateKey);
                  } else {
                    _expandedDates.add(dateKey);
                  }
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.description,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${documents.length} ${documents.length == 1 ? 'document' : 'documents'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expandable Content
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: documents
                    .map((doc) => _buildDocumentCard(doc))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> document) {
    final documentType = document['document_type'] ?? 'Document';
    final title = document['title'] ?? 'Untitled';
    final uploadedBy = document['uploaded_by'] ?? 'Unknown';
    final role = document['role'] ?? 'Unknown';
    final fileUrl = document['file_url'] ?? '';
    final fileName = document['file_name'] ?? 'document.pdf';

    // Determine icon and color based on document type
    IconData icon;
    Color color;

    switch (documentType.toLowerCase()) {
      case 'site plan':
        icon = Icons.map;
        color = Colors.green;
        break;
      case 'floor design':
        icon = Icons.layers;
        color = Colors.blue;
        break;
      case 'structural plan':
        icon = Icons.foundation;
        color = Colors.orange;
        break;
      case 'electrical plan':
        icon = Icons.electrical_services;
        color = Colors.amber;
        break;
      case 'plumbing plan':
        icon = Icons.plumbing;
        color = Colors.cyan;
        break;
      default:
        icon = Icons.description;
        color = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: InkWell(
        onTap: () => _openDocument(fileUrl, fileName),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      documentType,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$uploadedBy ($role)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new, color: Colors.grey[600], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _openDocument(String fileUrl, String fileName) async {
    try {
      // Construct full URL
      final fullUrl = fileUrl.startsWith('http')
          ? fileUrl
          : 'http://192.168.1.6:8001$fileUrl';

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Opening document...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Show info dialog with URL
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Document'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File: $fileName'),
              const SizedBox(height: 8),
              Text('URL: $fullUrl', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              const Text(
                'The document URL is ready. You can copy it or open it in a browser.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Close loading dialog if open
      if (mounted) Navigator.pop(context);

      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open document: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
