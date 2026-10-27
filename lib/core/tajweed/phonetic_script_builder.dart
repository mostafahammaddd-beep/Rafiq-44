import 'arabic_text.dart';

/// Builds an approximate phonetic script (Arabic letters + short vowels)
/// from an Uthmani word.
///
/// This is only used when the model's own lexicon (quran_phoneme_words.json)
/// is not available. It follows the conventions of the model's script as far
/// as they are public: doubled letters for shadda, dropped sukun, silent
/// letters removed, long vowels written as letters, waqf at the end of an ayah.
String buildPhoneticScript(String word, {required bool atWaqf}) {
  final List<ArabicLetter> letters = parseArabicWord(word);
  final StringBuffer out = StringBuffer();
  int lastVowel = 0;
  bool prevHadFathatan = false;
  final int lastIndex = letters.length - 1;

  for (int i = 0; i < letters.length; i++) {
    final ArabicLetter l = letters[i];
    if (l.silent || l.base == ArabicChars.alefWasla) {
      continue;
    }
    if (isSilentArticleLam(letters, i)) {
      continue;
    }
    if (l.base == ArabicChars.alef) {
      if (prevHadFathatan && !atWaqf) {
        prevHadFathatan = false;
        continue;
      }
      out.writeCharCode(ArabicChars.alef);
      prevHadFathatan = false;
      continue;
    }

    int emitted = l.base;
    if (l.isHamzaClass) {
      emitted = ArabicChars.hamza;
    } else if (l.base == ArabicChars.tehMarbuta) {
      emitted = (atWaqf && i == lastIndex) ? ArabicChars.heh : ArabicChars.teh;
    } else if (l.base == ArabicChars.alefMaksura) {
      emitted = (lastVowel == ArabicChars.fatha || l.superAlef)
          ? ArabicChars.alef
          : ArabicChars.yeh;
    }

    out.writeCharCode(emitted);
    if (l.shadda) {
      out.writeCharCode(emitted);
    }

    if (l.vowel != 0) {
      out.writeCharCode(l.vowel);
      lastVowel = l.vowel;
    } else if (l.tanween != 0 && !atWaqf) {
      final int vowel = _vowelOfTanween(l.tanween);
      out.writeCharCode(vowel);
      out.writeCharCode(ArabicChars.noon);
      lastVowel = vowel;
    }

    if (l.superAlef && l.base != ArabicChars.alefMaksura) {
      if (l.vowel == 0) {
        out.writeCharCode(ArabicChars.fatha);
      }
      out.writeCharCode(ArabicChars.alef);
      lastVowel = ArabicChars.fatha;
    }
    if (l.smallWaw) {
      out.writeCharCode(ArabicChars.waw);
    }
    if (l.smallYeh) {
      out.writeCharCode(ArabicChars.yeh);
    }
    prevHadFathatan = l.tanween == ArabicChars.fathatan;
  }

  String result = out.toString();
  if (atWaqf) {
    result = _stripTrailingVowels(result);
  }
  return result;
}

int _vowelOfTanween(int tanween) {
  if (tanween == ArabicChars.fathatan) {
    return ArabicChars.fatha;
  }
  if (tanween == ArabicChars.dammatan) {
    return ArabicChars.damma;
  }
  return ArabicChars.kasra;
}

String _stripTrailingVowels(String s) {
  int end = s.length;
  while (end > 0) {
    final int c = s.codeUnitAt(end - 1);
    if (c == ArabicChars.fatha || c == ArabicChars.damma || c == ArabicChars.kasra) {
      end--;
    } else {
      break;
    }
  }
  return s.substring(0, end);
}
