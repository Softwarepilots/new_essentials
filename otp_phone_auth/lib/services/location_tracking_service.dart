import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Supervisor live location, shared with admins during working hours only.
///
/// Runs as an Android foreground service (with a permanent notification), so
/// it keeps going after the app is closed and restarts after a reboot. It stops
/// on logout, when consent is withdrawn, or when the session expires. On iOS it
/// keeps running while the app is in the background, but iOS stops it if the
/// supervisor swipes the app away. Not available on web.
///
/// Backend: POST /api/location/update/ (django-backend/api/views_location.py),
/// which also refuses updates outside working hours.
class LocationTrackingService {
  static const consentKey = 'location_sharing_consent';

  // Keep in sync with django-backend/api/views_location.py
  static const workDays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
  };
  static const workStartHour = 8;
  static const workEndHour = 19;
  static const workHoursLabel = 'Mon–Sat, 8 AM – 7 PM';

  static const sendInterval = Duration(minutes: 5);
  static const distanceFilterMeters = 100;

  static const _supervisorRole = 'supervisor';
  static const _notificationId = 7351;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Working hours are defined in India time, whatever the phone's timezone.
  static bool isWorkingHours(DateTime when) {
    final ist = when.toUtc().add(const Duration(hours: 5, minutes: 30));
    return workDays.contains(ist.weekday) &&
        ist.hour >= workStartHour &&
        ist.hour < workEndHour;
  }

  /// Call once from main(). Does not start tracking.
  static Future<void> configure() async {
    if (!isSupported) return;
    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: locationServiceOnStart,
        autoStart: false,
        autoStartOnBoot: true, // onStart stops itself unless a consenting supervisor is logged in
        isForegroundMode: true,
        initialNotificationTitle: 'Essential Homes',
        initialNotificationContent: 'Location sharing with admin is starting…',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: locationServiceOnStart,
        onBackground: _iosOnBackground,
      ),
    );
  }

  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(consentKey) ?? false;
  }

  static Future<void> setConsent(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(consentKey, value);
    if (!value) await stop();
  }

  /// Current permission state, for the supervisor's status banner.
  static Future<LocationPermission> permission() => Geolocator.checkPermission();

  /// Asks for location permission, then "Allow all the time" so tracking
  /// survives the app being closed. Returns the resulting permission.
  static Future<LocationPermission> requestPermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      // Second request upgrades to "always" (Android opens the settings page
      // on Android 11+; iOS shows the "Change to Always Allow" prompt).
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  // Sharing states reported to POST /api/location/status/
  static const stateOk = 'ok';

  /// 'ok', 'gps_off' or 'permission_denied'.
  static Future<String> currentSharingState() async {
    if (!await Geolocator.isLocationServiceEnabled()) return 'gps_off';
    final permission = await Geolocator.checkPermission();
    return (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse)
        ? stateOk
        : 'permission_denied';
  }

  /// Tells the backend (and so the admins) whether sharing works. The backend
  /// ignores reports outside working hours. Returns false if it couldn't send.
  static Future<bool> reportSharingState(String state, String token) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/location/status/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'state': state}),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Location] status report failed: $e');
      return false;
    }
  }

  /// Called just before logout: a supervisor logging out during work hours
  /// stops sharing, so admins are told.
  static Future<void> reportLogout() async {
    if (!isSupported || !isWorkingHours(DateTime.now())) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userJson = prefs.getString('current_user');
    if (token == null || userJson == null) return;
    try {
      final role = (json.decode(userJson)['role'] ?? '').toString().toLowerCase().trim();
      if (role != _supervisorRole) return;
    } catch (_) {
      return;
    }
    await reportSharingState('logged_out', token);
  }

  static Future<bool> isRunning() async =>
      isSupported && await FlutterBackgroundService().isRunning();

  /// Starts sharing if the supervisor consented and location is permitted.
  static Future<bool> startIfAllowed() async {
    if (!isSupported || !await hasConsent()) return false;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return false;
    }
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) await service.startService();
    return true;
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    final service = FlutterBackgroundService();
    if (await service.isRunning()) service.invoke('stop');
  }
}

@pragma('vm:entry-point')
Future<bool> _iosOnBackground(ServiceInstance service) async => true;

