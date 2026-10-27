import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'admin_site_full_view.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SimpleBudgetScreen extends StatefulWidget {
  const SimpleBudgetScreen({Key? key}) : super(key: key);

  @override
  State<SimpleBudgetScreen> createState() => _SimpleBudgetScreenState();
}

class _SimpleBudgetScreenState extends State<SimpleBudgetScreen> {
  final _authService = AuthService();
  static const String baseUrl = 'http://192.168.1.6:8001/api';

  // Cascading dropdown state
  String? _selectedArea;
  String? _selectedStreet;
  String? _selectedSiteId;

  // Data lists
  List<String> _areas = [];
  List<String> _streets = [];
  List<Map<String, dynamic>> _sites = [];

  // Loading states
  bool _isLoadingAreas = false;
  bool _isLoadingStreets = false;
  bool _isLoadingSites = false;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoadingAreas = true);

    try {
      final token = await _authService.getToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authentication required. Please login again.')),
          );
        }
        return;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/construction/areas/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _areas = List<String>.from(data['areas'] ?? []);
        });

        if (_areas.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No areas found. Please create an area first.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load areas: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading areas: $e')),
        );
      }
    } finally {
      setState(() => _isLoadingAreas = false);
    }
  }

  Future<void> _loadStreets(String area) async {
    setState(() {
      _isLoadingStreets = true;
      _selectedStreet = null;
      _selectedSiteId = null;
      _streets = [];
      _sites = [];
    });

    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/construction/streets/${Uri.encodeComponent(area)}/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _streets = List<String>.from(data['streets'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading streets: $e');
    } finally {
      setState(() => _isLoadingStreets = false);
    }
  }

  Future<void> _loadSites(String area, String street) async {
    setState(() {
      _isLoadingSites = true;
      _selectedSiteId = null;
      _sites = [];
    });

    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/construction/sites/?area=${Uri.encodeComponent(area)}&street=${Uri.encodeComponent(street)}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _sites = List<Map<String, dynamic>>.from(data['sites'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading sites: $e');
    } finally {
      setState(() => _isLoadingSites = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCascadingDropdowns(),
        ],
      ),
    );
  }

  Widget _buildCascadingDropdowns() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Loading indicator
            if (_isLoadingAreas)
              Padding(
                padding: EdgeInsets.all(16.r),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),

            // Area Dropdown
            DropdownButtonFormField<String>(
              value: _areas.isEmpty ? null : (_areas.contains(_selectedArea) ? _selectedArea : null),
              decoration: const InputDecoration(
                labelText: 'Select Area',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_city),
              ),
              hint: const Text('Select Area'),
              isExpanded: true,
              items: _areas.isEmpty
                  ? null
                  : _areas.map((area) {
                      return DropdownMenuItem<String>(
                        value: area,
                        child: Text(area),
                      );
                    }).toList(),
              onChanged: _isLoadingAreas
                  ? null
                  : (area) {
                      setState(() {
                        _selectedArea = area;
                        _selectedStreet = null;
                        _selectedSiteId = null;
                        _streets = [];
                        _sites = [];
                      });
                      if (area != null) {
                        _loadStreets(area);
                      }
                    },
            ),

            SizedBox(height: 16.h),

            // Street Dropdown
            if (_isLoadingStreets)
              Padding(
                padding: EdgeInsets.all(16.r),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),

            DropdownButtonFormField<String>(
              value: _streets.isEmpty ? null : (_streets.contains(_selectedStreet) ? _selectedStreet : null),
              decoration: const InputDecoration(
                labelText: 'Select Street',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.signpost),
              ),
              hint: const Text('Select Street'),
              isExpanded: true,
              items: _streets.isEmpty
                  ? null
                  : _streets.map((street) {
                      return DropdownMenuItem<String>(
                        value: street,
                        child: Text(street),
                      );
                    }).toList(),
              onChanged: _selectedArea == null || _isLoadingStreets
                  ? null
                  : (street) {
                      setState(() {
                        _selectedStreet = street;
                        _selectedSiteId = null;
                        _sites = [];
                      });
                      if (street != null && _selectedArea != null) {
                        _loadSites(_selectedArea!, street);
                      }
                    },
            ),

            SizedBox(height: 16.h),

            // Site Dropdown
            if (_isLoadingSites)
              Padding(
                padding: EdgeInsets.all(16.r),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),

            DropdownButtonFormField<String>(
              value: _sites.isEmpty ? null : (_sites.any((s) => s['id'] == _selectedSiteId) ? _selectedSiteId : null),
              decoration: const InputDecoration(
                labelText: 'Select Site',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              hint: const Text('Select Site'),
              isExpanded: true,
              items: _sites.isEmpty
                  ? null
                  : _sites.map((site) {
                      return DropdownMenuItem<String>(
                        value: site['id'],
                        child: Text(site['display_name'] ?? site['site_name'] ?? 'Unknown Site'),
                      );
                    }).toList(),
              onChanged: _selectedStreet == null || _isLoadingSites
                  ? null
                  : (siteId) {
                      if (siteId != null) {
                        final site = _sites.firstWhere((s) => s['id'] == siteId);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminSiteFullView(
                              siteId: siteId,
                              siteName: site['display_name'] ?? site['site_name'] ?? 'Unknown',
                            ),
                          ),
                        );
                      }
                    },
            ),

            SizedBox(height: 16.h),

            // Create New Button
            ElevatedButton.icon(
              onPressed: () => _showCreateDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Create New Area / Street / Site'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.safetyOrange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16.h),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_city),
              title: const Text('Create New Area'),
              onTap: () {
                Navigator.pop(context);
                _showCreateAreaDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.signpost),
              title: const Text('Create New Street'),
              onTap: () {
                Navigator.pop(context);
                _showCreateStreetDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Create New Site'),
              onTap: () {
                Navigator.pop(context);
                _showCreateSiteDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateAreaDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Area'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Area Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context);
                await _createArea(controller.text);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCreateStreetDialog() {
    if (_selectedArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an area first')),
      );
      return;
    }

    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Street in $_selectedArea'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Street Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context);
                await _createStreet(_selectedArea!, controller.text);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCreateSiteDialog() {
    if (_selectedArea == null || _selectedStreet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select area and street first')),
      );
      return;
    }

    final nameController = TextEditingController();
    final cityController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Site in $_selectedArea, $_selectedStreet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Site Name',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: cityController,
              decoration: const InputDecoration(
                labelText: 'City',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                Navigator.pop(context);
                await _createSite(
                  nameController.text,
                  _selectedArea!,
                  _selectedStreet!,
                  cityController.text,
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createArea(String areaName) async {
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/construction/create-area/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
        body: json.encode({'area': areaName}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Area "$areaName" created successfully')),
          );
          _loadAreas();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating area: $e')),
        );
      }
    }
  }

  Future<void> _createStreet(String area, String streetName) async {
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/construction/create-street/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
        body: json.encode({'area': area, 'street': streetName}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Street "$streetName" created successfully')),
          );
          _loadStreets(area);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating street: $e')),
        );
      }
    }
  }

  Future<void> _createSite(String siteName, String area, String street, String city) async {
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/construction/create-site/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? ''}',
        },
        body: json.encode({
          'site_name': siteName,
          'area': area,
          'street': street,
          'city': city,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Site "$siteName" created successfully')),
          );
          _loadSites(area, street);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating site: $e')),
        );
      }
    }
  }
}
