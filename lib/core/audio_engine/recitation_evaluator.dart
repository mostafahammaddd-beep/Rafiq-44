import 'dart:math' as math;

import '../tajweed/tajweed_rule.dart';
import 'tajweed_checker.dart';

enum EvaluationMode { recite, memorize }

enum WordVerdict { correct, tajweedWarning, incorrect, uncertain }

/// Removes whitespace and invisible direction marks from display phoneme text.
String normalizePhonemes(String text) {
  return text.replaceAll(RegExp(r'[\s\u200B-\u200F\u202A-\u202E]'), '');
}

/// One word of the ayah. When the canonical reference can be exactly expressed
/// with tokens.txt, [phonemeTokens] is used to compare model token strings;
/// code-point matching is retained only as an explicitly weaker fallback.
class WordTarget {
  WordTarget({
    required this.index,
    required this.text,
    required String phonemes,
    required this.rules,
    List<String>? phonemeTokens,
    String? waqfPhonemes,
    List<String>? waqfPhonemeTokens,
  })  : phonemes = normalizePhonemes(phonemes),
        units = normalizePhonemes(phonemes).runes.toList(growable: false),
        phonemeTokens = phonemeTokens == null
            ? null
            : List<String>.unmodifiable(phonemeTokens),
        waqfPhonemes = waqfPhonemes == null
            ? null
            : normalizePhonemes(waqfPhonemes),
        waqfUnits = waqfPhonemes == null
            ? null
            : normalizePhonemes(waqfPhonemes).runes.toList(growable: false),
        waqfPhonemeTokens = waqfPhonemeTokens == null
            ? null
            : List<String>.unmodifiable(waqfPhonemeTokens);

  final int index;
  final String text;
  final String phonemes;
  final List<int> units;
  final List<String>? phonemeTokens;
  /// Rule-generated fallback variant for a pause. It is not a separately
  /// human-verified canonical transcription and is only used as a matching
  /// alternative when Sherpa marks the segment endpoint.
  final String? waqfPhonemes;
  final List<int>? waqfUnits;
  final List<String>? waqfPhonemeTokens;
  final List<TajweedRule> rules;
}

class WordEvaluation {
  const WordEvaluation({
    required this.wordIndex,
    required this.verdict,
    required this.advanced,
    this.rule,
    this.message,
  });

  final int wordIndex;
  final WordVerdict verdict;

  /// Whether the cursor moved on to the next word.
  final bool advanced;
  final TajweedRule? rule;
  final String? message;
}

class _Match {
  const _Match(this.distance, this.start, this.end);

  final int distance;
  final int start;
  final int end;
}

/// Streaming token-sequence evaluator used as a fallback while the live
/// backend exposes decoded tokens but not raw CTC frame log-probabilities.
/// It compares canonical phoneme tokens directly when vocabulary tokenization
/// succeeds; it does not issue frame-confidence or timing-based tajweed claims.
class RecitationEvaluator {
  RecitationEvaluator({
    required this.words,
    required this.mode,
    required this.checker,
    this.acceptRatio = 0.35,
  });

  final List<WordTarget> words;
  final EvaluationMode mode;
  final TajweedChecker checker;
  final double acceptRatio;

  int _cursor = 0;
  int _consumed = 0;
  String _lastHypothesis = '';
  bool _failureReportedForCursor = false;

  int get cursor => _cursor;
  int get consumed => _consumed;
  bool get isComplete => _cursor >= words.length;
  bool get canUseTokenSequence =>
      words.isNotEmpty && words.every((WordTarget word) => word.phonemeTokens != null);

  void setConsumed(int value) {
    _consumed = value < 0 ? 0 : value;
  }

  /// The recognizer reset its stream (pause detected): the hypothesis starts over.
  void onSegmentReset() {
    _consumed = 0;
    _lastHypothesis = '';
    _failureReportedForCursor = false;
  }

  /// Unicode-code-point fallback for a hypothesis without a token trace.
  List<WordEvaluation> update(String hypothesis, {bool endpoint = false}) {
    final String normalized = normalizePhonemes(hypothesis);
    return _updateSequence<int>(
      sequence: normalized.runes.toList(growable: false),
      identity: 'text:$normalized:endpoint=$endpoint',
      targetUnitOptions: (WordTarget target) => <List<int>>[
        target.units,
        if (target.waqfUnits != null) target.waqfUnits!,
      ],
      allowWaqfAtSegmentEnd: endpoint,
      display: (List<int> codePoints) => String.fromCharCodes(codePoints),
    );
  }

