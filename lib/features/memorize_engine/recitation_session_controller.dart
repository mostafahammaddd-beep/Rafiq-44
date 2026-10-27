import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/audio_engine/audio_capture_service.dart';
import '../../core/audio_engine/phoneme_lexicon_service.dart';
import '../../core/audio_engine/recitation_evaluator.dart';
import '../../core/audio_engine/sherpa_tajweed_engine.dart';
import '../../core/audio_engine/tajweed_checker.dart';
import '../../core/database/models.dart';
import '../../core/database/rafiq_database.dart';
import '../../core/tajweed/tajweed_rule.dart';
import '../../core/tajweed/phonetic_script_builder.dart';

enum WordStatus { pending, correct, warning, uncertain, incorrect }

class TajweedFeedback {
  const TajweedFeedback({
    required this.title,
    required this.message,
    required this.verdict,
    required this.wordText,
  });

  final String title;
  final String message;
  final WordVerdict verdict;
  final String wordText;
}

/// Drives one recitation session (live correction or hands-free memorization)
/// over the ayahs of a single surah.
class RecitationSessionController extends ChangeNotifier {
  RecitationSessionController({
    required this.database,
    required this.engine,
    required this.capture,
    required this.lexicon,
    required this.surah,
    required this.ayahs,
    required this.mode,
    required this.engineAvailable,
    int startAyahIndex = 0,
  }) {
    _prepareAyah(startAyahIndex, 0);
  }

  final RafiqDatabase database;
  final SherpaTajweedEngine engine;
  final AudioCaptureService capture;
  final PhonemeLexiconService lexicon;
  final Surah surah;
  final List<Ayah> ayahs;
  final EvaluationMode mode;
  final bool engineAvailable;

  int ayahIndex = 0;
  late List<WordTarget> targets;
  late RecitationEvaluator _evaluator;
  List<WordStatus> statuses = <WordStatus>[];
  List<int> shakeTokens = <int>[];
  bool usingLexicon = false;

  bool listening = false;
  bool busy = false;
  bool stopping = false;
  bool ayahComplete = false;
  bool surahComplete = false;
  bool showFirstLetter = false;
  String hypothesis = '';
  String? errorMessage;
  TajweedFeedback? feedback;

  /// Developer-only diagnostics. The current Sherpa binding exposes decoded
  /// text but no frame-level log-probabilities, so unsupported metrics remain
  /// explicitly unavailable instead of being inferred from text.
  bool showTelemetry = false;
  double? lastInferenceMs;
  List<String> latestTokens = <String>[];
  List<double> latestTokenTimestamps = <double>[];
  int lastEngineSequence = -1;
  int _activeSessionId = 0;

  String get telemetryBackend => '${engine.backendName} / ${engine.modelVersion}';
  String get telemetryEvidenceStatus {
    final String matching = _evaluator.canUseTokenSequence
        ? 'مطابقة رموز النموذج مقابل المرجع الصوتي مفعّلة'
        : 'مطابقة Unicode احتياطية: تعذّر تقسيم المرجع إلى رموز النموذج';
    return '$matching. المطابقة تثبت توافق تسلسل الرموز مع المرجع فقط، ولا تثبت جميع خصائص الأداء الصوتي. تتوفر توقيتات الرموز فقط؛ لا تتوفر raw frame log-probs أو ثقة معايرة. بديل الوقف مولّد بالقواعد وليس مرجعًا بشريًا مستقلًا.';
  }
  String get telemetryExpectedPhonemes => targets.isEmpty || currentWordIndex < 0
      ? '—'
      : targets[currentWordIndex].phonemes;

  final List<double> levels = List<double>.filled(48, 0.0, growable: true);

  int _wordsChecked = 0;
  int _wordsCorrect = 0;
  int _tajweedChecked = 0;
  int _tajweedPassed = 0;
  int _lastHypothesisLength = 0;
  Timer? _advanceTimer;
  bool _disposed = false;

