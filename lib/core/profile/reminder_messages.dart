import 'user_profile.dart';

class ReminderMessage {
  const ReminderMessage({required this.title, required this.body});

  final String title;
  final String body;
}

/// Rotating motivational content for the daily reminder: an ayah, a hadith,
/// a piece of wisdom, or a personal nudge built from the user's goals.
///
/// IMPORTANT: ayat and ahadith here must be audited by a qualified reviewer.
class ReminderMessages {
  ReminderMessages._();

  static const List<String> _ayat = <String>[
    '﴿وَلَقَدْ يَسَّرْنَا ٱلْقُرْءَانَ لِلذِّكْرِ فَهَلْ مِن مُّدَّكِرٍ﴾\n— سورة القمر',
    '﴿وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا﴾\n— سورة المزمل',
    '﴿أَلَا بِذِكْرِ ٱللَّهِ تَطْمَئِنُّ ٱلْقُلُوبُ﴾\n— سورة الرعد',
    '﴿فَٱذْكُرُونِىٓ أَذْكُرْكُمْ﴾\n— سورة البقرة',
    '﴿إِنَّ هَٰذَا ٱلْقُرْءَانَ يَهْدِى لِلَّتِى هِىَ أَقْوَمُ﴾\n— سورة الإسراء',
    '﴿فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا﴾\n— سورة الشرح',
    '﴿وَٱصْبِرْ فَإِنَّ ٱللَّهَ لَا يُضِيعُ أَجْرَ ٱلْمُحْسِنِينَ﴾\n— سورة هود',
    '﴿وَمَن يَتَّقِ ٱللَّهَ يَجْعَل لَّهُۥ مَخْرَجًا﴾\n— سورة الطلاق',
    '﴿وَنُنَزِّلُ مِنَ ٱلْقُرْءَانِ مَا هُوَ شِفَآءٌ وَرَحْمَةٌ لِّلْمُؤْمِنِينَ﴾\n— سورة الإسراء',
    '﴿ٱدْعُونِىٓ أَسْتَجِبْ لَكُمْ﴾\n— سورة غافر',
  ];

  static const List<String> _ahadith = <String>[
    '«خَيْرُكُمْ مَنْ تَعَلَّمَ الْقُرْآنَ وَعَلَّمَهُ»\n— رواه البخاري',
    '«اقْرَءُوا الْقُرْآنَ فَإِنَّهُ يَأْتِي يَوْمَ الْقِيَامَةِ شَفِيعًا لِأَصْحَابِهِ»\n— رواه مسلم',
    '«مَنْ قَرَأَ حَرْفًا مِنْ كِتَابِ اللَّهِ فَلَهُ بِهِ حَسَنَةٌ، وَالْحَسَنَةُ بِعَشْرِ أَمْثَالِهَا»\n— رواه الترمذي',
    '«أَحَبُّ الْأَعْمَالِ إِلَى اللَّهِ أَدْوَمُهَا وَإِنْ قَلَّ»\n— متفق عليه',
    '«تَعَاهَدُوا الْقُرْآنَ، فَوَالَّذِي نَفْسِي بِيَدِهِ لَهُوَ أَشَدُّ تَفَلُّتًا مِنَ الْإِبِلِ فِي عُقُلِهَا»\n— متفق عليه',
    '«الْمَاهِرُ بِالْقُرْآنِ مَعَ السَّفَرَةِ الْكِرَامِ الْبَرَرَةِ»\n— متفق عليه',
    '«يُقَالُ لِصَاحِبِ الْقُرْآنِ: اقْرَأْ وَارْتَقِ وَرَتِّلْ كَمَا كُنْتَ تُرَتِّلُ فِي الدُّنْيَا، فَإِنَّ مَنْزِلَتَكَ عِنْدَ آخِرِ آيَةٍ تَقْرَؤُهَا»\n— رواه أبو داود والترمذي',
    '«إِنَّ اللَّهَ يَرْفَعُ بِهَذَا الْكِتَابِ أَقْوَامًا وَيَضَعُ بِهِ آخَرِينَ»\n— رواه مسلم',
  ];

  static const List<String> _wisdoms = <String>[
    'القليل الدائم خيرٌ من الكثير المنقطع.',
    'من جدّ وجد، ومن زرع حصد.',
    'الحفظ يقوى بالتكرار، والتكرار يحتاج صبراً.',
    'رحلة الألف ميل تبدأ بخطوة.',
    'خطوة صغيرة كل يوم أبقى من حماسة تنطفئ بعد أسبوع.',
    'الاستمرار أصعب من البداية، وأجمل منها.',
    'ما كان لله دام واتصل.',
    'اجعل لقلبك وردًا من القرآن، فهو غذاؤه الذي لا يستغني عنه.',
  ];

  static const List<String> _ayahTitles = <String>[
    'آية لك من رَفِيق',
    'من نور القرآن',
    'آية تنتظرك',
  ];

  static const List<String> _hadithTitles = <String>[
    'حديث شريف',
    'من هدي النبي ﷺ',
  ];

  static const List<String> _wisdomTitles = <String>[
    'حكمة اليوم',
    'رَفِيق يهمس لك',
  ];

  /// [dayNumber] is any non-negative number that changes every day; the same
  /// number always gives the same message, consecutive numbers give different ones.
  static ReminderMessage pick({
    required int dayNumber,
    required UserProfile profile,
  }) {
    final int category = dayNumber % 4;
    final int round = dayNumber ~/ 4;

    if (category == 0) {
      return ReminderMessage(
        title: _ayahTitles[round % _ayahTitles.length],
        body: _ayat[round % _ayat.length],
      );
    }
    if (category == 1) {
      return ReminderMessage(
        title: _hadithTitles[round % _hadithTitles.length],
        body: _ahadith[round % _ahadith.length],
      );
    }
    if (category == 2) {
      return ReminderMessage(
        title: _wisdomTitles[round % _wisdomTitles.length],
        body: _wisdoms[round % _wisdoms.length],
      );
    }
    return _personal(round, profile);
  }

  static ReminderMessage _personal(int round, UserProfile profile) {
    final GoalType goal = profile.goals[round % profile.goals.length];
    final int minutes = profile.dailyMinutes;
    final List<String> bodies = <String>[
      'يا ${profile.name}، حان وقت ${goal.phrase}. $minutes دقيقة فقط تكفي اليوم.',
      'أنا بانتظارك يا ${profile.name}. لنبدأ ${goal.phrase} معاً بإذن الله.',
      '${profile.name}، قليلٌ دائم خير من كثير منقطع. ${goal.phrase} ينتظرك الآن.',
    ];
    return ReminderMessage(
      title: round.isEven ? 'حان وقت ${goal.phrase}' : 'رَفِيق ينتظرك',
      body: bodies[round % bodies.length],
    );
  }
}
