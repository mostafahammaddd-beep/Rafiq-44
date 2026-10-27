import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_engine/audio_capture_service.dart';
import '../../core/audio_engine/engine_providers.dart';
import '../../core/audio_engine/recitation_evaluator.dart';
import '../../core/database/database_providers.dart';
import '../../core/database/models.dart';
import '../../core/database/rafiq_database.dart';
import '../../core/tajweed/arabic_text.dart';
import '../../core/theme/app_theme.dart';
import 'recitation_session_controller.dart';
import 'widgets/recitation_widgets.dart';
import 'widgets/recitation_telemetry_overlay.dart';

/// Shared screen for the two modes:
///  - [EvaluationMode.recite]: live recitation and correction;
///  - [EvaluationMode.memorize]: hands-free "لنحفظ معاً" with hidden words.
class RecitationScreen extends ConsumerStatefulWidget {
  const RecitationScreen({
    super.key,
    required this.surah,
    required this.ayahs,
    required this.mode,
    this.startAyahIndex = 0,
  });

  final Surah surah;
  final List<Ayah> ayahs;
  final EvaluationMode mode;
  final int startAyahIndex;

  @override
  ConsumerState<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends ConsumerState<RecitationScreen>
    with WidgetsBindingObserver {
  late final RecitationSessionController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final RafiqDatabase database = ref.read(databaseProvider).value!;
    final PrepState prep = ref.read(modelPrepProvider);
    _controller = RecitationSessionController(
      database: database,
      engine: ref.read(engineProvider),
      capture: AudioCaptureService(),
      lexicon: ref.read(lexiconProvider),
      surah: widget.surah,
      ayahs: widget.ayahs,
      mode: widget.mode,
      engineAvailable: prep.stage == PrepStage.ready,
      startAyahIndex: widget.startAyahIndex,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never keep the microphone and the model running in the background.
    if (state == AppLifecycleState.paused) {
      _controller.stopListening();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool memorize = widget.mode == EvaluationMode.memorize;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final RecitationSessionController c = _controller;
        final ColorScheme scheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              '${widget.surah.nameAr} • ${memorize ? 'لنحفظ معاً' : 'تلاوة وتصحيح'}',
            ),
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                _AyahNavigator(controller: c),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: <Widget>[
                        if (!c.engineAvailable) const _NoModelBanner(),
                        Text(
                          memorize
                              ? 'الكلمات مخفية: اقرأها من حفظك لتنكشف تلقائياً.'
                              : 'اقرأ الآية بصوتك وستتلوّن الكلمات لحظياً.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        if (kDebugMode || const bool.fromEnvironment('RAFIQ_ENABLE_TELEMETRY')) ...<Widget>[
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: c.toggleTelemetry,
                              icon: Icon(c.showTelemetry ? Icons.monitor_heart : Icons.monitor_heart_outlined),
                              label: Text(c.showTelemetry ? 'إخفاء التشخيص' : 'تشخيص للمطور'),
                            ),
                          ),
                          if (c.showTelemetry)
                            RecitationTelemetryOverlay(
                              backend: c.telemetryBackend,
                              expectedPhonemes: c.telemetryExpectedPhonemes,
                              decodedHypothesis: c.hypothesis,
                              recognizedTokens: c.latestTokens,
                              tokenTimestamps: c.latestTokenTimestamps,
                              evidenceStatus: c.telemetryEvidenceStatus,
                              sequenceNumber: c.lastEngineSequence,
                              wordIndex: c.currentWordIndex,
                              inferenceMs: c.lastInferenceMs,
                            ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          textDirection: TextDirection.rtl,
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 14,
                          children: <Widget>[
                            for (int i = 0; i < c.targets.length; i++)
                              WordChip(
                                text: c.targets[i].text,
                                status: c.statuses[i],
                                isCurrent: i == c.currentWordIndex && !c.ayahComplete,
                                hidden: memorize &&
                                    (c.statuses[i] == WordStatus.pending ||
                                        c.statuses[i] == WordStatus.incorrect ||
                                        c.statuses[i] == WordStatus.uncertain),
                                showFirstLetter: c.showFirstLetter,
                                shakeToken: c.shakeTokens[i],
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (c.ayahComplete)
                          _InfoCard(
                            icon: Icons.check_circle_rounded,
                            color: AppColors.correct,
                            title: c.surahComplete
                                ? 'أتممت السورة، بارك الله فيك'
                                : 'أحسنت! أتممت الآية',
                            message: '',
                          ),
                        if (c.engineAvailable)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              c.usingLexicon
                                  ? 'يعرض هذا الإصدار رموز Sherpa وتوقيتاتها للمساعدة في التشخيص؛ لا يصدر حكمًا زمنيًا موثوقًا على المد والغنة دون احتمالات إطارية ومعايرة.'
                                  : 'المطابقة تقريبية. لا تتوفر احتمالات إطارية معايرة لقياس المد والغنة أو إصدار حكم تجويدي دقيق.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _BottomPanel(controller: c, memorize: memorize),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AyahNavigator extends StatelessWidget {
  const _AyahNavigator({required this.controller});

  final RecitationSessionController controller;

  @override
  Widget build(BuildContext context) {
    final int total = controller.ayahs.length;
    final int number = controller.currentAyah.number;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            tooltip: 'الآية السابقة',
            onPressed: controller.ayahIndex > 0 ? controller.previousAyah : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          Text(
            'الآية ${toArabicDigits(number)} من ${toArabicDigits(total)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'إعادة الآية',
                onPressed: controller.restartAyah,
                icon: const Icon(Icons.replay_rounded),
              ),
              IconButton(
                tooltip: 'الآية التالية',
                onPressed: controller.ayahIndex < total - 1 ? controller.nextAyah : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.controller, required this.memorize});

  final RecitationSessionController controller;
  final bool memorize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final RecitationSessionController c = controller;

    String heard = c.hypothesis.replaceAll(RegExp(r'\s'), '');
    if (heard.length > 48) {
      heard = heard.substring(heard.length - 48);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LiveWaveform(levels: c.levels, color: scheme.primary),
          const SizedBox(height: 6),
          Text(
            heard.isEmpty ? 'الأصوات المكتشفة ستظهر هنا…' : heard,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          if (c.feedback != null) ...<Widget>[
            const SizedBox(height: 8),
            _FeedbackCard(feedback: c.feedback!),
          ],
          if (c.errorMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            _InfoCard(
              icon: Icons.error_outline_rounded,
              color: AppColors.error,
              title: 'تنبيه',
              message: c.errorMessage!,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: c.busy ? null : c.toggleListening,
                  icon: Icon(c.listening ? Icons.stop_rounded : Icons.mic_rounded),
                  label: Text(c.listening ? 'إيقاف' : 'ابدأ الاستماع'),
                ),
              ),
              if (memorize) ...<Widget>[
                const SizedBox(width: 10),
                FilterChip(
                  label: const Text('أول حرف'),
                  selected: c.showFirstLetter,
                  onSelected: (bool _) => c.toggleFirstLetter(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'التصحيح الآلي قد يخطئ، ولا يغني عن معلّم متقن. أحكام التجويد الدقيقة تحتاج معايرة صوتية متخصصة.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback});

  final TajweedFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final bool isError = feedback.verdict == WordVerdict.incorrect;
    final bool isUncertain = feedback.verdict == WordVerdict.uncertain;
    return _InfoCard(
      icon: isError ? Icons.close_rounded : (isUncertain ? Icons.help_outline_rounded : Icons.tips_and_updates_rounded),
      color: isError ? AppColors.error : AppColors.warning,
      title: '${feedback.title} — ${feedback.wordText}',
      message: feedback.message,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: scheme.onSurface,
                  ),
                ),
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      message,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoModelBanner extends StatelessWidget {
  const _NoModelBanner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: _InfoCard(
        icon: Icons.mic_off_rounded,
        color: AppColors.warning,
        title: 'التصحيح الصوتي غير متاح',
        message:
            'النموذج الصوتي غير مضمّن في هذا الإصدار. يمكنك تصفح المصحف والإحصائيات فقط.',
      ),
    );
  }
}
