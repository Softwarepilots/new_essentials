import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

/// Admin view of supervisors' latest locations (shared during work hours).
/// Backend: GET /api/admin/supervisor-locations/ (api/views_location.py)
class AdminSupervisorLocationsScreen extends StatefulWidget {
  const AdminSupervisorLocationsScreen({super.key});

  @override
  State<AdminSupervisorLocationsScreen> createState() =>
      _AdminSupervisorLocationsScreenState();
}

class _AdminSupervisorLocationsScreenState
    extends State<AdminSupervisorLocationsScreen> {
  static const _navy = Color(0xFF1A1A2E);
  static const _chennai = LatLng(13.0827, 80.2707);

  final _authService = AuthService();
  final _mapController = MapController();
  Timer? _refreshTimer;

  List<Map<String, dynamic>> _supervisors = [];
  bool _workingHoursNow = false;
  String _workingHours = '';
  bool _loading = true;
  String? _error;
  bool _fittedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final token = await _authService.getToken();
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/admin/supervisor-locations/'),
        headers: {'Authorization': 'Bearer ${token ?? ''}'},
      ).timeout(const Duration(seconds: 30));
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? data['detail'] ?? 'Failed (${response.statusCode})');
      }
      if (!mounted) return;
      setState(() {
        _supervisors = List<Map<String, dynamic>>.from(
          (data['supervisors'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _workingHoursNow = data['working_hours_now'] == true;
        _workingHours = data['working_hours'] ?? '';
        _error = null;
        _loading = false;
      });
      _fitToPinsOnce();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _located =>
      _supervisors.where((s) => s['latitude'] != null).toList();

  LatLng _point(Map<String, dynamic> s) =>
      LatLng((s['latitude'] as num).toDouble(), (s['longitude'] as num).toDouble());

  void _fitToPinsOnce() {
    if (_fittedOnce) return;
    final points = _located.map(_point).toList();
    if (points.isEmpty) return;
    _fittedOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (points.length == 1) {
        _mapController.move(points.first, 15);
      } else {
        _mapController.fitCamera(
          CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48)),
        );
      }
    });
  }

  Color _statusColor(String status) => switch (status) {
        'live' => const Color(0xFF059669),
        'stale' => const Color(0xFFD97706),
        'off' => const Color(0xFFDC2626),
        _ => Colors.grey,
      };

  String _ago(DateTime time) {
    final ago = DateTime.now().difference(time.toLocal());
    return ago.inMinutes < 1
        ? 'just now'
        : ago.inMinutes < 60
            ? '${ago.inMinutes} min ago'
            : ago.inHours < 24
                ? '${ago.inHours} h ago'
                : '${ago.inDays} d ago';
  }

  String _statusText(Map<String, dynamic> s) {
    if (s['status'] == 'off') {
      final since = DateTime.tryParse(s['off_since'] ?? '');
      return 'Location off — ${s['off_reason'] ?? 'stopped sharing'}'
          '${since != null ? ' (${_ago(since)})' : ''}';
    }
    final recorded = DateTime.tryParse(s['recorded_at'] ?? '');
    if (recorded == null) return 'No location shared yet';
    return s['status'] == 'live' ? 'Live · ${_ago(recorded)}' : 'Last seen ${_ago(recorded)}';
  }

  void _focus(Map<String, dynamic> s) {
    if (s['latitude'] == null) return;
    _mapController.move(_point(s), 16);
    _showSupervisor(s);
  }

  void _showSupervisor(Map<String, dynamic> s) {
    final phone = (s['phone'] ?? '').toString();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s['name'] ?? 'Supervisor',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 4),
              Text(_statusText(s),
                  style: TextStyle(color: _statusColor(s['status'] ?? ''), fontWeight: FontWeight.w600)),
              if (s['accuracy_m'] != null)
                Text('Accuracy ±${(s['accuracy_m'] as num).round()} m',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 8),
              if (s['latitude'] != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Open in Google Maps'),
                  onTap: () => launchUrl(
                    Uri.parse('https://www.google.com/maps/search/?api=1&query='
                        '${s['latitude']},${s['longitude']}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              if (phone.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.call_outlined),
                  title: Text('Call $phone'),
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supervisor Locations',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _navy,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHoursBar(),
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!),
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    actions: [TextButton(onPressed: _load, child: const Text('Retry'))],
                  ),
                Expanded(flex: 3, child: _buildMap()),
                Expanded(flex: 2, child: _buildList()),
              ],
            ),
    );
  }

  Widget _buildHoursBar() {
    final color = _workingHoursNow ? const Color(0xFF059669) : Colors.grey.shade700;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        _workingHoursNow
            ? 'Work hours now ($_workingHours) · locations update every 5 min'
            : 'Outside work hours ($_workingHours) · showing last known locations',
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildMap() {
    final markers = _located.map((s) {
      final color = _statusColor(s['status'] ?? '');
      final name = (s['name'] ?? '?').toString();
      return Marker(
        point: _point(s),
        width: 120,
        height: 64,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () => _showSupervisor(s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navy),
                ),
              ),
              Icon(Icons.location_on, color: color, size: 36),
            ],
          ),
        ),
      );
    }).toList();

    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(initialCenter: _chennai, initialZoom: 11),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.essentialhomes.construction',
        ),
        MarkerLayer(markers: markers),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }

  Widget _buildList() {
    if (_supervisors.isEmpty) {
      return const Center(child: Text('No supervisors found'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _supervisors.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = _supervisors[i];
          final color = _statusColor(s['status'] ?? '');
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(
                s['latitude'] != null ? Icons.person_pin_circle : Icons.location_off,
                color: color,
              ),
            ),
            title: Text(s['name'] ?? 'Supervisor',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_statusText(s), style: TextStyle(color: color)),
            trailing: s['latitude'] != null ? const Icon(Icons.chevron_right) : null,
            onTap: s['latitude'] != null ? () => _focus(s) : null,
          );
        },
      ),
    );
  }
}
