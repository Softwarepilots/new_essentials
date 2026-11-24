// import 'package:flutter_screenutil/flutter_screenutil.dart';
// import 'package:flutter/material.dart';
// import 'package:url_launcher/url_launcher.dart';
// import '../services/accountant_bills_service.dart';
// import '../utils/app_colors.dart';
// import '../widgets/bill_upload_dialogs.dart';

// class AccountantBillsScreen extends StatefulWidget {
//   final String siteId;
//   final String siteName;

//   const AccountantBillsScreen({
//     super.key,
//     required this.siteId,
//     required this.siteName,
//   });

//   @override
//   State<AccountantBillsScreen> createState() => _AccountantBillsScreenState();
// }

// class _AccountantBillsScreenState extends State<AccountantBillsScreen> with SingleTickerProviderStateMixin {
//   late TabController _tabController;
//   final _billsService = AccountantBillsService();
  
//   List<Map<String, dynamic>> _materialBills = [];
//   List<Map<String, dynamic>> _vendorBills = [];
//   List<Map<String, dynamic>> _agreements = [];
  
//   bool _isLoadingMaterial = false;
//   bool _isLoadingVendor = false;
//   bool _isLoadingAgreements = false;

//   @override
//   void initState() {
//     super.initState();
//     _tabController = TabController(length: 3, vsync: this);
//     _loadAllData();
//   }

//   @override
//   void dispose() {
//     _tabController.dispose();
//     super.dispose();
//   }

//   Future<void> _loadAllData() async {
//     _loadMaterialBills();
//     _loadVendorBills();
//     _loadAgreements();
//   }

//   Future<void> _loadMaterialBills() async {
//     setState(() => _isLoadingMaterial = true);
//     final result = await _billsService.getMaterialBills(siteId: widget.siteId);
//     if (result['success'] == true) {
//       setState(() => _materialBills = result['bills']);
//     }
//     setState(() => _isLoadingMaterial = false);
//   }

//   Future<void> _loadVendorBills() async {
//     setState(() => _isLoadingVendor = true);
//     final result = await _billsService.getVendorBills(siteId: widget.siteId);
//     if (result['success'] == true) {
//       setState(() => _vendorBills = result['bills']);
//     }
//     setState(() => _isLoadingVendor = false);
//   }

//   Future<void> _loadAgreements() async {
//     setState(() => _isLoadingAgreements = true);
//     final result = await _billsService.getSiteAgreements(siteId: widget.siteId);
//     if (result['success'] == true) {
//       setState(() => _agreements = result['agreements']);
//     }
//     setState(() => _isLoadingAgreements = false);
//   }

//   Future<void> _openDocument(String fileUrl) async {
//     final url = 'http://187.127.164.22$fileUrl';
//     if (await canLaunchUrl(Uri.parse(url))) {
//       await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
//     } else {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Could not open document')),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white,
//       appBar: AppBar(
//         title: Text('Bills & Agreements - ${widget.siteName}'),
//         backgroundColor: AppColors.deepNavy,
//         foregroundColor: Colors.white,
//         bottom: TabBar(
//           controller: _tabController,
//           indicatorColor: Colors.white,
//           labelColor: Colors.white,
//           unselectedLabelColor: Colors.white70,
//           tabs: [
//             Tab(text: 'Material Bills (${_materialBills.length})'),
//             Tab(text: 'Vendor Bills (${_vendorBills.length})'),
//             Tab(text: 'Agreements (${_agreements.length})'),
//           ],
//         ),
//       ),
//       body: TabBarView(
//         controller: _tabController,
//         children: [
//           _buildMaterialBillsTab(),
//           _buildVendorBillsTab(),
//           _buildAgreementsTab(),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton.extended(
//         onPressed: () => _showUploadDialog(),
//         icon: const Icon(Icons.add),
//         label: const Text('Add Bill/Agreement'),
//         backgroundColor: AppColors.deepNavy,
//         foregroundColor: Colors.white,
//       ),
//     );
//   }

//   Widget _buildMaterialBillsTab() {
//     if (_isLoadingMaterial) {
//       return const Center(child: CircularProgressIndicator(color: AppColors.deepNavy));
//     }
    
//     if (_materialBills.isEmpty) {
//       return _buildEmptyState(
//         icon: Icons.receipt_long,
//         title: 'No Material Bills',
//         subtitle: 'Upload bills from material vendors',
//         onTap: () => _showMaterialBillDialog(),
//       );
//     }
    
//     return RefreshIndicator(
//       onRefresh: _loadMaterialBills,
//       color: AppColors.deepNavy,
//       child: ListView.builder(
//         padding: const EdgeInsets.all(16),
//         itemCount: _materialBills.length,
//         itemBuilder: (context, index) {
//           final bill = _materialBills[index];
//           return _buildMaterialBillCard(bill);
//         },
//       ),
//     );
//   }

//   Widget _buildVendorBillsTab() {
//     if (_isLoadingVendor) {
//       return const Center(child: CircularProgressIndicator(color: AppColors.deepNavy));
//     }
    
