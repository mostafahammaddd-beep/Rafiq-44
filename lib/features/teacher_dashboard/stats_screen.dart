import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_providers.dart';
import '../../core/database/models.dart';
import '../../core/tajweed/arabic_text.dart';
import '../../core/tajweed/tajweed_rule.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StatsSnapshot> stats = ref.watch(statsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات والتقارير')),
      body: stats.when(
        data: (StatsSnapshot s) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(statsProvider);
              await ref.read(statsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _SummaryRow(stats: s),
                const SizedBox(height: 16),
                _TopMistakesCard(stats: s),
                const SizedBox(height: 16),
                if (s.recentMistakes.isNotEmpty) ...<Widget>[
                  _RecentMistakesCard(stats: s),
                  const SizedBox(height: 16),
                ],
                const _DisclaimerCard(),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('تعذّر تحميل الإحصائيات: $error')),
      ),
    );
  }
}

String _percent(double? value) {
  if (value == null) {
    return '—';
  }
  return '${toArabicDigits((value * 100).round())}٪';
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.stats});

  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _StatTile(
                icon: Icons.verified_rounded,
                label: 'الآيات المتقنة',
                value:
                    '${toArabicDigits(stats.masteredAyahs)} / ${toArabicDigits(stats.totalAyahs)}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.record_voice_over_rounded,
                label: 'دقة التجويد العامة',
                value: _percent(stats.tajweedAccuracy),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatTile(
                icon: Icons.spellcheck_rounded,
                label: 'دقة نطق الكلمات',
                value: _percent(stats.wordAccuracy),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.repeat_rounded,
                label: 'مرات التسميع',
                value: toArabicDigits(stats.attempts),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: scheme.onPrimaryContainer),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopMistakesCard extends StatelessWidget {
  const _TopMistakesCard({required this.stats});

  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'أكثر الأخطاء تكراراً',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (stats.topMistakes.isEmpty)
              Text(
                'لا توجد أخطاء مسجّلة بعد. ابدأ التلاوة وستظهر هنا ملاحظاتك مع نصائح للتحسين.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              for (final MistakeSummary item in stats.topMistakes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              ruleDisplayName(item.ruleType),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text('${toArabicDigits(item.count)} مرة'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ruleTip(item.ruleType),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RecentMistakesCard extends StatelessWidget {
  const _RecentMistakesCard({required this.stats});

  final StatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'آخر الملاحظات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final MistakeRecord record in stats.recentMistakes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(record.wordText, style: const TextStyle(fontSize: 20)),
                subtitle: Text(
                  '${ruleDisplayName(record.ruleType)} • سورة رقم ${toArabicDigits(record.surahId)} آية ${toArabicDigits(record.ayahNumber)} • ${_formatDate(record.createdAt)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'إخلاء المسؤولية الشرعي والوقفي',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'رَفِيق وقف لله تعالى، مجاني بالكامل، بلا إعلانات ولا تتبّع، وتبقى تسجيلاتك على جهازك ولا تُرفع إلى أي مكان.\n'
              'التطبيق وسيلة مساعدة على الحفظ والمراجعة، ولا يغني عن التلقّي والمشافهة من معلّم متقن. '
              'والتصحيح الآلي اجتهاد تقني قد يُخطئ، وعند التعارض يُرجع إلى قول المعلّم المتقن.',
              style: TextStyle(height: 1.8, color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
