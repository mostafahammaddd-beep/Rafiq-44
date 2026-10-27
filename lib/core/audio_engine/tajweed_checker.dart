import '../tajweed/tajweed_rule.dart';
import 'recitation_evaluator.dart';

/// A rule-level finding from an acoustic diagnostic backend.
class TajweedFinding {
  const TajweedFinding({required this.rule, required this.message});

  final TajweedRule rule;
  final String message;
}

/// Conservative compatibility adapter for the legacy text-only evaluator.
///
/// The old implementation inferred madd timing from repeated characters and
/// inferred ghunna/ikhfa/qalqala/tafkhim from Arabic-character presence. Those
/// checks are not valid measurements of the model's 251-class acoustic tokens,
/// and they cannot measure duration. Keep the old method signature so callers
/// remain compatible, but do not issue a rule-level verdict from decoded text
/// alone. The CTC diagnostics layer consumes typed frame/alignment evidence.
class TajweedChecker {
  const TajweedChecker({required this.lexiconMode});

  final bool lexiconMode;

  TajweedFinding? check(WordTarget target, String heard) {
    // Inputs are accepted for API compatibility only. Without mapped CTC token
    // evidence, frame timing, and calibration, a rule-level conclusion would
    // manufacture confidence that this backend does not have.
    return null;
  }
}
