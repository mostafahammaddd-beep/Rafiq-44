import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq_app/core/audio_engine/ctc/adaptive_haraka_tracker.dart';
import 'package:rafiq_app/core/audio_engine/ctc/ctc_forced_aligner.dart';
import 'package:rafiq_app/core/audio_engine/ctc/ctc_gop_scorer.dart';
import 'package:rafiq_app/core/audio_engine/ctc/ctc_types.dart';
import 'package:rafiq_app/core/audio_engine/ctc/streaming_viterbi_aligner.dart';
import 'package:rafiq_app/core/audio_engine/ctc/tajweed_diagnostic.dart';
import 'package:rafiq_app/core/audio_engine/ctc/token_table.dart';
import 'package:rafiq_app/core/audio_engine/ctc/waqf_wasl_graph.dart';
import 'package:rafiq_app/core/audio_engine/recitation_evaluator.dart';
import 'package:rafiq_app/core/audio_engine/tajweed_checker.dart';
import 'package:rafiq_app/core/tajweed/tajweed_rule.dart';

CtcFrameBatch _batch({int startFrame = 0}) {
  const int frames = 4;
  const int classes = 3;
  final List<int> preferred = <int>[1, 0, 2, 0];
  final Float32List values = Float32List(frames * classes);
  for (int frame = 0; frame < frames; frame++) {
    for (int token = 0; token < classes; token++) {
      values[frame * classes + token] = math.log(token == preferred[frame] ? 0.94 : 0.03);
    }
  }
  return CtcFrameBatch(
    logProbs: values,
    frameCount: frames,
    classCount: classes,
    frameStepMs: 10,
    blankId: 0,
    globalStartFrame: startFrame,
    source: 'unit_test_synthetic_log_probs',
  );
}