//     if (_vendorBills.isEmpty) {
//       return _buildEmptyState(
//         icon: Icons.business_center,
//         title: 'No Vendor Bills',
//         subtitle: 'Upload bills from service providers',
//         onTap: () => _showVendorBillDialog(),
//       );
//     }
    
//     return RefreshIndicator(
//       onRefresh: _loadVendorBills,
//       color: AppColors.deepNavy,
//       child: ListView.builder(
//         padding: const EdgeInsets.all(16),
//         itemCount: _vendorBills.length,
//         itemBuilder: (context, index) {
//           final bill = _vendorBills[index];
//           return _buildVendorBillCard(bill);
//         },
//       ),
//     );
//   }

//   Widget _buildAgreementsTab() {
//     if (_isLoadingAgreements) {
//       return const Center(child: CircularProgressIndicator(color: AppColors.deepNavy));
//     }
    
//     if (_agreements.isEmpty) {
//       return _buildEmptyState(
//         icon: Icons.description,
//         title: 'No Agreements',
//         subtitle: 'Upload signed agreements',
//         onTap: () => _showAgreementDialog(),
//       );
//     }
    
//     return RefreshIndicator(
//       onRefresh: _loadAgreements,
//       color: AppColors.deepNavy,
//       child: ListView.builder(
//         padding: const EdgeInsets.all(16),
//         itemCount: _agreements.length,
//         itemBuilder: (context, index) {
//           final agreement = _agreements[index];
//           return _buildAgreementCard(agreement);
//         },
//       ),
//     );
//   }

