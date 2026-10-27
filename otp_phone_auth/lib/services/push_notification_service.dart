import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';
import 'notification_navigation_service.dart';

// Must be top-level for Firebase background processing
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs (FlutterFire handles it).
  // Nothing extra needed — the local notification is shown by the OS automatically
  // when the app is in background/terminated because the FCM payload includes a
  // notification block. For data-only payloads you would show one here.
  debugPrint('[FCM] background message: ${message.messageId}');
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  // Getter, not a field: FirebaseMessaging.instance throws on web, where
  // Firebase is never initialised, even though initialise() bails out there.
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  final _notificationService = NotificationService();

  static const _channelId = 'essential_homes_alerts';
  static const _channelName = 'Essential Homes Alerts';
  static const _channelDesc =
      'Site updates, guest check-ins, and admin alerts';

  bool _initialised = false;

  /// Call once after Firebase.initializeApp() — safe to call multiple times.
  Future<void> initialise() async {
    if (_initialised || kIsWeb) return;
    _initialised = true;

    // 1. Request permission (Android 13+ / iOS)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[FCM] notifications permission denied');
      return;
    }

    // 2. Set foreground presentation on iOS
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. Create Android notification channel
    await _createChannel();

    // 4. Initialise flutter_local_notifications
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    // 5. Register FCM token with backend
    await _registerToken();

    // Refresh token when it rotates
    _messaging.onTokenRefresh.listen((token) {
      _notificationService.registerFcmToken(token);
    });

    // 6. Foreground messages → show local banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 7. Background / terminated taps are handled by the OS notification;
    //    onMessageOpenedApp fires when the user taps a background notification.
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

    // Terminated-state tap
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onNotificationTap(initial);
  }

  Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('[FCM] token: $token');
        await _notificationService.registerFcmToken(token);
      }
    } catch (e) {
      debugPrint('[FCM] token registration error: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await showLocalNotification(
      title: n.title ?? 'Essential Homes',
      body: n.body ?? '',
      payload: message.data['type'],
    );
  }

  void _onNotificationTap(RemoteMessage message) {
    debugPrint('[FCM] notification tapped: ${message.data}');
    final type = message.data['type'] as String? ?? '';
    NotificationNavigationService().navigateTo(type);
  }

  /// Show an immediate local notification banner — used for:
  ///  • Foreground FCM messages
  ///  • Guest check-in (same-device scenario)
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;
    await _local.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }
}
