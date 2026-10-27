import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

class EngineUpdate {
  const EngineUpdate({
    required this.text,
    required this.endpoint,
    this.sessionId = 0,
    this.sequenceNumber = 0,
    this.requestId = 0,
    this.inferenceMs,
    this.tokens = const <String>[],
    this.timestamps = const <double>[],
    this.backend = 'sherpa_onnx_tokens_timestamps',
    this.modelVersion = 'unknown',
    this.rawFrameEvidenceAvailable = false,
  });

  /// Cumulative phoneme text of the current segment.
  final String text;

  /// True when the recognizer detected a pause and reset itself.
  final bool endpoint;

  /// Monotonic id for the active listening session. Old results are discarded.
  final int sessionId;
  final int sequenceNumber;
  final int requestId;
  final double? inferenceMs;

  /// Actual token sequence and per-token timestamps supplied by sherpa-onnx.
  /// They are not CTC frame logits and do not provide confidence calibration.
  final List<String> tokens;
  final List<double> timestamps;
  final String backend;
  final String modelVersion;

  /// Sherpa returns tokens/timestamps, but not frame-level CTC log-probabilities.
  /// Keep this false unless a backend really provides raw frame evidence.
  final bool rawFrameEvidenceAvailable;
}

/// Streaming Zipformer2-CTC phoneme recognizer (sherpa-onnx) running in its
/// own isolate, so decoding never blocks the UI thread.
///
/// Usage: [initialize] once, then per listening session [beginSession],
/// [feed] audio, listen to [updates], and [endSession].
class SherpaTajweedEngine {
  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _events;
  ReceivePort? _errors;
  StreamSubscription<dynamic>? _eventsSub;
  StreamSubscription<dynamic>? _errorsSub;
  // Synchronous delivery makes feedAndWait a real drain barrier: the
  // controller processes the final result before stopListening cancels its
  // subscription. The callback only updates in-memory state and UI notifiers.
  final StreamController<EngineUpdate> _updates =
      StreamController<EngineUpdate>.broadcast(sync: true);
  final Map<int, Completer<EngineUpdate?>> _feedWaiters =
      <int, Completer<EngineUpdate?>>{};
  final Map<int, Completer<void>> _drainWaiters = <int, Completer<void>>{};

  Stream<EngineUpdate> get updates => _updates.stream;

  bool get isReady => _commands != null;

  int _nextSessionId = 0;
  int _nextRequestId = 0;
  int _activeSessionId = 0;
  String _modelVersion = 'unknown';
  Completer<void>? _workerDisposed;
  Future<void>? _disposeFuture;

  int get activeSessionId => _activeSessionId;
  String get modelVersion => _modelVersion;
  String get backendName => 'sherpa_onnx';

