import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/material_service.dart';
import '../services/construction_service.dart';
import '../utils/app_colors.dart';
import 'package:intl/intl.dart';

class SiteEngineerMaterialScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const SiteEngineerMaterialScreen({
    Key? key,
    required this.siteId,
    required this.siteName,
  }) : super(key: key);

  @override
  State<SiteEngineerMaterialScreen> createState() => _SiteEngineerMaterialScreenState();
}

class _SiteEngineerMaterialScreenState extends State<SiteEngineerMaterialScreen> {
  final _materialService = MaterialService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _materialBalance = [];
  Map<String, dynamic> _todayUsageSummary = {};

  @override
  void initState() {
    super.initState();
    _loadMaterialData();
  }

  Future<void> _loadMaterialData() async {
    setState(() => _isLoading = true);

    try {
      // Load material balance
      final balanceResult = await _materialService.getMaterialBalance(widget.siteId);

      // Load today's usage
      final todayUsageResult = await _materialService.getTodayMaterialUsage(widget.siteId);

      if (balanceResult['success'] == true) {
        setState(() {
          _materialBalance = List<Map<String, dynamic>>.from(balanceResult['balance'] ?? []);
        });
      }

      if (todayUsageResult['success'] == true) {
        // Create a map for quick lookup of today's usage
        final todayUsageList = List<Map<String, dynamic>>.from(
          todayUsageResult['today_usage_summary'] ?? []
        );

        setState(() {
          _todayUsageSummary = {
            for (var item in todayUsageList)
              item['material_type']: item['total_used_today']
          };
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading materials: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showAddMaterialDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddMaterialDialog(
        siteId: widget.siteId,
        onSuccess: () {
          _loadMaterialData();
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'IN_STOCK':
        return AppColors.success;
      case 'LOW_STOCK':
        return AppColors.textSecondary;
      case 'OUT_OF_STOCK':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'IN_STOCK':
        return 'In Stock';
      case 'LOW_STOCK':
        return 'Low Stock';
      case 'OUT_OF_STOCK':
        return 'Out of Stock';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Material Inventory', style: TextStyle(fontSize: 18.sp)),
            Text(
              widget.siteName,
              style: TextStyle(fontSize: 12.sp, color: AppColors.white.withOpacity(0.8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMaterialData,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _materialBalance.isEmpty
              ? _buildEmptyState()
              : _buildMaterialList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMaterialDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        icon: Icon(Icons.add),
        label: Text('Add Material'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80.sp, color: AppColors.textSecondary),
          SizedBox(height: 16.h),
          Text(
            'No materials added yet',
            style: TextStyle(fontSize: 18.sp, color: AppColors.textPrimary),
          ),
          SizedBox(height: 8.h),
          Text(
            'Tap the button below to add materials',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialList() {
    return RefreshIndicator(
      onRefresh: _loadMaterialData,
      color: AppColors.primary,
      child: ListView.builder(
        padding: EdgeInsets.all(16.r),
        itemCount: _materialBalance.length,
        itemBuilder: (context, index) {
          final material = _materialBalance[index];
          return _buildMaterialCard(material);
        },
      ),
    );
  }

  Widget _buildMaterialCard(Map<String, dynamic> material) {
    final materialType = material['material_type'] ?? '';
    final initialStock = (material['initial_stock'] as num?)?.toDouble() ?? 0;
    final totalUsed = (material['total_used'] as num?)?.toDouble() ?? 0;
    final currentBalance = (material['current_balance'] as num?)?.toDouble() ?? 0;
    final unit = material['unit'] ?? '';
    final status = material['stock_status'] ?? 'IN_STOCK';
    final todayUsed = (_todayUsageSummary[materialType] as num?)?.toDouble() ?? 0;

    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      color: AppColors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with material name and status
            Row(
              children: [
                Icon(Icons.inventory_2, color: AppColors.primary, size: 24.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    materialType,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: _getStatusColor(status)),
                  ),
                  child: Text(
                    _getStatusText(status),
                    style: TextStyle(
                      color: _getStatusColor(status),
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),

            // Current Balance (Large Display)
            Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Text(
                        'Current Balance',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '${currentBalance.toStringAsFixed(1)} $unit',
                        style: TextStyle(
                          fontSize: 32.sp,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(status),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),

            // Stock Details
            Row(
              children: [
                Expanded(
                  child: _buildInfoColumn(
                    'Initial Stock',
                    '${initialStock.toStringAsFixed(1)} $unit',
                    Icons.add_circle_outline,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40.h,
                  color: AppColors.divider,
                ),
                Expanded(
                  child: _buildInfoColumn(
                    'Total Used',
                    '${totalUsed.toStringAsFixed(1)} $unit',
                    Icons.remove_circle_outline,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40.h,
                  color: AppColors.divider,
                ),
                Expanded(
                  child: _buildInfoColumn(
                    'Stocks Left',
                    '${(initialStock - totalUsed).toStringAsFixed(1)} $unit',
                    Icons.inventory_2,
                  ),
                ),
              ],
            ),

            // Today's Usage (Highlighted)
            if (todayUsed > 0) ...[
              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.all(12.r),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.today, color: AppColors.primary, size: 20.sp),
                    SizedBox(width: 8.w),
                    Text(
                      'Used Today: ',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14.sp,
                      ),
                    ),
                    Text(
                      '${todayUsed.toStringAsFixed(1)} $unit',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Action Buttons
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddStockDialog(material),
                    icon: Icon(Icons.add, size: 18.sp),
                    label: Text('Add Stock'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showUsageHistory(material),
                    icon: Icon(Icons.history, size: 18.sp),
                    label: Text('History'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showEditStocksLeftDialog(material, initialStock, totalUsed),
                icon: Icon(Icons.edit, size: 18.sp),
                label: Text('Edit Stocks Left'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: BorderSide(color: Colors.green),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 20.sp),
        SizedBox(height: 4.h),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.sp,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showAddStockDialog(Map<String, dynamic> material) {
    showDialog(
      context: context,
      builder: (context) => _AddStockDialog(
        siteId: widget.siteId,
        materialType: material['material_type'],
        unit: material['unit'],
        onSuccess: () {
          _loadMaterialData();
        },
      ),
    );
  }

  void _showEditStocksLeftDialog(Map<String, dynamic> material, double initialStock, double totalUsed) {
    showDialog(
      context: context,
      builder: (context) => _EditStocksLeftDialog(
        siteId: widget.siteId,
        materialType: material['material_type'],
        unit: material['unit'],
        currentStocksLeft: initialStock - totalUsed,
        initialStock: initialStock,
        totalUsed: totalUsed,
        onSuccess: () {
          _loadMaterialData();
        },
      ),
    );
  }

  void _showUsageHistory(Map<String, dynamic> material) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _MaterialUsageHistoryScreen(
          siteId: widget.siteId,
          materialType: material['material_type'],
          siteName: widget.siteName,
        ),
      ),
    );
  }
}

// ============================================
// ADD NEW MATERIAL DIALOG
// ============================================

class _AddMaterialDialog extends StatefulWidget {
  final String siteId;
  final VoidCallback onSuccess;

  const _AddMaterialDialog({
    required this.siteId,
    required this.onSuccess,
  });

  @override
  State<_AddMaterialDialog> createState() => _AddMaterialDialogState();
}

class _AddMaterialDialogState extends State<_AddMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _materialTypeController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _notesController = TextEditingController();
  final _materialService = MaterialService();
  bool _isSubmitting = false;
  bool _isLoadingMaterials = true;
  List<Map<String, dynamic>> _materials = [];
  String? _selectedMaterial;

  // Common units
  final List<String> _commonUnits = [
    'Bags',
    'Tons',
    'Pieces',
    'Cubic Meters',
    'Liters',
    'Kg',
    'Sq Meters',
  ];

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    setState(() => _isLoadingMaterials = true);

    try {
      // Import construction service to get materials from admin
      final constructionService = ConstructionService();
      final materials = await constructionService.getMaterials();

      setState(() {
        _materials = materials;
        _isLoadingMaterials = false;
      });
    } catch (e) {
      setState(() => _isLoadingMaterials = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading materials: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _materialTypeController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await _materialService.addMaterialStock(
        siteId: widget.siteId,
        materialType: _materialTypeController.text.trim(),
        quantity: double.parse(_quantityController.text),
        unit: _unitController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (result['success'] == true) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Material added successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to add material'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      title: Text('Add Material Stock', style: TextStyle(color: AppColors.textPrimary)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Loading indicator or Material Type Dropdown
              if (_isLoadingMaterials)
                Padding(
                  padding: EdgeInsets.all(16.r),
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              else if (_materials.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16.r),
                  child: Column(
                    children: [
                      Icon(Icons.warning, color: AppColors.textSecondary, size: 48.sp),
                      SizedBox(height: 8.h),
                      Text(
                        'No materials available',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'Admin needs to add materials first',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Material Type',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedMaterial,
                  items: _materials.map<DropdownMenuItem<String>>((material) {
                    final name = material['name']?.toString() ?? '';
                    return DropdownMenuItem<String>(value: name, child: Text(name));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedMaterial = value;
                      _materialTypeController.text = value ?? '';
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select material type';
                    }
                    return null;
                  },
                ),

              SizedBox(height: 16.h),

              // Quantity
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter quantity';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter valid number';
                  }
                  if (double.parse(value) <= 0) {
                    return 'Quantity must be greater than 0';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16.h),

              // Unit Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(),
                ),
                items: _commonUnits.map((unit) {
                  return DropdownMenuItem(value: unit, child: Text(unit));
                }).toList(),
                onChanged: (value) {
                  _unitController.text = value ?? '';
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select unit';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16.h),

              // Notes
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
          ),
          child: _isSubmitting
              ? SizedBox(
                  width: 20.w,
                  height: 20.h,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : Text('Add Material'),
        ),
      ],
    );
  }
}

// ============================================
// ADD STOCK TO EXISTING MATERIAL DIALOG
// ============================================

class _AddStockDialog extends StatefulWidget {
  final String siteId;
  final String materialType;
  final String unit;
  final VoidCallback onSuccess;

  const _AddStockDialog({
    required this.siteId,
    required this.materialType,
    required this.unit,
    required this.onSuccess,
  });

  @override
  State<_AddStockDialog> createState() => _AddStockDialogState();
}

class _AddStockDialogState extends State<_AddStockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  final _materialService = MaterialService();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await _materialService.addMaterialStock(
        siteId: widget.siteId,
        materialType: widget.materialType,
        quantity: double.parse(_quantityController.text),
        unit: widget.unit,
        notes: _notesController.text.trim(),
      );

      if (result['success'] == true) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock added successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to add stock'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      title: Text('Add Stock', style: TextStyle(color: AppColors.textPrimary)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Adding stock to: ${widget.materialType}',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 16.h),
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: 'Quantity (${widget.unit})',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter quantity';
                }
                if (double.tryParse(value) == null) {
                  return 'Please enter valid number';
                }
                if (double.parse(value) <= 0) {
                  return 'Quantity must be greater than 0';
                }
                return null;
              },
            ),
            SizedBox(height: 16.h),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
          ),
          child: _isSubmitting
              ? SizedBox(
                  width: 20.w,
                  height: 20.h,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : Text('Add Stock'),
        ),
      ],
    );
  }
}

// ============================================
// EDIT STOCKS LEFT DIALOG
// ============================================

class _EditStocksLeftDialog extends StatefulWidget {
  final String siteId;
  final String materialType;
  final String unit;
  final double currentStocksLeft;
  final double initialStock;
  final double totalUsed;
  final VoidCallback onSuccess;

  const _EditStocksLeftDialog({
    required this.siteId,
    required this.materialType,
    required this.unit,
    required this.currentStocksLeft,
    required this.initialStock,
    required this.totalUsed,
    required this.onSuccess,
  });

  @override
  State<_EditStocksLeftDialog> createState() => _EditStocksLeftDialogState();
}

class _EditStocksLeftDialogState extends State<_EditStocksLeftDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _stocksLeftController;
  final _materialService = MaterialService();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _stocksLeftController = TextEditingController(
      text: widget.currentStocksLeft.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _stocksLeftController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final newStocksLeft = double.parse(_stocksLeftController.text);
      final newTotalUsed = widget.initialStock - newStocksLeft;
      final difference = newTotalUsed - widget.totalUsed;

      // Record the difference as usage
      final result = await _materialService.recordMaterialUsage(
        siteId: widget.siteId,
        materialType: widget.materialType,
        quantityUsed: difference,
        unit: widget.unit,
        notes: 'Stocks left adjusted to ${newStocksLeft.toStringAsFixed(1)} ${widget.unit}',
      );

      if (result['success'] == true) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stocks left updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to update stocks left'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stocksLeftValue = double.tryParse(_stocksLeftController.text.trim()) ?? widget.currentStocksLeft;
    final newTotalUsed = widget.initialStock - stocksLeftValue;
    final difference = newTotalUsed - widget.totalUsed;

    return AlertDialog(
      backgroundColor: AppColors.white,
      title: Text('Edit Stocks Left', style: TextStyle(color: AppColors.textPrimary)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Material: ${widget.materialType}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
            ),
            SizedBox(height: 4.h),
            Text(
              'Initial Stock: ${widget.initialStock.toStringAsFixed(1)} ${widget.unit}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
            ),
            SizedBox(height: 12.h),
            TextFormField(
              controller: _stocksLeftController,
              decoration: InputDecoration(
                labelText: 'Stocks Left (${widget.unit})',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter stocks left';
                }
                final amount = double.tryParse(value);
                if (amount == null) {
                  return 'Please enter valid number';
                }
                if (amount < 0) {
                  return 'Stocks left cannot be negative';
                }
                if (amount > widget.initialStock) {
                  return 'Stocks left cannot exceed initial stock (${widget.initialStock.toStringAsFixed(1)})';
                }
                return null;
              },
            ),
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(12.r),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Updated Values:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 12.sp,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'New Total Used:',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
                      ),
                      Text(
                        '${newTotalUsed.toStringAsFixed(1)} ${widget.unit}',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                  if (difference.abs() > 0.01) ...[
                    SizedBox(height: 4.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Difference:',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
                        ),
                        Text(
                          '${difference > 0 ? '+' : ''}${difference.toStringAsFixed(1)} ${widget.unit}',
                          style: TextStyle(
                            color: difference > 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: AppColors.white,
          ),
          child: _isSubmitting
              ? SizedBox(
                  width: 20.w,
                  height: 20.h,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : Text('Update'),
        ),
      ],
    );
  }
}

// ============================================
// MATERIAL USAGE HISTORY SCREEN
// ============================================

class _MaterialUsageHistoryScreen extends StatefulWidget {
  final String siteId;
  final String materialType;
  final String siteName;

  const _MaterialUsageHistoryScreen({
    required this.siteId,
    required this.materialType,
    required this.siteName,
  });

  @override
  State<_MaterialUsageHistoryScreen> createState() => _MaterialUsageHistoryScreenState();
}

class _MaterialUsageHistoryScreenState extends State<_MaterialUsageHistoryScreen> {
  final _materialService = MaterialService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _usageHistory = [];

  @override
  void initState() {
    super.initState();
    _loadUsageHistory();
  }

  Future<void> _loadUsageHistory() async {
    setState(() => _isLoading = true);

    try {
      final result = await _materialService.getMaterialUsageHistory(
        siteId: widget.siteId,
        materialType: widget.materialType,
      );

      if (result['success'] == true) {
        setState(() {
          _usageHistory = List<Map<String, dynamic>>.from(result['usage_history'] ?? []);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading history: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usage History', style: TextStyle(fontSize: 18.sp)),
            Text(
              widget.materialType,
              style: TextStyle(fontSize: 12.sp, color: AppColors.white.withOpacity(0.8)),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _usageHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 80.sp, color: AppColors.textSecondary),
                      SizedBox(height: 16.h),
                      Text(
                        'No usage history',
                        style: TextStyle(fontSize: 18.sp, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16.r),
                  itemCount: _usageHistory.length,
                  itemBuilder: (context, index) {
                    final usage = _usageHistory[index];
                    return _buildUsageCard(usage);
                  },
                ),
    );
  }

  Widget _buildUsageCard(Map<String, dynamic> usage) {
    final supervisorName = usage['supervisor_name'] ?? 'Unknown';
    final quantityUsed = (usage['quantity_used'] as num?)?.toDouble() ?? 0;
    final unit = usage['unit'] ?? '';
    final usageDate = usage['usage_date'] ?? '';
    final usageTime = usage['usage_time'] ?? '';
    final notes = usage['notes'] ?? '';

    // Format date
    String formattedDate = '';
    try {
      final date = DateTime.parse(usageDate);
      formattedDate = DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      formattedDate = usageDate;
    }

    // Format time
    String formattedTime = '';
    try {
      final time = DateTime.parse(usageTime);
      formattedTime = DateFormat('hh:mm a').format(time);
    } catch (e) {
      formattedTime = usageTime.split('T').last.substring(0, 5);
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      color: AppColors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: AppColors.primary, size: 20.sp),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    supervisorName,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${quantityUsed.toStringAsFixed(1)} $unit',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14.sp, color: AppColors.textSecondary),
                SizedBox(width: 4.w),
                Text(
                  formattedDate,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
                ),
                SizedBox(width: 16.w),
                Icon(Icons.access_time, size: 14.sp, color: AppColors.textSecondary),
                SizedBox(width: 4.w),
                Text(
                  formattedTime,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
                ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Text(
                notes,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14.sp),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
