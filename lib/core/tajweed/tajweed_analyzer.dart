import 'arabic_text.dart';
import 'tajweed_rule.dart';

/// Detects which tajweed rules apply inside one word, from its Uthmani text.
///
/// [nextFirst] is the first pronounced letter of the following word (null at
/// the end of an ayah, where we stop and therefore apply waqf rules).
List<TajweedRule> analyzeTajweedRules({
  required List<ArabicLetter> letters,
  required bool isAyahEnd,
  ArabicLetter? nextFirst,
}) {
  final List<TajweedRule> rules = <TajweedRule>[];
  void add(TajweedRule rule) {
    if (!rules.contains(rule)) {
      rules.add(rule);
    }
  }

  final List<ArabicLetter> eff = <ArabicLetter>[];
  for (final ArabicLetter l in letters) {
    if (!l.silent && l.base != ArabicChars.alefWasla) {
      eff.add(l);
    }
  }
  if (eff.isEmpty) {
    return rules;
  }

  // ---- madd ---------------------------------------------------------------
  for (int k = 0; k < eff.length; k++) {
    final ArabicLetter l = eff[k];
    final ArabicLetter? prev = k > 0 ? eff[k - 1] : null;
    final ArabicLetter? next = k + 1 < eff.length ? eff[k + 1] : null;
    if (!_isMaddLetter(l, prev)) {
      continue;
    }
    if (next == null) {
      if (!isAyahEnd && nextFirst != null && nextFirst.isHamzaClass) {
        add(TajweedRule.maddMunfasil);
      } else {
        add(TajweedRule.maddTabii);
      }
    } else if (next.isHamzaClass) {
      add(TajweedRule.maddMuttasil);
    } else if (next.shadda) {
      add(TajweedRule.maddLazim);
    } else {
      add(TajweedRule.maddTabii);
    }
    if (isAyahEnd &&
        next != null &&
        k + 2 == eff.length &&
        !next.shadda &&
        next.tanween == 0) {
      add(TajweedRule.maddArid);
    }
  }

  // ---- ghunna (noon / meem with shadda) -------------------------------------
  for (final ArabicLetter l in eff) {
    if (l.shadda && (l.base == ArabicChars.noon || l.base == ArabicChars.meem)) {
      add(TajweedRule.ghunna);
    }
  }

  // ---- ikhfa / idgham with ghunna inside the word ---------------------------
  for (int k = 0; k + 1 < eff.length; k++) {
    final ArabicLetter l = eff[k];
    final ArabicLetter nx = eff[k + 1];
    if (l.base == ArabicChars.noon &&
        !l.hasHaraka &&
        !l.shadda &&
        !l.superAlef &&
        !nx.shadda &&
        ArabicChars.ikhfaLetters.contains(nx.base)) {
      add(TajweedRule.ikhfa);
    }
  }

  // ---- noon sakinah / tanween / meem sakinah at the end of the word -------
  final ArabicLetter last = eff.last;
  if (!isAyahEnd && nextFirst != null) {
    bool hasTanween = false;
    for (final ArabicLetter l in eff) {
      if (l.tanween != 0) {
        hasTanween = true;
      }
    }
    final bool finalNoonSakin = last.base == ArabicChars.noon &&
        !last.hasHaraka &&
        !last.shadda &&
        !last.superAlef;
    final bool finalMeemSakin = last.base == ArabicChars.meem &&
        !last.hasHaraka &&
        !last.shadda &&
        !last.superAlef;

    if (hasTanween || finalNoonSakin) {
      if (nextFirst.shadda && ArabicChars.ghunnaIdghamLetters.contains(nextFirst.base)) {
        add(TajweedRule.ghunna);
      } else if (!nextFirst.shadda && ArabicChars.ikhfaLetters.contains(nextFirst.base)) {
        add(TajweedRule.ikhfa);
      }
    }
    if (finalMeemSakin && nextFirst.base == ArabicChars.baa && !nextFirst.shadda) {
      add(TajweedRule.ikhfa);
    }
  }

  // ---- qalqala --------------------------------------------------------------
  for (final ArabicLetter l in eff) {
    if (l.sukun && ArabicChars.qalqalaLetters.contains(l.base)) {
      add(TajweedRule.qalqala);
    }
  }
  if (isAyahEnd) {
    final bool tanweenCarrierAlef = last.base == ArabicChars.alef &&
        eff.length > 1 &&
        eff[eff.length - 2].tanween != 0;
    if (!tanweenCarrierAlef && ArabicChars.qalqalaLetters.contains(last.base)) {
      add(TajweedRule.qalqala);
    }
  }

  // ---- tafkhim --------------------------------------------------------------
  for (final ArabicLetter l in eff) {
    if (ArabicChars.heavyLetters.contains(l.base)) {
      add(TajweedRule.tafkhim);
      break;
    }
  }

  return rules;
}

bool _isMaddLetter(ArabicLetter l, ArabicLetter? prev) {
  if (l.superAlef || l.smallWaw || l.smallYeh) {
    return true;
  }
  if (prev == null) {
    return false;
  }
  if (l.shadda || l.hasHaraka) {
    return false;
  }
  final int b = l.base;
  if (b == ArabicChars.alef) {
    return prev.vowel == ArabicChars.fatha && prev.tanween == 0;
  }
  if (b == ArabicChars.waw) {
    return prev.vowel == ArabicChars.damma;
  }
  if (b == ArabicChars.yeh) {
    return prev.vowel == ArabicChars.kasra;
  }
  if (b == ArabicChars.alefMaksura) {
    return l.maddah;
  }
  return false;
}