  /// Loads the model inside the worker isolate (a few seconds the first time).
  Future<void> initialize({
    required String modelPath,
    required String tokensPath,
    String modelVersion = 'unknown',
  }) async {
    if (_commands != null) {
      return;
    }
    _modelVersion = modelVersion;
    final ReceivePort events = ReceivePort();
    final ReceivePort errors = ReceivePort();
    final Completer<void> ready = Completer<void>();
    _events = events;
    _errors = errors;

    _eventsSub = events.listen((dynamic message) {
      if (message is! List || message.isEmpty) {
        return;
      }
      final Object? tag = message[0];
      if (tag == 'ready') {
        _commands = message[1] as SendPort;
        if (!ready.isCompleted) {
          ready.complete();
        }
      } else if (tag == 'error') {
        if (!ready.isCompleted) {
          ready.completeError(StateError(message[1] as String));
        }
      } else if (tag == 'disposed') {
        final Completer<void>? disposed = _workerDisposed;
        if (disposed != null && !disposed.isCompleted) disposed.complete();
      } else if (tag == 'barrier') {
        final int requestId = message.length > 2 ? message[2] as int : 0;
        final Completer<void>? waiter = _drainWaiters.remove(requestId);
        if (waiter != null && !waiter.isCompleted) waiter.complete();
      } else if (tag == 'update') {
        final EngineUpdate update = EngineUpdate(
          text: message[1] as String,
          endpoint: message[2] as bool,
          sessionId: message.length > 3 ? message[3] as int : 0,
          sequenceNumber: message.length > 4 ? message[4] as int : 0,
          inferenceMs: message.length > 5 ? (message[5] as num).toDouble() : null,
          modelVersion: _modelVersion,
          tokens: message.length > 6
              ? List<String>.unmodifiable((message[6] as List).cast<String>())
              : const <String>[],
          timestamps: message.length > 7
              ? List<double>.unmodifiable((message[7] as List).cast<num>().map((num n) => n.toDouble()))
              : const <double>[],
          requestId: message.length > 8 ? message[8] as int : 0,
        );
        if (!_updates.isClosed) _updates.add(update);
        if (update.requestId != 0) {
          final Completer<EngineUpdate?>? waiter = _feedWaiters.remove(update.requestId);
          if (waiter != null && !waiter.isCompleted) waiter.complete(update);
        }
      }
    });
    _errorsSub = errors.listen((dynamic error) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('Engine worker crashed: $error'));
      }
    });

    try {
      _isolate = await Isolate.spawn<List<Object>>(
        _workerMain,
        <Object>[events.sendPort, modelPath, tokensPath],
        onError: errors.sendPort,
      );
      await ready.future.timeout(const Duration(seconds: 120));
    } catch (_) {
      _cleanup();
      rethrow;
    }
  }

  /// Starts a fresh audio stream (call before each listening session).
  int beginSession() {
    final int sessionId = ++_nextSessionId;
    _activeSessionId = sessionId;
    _commands?.send(<Object>['begin', sessionId]);
    return sessionId;
  }

  /// Sends Float32 samples (16 kHz mono). The hypothesis arrives on [updates].
  void feed(Float32List samples) {
    _sendAudio(samples, requestId: 0);
  }

  /// Sends a final audio buffer and waits until its corresponding decode result
  /// has been delivered to [updates]. Used when stopping a recording so the
  /// last sub-240-ms buffer cannot be silently discarded.
  Future<EngineUpdate?> feedAndWait(
    Float32List samples, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (samples.isEmpty) return null;
    final SendPort? port = _commands;
    final int sessionId = _activeSessionId;
    if (port == null || sessionId == 0) return null;
    final int requestId = ++_nextRequestId;
    final Completer<EngineUpdate?> waiter = Completer<EngineUpdate?>();
    _feedWaiters[requestId] = waiter;
    _sendAudio(samples, requestId: requestId);
    try {
      return await waiter.future.timeout(timeout);
    } on TimeoutException {
      _feedWaiters.remove(requestId);
      return null;
    } finally {
      _feedWaiters.remove(requestId);
    }
  }

  void _sendAudio(Float32List samples, {required int requestId}) {
    final SendPort? port = _commands;
    final int sessionId = _activeSessionId;
    if (port == null || sessionId == 0 || samples.isEmpty) return;
    port.send(<Object>[
      'audio',
      sessionId,
      requestId,
      TransferableTypedData.fromList(<TypedData>[samples]),
    ]);
  }

  /// Waits until all previously submitted audio commands have been processed.
  /// This is required even when the last microphone chunk was exactly full.
  Future<bool> drain({Duration timeout = const Duration(seconds: 6)}) async {
    final SendPort? port = _commands;
    final int sessionId = _activeSessionId;
    if (port == null || sessionId == 0) return true;
    final int requestId = ++_nextRequestId;
    final Completer<void> waiter = Completer<void>();
    _drainWaiters[requestId] = waiter;
    port.send(<Object>['barrier', sessionId, requestId]);
    try {
      await waiter.future.timeout(timeout);
      return true;
    } on TimeoutException {
      // Caller can close the session after a bounded wait. No fake result is emitted.
      return false;
    } finally {
      _drainWaiters.remove(requestId);
    }
  }

  void endSession() {
    final int sessionId = _activeSessionId;
    _activeSessionId = 0;
    for (final Completer<EngineUpdate?> waiter in _feedWaiters.values) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    _feedWaiters.clear();
    for (final Completer<void> waiter in _drainWaiters.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _drainWaiters.clear();
    if (sessionId != 0) {
      _commands?.send(<Object>['end', sessionId]);
    }
  }

  Future<void> dispose() => _disposeFuture ??= _disposeWorker();

  Future<void> _disposeWorker() async {
    final SendPort? port = _commands;
    if (port == null) {
      _cleanup();
      if (!_updates.isClosed) await _updates.close();
      return;
    }

    final Completer<void> disposed = Completer<void>();
    _workerDisposed = disposed;
    port.send(<Object>['dispose']);
    try {
      await disposed.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // A native runtime can hang while tearing down. Fall back to killing the
      // isolate after the bounded grace period; never wait forever in dispose.
    } finally {
      _workerDisposed = null;
      for (final Completer<EngineUpdate?> waiter in _feedWaiters.values) {
        if (!waiter.isCompleted) waiter.complete(null);
      }
      _feedWaiters.clear();
      for (final Completer<void> waiter in _drainWaiters.values) {
        if (!waiter.isCompleted) waiter.complete();
      }
      _drainWaiters.clear();
      _cleanup();
      if (!_updates.isClosed) await _updates.close();
    }
  }

  void _cleanup() {
    _eventsSub?.cancel();
    _errorsSub?.cancel();
    _eventsSub = null;
    _errorsSub = null;
    _events?.close();
    _errors?.close();
    _events = null;
    _errors = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
  }
}

