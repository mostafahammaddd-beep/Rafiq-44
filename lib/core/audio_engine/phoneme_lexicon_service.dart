import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ctc/token_table.dart';

/// Phoneme lexicon shipped with the model (quran_phoneme_words.json).
///
/// The file format is not formally documented, so parsing is tolerant: it
/// accepts a map keyed by "surah:ayah" (value = list of phonetic words, or a
/// map holding such a list), a map surah -> ayah -> words, or a list of ayah
/// entries. An ayah is only used when its word count matches the Uthmani
/// word count, otherwise the app falls back to its approximate phonetizer.
class PhonemeLexiconService {
  Map<String, List<String>> _words = <String, List<String>>{};
  TokenTable? _tokenTable;
  String? tokenTableError;

  bool get isLoaded => _words.isNotEmpty;
  bool get tokenTableLoaded => _tokenTable != null;
  int get ayahCount => _words.length;

  /// Loads the actual model vocabulary. Expected references are tokenized only
  /// when every symbol can be represented exactly by this vocabulary.
  Future<void> loadTokens(String path, {int blankId = 250}) async {
    try {
      final List<String> lines = await File(path).readAsLines();
      _tokenTable = TokenTable.fromLines(lines, expectedBlankId: blankId);
      tokenTableError = null;
    } catch (error) {
      _tokenTable = null;
      tokenTableError = error.toString();
    }
  }

  List<String>? tokenLabelsFor(String phonemes) {
    final List<String>? tokens = _tokenTable?.tokenizeExpectedPhonemes(phonemes);
    // An empty reference is not a valid pronunciation target. Returning null
    // forces the explicit fallback path instead of auto-marking a word correct.
    if (tokens == null || tokens.isEmpty) return null;
    return tokens;
  }

  Future<void> load(String path) async {
    try {
      final String raw = await File(path).readAsString();
      _words = await compute(parseLexicon, raw);
    } catch (_) {
      _words = <String, List<String>>{};
    }
  }

  List<String>? wordsFor(int surah, int ayah) => _words['$surah:$ayah'];
}

final RegExp _ayahKey = RegExp(r'^(\d+)\s*[:_\-/]\s*(\d+)$');
final RegExp _digits = RegExp(r'^\d+$');

/// Top-level so it can run inside `compute`.
Map<String, List<String>> parseLexicon(String raw) {
  final Map<String, List<String>> result = <String, List<String>>{};
  final dynamic decoded = jsonDecode(raw);
  _collectLexicon(decoded, result);
  return result;
}

void _collectLexicon(dynamic decoded, Map<String, List<String>> result) {
  if (decoded is Map) {
    // Some exports wrap the canonical mapping under a named root key.
    const List<String> wrapperKeys = <String>[
      'data',
      'ayahs',
      'surahs',
      'ordered_quran_phonemes',
      'phoneme_lexicon',
    ];
    for (final String wrapper in wrapperKeys) {
      if (decoded.containsKey(wrapper)) {
        _collectLexicon(decoded[wrapper], result);
      }
    }

    decoded.forEach((dynamic key, dynamic value) {
      final String k = key.toString();
      final RegExpMatch? match = _ayahKey.firstMatch(k);
      if (match != null) {
        final List<String>? words = _wordsFromValue(value);
        if (words != null && words.isNotEmpty) {
          result['${int.parse(match.group(1)!)}:${int.parse(match.group(2)!)}'] = words;
        }
        return;
      }
      if (!_digits.hasMatch(k)) return;
      final int surah = int.parse(k);
      if (value is Map) {
        value.forEach((dynamic ayahKey, dynamic ayahValue) {
          final String ak = ayahKey.toString();
          if (!_digits.hasMatch(ak)) return;
          final List<String>? words = _wordsFromValue(ayahValue);
          if (words != null && words.isNotEmpty) {
            result['$surah:${int.parse(ak)}'] = words;
          }
        });
      } else if (value is List) {
        // Support the ordered [surah][ayah][word] tensor-like JSON form.
        for (int ayahIndex = 0; ayahIndex < value.length; ayahIndex++) {
          final List<String>? words = _wordsFromValue(value[ayahIndex]);
          if (words != null && words.isNotEmpty) {
            result['$surah:${ayahIndex + 1}'] = words;
          }
        }
      }
    });
  } else if (decoded is List) {
    for (int index = 0; index < decoded.length; index++) {
      final dynamic item = decoded[index];
      if (item is Map) {
        final int? surah = _asInt(
          item['surah'] ?? item['sura'] ?? item['surah_id'] ?? item['surah_index'] ?? item['surah_no'] ?? item['surahNumber'] ?? item['s'],
        );
        final int? ayah = _asInt(
          item['ayah'] ?? item['aya'] ?? item['ayah_number'] ?? item['ayah_index'] ?? item['ayah_no'] ?? item['ayahNumber'] ?? item['a'],
        );
        if (surah != null && ayah != null) {
          final List<String>? words = _wordsFromValue(item);
          if (words != null && words.isNotEmpty) {
            result['$surah:$ayah'] = words;
          }
        } else {
          _collectLexicon(item, result);
        }
      } else if (item is List) {
        // Support ordered [surah][ayah][phoneme-word] arrays, using one-based
        // Quran surah and ayah numbering for the array coordinates.
        for (int ayahIndex = 0; ayahIndex < item.length; ayahIndex++) {
          final List<String>? words = _wordsFromValue(item[ayahIndex]);
          if (words != null && words.isNotEmpty) {
            result['${index + 1}:${ayahIndex + 1}'] = words;
          }
        }
      }
    }
  }
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

List<String>? _wordsFromValue(dynamic value) {
  if (value is String) {
    final List<String> parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    return parts;
  }
  if (value is List) {
    final List<String> out = <String>[];
    for (final dynamic item in value) {
      if (item is String) {
        out.add(item);
      } else if (item is Map) {
        final dynamic p =
            item['phonemes'] ?? item['phoneme'] ?? item['phonetic'] ?? item['p'];
        if (p is String) {
          out.add(p);
        } else if (p is List) {
          out.add(p.join());
        } else {
          return null;
        }
      } else if (item is List) {
        out.add(item.join());
      } else {
        return null;
      }
    }
    return out;
  }
  if (value is Map) {
    const List<String> keys = <String>[
      'aya_phonemes_list',
      'phoneme_words',
      'phonetic_words',
      'words',
      'phonemes',
    ];
    for (final String key in keys) {
      if (value.containsKey(key)) {
        final List<String>? words = _wordsFromValue(value[key]);
        if (words != null && words.isNotEmpty) {
          return words;
        }
      }
    }
  }
  return null;
}
