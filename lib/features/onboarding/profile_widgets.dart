import 'package:flutter/material.dart';

import '../../core/profile/user_profile.dart';
import '../../core/tajweed/arabic_text.dart';

/// Multi-select list of goals (any combination can be chosen).
class GoalPicker extends StatelessWidget {
  const GoalPicker({super.key, required this.selected, required this.onChanged});

  final List<GoalType> selected;
  final ValueChanged<List<GoalType>> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        for (final GoalType goal in GoalType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _GoalTile(
              goal: goal,
              isSelected: selected.contains(goal),
              scheme: scheme,
              onTap: () {
                final List<GoalType> next = List<GoalType>.of(selected);
                if (next.contains(goal)) {
                  next.remove(goal);
                } else {
                  next.add(goal);
                }
                onChanged(next);
              },
            ),
          ),
      ],
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    required this.isSelected,
    required this.scheme,
    required this.onTap,
  });

  final GoalType goal;
  final bool isSelected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? scheme.primaryContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? scheme.primary : scheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(
                goal.icon,
                size: 30,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      goal.label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      goal.subtitle,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Daily time with the Quran, chosen from fixed options.
class MinutesPicker extends StatelessWidget {
  const MinutesPicker({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (final int minutes in kMinuteChoices)
          ChoiceChip(
            label: Text(
              '${toArabicDigits(minutes)} دقيقة',
              style: const TextStyle(fontSize: 16),
            ),
            selected: value == minutes,
            onSelected: (bool _) => onChanged(minutes),
          ),
      ],
    );
  }
}
