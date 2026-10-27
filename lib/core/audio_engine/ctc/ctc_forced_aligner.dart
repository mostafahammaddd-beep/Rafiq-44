import 'dart:math' as math;
import 'dart:typed_data';

import 'ctc_types.dart';

/// Viterbi forced alignment for a known CTC token sequence.
///
/// The input must contain actual per-frame log-probabilities from the acoustic
/// model. The implementation observes [CtcFrameBatch] strides and reports
/// frame ranges in global coordinates. It does not attempt to create frame
/// evidence from a decoded text string.
class CtcForcedAligner {
  const CtcForcedAligner();

  CtcAlignment align({
    required CtcFrameBatch batch,
    required List<int> targetTokenIds,
  }) {
    if (targetTokenIds.isEmpty) {
      return CtcAlignment(
        spans: const <AlignmentSpan>[],
        totalLogLikelihood: 0,
        globalStartFrame: batch.globalStartFrame,
        frameStepMs: batch.frameStepMs,
      );
    }
    for (final int id in targetTokenIds) {
      if (id < 0 || id >= batch.classCount) {
        throw ArgumentError('Target token id $id is outside ${batch.classCount} classes.');
      }
      if (id == batch.blankId) {
        throw ArgumentError('A target phoneme sequence cannot contain the CTC blank id.');
      }
    }

    final List<int> expanded = <int>[];
    for (final int id in targetTokenIds) {
      expanded
        ..add(batch.blankId)
        ..add(id);
    }
    expanded.add(batch.blankId);

    final int stateCount = expanded.length;
    final int frames = batch.frameCount;
    final double negativeInfinity = double.negativeInfinity;
    if (frames < targetTokenIds.length) {
      throw StateError('Not enough CTC frames to align all target tokens.');
    }

    var previous = List<double>.filled(stateCount, negativeInfinity);
    var current = List<double>.filled(stateCount, negativeInfinity);
    final Uint8List backPointers = Uint8List(frames * stateCount);

    previous[0] = batch.logProb(0, batch.blankId);
    if (stateCount > 1) {
      previous[1] = batch.logProb(0, expanded[1]);
    }

    for (int t = 1; t < frames; t++) {
      for (int s = 0; s < stateCount; s++) {
        double best = previous[s];
        int move = 0; // stay
        if (s >= 1 && previous[s - 1] > best) {
          best = previous[s - 1];
          move = 1; // advance one state
        }
        if (s >= 2 && _canSkip(expanded, s) && previous[s - 2] > best) {
          best = previous[s - 2];
          move = 2; // CTC skip over blank
        }
        current[s] = best + batch.logProb(t, expanded[s]);
        backPointers[t * stateCount + s] = move;
      }
      final List<double> swap = previous;
      previous = current;
      current = swap;
      current.fillRange(0, stateCount, negativeInfinity);
    }

    int state = stateCount - 1;
    double bestScore = previous[state];
    if (stateCount >= 2 && previous[stateCount - 2] > bestScore) {
      state = stateCount - 2;
      bestScore = previous[state];
    }
    if (!bestScore.isFinite) {
      throw StateError('No valid CTC path exists for this frame batch and target.');
    }

    final Uint16List pathState = Uint16List(frames);
    int cursor = state;
    for (int t = frames - 1; t >= 0; t--) {
      pathState[t] = cursor;
      if (t > 0) {
        final int move = backPointers[t * stateCount + cursor];
        if (move > cursor) {
          throw StateError('Invalid CTC backpointer encountered.');
        }
        cursor -= move;
      }
    }

    final List<AlignmentSpan> spans = <AlignmentSpan>[];
    for (int targetIndex = 0; targetIndex < targetTokenIds.length; targetIndex++) {
      final int tokenState = targetIndex * 2 + 1;
      int start = -1;
      int end = -1;
      double scoreSum = 0;
      int scoreCount = 0;
      for (int t = 0; t < frames; t++) {
        if (pathState[t] == tokenState) {
          start = start < 0 ? t : start;
          end = t + 1;
          scoreSum += batch.logProb(t, targetTokenIds[targetIndex]);
          scoreCount++;
        }
      }
      if (start < 0 || end <= start) {
        throw StateError('The best CTC path did not align target index $targetIndex.');
      }
      spans.add(AlignmentSpan(
        targetIndex: targetIndex,
        tokenId: targetTokenIds[targetIndex],
        startFrame: batch.globalStartFrame + start,
        endFrameExclusive: batch.globalStartFrame + end,
        startMs: (batch.globalStartFrame + start) * batch.frameStepMs,
        endMs: (batch.globalStartFrame + end) * batch.frameStepMs,
        meanTokenLogProb: scoreCount == 0 ? double.negativeInfinity : scoreSum / scoreCount,
      ));
    }

    return CtcAlignment(
      spans: List<AlignmentSpan>.unmodifiable(spans),
      totalLogLikelihood: bestScore,
      globalStartFrame: batch.globalStartFrame,
      frameStepMs: batch.frameStepMs,
    );
  }

  bool _canSkip(List<int> expanded, int state) {
    final int currentToken = expanded[state];
    final int tokenBeforeBlank = expanded[state - 2];
    return currentToken != expanded[state - 1] && currentToken != tokenBeforeBlank;
  }
}

/// Stable log(sum(exp(values))) helper used by the CTC forward algorithm.
double logSumExp3(double a, double b, double c) {
  final double maxValue = math.max(a, math.max(b, c)).toDouble();
  if (maxValue == double.negativeInfinity) return maxValue;
  return maxValue + math.log(
    math.exp(a - maxValue) + math.exp(b - maxValue) + math.exp(c - maxValue),
  );
}