/// Entry point of the background service (its own isolate on Android).
@pragma('vm:entry-point')
Future<void> locationServiceOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stop').listen((_) => service.stopSelf());

  final prefs = await SharedPreferences.getInstance();

  // Re-read login state each time: the app (another isolate) may have logged out.
  Future<String?> supervisorToken() async {
    await prefs.reload();
    if (!(prefs.getBool(LocationTrackingService.consentKey) ?? false)) return null;
    final token = prefs.getString('auth_token');
    final userJson = prefs.getString('current_user');
    if (token == null || userJson == null) return null;
    try {
      final role = (json.decode(userJson)['role'] ?? '').toString().toLowerCase().trim();
      return role == LocationTrackingService._supervisorRole ? token : null;
    } catch (_) {
      return null;
    }
  }

  if (await supervisorToken() == null) {
    await service.stopSelf();
    return;
  }

  void setNotification(String content) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Essential Homes – location sharing',
        content: content,
      );
    }
  }

  StreamSubscription<Position>? movementSub;
  DateTime? lastSent;
  String? lastReportedState;
  var sending = false;

  Future<void> send(Position position) async {
    if (sending) return;
    sending = true;
    try {
      final token = await supervisorToken();
      if (token == null) {
        await service.stopSelf();
        return;
      }
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/location/update/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'latitude': position.latitude,
              'longitude': position.longitude,
              'accuracy': position.accuracy,
              'recorded_at': position.timestamp.toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 || response.statusCode == 403) {
        // Session expired or not a supervisor any more: stop until next login
        await service.stopSelf();
        return;
      }
      if (response.statusCode == 200) {
        lastSent = DateTime.now();
        final time = TimeOfDay.fromDate(lastSent!);
        setNotification('Sharing with admin during work hours · last update $time');
      }
    } catch (e) {
      debugPrint('[Location] send failed: $e'); // retried on the next tick
    } finally {
      sending = false;
    }
  }

  Future<void> sendCurrent() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 45),
        ),
      );
      await send(position);
    } catch (e) {
      debugPrint('[Location] fix failed: $e');
    }
  }

  void startMovementUpdates() {
    const distance = LocationTrackingService.distanceFilterMeters;
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.iOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distance,
            activityType: ActivityType.otherNavigation,
            allowBackgroundLocationUpdates: true,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true, // blue status-bar pill
          )
        : AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distance,
            intervalDuration: const Duration(minutes: 1),
          );
    movementSub ??= Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        // Moved 100 m+; don't flood if GPS jitters right after a send
        final last = lastSent;
        if (last == null ||
            DateTime.now().difference(last) > const Duration(seconds: 60)) {
          send(position);
        }
      },
      onError: (e) => debugPrint('[Location] stream error: $e'),
    );
  }

  Future<void> tick() async {
    if (await supervisorToken() == null) {
      await service.stopSelf();
      return;
    }
    if (!LocationTrackingService.isWorkingHours(DateTime.now())) {
      await movementSub?.cancel();
      movementSub = null;
      setNotification(
        'Paused outside work hours (${LocationTrackingService.workHoursLabel})',
      );
      return;
    }
    // Sharing is mandatory in work hours: tell admins if GPS or permission is off
    final state = await LocationTrackingService.currentSharingState();
    if (state != lastReportedState) {
      final token = await supervisorToken();
      if (token != null &&
          await LocationTrackingService.reportSharingState(state, token)) {
        lastReportedState = state;
      }
    }
    if (state != LocationTrackingService.stateOk) {
      await movementSub?.cancel();
      movementSub = null;
      setNotification(state == 'gps_off'
          ? 'Location (GPS) is off — admin has been notified. Please turn it on.'
          : 'Location permission removed — admin has been notified.');
      return;
    }

    startMovementUpdates();
    final last = lastSent;
    if (last == null ||
        DateTime.now().difference(last) >=
            LocationTrackingService.sendInterval - const Duration(seconds: 30)) {
      await sendCurrent();
    }
  }

  setNotification('Sharing with admin during work hours');
  await tick();
  // Minute tick: switches on/off at the edges of working hours and sends at
  // least every 5 minutes; movement of 100 m+ sends immediately.
  Timer.periodic(const Duration(minutes: 1), (_) => tick());
}

/// Minimal "HH:MM" formatter usable in the background isolate.
class TimeOfDay {
  final int hour;
  final int minute;
  TimeOfDay.fromDate(DateTime d) : hour = d.hour, minute = d.minute;
  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
