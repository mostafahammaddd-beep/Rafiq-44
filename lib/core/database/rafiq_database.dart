import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/quran_seed.dart';
import '../tajweed/arabic_text.dart';
import '../tajweed/phonetic_script_builder.dart';
import '../tajweed/tajweed_analyzer.dart';
import '../tajweed/tajweed_rule.dart';
import 'models.dart';

/// Mastery value (0-100) from which an ayah counts as mastered.
const int kMasteredThreshold = 80;

class RafiqDatabase {
  Database? _db;

  /// Bump when the seeded content (text, phonemes, rules) changes.
  static const int _dbVersion = 1;

  Future<void> open() async {
    if (_db != null) {
      return;
    }
    final Directory dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final String path = p.join(dir.path, 'rafiq.db');
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (Database db, int version) async {
        await _createSchema(db);
        await _seedContent(db);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        await db.execute('DELETE FROM words');
        await db.execute('DELETE FROM ayahs');
        await db.execute('DELETE FROM surahs');
        await _seedContent(db);
      },
    );
  }

  Future<void> close() async {
    final Database? db = _db;
    _db = null;
    if (db != null) {
      await db.close();
    }
  }

  Database _requireDb() {
    final Database? db = _db;
    if (db == null) {
      throw StateError('RafiqDatabase is not open');
    }
    return db;
  }

  // ---------------------------------------------------------------- schema

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE surahs (
  id INTEGER PRIMARY KEY,
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,
  revelation TEXT NOT NULL,
  ayah_count INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE ayahs (
  id INTEGER PRIMARY KEY,
  surah_id INTEGER NOT NULL,
  ayah_number INTEGER NOT NULL,
  text TEXT NOT NULL,
  UNIQUE (surah_id, ayah_number)
)''');
    await db.execute('''
CREATE TABLE words (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ayah_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  text TEXT NOT NULL,
  phonemes TEXT NOT NULL,
  rules TEXT NOT NULL,
  UNIQUE (ayah_id, position)
)''');
    await db.execute('''
CREATE TABLE memorization_progress (
  ayah_id INTEGER PRIMARY KEY,
  mastery INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0,
  words_checked INTEGER NOT NULL DEFAULT 0,
  words_correct INTEGER NOT NULL DEFAULT 0,
  tajweed_checked INTEGER NOT NULL DEFAULT 0,
  tajweed_passed INTEGER NOT NULL DEFAULT 0,
  last_practiced INTEGER
)''');
    await db.execute('''
CREATE TABLE tajweed_mistakes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ayah_id INTEGER NOT NULL,
  word_position INTEGER NOT NULL,
  word_text TEXT NOT NULL,
  rule_type TEXT NOT NULL,
  message TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  created_at_iso TEXT NOT NULL
)''');
    await db.execute(
      'CREATE INDEX idx_mistakes_rule ON tajweed_mistakes (rule_type)',
    );
  }

  static Future<void> _seedContent(Database db) async {
    final Batch batch = db.batch();
    for (final SurahSeed surah in kSurahSeeds) {
      batch.insert('surahs', <String, Object?>{
        'id': surah.id,
        'name_ar': surah.nameAr,
        'name_en': surah.nameEn,
        'revelation': surah.revelation,
        'ayah_count': surah.ayahs.length,
      });
      for (int a = 0; a < surah.ayahs.length; a++) {
        final int number = a + 1;
        final int ayahId = surah.id * 1000 + number;
        final String ayahText = surah.ayahs[a];
        batch.insert('ayahs', <String, Object?>{
          'id': ayahId,
          'surah_id': surah.id,
          'ayah_number': number,
          'text': ayahText,
        });

        final List<String> words = splitAyahWords(ayahText);
        for (int w = 0; w < words.length; w++) {
          final bool isLast = w == words.length - 1;
          final ArabicLetter? nextFirst =
              isLast ? null : firstSoundLetter(words[w + 1]);
          final List<TajweedRule> rules = analyzeTajweedRules(
            letters: parseArabicWord(words[w]),
            isAyahEnd: isLast,
            nextFirst: nextFirst,
          );
          batch.insert('words', <String, Object?>{
            'ayah_id': ayahId,
            'position': w,
            'text': words[w],
            'phonemes': buildPhoneticScript(words[w], atWaqf: isLast),
            'rules': rules.map((TajweedRule r) => r.code).join(','),
          });
        }
      }
    }
    await batch.commit(noResult: true);
  }

  // --------------------------------------------------------------- queries

  Future<List<Surah>> getSurahs() async {
    final Database db = _requireDb();
    final List<Map<String, Object?>> rows =
        await db.query('surahs', orderBy: 'id ASC');
    return rows.map(_surahFromRow).toList();
  }

  Surah _surahFromRow(Map<String, Object?> row) {
    return Surah(
      id: row['id'] as int,
      nameAr: row['name_ar'] as String,
      nameEn: row['name_en'] as String,
      revelation: row['revelation'] as String,
      ayahCount: row['ayah_count'] as int,
    );
  }

  Future<List<SurahOverview>> getSurahOverviews() async {
    final Database db = _requireDb();
    final List<Map<String, Object?>> rows = await db.rawQuery('''
