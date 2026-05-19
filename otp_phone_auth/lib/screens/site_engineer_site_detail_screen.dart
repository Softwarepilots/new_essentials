import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/app_colors.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/construction_service.dart';
import 'site_engineer_labour_screen.dart';
import 'site_engineer_material_screen.dart';
import 'site_engineer_extra_cost_screen.dart';

class SiteEngineerSiteDetailScreen extends StatefulWidget {
  final Map<String, dynamic> site;
  final UserModel user;

  const SiteEngineerSiteDetailScreen({
    super.key,
    required this.site,
    required this.user,
  });

  @override
  State<SiteEngineerSiteDetailScreen> createState() => _SiteEngineerSiteDetailScreenState();
}

class _SiteEngineerSiteDetailScreenState extends State<SiteEngineerSiteDetailScreen> {
  final _authService = AuthService();
  List<Map<String, dynamic>> _extraCosts = [];
  bool _isLoadingExtraCosts = false;
  @override
  void initState() {
    super.initState();
    _loadExtraCosts();
  }

  Future<void> _loadExtraCosts() async {
    setState(() => _isLoadingExtraCosts = true);

    try {
      final token = await _authService.getToken();

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/construction/extra-costs/${widget.site['id']}/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      print('📦 [EXTRA_COST] Response status: ${response.statusCode}');
      print('📦 [EXTRA_COST] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final extraCostsList = List<Map<String, dynamic>>.from(data['extra_costs'] ?? []);
        print('📦 [EXTRA_COST] Loaded ${extraCostsList.length} extra costs');
        setState(() {
          _extraCosts = extraCostsList;
          _isLoadingExtraCosts = false;
        });
      } else {
        print('❌ [EXTRA_COST] Failed to load: ${response.statusCode}');
        setState(() => _isLoadingExtraCosts = false);
      }
    } catch (e) {
      print('❌ [EXTRA_COST] Exception: $e');
      setState(() => _isLoadingExtraCosts = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final siteName = widget.site['display_name'] ?? widget.site['site_name'] ?? 'Site Details';

    return Scaffold(
      backgroundColor: AppColors.lightSlate,
      appBar: AppBar(
        title: Text(
          siteName,
          style: const TextStyle(
            color: AppColors.deepNavy,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.cleanWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.deepNavy),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Site Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cleanWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [AppColors.cardShadow],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.deepNavy.withValues(alpha: 0.8), AppColors.deepNavy],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.location_city, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          siteName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.deepNavy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.site['area'] ?? ''}, ${widget.site['street'] ?? ''}',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    label: 'Labour Entry\nMorning',
                    icon: Icons.people,
                    color: Colors.orange,
                    onTap: _openLabourEntry,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    label: 'Material\nRequest',
                    icon: Icons.inventory_2,
                    color: Colors.teal,
                    onTap: _showMaterialRequirementDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Inventory Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openMaterialInventory,
                icon: const Icon(Icons.inventory_2, size: 20),
                label: const Text(
                  'Inventory',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Extra Cost Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Extra Costs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepNavy),
                ),
                TextButton.icon(
                  onPressed: _openExtraCostScreen,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.deepNavy),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildExtraCostSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openLabourEntry() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SiteEngineerLabourScreen(
          siteId: widget.site['id'].toString(),
          siteName: widget.site['display_name'] ?? widget.site['site_name'] ?? 'Unknown Site',
        ),
      ),
    );
  }

  void _openMaterialInventory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SiteEngineerMaterialScreen(
          siteId: widget.site['id'].toString(),
          siteName: widget.site['display_name'] ?? widget.site['site_name'] ?? 'Unknown Site',
        ),
      ),
    ).then((_) {
      // Reload data when returning from inventory
      _loadExtraCosts();
    });
  }

  Widget _buildExtraCostSection() {
    if (_isLoadingExtraCosts) {
      return const Center(child: CircularProgressIndicator(color: AppColors.deepNavy));
    }
    if (_extraCosts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cleanWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [AppColors.cardShadow],
        ),
        child: Center(
          child: Text(
            'No extra costs yet',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return Column(
      children: _extraCosts.map((cost) => _buildExtraCostCard(cost)).toList(),
    );
  }


  void _showMaterialRequirementDialog() {
    final _constructionService = ConstructionService();
    final materialNameController = TextEditingController();
    final quantityController = TextEditingController();
    final unitController = TextEditingController();
    final notesController = TextEditingController();
    String selectedPriority = 'normal';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Material Requirement'),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
                  const SizedBox(height: 16),
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
                      const SizedBox(width: 12),
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedPriority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'urgent', child: Text('🔴 Urgent')),
                      DropdownMenuItem(value: 'normal', child: Text('🟡 Normal')),
                      DropdownMenuItem(value: 'low', child: Text('🟢 Low')),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedPriority = value ?? 'normal');
                    },
                  ),
                  const SizedBox(height: 16),
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
                    const SnackBar(content: Text('Please fill all required fields')),
                  );
                  return;
                }

                final qty = double.tryParse(quantityController.text);
                if (qty == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid quantity')),
                  );
                  return;
                }

                final result = await _constructionService.submitMaterialRequirement(
                  siteId: widget.site['id'].toString(),
                  materialName: materialNameController.text.trim(),
                  quantity: qty,
                  unit: unitController.text.trim(),
                  priority: selectedPriority,
                  notes: notesController.text.trim(),
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result['success'] == true
                          ? result['message'] ?? 'Material requirement submitted'
                          : result['error'] ?? 'Failed to submit'),
                      backgroundColor:
                          result['success'] == true ? Colors.green : Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildExtraCostCard(Map<String, dynamic> cost) {
    final amount = cost['amount'] ?? 0;
    final description = cost['description'] ?? '';
    final bill = cost['bill'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cleanWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [AppColors.cardShadow],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount
            Text(
              '₹${(amount is num ? amount : double.tryParse(amount.toString()) ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
            // Description
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.deepNavy,
                ),
              ),
            ],
            // Bill reference if available
            if (bill != null && bill.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.receipt, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Bill: $bill',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openExtraCostScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SiteEngineerExtraCostScreen(site: widget.site),
      ),
    ).then((_) {
      _loadExtraCosts();
    });
  }

}
