import '../tajweed/tajweed_rule.dart';

class Surah {
  const Surah({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.revelation,
    required this.ayahCount,
  });

  final int id;
  final String nameAr;
  final String nameEn;
  final String revelation;
  final int ayahCount;
}

class AyahWord {
  const AyahWord({
    required this.position,
    required this.text,
    required this.phonemes,
    required this.rules,
  });

  final int position;
  final String text;
  final String phonemes;
  final List<TajweedRule> rules;
}

class Ayah {
  const Ayah({
    required this.id,
    required this.surahId,
    required this.number,
    required this.text,
    required this.words,
  });

  final int id;
  final int surahId;
  final int number;
  final String text;
  final List<AyahWord> words;
}

class SurahOverview {
  const SurahOverview({
    required this.surah,
    required this.masteredAyahs,
    required this.tajweedChecked,
    required this.tajweedPassed,
  });

  final Surah surah;
  final int masteredAyahs;
  final int tajweedChecked;
  final int tajweedPassed;

  double get memorizationFraction =>
      surah.ayahCount == 0 ? 0 : masteredAyahs / surah.ayahCount;

  /// Null when no word carrying a tajweed rule was checked yet.
  double? get tajweedAccuracy =>
      tajweedChecked == 0 ? null : tajweedPassed / tajweedChecked;
}

class MistakeSummary {
  const MistakeSummary({required this.ruleType, required this.count});

  final String ruleType;
  final int count;
}

class MistakeRecord {
  const MistakeRecord({
    required this.wordText,
    required this.ruleType,
    required this.surahId,
    required this.ayahNumber,
    required this.createdAt,
  });

  final String wordText;
  final String ruleType;
  final int surahId;
  final int ayahNumber;
  final DateTime createdAt;
}

class StatsSnapshot {
  const StatsSnapshot({
    required this.masteredAyahs,
    required this.totalAyahs,
    required this.attempts,
    required this.wordsChecked,
    required this.wordsCorrect,
    required this.tajweedChecked,
    required this.tajweedPassed,
    required this.totalMistakes,
    required this.topMistakes,
    required this.recentMistakes,
  });

  final int masteredAyahs;
  final int totalAyahs;
  final int attempts;
  final int wordsChecked;
  final int wordsCorrect;
  final int tajweedChecked;
  final int tajweedPassed;
  final int totalMistakes;
  final List<MistakeSummary> topMistakes;
  final List<MistakeRecord> recentMistakes;

  double? get tajweedAccuracy =>
      tajweedChecked == 0 ? null : tajweedPassed / tajweedChecked;

  double? get wordAccuracy =>
      wordsChecked == 0 ? null : wordsCorrect / wordsChecked;
}