void main() {
  group('CTC forced alignment', () {
    test('aligns target phones and reports global frame timestamps', () {
      final CtcAlignment alignment = const CtcForcedAligner().align(
        batch: _batch(startFrame: 100),
        targetTokenIds: const <int>[1, 2],
      );
      expect(alignment.spans, hasLength(2));
      expect(alignment.spans[0].tokenId, 1);
      expect(alignment.spans[0].startFrame, 100);
      expect(alignment.spans[0].startMs, 1000);
      expect(alignment.spans[1].tokenId, 2);
      expect(alignment.spans[1].startFrame, 102);
      expect(alignment.spans[1].startMs, 1020);
      expect(alignment.totalLogLikelihood.isFinite, isTrue);
    });

    test('respects non-contiguous tensor strides', () {
      const int frames = 4;
      const int classes = 3;
      final List<int> preferred = <int>[1, 0, 2, 0];
      final Float32List transposed = Float32List(classes * frames);
      for (int frame = 0; frame < frames; frame++) {
        for (int token = 0; token < classes; token++) {
          transposed[token * frames + frame] =
              math.log(token == preferred[frame] ? 0.94 : 0.03);
        }
      }
      final CtcFrameBatch strided = CtcFrameBatch(
        logProbs: transposed,
        frameCount: frames,
        classCount: classes,
        frameStepMs: 10,
        blankId: 0,
        frameStride: 1,
        classStride: frames,
      );
      expect(strided.logProb(2, 2), closeTo(math.log(0.94), 0.0001));
      expect(const CtcForcedAligner().align(
        batch: strided,
        targetTokenIds: const <int>[1, 2],
      ).spans, hasLength(2));
    });

    test('rejects blank inside target sequence', () {
      expect(
        () => const CtcForcedAligner().align(
          batch: _batch(),
          targetTokenIds: const <int>[1, 0],
        ),
        throwsArgumentError,
      );
    });

    test('streaming alignment revises against cumulative frame evidence', () {
      final StreamingViterbiAligner streaming = StreamingViterbiAligner(
        targetTokenIds: const <int>[1, 2],
      );
      final CtcFrameBatch whole = _batch();
      final CtcFrameBatch first = CtcFrameBatch(
        logProbs: Float32List.fromList(whole.logProbs.sublist(0, 3)),
        frameCount: 1,
        classCount: 3,
        frameStepMs: 10,
        blankId: 0,
        globalStartFrame: 0,
      );
      expect(streaming.append(first).hasAlignment, isFalse);
      final CtcFrameBatch rest = CtcFrameBatch(
        logProbs: Float32List.fromList(whole.logProbs.sublist(3)),
        frameCount: 3,
        classCount: 3,
        frameStepMs: 10,
        blankId: 0,
        globalStartFrame: 1,
      );
      final StreamingAlignmentSnapshot snapshot = streaming.append(rest);
      expect(snapshot.hasAlignment, isTrue);
      expect(snapshot.alignment!.spans, hasLength(2));
      expect(snapshot.revision, 1);
      streaming.resetSegment();
      expect(streaming.bufferedFrames, 0);
    });
  });

  test('substitution-aware local CTC score prefers the matching phone', () {
    final Float32List values = Float32List(12);
    for (int frame = 0; frame < 4; frame++) {
      values[frame * 3] = math.log(0.08);
      values[frame * 3 + 1] = math.log(0.90);
      values[frame * 3 + 2] = math.log(0.02);
    }
    final CtcFrameBatch evidence = CtcFrameBatch(
      logProbs: values,
      frameCount: 4,
      classCount: 3,
      frameStepMs: 10,
      blankId: 0,
    );
    final CtcPhoneScore score = const CtcGopScorer().scorePhone(
      batch: evidence,
      startFrame: 0,
      endFrameExclusive: 4,
      expectedTokenId: 1,
      competitorTokenIds: const <int>[2],
    );
    expect(score.bestCompetitorTokenId, 2);
    expect(score.logLikelihoodRatioPerFrame, isNotNull);
    expect(score.logLikelihoodRatioPerFrame!, greaterThan(0));
  });

  test('token table validates ids and resolves labels', () {
    final TokenTable table = TokenTable.fromLines(
      const <String>['<blk> 0', 'ق 1', 'ل 2'],
      expectedBlankId: 0,
    );
    expect(table.classCount, 3);
    expect(table.blankId, 0);
    expect(table.labelFor(1), 'ق');
    expect(table.idsFor('ل'), <int>[2]);
    expect(() => TokenTable.fromLines(
      const <String>['<blk> 0', 'ل 2'],
      expectedBlankId: 0,
    ), throwsFormatException);
  });

  test('token table keeps multi-codepoint phoneme symbols intact', () {
    final TokenTable table = TokenTable.fromLines(
      const <String>['<blk> 0', 'م 1', 'مَ 2', 'ن 3'],
      expectedBlankId: 0,
    );
    expect(table.tokenizeExpectedPhonemes('مَ ن'), <String>['مَ', 'ن']);
    expect(table.tokenizeExpectedPhonemes('مَ ز'), isNull);
  });

  test('tokenizer refuses ambiguous segmentation rather than guessing', () {
    final TokenTable table = TokenTable.fromLines(
      const <String>['<blk> 0', 'a 1', 'ab 2', 'bc 3', 'c 4'],
      expectedBlankId: 0,
    );
    expect(table.tokenizeExpectedPhonemes('abc'), isNull);
    expect(table.tokenizeExpectedPhonemes('bc'), <String>['bc']);
  });

  test('frame batch rejects logits mislabeled as log probabilities', () {
    expect(
      () => CtcFrameBatch(
        logProbs: Float32List.fromList(<double>[0.1, -0.1, -0.2, -0.3]),
        frameCount: 2,
        classCount: 2,
        frameStepMs: 10,
        blankId: 0,
      ),
      throwsArgumentError,
    );
  });

  test('recitation evaluator compares model token labels directly', () {
    final WordTarget target = WordTarget(
      index: 0,
      text: 'مثال',
      phonemes: 'مَ ن',
      phonemeTokens: const <String>['مَ', 'ن'],
      rules: const <TajweedRule>[],
    );
    final RecitationEvaluator evaluator = RecitationEvaluator(
      words: <WordTarget>[target],
      mode: EvaluationMode.recite,
      checker: const TajweedChecker(lexiconMode: true),
      acceptRatio: 0.2,
    );
    final List<WordEvaluation> events = evaluator.updateTokens(
      const <String>['مَ', 'ن'],
      fallbackHypothesis: 'مَن',
    );
    expect(events, hasLength(1));
    expect(events.single.verdict, WordVerdict.correct);
    expect(evaluator.isComplete, isTrue);
  });

  test('empty recognizer hypothesis does not mark an empty reference uncertain', () {
    final WordTarget missingReference = WordTarget(
      index: 0,
      text: 'كلمة',
      phonemes: '',
      rules: const <TajweedRule>[],
    );
    final RecitationEvaluator evaluator = RecitationEvaluator(
      words: <WordTarget>[missingReference],
      mode: EvaluationMode.recite,
      checker: const TajweedChecker(lexiconMode: false),
    );
    expect(evaluator.update(''), isEmpty);
    expect(evaluator.isComplete, isFalse);
    // Once actual recognized material exists, missing reference data is
    // explicitly inconclusive rather than automatically correct.
    final List<WordEvaluation> events = evaluator.update('صوت');
    expect(events, hasLength(1));
    expect(events.single.verdict, WordVerdict.uncertain);
  });

  test('exact target far into the hypothesis is not accepted as a nearby match', () {
    final WordTarget target = WordTarget(
      index: 0,
      text: 'مثال',
      phonemes: 'a b',
      phonemeTokens: const <String>['a', 'b'],
      rules: const <TajweedRule>[],
    );
    final RecitationEvaluator evaluator = RecitationEvaluator(
      words: <WordTarget>[target],
      mode: EvaluationMode.recite,
      checker: const TajweedChecker(lexiconMode: true),
      acceptRatio: 0.2,
    );
    final List<WordEvaluation> events = evaluator.updateTokens(
      const <String>['x', 'x', 'x', 'a', 'b'],
      fallbackHypothesis: 'xxxab',
    );
    expect(events, isNotEmpty);
    expect(events.first.verdict, isNot(WordVerdict.correct));
  });

  test('endpoint can match a word-level waqf alternative', () {
    final WordTarget target = WordTarget(
      index: 0,
      text: 'مثال',
      phonemes: 'مَ ن',
      phonemeTokens: const <String>['مَ', 'ن'],
      waqfPhonemes: 'مَ',
      waqfPhonemeTokens: const <String>['مَ'],
      rules: const <TajweedRule>[],
    );
    final RecitationEvaluator evaluator = RecitationEvaluator(
      words: <WordTarget>[target],
      mode: EvaluationMode.recite,
      checker: const TajweedChecker(lexiconMode: true),
      acceptRatio: 0.2,
    );
    final List<WordEvaluation> noPause = evaluator.updateTokens(
      const <String>['مَ'],
      fallbackHypothesis: 'مَ',
    );
    expect(noPause, isEmpty);
    evaluator.onSegmentReset();
    final List<WordEvaluation> paused = evaluator.updateTokens(
      const <String>['مَ'],
      fallbackHypothesis: 'مَ',
      endpoint: true,
    );
    expect(paused, hasLength(1));
    expect(paused.single.verdict, WordVerdict.correct);
  });

  test('tempo tracker needs reliable calibration and rejects outliers', () {
    final AdaptiveHarakaTracker tracker = AdaptiveHarakaTracker(minSamples: 3);
    expect(tracker.estimate(200).isCalibrated, isFalse);
    expect(tracker.observeTrustedShortVowel(durationMs: 100, confidence: 0.95), isTrue);
    expect(tracker.observeTrustedShortVowel(durationMs: 110, confidence: 0.97), isTrue);
    expect(tracker.observeTrustedShortVowel(durationMs: 105, confidence: 0.96), isTrue);
    expect(tracker.baselineMs, closeTo(105, 0.01));
    expect(tracker.observeTrustedShortVowel(durationMs: 600, confidence: 0.99), isFalse);
    expect(tracker.estimate(210).estimatedHarakat, closeTo(2, 0.05));
  });

  test('diagnostic classifier refuses uncalibrated tajweed assertions', () {
    const TajweedDiagnosticClassifier classifier = TajweedDiagnosticClassifier();
    final DiagnosticDecision unsupported = classifier.classify(
      const DiagnosticEvidence(
        kind: AcousticFindingKind.maddDuration,
        rawFrameEvidenceAvailable: false,
        frameAligned: false,
        confidenceCalibrated: false,
      ),
    );
    expect(unsupported.category, RecitationErrorClass.uncertain);
    expect(unsupported.isActionable, isFalse);

    final DiagnosticDecision durationPass = classifier.classify(
      const DiagnosticEvidence(
        kind: AcousticFindingKind.maddDuration,
        rawFrameEvidenceAvailable: true,
        frameAligned: true,
        confidenceCalibrated: true,
        calibratedConfidence: 0.99,
        measuredDurationMs: 200,
        allowedMinimumMs: 180,
        allowedMaximumMs: 220,
        tempoBaselineCalibrated: true,
      ),
    );
    expect(durationPass.category, RecitationErrorClass.uncertain);
    expect(durationPass.isActionable, isFalse);
  });

  test('waqf/wasl graph keeps forward-only word boundaries', () {
    final WaqfWaslGraph graph = WaqfWaslGraph(const <PronunciationAlternatives>[
      PronunciationAlternatives(
        wordIndex: 0,
        waslPhonemes: <int>[1, 2],
        waqfPhonemes: <int>[1],
      ),
      PronunciationAlternatives(wordIndex: 1, waslPhonemes: <int>[3]),
    ]);
    expect(graph.nodeCount, 3);
    final List<PronunciationCandidate> paused = graph.candidatesFor(
      0,
      pause: const PauseEvidence(
        durationMs: 400,
        fromVad: true,
        endpoint: false,
        confidence: 0.9,
      ),
    );
    expect(paused.first.mode, PronunciationMode.waqf);
    expect(graph.candidatesFor(
      1,
      pause: const PauseEvidence(
        durationMs: 400,
        fromVad: true,
        endpoint: false,
        confidence: 0.9,
      ),
    ), hasLength(1));
  });
}