  /// Preferred matcher: model token labels against the exact tokenization of
  /// the canonical reference. It never splits a multi-codepoint token into
  /// unrelated Unicode characters. If any expected word cannot be represented
  /// by tokens.txt, the caller should explicitly fall back to [update].
  List<WordEvaluation> updateTokens(
    List<String> tokens, {
    required String fallbackHypothesis,
    bool endpoint = false,
  }) {
    if (!canUseTokenSequence || tokens.isEmpty) {
      return update(fallbackHypothesis, endpoint: endpoint);
    }
    final List<String> immutable = List<String>.unmodifiable(tokens);
    return _updateSequence<String>(
      sequence: immutable,
      identity: 'tokens:${immutable.join('\u0000')}:endpoint=$endpoint',
      targetUnitOptions: (WordTarget target) => <List<String>>[
        target.phonemeTokens!,
        if (target.waqfPhonemeTokens != null) target.waqfPhonemeTokens!,
      ],
      allowWaqfAtSegmentEnd: endpoint,
      display: (List<String> sequence) => sequence.join(),
    );
  }

  List<WordEvaluation> _updateSequence<T>({
    required List<T> sequence,
    required String identity,
    required List<List<T>> Function(WordTarget target) targetUnitOptions,
    required bool allowWaqfAtSegmentEnd,
    required String Function(List<T> units) display,
  }) {
    if (identity == _lastHypothesis) return <WordEvaluation>[];
    _lastHypothesis = identity;
    if (_consumed > sequence.length) _consumed = 0;
    // Empty recognizer updates commonly arrive during warm-up or while a user
    // is silent. They are not evidence that a reference word is unscorable.
    if (sequence.isEmpty && !allowWaqfAtSegmentEnd) {
      return <WordEvaluation>[];
    }

    final List<WordEvaluation> events = <WordEvaluation>[];
    int guard = 0;
    while (!isComplete && guard < 32) {
      guard++;
      final WordTarget target = words[_cursor];
      final List<List<T>> options = targetUnitOptions(target);
      final List<T> pattern = options.first;

      if (pattern.isEmpty) {
        // Missing reference phonemes are not evidence of a correct recitation.
        // Advance to avoid wedging the cursor, but mark the word inconclusive.
        events.add(WordEvaluation(
          wordIndex: target.index,
          verdict: WordVerdict.uncertain,
          advanced: true,
          message: 'لا توجد مرجعية فونيمية صالحة لهذه الكلمة؛ لم تُحتسب صحيحة أو خاطئة.',
        ));
        _cursor++;
        _failureReportedForCursor = false;
        continue;
      }

      final int available = sequence.length - _consumed;
      if (available <= 0) break;
      final List<T> window = sequence.sublist(_consumed);

      // If the entire unconsumed tail is a repeat of the just-confirmed word,
      // treat it as a harmless repetition instead of marking the next target
      // incorrect. If the current target follows in the same cumulative
      // hypothesis, normal matching below can still consume it.
      if (_cursor > 0) {
        final List<T> previousPattern =
            targetUnitOptions(words[_cursor - 1]).first;
        if (previousPattern.isNotEmpty) {
          final _Match repeated = _bestMatch<T>(previousPattern, window);
          final _Match currentAtTail = _bestMatch<T>(pattern, window);
          final bool currentAlsoMatchesTail = currentAtTail.distance == 0 &&
              currentAtTail.start <= 1 &&
              currentAtTail.end >= window.length - 1;
          final bool repeatsPreviousOnly = repeated.distance == 0 &&
              repeated.start <= 1 && repeated.end >= window.length - 1;
          if (repeatsPreviousOnly && !currentAlsoMatchesTail) break;
        }
      }

      _Match match = _bestMatch<T>(pattern, window);
      double ratio =
          (match.distance + math.max(0, match.start - 2)) / pattern.length;
      int selectedOption = 0;

      // A pause permits the final observed word to use its vetted/available
      // waqf alternative. Do not apply waqf to earlier words in the same
      // cumulative hypothesis, and do not treat a blank alone as a pause.
      if (allowWaqfAtSegmentEnd && options.length > 1) {
        final List<T> waqfPattern = options[1];
        if (waqfPattern.isNotEmpty) {
          final _Match waqfMatch = _bestMatch<T>(waqfPattern, window);
          final double waqfRatio =
              (waqfMatch.distance + math.max(0, waqfMatch.start - 2)) /
                  waqfPattern.length;
          final bool endsAtPause = waqfMatch.end >= window.length - 1;
          final bool waqfUsable = endsAtPause &&
              (waqfRatio <= acceptRatio || waqfMatch.distance == 0) &&
              available >= (waqfPattern.length * 0.5).ceil();
          if (waqfUsable &&
              match.end >= window.length - 1 &&
              (waqfRatio < ratio ||
                  (waqfMatch.distance == 0 && match.distance > 0))) {
            match = waqfMatch;
            ratio = waqfRatio;
            selectedOption = 1;
          }
        }
      }
      final List<T> chosenPattern = options[selectedOption];
      // A distant exact substring must not silently skip intermediate words.
      // A memorization self-correction may search a wider bounded window after
      // a provisional error; normal recitation only tolerates a tiny prefix.
      final int maximumExactStart = _failureReportedForCursor ? 16 : 2;
      final bool exactNearby = match.distance == 0 &&
          match.start <= maximumExactStart;

      if ((ratio <= acceptRatio || exactNearby) &&
          available >= (chosenPattern.length * 0.5).ceil()) {
        final String heard = display(window.sublist(match.start, match.end));
        final TajweedFinding? finding = checker.check(target, heard);
        events.add(WordEvaluation(
          wordIndex: target.index,
          verdict: finding == null
              ? WordVerdict.correct
              : WordVerdict.tajweedWarning,
          advanced: true,
          rule: finding?.rule,
          message: finding?.message,
        ));
        _consumed += match.end;
        _cursor++;
        _failureReportedForCursor = false;
        continue;
      }

      final int slack = math.max(3, chosenPattern.length ~/ 2).toInt();
      if (available < chosenPattern.length + slack) break;

      // Memorization errors remain provisional until the student moves on; a
      // self-correction can still match this target without a duplicate event.
      if (mode == EvaluationMode.memorize) {
        if (!_failureReportedForCursor) {
          events.add(WordEvaluation(
            wordIndex: target.index,
            verdict: WordVerdict.incorrect,
            advanced: false,
            message: 'خطأ في نطق الكلمة أو التشكيل',
          ));
          _failureReportedForCursor = true;
        }
        break;
      }

      int skip = math.min(available, chosenPattern.length).toInt();
      if (_cursor + 1 < words.length) {
        final List<T> nextPattern = targetUnitOptions(words[_cursor + 1]).first;
        if (nextPattern.isNotEmpty) {
          final _Match nextMatch = _bestMatch<T>(nextPattern, window);
          final double nextRatio = nextMatch.distance / nextPattern.length;
          if (nextRatio <= acceptRatio * 0.8 &&
              nextMatch.start >= (pattern.length * 0.4).floor()) {
            skip = nextMatch.start;
          }
        }
      }
      events.add(WordEvaluation(
        wordIndex: target.index,
        verdict: WordVerdict.incorrect,
        advanced: true,
        message: 'خطأ في نطق الكلمة أو التشكيل',
      ));
      _consumed += skip;
      _cursor++;
      _failureReportedForCursor = false;
    }
    return events;
  }

