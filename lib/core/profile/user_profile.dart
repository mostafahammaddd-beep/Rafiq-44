import 'package:flutter/material.dart';

import '../tajweed/arabic_text.dart';

/// What the user wants to do with Rafiq (several can be chosen).
enum GoalType {
  wird(
    code: 'wird',
    label: 'الورد اليومي',
    subtitle: 'قراءة وردي من القرآن كل يوم',
    icon: Icons.auto_stories_rounded,
    phrase: 'وردك اليومي',
  ),
  memorize(
    code: 'memorize',
    label: 'حفظ جديد',
    subtitle: 'أحفظ آيات جديدة بتأنٍّ وإتقان',
    icon: Icons.psychology_alt_rounded,
    phrase: 'حفظك الجديد',
  ),
  recite(
    code: 'recite',
    label: 'التسميع',
    subtitle: 'أسمّع ما حفظت وأتلقى التصحيح لحظياً',
    icon: Icons.record_voice_over_rounded,
    phrase: 'تسميعك',
  ),
  review(
    code: 'review',
    label: 'مراجعة المحفوظ',
    subtitle: 'أثبّت ما حفظته وأمنع تفلّته',
    icon: Icons.autorenew_rounded,
    phrase: 'مراجعتك',
  ),
  follow(
    code: 'follow',
    label: 'متابعة التقدم',
    subtitle: 'أتابع إتقاني وأكثر أخطائي تكراراً',
    icon: Icons.insights_rounded,
    phrase: 'متابعة تقدمك',
  );

  const GoalType({
    required this.code,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.phrase,
  });

  final String code;
  final String label;
  final String subtitle;
  final IconData icon;
  final String phrase;

  static GoalType? fromCode(String code) {
    for (final GoalType goal in GoalType.values) {
      if (goal.code == code) {
        return goal;
      }
    }
    return null;
  }
}

const List<int> kMinuteChoices = <int>[5, 10, 15, 20, 30, 45, 60];

class UserProfile {
  const UserProfile({
    required this.name,
    required this.age,
    required this.goals,
    required this.dailyMinutes,
    required this.remindersEnabled,
    required this.reminderHour,
    required this.reminderMinute,
  });

  final String name;
  final int age;
  final List<GoalType> goals;
  final int dailyMinutes;
  final bool remindersEnabled;
  final int reminderHour;
  final int reminderMinute;

  UserProfile copyWith({
    String? name,
    int? age,
    List<GoalType>? goals,
    int? dailyMinutes,
    bool? remindersEnabled,
    int? reminderHour,
    int? reminderMinute,
  }) {
    return UserProfile(
      name: name ?? this.name,
      age: age ?? this.age,
      goals: goals ?? this.goals,
      dailyMinutes: dailyMinutes ?? this.dailyMinutes,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'age': age,
      'goals': goals.map((GoalType g) => g.code).toList(),
      'dailyMinutes': dailyMinutes,
      'remindersEnabled': remindersEnabled,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
    };
  }

  static UserProfile? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? name = raw['name'];
    if (name is! String || name.trim().isEmpty) {
      return null;
    }
    final List<GoalType> goals = <GoalType>[];
    final Object? rawGoals = raw['goals'];
    if (rawGoals is List) {
      for (final Object? item in rawGoals) {
        if (item is String) {
          final GoalType? goal = GoalType.fromCode(item);
          if (goal != null && !goals.contains(goal)) {
            goals.add(goal);
          }
        }
      }
    }
    return UserProfile(
      name: name.trim(),
      age: _asInt(raw['age'], 18),
      goals: goals.isEmpty ? <GoalType>[GoalType.wird] : goals,
      dailyMinutes: _asInt(raw['dailyMinutes'], 15),
      remindersEnabled: raw['remindersEnabled'] == true,
      reminderHour: _asInt(raw['reminderHour'], 21),
      reminderMinute: _asInt(raw['reminderMinute'], 0),
    );
  }

  static int _asInt(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }
}

/// e.g. "٩:٣٠ م"
String formatReminderTime(int hour, int minute) {
  final bool pm = hour >= 12;
  int h = hour % 12;
  if (h == 0) {
    h = 12;
  }
  final String minutes = minute.toString().padLeft(2, '0');
  final StringBuffer mm = StringBuffer();
  for (final String ch in minutes.split('')) {
    mm.write(toArabicDigits(int.parse(ch)));
  }
  return '${toArabicDigits(h)}:$mm ${pm ? 'م' : 'ص'}';
}
