import 'dart:math' as math;

/// Unicode code points used when analysing Uthmani-script Arabic text.
class ArabicChars {
  ArabicChars._();

  static const int hamza = 0x0621;
  static const int alefMadda = 0x0622;
  static const int alefHamzaAbove = 0x0623;
  static const int wawHamza = 0x0624;
  static const int alefHamzaBelow = 0x0625;
  static const int yehHamza = 0x0626;
  static const int alef = 0x0627;
  static const int baa = 0x0628;
  static const int tehMarbuta = 0x0629;
  static const int teh = 0x062A;
  static const int lam = 0x0644;
  static const int meem = 0x0645;
  static const int noon = 0x0646;
  static const int heh = 0x0647;
  static const int waw = 0x0648;
  static const int alefMaksura = 0x0649;
  static const int yeh = 0x064A;
  static const int alefWasla = 0x0671;

  static const int fathatan = 0x064B;
  static const int dammatan = 0x064C;
  static const int kasratan = 0x064D;
  static const int fatha = 0x064E;
  static const int damma = 0x064F;
  static const int kasra = 0x0650;
  static const int shadda = 0x0651;
  static const int sukun = 0x0652;
  static const int maddah = 0x0653;
  static const int superscriptAlef = 0x0670;
  static const int roundedZero = 0x06DF;
  static const int rectangularZero = 0x06E0;
  static const int dottedSukun = 0x06E1;
  static const int smallWaw = 0x06E5;
  static const int smallYeh = 0x06E6;

  /// Letters after which a noon sakinah / tanween is hidden (ikhfa).
  static const Set<int> ikhfaLetters = <int>{
    0x0635, 0x0630, 0x062B, 0x0643, 0x062C, //
    0x0634, 0x0642, 0x0633, 0x062F, 0x0637,
    0x0632, 0x0641, 0x062A, 0x0636, 0x0638,
  };

  /// Letters of idgham with ghunna (ي ن م و).
  static const Set<int> ghunnaIdghamLetters = <int>{
    0x064A, 0x0646, 0x0645, 0x0648,
  };

  /// Qalqala letters (ق ط ب ج د).
  static const Set<int> qalqalaLetters = <int>{
    0x0642, 0x0637, 0x0628, 0x062C, 0x062F,
  };

  /// Heavy letters (خ ص ض غ ط ق ظ).
  static const Set<int> heavyLetters = <int>{
    0x0635, 0x0636, 0x0637, 0x0638, 0x063A, 0x062E, 0x0642,
  };
}

bool isArabicBaseLetter(int c) {
  return (c >= 0x0621 && c <= 0x063A) ||
      (c >= 0x0641 && c <= 0x064A) ||
      c == 0x0671;
}

bool containsArabicBaseLetter(String text) {
  for (final int c in text.codeUnits) {
    if (isArabicBaseLetter(c)) {
      return true;
    }
  }
  return false;
}

/// One base letter together with the marks attached to it.
class ArabicLetter {
  ArabicLetter(this.base);

  final int base;
  int vowel = 0;
  int tanween = 0;
  bool shadda = false;
  bool sukun = false;
  bool superAlef = false;
  bool maddah = false;
  bool smallWaw = false;
  bool smallYeh = false;
  bool silent = false;

  bool get hasHaraka => vowel != 0 || tanween != 0;

  bool get isHamzaClass =>
      base == ArabicChars.hamza ||
      base == ArabicChars.alefMadda ||
      base == ArabicChars.alefHamzaAbove ||
      base == ArabicChars.wawHamza ||
      base == ArabicChars.alefHamzaBelow ||
      base == ArabicChars.yehHamza;
}

