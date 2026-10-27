import 'dart:async';

/// Holds the destination when a push notification is tapped.
class NotificationNavDestination {
  final int mainTab;    // admin dashboard bottom-nav index
  final int subTab;     // notifications tab-bar index (0=labour,1=photos,2=requirements,3=guests)

  const NotificationNavDestination({required this.mainTab, required this.subTab});
}

class NotificationNavigationService {
  static final NotificationNavigationService _instance =
      NotificationNavigationService._internal();
  factory NotificationNavigationService() => _instance;
  NotificationNavigationService._internal();

  final _controller =
      StreamController<NotificationNavDestination>.broadcast();

  Stream<NotificationNavDestination> get stream => _controller.stream;

  void navigateTo(String type) {
    // Main tab 2 = Notifications screen for all push types
    const mainTab = 2;

    final subTab = switch (type) {
      'guest_checkin' => 3,            // Guests sub-tab
      'labour'        => 0,            // Labour sub-tab
      _               => 1,            // Photos/Material sub-tab
    };

    _controller.add(
      NotificationNavDestination(mainTab: mainTab, subTab: subTab),
    );
  }

  void dispose() => _controller.close();
}