SELECT s.id, s.name_ar, s.name_en, s.revelation, s.ayah_count,
  COALESCE(SUM(CASE WHEN p.mastery >= $kMasteredThreshold THEN 1 ELSE 0 END), 0) AS mastered,
  COALESCE(SUM(p.tajweed_checked), 0) AS tchecked,
  COALESCE(SUM(p.tajweed_passed), 0) AS tpassed
FROM surahs s
LEFT JOIN ayahs a ON a.surah_id = s.id
LEFT JOIN memorization_progress p ON p.ayah_id = a.id
GROUP BY s.id
ORDER BY s.id ASC
''');
    return rows.map((Map<String, Object?> row) {
      return SurahOverview(
        surah: _surahFromRow(row),
        masteredAyahs: (row['mastered'] as num).toInt(),
        tajweedChecked: (row['tchecked'] as num).toInt(),
        tajweedPassed: (row['tpassed'] as num).toInt(),
      );
    }).toList();
  }

  Future<List<Ayah>> getAyahsWithWords(int surahId) async {
    final Database db = _requireDb();
    final List<Map<String, Object?>> ayahRows = await db.query(
      'ayahs',
      where: 'surah_id = ?',
      whereArgs: <Object?>[surahId],
      orderBy: 'ayah_number ASC',
    );
    final List<Map<String, Object?>> wordRows = await db.rawQuery(
      '''
