import 'package:flutter/material.dart';

import '../screens/walkie_talkie_screen.dart';
import '../services/push_notification_service.dart';
import '../services/walkie_talkie_service.dart';
import 'nav_badge.dart';

/// Opens the walkie-talkie. Shows how many voice messages are waiting.
///
/// Use [WalkieTalkieButton.fab] as a Scaffold's floatingActionButton, or the
/// default constructor as an AppBar action.
class WalkieTalkieButton extends StatefulWidget {
  final bool isAdmin;
  final bool _floating;
  final Color? iconColor;

  const WalkieTalkieButton({super.key, required this.isAdmin, this.iconColor}) : _floating = false;

  const WalkieTalkieButton.fab({super.key, required this.isAdmin})
      : _floating = true,
        iconColor = null;

  static void open(BuildContext context, {required bool isAdmin}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WalkieTalkieScreen(isAdmin: isAdmin)),
    );
  }

  @override
  State<WalkieTalkieButton> createState() => _WalkieTalkieButtonState();
}

class _WalkieTalkieButtonState extends State<WalkieTalkieButton> {
  final _service = WalkieTalkieService.instance;

  @override
  void initState() {
    super.initState();
    _service.start(); // keeps the badge current and plays new messages
    // Voice messages arrive by push; staff dashboards don't register otherwise
    PushNotificationService().initialise();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final count = _service.unheardCount;
        if (widget._floating) {
          return FloatingActionButton(
            heroTag: 'walkie_talkie_fab',
            tooltip: 'Walkie-talkie',
            backgroundColor: const Color(0xFF16213E),
            foregroundColor: Colors.white,
            onPressed: () => WalkieTalkieButton.open(context, isAdmin: widget.isAdmin),
            child: NavBadge(count: count, child: const Icon(Icons.settings_voice_rounded, size: 28)),
          );
        }
        return IconButton(
          tooltip: 'Walkie-talkie',
          onPressed: () => WalkieTalkieButton.open(context, isAdmin: widget.isAdmin),
          icon: NavBadge(
            count: count,
            child: Icon(Icons.settings_voice_rounded, color: widget.iconColor),
          ),
        );
      },
    );
  }
}