  /// Sellers substring edit distance over token units. Equality is checked on
  /// full token labels or Unicode code points depending on the selected path.
  static _Match _bestMatch<T>(List<T> pattern, List<T> text) {
    final int m = pattern.length;
    final int n = text.length;
    List<int> previous = List<int>.filled(n + 1, 0);
    List<int> previousStart = List<int>.generate(n + 1, (int j) => j);

    for (int i = 1; i <= m; i++) {
      final List<int> current = List<int>.filled(n + 1, 0);
      final List<int> currentStart = List<int>.filled(n + 1, 0);
      current[0] = i;
      currentStart[0] = 0;
      for (int j = 1; j <= n; j++) {
        final int substitution = previous[j - 1] +
            (pattern[i - 1] == text[j - 1] ? 0 : 1);
        final int deletion = previous[j] + 1;
        final int insertion = current[j - 1] + 1;
        int best = substitution;
        int bestStart = previousStart[j - 1];
        if (deletion < best) {
          best = deletion;
          bestStart = previousStart[j];
        }
        if (insertion < best) {
          best = insertion;
          bestStart = currentStart[j - 1];
        }
        current[j] = best;
        currentStart[j] = bestStart;
      }
      previous = current;
      previousStart = currentStart;
    }

    int bestEnd = 0;
    int bestDistance = previous[0];
    for (int j = 1; j <= n; j++) {
      if (previous[j] <= bestDistance) {
        bestDistance = previous[j];
        bestEnd = j;
      }
    }
    return _Match(bestDistance, previousStart[bestEnd], bestEnd);
  }
}