SELECT w.ayah_id, w.position, w.text, w.phonemes, w.rules
FROM words w
JOIN ayahs a ON a.id = w.ayah_id
WHERE a.surah_id = ?
ORDER BY w.ayah_id ASC, w.position ASC
''',
      <Object?>[surahId],
    );

    final Map<int, List<AyahWord>> byAyah = <int, List<AyahWord>>{};
    for (final Map<String, Object?> row in wordRows) {
      final int ayahId = row['ayah_id'] as int;
      byAyah.putIfAbsent(ayahId, () => <AyahWord>[]).add(
            AyahWord(
              position: row['position'] as int,
              text: row['text'] as String,
              phonemes: row['phonemes'] as String,
              rules: parseRuleCodes(row['rules'] as String),
            ),
          );
    }

    return ayahRows.map((Map<String, Object?> row) {
      final int id = row['id'] as int;
      return Ayah(
        id: id,
        surahId: row['surah_id'] as int,
        number: row['ayah_number'] as int,
        text: row['text'] as String,
        words: byAyah[id] ?? const <AyahWord>[],
      );
    }).toList();
  }

  /// ayah id -> mastery (0-100) for the given surah.
  Future<Map<int, int>> getMasteryByAyah(int surahId) async {
    final Database db = _requireDb();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
SELECT p.ayah_id, p.mastery
FROM memorization_progress p
JOIN ayahs a ON a.id = p.ayah_id
WHERE a.surah_id = ?
''',
      <Object?>[surahId],
    );
    final Map<int, int> result = <int, int>{};
    for (final Map<String, Object?> row in rows) {
      result[row['ayah_id'] as int] = row['mastery'] as int;
    }
    return result;
  }

  // ---------------------------------------------------------------- writes

  Future<void> recordAyahResult({
    required int ayahId,
    required int wordsChecked,
    required int wordsCorrect,
    required int tajweedChecked,
    required int tajweedPassed,
  }) async {
    final Database db = _requireDb();
    final double wordAccuracy =
        wordsChecked == 0 ? 0.0 : wordsCorrect / wordsChecked;
    final double tajweedAccuracy =
        tajweedChecked == 0 ? wordAccuracy : tajweedPassed / tajweedChecked;
    final int score =
        ((0.7 * wordAccuracy + 0.3 * tajweedAccuracy) * 100).round();
    final int now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        'memorization_progress',
        where: 'ayah_id = ?',
        whereArgs: <Object?>[ayahId],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert('memorization_progress', <String, Object?>{
          'ayah_id': ayahId,
          'mastery': math.max(0, math.min(100, score)).toInt(),
          'attempts': 1,
          'words_checked': wordsChecked,
          'words_correct': wordsCorrect,
          'tajweed_checked': tajweedChecked,
          'tajweed_passed': tajweedPassed,
          'last_practiced': now,
        });
        return;
      }
      final Map<String, Object?> row = rows.first;
      final int oldMastery = row['mastery'] as int;
      final int blended = ((oldMastery * 0.6) + (score * 0.4)).round();
      final int newMastery = math.max(0, math.min(100, blended)).toInt();
      await txn.update(
        'memorization_progress',
        <String, Object?>{
          'mastery': newMastery,
          'attempts': (row['attempts'] as int) + 1,
          'words_checked': (row['words_checked'] as int) + wordsChecked,
          'words_correct': (row['words_correct'] as int) + wordsCorrect,
          'tajweed_checked': (row['tajweed_checked'] as int) + tajweedChecked,
          'tajweed_passed': (row['tajweed_passed'] as int) + tajweedPassed,
          'last_practiced': now,
        },
        where: 'ayah_id = ?',
        whereArgs: <Object?>[ayahId],
      );
    });
  }

  Future<void> logMistake({
    required int ayahId,
    required int wordPosition,
    required String wordText,
    required String ruleType,
    required String message,
  }) async {
    final Database db = _requireDb();
    final DateTime now = DateTime.now();
    await db.insert('tajweed_mistakes', <String, Object?>{
      'ayah_id': ayahId,
      'word_position': wordPosition,
      'word_text': wordText,
      'rule_type': ruleType,
      'message': message,
      'created_at': now.millisecondsSinceEpoch,
      'created_at_iso': now.toIso8601String(),
    });
  }

  // ----------------------------------------------------------------- stats

  Future<StatsSnapshot> getStats() async {
    final Database db = _requireDb();

    final List<Map<String, Object?>> totals = await db.rawQuery('''
SELECT
  COALESCE(SUM(CASE WHEN mastery >= $kMasteredThreshold THEN 1 ELSE 0 END), 0) AS mastered,
  COALESCE(SUM(attempts), 0) AS attempts,
  COALESCE(SUM(words_checked), 0) AS wc,
  COALESCE(SUM(words_correct), 0) AS wk,
  COALESCE(SUM(tajweed_checked), 0) AS tc,
  COALESCE(SUM(tajweed_passed), 0) AS tp
FROM memorization_progress
''');
    final Map<String, Object?> t = totals.first;

    final int totalAyahs =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ayahs')) ??
            0;
    final int totalMistakes = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tajweed_mistakes'),
        ) ??
        0;

    final List<Map<String, Object?>> topRows = await db.rawQuery('''
SELECT rule_type, COUNT(*) AS c
FROM tajweed_mistakes
GROUP BY rule_type
ORDER BY c DESC
LIMIT 5
''');
    final List<Map<String, Object?>> recentRows = await db.rawQuery('''
SELECT m.word_text, m.rule_type, m.created_at, a.surah_id, a.ayah_number
FROM tajweed_mistakes m
JOIN ayahs a ON a.id = m.ayah_id
ORDER BY m.created_at DESC
LIMIT 8
''');

    return StatsSnapshot(
      masteredAyahs: (t['mastered'] as num).toInt(),
      totalAyahs: totalAyahs,
      attempts: (t['attempts'] as num).toInt(),
      wordsChecked: (t['wc'] as num).toInt(),
      wordsCorrect: (t['wk'] as num).toInt(),
      tajweedChecked: (t['tc'] as num).toInt(),
      tajweedPassed: (t['tp'] as num).toInt(),
      totalMistakes: totalMistakes,
      topMistakes: topRows.map((Map<String, Object?> row) {
        return MistakeSummary(
          ruleType: row['rule_type'] as String,
          count: (row['c'] as num).toInt(),
        );
      }).toList(),
      recentMistakes: recentRows.map((Map<String, Object?> row) {
        return MistakeRecord(
          wordText: row['word_text'] as String,
          ruleType: row['rule_type'] as String,
          surahId: row['surah_id'] as int,
          ayahNumber: row['ayah_number'] as int,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (row['created_at'] as num).toInt(),
          ),
        );
      }).toList(),
    );
  }
}