//   Widget _buildEmptyState({
//     required IconData icon,
//     required String title,
//     required String subtitle,
//     required VoidCallback onTap,
//   }) {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(icon, size: 80, color: AppColors.textSecondary),
//           const SizedBox(height: 16),
//           Text(
//             title,
//             style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepNavy),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             subtitle,
//             style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
//           ),
//           const SizedBox(height: 24),
//           ElevatedButton.icon(
//             onPressed: onTap,
//             icon: const Icon(Icons.upload_file),
//             label: const Text('Upload Now'),
//             style: ElevatedButton.styleFrom(
//               backgroundColor:AppColors.deepNavy,
//               foregroundColor: Colors.white,
//               padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildMaterialBillCard(Map<String, dynamic> bill) {
//     final paymentStatus = bill['payment_status'] ?? 'PENDING';
//     final statusColor = paymentStatus == 'PAID' 
//         ? Colors.green 
//         : paymentStatus == 'PARTIAL' 
//             ? Colors.orange 
//             : Colors.red;
    
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [AppColors.cardShadow],
//       ),
//       child: Material(
//         color: Colors.transparent,
//         child: InkWell(
//           onTap: () => _openDocument(bill['file_url']),
//           borderRadius: BorderRadius.circular(16),
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Container(
//                       width: 50,
//                       height: 50,
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF1A1A2E).withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: const Icon(Icons.receipt_long, color: const Color(0xFF1A1A2E), size: 30),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             bill['vendor_name'] ?? '',
//                             style: const TextStyle(
//                               fontSize: 16,
//                               fontWeight: FontWeight.bold,
//                               color: AppColors.deepNavy,
//                             ),
//                           ),
//                           const SizedBox(height: 4),
//                           Text(
//                             '${bill['vendor_type']} • ${bill['material_type']}',
//                             style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
//                           ),
//                         ],
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                       decoration: BoxDecoration(
//                         color: statusColor.withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: Text(
//                         paymentStatus,
//                         style: TextStyle(
//                           fontSize: 11,
//                           fontWeight: FontWeight.bold,
//                           color: statusColor,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 12),
//                 const Divider(height: 1),
//                 const SizedBox(height: 12),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           'Bill #${bill['bill_number']}',
//                           style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           bill['bill_date'] ?? '',
//                           style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
//                         ),
//                       ],
//                     ),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.end,
//                       children: [
//                         Text(
//                           '₹${bill['final_amount']?.toStringAsFixed(2) ?? '0.00'}',
//                           style: const TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: AppColors.deepNavy,
//                           ),
//                         ),
//                         Text(
//                           '${bill['quantity']} ${bill['unit']}',
//                           style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildVendorBillCard(Map<String, dynamic> bill) {
//     final paymentStatus = bill['payment_status'] ?? 'PENDING';
//     final statusColor = paymentStatus == 'PAID' 
//         ? Colors.green 
//         : paymentStatus == 'PARTIAL' 
//             ? Colors.orange 
//             : Colors.red;
    
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [AppColors.cardShadow],
//       ),
//       child: Material(
//         color: Colors.transparent,
//         child: InkWell(
//           onTap: () => _openDocument(bill['file_url']),
//           borderRadius: BorderRadius.circular(16),
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Container(
//                       width: 50,
//                       height: 50,
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF1A1A2E).withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: const Icon(Icons.business_center, color: Color(0xFF1A1A2E), size: 30),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             bill['vendor_name'] ?? '',
//                             style: const TextStyle(
//                               fontSize: 16,
//                               fontWeight: FontWeight.bold,
//                               color: AppColors.deepNavy,
//                             ),
//                           ),
//                           const SizedBox(height: 4),
//                           Text(
//                             '${bill['vendor_type']} • ${bill['service_type']}',
//                             style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
//                           ),
//                         ],
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                       decoration: BoxDecoration(
//                         color: statusColor.withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: Text(
//                         paymentStatus,
//                         style: TextStyle(
//                           fontSize: 11,
//                           fontWeight: FontWeight.bold,
//                           color: statusColor,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 12),
//                 const Divider(height: 1),
//                 const SizedBox(height: 12),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           'Bill #${bill['bill_number']}',
//                           style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           bill['bill_date'] ?? '',
//                           style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
//                         ),
//                       ],
//                     ),
//                     Text(
//                       '₹${bill['final_amount']?.toStringAsFixed(2) ?? '0.00'}',
//                       style: const TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.bold,
//                         color: AppColors.deepNavy,
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildAgreementCard(Map<String, dynamic> agreement) {
//     final status = agreement['status'] ?? 'ACTIVE';
//     final statusColor = status == 'ACTIVE' 
//         ? Colors.green 
//         : status == 'COMPLETED' 
//             ? const Color(0xFF1A1A2E) 
//             : Colors.grey;
    
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [AppColors.cardShadow],
//       ),
//       child: Material(
//         color: Colors.transparent,
//         child: InkWell(
//           onTap: () => _openDocument(agreement['file_url']),
//           borderRadius: BorderRadius.circular(16),
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Container(
//                       width: 50,
//                       height: 50,
//                       decoration: BoxDecoration(
//                         color: Colors.green.shade50,
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: const Icon(Icons.description, color: Colors.green, size: 30),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             agreement['title'] ?? '',
//                             style: const TextStyle(
//                               fontSize: 16,
//                               fontWeight: FontWeight.bold,
//                               color: AppColors.deepNavy,
//                             ),
//                             maxLines: 2,
//                             overflow: TextOverflow.ellipsis,
//                           ),
//                           const SizedBox(height: 4),
//                           Text(
//                             agreement['agreement_type'] ?? '',
//                             style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
//                           ),
//                         ],
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                       decoration: BoxDecoration(
//                         color: statusColor.withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: Text(
//                         status,
//                         style: TextStyle(
//                           fontSize: 11,
//                           fontWeight: FontWeight.bold,
//                           color: statusColor,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 12),
//                 const Divider(height: 1),
//                 const SizedBox(height: 12),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           agreement['party_name'] ?? '',
//                           style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           '${agreement['party_type']} • ${agreement['agreement_date']}',
//                           style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
//                         ),
//                       ],
//                     ),
//                     if (agreement['contract_value'] != null)
//                       Text(
//                         '₹${agreement['contract_value']?.toStringAsFixed(2) ?? '0.00'}',
//                         style: const TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           color: AppColors.deepNavy,
//                         ),
//                       ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   void _showUploadDialog() {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Upload Document'),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             ListTile(
//               leading: const Icon(Icons.receipt_long, color: const Color(0xFF1A1A2E)),
//               title: const Text('Material Bill'),
//               subtitle: const Text('From tiles shop, cement supplier, etc.'),
//               onTap: () {
//                 Navigator.pop(context);
//                 _showMaterialBillDialog();
//               },
//             ),
//             ListTile(
//               leading: const Icon(Icons.business_center, color: Color(0xFF1A1A2E)),
//               title: const Text('Vendor Bill'),
//               subtitle: const Text('From contractors, electricians, etc.'),
//               onTap: () {
//                 Navigator.pop(context);
//                 _showVendorBillDialog();
//               },
//             ),
//             ListTile(
//               leading: const Icon(Icons.description, color: Colors.green),
//               title: const Text('Site Agreement'),
//               subtitle: const Text('Signed agreements for new sites'),
//               onTap: () {
//                 Navigator.pop(context);
//                 _showAgreementDialog();
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   void _showMaterialBillDialog() {
//     showDialog(
//       context: context,
//       builder: (context) => MaterialBillUploadDialog(
//         siteId: widget.siteId,
//         siteName: widget.siteName,
//         onSuccess: () {
//           _loadMaterialBills();
//           _tabController.animateTo(0);
//         },
//       ),
//     );
//   }

//   void _showVendorBillDialog() {
//     showDialog(
//       context: context,
//       builder: (context) => VendorBillUploadDialog(
//         siteId: widget.siteId,
//         siteName: widget.siteName,
//         onSuccess: () {
//           _loadVendorBills();
//           _tabController.animateTo(1);
//         },
//       ),
//     );
//   }

//   void _showAgreementDialog() {
//     showDialog(
//       context: context,
//       builder: (context) => SiteAgreementUploadDialog(
//         siteId: widget.siteId,
//         siteName: widget.siteName,
//         onSuccess: () {
//           _loadAgreements();
//           _tabController.animateTo(2);
//         },
//       ),
//     );
//   }
// }
