import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_providers.dart';
import '../../core/database/models.dart';
import '../../core/profile/profile_repository.dart';
import '../../core/profile/user_profile.dart';
import '../../core/tajweed/arabic_text.dart';
import '../../core/theme/theme_mode_provider.dart';
import 'surah_screen.dart';

class SurahIndexScreen extends ConsumerWidget {
  const SurahIndexScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final AsyncValue<List<SurahOverview>> overviews =
        ref.watch(surahOverviewsProvider);
    final UserProfile? profile = ref.watch(profileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصحف'),
        actions: <Widget>[
          IconButton(
            tooltip: isDark ? 'الوضع النهاري' : 'الوضع الليلي',
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggle(theme.brightness);
            },
          ),
        ],
      ),
      body: overviews.when(
        data: (List<SurahOverview> items) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(surahOverviewsProvider);
              await ref.read(surahOverviewsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + 1,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return _GreetingCard(profile: profile);
                }
                return _SurahCard(overview: items[index - 1]);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('تعذّر تحميل السور: $error')),
      ),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final UserProfile? p = profile;
    if (p == null) {
      return const SizedBox.shrink();
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String goals = p.goals.map((GoalType g) => g.label).join(' • ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'السلام عليكم يا ${p.name}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'هدفك: $goals',
            style: TextStyle(color: scheme.onSurface, height: 1.6),
          ),
          Text(
            'وقتك اليوم: ${toArabicDigits(p.dailyMinutes)} دقيقة مع كتاب الله',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SurahCard extends ConsumerWidget {
  const _SurahCard({required this.overview});

  final SurahOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Surah surah = overview.surah;
    final double? tajweed = overview.tajweedAccuracy;
    final int memorizedPercent = (overview.memorizationFraction * 100).round();

    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => SurahScreen(surah: surah),
            ),
          );
          ref.invalidate(surahOverviewsProvider);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary,
                    child: Text(toArabicDigits(surah.id)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'سورة ${surah.nameAr}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          '${toArabicDigits(surah.ayahCount)} آيات • ${surah.revelation}',
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left_rounded, color: scheme.onPrimaryContainer),
                ],
              ),
              const SizedBox(height: 12),
              _ProgressLine(
                label: 'الحفظ',
                value: overview.memorizationFraction,
                trailing: '${toArabicDigits(memorizedPercent)}٪',
              ),
              const SizedBox(height: 8),
              _ProgressLine(
                label: 'إتقان التجويد',
                value: tajweed ?? 0,
                trailing:
                    tajweed == null ? '—' : '${toArabicDigits((tajweed * 100).round())}٪',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.trailing,
  });

  final String label;
  final double value;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            trailing,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer),
          ),
        ),
      ],
    );
  }
}
