import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'auth_service.dart';

/// One voice message in the walkie-talkie channel.
class WalkieMessage {
  final String id;
  final String senderName;
  final String senderRole;
  final bool fromAdmin;
  final bool isMine;
  final String audioUrl;
  final Duration duration;
  final DateTime createdAt;
  bool heard;

  /// Only for my own messages: how many recipients have listened, out of how many.
  final int? heardCount;
  final int? audienceSize;

  WalkieMessage.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        senderName = json['sender_name'] as String? ?? 'Unknown',
        senderRole = json['sender_role'] as String? ?? '',
        fromAdmin = json['from_admin'] == true,
        isMine = json['is_mine'] == true,
        audioUrl = json['audio_url'] as String,
        duration = Duration(milliseconds: (json['duration_ms'] as num?)?.toInt() ?? 0),
        createdAt = DateTime.parse(json['created_at'] as String).toLocal(),
        heard = json['heard'] == true,
        heardCount = (json['heard_count'] as num?)?.toInt(),
        audienceSize = (json['audience_size'] as num?)?.toInt();
}

/// Push-to-talk voice messages: an admin talks to all staff, staff reply to
/// the admins. Backend: api/views_walkie.py
///
/// Like a walkie-talkie, a new message from someone else plays by itself as
/// soon as the app sees it (push notification, or the regular refresh).
class WalkieTalkieService extends ChangeNotifier {
  WalkieTalkieService._();
  static final WalkieTalkieService instance = WalkieTalkieService._();

  static const maxRecording = Duration(seconds: 60);
  static const _idleRefresh = Duration(seconds: 30);
  static const _openRefresh = Duration(seconds: 5);

  final _auth = AuthService();
  final _player = AudioPlayer();

  List<WalkieMessage> messages = [];
  int unheardCount = 0;
  bool loading = false;
  String? error;

  /// The message playing right now, if any.
  String? playingId;

  Timer? _timer;
  StreamSubscription<PlayerState>? _playerStates;
  bool _started = false;
  bool _screenOpen = false;
  bool _firstLoadDone = false;
  bool _refreshing = false;
  final _known = <String>{};
  final _autoPlayQueue = <WalkieMessage>[];

  Stream<Duration> get positionStream => _player.positionStream;

  /// Starts background refreshing. Safe to call from every dashboard.
  void start() {
    if (_started) return;
    _started = true;
    _playerStates ??= _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) _onPlaybackFinished();
    });
    refresh();
    _schedule();
  }

  /// On logout: stop refreshing and forget this user's messages.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _firstLoadDone = false;
    _known.clear();
    _autoPlayQueue.clear();
    messages = [];
    unheardCount = 0;
    playingId = null;
    _player.stop();
    notifyListeners();
  }

  /// The walkie-talkie screen refreshes more often while it's open.
  set screenOpen(bool open) {
    _screenOpen = open;
    _schedule();
    if (open) refresh();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_started) return;
    _timer = Timer.periodic(_screenOpen ? _openRefresh : _idleRefresh, (_) => refresh());
  }

  /// A walkie push notification arrived while the app is open.
  void onPush() => refresh();

  Future<Map<String, String>> _authHeader() async {
    final token = await _auth.getToken();
    return {'Authorization': 'Bearer ${token ?? ''}'};
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (messages.isEmpty) {
      loading = true;
      notifyListeners();
    }
    try {
      final response = await http
          .get(Uri.parse('${AuthService.baseUrl}/walkie/messages/'), headers: await _authHeader())
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        // Logged out, or a role without walkie-talkie: stop asking
        _timer?.cancel();
        _timer = null;
        return;
      }
      final data = _decode(response);
      final latest = (data['messages'] as List)
          .map((e) => WalkieMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      // Keep "heard" for messages played since the server last told us
      final heardLocally = {for (final m in messages) if (m.heard) m.id};
      for (final m in latest) {
        if (heardLocally.contains(m.id)) m.heard = true;
      }

      // Only messages that arrive while the app is running play by
      // themselves; older unheard ones wait for a tap.
      if (_firstLoadDone) {
        for (final m in latest) {
          if (!_known.contains(m.id) && !m.isMine && !m.heard) _autoPlayQueue.add(m);
        }
      }
      _known.addAll(latest.map((m) => m.id));
      _firstLoadDone = true;

      messages = latest;
      unheardCount = latest.where((m) => !m.heard).length;
      error = null;
      _playNextQueued();
    } catch (e) {
      debugPrint('[WALKIE] refresh failed: $e');
      error = 'Could not load messages';
    } finally {
      _refreshing = false;
      loading = false;
      notifyListeners();
    }
  }

  /// Sends a recording; refreshes the list when done. Throws on failure.
  Future<void> send(Uint8List audio, String filename, Duration duration) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AuthService.baseUrl}/walkie/messages/'),
    );
    request.headers.addAll(await _authHeader());
    request.fields['duration_ms'] = duration.inMilliseconds.toString();
    request.files.add(http.MultipartFile.fromBytes('audio', audio, filename: filename));
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 60)),
    );
    final data = _decode(response);
    _known.add(data['id'] as String); // don't auto-play my own message
    await refresh();
  }

  /// Plays [message], or stops it if it's already playing.
  Future<void> togglePlay(WalkieMessage message) async {
    if (playingId == message.id) {
      _autoPlayQueue.clear();
      await _player.stop();
      playingId = null;
      notifyListeners();
      return;
    }
    _autoPlayQueue.removeWhere((m) => m.id == message.id);
    await _play(message);
  }

  Future<void> _play(WalkieMessage message) async {
    playingId = message.id;
    notifyListeners();
    try {
      await _player.stop();
      await _player.setUrl(message.audioUrl);
      _player.play(); // completes when playback ends; completion is handled by the listener
      _markHeard(message);
    } catch (e) {
      debugPrint('[WALKIE] playback failed: $e');
      playingId = null;
      notifyListeners();
      _playNextQueued();
    }
  }

  void _onPlaybackFinished() {
    playingId = null;
    notifyListeners();
    _playNextQueued();
  }

  void _playNextQueued() {
    if (playingId != null || _autoPlayQueue.isEmpty) return;
    _play(_autoPlayQueue.removeAt(0));
  }

  Future<void> _markHeard(WalkieMessage message) async {
    if (message.heard || message.isMine) return;
    message.heard = true;
    unheardCount = messages.where((m) => !m.heard).length;
    notifyListeners();
    try {
      await http.post(
        Uri.parse('${AuthService.baseUrl}/walkie/messages/${message.id}/heard/'),
        headers: await _authHeader(),
      );
    } catch (e) {
      debugPrint('[WALKIE] mark heard failed: $e');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Server error (${response.statusCode})');
    }
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? data['detail'] ?? 'Request failed');
    }
    return data;
  }
}
