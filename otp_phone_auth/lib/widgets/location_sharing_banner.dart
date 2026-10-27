import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';

/// Supervisor-facing status of location sharing with admins, shown above the
/// supervisor dashboard's bottom bar. Sharing is mandatory during work hours:
/// there is no way to switch it off in the app, the supervisor is asked to
/// turn it on whenever it's off, and admins are notified if GPS or the
/// permission is turned off. Hidden on web.
class LocationSharingBanner extends StatefulWidget {
  const LocationSharingBanner({super.key});

  @override
  State<LocationSharingBanner> createState() => _LocationSharingBannerState();
}

enum _SharingState { checking, on, paused, needsAlways, gpsOff, off }

class _LocationSharingBannerState extends State<LocationSharingBanner>
    with WidgetsBindingObserver {
  _SharingState _state = _SharingState.checking;
  Timer? _timer;
  bool _prompting = false;
  String? _lastReportedState;

  @override
  void initState() {
    super.initState();
    if (!LocationTrackingService.isSupported) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialise());
    // Re-check at the edges of working hours and if GPS is switched off
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the system settings page: permission/GPS may have changed
    if (state == AppLifecycleState.resumed) _refresh(restart: true);
  }

  Future<void> _initialise() async {
    await _refresh(restart: true);
    // Every time the dashboard opens: if sharing is off, ask to turn it on
    // (always on first use, so the supervisor sees the notice).
    final needsSetup = !await LocationTrackingService.hasConsent();
    final offInWorkHours = LocationTrackingService.isWorkingHours(DateTime.now()) &&
        (_state == _SharingState.off || _state == _SharingState.gpsOff);
    if (mounted && (needsSetup || offInWorkHours)) await _turnOn();
  }

  Future<void> _refresh({bool restart = false}) async {
    if (!mounted) return;
    final sharing = await LocationTrackingService.currentSharingState();
    final permission = await LocationTrackingService.permission();
    final consented = await LocationTrackingService.hasConsent();
    final workHours = LocationTrackingService.isWorkingHours(DateTime.now());

    // The background service reports too, but it isn't running if permission
    // was never granted — so the app reports what it sees as well.
    if (workHours && consented) _report(sharing);

    if (!consented || sharing == 'permission_denied') {
      _set(_SharingState.off);
      return;
    }
    if (restart) await LocationTrackingService.startIfAllowed();
    if (sharing == 'gps_off') {
      _set(_SharingState.gpsOff);
    } else if (permission == LocationPermission.whileInUse) {
      _set(_SharingState.needsAlways);
    } else if (!workHours) {
      _set(_SharingState.paused);
    } else {
      _set(_SharingState.on);
    }
  }

  Future<void> _report(String sharing) async {
    if (sharing == _lastReportedState) return;
    final token = await AuthService().getToken();
    if (token != null &&
        await LocationTrackingService.reportSharingState(sharing, token)) {
      _lastReportedState = sharing;
    }
  }

  void _set(_SharingState state) {
    if (mounted && state != _state) setState(() => _state = state);
  }

  /// Notice → permission → location services → start.
  Future<void> _turnOn() async {
    if (_prompting) return;
    _prompting = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _RequiredNoticeDialog(),
      );
      await LocationTrackingService.setConsent(true);

      final permission = await LocationTrackingService.requestPermissions();
      if (permission == LocationPermission.deniedForever && mounted) {
        final open = await _ask(
          'Location permission blocked',
          'Location sharing is required during work hours. Open settings and '
              'set Location to "Allow all the time".',
          'Open settings',
        );
        if (open) await Geolocator.openAppSettings();
      }
      if (!await Geolocator.isLocationServiceEnabled() && mounted) {
        final open = await _ask(
          'Turn on location',
          'Your phone\'s location (GPS) is off. It must be on during work hours.',
          'Open settings',
        );
        if (open) await Geolocator.openLocationSettings();
      }
      await _refresh(restart: true);
    } finally {
      _prompting = false;
    }
  }

  Future<bool> _ask(String title, String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showDetails() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Location sharing',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ..._RequiredNoticeDialog.points.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(p.$1, size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.$2)),
                    ],
                  ),
                ),
              ),
              if (_state == _SharingState.needsAlways)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings),
                  title: const Text('Allow "all the time"'),
                  subtitle: const Text(
                    'Needed so sharing continues while the app is closed',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Geolocator.openAppSettings();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!LocationTrackingService.isSupported || _state == _SharingState.checking) {
      return const SizedBox.shrink();
    }

    final workHours = LocationTrackingService.isWorkingHours(DateTime.now());
    final (color, icon, text, action) = switch (_state) {
      _SharingState.on => (
          const Color(0xFF059669),
          Icons.my_location,
          'Sharing your location with admin until 7 PM',
          null,
        ),
      _SharingState.paused => (
          const Color(0xFF6B7280),
          Icons.pause_circle_outline,
          'Location sharing paused · resumes in work hours '
              '(${LocationTrackingService.workHoursLabel})',
          null,
        ),
      _SharingState.needsAlways => (
          const Color(0xFFD97706),
          Icons.warning_amber_rounded,
          'Location shared only while the app is open. Tap to allow all the time.',
          null,
        ),
      _SharingState.gpsOff => (
          const Color(0xFFDC2626),
          Icons.gps_off,
          workHours
              ? 'GPS is off · required until 7 PM. Admin has been notified.'
              : 'GPS is off · it must be on during work hours.',
          'Turn on',
        ),
      _ => (
          const Color(0xFFDC2626),
          Icons.location_off,
          workHours
              ? 'Location sharing is required until 7 PM. Admin has been notified.'
              : 'Location sharing is required during work hours.',
          'Turn on',
        ),
    };
    final isOff = _state == _SharingState.off || _state == _SharingState.gpsOff;

    return Material(
      color: color.withValues(alpha: 0.1),
      child: InkWell(
        onTap: isOff ? _turnOn : _showDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (action != null)
                Text(
                  action,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                )
              else
                Icon(Icons.info_outline, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notice shown before asking for location permission. Sharing is required
/// for supervisors during work hours, so there is no "Not now".
class _RequiredNoticeDialog extends StatelessWidget {
  const _RequiredNoticeDialog();

  static const points = [
    (Icons.schedule, 'Required during work hours: ${LocationTrackingService.workHoursLabel}. Never shared outside them.'),
    (Icons.admin_panel_settings_outlined, 'Only admins can see it, and only your latest position. No route history is kept.'),
    (Icons.phonelink_lock, 'Continues while the app is closed, with a notification showing that sharing is on.'),
    (Icons.notifications_active_outlined, 'If GPS or the location permission is turned off during work hours, admins are notified.'),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.location_on, size: 36, color: Color(0xFF059669)),
        title: const Text('Location sharing is required'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Supervisors share their location with admins during work hours '
                'so site work can be coordinated.',
              ),
              const SizedBox(height: 14),
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(p.$1, size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.$2, style: const TextStyle(fontSize: 13.5))),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Next, choose "Allow all the time" when your phone asks.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
