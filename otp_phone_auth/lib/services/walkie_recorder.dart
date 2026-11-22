import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording, ready to send.
class WalkieRecording {
  final Uint8List bytes;
  final String filename;
  final Duration duration;
  const WalkieRecording(this.bytes, this.filename, this.duration);
}

/// Records one push-to-talk voice message.
///
/// Phones record AAC (.m4a), which every platform can play. In the browser
/// AAC recording isn't always available, so it falls back to WAV.
class WalkieRecorder {
  final _recorder = AudioRecorder();
  DateTime? _startedAt;
  String _extension = 'm4a';

  bool get isRecording => _startedAt != null;

  /// Asks for the microphone if needed. False if the user said no.
  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    var config = const RecordConfig(
      encoder: AudioEncoder.aacLc,
      sampleRate: 22050,
      numChannels: 1,
      bitRate: 48000,
    );
    _extension = 'm4a';
    if (kIsWeb && !await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      config = const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1);
      _extension = 'wav';
    }

    // The browser keeps the recording in memory; phones need a file
    final path = kIsWeb
        ? ''
        : '${(await getTemporaryDirectory()).path}/walkie_${DateTime.now().millisecondsSinceEpoch}.$_extension';
    await _recorder.start(config, path: path);
    _startedAt = DateTime.now();
  }

  /// Stops and returns the recording, or null if nothing was captured.
  Future<WalkieRecording?> stop() async {
    final startedAt = _startedAt;
    _startedAt = null;
    final path = await _recorder.stop();
    if (path == null || startedAt == null) return null;
    final bytes = await XFile(path).readAsBytes();
    if (bytes.isEmpty) return null;
    return WalkieRecording(
      bytes,
      'walkie_${DateTime.now().millisecondsSinceEpoch}.$_extension',
      DateTime.now().difference(startedAt),
    );
  }

  /// Stops and throws the recording away.
  Future<void> cancel() async {
    _startedAt = null;
    await _recorder.cancel();
  }

  Future<void> dispose() => _recorder.dispose();
}
