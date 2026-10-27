import 'dart:math' as math;

import 'ctc_types.dart';

/// Computes a local substitution-aware CTC score for one phoneme.
///
/// For each candidate token, it runs the CTC forward sum for the one-token
/// target `[token]` across the supplied aligned window, including blank paths.
/// The result is a local phoneme discrimination score. It deliberately does
/// not claim to be calibrated CAPT GOP: context-sensitive scoring and acoustic
/// validation data are still needed before making high-confidence tajweed
/// judgements.
class CtcGopScorer {
  const CtcGopScorer();

  CtcPhoneScore scorePhone({
    required CtcFrameBatch batch,
    required int startFrame,
    required int endFrameExclusive,
    required int expectedTokenId,
    required Iterable<int> competitorTokenIds,
  }) {
    if (startFrame < 0 || endFrameExclusive > batch.frameCount ||
        endFrameExclusive <= startFrame) {
      throw ArgumentError('Invalid local CTC scoring frame range.');
    }
    _validateCandidate(batch, expectedTokenId);
    final int count = endFrameExclusive - startFrame;
    final double expectedScore = _singlePhoneForward(
      batch, startFrame, endFrameExclusive, expectedTokenId,
    );
    int? bestCompetitor;
    double? bestCompetitorScore;
    final Set<int> unique = competitorTokenIds.toSet();
    unique.remove(expectedTokenId);
    unique.remove(batch.blankId);
    for (final int candidate in unique) {
      _validateCandidate(batch, candidate);
      final double candidateScore = _singlePhoneForward(
        batch, startFrame, endFrameExclusive, candidate,
      );
      if (bestCompetitorScore == null || candidateScore > bestCompetitorScore) {
        bestCompetitor = candidate;
        bestCompetitorScore = candidateScore;
      }
    }

    final double? llr = bestCompetitorScore == null
        ? null
        : (expectedScore - bestCompetitorScore) / math.max(1, count);
    return CtcPhoneScore(
      expectedTokenId: expectedTokenId,
      expectedLogLikelihood: expectedScore,
      bestCompetitorTokenId: bestCompetitor,
      bestCompetitorLogLikelihood: bestCompetitorScore,
      logLikelihoodRatioPerFrame: llr,
      frameCount: count,
      source: batch.source,
    );
  }

  void _validateCandidate(CtcFrameBatch batch, int candidate) {
    if (candidate < 0 || candidate >= batch.classCount || candidate == batch.blankId) {
      throw ArgumentError('Invalid non-blank CTC candidate id $candidate.');
    }
  }

  double _singlePhoneForward(
    CtcFrameBatch batch,
    int start,
    int endExclusive,
    int tokenId,
  ) {
    // Expanded CTC target for one phone: blank -> phone -> blank.
    double blankBefore = batch.logProb(start, batch.blankId);
    double phone = batch.logProb(start, tokenId);
    double blankAfter = double.negativeInfinity;
    for (int frame = start + 1; frame < endExclusive; frame++) {
      final double currentBlank = batch.logProb(frame, batch.blankId);
      final double currentPhone = batch.logProb(frame, tokenId);
      final double nextBlank = blankBefore + currentBlank;
      final double nextPhone = _logSumExp(blankBefore, phone) + currentPhone;
      blankAfter = _logSumExp(blankAfter, phone) + currentBlank;
      blankBefore = nextBlank;
      phone = nextPhone;
    }
    return _logSumExp(phone, blankAfter);
  }

  double _logSumExp(double a, double b) {
    final double maxValue = math.max(a, b).toDouble();
    if (maxValue == double.negativeInfinity) return maxValue;
    return maxValue + math.log(math.exp(a - maxValue) + math.exp(b - maxValue));
  }
}
