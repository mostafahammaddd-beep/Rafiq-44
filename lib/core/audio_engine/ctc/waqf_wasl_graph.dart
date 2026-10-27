/// Explicit pronunciation variants for a single word in the target ayah.
/// The caller supplies vetted variants; this class never invents Quranic
/// pronunciation rules from arbitrary strings.
class PronunciationAlternatives {
  const PronunciationAlternatives({
    required this.wordIndex,
    required this.waslPhonemes,
    this.waqfPhonemes,
  });

  final int wordIndex;
  final List<int> waslPhonemes;
  final List<int>? waqfPhonemes;
}

enum PronunciationMode { wasl, waqf }

class PauseEvidence {
  const PauseEvidence({
    required this.durationMs,
    required this.fromVad,
    required this.endpoint,
    required this.confidence,
  });

  final double durationMs;
  final bool fromVad;
  final bool endpoint;
  final double confidence;

  bool get supportsWaqf =>
      durationMs >= 260 && confidence >= 0.65 && (fromVad || endpoint);
}

class PronunciationCandidate {
  const PronunciationCandidate({
    required this.wordIndex,
    required this.mode,
    required this.phonemeIds,
    required this.transitionCost,
  });

  final int wordIndex;
  final PronunciationMode mode;
  final List<int> phonemeIds;
  final double transitionCost;
}

/// A DAG over word boundaries. Each word edge has up to two pronunciation
/// variants (wasl/waqf); all transitions advance from word i to i+1, so cycles
/// cannot be introduced by pauses. Waqf availability is only as accurate as
/// the supplied vetted alternate phoneme sequence.
class WaqfWaslGraph {
  WaqfWaslGraph(List<PronunciationAlternatives> words)
      : words = List<PronunciationAlternatives>.unmodifiable(words) {
    for (int i = 0; i < this.words.length; i++) {
      if (this.words[i].wordIndex != i) {
        throw ArgumentError('Word graph indices must be contiguous from zero.');
      }
      if (this.words[i].waslPhonemes.isEmpty) {
        throw ArgumentError('Word $i must provide a wasl phoneme sequence.');
      }
      if (this.words[i].waqfPhonemes != null && this.words[i].waqfPhonemes!.isEmpty) {
        throw ArgumentError('Word $i has an empty waqf alternative.');
      }
    }
  }

  final List<PronunciationAlternatives> words;
  int get nodeCount => words.length + 1;

  List<PronunciationCandidate> candidatesFor(
    int wordIndex, {
    required PauseEvidence pause,
  }) {
    if (wordIndex < 0 || wordIndex >= words.length) {
      return const <PronunciationCandidate>[];
    }
    final PronunciationAlternatives word = words[wordIndex];
    final List<PronunciationCandidate> candidates = <PronunciationCandidate>[
      PronunciationCandidate(
        wordIndex: wordIndex,
        mode: PronunciationMode.wasl,
        phonemeIds: word.waslPhonemes,
        transitionCost: pause.supportsWaqf ? 1.5 : 0.0,
      ),
    ];
    final List<int>? waqf = word.waqfPhonemes;
    if (waqf != null) {
      candidates.add(PronunciationCandidate(
        wordIndex: wordIndex,
        mode: PronunciationMode.waqf,
        phonemeIds: waqf,
        transitionCost: pause.supportsWaqf ? 0.0 : 1.25,
      ));
    }
    candidates.sort((PronunciationCandidate a, PronunciationCandidate b) =>
        a.transitionCost.compareTo(b.transitionCost));
    return List<PronunciationCandidate>.unmodifiable(candidates);
  }
}
