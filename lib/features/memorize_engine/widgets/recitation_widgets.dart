import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/tajweed/arabic_text.dart';
import '../recitation_session_controller.dart';

/// Shakes its child whenever [shakeToken] changes.
class ShakeWidget extends StatefulWidget {
  const ShakeWidget({super.key, required this.shakeToken, required this.child});

  final int shakeToken;
  final Widget child;

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void didUpdateWidget(ShakeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shakeToken != widget.shakeToken) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        final double dx = math.sin(t * math.pi * 8) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// One word of the ayah, colored by its recitation status.
class WordChip extends StatelessWidget {
  const WordChip({
    super.key,
    required this.text,
    required this.status,
    required this.isCurrent,
    required this.hidden,
    required this.showFirstLetter,
    required this.shakeToken,
  });

  final String text;
  final WordStatus status;
  final bool isCurrent;
  final bool hidden;
  final bool showFirstLetter;
  final int shakeToken;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    Color background = Colors.transparent;
    Color border = scheme.outlineVariant;
    if (status == WordStatus.correct) {
      background = AppColors.correctSoft;
      border = AppColors.correct;
    } else if (status == WordStatus.warning || status == WordStatus.uncertain) {
      background = AppColors.warningSoft;
      border = AppColors.warning;
    } else if (status == WordStatus.incorrect) {
      background = AppColors.errorSoft;
      border = AppColors.error;
    } else if (isCurrent) {
      border = scheme.primary;
    }

    String display = text;
    if (hidden) {
      display = showFirstLetter
          ? '${firstLetterWithMarks(text)} …'
          : maskWord(text);
    }

    return ShakeWidget(
      shakeToken: shakeToken,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: isCurrent ? 2.5 : 1.2),
        ),
        child: Text(
          display,
          style: TextStyle(
            fontSize: hidden ? 24 : 30,
            height: 1.9,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Live bar waveform driven by the microphone RMS level.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({super.key, required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformPainter(levels: levels, color: color),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    final int n = levels.length;
    if (n == 0) {
      return;
    }
    final double gap = size.width / n;
    final double mid = size.height / 2;
    for (int i = 0; i < n; i++) {
      final double h = math.max(4.0, levels[i] * size.height).toDouble();
      final double x = gap * i + gap / 2;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}
