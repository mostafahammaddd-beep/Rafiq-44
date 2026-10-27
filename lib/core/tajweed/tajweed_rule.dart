/// Code used in the database for mistakes that are not a tajweed rule
/// (a wrong word or wrong vowel).
const String kPronunciationCode = 'pronunciation';

enum TajweedRule {
  maddTabii(
    code: 'madd_tabii',
    arabicName: 'المد الطبيعي',
    hint: 'انتبه لزمن المد (حركتان)',
    tip: 'مُدّ الحرف مقدار حركتين فقط، دون زيادة أو نقص، وعُدّ في نفسك "واحد، اثنان".',
  ),
  maddMuttasil(
    code: 'madd_muttasil',
    arabicName: 'المد الواجب المتصل',
    hint: 'انتبه لزمن المد: أطِل المد (4 إلى 5 حركات)',
    tip: 'أطِل المد من 4 إلى 5 حركات لأن بعد حرف المد همزة في الكلمة نفسها.',
  ),
  maddMunfasil(
    code: 'madd_munfasil',
    arabicName: 'المد الجائز المنفصل',
    hint: 'انتبه لزمن المد عند الهمزة في أول الكلمة التالية',
    tip: 'مُدّ حرف المد حين تأتي الهمزة في أول الكلمة التالية، والتزم مقداراً واحداً في القراءة كلها.',
  ),
  maddLazim(
    code: 'madd_lazim',
    arabicName: 'المد اللازم',
    hint: 'انتبه لزمن المد: أطِل المد (6 حركات)',
    tip: 'أطِل المد 6 حركات لأن بعد حرف المد حرفاً مشدداً أو ساكناً أصلياً.',
  ),
  maddArid(
    code: 'madd_arid',
    arabicName: 'المد العارض للسكون',
    hint: 'انتبه لزمن المد عند الوقف',
    tip: 'عند الوقف يجوز مد حرف المد 2 أو 4 أو 6 حركات، فالتزم مقداراً واحداً.',
  ),
  ghunna(
    code: 'ghunna',
    arabicName: 'الغنة',
    hint: 'أظهر الغنة',
    tip: 'أظهر الغنة مقدار حركتين في النون والميم المشددتين، واجعل الصوت يخرج من الخيشوم.',
  ),
  ikhfa(
    code: 'ikhfa',
    arabicName: 'الإخفاء',
    hint: 'أخفِ النون مع الغنة',
    tip: 'أخفِ النون الساكنة والتنوين مع غنة عند حروف الإخفاء، دون إظهار النون ولا إدغامها.',
  ),
  qalqala(
    code: 'qalqala',
    arabicName: 'القلقلة',
    hint: 'بيّن القلقلة',
    tip: 'بيّن اهتزاز صوت الحرف الساكن من حروف (قطب جد) دون أن تتبعه حركة.',
  ),
  tafkhim(
    code: 'tafkhim',
    arabicName: 'التفخيم',
    hint: 'فخّم الحرف',
    tip: 'فخّم حروف الاستعلاء (خ ص ض غ ط ق ظ) بتغليظ الصوت، ولا ترقّقها.',
  );

  const TajweedRule({
    required this.code,
    required this.arabicName,
    required this.hint,
    required this.tip,
  });

  final String code;
  final String arabicName;
  final String hint;
  final String tip;

  bool get isMadd =>
      this == maddTabii ||
      this == maddMuttasil ||
      this == maddMunfasil ||
      this == maddLazim ||
      this == maddArid;

  static TajweedRule? fromCode(String code) {
    for (final TajweedRule rule in TajweedRule.values) {
      if (rule.code == code) {
        return rule;
      }
    }
    return null;
  }
}

/// Parses the comma separated rule codes stored in the `words.rules` column.
List<TajweedRule> parseRuleCodes(String csv) {
  if (csv.trim().isEmpty) {
    return const <TajweedRule>[];
  }
  final List<TajweedRule> rules = <TajweedRule>[];
  for (final String code in csv.split(',')) {
    final TajweedRule? rule = TajweedRule.fromCode(code.trim());
    if (rule != null) {
      rules.add(rule);
    }
  }
  return rules;
}

String ruleDisplayName(String code) {
  if (code == kPronunciationCode) {
    return 'نطق الكلمة أو التشكيل';
  }
  return TajweedRule.fromCode(code)?.arabicName ?? code;
}

String ruleTip(String code) {
  if (code == kPronunciationCode) {
    return 'أعد قراءة الكلمة ببطء مع ضبط الحركات (الفتح والضم والكسر) وأحرف الكلمة.';
  }
  return TajweedRule.fromCode(code)?.tip ?? '';
}
