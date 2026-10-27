import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as pth;

import 'model_loader_service.dart';
import 'phoneme_lexicon_service.dart';
import 'sherpa_tajweed_engine.dart';

final engineProvider = Provider<SherpaTajweedEngine>((ref) {
  final SherpaTajweedEngine engine = SherpaTajweedEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final lexiconProvider = Provider<PhonemeLexiconService>((ref) {
  return PhonemeLexiconService();
});

enum PrepStage { idle, working, ready, modelMissing, failed }

class PrepState {
  const PrepState({
    this.stage = PrepStage.idle,
    this.progress = 0,
    this.message = '',
  });

  final PrepStage stage;
  final double progress;
  final String message;
}

/// Prepares the acoustic model and recognizer. The large model pack is imported
/// once into persistent app storage, then survives normal APK upgrades.
class ModelPrepNotifier extends Notifier<PrepState> {
  bool _started = false;

  @override
  PrepState build() => const PrepState();

  Future<void> prepare({bool force = false}) async {
    if (_started && !force) return;
    _started = true;
    state = const PrepState(
      stage: PrepStage.working,
      progress: 0.02,
      message: 'جارٍ التحقق من النموذج الصوتي المحلي…',
    );

    final ModelLoaderService loader = ModelLoaderService();
    try {
      if (await loader.findInstalled() == null) {
        _started = false;
        state = const PrepState(
          stage: PrepStage.modelMissing,
          progress: 1,
          message:
              'لم تُثبت حزمة النموذج بعد. نزّل حزمة v3.1 من GitHub Actions، وفك ضغطها، ثم اختر ملفاتها الخمسة هنا مرة واحدة.',
        );
        return;
      }

      final ModelPaths paths = await loader.prepare((double p, String msg) {
        state = PrepState(
          stage: PrepStage.working,
          progress: 0.05 + p * 0.15,
          message: msg,
        );
      });
      await _initializeEngine(paths, force: force);
    } catch (e) {
      state = PrepState(
        stage: PrepStage.failed,
        message: 'تعذّر تجهيز المحرك الصوتي: $e',
      );
      _started = false;
    }
  }

  /// Installs a model pack selected with the platform file picker. Only file
  /// paths cross into the loader, so the large ONNX file is copied as a stream
  /// and is never loaded wholesale into Dart memory.
  Future<void> installModelFiles(Map<String, String> selectedPaths) async {
    if (_started) return;
    _started = true;
    state = const PrepState(
      stage: PrepStage.working,
      progress: 0.01,
      message: 'جارٍ تثبيت حزمة النموذج المحلية…',
    );
    final ModelLoaderService loader = ModelLoaderService();
    try {
      await loader.importFiles(
        selectedPaths,
        onProgress: (double progress, String message) {
          state = PrepState(
            stage: PrepStage.working,
            progress: progress * 0.7,
            message: message,
          );
        },
      );
      _started = false;
      await prepare(force: true);
    } catch (e) {
      state = PrepState(
        stage: PrepStage.failed,
        message: 'تعذّر تثبيت حزمة النموذج: $e',
      );
      _started = false;
    }
  }

  Future<void> _initializeEngine(ModelPaths paths, {required bool force}) async {
    state = const PrepState(
      stage: PrepStage.working,
      progress: 0.25,
      message: 'جارٍ تحميل محرك التعرف على التلاوة…',
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final File lock = File(
      pth.join(pth.dirname(paths.modelPath), 'engine_init.lock'),
    );
    if (!force && await lock.exists()) {
      state = const PrepState(
        stage: PrepStage.failed,
        message:
            'توقف التطبيق في المرة السابقة أثناء تحميل المحرك الصوتي. '
            'يمكنك إعادة المحاولة، أو المتابعة بدون التصحيح الصوتي.',
      );
      _started = false;
      return;
    }
    await lock.writeAsString('init', flush: true);
    final SherpaTajweedEngine engine = ref.read(engineProvider);
    try {
      await engine.initialize(
        modelPath: paths.modelPath,
        tokensPath: paths.tokensPath,
        modelVersion: paths.modelVersion,
      );
    } finally {
      if (await lock.exists()) await lock.delete();
    }

    final PhonemeLexiconService lexiconService = ref.read(lexiconProvider);
    await lexiconService.loadTokens(paths.tokensPath, blankId: paths.blankId ?? 250);
    final String? lexiconPath = paths.lexiconPath;
    if (lexiconPath != null) await lexiconService.load(lexiconPath);

    state = const PrepState(
      stage: PrepStage.ready,
      progress: 1,
      message: 'اكتمل التجهيز',
    );
  }
}

final modelPrepProvider =
    NotifierProvider<ModelPrepNotifier, PrepState>(ModelPrepNotifier.new);