List<ArabicLetter> parseArabicWord(String word) {
  final List<ArabicLetter> letters = <ArabicLetter>[];
  for (final int c in word.codeUnits) {
    if (isArabicBaseLetter(c)) {
      letters.add(ArabicLetter(c));
      continue;
    }
    if (letters.isEmpty) {
      continue;
    }
    final ArabicLetter l = letters.last;
    if (c == ArabicChars.fatha || c == ArabicChars.damma || c == ArabicChars.kasra) {
      l.vowel = c;
    } else if (c == ArabicChars.fathatan ||
        c == ArabicChars.dammatan ||
        c == ArabicChars.kasratan) {
      l.tanween = c;
    } else if (c == ArabicChars.shadda) {
      l.shadda = true;
    } else if (c == ArabicChars.sukun || c == ArabicChars.dottedSukun) {
      l.sukun = true;
    } else if (c == ArabicChars.superscriptAlef) {
      l.superAlef = true;
    } else if (c == ArabicChars.maddah) {
      l.maddah = true;
    } else if (c == ArabicChars.smallWaw) {
      l.smallWaw = true;
    } else if (c == ArabicChars.smallYeh) {
      l.smallYeh = true;
    } else if (c == ArabicChars.roundedZero || c == ArabicChars.rectangularZero) {
      l.silent = true;
    }
  }
  return letters;
}

/// True when [letters] starts with a silent article lam, e.g. the lam of
/// "ٱلرَّحْمَٰنِ" which is not pronounced before a sun letter.
bool isSilentArticleLam(List<ArabicLetter> letters, int i) {
  final ArabicLetter l = letters[i];
  return l.base == ArabicChars.lam &&
      !l.hasHaraka &&
      !l.sukun &&
      !l.shadda &&
      i > 0 &&
      letters[i - 1].base == ArabicChars.alefWasla &&
      i + 1 < letters.length &&
      letters[i + 1].shadda;
}

/// The first letter actually pronounced in [word] (skips hamzat wasl and
/// the silent article lam). Null if the word has no pronounced letter.
ArabicLetter? firstSoundLetter(String word) {
  final List<ArabicLetter> letters = parseArabicWord(word);
  for (int i = 0; i < letters.length; i++) {
    final ArabicLetter l = letters[i];
    if (l.silent || l.base == ArabicChars.alefWasla) {
      continue;
    }
    if (isSilentArticleLam(letters, i)) {
      continue;
    }
    return l;
  }
  return null;
}

/// Splits an ayah into words. A token made only of marks (such as a waqf
/// sign) is attached to the previous word.
List<String> splitAyahWords(String text) {
  final List<String> words = <String>[];
  for (final String token in text.split(RegExp(r'\s+'))) {
    if (token.isEmpty) {
      continue;
    }
    if (!containsArabicBaseLetter(token) && words.isNotEmpty) {
      words[words.length - 1] = words.last + token;
    } else {
      words.add(token);
    }
  }
  return words;
}

/// First letter of [word] with its marks (used as a hint in memorization mode).
/// When the word starts with hamzat wasl, the next letter is included too.
String firstLetterWithMarks(String word) {
  final StringBuffer buffer = StringBuffer();
  int bases = 0;
  int needed = 1;
  for (final int c in word.codeUnits) {
    if (isArabicBaseLetter(c)) {
      if (bases == 0 && c == ArabicChars.alefWasla) {
        needed = 2;
      }
      if (bases >= needed) {
        break;
      }
      bases++;
      buffer.writeCharCode(c);
    } else if (bases > 0) {
      buffer.writeCharCode(c);
    }
  }
  return buffer.toString();
}

int baseLetterCount(String word) {
  int count = 0;
  for (final int c in word.codeUnits) {
    if (isArabicBaseLetter(c)) {
      count++;
    }
  }
  return count;
}

/// A short dotted mask for a hidden word.
String maskWord(String word) {
  final int count = math.max(2, math.min(baseLetterCount(word), 6)).toInt();
  return List<String>.filled(count, '•').join(' ');
}

String toArabicDigits(int number) {
  const List<String> digits = <String>[
    '٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩', //
  ];
  final StringBuffer buffer = StringBuffer();
  for (final String ch in number.toString().split('')) {
    buffer.write(digits[int.parse(ch)]);
  }
  return buffer.toString();
}