  // Audio is sent to the engine in blocks (~0.24 s) instead of every tiny
  // microphone callback, which keeps the isolate messaging light.
  static const int _flushSamples = 3840;
  static const double _quietLevel = 0.04;
  static const int _autoStopQuietMs = 45000;
  final List<Float32List> _pending = <Float32List>[];
  int _pendingSamples = 0;
  int _quietMs = 0;
  int _lastNotifyMs = 0;
  StreamSubscription<EngineUpdate>? _engineSub;

  Ayah get currentAyah => ayahs[ayahIndex];

  int get currentWordIndex =>
      _evaluator.cursor >= targets.length ? targets.length - 1 : _evaluator.cursor;

  // ------------------------------------------------------------- ayah state

  void _prepareAyah(int index, int carryConsumed) {
    ayahIndex = index;
    final Ayah ayah = ayahs[index];

    final List<String>? lex = lexicon.wordsFor(surah.id, ayah.number);
    final List<String>? usable =
        (lex != null && lex.length == ayah.words.length) ? lex : null;
    usingLexicon = usable != null;

    targets = <WordTarget>[
      for (int i = 0; i < ayah.words.length; i++)
        WordTarget(
          index: i,
          text: ayah.words[i].text,
          phonemes: usable != null ? usable[i] : ayah.words[i].phonemes,
          phonemeTokens: usable == null
              ? null
              : lexicon.tokenLabelsFor(usable[i]),
          waqfPhonemes: buildPhoneticScript(
            ayah.words[i].text,
            atWaqf: true,
          ),
          waqfPhonemeTokens: lexicon.tokenLabelsFor(
            buildPhoneticScript(ayah.words[i].text, atWaqf: true),
          ),
          rules: ayah.words[i].rules,
        ),
    ];

    _evaluator = RecitationEvaluator(
      words: targets,
      mode: mode,
      checker: TajweedChecker(lexiconMode: usingLexicon),
      acceptRatio: usingLexicon ? 0.25 : 0.38,
    );
    _evaluator.setConsumed(carryConsumed);

    statuses = List<WordStatus>.filled(targets.length, WordStatus.pending);
    shakeTokens = List<int>.filled(targets.length, 0);
    ayahComplete = false;
    feedback = null;
    _wordsChecked = 0;
    _wordsCorrect = 0;
    _tajweedChecked = 0;
    _tajweedPassed = 0;
  }

  void goToAyah(int index) {
    if (index < 0 || index >= ayahs.length) {
      return;
    }
    _advanceTimer?.cancel();
    surahComplete = false;
    _prepareAyah(index, _lastHypothesisLength);
    _notify();
  }

  void nextAyah() => goToAyah(ayahIndex + 1);

  void previousAyah() => goToAyah(ayahIndex - 1);

  void restartAyah() => goToAyah(ayahIndex);

  void toggleFirstLetter() {
    showFirstLetter = !showFirstLetter;
    _notify();
  }

  void toggleTelemetry() {
    showTelemetry = !showTelemetry;
    _notify();
  }

  // -------------------------------------------------------------- listening

