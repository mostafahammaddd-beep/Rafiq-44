class HarakaEstimate {
  const HarakaEstimate({
    required this.durationMs,
    required this.estimatedHarakat,
    required this.baselineMs,
    required this.calibrationSamples,
  });

  final double durationMs;
  final double? estimatedHarakat;
  final double? baselineMs;
  final int calibrationSamples;

  bool get isCalibrated => estimatedHarakat != null && baselineMs != null;
}

/// Robust, user-specific tempo baseline for short vowel nuclei.
///
/// Call [observeTrustedShortVowel] only for a manually/algorithmically verified
/// short-vowel span. Do not feed madd spans, silence, stop bursts, or low
/// confidence alignments into the baseline. The estimate is a learning aid,
/// not a standalone tajweed ruling.
class AdaptiveHarakaTracker {
  AdaptiveHarakaTracker({this.maxSamples = 31, this.minSamples = 5}) {
    if (maxSamples < 5 || minSamples < 3 || minSamples > maxSamples) {
      throw ArgumentError('Invalid tempo-tracker sample configuration.');
    }
  }

  final int maxSamples;
  final int minSamples;
  final List<double> _samples = <double>[];

  int get sampleCount => _samples.length;
  double? get baselineMs => _samples.length < minSamples ? null : _median(_samples);

  bool observeTrustedShortVowel({
    required double durationMs,
    required double confidence,
  }) {
    if (!durationMs.isFinite || durationMs < 35 || durationMs > 650) {
      return false;
    }
    if (!confidence.isFinite || confidence < 0.85 || confidence > 1.0) {
      return false;
    }

    final double? current = baselineMs;
    if (current != null) {
      // Reject a severe outlier rather than teach the tracker from a likely
      // misalignment or elongated consonant.
      final double ratio = durationMs / current;
      if (ratio < 0.35 || ratio > 2.8) {
        return false;
      }
    }
    _samples.add(durationMs);
    if (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
    return true;
  }

  HarakaEstimate estimate(double durationMs) {
    final double? baseline = baselineMs;
    final double? count = baseline == null || !durationMs.isFinite || durationMs < 0
        ? null
        : durationMs / baseline;
    return HarakaEstimate(
      durationMs: durationMs,
      estimatedHarakat: count,
      baselineMs: baseline,
      calibrationSamples: _samples.length,
    );
  }

  void reset() => _samples.clear();

  double _median(List<double> input) {
    final List<double> sorted = List<double>.of(input)..sort();
    final int middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }
}

/// A conservative range check which deliberately never decides with no
/// tempo calibration or an untrusted duration measurement.
class HarakaRangeAssessment {
  const HarakaRangeAssessment({
    required this.estimate,
    required this.minimum,
    required this.maximum,
  });

  final HarakaEstimate estimate;
  final double minimum;
  final double maximum;

  bool? get withinRange {
    final double? value = estimate.estimatedHarakat;
    if (value == null || minimum > maximum) {
      return null;
    }
    return value >= minimum && value <= maximum;
  }
}

/// Median helper exported for deterministic unit tests of the tempo policy.
double medianDurationMs(Iterable<double> values) {
  final List<double> sorted = values.where((double value) => value.isFinite).toList()
    ..sort();
  if (sorted.isEmpty) {
    return double.nan;
  }
  final int middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2.0;
}