/// Entry point of the worker isolate. Everything native lives here.
void _workerMain(List<Object> args) {
  final SendPort toMain = args[0] as SendPort;
  final String modelPath = args[1] as String;
  final String tokensPath = args[2] as String;
  final ReceivePort commands = ReceivePort();
  int activeSessionId = 0;
  int sequenceNumber = 0;

  late final sherpa_onnx.OnlineRecognizer recognizer;
  try {
    sherpa_onnx.initBindings();

    // Same layout as sherpa-onnx's own factory for streaming zipformer2 CTC
    // (no explicit modelType: the recognizer is chosen from the model path).
    final sherpa_onnx.OnlineModelConfig modelConfig =
        sherpa_onnx.OnlineModelConfig(
      zipformer2Ctc: sherpa_onnx.OnlineZipformer2CtcModelConfig(model: modelPath),
      tokens: tokensPath,
      numThreads: 2,
      provider: 'cpu',
    );
    final sherpa_onnx.OnlineRecognizerConfig config =
        sherpa_onnx.OnlineRecognizerConfig(
      model: modelConfig,
      feat: sherpa_onnx.FeatureConfig(sampleRate: 16000, featureDim: 80),
    );
    recognizer = sherpa_onnx.OnlineRecognizer(config);

    // Warm-up: the first decode allocates buffers, so do it before the user speaks.
    final sherpa_onnx.OnlineStream warm = recognizer.createStream();
    warm.acceptWaveform(samples: Float32List(16000), sampleRate: 16000);
    while (recognizer.isReady(warm)) {
      recognizer.decode(warm);
    }
    warm.free();
  } catch (e) {
    toMain.send(<Object>['error', e.toString()]);
    return;
  }

  toMain.send(<Object>['ready', commands.sendPort]);

  sherpa_onnx.OnlineStream? stream;

  commands.listen((dynamic message) {
    if (message is! List || message.isEmpty) {
      return;
    }
    final Object? command = message[0];

    if (command == 'begin') {
      stream?.free();
      activeSessionId = message.length > 1 ? message[1] as int : activeSessionId + 1;
      sequenceNumber = 0;
      stream = recognizer.createStream();
    } else if (command == 'audio') {
      final int messageSessionId = message.length > 1 ? message[1] as int : activeSessionId;
      if (messageSessionId == 0 || messageSessionId != activeSessionId) {
        return;
      }
      final sherpa_onnx.OnlineStream? current = stream;
      if (current == null) {
        return;
      }
      final Stopwatch stopwatch = Stopwatch()..start();
      final int requestId = message.length > 2 ? message[2] as int : 0;
      final int dataIndex = message.length > 3 ? 3 : 2;
      final Float32List samples =
          (message[dataIndex] as TransferableTypedData).materialize().asFloat32List();
      current.acceptWaveform(samples: samples, sampleRate: 16000);
      while (recognizer.isReady(current)) {
        recognizer.decode(current);
      }
      final sherpa_onnx.OnlineRecognizerResult result = recognizer.getResult(current);
      final String text = result.text;
      final List<String> tokens = List<String>.of(result.tokens);
      final List<double> timestamps = List<double>.of(result.timestamps);
      final bool endpoint = recognizer.isEndpoint(current);
      if (endpoint) {
        recognizer.reset(current);
      }
      stopwatch.stop();
      toMain.send(<Object>[
        'update', text, endpoint, activeSessionId, sequenceNumber++,
        stopwatch.elapsedMicroseconds / 1000.0, tokens, timestamps, requestId,
      ]);
    } else if (command == 'barrier') {
      final int messageSessionId = message.length > 1 ? message[1] as int : activeSessionId;
      final int requestId = message.length > 2 ? message[2] as int : 0;
      if (messageSessionId == activeSessionId && requestId != 0) {
        toMain.send(<Object>['barrier', activeSessionId, requestId]);
      }
    } else if (command == 'end') {
      final int messageSessionId = message.length > 1 ? message[1] as int : activeSessionId;
      if (messageSessionId == activeSessionId) {
        stream?.free();
        stream = null;
        activeSessionId = 0;
      }
    } else if (command == 'dispose') {
      stream?.free();
      stream = null;
      recognizer.free();
      toMain.send(<Object>['disposed']);
      commands.close();
    }
  });
}
