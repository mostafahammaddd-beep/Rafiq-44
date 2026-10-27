import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_engine/recitation_evaluator.dart';
import '../../core/database/database_providers.dart';
import '../../core/database/models.dart';
import '../../core/tajweed/arabic_text.dart';
import '../../core/tajweed/tajweed_rule.dart';
import '../memorize_engine/recitation_screen.dart';

class SurahScreen extends ConsumerWidget {
  const SurahScreen({super.key, required this.surah});

  final Surah surah;

  Future<void> _openSession(
    BuildContext context,
    WidgetRef ref,
    List<Ayah> ayahs,
    EvaluationMode mode,
    int startIndex,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RecitationScreen(
          surah: surah,
          ayahs: ayahs,
          mode: mode,
          startAyahIndex: startIndex,
        ),
      ),
    );
    ref.invalidate(surahMasteryProvider(surah.id));
    ref.invalidate(surahOverviewsProvider);
    ref.invalidate(statsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Ayah>> ayahsAsync = ref.watch(surahAyahsProvider(surah.id));
    final Map<int, int> mastery =
        ref.watch(surahMasteryProvider(surah.id)).value ?? const <int, int>{};

    return Scaffold(
      appBar: AppBar(title: Text('سورة ${surah.nameAr}')),
      body: ayahsAsync.when(
        data: (List<Ayah> ayahs) {
          return Column(
            children: <Widget>[
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: ayahs.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final Ayah ayah = ayahs[index];
                    return _AyahTile(
                      ayah: ayah,
                      mastery: mastery[ayah.id],
                      onTap: () => _showAyahSheet(context, ref, ayahs, index),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _openSession(
                            context,
                            ref,
                            ayahs,
                            EvaluationMode.recite,
                            0,
                          ),
                          icon: const Icon(Icons.graphic_eq_rounded),
                          label: const Text('تلاوة وتصحيح'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _openSession(
                            context,
                            ref,
                            ayahs,
                            EvaluationMode.memorize,
                            0,
                          ),
                          icon: const Icon(Icons.visibility_off_rounded),
                          label: const Text('لنحفظ معاً'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('تعذّر تحميل الآيات: $error')),
      ),
    );
  }

  void _showAyahSheet(
    BuildContext context,
    WidgetRef ref,
    List<Ayah> ayahs,
    int index,
  ) {
    final Ayah ayah = ayahs[index];
    final Set<TajweedRule> rules = <TajweedRule>{};
    for (final AyahWord word in ayah.words) {
      rules.addAll(word.rules);
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'الآية ${toArabicDigits(ayah.number)}: أحكام التجويد فيها',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final TajweedRule rule in rules)
                      Chip(label: Text(rule.arabicName)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _openSession(context, ref, ayahs, EvaluationMode.recite, index);
                        },
                        child: const Text('تلاوة من هنا'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _openSession(context, ref, ayahs, EvaluationMode.memorize, index);
                        },
                        child: const Text('حفظ من هنا'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AyahTile extends StatelessWidget {
  const _AyahTile({
    required this.ayah,
    required this.mastery,
    required this.onTap,
  });

  final Ayah ayah;
  final int? mastery;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int? m = mastery;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary,
                    child: Text(
                      toArabicDigits(ayah.number),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  if (m != null)
                    Text(
                      'الإتقان ${toArabicDigits(m)}٪',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ayah.text,
                style: const TextStyle(fontSize: 26, height: 2.0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
