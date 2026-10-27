/// Uthmani text of the ten short surahs bundled in this stage.
///
/// IMPORTANT: this text must be audited against the printed Madinah Mushaf
/// (King Fahd Complex) by a qualified reviewer before any public release.
class SurahSeed {
  const SurahSeed({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.revelation,
    required this.ayahs,
  });

  final int id;
  final String nameAr;
  final String nameEn;
  final String revelation;
  final List<String> ayahs;
}

const List<SurahSeed> kSurahSeeds = <SurahSeed>[
  SurahSeed(
    id: 1,
    nameAr: 'الفاتحة',
    nameEn: 'Al-Fatihah',
    revelation: 'مكية',
    ayahs: <String>[
      'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
      'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      'مَٰلِكِ يَوْمِ ٱلدِّينِ',
      'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
      'ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ',
      'صِرَٰطَ ٱلَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَلَا ٱلضَّآلِّينَ',
    ],
  ),
  SurahSeed(
    id: 103,
    nameAr: 'العصر',
    nameEn: 'Al-Asr',
    revelation: 'مكية',
    ayahs: <String>[
      'وَٱلْعَصْرِ',
      'إِنَّ ٱلْإِنسَٰنَ لَفِى خُسْرٍ',
      'إِلَّا ٱلَّذِينَ ءَامَنُوا۟ وَعَمِلُوا۟ ٱلصَّٰلِحَٰتِ وَتَوَاصَوْا۟ بِٱلْحَقِّ وَتَوَاصَوْا۟ بِٱلصَّبْرِ',
    ],
  ),
  SurahSeed(
    id: 105,
    nameAr: 'الفيل',
    nameEn: 'Al-Fil',
    revelation: 'مكية',
    ayahs: <String>[
      'أَلَمْ تَرَ كَيْفَ فَعَلَ رَبُّكَ بِأَصْحَٰبِ ٱلْفِيلِ',
      'أَلَمْ يَجْعَلْ كَيْدَهُمْ فِى تَضْلِيلٍ',
      'وَأَرْسَلَ عَلَيْهِمْ طَيْرًا أَبَابِيلَ',
      'تَرْمِيهِم بِحِجَارَةٍ مِّن سِجِّيلٍ',
      'فَجَعَلَهُمْ كَعَصْفٍ مَّأْكُولٍۭ',
    ],
  ),
  SurahSeed(
    id: 106,
    nameAr: 'قريش',
    nameEn: 'Quraysh',
    revelation: 'مكية',
    ayahs: <String>[
      'لِإِيلَٰفِ قُرَيْشٍ',
      'إِۦلَٰفِهِمْ رِحْلَةَ ٱلشِّتَآءِ وَٱلصَّيْفِ',
      'فَلْيَعْبُدُوا۟ رَبَّ هَٰذَا ٱلْبَيْتِ',
      'ٱلَّذِىٓ أَطْعَمَهُم مِّن جُوعٍ وَءَامَنَهُم مِّنْ خَوْفٍۭ',
    ],
  ),
  SurahSeed(
    id: 108,
    nameAr: 'الكوثر',
    nameEn: 'Al-Kawthar',
    revelation: 'مكية',
    ayahs: <String>[
      'إِنَّآ أَعْطَيْنَٰكَ ٱلْكَوْثَرَ',
      'فَصَلِّ لِرَبِّكَ وَٱنْحَرْ',
      'إِنَّ شَانِئَكَ هُوَ ٱلْأَبْتَرُ',
    ],
  ),
  SurahSeed(
    id: 110,
    nameAr: 'النصر',
    nameEn: 'An-Nasr',
    revelation: 'مدنية',
    ayahs: <String>[
      'إِذَا جَآءَ نَصْرُ ٱللَّهِ وَٱلْفَتْحُ',
      'وَرَأَيْتَ ٱلنَّاسَ يَدْخُلُونَ فِى دِينِ ٱللَّهِ أَفْوَاجًا',
      'فَسَبِّحْ بِحَمْدِ رَبِّكَ وَٱسْتَغْفِرْهُ ۚ إِنَّهُۥ كَانَ تَوَّابًۢا',
    ],
  ),
  SurahSeed(
    id: 111,
    nameAr: 'المسد',
    nameEn: 'Al-Masad',
    revelation: 'مكية',
    ayahs: <String>[
      'تَبَّتْ يَدَآ أَبِى لَهَبٍ وَتَبَّ',
      'مَآ أَغْنَىٰ عَنْهُ مَالُهُۥ وَمَا كَسَبَ',
      'سَيَصْلَىٰ نَارًا ذَاتَ لَهَبٍ',
      'وَٱمْرَأَتُهُۥ حَمَّالَةَ ٱلْحَطَبِ',
      'فِى جِيدِهَا حَبْلٌ مِّن مَّسَدٍۭ',
    ],
  ),
  SurahSeed(
    id: 112,
    nameAr: 'الإخلاص',
    nameEn: 'Al-Ikhlas',
    revelation: 'مكية',
    ayahs: <String>[
      'قُلْ هُوَ ٱللَّهُ أَحَدٌ',
      'ٱللَّهُ ٱلصَّمَدُ',
      'لَمْ يَلِدْ وَلَمْ يُولَدْ',
      'وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ',
    ],
  ),
  SurahSeed(
    id: 113,
    nameAr: 'الفلق',
    nameEn: 'Al-Falaq',
    revelation: 'مكية',
    ayahs: <String>[
      'قُلْ أَعُوذُ بِرَبِّ ٱلْفَلَقِ',
      'مِن شَرِّ مَا خَلَقَ',
      'وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ',
      'وَمِن شَرِّ ٱلنَّفَّٰثَٰتِ فِى ٱلْعُقَدِ',
      'وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ',
    ],
  ),
  SurahSeed(
    id: 114,
    nameAr: 'الناس',
    nameEn: 'An-Nas',
    revelation: 'مكية',
    ayahs: <String>[
      'قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ',
      'مَلِكِ ٱلنَّاسِ',
      'إِلَٰهِ ٱلنَّاسِ',
      'مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ',
      'ٱلَّذِى يُوَسْوِسُ فِى صُدُورِ ٱلنَّاسِ',
      'مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ',
    ],
  ),
];
