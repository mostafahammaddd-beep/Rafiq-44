import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile/profile_repository.dart';
import '../../core/profile/reminder_service.dart';
import '../../core/profile/user_profile.dart';
import '../../core/tajweed/arabic_text.dart';
import '../onboarding/profile_widgets.dart';

/// "حسابي": goals, daily minutes and reminders can be changed at any time.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _save(WidgetRef ref, UserProfile profile) async {
    await ref.read(profileRepositoryProvider).save(profile);
    await ReminderService.scheduleDaily(profile);
    ref.invalidate(profileProvider);
  }

  Future<void> _toggleReminders(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    bool enabled,
  ) async {
    if (enabled) {
      final bool granted = await ReminderService.requestPermission();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فعّل إذن الإشعارات لرَفِيق من إعدادات الجهاز أولاً.'),
            ),
          );
        }
        return;
      }
    }
    await _save(ref, profile.copyWith(remindersEnabled: enabled));
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: profile.reminderHour,
        minute: profile.reminderMinute,
      ),
    );
    if (picked == null) {
      return;
    }
    await _save(
      ref,
      profile.copyWith(reminderHour: picked.hour, reminderMinute: picked.minute),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserProfile? profile = ref.watch(profileProvider).value;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  elevation: 0,
                  color: scheme.primaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      child: const Icon(Icons.person_rounded),
                    ),
                    title: Text(
                      profile.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    subtitle: Text(
                      '${toArabicDigits(profile.age)} سنة',
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionTitle('أهدافي'),
                GoalPicker(
                  selected: profile.goals,
                  onChanged: (List<GoalType> goals) {
                    if (goals.isEmpty) {
                      return;
                    }
                    _save(ref, profile.copyWith(goals: goals));
                  },
                ),
                const SizedBox(height: 12),
                const _SectionTitle('وقتي اليومي مع القرآن'),
                MinutesPicker(
                  value: profile.dailyMinutes,
                  onChanged: (int minutes) {
                    _save(ref, profile.copyWith(dailyMinutes: minutes));
                  },
                ),
                const SizedBox(height: 24),
                const _SectionTitle('تذكير رَفِيق'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: profile.remindersEnabled,
                  onChanged: (bool value) =>
                      _toggleReminders(context, ref, profile, value),
                  title: const Text('ذكّرني يومياً برسالة مختلفة'),
                  subtitle: const Text('آية، أو حديث، أو حكمة، أو رسالة تحفيزية'),
                ),
                if (profile.remindersEnabled) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickTime(context, ref, profile),
                          icon: const Icon(Icons.alarm_rounded),
                          label: Text(
                            formatReminderTime(
                              profile.reminderHour,
                              profile.reminderMinute,
                            ),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton.icon(
                        onPressed: () => ReminderService.showNow(profile),
                        icon: const Icon(Icons.notifications_active_rounded),
                        label: const Text('جرّب الآن'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
