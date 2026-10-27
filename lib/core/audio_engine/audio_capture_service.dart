import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Captures 16 kHz mono PCM16 audio from the microphone and converts it to
/// Float32 samples (what sherpa-onnx expects), plus an RMS level for the
/// live waveform.
class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  bool _running = false;
  int? _pendingByte;

  bool get isRunning => _running;

  Future<bool> requestPermission() async {
    final PermissionStatus status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> start(
    void Function(Float32List samples, double level) onChunk,
  ) async {
    if (_running) {
      return;
    }
    _pendingByte = null;
    final Stream<Uint8List> stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _running = true;
    _subscription = stream.listen((Uint8List bytes) {
      final Float32List samples = _toFloat32(bytes);
      if (samples.isEmpty) {
        return;
      }
      onChunk(samples, _rmsLevel(samples));
    });
  }

  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    // Stop the native recorder first. The stream may deliver its last buffered
    // PCM bytes while it closes; canceling first can discard the final phoneme.
    try {
      await _recorder.stop();
    } catch (_) {
      // The recorder may already be stopped.
    } finally {
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _recorder.dispose();
    } catch (_) {
      // Ignore errors while disposing.
    }
  }

  /// PCM16 little endian bytes -> Float32 in [-1, 1) (divide by 32768).
  Float32List _toFloat32(Uint8List bytes) {
    Uint8List data = bytes;
    final int? pending = _pendingByte;
    if (pending != null) {
      final Uint8List merged = Uint8List(bytes.length + 1);
      merged[0] = pending;
      merged.setRange(1, merged.length, bytes);
      data = merged;
      _pendingByte = null;
    }
    int usable = data.length;
    if (usable.isOdd) {
      usable -= 1;
      _pendingByte = data[usable];
    }
    final int count = usable ~/ 2;
    final Float32List out = Float32List(count);
    if (count == 0) {
      return out;
    }
    final ByteData view = ByteData.sublistView(data, 0, usable);
    for (int i = 0; i < count; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  double _rmsLevel(Float32List samples) {
    double sum = 0;
    for (int i = 0; i < samples.length; i++) {
      sum += samples[i] * samples[i];
    }
    final double rms = math.sqrt(sum / samples.length);
    final double scaled = rms * 6.0;
    if (scaled < 0) {
      return 0;
    }
    return scaled > 1 ? 1 : scaled;
  }
}
