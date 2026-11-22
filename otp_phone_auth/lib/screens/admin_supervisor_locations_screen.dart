import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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
  List<Map<String, dynamic>> _sites = [];
  bool _workingHoursNow = false;

  // Pin mode: the admin picked a site and is placing it on the map
  Map<String, dynamic>? _pinningSite;
  LatLng? _pendingPin;
  double _pinRadius = 150;
  bool _savingPin = false;
  static const _siteColor = Color(0xFFEA580C);
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
        _sites = List<Map<String, dynamic>>.from(
          ((data['sites'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
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

  List<Map<String, dynamic>> get _pinnedSites =>
      _sites.where((s) => s['latitude'] != null).toList();

  void _fitToPinsOnce() {
    if (_fittedOnce) return;
    final points = [..._located.map(_point), ..._pinnedSites.map(_point)];
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

  /// "At Sudesh house" / "1.2 km from Sudesh house", or null if no site is pinned.
  String? _siteText(Map<String, dynamic> s) {
    final near = s['nearest_site'] as Map?;
    if (near == null) return null;
    if (near['inside'] == true) return 'At ${near['name']}';
    final m = (near['distance_m'] as num).toDouble();
    final distance = m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
    return '$distance from ${near['name']}';
  }

  // ── Site pins ───────────────────────────────────────────────

  Future<void> _chooseSiteToPin() async {
    final site = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('Which site do you want to pin?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _navy)),
            ),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: _sites.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final site = _sites[i];
                  final pinned = site['latitude'] != null;
                  return ListTile(
                    leading: Icon(pinned ? Icons.home_work : Icons.home_work_outlined,
                        color: pinned ? _siteColor : Colors.grey),
                    title: Text(site['name'] ?? 'Site',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([site['area'], site['street']]
                        .where((e) => (e ?? '').toString().isNotEmpty)
                        .join(' · ')),
                    trailing: Text(pinned ? 'Pinned · move' : 'Not pinned',
                        style: TextStyle(
                            fontSize: 12, color: pinned ? _siteColor : Colors.grey.shade600)),
                    onTap: () => Navigator.pop(context, site),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (site != null) _startPinning(site);
  }

  void _startPinning(Map<String, dynamic> site) {
    final pinned = site['latitude'] != null;
    setState(() {
      _pinningSite = site;
      _pendingPin = pinned ? _point(site) : null;
      _pinRadius = ((site['radius_m'] as num?) ?? 150).toDouble().clamp(50, 500);
    });
    if (pinned) _mapController.move(_point(site), 17);
  }

  void _cancelPinning() => setState(() {
        _pinningSite = null;
        _pendingPin = null;
      });

  /// For when the admin is standing at the site.
  Future<void> _useMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Allow location access to use your position');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 20));
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() => _pendingPin = here);
      _mapController.move(here, 17);
    } catch (e) {
      _snack('Could not get your location: ${e.toString().replaceFirst('Exception: ', '')}',
          error: true);
    }
  }

  Future<void> _savePin() async {
    final site = _pinningSite;
    final pin = _pendingPin;
    if (site == null || pin == null) return;
    setState(() => _savingPin = true);
    try {
      await _sendSiteLocation(site['id'], 'POST', {
        'latitude': pin.latitude,
        'longitude': pin.longitude,
        'radius_m': _pinRadius.round(),
      });
      _snack('📍 ${site['name']} pinned');
      _cancelPinning();
      await _load();
    } catch (e) {
      _snack('Not saved: ${e.toString().replaceFirst('Exception: ', '')}', error: true);
    } finally {
      if (mounted) setState(() => _savingPin = false);
    }
  }

  Future<void> _removePin(Map<String, dynamic> site) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove the pin for ${site['name']}?'),
        content: const Text('Supervisors will no longer show as being at this site.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sendSiteLocation(site['id'], 'DELETE');
      _snack('Pin removed');
      await _load();
    } catch (e) {
      _snack('Could not remove: ${e.toString().replaceFirst('Exception: ', '')}', error: true);
    }
  }

  Future<void> _sendSiteLocation(String siteId, String method, [Map<String, dynamic>? body]) async {
    final token = await _authService.getToken();
    final request = http.Request(method, Uri.parse('${AuthService.baseUrl}/admin/sites/$siteId/location/'))
      ..headers.addAll({
        'Authorization': 'Bearer ${token ?? ''}',
        'Content-Type': 'application/json',
      });
    if (body != null) request.body = json.encode(body);
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 30)),
    );
    if (response.statusCode != 200) {
      String message = 'Failed (${response.statusCode})';
      try {
        message = (json.decode(response.body) as Map)['error'] ?? message;
      } catch (_) {}
      throw Exception(message);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red : const Color(0xFF059669),
    ));
  }

  void _showSite(Map<String, dynamic> site) {
    final here = _supervisors
        .where((s) => (s['nearest_site'] as Map?)?['id'] == site['id'] &&
            (s['nearest_site'] as Map?)?['inside'] == true)
        .toList();
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
              Row(
                children: [
                  const Icon(Icons.home_work, color: _siteColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(site['name'] ?? 'Site',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${[site['area'], site['street']].where((e) => (e ?? '').toString().isNotEmpty).join(' · ')}'
                ' · radius ${site['radius_m']} m',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(
                here.isEmpty
                    ? 'No supervisor at this site right now'
                    : 'At this site: ${here.map((s) => s['name']).join(', ')}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: here.isEmpty ? Colors.grey.shade700 : const Color(0xFF059669),
                ),
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: const Text('Move pin / change radius'),
                onTap: () {
                  Navigator.pop(context);
                  _startPinning(site);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.map_outlined),
                title: const Text('Open in Google Maps'),
                onTap: () => launchUrl(
                  Uri.parse('https://www.google.com/maps/search/?api=1&query='
                      '${site['latitude']},${site['longitude']}'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wrong_location_outlined, color: Colors.red),
                title: const Text('Remove pin', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removePin(site);
                },
              ),
            ],
          ),
        ),
      ),
    );
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
              if (_siteText(s) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('📍 ${_siteText(s)}',
                      style: const TextStyle(color: _siteColor, fontWeight: FontWeight.w600)),
                ),
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
          TextButton.icon(
            onPressed: _sites.isEmpty || _pinningSite != null ? null : _chooseSiteToPin,
            icon: const Icon(Icons.add_location_alt, color: Colors.white),
            label: const Text('Pin site', style: TextStyle(color: Colors.white)),
          ),
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

    // Sites (the one being moved is drawn at its new spot instead)
    final shownSites = _pinnedSites.where((s) => s['id'] != _pinningSite?['id']).toList();
    final circles = [
      for (final site in shownSites)
        CircleMarker(
          point: _point(site),
          radius: ((site['radius_m'] as num?) ?? 150).toDouble(),
          useRadiusInMeter: true,
          color: _siteColor.withValues(alpha: 0.12),
          borderColor: _siteColor.withValues(alpha: 0.6),
          borderStrokeWidth: 1.5,
        ),
      if (_pendingPin != null)
        CircleMarker(
          point: _pendingPin!,
          radius: _pinRadius,
          useRadiusInMeter: true,
          color: _siteColor.withValues(alpha: 0.2),
          borderColor: _siteColor,
          borderStrokeWidth: 2,
        ),
    ];
    final siteMarkers = [
      for (final site in shownSites)
        Marker(
          point: _point(site),
          width: 130,
          height: 58,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: _pinningSite == null ? () => _showSite(site) : null,
            child: _siteLabel(site['name'] ?? 'Site', Icons.home_work),
          ),
        ),
      if (_pendingPin != null)
        Marker(
          point: _pendingPin!,
          width: 130,
          height: 58,
          alignment: Alignment.topCenter,
          child: _siteLabel(_pinningSite?['name'] ?? 'Site', Icons.add_home_work),
        ),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _chennai,
            initialZoom: 11,
            onTap: (_, point) {
              if (_pinningSite != null) setState(() => _pendingPin = point);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.essentialhomes.construction',
            ),
            CircleLayer(circles: circles),
            MarkerLayer(markers: siteMarkers),
            MarkerLayer(markers: markers),
            const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
          ],
        ),
        if (_pinningSite != null) ...[
          Positioned(top: 8, left: 8, right: 8, child: _buildPinHint()),
          Positioned(bottom: 8, left: 8, right: 8, child: _buildPinPanel()),
        ],
      ],
    );
  }

  Widget _siteLabel(String name, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _siteColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        Icon(icon, color: _siteColor, size: 30),
      ],
    );
  }

  Widget _buildPinHint() {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: _navy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.touch_app, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tap the map where ${_pinningSite!['name']} is',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: _savingPin ? null : _cancelPinning,
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinPanel() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Site radius', style: TextStyle(fontWeight: FontWeight.w600, color: _navy)),
                Expanded(
                  child: Slider(
                    value: _pinRadius,
                    min: 50,
                    max: 500,
                    divisions: 18,
                    activeColor: _siteColor,
                    label: '${_pinRadius.round()} m',
                    onChanged: (v) => setState(() => _pinRadius = v),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text('${_pinRadius.round()} m',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _savingPin ? null : _useMyLocation,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text("I'm at the site"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pendingPin == null || _savingPin ? null : _savePin,
                    style: FilledButton.styleFrom(backgroundColor: _siteColor),
                    icon: _savingPin
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Save pin'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
            subtitle: Text.rich(TextSpan(children: [
              TextSpan(text: _statusText(s), style: TextStyle(color: color)),
              if (_siteText(s) != null)
                TextSpan(
                  text: '\n📍 ${_siteText(s)}',
                  style: const TextStyle(color: _siteColor, fontWeight: FontWeight.w600),
                ),
            ])),
            trailing: s['latitude'] != null ? const Icon(Icons.chevron_right) : null,
            onTap: s['latitude'] != null ? () => _focus(s) : null,
          );
        },
      ),
    );
  }
}
