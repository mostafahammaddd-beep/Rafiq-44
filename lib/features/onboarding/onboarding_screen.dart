import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile/profile_repository.dart';
import '../../core/profile/reminder_service.dart';
import '../../core/profile/user_profile.dart';
import '../../core/tajweed/arabic_text.dart';
import 'profile_widgets.dart';

/// First-run flow: animated introduction from Rafiq, then name, age, goals,
/// daily minutes and reminders.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _lastStep = 5;

  final TextEditingController _nameController = TextEditingController();
  int _step = 0;
  bool _goingForward = true;
  bool _saving = false;

  int _age = 18;
  List<GoalType> _goals = <GoalType>[];
  int _minutes = 15;
  bool _remind = true;
  TimeOfDay _time = const TimeOfDay(hour: 21, minute: 0);

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canContinue {
    if (_step == 1) {
      return _nameController.text.trim().isNotEmpty;
    }
    if (_step == 3) {
      return _goals.isNotEmpty;
    }
    return true;
  }

  void _next() {
    if (_step >= _lastStep) {
      _finish();
      return;
    }
    setState(() {
      _goingForward = true;
      _step++;
    });
  }

  void _back() {
    if (_step == 0) {
      return;
    }
    setState(() {
      _goingForward = false;
      _step--;
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() {
        _time = picked;
      });
    }
  }

  Future<void> _finish() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
    });

    bool remind = _remind;
    if (remind) {
      final bool granted = await ReminderService.requestPermission();
      if (!granted) {
        remind = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'لم يُسمح بالإشعارات، يمكنك تفعيل التذكير لاحقاً من تبويب حسابي.',
              ),
            ),
          );
        }
      }
    }

    final UserProfile profile = UserProfile(
      name: _nameController.text.trim(),
      age: _age,
      goals: _goals,
      dailyMinutes: _minutes,
      remindersEnabled: remind,
      reminderHour: _time.hour,
      reminderMinute: _time.minute,
    );
    await ref.read(profileRepositoryProvider).save(profile);
    await ReminderService.scheduleDaily(profile);
    if (!mounted) {
      return;
    }
    ref.invalidate(profileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isIntro = _step == 0;
    final bool isLast = _step == _lastStep;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_step + 1) / (_lastStep + 1),
                  minHeight: 6,
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final Offset begin =
                      Offset(_goingForward ? -0.15 : 0.15, 0);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: begin, end: Offset.zero)
                          .animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_step),
                  child: _buildStep(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: <Widget>[
                  if (!isIntro)
                    TextButton(
                      onPressed: _saving ? null : _back,
                      child: const Text('السابق'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: (_canContinue && !_saving) ? _next : null,
                    child: _saving
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: scheme.onPrimary,
                            ),
                          )
                        : Text(
                            isIntro
                                ? 'هيا نبدأ'
                                : (isLast ? 'ابدأ رحلتي' : 'التالي'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case 0:
        return const _IntroStep();
      case 1:
        return _StepScaffold(
          title: 'ما اسمك؟',
          subtitle: 'أحب أن أناديك باسمك',
          child: TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 22),
            decoration: const InputDecoration(hintText: 'اكتب اسمك هنا'),
          ),
        );
      case 2:
        return _StepScaffold(
          title: 'كم عمرك؟',
          subtitle: 'لأختار لك أسلوباً مناسباً',
          child: _AgeStep(
            age: _age,
            onChanged: (int value) {
              setState(() {
                _age = value;
              });
            },
          ),
        );
      case 3:
        return _StepScaffold(
          title: 'ما هدفك؟',
          subtitle: 'اختر ما يناسبك، ويمكنك اختيار أكثر من هدف',
          scrollable: true,
          child: GoalPicker(
            selected: _goals,
            onChanged: (List<GoalType> value) {
              setState(() {
                _goals = value;
              });
            },
          ),
        );
      case 4:
        return _StepScaffold(
          title: 'كم دقيقة يومياً للقرآن؟',
          subtitle: 'اختر وقتاً تستطيع الاستمرار عليه',
          child: MinutesPicker(
            value: _minutes,
            onChanged: (int value) {
              setState(() {
                _minutes = value;
              });
            },
          ),
        );
      default:
        return _StepScaffold(
          title: 'أذكّرك في وقتك؟',
          subtitle:
              'أرسل لك إشعاراً في هذا الوقت برسالة مختلفة كل مرة: آية، أو حديث، أو حكمة…',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                value: _remind,
                onChanged: (bool value) {
                  setState(() {
                    _remind = value;
                  });
                },
                title: const Text('نعم، ذكّرني يومياً'),
              ),
              const SizedBox(height: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _remind ? 1 : 0.4,
                child: OutlinedButton.icon(
                  onPressed: _remind ? _pickTime : null,
                  icon: const Icon(Icons.alarm_rounded),
                  label: Text(
                    formatReminderTime(_time.hour, _time.minute),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.scrollable = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 24),
        Text(
          title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(fontSize: 15, height: 1.6, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        child,
      ],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: content,
    );
  }
}

class _AgeStep extends StatelessWidget {
  const _AgeStep({required this.age, required this.onChanged});

  final int age;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton.filledTonal(
              onPressed: age < 90 ? () => onChanged(age + 1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 24),
            Text(
              toArabicDigits(age),
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 24),
            IconButton.filledTonal(
              onPressed: age > 4 ? () => onChanged(age - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
          ],
        ),
        Slider(
          min: 4,
          max: 90,
          divisions: 86,
          value: age.toDouble(),
          label: toArabicDigits(age),
          onChanged: (double value) => onChanged(value.round()),
        ),
        Text(
          'سنة',
          style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Animated introduction: the logo appears, then Rafiq's message line by line.
class _IntroStep extends StatefulWidget {
  const _IntroStep();

  @override
  State<_IntroStep> createState() => _IntroStepState();
}

class _IntroStepState extends State<_IntroStep>
    with SingleTickerProviderStateMixin {
  static const List<String> _lines = <String>[
    'السلام عليكم ورحمة الله وبركاته',
    'أنا رَفِيق، رفيقك في رحلة حفظ كتاب الله',
    'أسمع تلاوتك وأصحّح لك الحفظ والتجويد لحظة بلحظة، دون إنترنت ودون مقابل، وقفاً لله تعالى',
    'لنتعرّف عليك أولاً ونرتّب رحلتنا معاً',
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7000),
  );

  late final Animation<double> _logo = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.2, curve: Curves.easeOutBack),
  );

  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.15, curve: Curves.easeOut),
  );

  late final List<Animation<double>> _lineAnimations = <Animation<double>>[
    for (int i = 0; i < _lines.length; i++)
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          0.2 + i * 0.2,
          0.2 + i * 0.2 + 0.18,
          curve: Curves.easeOut,
        ),
      ),
  ];

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ScaleTransition(
              scale: _logo,
              child: FadeTransition(
                opacity: _logoFade,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x55DCB054),
                        blurRadius: 40,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 170,
                      height: 170,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            for (int i = 0; i < _lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: FadeTransition(
                  opacity: _lineAnimations[i],
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(_lineAnimations[i]),
                    child: Text(
                      _lines[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: i == 1 ? 24 : (i == 0 ? 20 : 17),
                        fontWeight: i == 1 ? FontWeight.w800 : FontWeight.w500,
                        height: 1.7,
                        color: i == 1 ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