  Future<void> toggleListening() async {
    if (listening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (listening || busy || stopping) {
      return;
    }
    if (!engineAvailable || !engine.isReady) {
      errorMessage = 'التصحيح الصوتي غير متاح: النموذج غير مضمّن في هذا الإصدار.';
      _notify();
      return;
    }
    busy = true;
    errorMessage = null;
    _notify();
    try {
      final bool granted = await capture.requestPermission();
      if (!granted) {
        errorMessage = 'يلزم السماح باستخدام الميكروفون من إعدادات الجهاز.';
        return;
      }
      await _engineSub?.cancel();
      _engineSub = engine.updates.listen(_onEngineUpdate);
      hypothesis = '';
      _lastHypothesisLength = 0;
      lastInferenceMs = null;
      latestTokens = <String>[];
      latestTokenTimestamps = <double>[];
      lastEngineSequence = -1;
      _evaluator.onSegmentReset();
      _pending.clear();
      _pendingSamples = 0;
      _quietMs = 0;
      _activeSessionId = engine.beginSession();
      // Set listening before starting the recorder: some recorder backends may
      // deliver the first chunk immediately from start().
      listening = true;
      await capture.start(_onAudio);
    } catch (e) {
      listening = false;
      engine.endSession();
      _activeSessionId = 0;
      try {
        await capture.stop();
      } catch (_) {
        // Preserve the original startup error; recorder cleanup is best effort.
      }
      errorMessage = 'تعذّر تشغيل الميكروفون: $e';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> stopListening() async {
    if (!listening || stopping) {
      return;
    }
    // Keep listening=true until the worker has drained queued chunks so its
    // final results still reach _onEngineUpdate. stopping prevents re-entry.
    stopping = true;
    busy = true;
    _notify();
    try {
      try {
        await capture.stop();
      } catch (e) {
        errorMessage = 'توقف الميكروفون مع تنبيه: $e';
      }

      if (_pendingSamples > 0 && _activeSessionId != 0) {
        final Float32List finalSamples = _takePending();
        await engine.feedAndWait(
          finalSamples,
          timeout: const Duration(seconds: 6),
        );
      }
      // Also drain full-sized chunks that were submitted before Stop.
      final bool drained = await engine.drain(timeout: const Duration(seconds: 6));
      if (!drained) {
        errorMessage ??= 'تجاوزت معالجة آخر المقاطع المهلة؛ قد لا يكون آخر تحديث قد وصل.';
      }
    } finally {
      listening = false;
      await _engineSub?.cancel();
      _engineSub = null;
      engine.endSession();
      _activeSessionId = 0;
      _pending.clear();
      _pendingSamples = 0;
      for (int i = 0; i < levels.length; i++) {
        levels[i] = 0.0;
      }
      stopping = false;
      busy = false;
      _notify();
    }
  }

  void _onAudio(Float32List samples, double level) {
    if (_disposed || !listening) {
      return;
    }
    levels.removeAt(0);
    levels.add(level);

    _pending.add(samples);
    _pendingSamples += samples.length;
    if (_pendingSamples >= _flushSamples) {
      engine.feed(_takePending());
    }

    // Stop by itself after a long silence to save battery.
    if (level < _quietLevel) {
      _quietMs += samples.length * 1000 ~/ 16000;
    } else {
      _quietMs = 0;
    }
    if (_quietMs >= _autoStopQuietMs) {
      errorMessage = 'توقف الاستماع تلقائياً لعدم سماع صوت، لتوفير البطارية.';
      unawaited(stopListening());
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotifyMs >= 90) {
      _lastNotifyMs = now;
      _notify();
    }
  }

  Float32List _takePending() {
    final Float32List merged = Float32List(_pendingSamples);
    int offset = 0;
    for (final Float32List part in _pending) {
      merged.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    _pending.clear();
    _pendingSamples = 0;
    return merged;
  }

  /// Hypothesis coming back from the engine isolate.
  void _onEngineUpdate(EngineUpdate update) {
    if (_disposed || !listening || update.sessionId != _activeSessionId) {
      return;
    }
    if (update.sequenceNumber <= lastEngineSequence) {
      return;
    }
    lastEngineSequence = update.sequenceNumber;
    lastInferenceMs = update.inferenceMs;
    latestTokens = update.tokens;
    latestTokenTimestamps = update.timestamps;
    hypothesis = update.text;
    _lastHypothesisLength = _evaluator.canUseTokenSequence && update.tokens.isNotEmpty
        ? update.tokens.length
        : update.text.replaceAll(RegExp(r'\s'), '').runes.length;

    if (!ayahComplete) {
      final List<WordEvaluation> events = update.tokens.isNotEmpty && _evaluator.canUseTokenSequence
          ? _evaluator.updateTokens(
              update.tokens,
              fallbackHypothesis: update.text,
              endpoint: update.endpoint,
            )
          : _evaluator.update(update.text, endpoint: update.endpoint);
      for (final WordEvaluation event in events) {
        _apply(event);
      }
      if (_evaluator.isComplete) {
        _completeAyah();
      }
    }
    if (update.endpoint) {
      _evaluator.onSegmentReset();
      _lastHypothesisLength = 0;
    }
    _notify();
  }

  // ------------------------------------------------------------- evaluation

  void _apply(WordEvaluation event) {
    final int i = event.wordIndex;
    final WordTarget target = targets[i];
    if (event.verdict == WordVerdict.uncertain) {
      statuses[i] = WordStatus.uncertain;
      feedback = TajweedFeedback(
        title: 'التقييم غير حاسم',
        message: event.message ?? 'لا تتوفر مرجعية أو أدلة كافية للحكم على هذه الكلمة.',
        verdict: WordVerdict.uncertain,
        wordText: target.text,
      );
      // Intentionally do not count this word as correct or incorrect and do
      // not store a mistake derived from missing reference data.
      return;
    }

    if (event.verdict == WordVerdict.correct) {
      statuses[i] = WordStatus.correct;
      _wordsChecked++;
      _wordsCorrect++;
      // A text-only phoneme hypothesis cannot certify duration-based tajweed
      // rules. Do not increment tajweedPassed without rule-level evidence.
      feedback = null;
      return;
    }

    if (event.verdict == WordVerdict.tajweedWarning) {
      final TajweedRule rule = event.rule ?? TajweedRule.maddTabii;
      statuses[i] = WordStatus.warning;
      _wordsChecked++;
      _wordsCorrect++;
      _tajweedChecked++;
      feedback = TajweedFeedback(
        title: rule.arabicName,
        message: event.message ?? rule.hint,
        verdict: WordVerdict.tajweedWarning,
        wordText: target.text,
      );
      HapticFeedback.lightImpact();
      _logMistake(target, rule.code, event.message ?? rule.hint);
      return;
    }

    // A non-advancing memorize verdict is provisional: the student may be
    // correcting themself in the same utterance. Show feedback once, but do
    // not persist a mistake or count the word until an actual final event.
    final String message = event.message ?? 'خطأ في النطق أو التشكيل';
    if (!event.advanced) {
      statuses[i] = WordStatus.warning;
      feedback = TajweedFeedback(
        title: 'راجع هذه الكلمة',
        message: 'التقييم ما زال مبدئيًا؛ أعد المحاولة. $message',
        verdict: WordVerdict.incorrect,
        wordText: target.text,
      );
      HapticFeedback.lightImpact();
      return;
    }

    statuses[i] = WordStatus.incorrect;
    shakeTokens[i] = shakeTokens[i] + 1;
    _wordsChecked++;
    feedback = TajweedFeedback(
      title: 'خطأ في النطق',
      message: message,
      verdict: WordVerdict.incorrect,
      wordText: target.text,
    );
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
    _logMistake(target, kPronunciationCode, message);
  }

  void _logMistake(WordTarget target, String ruleType, String message) {
    unawaited(
      database
          .logMistake(
            ayahId: currentAyah.id,
            wordPosition: target.index,
            wordText: target.text,
            ruleType: ruleType,
            message: message,
          )
          .catchError((Object error) {}),
    );
  }

  void _completeAyah() {
    ayahComplete = true;
    unawaited(
      database
          .recordAyahResult(
            ayahId: currentAyah.id,
            wordsChecked: _wordsChecked,
            wordsCorrect: _wordsCorrect,
            tajweedChecked: _tajweedChecked,
            tajweedPassed: _tajweedPassed,
          )
          .catchError((Object error) {}),
    );

    if (ayahIndex >= ayahs.length - 1) {
      surahComplete = true;
      unawaited(stopListening());
      return;
    }
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 1200), () {
      if (_disposed) {
        return;
      }
      final int carry = _evaluator.consumed;
      _prepareAyah(ayahIndex + 1, carry);
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _advanceTimer?.cancel();
    unawaited(_engineSub?.cancel());
    if (listening) {
      listening = false;
      engine.endSession();
      _activeSessionId = 0;
    }
    unawaited(capture.dispose());
    super.dispose();
  }
}
