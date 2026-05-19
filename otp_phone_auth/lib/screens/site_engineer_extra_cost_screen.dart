import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/app_colors.dart';
import '../services/auth_service.dart';

class SiteEngineerExtraCostScreen extends StatefulWidget {
  final Map<String, dynamic> site;

  const SiteEngineerExtraCostScreen({
    super.key,
    required this.site,
  });

  @override
  State<SiteEngineerExtraCostScreen> createState() => _SiteEngineerExtraCostScreenState();
}

class _SiteEngineerExtraCostScreenState extends State<SiteEngineerExtraCostScreen> {
  final _authService = AuthService();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> _extraCosts = [];
  bool _isLoadingExtraCosts = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadExtraCosts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadExtraCosts() async {
    setState(() => _isLoadingExtraCosts = true);

    try {
      final token = await _authService.getToken();

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/construction/extra-costs/${widget.site['id']}/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final extraCostsList = List<Map<String, dynamic>>.from(data['extra_costs'] ?? []);
        setState(() {
          _extraCosts = extraCostsList;
          _isLoadingExtraCosts = false;
        });
      } else {
        setState(() => _isLoadingExtraCosts = false);
      }
    } catch (e) {
      setState(() => _isLoadingExtraCosts = false);
    }
  }

  Future<void> _submitExtraCost() async {
    final amount = _amountController.text.trim();
    final description = _descriptionController.text.trim();

    if (amount.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
        ),
      );
      return;
    }

    final amountValue = double.tryParse(amount);
    if (amountValue == null || amountValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/construction/submit-extra-cost/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'site_id': widget.site['id'],
          'amount': amountValue,
          'description': description,
        }),
      );

      if (mounted) {
        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Extra cost added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _amountController.clear();
          _descriptionController.clear();
          _loadExtraCosts();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to add extra cost'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final siteName = widget.site['display_name'] ?? widget.site['site_name'] ?? 'Site Details';

    return Scaffold(
      backgroundColor: AppColors.lightSlate,
      appBar: AppBar(
        title: Text(
          'Extra Costs - $siteName',
          style: const TextStyle(
            color: AppColors.deepNavy,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.cleanWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.deepNavy),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cleanWhite,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [AppColors.cardShadow],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Extra Cost',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹) *',
                        hintText: 'Enter amount',
                        prefixIcon: Icon(Icons.currency_rupee),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        hintText: 'e.g., Transport, Tools, Site utilities',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitExtraCost,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryOrange,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.cleanWhite,
                                  ),
                                ),
                              )
                            : const Text(
                                'Submit Extra Cost',
                                style: TextStyle(
                                  color: AppColors.cleanWhite,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Extra Costs',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepNavy,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _isLoadingExtraCosts
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: CircularProgressIndicator(),
                    )
                  : _extraCosts.isEmpty
                      ? Container(
                          decoration: BoxDecoration(
                            color: AppColors.cleanWhite,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [AppColors.cardShadow],
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: const Center(
                            child: Text(
                              'No extra costs added yet',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: _extraCosts.map((cost) {
                            return _buildExtraCostCard(cost);
                          }).toList(),
                        ),
            ],
          ),
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
            Text(
              '₹${(amount is num ? amount : double.tryParse(amount.toString()) ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.deepNavy,
              ),
            ),
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
}
