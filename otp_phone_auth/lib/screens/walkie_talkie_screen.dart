import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/walkie_recorder.dart';
import '../services/walkie_talkie_service.dart';

const _navy = Color(0xFF16213E);
const _red = Color(0xFFE53935);
const _background = Color(0xFFF4F6FA);

/// Push-to-talk voice messages. Admins talk to all staff; staff reply to
/// the admins. Hold the big button to talk, release to send.
class WalkieTalkieScreen extends StatefulWidget {
  /// True for admins (they talk to all staff), false for staff.
  final bool isAdmin;

  const WalkieTalkieScreen({super.key, required this.isAdmin});

  @override
  State<WalkieTalkieScreen> createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends State<WalkieTalkieScreen>
    with SingleTickerProviderStateMixin {
  final _service = WalkieTalkieService.instance;
  final _recorder = WalkieRecorder();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _pressing = false; // finger/mouse is on the button
  bool _recording = false;
  bool _sending = false;
  bool _cancelArmed = false; // finger slid away: releasing cancels
  Offset? _pressOrigin;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  static const _minRecording = Duration(milliseconds: 700);
  static const _cancelDistance = 90.0;

  String get _audienceLabel => widget.isAdmin ? 'all staff' : 'admin';

  @override
  void initState() {
    super.initState();
    _service.start();
    _service.screenOpen = true;
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.screenOpen = false;
    _service.removeListener(_onServiceChanged);
    _ticker?.cancel();
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Push to talk
  // ---------------------------------------------------------------------------

  Future<void> _startTalking(Offset origin) async {
    _pressing = true;
    if (_recording || _sending) return;
    if (!await _recorder.hasPermission()) {
      _showMessage('Allow microphone access to use the walkie-talkie', isError: true);
      return;
    }
    try {
      await _recorder.start();
    } catch (e) {
      _showMessage('Could not start recording: $e', isError: true);
      return;
    }
    if (!_pressing || !mounted) {
      // Let go while the microphone was starting (e.g. the permission prompt)
      await _recorder.cancel();
      _showMessage('Hold the button while you talk, then let go to send');
      return;
    }
    HapticFeedback.mediumImpact();
    _pressOrigin = origin;
    _elapsed = Duration.zero;
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() => _elapsed += const Duration(milliseconds: 200));
      if (_elapsed >= WalkieTalkieService.maxRecording) _stopTalking();
    });
    _pulse.repeat(reverse: true);
    setState(() {
      _recording = true;
      _cancelArmed = false;
    });
  }

  void _onPointerMove(Offset position) {
    if (!_recording || _pressOrigin == null) return;
    final armed = (position - _pressOrigin!).distance > _cancelDistance;
    if (armed != _cancelArmed) {
      HapticFeedback.selectionClick();
      setState(() => _cancelArmed = armed);
    }
  }

  Future<void> _stopTalking({bool cancel = false}) async {
    _pressing = false;
    if (!_recording) return;
    _ticker?.cancel();
    _pulse.stop();
    _pulse.reset();
    final tooShort = _elapsed < _minRecording;
    final discard = cancel || _cancelArmed || tooShort;
    setState(() {
      _recording = false;
      _cancelArmed = false;
    });

    if (discard) {
      await _recorder.cancel();
      if (tooShort && !cancel) {
        _showMessage('Hold the button while you talk, then let go to send');
      }
      return;
    }

    setState(() => _sending = true);
    try {
      final recording = await _recorder.stop();
      if (recording == null) throw Exception('Nothing was recorded');
      await _service.send(recording.bytes, recording.filename, recording.duration);
      HapticFeedback.lightImpact();
    } catch (e) {
      _showMessage('Not sent: ${e.toString().replaceFirst('Exception: ', '')}', isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: isError ? _red : _navy,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Walkie-talkie',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            Text(
              widget.isAdmin ? 'You talk to all staff' : 'Your messages go to the admin',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _service.refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildTalkPanel(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    final messages = _service.messages;
    if (messages.isEmpty) {
      if (_service.loading) return const Center(child: CircularProgressIndicator());
      return _buildEmptyState();
    }
    // Newest at the bottom, like a chat; reversed so it opens scrolled to the end
    final items = <Widget>[];
    DateTime? lastDay;
    for (final message in messages) {
      final day = DateUtils.dateOnly(message.createdAt);
      if (day != lastDay) {
        items.add(_DayDivider(day: day));
        lastDay = day;
      }
      items.add(_MessageBubble(message: message, service: _service));
    }
    return RefreshIndicator(
      onRefresh: _service.refresh,
      child: ListView(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        children: items.reversed.toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.settings_voice_rounded, size: 46, color: _navy),
            ),
            const SizedBox(height: 18),
            const Text('No voice messages yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _navy)),
            const SizedBox(height: 6),
            Text(
              'Hold the button below and talk.\nLet go to send it to $_audienceLabel.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.4),
            ),
            if (_service.error != null) ...[
              const SizedBox(height: 14),
              Text(_service.error!, style: const TextStyle(color: _red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTalkPanel() {
    final String hint;
    if (_sending) {
      hint = 'Sending…';
    } else if (_recording && _cancelArmed) {
      hint = 'Let go to cancel';
    } else if (_recording) {
      hint = 'Release to send · slide away to cancel';
    } else {
      hint = 'Hold to talk to $_audienceLabel';
    }
    final remaining = WalkieTalkieService.maxRecording - _elapsed;
    final buttonColor = _cancelArmed ? const Color(0xFF9CA3AF) : (_recording ? _red : _navy);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 22,
            child: _recording
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.fiber_manual_record, color: _red, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _formatDuration(_elapsed),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, color: _red,
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      if (remaining <= const Duration(seconds: 10))
                        Text('  · ${remaining.inSeconds}s left',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                    ],
                  )
                : null,
          ),
          const SizedBox(height: 8),
          Listener(
            onPointerDown: (e) => _startTalking(e.position),
            onPointerMove: (e) => _onPointerMove(e.position),
            onPointerUp: (_) => _stopTalking(),
            onPointerCancel: (_) => _stopTalking(cancel: true),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final glow = _recording && !_cancelArmed ? 10 + 14 * _pulse.value : 0.0;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _recording ? 104 : 92,
                  height: _recording ? 104 : 92,
                  decoration: BoxDecoration(
                    color: buttonColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: buttonColor.withValues(alpha: 0.35),
                        blurRadius: 12 + glow,
                        spreadRadius: glow / 2,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Center(
                child: _sending
                    ? const SizedBox(
                        width: 30, height: 30,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : Icon(
                        _cancelArmed ? Icons.close_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hint,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _cancelArmed ? _red : const Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final seconds = d.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _DayDivider extends StatelessWidget {
  final DateTime day;
  const _DayDivider({required this.day});

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final String label;
    if (day == today) {
      label = 'Today';
    } else if (day == today.subtract(const Duration(days: 1))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('d MMM yyyy').format(day);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4B5563))),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final WalkieMessage message;
  final WalkieTalkieService service;

  const _MessageBubble({required this.message, required this.service});

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final playing = service.playingId == message.id;
    final accent = mine ? Colors.white : _navy;
    final bubbleColor = mine ? _navy : Colors.white;
    final subtle = mine ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF6B7280);

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: mine ? Colors.white.withValues(alpha: 0.18) : _navy,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => service.togglePlay(message),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: Colors.white, size: 26),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: playing
                      ? StreamBuilder<Duration>(
                          stream: service.positionStream,
                          builder: (context, snapshot) {
                            final total = message.duration.inMilliseconds;
                            final pos = snapshot.data?.inMilliseconds ?? 0;
                            return _ProgressBar(
                              value: total == 0 ? 0 : (pos / total).clamp(0.0, 1.0),
                              color: accent,
                            );
                          },
                        )
                      : _ProgressBar(value: 0, color: accent),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_formatDuration(message.duration),
                        style: TextStyle(fontSize: 12, color: subtle, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text(DateFormat('h:mm a').format(message.createdAt),
                        style: TextStyle(fontSize: 12, color: subtle)),
                    if (!mine && !message.heard) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message.senderName,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navy)),
                  if (message.senderRole.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: message.fromAdmin
                            ? const Color(0xFFFFEDD5)
                            : const Color(0xFFE0E7FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        message.senderRole,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: message.fromAdmin
                              ? const Color(0xFF9A3412)
                              : const Color(0xFF3730A3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          bubble,
          if (mine && message.audienceSize != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.headphones_rounded,
                    size: 14,
                    color: (message.heardCount ?? 0) > 0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Heard by ${message.heardCount ?? 0} of ${message.audienceSize}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  const _ProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 5,
        backgroundColor: color.withValues(alpha: 0.2),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
