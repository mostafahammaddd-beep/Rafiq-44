import 'dart:math' as math;
import 'dart:typed_data';

/// A batch of real CTC frame log-probabilities.
///
/// Values are addressed with explicit strides: `frame * frameStride +
/// classId * classStride`. This intentionally does not assume contiguous
/// `[frames, classes]` storage. `frameStepMs` must come from the actual model /
/// feature-extractor contract, not from the microphone chunk duration.
class CtcFrameBatch {
  CtcFrameBatch({
    required this.logProbs,
    required this.frameCount,
    required this.classCount,
    required this.frameStepMs,
    required this.blankId,
    this.globalStartFrame = 0,
    int? frameStride,
    this.classStride = 1,
    this.source = 'raw_ctc_backend',
  }) : frameStride = frameStride ?? classCount {
    if (frameCount <= 0) throw ArgumentError.value(frameCount, 'frameCount');
    if (classCount <= 1) throw ArgumentError.value(classCount, 'classCount');
    if (blankId < 0 || blankId >= classCount) {
      throw ArgumentError.value(blankId, 'blankId');
    }
    if (!frameStepMs.isFinite || frameStepMs <= 0) {
      throw ArgumentError.value(frameStepMs, 'frameStepMs');
    }
    if (globalStartFrame < 0) {
      throw ArgumentError.value(globalStartFrame, 'globalStartFrame');
    }
    if (this.frameStride <= 0 || classStride <= 0) {
      throw ArgumentError('Tensor strides must be positive.');
    }
    final int maxIndex =
        (frameCount - 1) * this.frameStride + (classCount - 1) * classStride;
    if (maxIndex >= logProbs.length) {
      throw ArgumentError(
        'Tensor buffer too short for shape/strides: max index $maxIndex, '
        'buffer length ${logProbs.length}.',
      );
    }
    for (int frame = 0; frame < frameCount; frame++) {
      for (int classId = 0; classId < classCount; classId++) {
        final double value = logProbs[
          frame * this.frameStride + classId * classStride
        ].toDouble();
        // -infinity is allowed for impossible paths; NaN, +infinity, and
        // positive values are not valid log-probabilities and often indicate
        // a logits/probabilities contract mismatch.
        if (value.isNaN || value == double.infinity || value > 1e-3) {
          throw ArgumentError(
            'Frame output contains a non-log-probability value at '
            'frame=$frame class=$classId ($value).',
          );
        }
      }
    }
  }

  final Float32List logProbs;
  final int frameCount;
  final int classCount;
  final int frameStride;
  final int classStride;
  final double frameStepMs;
  final int blankId;
  final int globalStartFrame;
  final String source;

  double logProb(int frame, int classId) {
    if (frame < 0 || frame >= frameCount) {
      throw RangeError.range(frame, 0, frameCount - 1, 'frame');
    }
    if (classId < 0 || classId >= classCount) {
      throw RangeError.range(classId, 0, classCount - 1, 'classId');
    }
    return logProbs[frame * frameStride + classId * classStride].toDouble();
  }

  double get endTimeMs => (globalStartFrame + frameCount) * frameStepMs;
}

class AlignmentSpan {
  const AlignmentSpan({
    required this.targetIndex,
    required this.tokenId,
    required this.startFrame,
    required this.endFrameExclusive,
    required this.startMs,
    required this.endMs,
    required this.meanTokenLogProb,
  });

  final int targetIndex;
  final int tokenId;
  final int startFrame;
  final int endFrameExclusive;
  final double startMs;
  final double endMs;
  final double meanTokenLogProb;

  int get frameCount => endFrameExclusive - startFrame;
  double get durationMs => math.max(0, endMs - startMs).toDouble();
}

class CtcAlignment {
  const CtcAlignment({
    required this.spans,
    required this.totalLogLikelihood,
    required this.globalStartFrame,
    required this.frameStepMs,
  });

  final List<AlignmentSpan> spans;
  final double totalLogLikelihood;
  final int globalStartFrame;
  final double frameStepMs;
}

class CtcPhoneScore {
  const CtcPhoneScore({
    required this.expectedTokenId,
    required this.expectedLogLikelihood,
    required this.bestCompetitorTokenId,
    required this.bestCompetitorLogLikelihood,
    required this.logLikelihoodRatioPerFrame,
    required this.frameCount,
    required this.source,
  });

  final int expectedTokenId;
  final double expectedLogLikelihood;
  final int? bestCompetitorTokenId;
  final double? bestCompetitorLogLikelihood;

  /// `(expected CTC log-likelihood - best competing CTC log-likelihood) /
  /// number of frames`. This is a local one-phoneme CTC score, not a calibrated
  /// probability and not a substitute for contextual human evaluation.
  final double? logLikelihoodRatioPerFrame;
  final int frameCount;
  final String source;

  bool get isComparable =>
      bestCompetitorTokenId != null && logLikelihoodRatioPerFrame != null;
}
